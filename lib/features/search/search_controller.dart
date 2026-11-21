import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:developer' as developer;

import '../../models/api_failure.dart';
import '../../models/repository_models.dart' show NextPage, PageEnd;
import '../../providers.dart';

import 'search_state.dart';
import 'unexpected_error_reporter.dart';

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  int _requestGeneration = 0;

  @override
  SearchState build() {
    // Providerの状態が破棄された時点で、
    // 実行中の古い検索要求を無効化する。
    ref.onDispose(() {
      ++_requestGeneration;
    });

    return const SearchIdle();
  }

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
    final reporter = requestRef.read(unexpectedErrorReporterProvider);
    // この検索を識別する番号を発行。
    final generation = ++_requestGeneration;

    state = SearchLoading(query);

    try {
      const requestedPage = 1;
      const requestedPerPage = 30;

      final page = await gateway.searchRepositories(
        query,
        page: requestedPage,
        perPage: requestedPerPage,
      );

      // 破棄済み・キャンセル済みなら反映しない。
      if (!requestRef.mounted || generation != _requestGeneration) {
        return;
      }

      // 要求と異なるページ情報を持つ応答は採用しない。
      if (page.page != requestedPage || page.perPage != requestedPerPage) {
        throw StateError('Unexpected initial search response');
      }

      if (page.items.isEmpty) {
        state = SearchEmpty(
          query: query,
          totalCount: page.totalCount,
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

      state = SearchFailure(query, const UnexpectedSearchProblem());

      _reportUnexpectedSafely(reporter, error, stackTrace);
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
    final reporter = requestRef.read(unexpectedErrorReporterProvider);
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

      _reportUnexpectedSafely(reporter, error, stackTrace);
    }
  }

  void _reportUnexpectedSafely(
    UnexpectedErrorReporter reporter,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      reporter.report(error, stackTrace);
    } catch (reportError, reportStackTrace) {
      // Reporterの失敗で検索状態を壊さない。
      // 比較試作では別の診断出力へフォールバックする。
      developer.log(
        'Unexpected error reporter failed',
        name: 'yumemi.search',
        error: reportError,
        stackTrace: reportStackTrace,
      );

      developer.log(
        'Original unexpected search error',
        name: 'yumemi.search',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
