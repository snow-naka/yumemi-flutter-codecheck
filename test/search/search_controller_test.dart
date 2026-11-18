import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/features/search/search_controller.dart';
import 'package:yumemi_app/features/search/search_state.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';

import 'search_test_support.dart';

void main() {
  late ProviderContainer container;
  late SearchController controller;
  late List<String> queries;
  late List<Completer<SearchPage>> requests;
  const failure = ApiFailure(kind: ApiFailureKind.network, safeMessage: '仮の失敗');

  setUp(() {
    queries = [];
    requests = [];
    final fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) {
        queries.add(query);
        final pending = Completer<SearchPage>();
        requests.add(pending);
        return pending.future;
      },
    );
    container = ProviderContainer.test(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
    );
    controller = container.read(searchControllerProvider.notifier);
  });

  test('initialization and blank input never start a request', () async {
    expect(container.read(searchControllerProvider), isA<SearchInitial>());
    await controller.search('   ');
    expect(container.read(searchControllerProvider), isA<SearchInitial>());
    expect(queries, isEmpty);
  });

  test(
    'submitted query is trimmed and loading waits for explicit completion',
    () async {
      final future = controller.search('  flutter  ');
      final loading = container.read(searchControllerProvider) as SearchLoading;
      expect(loading.query, 'flutter');
      expect(queries, ['flutter']);
      await Future<void>.value();
      expect(container.read(searchControllerProvider), same(loading));
      final result = resultPage();
      requests.single.complete(result);
      await future;
      final success = container.read(searchControllerProvider) as SearchSuccess;
      expect(success.query, 'flutter');
      expect(success.result, same(result));
    },
  );

  test('a second submission cannot start another pending search', () async {
    final first = controller.search('first');
    await controller.search('second');
    expect(queries, ['first']);
    expect(container.read(searchControllerProvider).query, 'first');
    requests.single.complete(resultPage());
    await first;
  });

  for (final incomplete in [false, true]) {
    test(
      'empty result is success and preserves incomplete=$incomplete',
      () async {
        final future = controller.search('empty');
        requests.single.complete(resultPage(count: 0, incomplete: incomplete));
        await future;
        final state = container.read(searchControllerProvider) as SearchSuccess;
        expect(state.result.items, isEmpty);
        expect(state.result.incompleteResults, incomplete);
      },
    );
  }

  for (final fails in [false, true]) {
    test(
      'blank input preserves the preceding state (failure=$fails)',
      () async {
        final future = controller.search('first');
        if (fails) {
          requests.single.completeError(failure);
        } else {
          requests.single.complete(resultPage());
        }
        await future;
        final previous = container.read(searchControllerProvider);
        await controller.search('  ');
        expect(container.read(searchControllerProvider), same(previous));
        expect(queries, ['first']);
      },
    );
  }

  test(
    'failure can be followed by a new search without old results or error',
    () async {
      final first = controller.search('first');
      requests.single.completeError(failure);
      await first;
      final failed = container.read(searchControllerProvider) as SearchFailure;
      expect(failed.failure, same(failure));
      expect(failed.query, 'first');
      final second = controller.search('second');
      expect(container.read(searchControllerProvider), isA<SearchLoading>());
      requests.last.complete(resultPage());
      await second;
      expect(container.read(searchControllerProvider), isA<SearchSuccess>());
      expect(container.read(searchControllerProvider).query, 'second');
    },
  );

  test(
    'old completion cannot overwrite state after provider invalidation',
    () async {
      final first = controller.search('old');
      container.invalidate(searchControllerProvider);
      expect(container.read(searchControllerProvider), isA<SearchInitial>());
      final second = container
          .read(searchControllerProvider.notifier)
          .search('new');
      requests.first.complete(resultPage());
      await first;
      expect(container.read(searchControllerProvider), isA<SearchLoading>());
      expect(container.read(searchControllerProvider).query, 'new');
      requests.last.complete(resultPage(count: 0));
      await second;
      expect(container.read(searchControllerProvider).query, 'new');
    },
  );

  test('completion after scope disposal is ignored', () async {
    final future = controller.search('pending');
    container.dispose();
    requests.single.completeError(failure);
    await future;
  });

  test(
    'programming errors are not relabeled as expected API failures',
    () async {
      final future = controller.search('bug');
      final assertion = expectLater(future, throwsStateError);
      requests.single.completeError(StateError('programming error'));
      await assertion;
      expect(
        container.read(searchControllerProvider),
        isNot(isA<SearchFailure>()),
      );
    },
  );
}
