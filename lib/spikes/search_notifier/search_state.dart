import '../../models/api_failure.dart';
import '../../models/repository_models.dart';

// 検索全体の状態
sealed class SearchState {
  const SearchState();
}

final class SearchIdle extends SearchState {
  const SearchIdle();
}

final class SearchLoading extends SearchState {
  const SearchLoading(this.query);

  final String query;
}

final class SearchFailure extends SearchState {
  const SearchFailure(this.query, this.problem);

  final String query;
  final SearchProblem problem;
}

final class SearchEmpty extends SearchState {
  const SearchEmpty({required this.query, required this.incompleteResults});

  final String query;
  final bool incompleteResults;
}

final class SearchResults extends SearchState {
  SearchResults({
    required this.query,
    required List<RepositorySummary> items,
    required this.totalCount,
    required this.incompleteResults,
    required this.loadedPage,
    required this.loadMore,
  }) : items = List.unmodifiable(items) {
    if (this.items.isEmpty) {
      throw ArgumentError('SearchResults requires items');
    }
    if (loadedPage < 1) {
      throw ArgumentError.value(loadedPage, 'loadedPage');
    }
  }

  final String query;
  final List<RepositorySummary> items;
  final int totalCount;
  final bool incompleteResults;
  final int loadedPage;
  final LoadMoreState loadMore;
}

// 追加読み込みの状態
sealed class LoadMoreState {
  const LoadMoreState();
}

final class LoadMoreAvailable extends LoadMoreState {
  const LoadMoreAvailable();
}

final class LoadMoreLoading extends LoadMoreState {
  const LoadMoreLoading();
}

final class LoadMoreFailure extends LoadMoreState {
  const LoadMoreFailure(this.problem);

  final SearchProblem problem;
}

final class LoadMoreEnd extends LoadMoreState {
  const LoadMoreEnd(this.reason);

  final SearchEndReason reason;
}

enum SearchEndReason { exhausted, githubLimitReached }

// 失敗原因の分類
sealed class SearchProblem {
  const SearchProblem();
}

final class ApiSearchProblem extends SearchProblem {
  const ApiSearchProblem(this.failure);

  final ApiFailure failure;
}

final class UnexpectedSearchProblem extends SearchProblem {
  const UnexpectedSearchProblem();
}
