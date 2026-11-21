import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';
import 'package:yumemi_app/data/http_github_repository_gateway.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';

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
              .having((e) => e.httpStatus, 'httpStatus', status),
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
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.invalidRequest,
        ),
      ),
    );

    expect(requestCount, 0);
    client.close();
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
}
