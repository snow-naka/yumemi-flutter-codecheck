import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';
import 'package:yumemi_app/data/http_github_repository_gateway.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/data/github_repository_gateway.dart';
import 'package:yumemi_app/devtools/api_diagnostics.dart';

import 'dart:io' show CertificateException, HandshakeException, sleep;

void main() {
  final now = DateTime.utc(2026, 11, 21, 12);

  Map<String, dynamic> payload() => {
    'total_count': 100,
    'incomplete_results': false,
    'items': [
      {
        'id': 123,
        'name': 'example',
        'owner': {
          'login': 'sample',
          'avatar_url': 'https://example.com/avatar.png',
        },
        'language': 'Dart',
        'stargazers_count': 42,
        'forks_count': 7,
        'open_issues_count': 3,
      },
    ],
  };

  test('HG01: 検索要求とJSON変換・次ページ判定', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/search/repositories');
      expect(request.url.queryParameters['q'], 'flutter riverpod');
      expect(request.url.queryParameters['page'], '1');
      expect(request.url.queryParameters['per_page'], '30');

      expect(request.headers['X-GitHub-Api-Version'], '2026-03-10');

      return http.Response(
        jsonEncode(payload()),
        200,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'link':
              '<https://api.github.com/search/repositories?page=2>; rel="next"',
        },
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    final result = await gateway.searchRepositories('flutter riverpod');

    expect(result.totalCount, 100);
    expect(result.items.single.fullName, 'sample/example');
    expect(result.items.single.starCount, 42);
    expect(result.items.single.forkCount, 7);
    expect(result.navigation, isA<NextPage>().having((n) => n.page, 'page', 2));
  });

  test('HG02: Primary制限後はHTTP通信を送らない', () async {
    var requestCount = 0;

    final reset = now.add(const Duration(minutes: 2));

    final client = MockClient((request) async {
      requestCount++;

      return http.Response(
        '{"message":"API rate limit exceeded"}',
        403,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
        },
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    for (var i = 0; i < 2; i++) {
      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );
    }

    // 2回呼んでも、HTTP要求は最初の1回だけ。
    expect(requestCount, 1);
  });

  test('HG03: 不正なJSONはinvalidResponse', () async {
    final client = MockClient(
      (request) async => http.Response('{"total_count":"invalid"}', 200),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('HG04: HTTPステータスを適切なエラーに分類', () async {
    final cases = <(int, ApiFailureKind)>[
      (401, ApiFailureKind.accessDenied),
      (403, ApiFailureKind.accessDenied),
      (404, ApiFailureKind.notFoundOrUnavailable),
      (422, ApiFailureKind.invalidRequest),
      (503, ApiFailureKind.serverError),
    ];

    for (final (status, expectedKind) in cases) {
      final client = MockClient(
        (_) async => http.Response('{"message":"error"}', status),
      );

      final gateway = HttpGitHubRepositoryGateway(
        client: client,
        policy: GitHubRateLimitPolicy(),
        now: () => now,
      );

      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.kind, 'kind ($status)', expectedKind)
              .having((e) => e.httpStatus, 'httpStatus', status)
              .having((e) => e.reason, 'reason', isNull),
        ),
      );

      client.close();
    }
  });

  test('HG05: 429応答後は次のHTTP要求を送らない', () async {
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;
      return http.Response('{"message":"Too many requests"}', 429);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => now,
    );

    for (var i = 0; i < 2; i++) {
      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );
    }

    expect(requestCount, 1);
    expect(
      policy.retryAt(GitHubApiResource.search, now),
      now.add(const Duration(minutes: 1)),
    );
    expect(policy.canRequest(GitHubApiResource.core, now), isFalse);

    client.close();
  });

  test('HG06: 正常応答の残数0でも次の送信を停止', () async {
    var requestCount = 0;
    final reset = now.add(const Duration(minutes: 2));

    final client = MockClient((_) async {
      requestCount++;

      return http.Response(
        jsonEncode(payload()),
        200,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
        },
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    // 残数0でも、この成功応答の結果は利用できる。
    final result = await gateway.searchRepositories('flutter');
    expect(result.items.single.fullName, 'sample/example');

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(isA<ApiFailure>().having((e) => e.retryAt, 'retryAt', reset)),
    );

    expect(requestCount, 1);
    client.close();
  });

  test('HG07: 1000件境界ではgithubLimitReached', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final data = {
      ...payload(),
      'total_count': 1500,
      // 30件刻みの34ページ目は最大10件。
      'items': List.generate(10, (i) => {...seed, 'id': i + 1}),
    };

    final client = MockClient(
      (_) async =>
          http.Response(
            jsonEncode(data),
            200,
            headers: {
              // 次ページが案内されても1000件上限を優先。
              'link': '<https://api.github.com/search/repositories?page=35>; rel="next"',
            },
          ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    final result = await gateway.searchRepositories(
      'flutter',
      page: 34,
      perPage: 30,
    );

    expect(result.items.length, 10);
    expect(
      result.navigation,
      isA<PageEnd>().having(
        (e) => e.reason,
        'reason',
        SearchEndReason.githubLimitReached,
      ),
    );

    client.close();
  });

  test('HG08: 1000件を超えるページはHTTP送信前に拒否', () async {
    var requestCount = 0;

    final client = MockClient((_) async {
      requestCount++;
      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    await expectLater(
      gateway.searchRepositories('flutter', page: 35, perPage: 30),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.invalidRequest)
            .having(
              (e) => e.reason,
              'reason',
              ApiFailureReason.invalidSearchCondition,
            ),
      ),
    );

    expect(requestCount, 0);
    client.close();
  });

  test('ER02: 不正なリポジトリ指定ではHTTP送信せず原因を設定する', () async {
    var requestCount = 0;

    final client = MockClient((_) async {
      requestCount++;
      throw StateError('HTTP request must not be sent');
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    await expectLater(
      gateway.getRepository(
        const RepositoryKey(id: 0, owner: 'sample', name: 'example'),
      ),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.invalidRequest)
            .having(
              (e) => e.reason,
              'reason',
              ApiFailureReason.invalidRepositoryKey,
            )
            .having((e) => e.httpStatus, 'httpStatus', isNull),
      ),
    );

    expect(requestCount, 0);
  });

  test('HG09: incomplete_resultsを保持する', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({...payload(), 'incomplete_results': true}),
        200,
      ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    final result = await gateway.searchRepositories('flutter');

    expect(result.incompleteResults, isTrue);
    expect(result.items.length, 1);

    client.close();
  });

  test('HG10: ClientExceptionをnetworkに分類', () async {
    final client = MockClient((request) async {
      throw http.ClientException('Simulated connection failure', request.url);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.network),
      ),
    );

    client.close();
  });

  test('HG11: 応答がない場合はtimeoutに分類', () async {
    final pending = Completer<http.Response>();

    final client = MockClient((_) => pending.future);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      requestTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.timeout),
      ),
    );

    // テスト用の未完了Futureを終了させる。
    pending.complete(http.Response('{}', 200));
    client.close();
  });

  test('HG12: 必須項目の欠落・型不正はinvalidResponse', () async {
    final withoutItems = payload()..remove('items');

    final cases = <(String, Map<String, dynamic>)>[
      ('items欠落', withoutItems),
      ('total_count型不正', {...payload(), 'total_count': '100'}),
      ('incomplete_results型不正', {...payload(), 'incomplete_results': 'false'}),
      (
        'ownerがnull',
        {
          ...payload(),
          'items': [
            {
              ...((payload()['items'] as List<dynamic>).single
                  as Map<String, dynamic>),
              'owner': null,
            },
          ],
        },
      ),
    ];

    for (final (label, body) in cases) {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(body), 200),
      );

      final gateway = HttpGitHubRepositoryGateway(
        client: client,
        policy: GitHubRateLimitPolicy(),
        now: () => now,
      );

      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
        reason: label,
      );

      client.close();
    }
  });

  test('HG13: 要求件数を超えるitemsはinvalidResponse', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          ...payload(),
          'items': [
            seed,
            {...seed, 'id': 456},
          ],
        }),
        200,
      ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    await expectLater(
      gateway.searchRepositories('flutter', perPage: 1),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );

    client.close();
  });

  test('HG14: Linkにnextがなければ追加読み込み終了', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({...payload(), 'total_count': 61}),
        200,
        headers: {
          'link':
              '<https://api.github.com/search/repositories?page=2>; rel="prev", '
              '<https://api.github.com/search/repositories?page=1>; rel="first"',
        },
      ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    final result = await gateway.searchRepositories(
      'flutter',
      page: 3,
      perPage: 30,
    );

    expect(result.page, 3);
    expect(
      result.navigation,
      isA<PageEnd>().having(
        (e) => e.reason,
        'reason',
        SearchEndReason.exhausted,
      ),
    );

    client.close();
  });

  test('HG15: perPage100でも1000件上限を守る', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          ...payload(),
          'total_count': 1500,
          'items': List.generate(100, (i) => {...seed, 'id': i + 1}),
        }),
        200,
        headers: {
          'link': '<https://api.github.com/search/repositories?page=11>; rel="next"',
        },
      ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    // 9ページ目はまだ1,000件未満。
    final beforeLimit = await gateway.searchRepositories(
      'flutter',
      page: 9,
      perPage: 100,
    );

    expect(
      beforeLimit.navigation,
      isA<NextPage>().having((e) => e.page, 'page', 10),
    );

    // 10ページ目で1,000件に到達。
    final atLimit = await gateway.searchRepositories(
      'flutter',
      page: 10,
      perPage: 100,
    );

    expect(
      atLimit.navigation,
      isA<PageEnd>().having(
        (e) => e.reason,
        'reason',
        SearchEndReason.githubLimitReached,
      ),
    );

    client.close();
  });

  test('HG16: 詳細APIからWatcher数を取得する', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/repos/sample/example');
      expect(request.headers['X-GitHub-Api-Version'], '2026-03-10');

      return http.Response(
        jsonEncode({...seed, 'watchers_count': 999, 'subscribers_count': 17}),
        200,
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    final result = await gateway.getRepository(
      const RepositoryKey(id: 123, owner: 'sample', name: 'example'),
    );

    expect(result.summary.fullName, 'sample/example');
    expect(result.summary.starCount, 42);
    expect(result.watcherCount, 17);

    client.close();
  });

  test('HG17: 詳細取得の404はnotFoundOrUnavailable', () async {
    final client = MockClient(
      (_) async => http.Response('{"message":"Not Found"}', 404),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    await expectLater(
      gateway.getRepository(
        const RepositoryKey(id: 123, owner: 'sample', name: 'example'),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.notFoundOrUnavailable,
        ),
      ),
    );

    client.close();
  });

  test('HG18: 詳細データの不正やID不一致を拒否', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final cases = [
      {...seed, 'subscribers_count': 'invalid'},
      {...seed, 'subscribers_count': 17, 'id': 999},
    ];

    for (final data in cases) {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(data), 200),
      );

      final gateway = HttpGitHubRepositoryGateway(
        client: client,
        policy: GitHubRateLimitPolicy(),
        now: () => now,
      );

      await expectLater(
        gateway.getRepository(
          const RepositoryKey(id: 123, owner: 'sample', name: 'example'),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );

      client.close();
    }
  });

  test('HG19: 詳細のPrimary制限は検索に影響しない', () async {
    var requestCount = 0;
    final reset = now.add(const Duration(minutes: 2));

    final client = MockClient((request) async {
      requestCount++;

      if (request.url.path.startsWith('/repos/')) {
        return http.Response(
          '{"message":"API rate limit exceeded"}',
          403,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          },
        );
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    const key = RepositoryKey(id: 123, owner: 'sample', name: 'example');

    for (var i = 0; i < 2; i++) {
      await expectLater(
        gateway.getRepository(key),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );
    }

    final searchResult = await gateway.searchRepositories('flutter');

    expect(searchResult.items.length, 1);

    // 詳細1回＋検索1回。詳細の2回目は送信されない。
    expect(requestCount, 2);

    client.close();
  });

  test('HG20: 同時要求でも先行応答のレート制限を守る', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    var requestCount = 0;
    final reset = now.add(const Duration(minutes: 2));

    final client = MockClient((_) {
      requestCount++;

      if (requestCount == 1) {
        firstStarted.complete();
        return firstResponse.future;
      }

      return Future.value(http.Response(jsonEncode(payload()), 200));
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    final first = gateway.searchRepositories('flutter');
    await firstStarted.future;

    final second = gateway.searchRepositories('dart');

    // 先行要求が完了するまで、2件目は送信しない。
    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);

    final secondAssertion = expectLater(
      second,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    firstResponse.complete(
      http.Response(
        jsonEncode(payload()),
        200,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
        },
      ),
    );

    // 先行要求の成功結果はそのまま使える。
    final result = await first;
    expect(result.items.length, 1);

    // 後続要求はHTTP送信前に拒否される。
    await secondAssertion;
    expect(requestCount, 1);

    client.close();
  });

  test('HG21: 先行要求が失敗しても後続要求は処理する', () async {
    var requestCount = 0;

    final client = MockClient((_) async {
      requestCount++;

      if (requestCount == 1) {
        return http.Response('{"message":"Server error"}', 503);
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    final first = gateway.searchRepositories('flutter');
    final second = gateway.searchRepositories('dart');

    await expectLater(
      first,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.serverError,
        ),
      ),
    );

    final result = await second;

    expect(result.items.length, 1);
    expect(requestCount, 2);

    client.close();
  });

  test('HG22: Secondary制限後は詳細取得も送信しない', () async {
    var requestCount = 0;

    final client = MockClient((_) async {
      requestCount++;
      return http.Response(
        '{"message":"You have exceeded a secondary rate limit"}',
        403,
        headers: {'retry-after': '60'},
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    await expectLater(
      gateway.getRepository(
        const RepositoryKey(id: 123, owner: 'sample', name: 'example'),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    // 詳細取得は実際には送信されていない。
    expect(requestCount, 1);

    client.close();
  });

  test('HG23: タイムアウト後も未終了のGETを追い越さない', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    var requestCount = 0;

    final client = MockClient((_) {
      requestCount++;

      if (requestCount == 1) {
        firstStarted.complete();
        return firstResponse.future;
      }

      return Future.value(http.Response(jsonEncode(payload()), 200));
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      requestTimeout: const Duration(milliseconds: 50),
    );

    final first = gateway.searchRepositories('flutter');
    await firstStarted.future;

    final second = gateway.searchRepositories('dart');

    // 後続Futureの成功・失敗を捕捉しておく。
    final secondOutcome = second.then<Object>(
      (result) => result,
      onError: (Object error, StackTrace stack) => error,
    );

    try {
      await expectLater(
        first,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );

      // タイムアウト後のキュー処理を進める。
      await Future<void>.delayed(Duration.zero);

      // 最初の通信は、まだ終了していない。
      // この時点で2件目を送信してはいけない。
      expect(requestCount, 1, reason: '先行GETの終了・中断確認前に次のGETを開始した');
    } finally {
      // 失敗時にも通信を終了させ、テストを後始末する。
      if (!firstResponse.isCompleted) {
        firstResponse.complete(http.Response(jsonEncode(payload()), 200));
      }

      await secondOutcome;
      client.close();
    }
  });

  test('HG24: タイムアウト後に届いた429を後続要求へ反映', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    var requestCount = 0;

    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) {
      requestCount++;

      if (requestCount == 1) {
        firstStarted.complete();
        return firstResponse.future;
      }

      return Future.value(http.Response(jsonEncode(payload()), 200));
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => now,
      requestTimeout: const Duration(milliseconds: 50),
    );

    try {
      // Aを送信し、応答を保留する。
      final first = gateway.searchRepositories('flutter');
      await firstStarted.future;

      // Aが通信中の間にBをキューへ追加。
      final second = gateway.searchRepositories('dart');

      // Aは通信タイムアウト。
      await expectLater(
        first,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );

      // Bもキュー待機中に自分の期限を迎える。
      await expectLater(
        second,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );

      // この時点でHTTP送信はAの1回だけ。
      expect(requestCount, 1);

      // Aの通信が遅れて429を返す。
      firstResponse.complete(
        http.Response(
          '{"message":"Too many requests"}',
          429,
          headers: {'retry-after': '120'},
        ),
      );

      // 新しいCを要求。
      // Aの429を反映して、HTTP送信前に拒否される。
      await expectLater(
        gateway.searchRepositories('riverpod'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );

      expect(
        policy.retryAt(GitHubApiResource.search, now),
        now.add(const Duration(seconds: 120)),
      );

      // BもCも実際にはHTTP送信されていない。
      expect(requestCount, 1);
    } finally {
      if (!firstResponse.isCompleted) {
        firstResponse.complete(http.Response(jsonEncode(payload()), 200));
      }

      client.close();
    }
  });

  test('HG25: 中断成功後にキューが復帰する', () async {
    final firstStarted = Completer<void>();
    final abortObserved = Completer<void>();
    final allowAbortCompletion = Completer<void>();
    final sentQueries = <String>[];

    final client = MockClient.streaming((request, bodyStream) async {
      final query = request.url.queryParameters['q']!;
      sentQueries.add(query);

      if (query == 'flutter') {
        final abortable = request as http.AbortableRequest;

        firstStarted.complete();

        // Aがタイムアウトし、中断要求を受けるまで待つ。
        await abortable.abortTrigger!;
        abortObserved.complete();

        // 中断処理がまだ完了していない状態を維持する。
        await allowAbortCompletion.future;

        throw http.RequestAbortedException(request.url);
      }

      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload()))),
        200,
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      requestTimeout: const Duration(milliseconds: 500),
    );

    try {
      // Aを送信する。
      final first = gateway.searchRepositories('flutter');

      // タイムアウトを早めに捕捉する。
      final firstAssertion = expectLater(
        first,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );

      await firstStarted.future.timeout(const Duration(seconds: 2));

      // Aがタイムアウトしたことを確認。
      await firstAssertion;

      // HTTPクライアントが中断要求を受け取った。
      await abortObserved.future.timeout(const Duration(seconds: 2));

      // Aの中断処理はまだ完了させない。
      // ここでBをキューへ追加する。
      final second = gateway.searchRepositories('dart');

      final secondOutcome = second.then<Object>(
        (result) => result,
        onError: (Object error, StackTrace stack) => error,
      );

      await Future<void>.delayed(Duration.zero);

      // Aの中断完了前にBを送信してはいけない。
      expect(sentQueries, ['flutter']);

      // Aの中断を完了させ、キューを進める。
      allowAbortCompletion.complete();

      final result = await secondOutcome.timeout(const Duration(seconds: 2));

      expect(result, isA<SearchPage>());
      expect((result as SearchPage).items.single.fullName, 'sample/example');

      // 中断確認後、Bが正常に送信された。
      expect(sentQueries, ['flutter', 'dart']);
    } finally {
      if (!allowAbortCompletion.isCompleted) {
        allowAbortCompletion.complete();
      }

      client.close();
    }
  });

  test('HG26: ヘッダー受信後のタイムアウトでも429を保持', () async {
    final firstStarted = Completer<void>();
    final abortObserved = Completer<void>();
    var requestCount = 0;

    final policy = GitHubRateLimitPolicy();

    final client = MockClient.streaming((request, bodyStream) async {
      requestCount++;

      final abortable = request as http.AbortableRequest;

      // 429ヘッダーは返すが、本文は中断まで完了しない。
      Stream<List<int>> pendingBody() async* {
        await abortable.abortTrigger!;
        abortObserved.complete();

        throw http.RequestAbortedException(request.url);
      }

      firstStarted.complete();

      return http.StreamedResponse(
        pendingBody(),
        429,
        headers: {'retry-after': '120'},
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => now,
      requestTimeout: const Duration(milliseconds: 50),
    );

    try {
      final first = gateway.searchRepositories('flutter');

      await firstStarted.future.timeout(const Duration(seconds: 2));

      // 呼び出し元にはタイムアウトを通知する。
      await expectLater(
        first,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );

      // 本文の中断を確認する。
      await abortObserved.future.timeout(const Duration(seconds: 2));

      // 本文が完了していなくても、
      // 受信済み429ヘッダーの制限は保持される。
      expect(
        policy.retryAt(GitHubApiResource.search, now),
        now.add(const Duration(seconds: 120)),
      );

      expect(policy.canRequest(GitHubApiResource.search, now), isFalse);

      expect(requestCount, 1);
    } finally {
      client.close();
    }
  });

  test('HG27: Reset欠落でもRetry-After 7200秒を守る', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;

      if (requestCount == 1) {
        return http.Response(
          '{"message":"API rate limit exceeded"}',
          429,
          headers: {'x-ratelimit-remaining': '0', 'retry-after': '7200'},
        );
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    final deadline = now.add(const Duration(hours: 2));

    expect(policy.retryAt(GitHubApiResource.search, now), deadline);

    // 119分後はまだ送信禁止。
    current = now.add(const Duration(minutes: 119));

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(isA<ApiFailure>()),
    );

    expect(requestCount, 1);

    // 120分経過したら送信可能。
    current = deadline;

    final result = await gateway.searchRepositories('flutter');

    expect(result.items.length, 1);
    expect(requestCount, 2);

    client.close();
  });

  test('HG28: 通常403でもRetry-Afterの待機指示を守る', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;

      if (requestCount == 1) {
        return http.Response(
          '{"message":"Forbidden"}',
          403,
          headers: {'x-ratelimit-remaining': '7', 'retry-after': '120'},
        );
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    // エラー分類はaccessDeniedのまま。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.accessDenied,
        ),
      ),
    );

    final deadline = now.add(const Duration(seconds: 120));

    expect(policy.retryAt(GitHubApiResource.search, now), deadline);

    current = now.add(const Duration(seconds: 119));

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    expect(requestCount, 1);

    current = deadline;

    final result = await gateway.searchRepositories('flutter');

    expect(result.items.length, 1);
    expect(requestCount, 2);

    client.close();
  });

  test('HG29: 待機指示のない通常403は次の送信を妨げない', () async {
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;

      if (requestCount == 1) {
        return http.Response(
          '{"message":"Forbidden"}',
          403,
          headers: {'x-ratelimit-remaining': '7'},
        );
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => now,
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.accessDenied,
        ),
      ),
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isTrue);
    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);

    final result = await gateway.searchRepositories('dart');

    expect(result.items.length, 1);
    expect(requestCount, 2);

    client.close();
  });

  test('HG30: ResetとRetry-Afterでは遅い期限を優先', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final reset = now.add(const Duration(minutes: 1));
    final retryAt = now.add(const Duration(minutes: 3));

    final client = MockClient((_) async {
      requestCount++;

      if (requestCount == 1) {
        return http.Response(
          '{"message":"API rate limit exceeded"}',
          403,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
            'retry-after': '180',
          },
        );
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(isA<ApiFailure>()),
    );

    expect(policy.retryAt(GitHubApiResource.search, now), retryAt);

    current = retryAt.subtract(const Duration(milliseconds: 1));

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(isA<ApiFailure>()),
    );

    expect(requestCount, 1);

    current = retryAt;

    final result = await gateway.searchRepositories('flutter');

    expect(result.items.length, 1);
    expect(requestCount, 2);

    client.close();
  });

  test('HG31: Secondary制限の連続発生で待機を延長する', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;

      return http.Response(
        '{"message":"You have exceeded a secondary rate limit"}',
        403,
        headers: {'x-ratelimit-remaining': '7'},
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    // 1回目：60秒停止。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    final firstDeadline = now.add(const Duration(seconds: 60));

    expect(policy.retryAt(GitHubApiResource.search, now), firstDeadline);

    // 60秒後に利用者が再要求する。
    current = firstDeadline;

    // 2回目：Secondary制限が再発。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    // 次は120秒待つ。
    expect(
      policy.retryAt(GitHubApiResource.search, current),
      current.add(const Duration(seconds: 120)),
    );

    expect(requestCount, 2);
    client.close();
  });

  test('HG32: 429のヘッダーと本文で制限を二重計上しない', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;

      return http.Response('{"message":"Too many requests"}', 429);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    // 1回の429応答で60秒停止。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    final firstDeadline = now.add(const Duration(seconds: 60));

    expect(policy.retryAt(GitHubApiResource.search, now), firstDeadline);

    current = firstDeadline;

    // 2回目の429応答で120秒停止。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    expect(
      policy.retryAt(GitHubApiResource.search, current),
      current.add(const Duration(seconds: 120)),
    );

    expect(requestCount, 2);
    client.close();
  });

  test('HG33: 正常応答でSecondary制限の連続回数をリセット', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;

      // 1回目と3回目はSecondary制限。
      if (requestCount == 1 || requestCount == 3) {
        return http.Response(
          '{"message":"You have exceeded a secondary rate limit"}',
          403,
          headers: {'x-ratelimit-remaining': '7'},
        );
      }

      // 2回目は正常応答。
      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    // 1回目：60秒の制限。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    final firstDeadline = now.add(const Duration(seconds: 60));

    expect(policy.retryAt(GitHubApiResource.search, now), firstDeadline);

    // 制限解除後、正常に検索できる。
    current = firstDeadline;

    final result = await gateway.searchRepositories('flutter');
    expect(result.items.length, 1);

    // 再びSecondary制限が発生。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    // 正常応答で回数がリセットされたので、
    // 120秒ではなく初回の60秒になる。
    expect(
      policy.retryAt(GitHubApiResource.search, current),
      current.add(const Duration(seconds: 60)),
    );

    expect(requestCount, 3);
    client.close();
  });

  test('HG34: 連続制限でもサーバー指定の長い待機期限を保持', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((_) async {
      requestCount++;

      if (requestCount == 1) {
        return http.Response(
          '{"message":"You have exceeded a secondary rate limit"}',
          403,
          headers: {'x-ratelimit-remaining': '7'},
        );
      }

      if (requestCount == 2) {
        return http.Response(
          '{"message":"You have exceeded a secondary rate limit"}',
          403,
          headers: {'x-ratelimit-remaining': '7', 'retry-after': '7200'},
        );
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    // 1回目：60秒待機。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(isA<ApiFailure>()),
    );

    current = now.add(const Duration(seconds: 60));

    // 2回目：サーバーが7200秒の待機を指定。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    final serverDeadline = current.add(const Duration(seconds: 7200));

    expect(policy.retryAt(GitHubApiResource.search, current), serverDeadline);

    // 解除直前は送信できない。
    current = serverDeadline.subtract(const Duration(milliseconds: 1));

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(isA<ApiFailure>()),
    );

    expect(requestCount, 2);

    // 指定時刻に到達したら送信可能。
    current = serverDeadline;

    final result = await gateway.searchRepositories('flutter');

    expect(result.items.length, 1);
    expect(requestCount, 3);

    client.close();
  });

  test('HG35: キュー内でキャンセルされた検索Bを送信しない', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();

    final sentQueries = <String>[];

    final client = MockClient((request) {
      sentQueries.add(request.url.queryParameters['q']!);

      if (sentQueries.length == 1) {
        firstStarted.complete();
        return firstResponse.future;
      }

      return Future.value(http.Response(jsonEncode(payload()), 200));
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    var canceledA = false;
    var canceledB = false;

    // Aを送信する。
    final a = gateway.searchRepositories('alpha', isCanceled: () => canceledA);

    await firstStarted.future;

    // Aは送信済みなので、キャンセルしても通信は継続する。
    canceledA = true;

    // Bをキューに追加し、送信前にキャンセルする。
    final b = gateway.searchRepositories('beta', isCanceled: () => canceledB);

    canceledB = true;

    // 最新の検索Cをキューに追加する。
    final c = gateway.searchRepositories('gamma');

    final bOutcome = b.then<Object>(
      (value) => value,
      onError: (Object error, StackTrace stack) => error,
    );

    try {
      // Aを完了させる。
      firstResponse.complete(http.Response(jsonEncode(payload()), 200));

      await a;

      final canceledResult = await bOutcome;
      final cResult = await c;

      expect(canceledResult, isA<QueuedRequestCanceled>());
      expect(cResult.items.length, 1);

      // AとCのみ送信。Bは送信されない。
      expect(sentQueries, ['alpha', 'gamma']);
    } finally {
      client.close();
    }
  });

  test('HG36: TLSハンドシェイク失敗はnetworkに分類', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      throw const HandshakeException('Simulated TLS handshake failure');
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    try {
      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.kind, 'kind', ApiFailureKind.network)
              .having((e) => e.reason, 'reason', isNull)
              .having((e) => e.toString(), 'toString', 'ApiFailure(network)'),
        ),
      );
    } finally {
      client.close();
    }
  });

  test('HG37: 証明書エラーも安全な通信エラーに分類', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      throw const CertificateException(
        'Simulated certificate verification failure',
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    try {
      await expectLater(
        gateway.getRepository(
          const RepositoryKey(id: 123, owner: 'sample', name: 'example'),
        ),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.kind, 'kind', ApiFailureKind.network)
              .having((e) => e.reason, 'reason', isNull)
              .having((e) => e.toString(), 'toString', 'ApiFailure(network)'),
        ),
      );
    } finally {
      client.close();
    }
  });

  test('HG38: 検索結果の不正な値をinvalidResponseとして拒否', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final owner = seed['owner'] as Map<String, dynamic>;

    final cases = <(String, Map<String, dynamic>)>[
      ('IDが0', {...seed, 'id': 0}),
      ('IDが負数', {...seed, 'id': -1}),
      (
        'ownerが空白',
        {
          ...seed,
          'owner': {...owner, 'login': '  '},
        },
      ),
      ('nameが空白', {...seed, 'name': '  '}),
      ('Star数が負数', {...seed, 'stargazers_count': -3}),
      ('Fork数が負数', {...seed, 'forks_count': -1}),
      ('Issue数が負数', {...seed, 'open_issues_count': -1}),
    ];

    for (final (label, item) in cases) {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            ...payload(),
            'items': [item],
          }),
          200,
        ),
      );

      final gateway = HttpGitHubRepositoryGateway(
        client: client,
        policy: GitHubRateLimitPolicy(),
        now: () => now,
      );

      try {
        await expectLater(
          gateway.searchRepositories('flutter'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              ApiFailureKind.invalidResponse,
            ),
          ),
          reason: label,
        );
      } finally {
        client.close();
      }
    }
  });

  test('HG39: 1000件境界を超えるitemsを拒否', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          ...payload(),
          'total_count': 1500,
          'items': List.generate(11, (i) => {...seed, 'id': i + 1}),
        }),
        200,
      ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    try {
      await expectLater(
        gateway.searchRepositories('flutter', page: 34, perPage: 30),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
    } finally {
      client.close();
    }
  });

  test('HG40: 件数0とlanguage nullは正常な検索結果', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          ...payload(),
          'items': [
            {
              ...seed,
              'language': null,
              'stargazers_count': 0,
              'forks_count': 0,
              'open_issues_count': 0,
            },
          ],
        }),
        200,
      ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    try {
      final result = await gateway.searchRepositories('flutter');
      final repo = result.items.single;

      expect(repo.key.id, 123);
      expect(repo.language, isNull);
      expect(repo.starCount, 0);
      expect(repo.forkCount, 0);
      expect(repo.openIssueAndPullRequestCount, 0);
    } finally {
      client.close();
    }
  });

  test('HG41: 詳細取得でWatcher数0を正常に受理', () async {
    final seed =
        (payload()['items'] as List<dynamic>).single as Map<String, dynamic>;

    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          ...seed,
          'language': null,
          'stargazers_count': 0,
          'forks_count': 0,
          'open_issues_count': 0,
          'subscribers_count': 0,
        }),
        200,
      ),
    );

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
    );

    try {
      final detail = await gateway.getRepository(
        const RepositoryKey(id: 123, owner: 'sample', name: 'example'),
      );

      expect(detail.summary.language, isNull);
      expect(detail.summary.starCount, 0);
      expect(detail.watcherCount, 0);
    } finally {
      client.close();
    }
  });

  test('HG42: Reset経過後の本文完了で停止期間を延長しない', () async {
    var current = now;
    var requestCount = 0;

    final bodyStarted = Completer<void>();
    final releaseBody = Completer<void>();

    final policy = GitHubRateLimitPolicy();
    final reset = now.add(const Duration(seconds: 1));

    final client = MockClient.streaming((request, bodyStream) async {
      requestCount++;

      if (requestCount == 1) {
        // ヘッダーは即座に返すが、本文の完了は保留する。
        Stream<List<int>> delayedBody() async* {
          bodyStarted.complete();
          await releaseBody.future;

          yield utf8.encode('{"message":"API rate limit exceeded"}');
        }

        return http.StreamedResponse(
          delayedBody(),
          403,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          },
        );
      }

      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload()))),
        200,
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    try {
      final first = gateway.searchRepositories('flutter');

      final firstAssertion = expectLater(
        first,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );

      // ヘッダーを受信し、本文の途中で停止。
      await bodyStarted.future.timeout(const Duration(seconds: 2));

      // 本文完了前に、GitHubのReset時刻を経過させる。
      current = now.add(const Duration(seconds: 2));

      releaseBody.complete();
      await firstAssertion;

      // Resetはすでに経過しているため、
      // 新しい60分停止を登録してはいけない。
      expect(
        policy.canRequest(GitHubApiResource.search, current),
        isTrue,
        reason: 'Reset経過後に余分な停止が追加された',
      );

      final result = await gateway.searchRepositories('dart');

      expect(result.items.length, 1);
      expect(requestCount, 2);
    } finally {
      if (!releaseBody.isCompleted) {
        releaseBody.complete();
      }

      client.close();
    }
  });

  test('HG43: 本文受信が遅れてもRetry-Afterを延長しない', () async {
    var current = now;
    var requestCount = 0;

    final bodyStarted = Completer<void>();
    final releaseBody = Completer<void>();
    final policy = GitHubRateLimitPolicy();

    final client = MockClient.streaming((request, bodyStream) async {
      requestCount++;

      if (requestCount == 1) {
        Stream<List<int>> delayedBody() async* {
          bodyStarted.complete();
          await releaseBody.future;
          yield utf8.encode('{"message":"Too many requests"}');
        }

        return http.StreamedResponse(
          delayedBody(),
          429,
          headers: {'retry-after': '5'},
        );
      }

      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload()))),
        200,
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    try {
      final first = gateway.searchRepositories('flutter');

      final firstAssertion = expectLater(
        first,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );

      await bodyStarted.future.timeout(const Duration(seconds: 2));

      // ヘッダー受信から2秒経過したことにする。
      current = now.add(const Duration(seconds: 2));

      releaseBody.complete();
      await firstAssertion;

      // T+2秒から5秒ではなく、Tから5秒が期限。
      final deadline = now.add(const Duration(seconds: 5));

      expect(policy.retryAt(GitHubApiResource.search, current), deadline);

      current = deadline.subtract(const Duration(milliseconds: 1));

      await expectLater(
        gateway.searchRepositories('dart'),
        throwsA(isA<ApiFailure>()),
      );

      expect(requestCount, 1);

      current = deadline;

      final result = await gateway.searchRepositories('dart');

      expect(result.items.length, 1);
      expect(requestCount, 2);
    } finally {
      if (!releaseBody.isCompleted) {
        releaseBody.complete();
      }
      client.close();
    }
  });

  test('HG44: 最初から過去のResetでは60分停止しない', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final pastReset = now.subtract(const Duration(seconds: 1));

    final client = MockClient((_) async {
      requestCount++;

      if (requestCount == 1) {
        return http.Response(
          '{"message":"API rate limit exceeded"}',
          403,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${pastReset.millisecondsSinceEpoch ~/ 1000}',
          },
        );
      }

      return http.Response(jsonEncode(payload()), 200);
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    try {
      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );

      // 過去のResetが既知なので、暫定停止は60秒。
      final deadline = now.add(const Duration(seconds: 60));

      expect(policy.retryAt(GitHubApiResource.search, now), deadline);

      // 解除直前には送信しない。
      current = deadline.subtract(const Duration(milliseconds: 1));

      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(isA<ApiFailure>()),
      );

      expect(requestCount, 1);

      // 60秒経過後、利用者の再要求を許可。
      current = deadline;

      final result = await gateway.searchRepositories('flutter');

      expect(result.items.length, 1);
      expect(requestCount, 2);
    } finally {
      client.close();
    }
  });

  test('HG45: キュー待機中の期限切れ要求は送信しない', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    final sentQueries = <String>[];

    final client = MockClient((request) {
      final query = request.url.queryParameters['q']!;
      sentQueries.add(query);

      if (query == 'alpha') {
        firstStarted.complete();
        return firstResponse.future;
      }

      return Future.value(http.Response(jsonEncode(payload()), 200));
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      requestTimeout: const Duration(milliseconds: 50),
    );

    // Aは実際にHTTP送信するが、応答を返さない。
    final aOutcome = gateway
        .searchRepositories('alpha')
        .then<Object>(
          (result) => result,
          onError: (Object error, StackTrace stack) => error,
        );

    final started = firstStarted.future.timeout(const Duration(seconds: 2));

    try {
      await started;

      // Aが未終了のままBをキューに追加。
      final bOutcome = gateway
          .searchRepositories('beta')
          .then<Object>(
            (result) => result,
            onError: (Object error, StackTrace stack) => error,
          );

      try {
        // Bも自分の期限内にタイムアウトしなければならない。
        final bResult = await bOutcome.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => StateError('Bがキュー待機中にタイムアウトしなかった'),
        );

        expect(
          bResult,
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        );

        // Aが未終了なので、Bは送信されていない。
        expect(sentQueries, ['alpha']);

        // ここでAを終了させる。
        firstResponse.complete(http.Response(jsonEncode(payload()), 200));

        await aOutcome;

        // 期限切れのBを追い越し、新しいCが正常に動く。
        final cResult = await gateway
            .searchRepositories('gamma')
            .timeout(const Duration(seconds: 2));

        expect(cResult.items.length, 1);

        // BはA終了後にも送信してはいけない。
        expect(sentQueries, ['alpha', 'gamma']);
      } finally {
        if (!firstResponse.isCompleted) {
          firstResponse.complete(http.Response(jsonEncode(payload()), 200));
        }

        await bOutcome.timeout(const Duration(seconds: 2));
      }
    } finally {
      if (!firstResponse.isCompleted) {
        firstResponse.complete(http.Response(jsonEncode(payload()), 200));
      }

      await aOutcome.timeout(const Duration(seconds: 2));
      client.close();
    }
  });

  testWidgets('HG46: キュー待機時間も通信期限に含める', (tester) async {
    final firstResponse = Completer<http.Response>();
    final secondResponse = Completer<http.Response>();
    final sentQueries = <String>[];

    http.Response successResponse() =>
        http.Response(jsonEncode(payload()), 200);

    final client = MockClient((request) {
      final query = request.url.queryParameters['q']!;
      sentQueries.add(query);

      return switch (query) {
        'alpha' => firstResponse.future,
        'beta' => secondResponse.future,
        _ => throw StateError('Unexpected query: $query'),
      };
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      requestTimeout: const Duration(milliseconds: 100),
    );

    final firstOutcome = gateway
        .searchRepositories('alpha')
        .then<Object>(
          (result) => result,
          onError: (Object error, StackTrace stack) => error,
        );

    Object? secondResult;

    try {
      await tester.pump();
      expect(sentQueries, ['alpha']);

      // Bをキューへ登録。この時点から100msを計測。
      final secondOutcome = gateway
          .searchRepositories('beta')
          .then<Object>(
            (result) => result,
            onError: (Object error, StackTrace stack) => error,
          );

      unawaited(
        secondOutcome.then<void>((result) {
          secondResult = result;
        }),
      );

      // Bの期限の80%を待機キュー内で消費。
      await tester.pump(const Duration(milliseconds: 80));

      expect(sentQueries, ['alpha']);
      expect(secondResult, isNull);

      // Aが終了し、BがHTTP送信を開始。
      firstResponse.complete(successResponse());
      await tester.pump();

      expect(sentQueries, ['alpha', 'beta']);

      // Bの残り通信時間は20ms。
      await tester.pump(const Duration(milliseconds: 19));
      expect(secondResult, isNull);

      await tester.pump(const Duration(milliseconds: 1));

      expect(
        secondResult,
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.timeout),
      );

      expect(await firstOutcome, isA<SearchPage>());
    } finally {
      // 中断非対応のMockClientを完了させる。
      if (!firstResponse.isCompleted) {
        firstResponse.complete(successResponse());
      }
      if (!secondResponse.isCompleted) {
        secondResponse.complete(successResponse());
      }

      await tester.pump();
      client.close();
    }
  });

  test('HG47: 429本文切断でも連続制限を1回として計上', () async {
    var current = now;
    var requestCount = 0;
    final policy = GitHubRateLimitPolicy();

    final client = MockClient.streaming((request, bodyStream) async {
      requestCount++;

      if (requestCount == 1) {
        // 429ヘッダーは届くが本文の受信で失敗。
        return http.StreamedResponse(
          Stream<List<int>>.error(
            http.ClientException('Simulated body disconnect'),
          ),
          429,
        );
      }

      // 2回目は本文も正常に受信できる429。
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"Too many requests"}')),
        429,
      );
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => current,
    );

    try {
      // 1回目：本文切断による通信エラー。
      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.network,
          ),
        ),
      );

      // ヘッダーで認識した429によって60秒停止。
      expect(
        policy.retryAt(GitHubApiResource.search, now),
        now.add(const Duration(seconds: 60)),
      );

      // 61秒経過後、再び429を受信する。
      current = now.add(const Duration(seconds: 61));

      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.rateLimited,
          ),
        ),
      );

      // 2回目なので、ここから120秒停止する。
      final expectedDeadline = current.add(const Duration(seconds: 120));

      expect(
        policy.retryAt(GitHubApiResource.search, current),
        expectedDeadline,
      );

      // 共通制限なので詳細取得も停止する。
      expect(policy.retryAt(GitHubApiResource.core, current), expectedDeadline);

      // ここまでHTTP送信は2回だけ。
      expect(requestCount, 2);
    } finally {
      client.close();
    }
  });
  test('HG48: タイマー通知前でも期限切れ要求を送信しない', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    final sentQueries = <String>[];

    final client = MockClient((request) {
      final query = request.url.queryParameters['q']!;
      sentQueries.add(query);

      if (query == 'alpha') {
        firstStarted.complete();
        return firstResponse.future;
      }

      return Future.value(http.Response(jsonEncode(payload()), 200));
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      requestTimeout: const Duration(milliseconds: 100),
    );

    final aOutcome = gateway
        .searchRepositories('alpha')
        .then<Object>(
          (value) => value,
          onError: (Object error, StackTrace stack) => error,
        );

    try {
      await firstStarted.future.timeout(const Duration(seconds: 2));

      // Aの実通信中にBをキューへ登録する。
      final bOutcome = gateway
          .searchRepositories('beta')
          .then<Object>(
            (value) => value,
            onError: (Object error, StackTrace stack) => error,
          );

      // イベント処理を意図的に250ms停止する。
      // この間、Timerのコールバックも実行できない。
      sleep(const Duration(milliseconds: 250));

      // Timer通知より先にAの完了を通知する。
      firstResponse.complete(http.Response(jsonEncode(payload()), 200));

      final aResult = await aOutcome.timeout(const Duration(seconds: 2));
      final bResult = await bOutcome.timeout(const Duration(seconds: 2));

      // Timerが遅れても、実経過時間で期限切れと判断。
      expect(
        aResult,
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.timeout),
      );

      expect(
        bResult,
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.timeout),
      );

      // 期限切れのBを送信していない。
      expect(sentQueries, ['alpha']);

      // 新しいCは正常に送信できる。
      final cResult = await gateway.searchRepositories('gamma');

      expect(cResult.items.length, 1);
      expect(sentQueries, ['alpha', 'gamma']);
    } finally {
      if (!firstResponse.isCompleted) {
        firstResponse.complete(http.Response(jsonEncode(payload()), 200));
      }
      client.close();
    }
  });
  test('HG49: HTTP応答の制限ヘッダーを診断記録する', () async {
    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    final reset = now.add(const Duration(minutes: 2));

    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(payload()),
        200,
        headers: {
          'x-ratelimit-limit': '10',
          'x-ratelimit-remaining': '7',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          'x-ratelimit-resource': 'search',
        },
      ),
    );
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      diagnostics: diagnostics,
    );

    final result = await gateway.searchRepositories('flutter');

    expect(result.items.length, 1);
    expect(diagnostics.value.length, 1);

    final event = diagnostics.value.single;

    expect(event.operation, ApiDiagnosticOperation.search);
    expect(event.outcome, ApiDiagnosticOutcome.response);
    expect(event.httpStatus, 200);
    expect(event.rateLimitLimit, 10);
    expect(event.rateLimitRemaining, 7);
    expect(event.rateLimitResetAt, reset);

    // D02ではJSON本文は保存しない。
    expect(event.responsePreview, isNull);
  });

  test('HG50: 本文切断後も429の停止期限を診断し再送を拒否', () async {
    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    final policy = GitHubRateLimitPolicy();
    final expectedRetryAt = now.toUtc().add(const Duration(seconds: 120));

    var requestCount = 0;

    final client = MockClient.streaming((request, bodyStream) async {
      requestCount++;

      return http.StreamedResponse(
        Stream<List<int>>.error(http.ClientException('Simulated body failure')),
        429,
        headers: {'retry-after': '120'},
      );
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => now,
      diagnostics: diagnostics,
    );

    // 1. 初回はHTTP送信後、本文受信エラーで失敗する。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.network),
      ),
    );

    expect(requestCount, 1);

    // 2. HTTP応答とアプリ側の停止期限が別々に記録される。
    expect(diagnostics.value, hasLength(2));

    final responseEvent = diagnostics.value[0];

    expect(responseEvent.operation, ApiDiagnosticOperation.search);
    expect(responseEvent.outcome, ApiDiagnosticOutcome.response);
    expect(responseEvent.httpStatus, 429);
    expect(responseEvent.retryAfter, const Duration(seconds: 120));

    final policyEvent = diagnostics.value[1];

    expect(
      policyEvent.outcome,
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
    );
    expect(policyEvent.httpStatus, isNull);
    expect(policyEvent.policyRetryAt, expectedRetryAt);

    // 3. 直後の再検索は送信前に拒否する。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.rateLimited)
            .having((e) => e.retryAt, 'retryAt', expectedRetryAt),
      ),
    );

    // 実際のHTTP送信は1回のまま。
    expect(requestCount, 1);

    // 4. 送信前の拒否も独立した診断記録として残る。
    expect(diagnostics.value, hasLength(3));

    final blockedEvent = diagnostics.value[2];

    expect(blockedEvent.outcome, ApiDiagnosticOutcome.blockedByRateLimit);
    expect(blockedEvent.httpStatus, isNull);
    expect(blockedEvent.policyRetryAt, expectedRetryAt);
  });

  test('HG51: 診断Sinkの失敗はHTTP検索に影響しない', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode(payload()), 200),
    );
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      diagnostics: _ThrowingDiagnosticsSink(),
    );

    final result = await gateway.searchRepositories('flutter');

    expect(result.items.single.fullName, 'sample/example');
  });

  test('HG52: HTTPの429と送信前の制限を区別して診断記録', () async {
    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    final policy = GitHubRateLimitPolicy();
    var requestCount = 0;

    final client = MockClient((request) async {
      requestCount++;

      return http.Response(
        '{"message":"Too many requests"}',
        429,
        headers: {'retry-after': '120'},
      );
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => now,
      diagnostics: diagnostics,
    );

    // 1回目：実際にGitHubから429が返る状況。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    expect(requestCount, 1);
    expect(diagnostics.value, hasLength(2));

    final responseEvent = diagnostics.value[0];
    final policyEvent = diagnostics.value[1];

    expect(responseEvent.outcome, ApiDiagnosticOutcome.response);
    expect(responseEvent.httpStatus, 429);
    expect(responseEvent.retryAfter, const Duration(seconds: 120));

    expect(
      policyEvent.outcome,
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
    );
    expect(policyEvent.httpStatus, isNull);
    expect(policyEvent.policyRetryAt, now.add(const Duration(seconds: 120)));

    // 2回目：まだ制限中なのでHTTP送信しない。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    // HTTP要求は増えていない。
    expect(requestCount, 1);

    // 診断履歴は2件になる。
    expect(diagnostics.value, hasLength(3));

    final blockedEvent = diagnostics.value.last;

    expect(blockedEvent.operation, ApiDiagnosticOperation.search);
    expect(blockedEvent.outcome, ApiDiagnosticOutcome.blockedByRateLimit);

    // HTTP応答がないのでステータスはnull。
    expect(blockedEvent.httpStatus, isNull);

    // GitHubから通知された待機時間に基づく
    // アプリ側の送信再開予定時刻。
    expect(blockedEvent.policyRetryAt, now.add(const Duration(seconds: 120)));
  });

  test('HG53: 429応答後のPolicy期限を診断記録する', () async {
    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    final client = MockClient(
      (_) async => http.Response(
        '{"message":"Too many requests"}',
        429,
        headers: {'retry-after': '120'},
      ),
    );
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      diagnostics: diagnostics,
    );

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.rateLimited,
        ),
      ),
    );

    expect(diagnostics.value, hasLength(2));

    final responseEvent = diagnostics.value.first;
    final policyEvent = diagnostics.value.last;

    expect(responseEvent.outcome, ApiDiagnosticOutcome.response);
    expect(responseEvent.httpStatus, 429);

    expect(
      policyEvent.outcome,
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
    );
    expect(policyEvent.httpStatus, isNull);
    expect(policyEvent.policyRetryAt, now.add(const Duration(seconds: 120)));
  });

  test('HG54: HTTP 200で残数0ならPolicyの停止を診断記録', () async {
    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    final reset = now.add(const Duration(minutes: 2));

    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(payload()),
        200,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
        },
      ),
    );
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      diagnostics: diagnostics,
    );

    final result = await gateway.searchRepositories('flutter');

    // 正常な検索結果は利用できる。
    expect(result.items.length, 1);

    // HTTP応答とPolicyの状態を別々に記録。
    expect(diagnostics.value, hasLength(2));
    expect(diagnostics.value.first.httpStatus, 200);

    final policyEvent = diagnostics.value.last;

    expect(
      policyEvent.outcome,
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
    );
    expect(policyEvent.policyRetryAt, reset);
  });
  test('HG55: 404で残数0なら詳細枠だけをResetまで停止', () async {
    await verifyPrimaryExhaustionOnHttpError(
      statusCode: 404,
      expectedKind: ApiFailureKind.notFoundOrUnavailable,
    );
  });

  test('HG56: 422で残数0なら詳細枠だけをResetまで停止', () async {
    await verifyPrimaryExhaustionOnHttpError(
      statusCode: 422,
      expectedKind: ApiFailureKind.invalidRequest,
    );
  });

  test('HG57: 503のRetry-Afterを守り、serverErrorを維持する', () async {
    var now = DateTime.utc(2026, 11, 22, 12);
    final retryAt = now.add(const Duration(seconds: 120));

    var searchRequestCount = 0;
    var detailRequestCount = 0;

    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    final client = MockClient((request) async {
      if (request.url.path == '/search/repositories') {
        searchRequestCount++;

        if (searchRequestCount == 1) {
          return http.Response(
            '{"message":"Service unavailable"}',
            503,
            headers: {'retry-after': '120'},
          );
        }

        return http.Response(
          '{"total_count":0,"incomplete_results":false,"items":[]}',
          200,
        );
      }

      if (request.url.path.startsWith('/repos/')) {
        detailRequestCount++;

        return http.Response('{"message":"Not found"}', 404);
      }

      throw StateError('Unexpected request: ${request.url}');
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => now,
      diagnostics: diagnostics,
    );

    // 1. 最初の503はserverErrorとして返す。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              ApiFailureKind.serverError,
            )
            .having((failure) => failure.httpStatus, 'httpStatus', 503),
      ),
    );

    expect(searchRequestCount, 1);

    // 2. 応答後、アプリが待機状態を記録している。
    expect(diagnostics.value, hasLength(2));

    expect(diagnostics.value.first.outcome, ApiDiagnosticOutcome.response);
    expect(diagnostics.value.first.httpStatus, 503);

    final policyEvent = diagnostics.value.last;

    expect(
      policyEvent.outcome,
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
    );
    expect(policyEvent.policyRetryAt, retryAt);

    // 3. 119秒後は送信を拒否する。
    now = now.add(const Duration(seconds: 119));

    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              ApiFailureKind.rateLimited,
            )
            .having(
              (failure) => failure.reason,
              'reason',
              ApiFailureReason.blockedBeforeSend,
            )
            .having((failure) => failure.retryAt, 'retryAt', retryAt),
      ),
    );

    expect(searchRequestCount, 1);

    // 4. 検索の待機中でも詳細APIは送信できる。
    await expectLater(
      gateway.getRepository(
        const RepositoryKey(id: 101, owner: 'sample', name: 'missing'),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.kind,
          'kind',
          ApiFailureKind.notFoundOrUnavailable,
        ),
      ),
    );

    expect(detailRequestCount, 1);

    // 5. 120秒経過したら再び検索を送信できる。
    now = retryAt;

    final result = await gateway.searchRepositories('flutter');

    expect(result.items, isEmpty);
    expect(searchRequestCount, 2);
  });

  Future<void> verifyInterruptedPrimaryExhaustion({
    required int statusCode,
    required bool isSearch,
  }) async {
    final start = DateTime.utc(2026, 11, 22, 12);
    var clock = start;
    final resetAt = start.add(const Duration(seconds: 120));

    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    var requestCount = 0;

    final client = MockClient.streaming((request, bodyStream) async {
      requestCount++;

      expect(
        request.url.path,
        isSearch ? '/search/repositories' : '/repos/sample/missing',
      );

      return http.StreamedResponse(
        Stream<List<int>>.error(http.ClientException('Simulated body failure')),
        statusCode,
        headers: {
          'x-ratelimit-resource': isSearch ? 'search' : 'core',
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${resetAt.millisecondsSinceEpoch ~/ 1000}',
        },
      );
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => clock,
      diagnostics: diagnostics,
    );

    Future<void> requestOnce() async {
      if (isSearch) {
        await gateway.searchRepositories('flutter');
      } else {
        await gateway.getRepository(
          const RepositoryKey(id: 101, owner: 'sample', name: 'missing'),
        );
      }
    }

    // 1. ヘッダー受信後に本文が切断される。
    await expectLater(
      requestOnce(),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.network),
      ),
    );

    expect(requestCount, 1);

    // 2. 本文が切断されても、制限は診断に記録される。
    expect(diagnostics.value, hasLength(2));

    final responseEvent = diagnostics.value[0];
    expect(responseEvent.outcome, ApiDiagnosticOutcome.response);
    expect(responseEvent.httpStatus, statusCode);
    expect(responseEvent.rateLimitRemaining, 0);
    expect(responseEvent.rateLimitResetAt, resetAt);

    final policyEvent = diagnostics.value[1];
    expect(
      policyEvent.outcome,
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
    );
    expect(policyEvent.policyRetryAt, resetAt);

    // 3. Resetの1秒前にはHTTP要求を送信しない。
    clock = start.add(const Duration(seconds: 119));

    await expectLater(
      requestOnce(),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.rateLimited)
            .having((e) => e.retryAt, 'retryAt', resetAt),
      ),
    );

    expect(requestCount, 1);

    // 送信前に拒否した記録が追加される。
    expect(diagnostics.value, hasLength(3));
    expect(
      diagnostics.value.last.outcome,
      ApiDiagnosticOutcome.blockedByRateLimit,
    );

    // 4. Reset到達後はHTTP送信できる。
    clock = resetAt;

    // Mockは再び本文切断するため、結果はnetwork。
    // ここではHTTP送信が再開されたことを確認する。
    await expectLater(
      requestOnce(),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.network),
      ),
    );

    expect(requestCount, 2);
  }

  test('HG58: 404で本文切断しても残数0を反映する', () async {
    await verifyInterruptedPrimaryExhaustion(statusCode: 404, isSearch: false);
  });

  test('HG59: 422で本文切断しても残数0を反映する', () async {
    await verifyInterruptedPrimaryExhaustion(statusCode: 422, isSearch: true);
  });

  Future<void> verify503CompositeDeadlines({
    required Duration retryAfter,
    required Duration primaryReset,
  }) async {
    final start = DateTime.utc(2026, 11, 22, 12);
    var clock = start;

    final resetAt = start.add(primaryReset);
    final longestDelay = retryAfter.compareTo(primaryReset) >= 0
        ? retryAfter
        : primaryReset;
    final expectedRetryAt = start.add(longestDelay);

    var requestCount = 0;

    final diagnostics = InMemoryApiDiagnostics();
    addTearDown(diagnostics.dispose);

    final client = MockClient((request) async {
      expect(request.url.path, '/search/repositories');

      requestCount++;

      if (requestCount == 1) {
        return http.Response(
          '{"message":"Service unavailable"}',
          503,
          headers: {
            'retry-after': '${retryAfter.inSeconds}',
            'x-ratelimit-resource': 'search',
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${resetAt.millisecondsSinceEpoch ~/ 1000}',
          },
        );
      }

      return http.Response(
        '{"total_count":0,"incomplete_results":false,"items":[]}',
        200,
        headers: {'x-ratelimit-remaining': '5'},
      );
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => clock,
      diagnostics: diagnostics,
    );

    // 1. 最初の503はserverErrorとして扱う。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.serverError)
            .having((e) => e.httpStatus, 'httpStatus', 503),
      ),
    );

    expect(requestCount, 1);

    // 2. アプリが長い方の期限を記録する。
    expect(diagnostics.value, hasLength(2));

    final policyEvent = diagnostics.value.last;
    expect(
      policyEvent.outcome,
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
    );
    expect(policyEvent.policyRetryAt, expectedRetryAt);

    // 3. 短い方の待機期限（5秒）では送信を再開しない。
    //    さらに119秒後も送信禁止であることを確認。
    for (final elapsedSeconds in [5, 119]) {
      clock = start.add(Duration(seconds: elapsedSeconds));

      await expectLater(
        gateway.searchRepositories('flutter'),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.kind, 'kind', ApiFailureKind.rateLimited)
              .having((e) => e.retryAt, 'retryAt', expectedRetryAt),
        ),
      );

      expect(requestCount, 1, reason: '$elapsedSeconds秒時点でHTTPを再送してはいけない');
    }

    // 4. 最も遅い期限に到達したら送信可能。
    clock = expectedRetryAt;

    final result = await gateway.searchRepositories('flutter');

    expect(result.items, isEmpty);
    expect(requestCount, 2);
  }

  test('HG60: 503でPrimary ResetがRetry-Afterより長い', () async {
    await verify503CompositeDeadlines(
      retryAfter: const Duration(seconds: 5),
      primaryReset: const Duration(seconds: 120),
    );
  });

  test('HG61: 503でRetry-AfterがPrimary Resetより長い', () async {
    await verify503CompositeDeadlines(
      retryAfter: const Duration(seconds: 120),
      primaryReset: const Duration(seconds: 5),
    );
  });

  test('HG62: Issue検索は既存のSearch API制限を共有する', () async {
    var clock = DateTime.utc(2026, 11, 22, 12);
    final resetAt = clock.add(const Duration(minutes: 2));

    final requests = <Uri>[];

    final client = MockClient((request) async {
      requests.add(request.url);

      if (request.url.path == '/search/issues') {
        expect(
          request.url.queryParameters['q'],
          'repo:sample/example is:issue is:open',
        );

        expect(request.url.queryParameters['per_page'], '1');

        return http.Response(
          '{"total_count":7,"incomplete_results":false,"items":[{"number":1}]}',
          200,
          headers: {
            'x-ratelimit-resource': 'search',
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${resetAt.millisecondsSinceEpoch ~/ 1000}',
          },
        );
      }

      if (request.url.path == '/repos/sample/example') {
        return http.Response('{"message":"Not found"}', 404);
      }

      if (request.url.path == '/search/repositories') {
        return http.Response(
          '{"total_count":0,"incomplete_results":false,"items":[]}',
          200,
        );
      }

      throw StateError('Unexpected request: ${request.url}');
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => clock,
    );

    const key = RepositoryKey(id: 1, owner: 'sample', name: 'example');

    // 1. Gateway生成だけではAPI通信しない。
    expect(requests, isEmpty);

    // 2. 明示的なIssue検索で1回送信。
    final count = await gateway.getOpenIssueCount(key);

    expect(count, 7);
    expect(requests, hasLength(1));
    expect(requests.single.path, '/search/issues');

    // 3. Issue検索でSearch枠が0になったので、
    //    通常のリポジトリ検索も送信前に停止する。
    await expectLater(
      gateway.searchRepositories('flutter'),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.rateLimited)
            .having((e) => e.retryAt, 'retryAt', resetAt),
      ),
    );

    expect(requests, hasLength(1));

    // 4. Search枠が停止しても詳細取得のCore枠は使用可能。
    await expectLater(
      gateway.getRepository(key),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.notFoundOrUnavailable,
        ),
      ),
    );

    expect(requests, hasLength(2));

    // 5. Resetに到達すれば通常検索を再開できる。
    clock = resetAt;

    final result = await gateway.searchRepositories('flutter');

    expect(result.items, isEmpty);
    expect(requests, hasLength(3));
  });

  test('HG63: キュー待機中にキャンセルされたIssue検索は送信しない', () async {
    final firstRequestStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();

    final sentPaths = <String>[];

    final client = MockClient((request) async {
      sentPaths.add(request.url.path);

      if (request.url.path == '/search/repositories') {
        firstRequestStarted.complete();

        // 先行要求の応答を意図的に保留する。
        return firstResponse.future;
      }

      if (request.url.path == '/search/issues') {
        return http.Response(
          '{"total_count":7,"incomplete_results":false,"items":[]}',
          200,
        );
      }

      throw StateError('Unexpected request: ${request.url}');
    });
    addTearDown(client.close);

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => DateTime.utc(2026, 11, 22, 12),
    );

    const key = RepositoryKey(id: 1, owner: 'sample', name: 'example');

    // 1. 最初の検索要求を送信し、応答待ちにする。
    final searchFuture = gateway.searchRepositories('flutter');

    await firstRequestStarted.future;

    expect(sentPaths, ['/search/repositories']);

    // 2. Issue検索を要求。先行要求が未完了なのでキューで待機。
    var canceled = false;

    final issueFuture = gateway.getOpenIssueCount(
      key,
      isCanceled: () => canceled,
    );

    // 期待するキャンセル例外を先に監視する。
    final canceledExpectation = expectLater(
      issueFuture,
      throwsA(isA<QueuedRequestCanceled>()),
    );

    // キュー処理が進む機会を与える。
    await Future<void>.delayed(Duration.zero);

    // まだIssue検索は送信されていない。
    expect(sentPaths, ['/search/repositories']);

    // 3. 画面を閉じた状態を模擬する。
    canceled = true;

    // 4. 先行する検索を完了する。
    firstResponse.complete(
      http.Response(
        '{"total_count":0,"incomplete_results":false,"items":[]}',
        200,
      ),
    );

    final searchResult = await searchFuture;
    expect(searchResult.items, isEmpty);

    // 5. Issue検索は送信前にキャンセルされる。
    await canceledExpectation;

    // 実際のHTTP送信は最初の検索だけ。
    expect(sentPaths, ['/search/repositories']);
  });
}

