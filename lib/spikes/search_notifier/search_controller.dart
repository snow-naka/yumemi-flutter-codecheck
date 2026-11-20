import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/api_failure.dart';
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
      final hasMore =
          page.items.length == page.perPage &&
          page.page * page.perPage < page.totalCount;

      state = SearchResults(
        query: query,
        items: page.items,
        totalCount: page.totalCount,
        incompleteResults: page.incompleteResults,
        loadedPage: page.page,
        loadMore: hasMore
            ? const LoadMoreAvailable()
            : const LoadMoreEnd(SearchEndReason.exhausted),
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
    // 今回は初回検索のキャンセルのみ実装。
    if (state is! SearchLoading) return;

    // 先に古い要求を無効化する。
    ++_requestGeneration;

    state = const SearchIdle();
  }
}
