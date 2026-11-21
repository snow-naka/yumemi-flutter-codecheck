import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/models/repository_models.dart';

void main() {
  const summary = RepositorySummary(
    key: RepositoryKey(id: 1, owner: 'test', name: 'repo'),
    avatarUrl: '',
    language: 'Dart',
    starCount: 0,
    forkCount: 0,
    openIssueAndPullRequestCount: 0,
  );

  SearchPage makePage({
    int page = 1,
    int perPage = 2,
    int totalCount = 2,
    List<RepositorySummary>? items,
    bool incomplete = false,
    PageNavigation navigation = const PageEnd(SearchEndReason.exhausted),
  }) {
    return SearchPage(
      items: items ?? [summary],
      totalCount: totalCount,
      incompleteResults: incomplete,
      page: page,
      perPage: perPage,
      navigation: navigation,
    );
  }

  test('valid next page', () {
    final page = makePage(navigation: const NextPage(2));

    expect(page.navigation, isA<NextPage>());
    expect((page.navigation as NextPage).page, 2);
  });

  test('valid empty later page', () {
    final page = makePage(page: 2, totalCount: 99, items: []);

    expect(page.items, isEmpty);
    expect(page.totalCount, 99);
    expect(page.navigation, isA<PageEnd>());
  });

  test('incomplete result is allowed', () {
    final page = makePage(incomplete: true);

    expect(page.incompleteResults, isTrue);
  });

  test('invalid page is rejected', () {
    expect(() => makePage(page: 0), throwsArgumentError);
  });

  test('invalid perPage is rejected', () {
    expect(() => makePage(perPage: 0), throwsArgumentError);
    expect(() => makePage(perPage: 101), throwsArgumentError);
  });

  test('negative totalCount is rejected', () {
    expect(() => makePage(totalCount: -1), throwsArgumentError);
  });

  test('too many items are rejected', () {
    expect(
      () => makePage(perPage: 1, items: [summary, summary]),
      throwsArgumentError,
    );
  });

  test('NextPage must point to the next page', () {
    expect(() => makePage(navigation: const NextPage(3)), throwsArgumentError);
  });

  test('items are copied and unmodifiable', () {
    final source = [summary];
    final page = makePage(items: source);

    source.clear();

    expect(page.items, hasLength(1));
    expect(() => page.items.add(summary), throwsUnsupportedError);
  });
}
