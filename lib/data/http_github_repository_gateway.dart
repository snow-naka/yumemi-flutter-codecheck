import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_failure.dart';
import '../models/repository_models.dart';
import 'github_rate_limit_coordinator.dart';
import 'github_rate_limit_evaluator.dart';
import 'github_rate_limit_guard.dart';
import 'github_rate_limit_headers.dart';
import 'github_rate_limit_policy.dart';
import 'github_repository_gateway.dart';

import 'dart:io' show TlsException;
import 'dart:math' show min;

final class HttpGitHubRepositoryGateway implements GitHubRepositoryGateway {
  HttpGitHubRepositoryGateway({
    required http.Client client,
    required GitHubRateLimitPolicy policy,
    DateTime Function()? now,
    Duration? requestTimeout,
  }) : // client: という公開引数名を維持するため。
       // ignore: prefer_initializing_formals
       _client = client,
       _policy = policy,
       _now = now ?? DateTime.now,
       _guard = GitHubRateLimitGuard(policy),
       _requestTimeout = requestTimeout ?? const Duration(seconds: 10),
       _coordinator = GitHubRateLimitCoordinator(policy);
  final http.Client _client;
  final GitHubRateLimitPolicy _policy;
  final DateTime Function() _now;
  final GitHubRateLimitGuard _guard;
  final GitHubRateLimitCoordinator _coordinator;
  final Duration _requestTimeout;
  Future<void> _requestQueue = Future<void>.value();

  static const _headers = <String, String>{
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2026-03-10',
    'User-Agent': 'yumemi-flutter-codecheck',
  };

