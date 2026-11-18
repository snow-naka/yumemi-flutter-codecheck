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
  }) : items = List.unmodifiable(items);

  final List<RepositorySummary> items;
  final int totalCount;
  final bool incompleteResults;
  final int page;
  final int perPage;
}
