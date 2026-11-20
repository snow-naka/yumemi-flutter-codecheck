import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/spikes/search_notifier/search_controller.dart';
import 'package:yumemi_app/spikes/search_notifier/search_state.dart';
import 'package:yumemi_app/models/api_failure.dart';

import '../../search/search_test_support.dart';

void main() {
  late ProviderContainer container;
  late SpikeSearchController controller;

  late List<String> queries;
  late List<Completer<SearchPage>> requests;
  late List<({String query, int page, int perPage})> calls;
  setUp(() {
    queries = [];
    requests = [];
    calls = [];
    final fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) {
        queries.add(query);
        calls.add((query: query, page: page, perPage: perPage));

        final completer = Completer<SearchPage>();
        requests.add(completer);

        return completer.future;
      },
    );

    container = ProviderContainer.test(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
    );

    controller = container.read(spikeSearchControllerProvider.notifier);
  });

  test('T01: 初回検索が成功する', () async {
    final task = controller.search(' flutter ');

    expect(queries, ['flutter']);

    final loading = container.read(spikeSearchControllerProvider);

    expect(loading, isA<SearchLoading>());
    expect((loading as SearchLoading).query, 'flutter');

    requests.single.complete(resultPage(count: 2));

    await task;

    final result = container.read(spikeSearchControllerProvider);

    expect(result, isA<SearchResults>());

    final success = result as SearchResults;
    expect(success.query, 'flutter');
    expect(success.items, hasLength(2));
    expect(success.loadedPage, 1);
  });

  test('T02: キャンセル後に古い結果を無視する', () async {
    final task = controller.search('flutter');

    expect(container.read(spikeSearchControllerProvider), isA<SearchLoading>());

    controller.cancel();

    expect(container.read(spikeSearchControllerProvider), isA<SearchIdle>());

    // キャンセル済みFutureを後から完了させる。
    requests.single.complete(resultPage());

    await task;

    expect(container.read(spikeSearchControllerProvider), isA<SearchIdle>());
  });

  test('T03: 同じ検索語の古い応答を破棄する', () async {
    final taskA = controller.search('flutter');

    controller.cancel();

    final taskB = controller.search('flutter');

    expect(queries, ['flutter', 'flutter']);

    final loadingB = container.read(spikeSearchControllerProvider);

    expect(loadingB, isA<SearchLoading>());

    // キャンセルされたAが先に完了。
    requests[0].complete(resultPage(count: 1));

    await taskA;

    // BはまだLoadingのまま。
    expect(container.read(spikeSearchControllerProvider), same(loadingB));

    // Bを正常完了させる。
    requests[1].complete(resultPage(count: 2));

    await taskB;

    final result = container.read(spikeSearchControllerProvider);

    expect(result, isA<SearchResults>());

    final success = result as SearchResults;

    expect(success.query, 'flutter');
    expect(success.items, hasLength(2));
  });

  test('T05: 取得済み結果を保持して追加読み込みする', () async {
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(page: 1, ids: [1, 2], totalCount: 3, navigation: const NextPage(2)),
    );
    await firstTask;

    final task = controller.loadMore();

    final loading =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(loading.items, hasLength(2));
    expect(loading.loadMore, isA<LoadMoreLoading>());
    expect(calls.last.page, 2);

    // ID=2は既存結果と重複している。
    requests[1].complete(
      _page(
        page: 2,
        ids: [2, 3],
        totalCount: 3,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );
    await task;

    final result =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(result.items.map((e) => e.key.id).toList(), [1, 2, 3]);
    expect(result.loadedPage, 2);
    expect(result.loadMore, isA<LoadMoreEnd>());
  });

  test('T06: 追加読み込み失敗後に同じページを再試行', () async {
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(page: 1, ids: [1, 2], totalCount: 3, navigation: const NextPage(2)),
    );
    await firstTask;

    final loadTask = controller.loadMore();

    requests[1].completeError(
      const ApiFailure(kind: ApiFailureKind.network, safeMessage: 'テスト用の通信失敗'),
    );
    await loadTask;

    final failed =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(failed.items, hasLength(2));
    expect(failed.loadedPage, 1);
    expect(failed.loadMore, isA<LoadMoreFailure>());

    final retryTask = controller.retryLoadMore();

    // 再試行でも2ページ目を要求する。
    expect(calls.last.page, 2);

    requests[2].complete(
      _page(
        page: 2,
        ids: [3],
        totalCount: 3,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await retryTask;

    final result =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(result.items, hasLength(3));
    expect(result.loadedPage, 2);
    expect(result.loadMore, isA<LoadMoreEnd>());
  });

  test('T07: 追加読み込みキャンセル後も結果を維持', () async {
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(page: 1, ids: [1, 2], totalCount: 3, navigation: const NextPage(2)),
    );
    await firstTask;

    final loadTask = controller.loadMore();

    controller.cancel();

    final cancelled =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(cancelled.items, hasLength(2));
    expect(cancelled.loadedPage, 1);
    expect(cancelled.loadMore, isA<LoadMoreAvailable>());

    // キャンセル済みの2ページ目が後から完了。
    requests[1].complete(
      _page(
        page: 2,
        ids: [3],
        totalCount: 3,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await loadTask;

    expect(container.read(spikeSearchControllerProvider), same(cancelled));
  });

  test('T08: 追加ページが0件でも取得済み結果を保持', () async {
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(
        page: 1,
        perPage: 100,
        ids: List.generate(100, (i) => i + 1),
        totalCount: 101,
        navigation: const NextPage(2),
      ),
    );
    await firstTask;

    final loadTask = controller.loadMore();

    expect(calls.last.page, 2);
    expect(calls.last.perPage, 100);

    requests[1].complete(
      _page(
        page: 2,
        perPage: 100,
        ids: [],
        totalCount: 99,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );
    await loadTask;

    final result =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(result.items, hasLength(100));
    expect(result.totalCount, 101);
    expect(result.loadedPage, 2);
    expect(result.loadMore, isA<LoadMoreEnd>());
  });
}

SearchPage _page({
  required int page,
  required List<int> ids,
  required int totalCount,
  required PageNavigation navigation,
  int perPage = 30,
}) {
  return SearchPage(
    items: [
      for (final id in ids)
        RepositorySummary(
          key: RepositoryKey(id: id, owner: 'test', name: 'repo-$id'),
          avatarUrl: '',
          language: 'Dart',
          starCount: 0,
          forkCount: 0,
          openIssueAndPullRequestCount: 0,
        ),
    ],
    totalCount: totalCount,
    incompleteResults: false,
    page: page,
    perPage: perPage,
    navigation: navigation,
  );
}