  @override
  Future<SearchPage> searchRepositories(
    String query, {
    int page = 1,
    int perPage = 30,
    bool Function()? isCanceled,
  }) async {
    if (query.trim().isEmpty ||
        page < 1 ||
        perPage < 1 ||
        perPage > 100 ||
        (page - 1) * perPage >= 1000) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidRequest,
        safeMessage: '検索条件が不正です。',
      );
    }

    final uri = Uri.https('api.github.com', '/search/repositories', {
      'q': query,
      'page': '$page',
      'per_page': '$perPage',
    });

    final response = await _get(
      uri,
      GitHubApiResource.search,
      isCanceled: isCanceled,
    );

    try {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final totalCount = data['total_count'] as int;
      final incomplete = data['incomplete_results'] as bool;
      final rawItems = data['items'] as List<dynamic>;

      final items = rawItems.map((raw) {
        return _parseSummary(raw as Map<String, dynamic>);
      }).toList();

      // GitHub検索APIは最大1,000件まで取得可能。
      final start = (page - 1) * perPage;
      final remainingWithinLimit = 1000 - start;

      // 通常の1ページ上限と、残りの取得可能件数を比較。
      final maxItems = min(perPage, remainingWithinLimit);

      if (items.length > maxItems) {
        throw const FormatException('Search result exceeds GitHub limit');
      }

      final link = response.headers.entries
          .where((e) => e.key.toLowerCase() == 'link')
          .map((e) => e.value)
          .join(',');

      final hasNext = RegExp(
        r'rel\s*=\s*"next"',
        caseSensitive: false,
      ).hasMatch(link);

      final reachedLimit = page * perPage >= 1000;

      return SearchPage(
        items: items,
        totalCount: totalCount,
        incompleteResults: incomplete,
        page: page,
        perPage: perPage,
        navigation: hasNext && !reachedLimit
            ? NextPage(page + 1)
            : PageEnd(
                reachedLimit && totalCount > 1000
                    ? SearchEndReason.githubLimitReached
                    : SearchEndReason.exhausted,
              ),
      );
    } catch (_) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        safeMessage: 'GitHub APIの応答形式が不正です。',
      );
    }
  }

  Future<http.Response> _get(
    Uri uri,
    GitHubApiResource resource, {
    bool Function()? isCanceled,
  }) {
    final caller = Completer<http.Response>();

    _requestQueue = _requestQueue.then((_) async {
      if (isCanceled?.call() ?? false) {
        caller.completeError(const QueuedRequestCanceled());
        return;
      }

      final abort = Completer<void>();

      final inFlight = _getOnce(uri, resource, abort.future);

      // 呼び出し元へのタイムアウト通知。
      unawaited(
        inFlight
            .timeout(
              _requestTimeout,
              onTimeout: () {
                // 通信自体の中断も要求する。
                if (!abort.isCompleted) {
                  abort.complete();
                }

                throw const ApiFailure(
                  kind: ApiFailureKind.timeout,
                  safeMessage: '通信がタイムアウトしました。',
                );
              },
            )
            .then<void>(
              (response) {
                caller.complete(response);
              },
              onError: (Object error, StackTrace stackTrace) {
                caller.completeError(error, stackTrace);
              },
            ),
      );

      // 中断要求を出しただけでは次へ進まない。
      // 実際のHTTP処理が終了するまで待つ。
      try {
        await inFlight;
      } catch (_) {
        // エラーは呼び出し元への通知経路で処理する。
        // キューは次の要求へ進める。
      }
    });

    return caller.future;
  }

  Future<http.Response> _getOnce(
    Uri uri,
    GitHubApiResource resource,
    Future<void> abortTrigger,
  ) async {
    _guard.check(resource, _now().toUtc());

    late final http.Response response;

    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abortTrigger,
      );

      request.headers.addAll(_headers);

      final streamedResponse = await _client.send(request);

      // 本文の受信完了を待たず、ヘッダーを先に観測する。
      final headerReceivedAt = _now().toUtc();
      final receivedHeaders = GitHubRateLimitHeaders.parse(
        streamedResponse.headers,
      );
      _coordinator.observeRetryAfter(
        statusCode: streamedResponse.statusCode,
        headers: receivedHeaders,
        requestedResource: resource,
        now: headerReceivedAt,
      );

      if (streamedResponse.statusCode == 200) {
        _coordinator.observeSuccessfulResponse(
          statusCode: streamedResponse.statusCode,
          headers: receivedHeaders,
          requestedResource: resource,
          now: headerReceivedAt,
        );
      } else if (streamedResponse.statusCode == 403 ||
          streamedResponse.statusCode == 429) {
        // 本文なしで判定できるPrimary制限や429を先に記録。
        final earlyDecision = GitHubRateLimitEvaluator.evaluate(
          statusCode: streamedResponse.statusCode,
          headers: receivedHeaders,
          now: headerReceivedAt,
        );

        if (earlyDecision.isRateLimited) {
          _coordinator.apply(
            decision: earlyDecision,
            requestedResource: resource,
            now: headerReceivedAt,
          );
        }
      }

      // ここで本文を読む。中断しても観測済みの制限は残る。
      response = await http.Response.fromStream(streamedResponse);
    } on http.RequestAbortedException {
      rethrow;
    } on TlsException {
      throw const ApiFailure(
        kind: ApiFailureKind.network,
        safeMessage: 'GitHubとの通信に失敗しました。',
      );
    } on http.ClientException {
      throw const ApiFailure(
        kind: ApiFailureKind.network,
        safeMessage: 'GitHubとの通信に失敗しました。',
      );
    }

    final observedAt = _now().toUtc();
    final rateHeaders = GitHubRateLimitHeaders.parse(response.headers);

    if (response.statusCode == 200) {
      _coordinator.recordSuccessfulResponse();
    }
    if (response.statusCode != 200) {
      final decision = GitHubRateLimitEvaluator.evaluate(
        statusCode: response.statusCode,
        headers: rateHeaders,
        now: observedAt,
        secondaryLimitIndicated: _secondaryLimitIndicated(response),
      );

      _coordinator.apply(
        decision: decision,
        requestedResource: resource,
        now: observedAt,
      );
      _coordinator.recordCompletedRateLimit(
        decision: decision,
        now: observedAt,
      );

      if (decision.isRateLimited) {
        throw ApiFailure(
          kind: ApiFailureKind.rateLimited,
          safeMessage: 'GitHub APIの利用制限中です。',
          httpStatus: response.statusCode,
          retryAt: _policy.retryAt(resource, observedAt),
        );
      }

      throw ApiFailure(
        kind: switch (response.statusCode) {
          401 || 403 => ApiFailureKind.accessDenied,
          404 => ApiFailureKind.notFoundOrUnavailable,
          422 => ApiFailureKind.invalidRequest,
          >= 500 => ApiFailureKind.serverError,
          _ => ApiFailureKind.otherHttp,
        },
        safeMessage: 'GitHub APIからエラーが返されました。',
        httpStatus: response.statusCode,
      );
    }

    return response;
  }

  static bool _secondaryLimitIndicated(http.Response response) {
    try {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final message = data['message'];

      if (message is! String) return false;

      final lower = message.toLowerCase();

      return lower.contains('secondary rate limit') ||
          lower.contains('abuse detection');
    } catch (_) {
      return false;
    }
  }

  static RepositorySummary _parseSummary(Map<String, dynamic> item) {
    final owner = item['owner'] as Map<String, dynamic>;

    final id = item['id'] as int;
    final ownerLogin = owner['login'] as String;
    final name = item['name'] as String;
    final avatarUrl = owner['avatar_url'] as String;
    final language = item['language'] as String?;

    final starCount = item['stargazers_count'] as int;
    final forkCount = item['forks_count'] as int;
    final issueCount = item['open_issues_count'] as int;

    // 検索と詳細取得で共通の値検証を行う。
    if (id <= 0 ||
        ownerLogin.trim().isEmpty ||
        name.trim().isEmpty ||
        starCount < 0 ||
        forkCount < 0 ||
        issueCount < 0) {
      throw const FormatException('Invalid repository summary values');
    }

    return RepositorySummary(
      key: RepositoryKey(id: id, owner: ownerLogin, name: name),
      avatarUrl: avatarUrl,
      language: language,
      starCount: starCount,
      forkCount: forkCount,
      openIssueAndPullRequestCount: issueCount,
    );
  }

  @override
  Future<RepositoryDetail> getRepository(RepositoryKey key) async {
    if (key.id <= 0 || key.owner.trim().isEmpty || key.name.trim().isEmpty) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidRequest,
        safeMessage: 'リポジトリの指定が不正です。',
      );
    }

    final uri = Uri(
      scheme: 'https',
      host: 'api.github.com',
      pathSegments: ['repos', key.owner, key.name],
    );

    final response = await _get(uri, GitHubApiResource.core);

    try {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final summary = _parseSummary(data);
      final watcherCount = data['subscribers_count'] as int;

      // 検索時と異なるリポジトリを表示しない。
      if (summary.key.id != key.id || watcherCount < 0) {
        throw const FormatException('Repository detail validation failed');
      }

      return RepositoryDetail(summary: summary, watcherCount: watcherCount);
    } catch (_) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        safeMessage: 'GitHub APIの応答形式が不正です。',
      );
    }
  }
}
