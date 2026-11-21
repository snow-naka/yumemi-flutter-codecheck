import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';
import 'package:yumemi_app/data/http_github_repository_gateway.dart';
import 'package:yumemi_app/features/search/search_controller.dart';
import 'package:yumemi_app/features/search/search_state.dart';
import 'package:yumemi_app/providers.dart';

void main() {
  test('SC-HTTP01: Notifierのキャンセルで未送信検索を除外', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    final sentQueries = <String>[];

    http.Response successResponse() {
      return http.Response(
        jsonEncode({
          'total_count': 1,
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
        }),
        200,
      );
    }

    final client = MockClient((request) {
      final query = request.url.queryParameters['q']!;
      sentQueries.add(query);

      if (sentQueries.length == 1) {
        firstStarted.complete();
        return firstResponse.future;
      }

      return Future.value(successResponse());
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => DateTime.utc(2026, 11, 21, 12),
    );

    final container = ProviderContainer(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(gateway)],
    );

    try {
      final controller = container.read(searchControllerProvider.notifier);

      // A: 実際にHTTP送信し、応答を待機。
      final a = controller.search('alpha');

      await firstStarted.future.timeout(const Duration(seconds: 2));

      // Aをキャンセル。
      controller.cancel();

      // B: キューへ追加した後、送信前にキャンセル。
      final b = controller.search('beta');
      controller.cancel();

      // C: 最新の検索。
      final c = controller.search('gamma');

      // Aを完了させ、キューを進める。
      firstResponse.complete(successResponse());

      await Future.wait([a, b, c]).timeout(const Duration(seconds: 2));

      // キャンセルされたBは送信されない。
      expect(sentQueries, ['alpha', 'gamma']);

      // 古いAの応答ではなく、Cの結果を表示する。
      final state = container.read(searchControllerProvider);

      expect(state, isA<SearchResults>());

      final results = state as SearchResults;

      expect(results.query, 'gamma');
      expect(results.items.single.fullName, 'sample/example');
    } finally {
      if (!firstResponse.isCompleted) {
        firstResponse.complete(successResponse());
      }

      container.dispose();
      client.close();
    }
  });

  test('SC-HTTP02: 追加読み込みのキャンセルで未送信要求を除外', () async {
    final firstLoadStarted = Completer<void>();
    final firstLoadResponse = Completer<http.Response>();
    final sentPages = <int>[];
    var page2Requests = 0;

    http.Response pageResponse(int id, {required bool hasNext}) {
      return http.Response(
        jsonEncode({
          'total_count': 2,
          'incomplete_results': false,
          'items': [
            {
              'id': id,
              'name': 'repo$id',
              'owner': {
                'login': 'sample',
                'avatar_url': 'https://example.com/avatar.png',
              },
              'language': 'Dart',
              'stargazers_count': 10,
              'forks_count': 2,
              'open_issues_count': 1,
            },
          ],
        }),
        200,
        headers: hasNext
            ? {
                'link': '<https://api.github.com/search/repositories?page=2>; rel="next"',
              }
            : {},
      );
    }

    final client = MockClient((request) {
      final page = int.parse(request.url.queryParameters['page']!);
      sentPages.add(page);

      if (page == 1) {
        return Future.value(pageResponse(1, hasNext: true));
      }

      if (page == 2) {
        page2Requests++;

        if (page2Requests == 1) {
          firstLoadStarted.complete();
          return firstLoadResponse.future;
        }

        return Future.value(pageResponse(2, hasNext: false));
      }

      throw StateError('Unexpected page: $page');
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => DateTime.utc(2026, 11, 21, 12),
    );

    final container = ProviderContainer(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(gateway)],
    );

    try {
      final controller = container.read(searchControllerProvider.notifier);

      // 1ページ目を取得。
      await controller.search('flutter');

      final initial = container.read(searchControllerProvider);
      expect(initial, isA<SearchResults>());

      // 追加読み込みAを送信し、応答待ちにする。
      final a = controller.loadMore();

      await firstLoadStarted.future.timeout(const Duration(seconds: 2));

      // Aをキャンセル。
      controller.cancel();

      // Bをキューへ追加し、送信前にキャンセル。
      final b = controller.loadMore();
      controller.cancel();

      // 最新の追加読み込みC。
      final c = controller.loadMore();

      // Aが完了するとBは破棄され、Cが送信される。
      firstLoadResponse.complete(pageResponse(2, hasNext: false));

      await Future.wait([a, b, c]).timeout(const Duration(seconds: 2));

      // 1ページ目、追加読み込みA、追加読み込みCのみ送信。
      expect(sentPages, [1, 2, 2]);

      final state = container.read(searchControllerProvider);
      expect(state, isA<SearchResults>());

      final results = state as SearchResults;

      expect(results.query, 'flutter');
      expect(results.loadedPage, 2);
      expect(results.items.map((item) => item.fullName).toList(), [
        'sample/repo1',
        'sample/repo2',
      ]);
      expect(results.loadMore, isA<LoadMoreEnd>());
    } finally {
      if (!firstLoadResponse.isCompleted) {
        firstLoadResponse.complete(pageResponse(2, hasNext: false));
      }

      container.dispose();
      client.close();
    }
  });

  test('SC-HTTP03: Provider破棄後は未送信検索を除外', () async {
    final firstStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    final sentQueries = <String>[];

    final now = DateTime.utc(2026, 11, 21, 12);
    final policy = GitHubRateLimitPolicy();

    final client = MockClient((request) {
      final query = request.url.queryParameters['q']!;
      sentQueries.add(query);

      if (sentQueries.length == 1) {
        firstStarted.complete();
        return firstResponse.future;
      }

      // キャンセルされた要求が誤送信された場合の応答。
      return Future.value(http.Response('{}', 200));
    });

    final gateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: policy,
      now: () => now,
    );

    final container = ProviderContainer(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(gateway)],
    );

    var disposed = false;

    try {
      final controller = container.read(searchControllerProvider.notifier);

      // Aを送信して応答を保留する。
      final a = controller.search('alpha');

      await firstStarted.future.timeout(const Duration(seconds: 2));

      // Aをキャンセルし、Bをキューへ追加する。
      controller.cancel();
      final b = controller.search('beta');

      // この時点ではAだけが送信済み。
      expect(sentQueries, ['alpha']);

      // Providerを破棄してBを失効させる。
      container.dispose();
      disposed = true;

      // Aには429応答が返ってくる。
      firstResponse.complete(
        http.Response(
          '{"message":"Too many requests"}',
          429,
          headers: {'retry-after': '120'},
        ),
      );

      await Future.wait([a, b]).timeout(const Duration(seconds: 2));

      // Bは送信されない。
      expect(sentQueries, ['alpha']);

      // Aのレート制限情報は失われない。
      expect(
        policy.retryAt(GitHubApiResource.search, now),
        now.add(const Duration(seconds: 120)),
      );
    } finally {
      if (!firstResponse.isCompleted) {
        firstResponse.complete(http.Response('{}', 200));
      }

      if (!disposed) {
        container.dispose();
      }

      client.close();
    }
  });
}
