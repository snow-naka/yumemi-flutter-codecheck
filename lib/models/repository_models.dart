class RepositoryKey {
  const RepositoryKey({
    required this.id,
    required this.owner,
    required this.name,
  });

  final int id;
  final String owner;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is RepositoryKey &&
      id == other.id &&
      owner == other.owner &&
      name == other.name;

  @override
  int get hashCode => Object.hash(id, owner, name);
}

class RepositorySummary {
  const RepositorySummary({
    required this.key,
    required this.avatarUrl,
    required this.language,
    required this.starCount,
    required this.forkCount,
    required this.openIssueAndPullRequestCount,
  });

  final RepositoryKey key;
  final String avatarUrl;
  final String? language;
  final int starCount;
  final int forkCount;
  final int openIssueAndPullRequestCount;

  String get name => key.name;
  String get fullName => '${key.owner}/${key.name}';
}

class RepositoryDetail {
  const RepositoryDetail({required this.summary, required this.watcherCount});

  final RepositorySummary summary;
  final int watcherCount;
}

class SearchPage {
  SearchPage({
    required List<RepositorySummary> items,
    required this.totalCount,
    required this.incompleteResults,
    required this.page,
    required this.perPage,
    required this.navigation,
  }) : items = List.unmodifiable(items) {
    if (page < 1) {
      throw ArgumentError.value(page, 'page');
    }
    if (perPage < 1 || perPage > 100) {
      throw ArgumentError.value(perPage, 'perPage');
    }
    if (totalCount < 0) {
      throw ArgumentError.value(totalCount, 'totalCount');
    }
    if (this.items.length > perPage) {
      throw ArgumentError.value(this.items.length, 'items.length');
    }

    final nav = navigation;
    if (nav is NextPage && nav.page != page + 1) {
      throw ArgumentError.value(nav.page, 'navigation.page');
    }
  }

  final List<RepositorySummary> items;
  final int totalCount;
  final bool incompleteResults;
  final int page;
  final int perPage;
  final PageNavigation navigation;
}

sealed class PageNavigation {
  const PageNavigation();
}

final class NextPage extends PageNavigation {
  const NextPage(this.page);

  final int page;
}

final class PageEnd extends PageNavigation {
  const PageEnd(this.reason);

  final SearchEndReason reason;
}

enum SearchEndReason { exhausted, githubLimitReached }
