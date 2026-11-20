import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/api_failure.dart';
import '../../models/repository_models.dart' show NextPage, PageEnd;
import '../../providers.dart';
import 'search_state.dart';

final spikeSearchControllerProvider =
    NotifierProvider<SpikeSearchController, SearchState>(
      SpikeSearchController.new,
    );

class SpikeSearchController extends Notifier<SearchState> {
  int _requestGeneration = 0;

  @override
  SearchState build() => const SearchIdle();

  Future<void> search(String input) async {
    // 実行中の新規検索は受け付けない。
    final current = state;
    if (current is SearchLoading ||
        (current is SearchResults && current.loadMore is LoadMoreLoading)) {
      return;
    }

    final query = input.trim();
    if (query.isEmpty) return;

    final requestRef = ref;
    final gateway = requestRef.read(githubRepositoryGatewayProvider);

    // この検索を識別する番号を発行。
    final generation = ++_requestGeneration;

    state = SearchLoading(query);

    try {
      final page = await gateway.searchRepositories(query);

      // 破棄済み・キャンセル済みなら反映しない。
      if (!requestRef.mounted || generation != _requestGeneration) {
        return;
      }

      if (page.items.isEmpty) {
        state = SearchEmpty(
          query: query,
          incompleteResults: page.incompleteResults,
        );
        return;
      }

      // 暫定判定。
      // PageNavigationが実装されたら置き換える。
      final LoadMoreState loadMore = switch (page.navigation) {
        NextPage() => const LoadMoreAvailable(),
        PageEnd(:final reason) => LoadMoreEnd(reason),
      };

      state = SearchResults(
        query: query,
        items: page.items,
        totalCount: page.totalCount,
        incompleteResults: page.incompleteResults,
        loadedPage: page.page,
        loadMore: loadMore,
        perPage: page.perPage,
      );
    } on ApiFailure catch (failure) {
      if (!requestRef.mounted || generation != _requestGeneration) {
        return;
      }

      state = SearchFailure(query, ApiSearchProblem(failure));
    } catch (error, stackTrace) {
      if (!requestRef.mounted || generation != _requestGeneration) {
        return;
      }

      // 内部エラーを通信失敗と区別する。
      state = SearchFailure(query, const UnexpectedSearchProblem());

      // 比較試作では呼び出し元へ例外を伝える。
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void cancel() {
    final current = state;

    final isInitialLoading = current is SearchLoading;
    final isLoadingMore =
        current is SearchResults && current.loadMore is LoadMoreLoading;

    if (!isInitialLoading && !isLoadingMore) return;

    // 古いFutureを先に無効化する。
    ++_requestGeneration;

    if (current is SearchLoading) {
      state = const SearchIdle();
    } else if (current is SearchResults) {
      // 取得済みの結果とページ番号を維持する。
      state = current.copyWith(loadMore: const LoadMoreAvailable());
    }
  }

  Future<void> loadMore() => _loadMore(retry: false);

  Future<void> retryLoadMore() => _loadMore(retry: true);

  Future<void> _loadMore({required bool retry}) async {
    final current = state;

    if (current is! SearchResults) return;

    // 通常取得と失敗後の再試行を区別する。
    if (retry) {
      if (current.loadMore is! LoadMoreFailure) return;
    } else {
      if (current.loadMore is! LoadMoreAvailable) return;
    }

    final requestRef = ref;
    final gateway = requestRef.read(githubRepositoryGatewayProvider);

    final generation = ++_requestGeneration;
    final requestedPage = current.loadedPage + 1;

    // 既存一覧を残したまま追加読み込みへ移行する。
    state = current.copyWith(loadMore: const LoadMoreLoading());

    try {
      final page = await gateway.searchRepositories(
        current.query,
        page: requestedPage,
        perPage: current.perPage,
      );

      if (!requestRef.mounted || generation != _requestGeneration) {
        return;
      }

      // 要求と異なるページを返されたら採用しない。
      if (page.page != requestedPage || page.perPage != current.perPage) {
        throw StateError('Unexpected pagination response');
      }

      // リポジトリIDで重複を除去する。
      final knownIds = current.items.map((item) => item.key.id).toSet();

      final additions = page.items
          .where((item) => knownIds.add(item.key.id))
          .toList();

      final LoadMoreState nextLoadMore = switch (page.navigation) {
        NextPage() => const LoadMoreAvailable(),
        PageEnd(:final reason) => LoadMoreEnd(reason),
      };

      state = current.copyWith(
        items: [...current.items, ...additions],
        loadedPage: page.page,
        incompleteResults: current.incompleteResults || page.incompleteResults,
        loadMore: nextLoadMore,
      );
    } on ApiFailure catch (failure) {
      if (!requestRef.mounted || generation != _requestGeneration) {
        return;
      }

      // 失敗しても既存一覧は保持する。
      state = current.copyWith(
        loadMore: LoadMoreFailure(ApiSearchProblem(failure)),
      );
    } catch (error, stackTrace) {
      if (!requestRef.mounted || generation != _requestGeneration) {
        return;
      }

      state = current.copyWith(
        loadMore: const LoadMoreFailure(UnexpectedSearchProblem()),
      );

      // 比較試作では内部エラーを呼び出し元へ伝える。
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
