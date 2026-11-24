import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/features/detail/repository_detail_provider.dart';
import 'package:yumemi_app/features/search/search_controller.dart';
import 'package:yumemi_app/features/search/search_state.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';

import '../search/search_test_support.dart';

void main() {
  late ProviderContainer container;
  late List<RepositoryKey> keys;
  late List<Completer<RepositoryDetail>> requests;
  late int searches;
  setUp(() {
    keys = [];
    requests = [];
    searches = 0;
    final fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) async {
        searches++;
        return resultPage(count: 2);
      },
      detailHandler: (key) {
        keys.add(key);
        final pending = Completer<RepositoryDetail>();
        requests.add(pending);
        return pending.future;
      },
    );
    container = ProviderContainer.test(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
    );
  });

  test('value-equal keys reuse one request; detail completion preserves search state', () async {
    await container.read(searchControllerProvider.notifier).search('first');
    final searchState =
        container.read(searchControllerProvider) as SearchResults;
    final summary = searchState.items.first;
    final provider = repositoryDetailProvider(summary.key);
    final first = container.listen(provider, (_, _) {});
    addTearDown(first.close);
    final equivalent = RepositoryKey(
      id: summary.key.id,
      owner: summary.key.owner,
      name: summary.key.name,
    );
    final second = container.listen(
      repositoryDetailProvider(equivalent),
      (_, _) {},
    );
    addTearDown(second.close);
    expect(keys, [summary.key]);
    expect(first.read().isLoading, isTrue);
    final detail = RepositoryDetail(summary: summary, watcherCount: 8);
    requests.single.complete(detail);
    await container.pump();
    expect(first.read().asData?.value, same(detail));
    expect(second.read().asData?.value, same(detail));
    expect(container.read(searchControllerProvider), same(searchState));
    expect(searches, 1);
  });

  test(
    'different detail keys have independent success and error states',
    () async {
      final summaries = resultPage(count: 2).items;
      final first = container.listen(
        repositoryDetailProvider(summaries[0].key),
        (_, _) {},
      );
      final second = container.listen(
        repositoryDetailProvider(summaries[1].key),
        (_, _) {},
      );
      addTearDown(first.close);
      addTearDown(second.close);
      const failure = ApiFailure(kind: ApiFailureKind.network);
      requests.first.completeError(failure);
      await container.pump();
      expect(first.read().asError?.error, same(failure));
      expect(second.read().isLoading, isTrue);
      requests.last.complete(
        RepositoryDetail(summary: summaries[1], watcherCount: 0),
      );
      await container.pump();
      expect(second.read().asData?.value.watcherCount, 0);
      expect(first.read().asError?.error, same(failure));
      expect(container.read(searchControllerProvider), isA<SearchIdle>());
      expect(searches, 0);
    },
  );

  test('disposal during loading ignores old success when the same detail is reopened', () async {
    final summary = resultPage().items.single;
    final provider = repositoryDetailProvider(summary.key);
    final first = container.listen(provider, (_, _) {});
    first.close();
    await container.pump();
    expect(container.read(provider.exists), isFalse);
    final second = container.listen(provider, (_, _) {});
    addTearDown(second.close);
    expect(keys, [summary.key, summary.key]);
    requests.first.complete(
      RepositoryDetail(summary: summary, watcherCount: 99),
    );
    await container.pump();
    expect(second.read().isLoading, isTrue);
    requests.last.complete(RepositoryDetail(summary: summary, watcherCount: 8));
    await container.pump();
    expect(second.read().asData?.value.watcherCount, 8);
  });

  test(
    'an error completing after disposal cannot affect another detail',
    () async {
      final summaries = resultPage(count: 2).items;
      final old = container.listen(
        repositoryDetailProvider(summaries[0].key),
        (_, _) {},
      );
      old.close();
      await container.pump();
      final current = container.listen(
        repositoryDetailProvider(summaries[1].key),
        (_, _) {},
      );
      addTearDown(current.close);
      requests.first.completeError(
        const ApiFailure(kind: ApiFailureKind.network),
      );
      await container.pump();
      expect(current.read().isLoading, isTrue);
      requests.last.complete(
        RepositoryDetail(summary: summaries[1], watcherCount: 0),
      );
      await container.pump();
      expect(current.read().asData?.value.watcherCount, 0);
      expect(searches, 0);
    },
  );

  test(
    'a new search does not refetch or overwrite existing detail state',
    () async {
      final summary = resultPage().items.single;
      final detail = container.listen(
        repositoryDetailProvider(summary.key),
        (_, _) {},
      );
      addTearDown(detail.close);
      await container
          .read(searchControllerProvider.notifier)
          .search('new query');
      expect(keys, [summary.key]);
      expect(detail.read().isLoading, isTrue);
      final searchState = container.read(searchControllerProvider);
      requests.single.complete(
        RepositoryDetail(summary: summary, watcherCount: 8),
      );
      await container.pump();
      expect(container.read(searchControllerProvider), same(searchState));
      expect(detail.read().asData?.value.watcherCount, 8);
    },
  );

  test('検索時のIDと異なる詳細応答を失敗として扱う', () async {
    final summaries = resultPage(count: 2).items;
    final provider = repositoryDetailProvider(summaries.first.key);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    requests.single.complete(
      RepositoryDetail(summary: summaries.last, watcherCount: 77),
    );
    await container.pump();

    final error = subscription.read().asError!.error;
    expect(
      error,
      isA<ApiFailure>().having(
        (failure) => failure.kind,
        'kind',
        ApiFailureKind.invalidResponse,
      ),
    );
  });
}