final class _ThrowingDiagnosticsSink implements ApiDiagnosticsSink {
  @override
  void record(ApiDiagnosticEvent event) {
    throw StateError('Simulated diagnostics failure');
  }
}

Future<void> verifyPrimaryExhaustionOnHttpError({
  required int statusCode,
  required ApiFailureKind expectedKind,
}) async {
  var now = DateTime.utc(2026, 11, 22, 12);
  final resetAt = now.add(const Duration(seconds: 120));

  var detailRequestCount = 0;
  var searchRequestCount = 0;

  final client = MockClient((request) async {
    if (request.url.path == '/search/repositories') {
      searchRequestCount++;

      return http.Response(
        '{"total_count":0,"incomplete_results":false,"items":[]}',
        200,
        headers: {
          'x-ratelimit-resource': 'search',
          'x-ratelimit-remaining': '5',
        },
      );
    }

    if (request.url.path.startsWith('/repos/')) {
      detailRequestCount++;

      return http.Response(
        '{"message":"Repository unavailable"}',
        statusCode,
        headers: {
          'x-ratelimit-resource': 'core',

          // 最初の詳細応答で枠が0になる。
          // Reset後の詳細応答では残数5に戻す。
          'x-ratelimit-remaining': detailRequestCount == 1 ? '0' : '5',

          'x-ratelimit-reset': '${resetAt.millisecondsSinceEpoch ~/ 1000}',
        },
      );
    }

    throw StateError('Unexpected request: ${request.url}');
  });
  addTearDown(client.close);

  final gateway = HttpGitHubRepositoryGateway(
    client: client,
    policy: GitHubRateLimitPolicy(),
    now: () => now,
  );

  const firstKey = RepositoryKey(id: 101, owner: 'sample', name: 'missing-a');

  const secondKey = RepositoryKey(id: 102, owner: 'sample', name: 'missing-b');

  // 1. 最初のHTTPエラーは、元のエラー分類を維持する。
  await expectLater(
    gateway.getRepository(firstKey),
    throwsA(
      isA<ApiFailure>().having((failure) => failure.kind, 'kind', expectedKind),
    ),
  );

  expect(detailRequestCount, 1);

  // 2. Resetの119秒後では、別の詳細要求も送信できない。
  now = now.add(const Duration(seconds: 119));

  await expectLater(
    gateway.getRepository(secondKey),
    throwsA(
      isA<ApiFailure>()
          .having((failure) => failure.kind, 'kind', ApiFailureKind.rateLimited)
          .having((failure) => failure.retryAt, 'retryAt', resetAt),
    ),
  );

  // HTTP送信数は増えない。
  expect(detailRequestCount, 1);

  // 3. coreが停止しても、searchの枠は使用できる。
  final searchResult = await gateway.searchRepositories('flutter');

  expect(searchResult.items, isEmpty);
  expect(searchRequestCount, 1);
  expect(detailRequestCount, 1);

  // 4. Reset到達時には詳細要求を再開できる。
  now = resetAt;

  await expectLater(
    gateway.getRepository(secondKey),
    throwsA(
      isA<ApiFailure>().having((failure) => failure.kind, 'kind', expectedKind),
    ),
  );

  // 2回目の詳細HTTP要求が送信された。
  expect(detailRequestCount, 2);

  // 5. Reset後は残数5なので、続けて詳細要求を送信できる。
  await expectLater(
    gateway.getRepository(firstKey),
    throwsA(
      isA<ApiFailure>().having((failure) => failure.kind, 'kind', expectedKind),
    ),
  );

  expect(detailRequestCount, 3);
}
