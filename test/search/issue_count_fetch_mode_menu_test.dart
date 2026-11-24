import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/features/detail/issue_count_fetch_preferences.dart';
import 'package:yumemi_app/features/search/search_layout_preferences.dart';
import 'package:yumemi_app/main.dart';
import 'package:yumemi_app/providers.dart';

import 'search_test_support.dart';

final class _FakeIssueCountFetchModeStore implements IssueCountFetchModeStore {
  IssueCountFetchMode saved = IssueCountFetchMode.automatic;

  bool failRead = false;
  bool failWrite = false;

  int readCalls = 0;
  final writes = <IssueCountFetchMode>[];

  Completer<void>? readGate;
  Completer<void>? writeGate;

  @override
  Future<IssueCountFetchMode> read() async {
    readCalls++;

    final gate = readGate;
    if (gate != null) {
      await gate.future;
    }

    if (failRead) {
      throw StateError('Read failed');
    }

    return saved;
  }

  @override
  Future<void> write(IssueCountFetchMode mode) async {
    writes.add(mode);

    final gate = writeGate;
    if (gate != null) {
      await gate.future;
    }

    if (failWrite) {
      throw StateError('Write failed');
    }

    saved = mode;
  }
}

final class _FakeLayoutStore implements SearchPanelPositionStore {
  SearchPanelPosition saved = SearchPanelPosition.top;

  @override
  Future<SearchPanelPosition> read() async => saved;

  @override
  Future<void> write(SearchPanelPosition position) async {
    saved = position;
  }
}

