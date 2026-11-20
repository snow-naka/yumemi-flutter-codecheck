import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/data/github_repository_gateway.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';

void main() {
  late GitHubRepositoryGateway gateway;
  setUp(() {
    gateway = FakeGitHubRepositoryGateway(delay: Duration.zero);
  });

  test('search and detail keep stars and watchers distinct', () async {
    final page = await gateway.searchRepositories('flutter');
    expect(page.items, hasLength(1));
    final summary = page.items.single;
    final equivalentKey = RepositoryKey(
      id: summary.key.id,
      owner: summary.key.owner,
      name: summary.key.name,
    );
    expect({summary.key: 'selected'}[equivalentKey], 'selected');
    final detail = await gateway.getRepository(equivalentKey);
    expect(detail.summary.key, summary.key);
    expect(detail.summary.starCount, 120);
    expect(detail.watcherCount, 8);
    expect(detail.summary.openIssueAndPullRequestCount, 7);
  });

  test('zero results and incomplete zero results remain successes', () async {
    final empty = await gateway.searchRepositories('empty');
    expect(empty.items, isEmpty);
    expect(empty.totalCount, 0);
    expect(empty.incompleteResults, isFalse);
    final partial = await gateway.searchRepositories(
      'incomplete',
      page: 3,
      perPage: 1,
    );
    expect(partial.items, isEmpty);
    expect(partial.totalCount, 2);
    expect(partial.incompleteResults, isTrue);
  });

  test('pagination preserves total count and request information', () async {
    final first = await gateway.searchRepositories('example', perPage: 1);
    final second = await gateway.searchRepositories(
      'example',
      page: 2,
      perPage: 1,
    );
    expect(first.totalCount, 2);
    expect(second.totalCount, 2);
    expect(second.page, 2);
    expect(second.perPage, 1);
    expect(first.items.single.key, isNot(second.items.single.key));
    expect(second.items.single.language, isNull);
    expect(second.items.single.starCount, 0);
  });

  test('search failure is a typed exception, not an empty page', () async {
    await expectLater(
      gateway.searchRepositories('error'),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', ApiFailureKind.network),
      ),
    );
  });

  test(
    'detail fails once and succeeds only on a subsequent explicit call',
    () async {
      final summary = (await gateway.searchRepositories('riverpod'))
          .items
          .single;
      await expectLater(
        gateway.getRepository(summary.key),
        throwsA(isA<ApiFailure>()),
      );
      final detail = await gateway.getRepository(summary.key);
      expect(detail.summary.key, summary.key);
      expect(detail.watcherCount, 0);
      // A fresh Fake has its own scripted failure, not shared global state.
      final fresh = FakeGitHubRepositoryGateway(delay: Duration.zero);
      await expectLater(
        fresh.getRepository(summary.key),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test('unknown repository does not become dummy detail data', () async {
    await expectLater(
      gateway.getRepository(
        const RepositoryKey(id: 999, owner: 'missing', name: 'missing'),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.notFoundOrUnavailable,
        ),
      ),
    );
  });

  test('search handler receives input and controls completion', () async {
    final pending = Completer<SearchPage>();
    var calls = 0;
    var completed = false;
    final controlled = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) {
        calls++;
        expect(query, 'controlled');
        expect(page, 2);
        expect(perPage, 5);
        return pending.future;
      },
    );
    final result = controlled.searchRepositories(
      'controlled',
      page: 2,
      perPage: 5,
    )..then((_) => completed = true);
    await Future<void>.value();
    expect(calls, 1);
    expect(completed, isFalse);
    final page = SearchPage(
      items: [],
      totalCount: 0,
      incompleteResults: false,
      page: 2,
      perPage: 5,
      navigation: const PageEnd(SearchEndReason.exhausted),
    );
    pending.complete(page);
    expect(await result, same(page));
  });

  test(
    'detail handler controls failure without default scripted behavior',
    () async {
      const key = RepositoryKey(id: 42, owner: 'test', name: 'controlled');
      const failure = ApiFailure(
        kind: ApiFailureKind.network,
        safeMessage: 'test failure',
      );
      final pending = Completer<RepositoryDetail>();
      final controlled = FakeGitHubRepositoryGateway(
        detailHandler: (received) {
          expect(received, key);
          return pending.future;
        },
      );
      final result = controlled.getRepository(key);
      final assertion = expectLater(result, throwsA(same(failure)));
      pending.completeError(failure);
      await assertion;
    },
  );

  test('search page owns an unmodifiable copy of the input list', () async {
    final items = [...(await gateway.searchRepositories('example')).items];
    final page = SearchPage(
      items: items,
      totalCount: 2,
      incompleteResults: false,
      page: 1,
      perPage: 30,
      navigation: const PageEnd(SearchEndReason.exhausted),
    );
    items.clear();
    expect(page.items, hasLength(2));
    expect(() => page.items.clear(), throwsUnsupportedError);
  });

  test(
    'invalid paging is a programming error, not a simulated network failure',
    () async {
      for (final perPage in [0, 101]) {
        await expectLater(
          gateway.searchRepositories('flutter', perPage: perPage),
          throwsArgumentError,
        );
      }
      await expectLater(
        gateway.searchRepositories('flutter', page: 0),
        throwsArgumentError,
      );
    },
  );

  test('F01: 5件を2件ずつ取得し、最後に終了する', () async {
    final fake = FakeGitHubRepositoryGateway(
      delay: Duration.zero,
      searchSummaries: _buildSearchItems(5),
    );

    final first = await fake.searchRepositories('sample', page: 1, perPage: 2);
    final second = await fake.searchRepositories('sample', page: 2, perPage: 2);
    final third = await fake.searchRepositories('sample', page: 3, perPage: 2);

    expect(first.items, hasLength(2));
    expect(second.items, hasLength(2));
    expect(third.items, hasLength(1));

    expect(first.navigation, isA<NextPage>().having((n) => n.page, 'page', 2));
    expect(second.navigation, isA<NextPage>().having((n) => n.page, 'page', 3));
    expect(
      third.navigation,
      isA<PageEnd>().having(
        (n) => n.reason,
        'reason',
        SearchEndReason.exhausted,
      ),
    );
  });

  test('F04: 1000件ちょうどなら通常の終端になる', () async {
    final fake = FakeGitHubRepositoryGateway(
      delay: Duration.zero,
      searchSummaries: _buildSearchItems(1000),
    );

    final last = await fake.searchRepositories(
      'sample',
      page: 10,
      perPage: 100,
    );

    expect(last.totalCount, 1000);
    expect(last.items, hasLength(100));
    expect(
      last.navigation,
      isA<PageEnd>().having(
        (n) => n.reason,
        'reason',
        SearchEndReason.exhausted,
      ),
    );
  });

  test('F05: 1001件なら1000件の取得上限で終了する', () async {
    final fake = FakeGitHubRepositoryGateway(
      delay: Duration.zero,
      searchSummaries: _buildSearchItems(1001),
    );

    final last = await fake.searchRepositories(
      'sample',
      page: 10,
      perPage: 100,
    );

    expect(last.totalCount, 1001);
    expect(last.items, hasLength(100));
    expect(
      last.navigation,
      isA<PageEnd>().having(
        (n) => n.reason,
        'reason',
        SearchEndReason.githubLimitReached,
      ),
    );
  });
}

List<RepositorySummary> _buildSearchItems(int count) {
  return List.generate(
    count,
    (index) => RepositorySummary(
      key: RepositoryKey(id: index + 1, owner: 'test', name: 'sample-$index'),
      avatarUrl: '',
      language: 'Dart',
      starCount: 0,
      forkCount: 0,
      openIssueAndPullRequestCount: 0,
    ),
  );
}
