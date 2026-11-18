import 'package:yumemi_app/models/repository_models.dart';

SearchPage resultPage({int count = 1, bool incomplete = false}) => SearchPage(
  items: List.generate(
    count,
    (index) => RepositorySummary(
      key: RepositoryKey(id: index, owner: 'test', name: 'repository-$index'),
      avatarUrl: '',
      language: index == 0 ? 'Dart' : null,
      starCount: 120,
      forkCount: 12,
      openIssueAndPullRequestCount: 7,
    ),
  ),
  totalCount: count,
  incompleteResults: incomplete,
  page: 1,
  perPage: 30,
);
