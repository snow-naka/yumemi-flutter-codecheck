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
import 'package:yumemi_app/features/detail/repository_detail_cache.dart';

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
      const failure = ApiFailure(
        kind: ApiFailureKind.network,
        safeMessage: 'detail failed',
      );
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
        const ApiFailure(
          kind: ApiFailureKind.network,
          safeMessage: 'late failure',
        ),
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

  test('DC05: 詳細Providerは15分以内なら再利用し期限切れで再取得', () async {
    final start = DateTime.utc(2026, 11, 23, 12);
    var clock = start;

    final cache = RepositoryDetailCache(now: () => clock);

    const key = RepositoryKey(id: 101, owner: 'sample', name: 'example');

    var requestCount = 0;

    final gateway = FakeGitHubRepositoryGateway(
      detailHandler: (requestedKey) async {
        requestCount++;

        return RepositoryDetail(
          summary: RepositorySummary(
            key: requestedKey,
            avatarUrl: '',
            language: 'Dart',
            starCount: 10,
            forkCount: 2,
            openIssueAndPullRequestCount: 1,
          ),
          watcherCount: requestCount,
        );
      },
    );

    final testContainer = ProviderContainer.test(
      overrides: [
        githubRepositoryGatewayProvider.overrideWithValue(gateway),
        repositoryDetailCacheProvider.overrideWithValue(cache),
      ],
    );

    // 詳細画面を開いて閉じる操作に相当する。
    Future<int> openAndClose() async {
      final subscription = testContainer.listen(
        repositoryDetailProvider(key),
        (_, _) {},
      );

      await testContainer.pump();

      final watcherCount = subscription.read().asData!.value.watcherCount;

      subscription.close();
      await testContainer.pump();

      return watcherCount;
    }

    // 初回はHTTP Gateway相当の取得処理を呼ぶ。
    expect(await openAndClose(), 1);
    expect(requestCount, 1);

    // 14分後はキャッシュを利用。
    clock = start.add(const Duration(minutes: 14));

    expect(await openAndClose(), 1);
    expect(requestCount, 1);

    // 15分経過すると再取得する。
    clock = start.add(const Duration(minutes: 15));

    expect(await openAndClose(), 2);
    expect(requestCount, 2);
  });

  test('DC07: 無効化直後の古い応答をキャッシュしない', () async {
    final summary = resultPage().items.single;
    final key = summary.key;
    final cache = container.read(repositoryDetailCacheProvider);
    final provider = repositoryDetailProvider(key);

    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    // 要求Aを開始。
    expect(keys, [key]);
    expect(requests, hasLength(1));

    // Aの処理中にProviderを無効化。
    container.invalidate(provider);

    // この時点では新要求Bが始まっていない。
    expect(keys, [key]);

    // 古い要求Aを先に完了させる。
    requests[0].complete(RepositoryDetail(summary: summary, watcherCount: 99));
    await Future<void>.delayed(Duration.zero);

    // 失効したAの値はキャッシュに入らない。
    expect(cache.getFresh(key), isNull, reason: '無効化済みの要求Aをキャッシュしてはいけない');

    // 新しい評価ではキャッシュを使わず要求Bが必要。
    await container.pump();
    expect(keys, [key, key]);

    requests[1].complete(RepositoryDetail(summary: summary, watcherCount: 8));
    await container.pump();

    expect(subscription.read().asData?.value.watcherCount, 8);
    expect(cache.getFresh(key)?.watcherCount, 8);
  });

  test('DC08: 新要求の成功後に古い応答が来ても上書きしない', () async {
    final summary = resultPage().items.single;
    final key = summary.key;
    final cache = container.read(repositoryDetailCacheProvider);
    final provider = repositoryDetailProvider(key);

    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    // 要求Aを開始。
    expect(keys, [key]);

    // Aの完了前に無効化して要求Bを開始。
    container.invalidate(provider);
    await container.pump();

    expect(keys, [key, key]);
    expect(requests, hasLength(2));

    // 新しい要求Bが先に成功。
    requests[1].complete(RepositoryDetail(summary: summary, watcherCount: 42));
    await container.pump();

    expect(subscription.read().asData?.value.watcherCount, 42);
    expect(cache.getFresh(key)?.watcherCount, 42);

    // その後、古い要求Aが成功しても影響しない。
    requests[0].complete(RepositoryDetail(summary: summary, watcherCount: 99));
    await container.pump();

    expect(
      subscription.read().asData?.value.watcherCount,
      42,
      reason: '画面のProvider値が古い応答に戻らない',
    );
    expect(cache.getFresh(key)?.watcherCount, 42, reason: 'キャッシュも新しい応答を維持する');
  });
}
