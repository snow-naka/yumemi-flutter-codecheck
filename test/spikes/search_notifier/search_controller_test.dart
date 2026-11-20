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

  test('T09: 追加読み込みキャンセル後の新規検索を保護する', () async {
    // 検索Aの1ページ目を取得
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(page: 1, ids: [1, 2], totalCount: 3, navigation: const NextPage(2)),
    );
    await firstTask;

    // 検索Aの2ページ目を開始（未完了）
    final loadTask = controller.loadMore();

    expect(calls.last.query, 'flutter');
    expect(calls.last.page, 2);

    // 追加読み込みをキャンセル
    controller.cancel();

    final cancelled =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(cancelled.items, hasLength(2));
    expect(cancelled.loadMore, isA<LoadMoreAvailable>());

    // 新しい検索Bを開始
    final taskB = controller.search('dart');

    expect(calls, hasLength(3));
    expect(calls.last.query, 'dart');
    expect(calls.last.page, 1);

    final loadingB = container.read(spikeSearchControllerProvider);

    expect(loadingB, isA<SearchLoading>());
    expect((loadingB as SearchLoading).query, 'dart');

    // キャンセル済みの検索A・2ページ目が後から成功
    requests[1].complete(
      _page(
        page: 2,
        ids: [3],
        totalCount: 3,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );
    await loadTask;

    // 古いAの完了によってBのLoadingは変わらない
    expect(container.read(spikeSearchControllerProvider), same(loadingB));

    // 検索Bを正常完了させる
    requests[2].complete(
      _page(
        page: 1,
        ids: [10, 11],
        totalCount: 2,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );
    await taskB;

    final result =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(result.query, 'dart');
    expect(result.items.map((item) => item.key.id).toList(), [10, 11]);
    expect(result.loadedPage, 1);
  });

  test('T10: 古い追加読み込みの失敗で新しい成功結果を壊さない', () async {
    // 検索Aの初回取得
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(page: 1, ids: [1, 2], totalCount: 3, navigation: const NextPage(2)),
    );
    await firstTask;

    // Aの2ページ目を開始
    final loadTask = controller.loadMore();

    // Aの追加取得をキャンセル
    controller.cancel();

    // あえて同じ検索語でもう一度検索する
    final taskB = controller.search('flutter');

    expect(calls, hasLength(3));

    // 新しい検索Bを先に成功させる
    requests[2].complete(
      _page(
        page: 1,
        ids: [10, 11],
        totalCount: 2,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );
    await taskB;

    final successB =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(successB.items.map((item) => item.key.id).toList(), [10, 11]);

    // キャンセル済みAの追加取得が後から失敗する
    requests[1].completeError(
      const ApiFailure(kind: ApiFailureKind.network, safeMessage: '古い検索の通信失敗'),
    );
    await loadTask;

    // AのエラーでBの成功状態が上書きされない
    expect(container.read(spikeSearchControllerProvider), same(successB));

    expect(successB.items.map((item) => item.key.id).toList(), [10, 11]);
  });

  test('T11: 初回検索中の新しい検索要求を拒否する', () async {
    final taskA = controller.search('flutter');

    final loadingA = container.read(spikeSearchControllerProvider);

    expect(loadingA, isA<SearchLoading>());

    // 検索Aが未完了の間にBを要求
    await controller.search('dart');

    // GatewayはAの1回しか呼ばれない
    expect(calls, hasLength(1));
    expect(calls.single.query, 'flutter');

    expect(container.read(spikeSearchControllerProvider), same(loadingA));

    requests.single.complete(
      _page(
        page: 1,
        ids: [1],
        totalCount: 1,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await taskA;

    final result =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(result.query, 'flutter');
    expect(result.items.single.key.id, 1);
  });

  test('T12: Provider無効化後の古い応答を無視する', () async {
    // 古いControllerで検索開始
    final oldTask = controller.search('flutter');

    expect(requests, hasLength(1));

    // Futureが未完了のままProviderを無効化
    container.invalidate(spikeSearchControllerProvider);

    // 新しいControllerの状態を確認
    final newState = container.read(spikeSearchControllerProvider);

    expect(newState, isA<SearchIdle>());

    // 古い検索が後から完了する
    requests.single.complete(
      _page(
        page: 1,
        ids: [1],
        totalCount: 1,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await oldTask;

    // 新しいControllerには影響しない
    expect(container.read(spikeSearchControllerProvider), isA<SearchIdle>());
  });

  test('T13: 想定外例外後も再検索できる', () async {
    // 1回目の検索
    final taskA = controller.search('flutter');

    expect(container.read(spikeSearchControllerProvider), isA<SearchLoading>());

    // エラーを検証するFutureを先に登録する。
    final errorCheck = expectLater(taskA, throwsA(isA<StateError>()));

    // Gatewayで想定外例外が発生
    requests[0].completeError(StateError('想定外の内部エラー'));

    await errorCheck;

    // Loadingに残らず、内部エラーとして分類される。
    final failed =
        container.read(spikeSearchControllerProvider) as SearchFailure;

    expect(failed.query, 'flutter');
    expect(failed.problem, isA<UnexpectedSearchProblem>());

    // エラー後の新しい検索
    final taskB = controller.search('dart');

    expect(calls, hasLength(2));
    expect(calls.last.query, 'dart');

    requests[1].complete(
      _page(
        page: 1,
        ids: [10],
        totalCount: 1,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await taskB;

    final result =
        container.read(spikeSearchControllerProvider) as SearchResults;

    expect(result.query, 'dart');
    expect(result.items.single.key.id, 10);
  });

  test('T14: 追加読み込みの想定外例外でも既存結果を保持', () async {
    // 1ページ目の取得
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(page: 1, ids: [1, 2], totalCount: 3, navigation: const NextPage(2)),
    );

    await firstTask;

    // 2ページ目の追加読み込み
    final loadTask = controller.loadMore();

    final errorCheck = expectLater(loadTask, throwsA(isA<StateError>()));

    // 想定外例外を発生させる
    requests[1].completeError(StateError('追加取得の内部エラー'));

    await errorCheck;

    final failed =
        container.read(spikeSearchControllerProvider) as SearchResults;

    // 取得済みの一覧とページ番号は変わらない。
    expect(failed.items.map((e) => e.key.id).toList(), [1, 2]);
    expect(failed.loadedPage, 1);

    // 追加読み込みの内部エラーとして分類される。
    expect(failed.loadMore, isA<LoadMoreFailure>());

    final problem = (failed.loadMore as LoadMoreFailure).problem;

    expect(problem, isA<UnexpectedSearchProblem>());

    // 同じ2ページ目を再試行できる。
    final retryTask = controller.retryLoadMore();

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

    expect(result.items.map((e) => e.key.id).toList(), [1, 2, 3]);
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
