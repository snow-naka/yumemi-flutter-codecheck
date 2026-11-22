import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/http_github_repository_gateway.dart';
import 'package:yumemi_app/providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:yumemi_app/models/repository_models.dart';

void main() {
  test('GP01: 通常ProviderはHTTP Gatewayを共有する', () {
    final container = ProviderContainer();

    try {
      final first = container.read(githubRepositoryGatewayProvider);

      final second = container.read(githubRepositoryGatewayProvider);

      expect(first, isA<HttpGitHubRepositoryGateway>());
      expect(second, same(first));
    } finally {
      container.dispose();
    }
  });

  test('GP02: ProviderContainer破棄でHTTP Clientが閉じられる', () async {
    final container = ProviderContainer();

    // 実際の通常Providerを使用する。
    final gateway = container.read(githubRepositoryGatewayProvider);
    final client = container.read(githubHttpClientProvider);

    expect(gateway, isA<HttpGitHubRepositoryGateway>());
    expect(client, isA<IOClient>());

    // ProviderContainerを破棄する。
    container.dispose();

    // 閉鎖済みIOClientは新しい要求を受け付けない。
    // ループバック宛てなので外部APIには接続しない。
    await expectLater(
      client.send(http.Request('GET', Uri.parse('http://127.0.0.1:1/'))),
      throwsA(
        isA<http.ClientException>().having(
          (e) => e.message,
          'message',
          contains('already closed'),
        ),
      ),
    );
  });

  test('GP03: Provider経由で検索と詳細取得ができる', () async {
    final requestedPaths = <String>[];

    final repository = <String, dynamic>{
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
    };

    final client = MockClient((request) async {
      requestedPaths.add(request.url.path);

      expect(request.method, 'GET');
      expect(request.headers['X-GitHub-Api-Version'], '2026-03-10');

      if (request.url.path == '/search/repositories') {
        expect(request.url.queryParameters['q'], 'flutter');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['per_page'], '30');

        return http.Response(
          jsonEncode({
            'total_count': 1,
            'incomplete_results': false,
            'items': [repository],
          }),
          200,
        );
      }

      if (request.url.path == '/repos/sample/example') {
        return http.Response(
          jsonEncode({...repository, 'subscribers_count': 17}),
          200,
        );
      }

      throw StateError('Unexpected URL: ${request.url}');
    });

    // Gatewayは本番用Providerのまま。
    // HTTP Clientだけをテスト用に差し替える。
    final container = ProviderContainer(
      overrides: [githubHttpClientProvider.overrideWithValue(client)],
    );

    try {
      final gateway = container.read(githubRepositoryGatewayProvider);

      expect(gateway, isA<HttpGitHubRepositoryGateway>());

      // 検索API
      final search = await gateway.searchRepositories('flutter');

      expect(search.totalCount, 1);
      expect(search.items.single.fullName, 'sample/example');

      // 検索結果のキーから詳細取得
      final detail = await gateway.getRepository(search.items.single.key);

      expect(
        detail.summary.key,
        const RepositoryKey(id: 123, owner: 'sample', name: 'example'),
      );

      expect(detail.summary.starCount, 42);
      expect(detail.watcherCount, 17);

      // 同じMockClientで2つのAPIを処理したことを確認。
      expect(requestedPaths, ['/search/repositories', '/repos/sample/example']);

      // Providerを読み直しても同じGatewayを利用する。
      expect(container.read(githubRepositoryGatewayProvider), same(gateway));
    } finally {
      container.dispose();

      // 注入したMockClientの所有者はこのテスト。
      client.close();
    }
  });

  test('GP04: HTTP Gatewayと診断履歴Providerを共有する', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'total_count': 0,
          'incomplete_results': false,
          'items': [],
        }),
        200,
        headers: {
          'x-ratelimit-limit': '10',
          'x-ratelimit-remaining': '7',
          'x-ratelimit-resource': 'search',
        },
      ),
    );

    final container = ProviderContainer(
      overrides: [githubHttpClientProvider.overrideWithValue(client)],
    );

    try {
      final diagnostics = container.read(apiDiagnosticsProvider);
      final gateway = container.read(githubRepositoryGatewayProvider);

      expect(diagnostics.value, isEmpty);

      final result = await gateway.searchRepositories('flutter');

      expect(result.items, isEmpty);

      // Gatewayが共有履歴に記録していることを確認。
      expect(diagnostics.value, hasLength(1));

      final event = diagnostics.value.single;
      expect(event.httpStatus, 200);
      expect(event.rateLimitLimit, 10);
      expect(event.rateLimitRemaining, 7);

      // Providerを再取得しても同じ記録先。
      expect(container.read(apiDiagnosticsProvider), same(diagnostics));
    } finally {
      container.dispose();
      client.close();
    }
  });
}