void main() {
  late _FakeIssueCountFetchModeStore store;
  late _FakeLayoutStore layoutStore;
  late List<String> queries;

  final menu = find.byKey(const Key('issue-count-fetch-mode-menu'));

  final automaticItem = find.byKey(const Key('issue-fetch-mode-automatic'));

  final manualItem = find.byKey(const Key('issue-fetch-mode-manual'));

  setUp(() {
    store = _FakeIssueCountFetchModeStore();
    layoutStore = _FakeLayoutStore();
    queries = [];
  });

  Future<void> start(
    WidgetTester tester, {
    Locale locale = const Locale('ja', 'JP'),
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final gateway = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) async {
        queries.add(query);
        return resultPage();
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          githubRepositoryGatewayProvider.overrideWithValue(gateway),
          searchPanelPositionStoreProvider.overrideWithValue(layoutStore),
          issueCountFetchModeStoreProvider.overrideWithValue(store),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();
  }

  bool menuEnabled(WidgetTester tester) {
    return tester.widget<PopupMenuButton<IssueCountFetchMode>>(menu).enabled;
  }

  Future<void> openMenu(WidgetTester tester) async {
    expect(menuEnabled(tester), isTrue);

    await tester.tap(menu);
    await tester.pumpAndSettle();
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
  }

  void expectSelection(WidgetTester tester, IssueCountFetchMode mode) {
    final automatic = tester.widget<CheckedPopupMenuItem<IssueCountFetchMode>>(
      automaticItem,
    );

    final manual = tester.widget<CheckedPopupMenuItem<IssueCountFetchMode>>(
      manualItem,
    );

    expect(automatic.checked, mode == IssueCountFetchMode.automatic);

    expect(manual.checked, mode == IssueCountFetchMode.manual);
  }

  Future<void> selectMode(WidgetTester tester, IssueCountFetchMode mode) async {
    await tester.tap(
      mode == IssueCountFetchMode.automatic ? automaticItem : manualItem,
    );

    await tester.pumpAndSettle();
  }

  testWidgets('IU01: 初期設定では自動取得が選択される', (tester) async {
    await start(tester);
    await openMenu(tester);

    expectSelection(tester, IssueCountFetchMode.automatic);

    expect(store.writes, isEmpty);
    expect(queries, isEmpty);
  });

  testWidgets('IU02: 保存済みの手動取得が選択される', (tester) async {
    store.saved = IssueCountFetchMode.manual;

    await start(tester);
    await openMenu(tester);

    expectSelection(tester, IssueCountFetchMode.manual);

    expect(store.readCalls, 1);
    expect(store.writes, isEmpty);
  });

  testWidgets('IU03: 取得方式を切り替えて保存できる', (tester) async {
    await start(tester);

    await openMenu(tester);
    await selectMode(tester, IssueCountFetchMode.manual);

    expect(store.saved, IssueCountFetchMode.manual);

    await openMenu(tester);
    expectSelection(tester, IssueCountFetchMode.manual);

    await selectMode(tester, IssueCountFetchMode.automatic);

    expect(store.saved, IssueCountFetchMode.automatic);

    await openMenu(tester);
    expectSelection(tester, IssueCountFetchMode.automatic);

    expect(store.writes, [
      IssueCountFetchMode.manual,
      IssueCountFetchMode.automatic,
    ]);

    expect(queries, isEmpty);
  });

  testWidgets('IU04: 設定読み込み中はメニュー操作を禁止する', (tester) async {
    store.readGate = Completer<void>();
    store.saved = IssueCountFetchMode.manual;

    await start(tester);

    expect(menuEnabled(tester), isFalse);
    expect(store.writes, isEmpty);

    store.readGate!.complete();
    await tester.pumpAndSettle();

    expect(menuEnabled(tester), isTrue);

    await openMenu(tester);
    expectSelection(tester, IssueCountFetchMode.manual);
  });

  testWidgets('IU05: 設定保存中はメニュー操作を禁止する', (tester) async {
    store.writeGate = Completer<void>();

    await start(tester);
    await openMenu(tester);

    await selectMode(tester, IssueCountFetchMode.manual);

    expect(menuEnabled(tester), isFalse);
    expect(store.saved, IssueCountFetchMode.automatic);

    expect(store.writes, [IssueCountFetchMode.manual]);

    store.writeGate!.complete();
    await tester.pumpAndSettle();

    expect(menuEnabled(tester), isTrue);
    expect(store.saved, IssueCountFetchMode.manual);

    await openMenu(tester);
    expectSelection(tester, IssueCountFetchMode.manual);
  });

  testWidgets('IU06: 保存失敗時は変更前の設定を維持して通知する', (tester) async {
    store.failWrite = true;

    await start(tester);
    await openMenu(tester);

    await selectMode(tester, IssueCountFetchMode.manual);

    expect(find.text('Issue数の取得方式を保存できませんでした。'), findsOneWidget);

    expect(store.saved, IssueCountFetchMode.automatic);
    expect(menuEnabled(tester), isTrue);

    await openMenu(tester);
    expectSelection(tester, IssueCountFetchMode.automatic);

    // 保存失敗後も再試行できる。
    store.failWrite = false;

    await selectMode(tester, IssueCountFetchMode.manual);

    expect(store.saved, IssueCountFetchMode.manual);
  });

  testWidgets('IU07: 読み込み失敗時は手動取得にして再設定を許可する', (tester) async {
    store.failRead = true;

    await start(tester);
    await openMenu(tester);

    expectSelection(tester, IssueCountFetchMode.manual);

    const message = '取得方式を読み込めなかったため、手動取得にしています。';

    expect(find.text(message), findsOneWidget);
    expect(store.writes, isEmpty);

    // フォールバックと同じ設定でも明示的な選択は保存する。
    await selectMode(tester, IssueCountFetchMode.manual);

    expect(store.saved, IssueCountFetchMode.manual);
    expect(store.writes, [IssueCountFetchMode.manual]);

    await openMenu(tester);

    expectSelection(tester, IssueCountFetchMode.manual);
    expect(find.text(message), findsNothing);
  });

  testWidgets('IU08: 英語で取得方式を表示できる', (tester) async {
    await start(tester, locale: const Locale('en', 'US'));

    await openMenu(tester);

    expect(find.text('Open issue count fetch mode'), findsOneWidget);

    expect(find.text('Automatic (on opening details)'), findsOneWidget);

    expect(find.text('Manual (on demand)'), findsOneWidget);

    expectSelection(tester, IssueCountFetchMode.automatic);
  });

  testWidgets('IU09: 言語・テーマ変更時も取得方式を維持する', (tester) async {
    await start(tester);

    await openMenu(tester);
    await selectMode(tester, IssueCountFetchMode.manual);

    // 英語へ変更。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    await openMenu(tester);

    expectSelection(tester, IssueCountFetchMode.manual);

    expect(find.text('Manual (on demand)'), findsOneWidget);

    await closeMenu(tester);

    // ダークモードへ変更。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

    await tester.pumpAndSettle();

    expect(Theme.of(tester.element(menu)).brightness, Brightness.dark);

    await openMenu(tester);

    expectSelection(tester, IssueCountFetchMode.manual);

    expect(store.readCalls, 1);
    expect(store.writes, [IssueCountFetchMode.manual]);
    expect(queries, isEmpty);
  });

  testWidgets('IU10: 取得方式変更時も検索状態と入力を維持する', (tester) async {
    await start(tester);

    final input = find.byType(TextFormField);

    await tester.enterText(input, 'first');

    await tester.tap(find.byKey(const Key('search-submit-button')));

    await tester.pumpAndSettle();

    expect(queries, ['first']);
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('送信済みの検索語：first'), findsOneWidget);

    // 送信済みの検索語とは異なる入力途中の文字列。
    await tester.enterText(input, 'second');

    await openMenu(tester);
    await selectMode(tester, IssueCountFetchMode.manual);

    expect(store.saved, IssueCountFetchMode.manual);

    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('送信済みの検索語：first'), findsOneWidget);

    expect(tester.widget<TextFormField>(input).controller!.text, 'second');

    // 設定変更によって検索APIが再実行されない。
    expect(queries, ['first']);
  });
}
