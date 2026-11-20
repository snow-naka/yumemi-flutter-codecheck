import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/spikes/search_notifier/search_controller.dart';
import 'package:yumemi_app/spikes/search_notifier/search_state.dart';

import '../../search/search_test_support.dart';

void main() {
  late ProviderContainer container;
  late SpikeSearchController controller;

  late List<String> queries;
  late List<Completer<SearchPage>> requests;

  setUp(() {
    queries = [];
    requests = [];

    final fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) {
        queries.add(query);

        final completer = Completer<SearchPage>();
        requests.add(completer);

        return completer.future;
      },
    );

    container = ProviderContainer.test(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
    );

    controller = container.read(spikeSearchControllerProvider.notifier);
  });

  test('T01: 初回検索が成功する', () async {
    final task = controller.search(' flutter ');

    expect(queries, ['flutter']);

    final loading = container.read(spikeSearchControllerProvider);

    expect(loading, isA<SearchLoading>());
    expect((loading as SearchLoading).query, 'flutter');

    requests.single.complete(resultPage(count: 2));

    await task;

    final result = container.read(spikeSearchControllerProvider);

    expect(result, isA<SearchResults>());

    final success = result as SearchResults;
    expect(success.query, 'flutter');
    expect(success.items, hasLength(2));
    expect(success.loadedPage, 1);
  });

  test('T02: キャンセル後に古い結果を無視する', () async {
    final task = controller.search('flutter');

    expect(container.read(spikeSearchControllerProvider), isA<SearchLoading>());

    controller.cancel();

    expect(container.read(spikeSearchControllerProvider), isA<SearchIdle>());

    // キャンセル済みFutureを後から完了させる。
    requests.single.complete(resultPage());

    await task;

    expect(container.read(spikeSearchControllerProvider), isA<SearchIdle>());
  });

  test('T03: 同じ検索語の古い応答を破棄する', () async {
    final taskA = controller.search('flutter');

    controller.cancel();

    final taskB = controller.search('flutter');

    expect(queries, ['flutter', 'flutter']);

    final loadingB = container.read(spikeSearchControllerProvider);

    expect(loadingB, isA<SearchLoading>());

    // キャンセルされたAが先に完了。
    requests[0].complete(resultPage(count: 1));

    await taskA;

    // BはまだLoadingのまま。
    expect(container.read(spikeSearchControllerProvider), same(loadingB));

    // Bを正常完了させる。
    requests[1].complete(resultPage(count: 2));

    await taskB;

    final result = container.read(spikeSearchControllerProvider);

    expect(result, isA<SearchResults>());

    final success = result as SearchResults;

    expect(success.query, 'flutter');
    expect(success.items, hasLength(2));
  });
}
