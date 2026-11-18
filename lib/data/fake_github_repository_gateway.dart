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
  });

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
        safeMessage: '仮の検索失敗です。もう一度検索してください。',
      );
    }
    final incomplete = normalized == 'incomplete';
    final matches = normalized.isEmpty || normalized == 'empty'
        ? <RepositorySummary>[]
        : _summaries
              .where(
                (item) =>
                    incomplete ||
                    item.fullName.toLowerCase().contains(normalized),
              )
              .toList();
    return SearchPage(
      items: matches.skip((page - 1) * perPage).take(perPage).toList(),
      totalCount: matches.length,
      incompleteResults: incomplete,
      page: page,
      perPage: perPage,
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
        safeMessage: '対象の仮データを取得できませんでした。',
        httpStatus: 404,
      );
    }
    final attempts = (_detailAttempts[key] ?? 0) + 1;
    _detailAttempts[key] = attempts;
    if (key.id == 2 && attempts == 1) {
      throw const ApiFailure(
        kind: ApiFailureKind.network,
        safeMessage: '仮の詳細取得失敗です。再試行してください。',
      );
    }
    return RepositoryDetail(
      summary: matches.single,
      watcherCount: key.id == 1 ? 8 : 0,
    );
  }

  Future<void> _wait() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }
}
