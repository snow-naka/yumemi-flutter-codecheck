import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/features/search/search_controller.dart';
import 'package:yumemi_app/features/search/search_state.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/features/search/unexpected_error_reporter.dart';

import 'search_test_support.dart';

void main() {
  late ProviderContainer container;
  late SearchController controller;

  late List<String> queries;
  late List<Completer<SearchPage>> requests;
  late List<({String query, int page, int perPage})> calls;
  late _RecordingUnexpectedErrorReporter reporter;
  setUp(() {
    queries = [];
    requests = [];
    calls = [];
    reporter = _RecordingUnexpectedErrorReporter();
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
      overrides: [
        githubRepositoryGatewayProvider.overrideWithValue(fake),
        unexpectedErrorReporterProvider.overrideWithValue(reporter),
      ],
    );

    controller = container.read(searchControllerProvider.notifier);
  });

  test('T01: 初回検索が成功する', () async {
    final task = controller.search(' flutter ');

    expect(queries, ['flutter']);

    final loading = container.read(searchControllerProvider);

    expect(loading, isA<SearchLoading>());
    expect((loading as SearchLoading).query, 'flutter');

    requests.single.complete(resultPage(count: 2));

    await task;

    final result = container.read(searchControllerProvider);

    expect(result, isA<SearchResults>());

    final success = result as SearchResults;
    expect(success.query, 'flutter');
    expect(success.items, hasLength(2));
    expect(success.loadedPage, 1);
  });

  test('T02: キャンセル後に古い結果を無視する', () async {
    final task = controller.search('flutter');

    expect(container.read(searchControllerProvider), isA<SearchLoading>());

    controller.cancel();

    expect(container.read(searchControllerProvider), isA<SearchIdle>());

    // キャンセル済みFutureを後から完了させる。
    requests.single.complete(resultPage());

    await task;

    expect(container.read(searchControllerProvider), isA<SearchIdle>());
  });

  test('T03: 同じ検索語の古い応答を破棄する', () async {
    final taskA = controller.search('flutter');

    controller.cancel();

    final taskB = controller.search('flutter');

    expect(queries, ['flutter', 'flutter']);

    final loadingB = container.read(searchControllerProvider);

    expect(loadingB, isA<SearchLoading>());

    // キャンセルされたAが先に完了。
    requests[0].complete(resultPage(count: 1));

    await taskA;

    // BはまだLoadingのまま。
    expect(container.read(searchControllerProvider), same(loadingB));

    // Bを正常完了させる。
    requests[1].complete(resultPage(count: 2));

    await taskB;

    final result = container.read(searchControllerProvider);

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

    final loading = container.read(searchControllerProvider) as SearchResults;

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

    final result = container.read(searchControllerProvider) as SearchResults;

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

    final failed = container.read(searchControllerProvider) as SearchResults;

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

    final result = container.read(searchControllerProvider) as SearchResults;

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

    final cancelled = container.read(searchControllerProvider) as SearchResults;

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

    expect(container.read(searchControllerProvider), same(cancelled));
  });

  test('T08: 追加ページが0件でも取得済み結果を保持', () async {
    final firstTask = controller.search('flutter');

    // 初回は30件要求し、総31件と報告される。
    expect(calls.single.page, 1);
    expect(calls.single.perPage, 30);

    requests[0].complete(
      _page(
        page: 1,
        ids: List.generate(30, (i) => i + 1),
        totalCount: 31,
        navigation: const NextPage(2),
      ),
    );

    await firstTask;

    final loadTask = controller.loadMore();

    expect(calls.last.page, 2);
    expect(calls.last.perPage, 30);

    // 検索結果が変動し、2ページ目は0件になる。
    requests[1].complete(
      _page(
        page: 2,
        ids: [],
        totalCount: 29,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await loadTask;

    final result = container.read(searchControllerProvider) as SearchResults;

    expect(result.items, hasLength(30));
    expect(result.totalCount, 31);
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

    final cancelled = container.read(searchControllerProvider) as SearchResults;

    expect(cancelled.items, hasLength(2));
    expect(cancelled.loadMore, isA<LoadMoreAvailable>());

    // 新しい検索Bを開始
    final taskB = controller.search('dart');

    expect(calls, hasLength(3));
    expect(calls.last.query, 'dart');
    expect(calls.last.page, 1);

    final loadingB = container.read(searchControllerProvider);

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
    expect(container.read(searchControllerProvider), same(loadingB));

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

    final result = container.read(searchControllerProvider) as SearchResults;

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

    final successB = container.read(searchControllerProvider) as SearchResults;

    expect(successB.items.map((item) => item.key.id).toList(), [10, 11]);

    // キャンセル済みAの追加取得が後から失敗する
    requests[1].completeError(
      const ApiFailure(kind: ApiFailureKind.network, safeMessage: '古い検索の通信失敗'),
    );
    await loadTask;

    // AのエラーでBの成功状態が上書きされない
    expect(container.read(searchControllerProvider), same(successB));

    expect(successB.items.map((item) => item.key.id).toList(), [10, 11]);
  });

  test('T11: 初回検索中の新しい検索要求を拒否する', () async {
    final taskA = controller.search('flutter');

    final loadingA = container.read(searchControllerProvider);

    expect(loadingA, isA<SearchLoading>());

    // 検索Aが未完了の間にBを要求
    await controller.search('dart');

    // GatewayはAの1回しか呼ばれない
    expect(calls, hasLength(1));
    expect(calls.single.query, 'flutter');

    expect(container.read(searchControllerProvider), same(loadingA));

    requests.single.complete(
      _page(
        page: 1,
        ids: [1],
        totalCount: 1,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await taskA;

    final result = container.read(searchControllerProvider) as SearchResults;

    expect(result.query, 'flutter');
    expect(result.items.single.key.id, 1);
  });

  test('T12: Provider無効化後の古い応答を無視する', () async {
    // 古いControllerで検索開始
    final oldTask = controller.search('flutter');

    expect(requests, hasLength(1));

    // Futureが未完了のままProviderを無効化
    container.invalidate(searchControllerProvider);

    // 新しいControllerの状態を確認
    final newState = container.read(searchControllerProvider);

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
    expect(container.read(searchControllerProvider), isA<SearchIdle>());
  });

  test('T13: 想定外例外後も再検索できる', () async {
    // 1回目の検索
    final taskA = controller.search('flutter');

    expect(container.read(searchControllerProvider), isA<SearchLoading>());

    // Gatewayで想定外例外が発生
    requests[0].completeError(StateError('想定外の内部エラー'));

    await taskA;

    // Loadingに残らず、内部エラーとして分類される。
    final failed = container.read(searchControllerProvider) as SearchFailure;

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

    final result = container.read(searchControllerProvider) as SearchResults;

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

    // 想定外例外を発生させる
    requests[1].completeError(StateError('追加取得の内部エラー'));

    await loadTask;

    final failed = container.read(searchControllerProvider) as SearchResults;

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

    final result = container.read(searchControllerProvider) as SearchResults;

    expect(result.items.map((e) => e.key.id).toList(), [1, 2, 3]);
    expect(result.loadedPage, 2);
    expect(result.loadMore, isA<LoadMoreEnd>());
  });

  test('T15: 初回検索の内部エラーをReporterへ通知', () async {
    final originalError = StateError('Internal failure');

    final task = controller.search('flutter');

    requests[0].completeError(originalError);

    await task;

    final failed = container.read(searchControllerProvider);

    expect(failed, isA<SearchFailure>());

    final failure = failed as SearchFailure;
    expect(failure.problem, isA<UnexpectedSearchProblem>());

    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.error, same(originalError));
    expect(reporter.reports.single.stackTrace, isA<StackTrace>());
  });

  test('T16: 追加取得の内部エラーをReporterへ通知', () async {
    final firstTask = controller.search('flutter');

    requests[0].complete(
      _page(page: 1, ids: [1, 2], totalCount: 3, navigation: const NextPage(2)),
    );

    await firstTask;

    final loadTask = controller.loadMore();
    final originalError = StateError('Load more failure');

    requests[1].completeError(originalError);

    await loadTask;

    final state = container.read(searchControllerProvider) as SearchResults;

    expect(state.items, hasLength(2));
    expect(state.loadedPage, 1);
    expect(state.loadMore, isA<LoadMoreFailure>());

    final failure = state.loadMore as LoadMoreFailure;
    expect(failure.problem, isA<UnexpectedSearchProblem>());

    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.error, same(originalError));
  });

  test('T17: Reporterが失敗しても検索を再開できる', () async {
    reporter.throwOnReport = true;

    final taskA = controller.search('flutter');

    requests[0].completeError(StateError('Gateway internal failure'));

    // Reporterが失敗してもControllerのFutureは完了する。
    await taskA;

    final failed = container.read(searchControllerProvider);

    expect(failed, isA<SearchFailure>());
    expect((failed as SearchFailure).problem, isA<UnexpectedSearchProblem>());

    expect(reporter.reports, hasLength(1));

    // 次の検索を実行できる。
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

    final result = container.read(searchControllerProvider) as SearchResults;

    expect(result.query, 'dart');
    expect(result.items.single.key.id, 10);
  });

  test('T18: 検索結果0件でもメタデータを保持する', () async {
    // 検索を開始
    final task = controller.search('flutter');

    expect(container.read(searchControllerProvider), isA<SearchLoading>());

    // APIは0件の結果とメタデータを返す
    requests.single.complete(
      SearchPage(
        items: const [],
        totalCount: 100,
        incompleteResults: true,
        page: 1,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await task;

    // 0件専用の状態になる
    final state = container.read(searchControllerProvider);

    expect(state, isA<SearchEmpty>());

    final empty = state as SearchEmpty;

    // APIから受け取った情報が失われていない
    expect(empty.query, 'flutter');
    expect(empty.totalCount, 100);
    expect(empty.incompleteResults, isTrue);

    // 余分な検索が発生していない
    expect(calls, hasLength(1));
    expect(calls.single.page, 1);
  });

  for (final fails in [false, true]) {
    test('T20: 空入力で既存状態を維持する (failure=$fails)', () async {
      // 初期状態で空入力しても検索しない
      expect(container.read(searchControllerProvider), isA<SearchIdle>());

      await controller.search('   ');

      expect(container.read(searchControllerProvider), isA<SearchIdle>());
      expect(queries, isEmpty);

      // 最初の検索を実行
      final task = controller.search('flutter');

      if (fails) {
        requests.single.completeError(
          const ApiFailure(
            kind: ApiFailureKind.network,
            safeMessage: 'テスト用の通信失敗',
          ),
        );
      } else {
        requests.single.complete(resultPage());
      }

      await task;

      final previous = container.read(searchControllerProvider);

      expect(previous, fails ? isA<SearchFailure>() : isA<SearchResults>());

      // 結果取得後・失敗後の空入力
      await controller.search('   ');

      // 状態を変更しない
      expect(container.read(searchControllerProvider), same(previous));
      expect(queries, ['flutter']);
    });
  }
  test('T21: Provider破棄後の遅延応答を安全に無視する', () async {
    final task = controller.search('flutter');

    expect(container.read(searchControllerProvider), isA<SearchLoading>());

    // 検索完了前にProviderContainerを破棄
    container.dispose();

    // 破棄後にAPIエラーが到着
    requests.single.completeError(
      const ApiFailure(kind: ApiFailureKind.network, safeMessage: '遅延した通信失敗'),
    );

    // 破棄済みProviderへの更新などで例外終了しない
    await task;
  });
  test('T22: 無効化直後の古い内部例外はReporterに通知しない', () async {
    // 検索Aを開始して、応答を保留する。
    final oldTask = controller.search('flutter');

    expect(requests, hasLength(1));

    // Providerを無効化する。
    container.invalidate(searchControllerProvider);

    // 重要：
    // ここではProviderをreadせず、再構築させない。

    // 古い検索Aが想定外例外で完了する。
    requests.single.completeError(StateError('古い検索の内部エラー'));

    await oldTask;

    // 無効化済みの検索の例外を通知しない。
    expect(reporter.reports, isEmpty);

    // 再構築後は待機状態。
    expect(container.read(searchControllerProvider), isA<SearchIdle>());
  });
  for (final response in [
    (name: 'page', page: 2, perPage: 30),
    (name: 'perPage', page: 1, perPage: 100),
  ]) {
    test('T23: 初回応答のページ情報不一致を拒否する (${response.name})', () async {
      final task = controller.search('flutter');

      // 実際の初回要求は1ページ目・30件。
      expect(calls.single.page, 1);
      expect(calls.single.perPage, 30);

      // 要求と異なるページ番号またはページサイズを返す。
      requests.single.complete(
        _page(
          page: response.page,
          perPage: response.perPage,
          ids: [1],
          totalCount: 1,
          navigation: const PageEnd(SearchEndReason.exhausted),
        ),
      );

      await task;

      // 不正な応答を検索成功として扱わない。
      final state = container.read(searchControllerProvider);

      expect(state, isA<SearchFailure>());
      expect((state as SearchFailure).problem, isA<UnexpectedSearchProblem>());

      expect(reporter.reports, hasLength(1));

      // 失敗後の再検索は1ページ目から実行できる。
      final retryTask = controller.search('flutter');

      expect(calls.last.page, 1);
      expect(calls.last.perPage, 30);

      requests.last.complete(
        _page(
          page: 1,
          ids: [2],
          totalCount: 1,
          navigation: const PageEnd(SearchEndReason.exhausted),
        ),
      );

      await retryTask;

      final result = container.read(searchControllerProvider) as SearchResults;

      expect(result.items.single.key.id, 2);
    });
  }
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

final class _RecordingUnexpectedErrorReporter
    implements UnexpectedErrorReporter {
  final reports = <({Object error, StackTrace stackTrace})>[];

  bool throwOnReport = false;

  @override
  void report(Object error, StackTrace stackTrace) {
    reports.add((error: error, stackTrace: stackTrace));

    if (throwOnReport) {
      throw StateError('Reporter failed');
    }
  }
}
