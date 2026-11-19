import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/features/detail/repository_detail_provider.dart';
import 'package:yumemi_app/features/detail/repository_detail_screen.dart';
import 'package:yumemi_app/features/search/search_controller.dart';
import 'package:yumemi_app/features/search/search_state.dart';
import 'package:yumemi_app/main.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';

import '../search/search_test_support.dart';

void main() {
  late List<String> searches;
  late List<RepositoryKey> keys;
  late List<Completer<RepositoryDetail>> requests;
  late FakeGitHubRepositoryGateway fake;
  setUp(() {
    searches = [];
    keys = [];
    requests = [];
    fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) async {
        searches.add(query);
        return resultPage(count: 30);
      },
      detailHandler: (key) {
        keys.add(key);
        final pending = Completer<RepositoryDetail>();
        requests.add(pending);
        return pending.future;
      },
    );
  });

  Future<ProviderContainer> start(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
        child: const MyApp(),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'submitted');
    await tester.tap(find.widgetWithText(FilledButton, '検索'));
    await tester.pump();
    return tester.container();
  }

  Future<void> open(WidgetTester tester, {String name = 'repository-0'}) async {
    await tester.tap(find.text(name));
    await tester.pump();
    final route = ModalRoute.of(
      tester.element(find.byType(RepositoryDetailScreen, skipOffstage: false)),
    )!;
    // インジケーターは動き続けるため、画面遷移の完了だけを待つ。
    for (
      var frame = 0;
      route.animation!.status != AnimationStatus.completed && frame < 200;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.pump();
  }

  Future<void> back(WidgetTester tester) async {
    final route = ModalRoute.of(
      tester.element(find.byType(RepositoryDetailScreen)),
    )!;
    final animation = route.animation!;
    await tester.pageBack();
    for (
      var frame = 0;
      animation.status != AnimationStatus.dismissed && frame < 200;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(animation.status, AnimationStatus.dismissed);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('selected summary is shown while only its detail is pending', (
    tester,
  ) async {
    final container = await start(tester);
    final searchState =
        container.read(searchControllerProvider) as SearchSuccess;
    await open(tester);
    expect(keys, [searchState.result.items.first.key]);
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('言語：Dart'), findsOneWidget);
    expect(find.text('詳細情報を取得中…'), findsOneWidget);
    expect(find.textContaining('Watcher数：'), findsNothing);
    expect(find.textContaining('Star数：'), findsNothing);
    final old = searchState.result.items.first;
    final updated = RepositorySummary(
      key: old.key,
      avatarUrl: '',
      language: 'Rust',
      starCount: 321,
      forkCount: 12,
      openIssueAndPullRequestCount: 7,
    );
    requests.single.complete(
      RepositoryDetail(summary: updated, watcherCount: 8),
    );
    await tester.pump();
    expect(find.text('言語：Rust'), findsOneWidget);
    expect(find.text('Star数：321'), findsOneWidget);
    expect(find.text('Watcher数：8'), findsOneWidget);
    expect(find.text('Open Issue＋PR数：7'), findsOneWidget);
    expect(container.read(searchControllerProvider), same(searchState));
    expect(searches, ['submitted']);
  });

  testWidgets(
    'failure stays visible without auto retry; manual retry changes only detail',
    (tester) async {
      final container = await start(tester);
      final searchState =
          container.read(searchControllerProvider) as SearchSuccess;
      await open(tester);
      requests.single.completeError(
        const ApiFailure(kind: ApiFailureKind.network, safeMessage: '仮の詳細取得失敗'),
      );
      await tester.pump();
      expect(find.text('仮の詳細取得失敗'), findsOneWidget);
      expect(find.text('repository-0'), findsOneWidget);
      expect(find.textContaining('Watcher数：'), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(keys, hasLength(1));
      expect(container.read(searchControllerProvider), same(searchState));
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(keys, hasLength(2));
      expect(find.text('詳細情報を取得中…'), findsOneWidget);
      expect(find.text('仮の詳細取得失敗'), findsNothing);
      requests.last.complete(
        RepositoryDetail(
          summary: searchState.result.items.first,
          watcherCount: 8,
        ),
      );
      await tester.pump();
      expect(find.text('Watcher数：8'), findsOneWidget);
      expect(container.read(searchControllerProvider), same(searchState));
      expect(searches, ['submitted']);
    },
  );

  testWidgets(
    'return preserves submitted query, draft, results and exact scroll offset',
    (tester) async {
      final container = await start(tester);
      await tester.scrollUntilVisible(
        find.text('repository-12'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'unsubmitted draft');
      await tester.pump();
      final offset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      final searchState =
          container.read(searchControllerProvider) as SearchSuccess;
      await open(tester, name: 'repository-12');
      requests.single.completeError(
        const ApiFailure(
          kind: ApiFailureKind.network,
          safeMessage: 'detail failed',
        ),
      );
      await tester.pump();
      await back(tester);
      expect(container.read(searchControllerProvider), same(searchState));
      expect(find.text('送信済みの検索語：submitted'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'unsubmitted draft',
      );
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        offset,
      );
      expect(offset, greaterThan(0));
      expect(searches, ['submitted']);
    },
  );

  testWidgets(
    'leaving during loading discards late response and reopening refetches',
    (tester) async {
      final container = await start(tester);
      final searchState =
          container.read(searchControllerProvider) as SearchSuccess;
      final summary = searchState.result.items.first;
      await open(tester);
      await back(tester);
      expect(
        container.read(repositoryDetailProvider(summary.key).exists),
        isFalse,
      );
      await open(tester);
      expect(keys, hasLength(2));
      requests.first.complete(
        RepositoryDetail(summary: summary, watcherCount: 99),
      );
      await tester.pump();
      expect(find.text('詳細情報を取得中…'), findsOneWidget);
      expect(find.text('Watcher数：99'), findsNothing);
      requests.last.complete(
        RepositoryDetail(summary: summary, watcherCount: 8),
      );
      await tester.pump();
      expect(find.text('Watcher数：8'), findsOneWidget);
      expect(searches, ['submitted']);
    },
  );

  testWidgets('closing a successful detail clears its cache before reopening', (
    tester,
  ) async {
    final container = await start(tester);
    final summary = (container.read(
      searchControllerProvider,
    ) as SearchSuccess).result.items.first;
    await open(tester);
    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();
    await back(tester);
    expect(
      container.read(repositoryDetailProvider(summary.key).exists),
      isFalse,
    );
    await open(tester);
    expect(keys, hasLength(2));
    expect(find.textContaining('Watcher数：'), findsNothing);
    requests.last.complete(RepositoryDetail(summary: summary, watcherCount: 9));
    await tester.pump();
    expect(find.text('Watcher数：9'), findsOneWidget);
  });

  testWidgets('unexpected detail errors do not claim to be network failures', (
    tester,
  ) async {
    final container = await start(tester);
    final searchState = container.read(searchControllerProvider);
    await open(tester);
    requests.single.completeError(StateError('internal bug'));
    await tester.pump();
    expect(find.text('詳細情報の処理中に問題が発生しました。'), findsOneWidget);
    expect(find.textContaining('internal bug'), findsNothing);
    expect(container.read(searchControllerProvider), same(searchState));
  });

  testWidgets(
    'default Fake detail retries explicitly and displays zero and null values',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            githubRepositoryGatewayProvider.overrideWithValue(
              FakeGitHubRepositoryGateway(delay: Duration.zero),
            ),
          ],
          child: const MyApp(),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'riverpod');
      await tester.tap(find.widgetWithText(FilledButton, '検索'));
      await tester.pump();
      final container = tester.container();
      final searchState = container.read(searchControllerProvider);
      await open(tester, name: 'riverpod-sample');
      expect(find.text('言語：未指定'), findsOneWidget);
      expect(find.text('仮の詳細取得失敗です。再試行してください。'), findsOneWidget);
      expect(find.textContaining('Watcher数：'), findsNothing);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(find.text('Star数：0'), findsOneWidget);
      expect(find.text('Watcher数：0'), findsOneWidget);
      expect(find.text('Fork数：0'), findsOneWidget);
      expect(find.text('Open Issue＋PR数：0'), findsOneWidget);
      expect(container.read(searchControllerProvider), same(searchState));
      await back(tester);
      expect(find.text('送信済みの検索語：riverpod'), findsOneWidget);
    },
  );
}
