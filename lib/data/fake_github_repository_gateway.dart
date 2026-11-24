import '../models/api_failure.dart';
import '../models/repository_models.dart';
import 'github_repository_gateway.dart';

typedef FakeSearchHandler = Future<SearchPage> Function(
  String query, {
  required int page,
  required int perPage,
});
typedef FakeDetailHandler = Future<RepositoryDetail> Function(
  RepositoryKey key,
);

class FakeGitHubRepositoryGateway implements GitHubRepositoryGateway {
  FakeGitHubRepositoryGateway({
    this.delay = const Duration(milliseconds: 300),
    this.searchHandler,
    this.detailHandler,
    this.openIssueCountHandler,
    List<RepositorySummary>? searchSummaries,
  }) : _searchSummaries = List<RepositorySummary>.unmodifiable(
         searchSummaries ?? _summaries,
       );

  final List<RepositorySummary> _searchSummaries;
  final FakeOpenIssueCountHandler? openIssueCountHandler;
  final Duration delay;
  // 指定したハンドラーは既定の待機・シナリオを置き換える。
  final FakeSearchHandler? searchHandler;
  final FakeDetailHandler? detailHandler;
  final Map<RepositoryKey, int> _detailAttempts = {};

  static const _summaries = [
    RepositorySummary(
      key: RepositoryKey(id: 1, owner: 'example', name: 'flutter-sample'),
      avatarUrl: '',
      language: 'Dart',
      starCount: 120,
      forkCount: 12,
      openIssueAndPullRequestCount: 7,
    ),
    RepositorySummary(
      key: RepositoryKey(id: 2, owner: 'example', name: 'riverpod-sample'),
      avatarUrl: '',
      language: null,
      starCount: 0,
      forkCount: 0,
      openIssueAndPullRequestCount: 0,
    ),
  ];

  @override
  Future<SearchPage> searchRepositories(
    String query, {
    int page = 1,
    int perPage = 30,
    bool Function()? isCanceled,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    if (perPage < 1 || perPage > 100) {
      throw ArgumentError.value(perPage, 'perPage');
    }
    final handler = searchHandler;
    if (handler != null) return handler(query, page: page, perPage: perPage);
    await _wait();
    final normalized = query.trim().toLowerCase();
    if (normalized == 'error') {
      throw const ApiFailure(
        kind: ApiFailureKind.network,
        reason: ApiFailureReason.simulatedSearchFailure,
      );
    }
    final incomplete = normalized == 'incomplete';
    final matches = normalized.isEmpty || normalized == 'empty'
        ? <RepositorySummary>[]
        : _searchSummaries
              .where(
                (item) =>
                    incomplete ||
                    item.fullName.toLowerCase().contains(normalized),
              )
              .toList();
    const maxSearchResults = 1000;

    final accessibleCount = matches.length > maxSearchResults
        ? maxSearchResults
        : matches.length;

    final start = (page - 1) * perPage;
    final remaining = accessibleCount - start;

    final takeCount = remaining <= 0
        ? 0
        : (remaining < perPage ? remaining : perPage);

    final items = matches.skip(start).take(takeCount).toList();

    final PageNavigation navigation;

    if (start + items.length < accessibleCount) {
      navigation = NextPage(page + 1);
    } else if (matches.length > maxSearchResults &&
        start + items.length >= maxSearchResults) {
      navigation = const PageEnd(SearchEndReason.githubLimitReached);
    } else {
      navigation = const PageEnd(SearchEndReason.exhausted);
    }

    return SearchPage(
      items: items,
      totalCount: matches.length,
      incompleteResults: incomplete,
      page: page,
      perPage: perPage,
      navigation: navigation,
    );
  }

  @override
  Future<RepositoryDetail> getRepository(RepositoryKey key) async {
    final handler = detailHandler;
    if (handler != null) return handler(key);
    await _wait();
    final matches = _summaries.where((item) => item.key == key);
    if (matches.isEmpty) {
      throw const ApiFailure(
        kind: ApiFailureKind.notFoundOrUnavailable,
        reason: ApiFailureReason.simulatedRepositoryNotFound,
        httpStatus: 404,
      );
    }
    final attempts = (_detailAttempts[key] ?? 0) + 1;
    _detailAttempts[key] = attempts;
    if (key.id == 2 && attempts == 1) {
      throw const ApiFailure(
        kind: ApiFailureKind.network,
        reason: ApiFailureReason.simulatedDetailFailure,
      );
    }
    return RepositoryDetail(
      summary: matches.single,
      watcherCount: key.id == 1 ? 8 : 0,
    );
  }

  @override
  Future<int> getOpenIssueCount(
    RepositoryKey key, {
    bool Function()? isCanceled,
  }) async {
    if (isCanceled?.call() ?? false) {
      throw const QueuedRequestCanceled();
    }

    final handler = openIssueCountHandler;
    if (handler != null) {
      return handler(key);
    }

    await _wait();

    if (isCanceled?.call() ?? false) {
      throw const QueuedRequestCanceled();
    }

    return 0;
  }

  Future<void> _wait() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }
}

typedef FakeOpenIssueCountHandler = Future<int> Function(RepositoryKey key);
