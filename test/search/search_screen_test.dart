import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/main.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/features/search/viewed_repository_provider.dart';
import 'package:yumemi_app/features/detail/repository_detail_screen.dart';
import 'package:yumemi_app/features/search/search_layout_preferences.dart';

import 'search_test_support.dart';

final class _FakeSearchPanelPositionStore implements SearchPanelPositionStore {
  SearchPanelPosition saved = SearchPanelPosition.top;
  bool failWrites = false;
  final writes = <SearchPanelPosition>[];

  @override
  Future<SearchPanelPosition> read() async => saved;

  @override
  Future<void> write(SearchPanelPosition position) async {
    writes.add(position);

    if (failWrites) {
      throw StateError('テスト用の保存失敗');
    }

    saved = position;
  }
}

void main() {
  late List<String> queries;
  late List<Completer<SearchPage>> requests;
  late FakeGitHubRepositoryGateway fake;
  late _FakeSearchPanelPositionStore layoutStore;
  final input = find.byType(TextFormField);
  final submit = find.byKey(const Key('search-submit-button'));

  setUp(() {
    queries = [];
    requests = [];
    layoutStore = _FakeSearchPanelPositionStore();
    fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) {
        queries.add(query);
        final pending = Completer<SearchPage>();
        requests.add(pending);
        return pending.future;
      },
    );
  });

  Future<void> start(
    WidgetTester tester, {
    Locale locale = const Locale('ja', 'JP'),
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];

    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
        child: const MyApp(),
      ),
    );
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(input, query);
    await tester.tap(submit);
    await tester.pump();
  }

  Future<void> startWithLayout(
    WidgetTester tester, {
    Locale locale = const Locale('ja', 'JP'),
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];

    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          githubRepositoryGatewayProvider.overrideWithValue(fake),
          searchPanelPositionStoreProvider.overrideWithValue(layoutStore),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pump();
  }

  Future<void> choosePosition(
    WidgetTester tester,
    SearchPanelPosition position,
  ) async {
    await tester.tap(find.byKey(const Key('search-layout-menu')));
    await tester.pumpAndSettle();

    final label = position == SearchPanelPosition.top ? '上に配置（標準）' : '下に配置';

    // Textではなく、タップ対象のメニュー項目を指定する。
    final menuItem = find.widgetWithText(
      CheckedPopupMenuItem<SearchPanelPosition>,
      label,
    );

    expect(menuItem, findsOneWidget);
    await tester.tap(menuItem);
    await tester.pumpAndSettle();
  }

  final localizedLayoutCases = [
    for (final locale in const [Locale('ja', 'JP'), Locale('en', 'US')])
      for (final position in SearchPanelPosition.values) (position, locale),
  ];
  testWidgets('initial view and blank submission do not call the gateway', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('キーワードを入力して検索してください。'), findsOneWidget);
    await search(tester, '  ');
    expect(find.text('検索キーワードを入力してください。'), findsOneWidget);
    expect(queries, isEmpty);
  });

  testWidgets(
    'pending search allows editing but rejects button and keyboard resubmission',
    (tester) async {
      await start(tester);
      await search(tester, '  first  ');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<IconButton>(submit).onPressed, isNull);
      await tester.enterText(input, 'second');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.tap(submit);
      await tester.pump();
      expect(queries, ['first']);
      expect(find.text('送信済みの検索語：first'), findsOneWidget);
      requests.single.complete(resultPage());
      await tester.pump();
      expect(find.text('repository-0'), findsOneWidget);
      expect(find.text('送信済みの検索語：first'), findsOneWidget);
      expect(tester.widget<TextFormField>(input).controller!.text, 'second');
      expect(tester.widget<IconButton>(submit).onPressed, isNotNull);
      // 最初の送信でフォーカスが外れるので、次の入力操作を開始する。
      await tester.tap(input);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(queries, ['first', 'second']);
      expect(find.text('repository-0'), findsNothing);
      requests.last.complete(resultPage(count: 0));
      await tester.pump();
      expect(find.text('一致するリポジトリは見つかりませんでした。'), findsOneWidget);
      expect(find.text('送信済みの検索語：second'), findsOneWidget);
    },
  );

  testWidgets(
    'blank input preserves results and editing does not change their submitted query',
    (tester) async {
      await start(tester);
      await search(tester, 'first');
      requests.single.complete(resultPage());
      await tester.pump();
      await search(tester, '  ');
      expect(find.text('検索キーワードを入力してください。'), findsOneWidget);
      expect(find.text('repository-0'), findsOneWidget);
      expect(find.text('送信済みの検索語：first'), findsOneWidget);
      expect(queries, ['first']);
    },
  );

  for (final count in [0, 2]) {
    testWidgets(
      'incomplete results are distinguished from complete absence (count=$count)',
      (tester) async {
        await start(tester);
        await search(tester, 'partial');
        requests.single.complete(resultPage(count: count, incomplete: true));
        await tester.pump();
        expect(find.text('検索結果が不完全な可能性があります。'), findsOneWidget);
        expect(find.text('一致するリポジトリは見つかりませんでした。'), findsNothing);
        if (count > 0) {
          expect(find.text('repository-0'), findsOneWidget);
          expect(find.text('test/repository-1 / 未指定'), findsOneWidget);
        } else {
          expect(find.text('表示できる結果がありません。検索結果が不完全な可能性があります。'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'manual retry uses the failed query while leaving the edited draft intact',
    (tester) async {
      await start(tester);
      await search(tester, 'failed');
      requests.single.completeError(
        const ApiFailure(kind: ApiFailureKind.network),
      );
      await tester.pump();
      expect(find.text('GitHubとの通信に失敗しました。'), findsOneWidget);
      expect(tester.widget<IconButton>(submit).onPressed, isNotNull);
      await tester.enterText(input, 'edited');
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(queries, ['failed', 'failed']);
      expect(find.text('GitHubとの通信に失敗しました。'), findsNothing);
      expect(tester.widget<TextFormField>(input).controller!.text, 'edited');
      requests.last.complete(resultPage());
      await tester.pump();
      expect(find.text('repository-0'), findsOneWidget);
    },
  );

  testWidgets('a new search resets the result scroll position', (tester) async {
    await start(tester);
    await search(tester, 'long');
    requests.single.complete(resultPage(count: 30));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    final oldList = tester.widget<ListView>(find.byType(ListView));
    expect(oldList.controller!.offset, greaterThan(0));
    await search(tester, 'new');
    requests.last.complete(resultPage(count: 30));
    await tester.pump();
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      0,
    );
    expect(find.text('repository-0'), findsOneWidget);
  });
  testWidgets('追加読み込みで既存一覧を保持して結果を増やす', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    // 1ページ目：2件取得、次ページあり
    requests[0].complete(
      SearchPage(
        items: resultPage(count: 2).items,
        totalCount: 3,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const NextPage(2),
      ),
    );

    await tester.pump();

    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('もっと読み込む'), findsOneWidget);

    // 追加読み込みボタンを押す
    await tester.tap(find.text('もっと読み込む'));
    await tester.pump();

    expect(queries, ['flutter', 'flutter']);
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('追加読み込み中…'), findsOneWidget);

    // 2ページ目：1件追加、最終ページ
    requests[1].complete(
      SearchPage(
        items: [resultPage(count: 3).items.last],
        totalCount: 3,
        incompleteResults: false,
        page: 2,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-2'), findsOneWidget);
    expect(find.text('これ以上の結果はありません。'), findsOneWidget);
  });
  testWidgets('追加読み込み失敗後に既存結果を保持して再試行できる', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    // 1ページ目は成功
    requests[0].complete(
      SearchPage(
        items: resultPage(count: 2).items,
        totalCount: 3,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const NextPage(2),
      ),
    );

    await tester.pump();

    // 2ページ目を取得開始
    await tester.tap(find.text('もっと読み込む'));
    await tester.pump();

    expect(requests, hasLength(2));
    expect(find.text('repository-0'), findsOneWidget);

    // 追加読み込みで通信エラー
    requests[1].completeError(const ApiFailure(kind: ApiFailureKind.network));

    await tester.pump();

    // 既存結果が消えず、再試行ボタンが表示される
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-1'), findsOneWidget);
    expect(find.text('2件表示 / 初回総件数 3件'), findsOneWidget);
    expect(find.text('GitHubとの通信に失敗しました。'), findsOneWidget);
    expect(find.text('追加読み込みを再試行'), findsOneWidget);

    // 追加読み込み失敗中に英語へ変更。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    expect(find.text('Failed to communicate with GitHub.'), findsOneWidget);
    expect(find.text('Retry loading more'), findsOneWidget);
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-1'), findsOneWidget);
    expect(find.text('Showing 2 / Initial total: 3'), findsOneWidget);

    expect(requests, hasLength(2));

    // 日本語へ戻して既存の再試行テストを続ける。
    tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];

    await tester.pumpAndSettle();

    expect(find.text('GitHubとの通信に失敗しました。'), findsOneWidget);
    expect(find.text('追加読み込みを再試行'), findsOneWidget);
    expect(requests, hasLength(2));

    // 再試行する
    await tester.tap(find.text('追加読み込みを再試行'));
    await tester.pump();

    expect(requests, hasLength(3));
    expect(queries, ['flutter', 'flutter', 'flutter']);
    expect(find.text('追加読み込み中…'), findsOneWidget);

    // 再試行成功
    requests[2].complete(
      SearchPage(
        items: [resultPage(count: 3).items.last],
        totalCount: 3,
        incompleteResults: false,
        page: 2,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-1'), findsOneWidget);
    expect(find.text('repository-2'), findsOneWidget);
    expect(find.text('3件表示 / 初回総件数 3件'), findsOneWidget);
    expect(find.text('これ以上の結果はありません。'), findsOneWidget);
  });
  testWidgets('追加読み込みキャンセル後も既存結果を保持し、再取得できる', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    // 1ページ目：2件、次ページあり
    requests[0].complete(
      SearchPage(
        items: resultPage(count: 2).items,
        totalCount: 3,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const NextPage(2),
      ),
    );

    await tester.pump();

    // 追加読み込みを開始
    await tester.tap(find.text('もっと読み込む'));
    await tester.pump();

    expect(requests, hasLength(2));
    expect(find.text('追加読み込み中…'), findsOneWidget);
    expect(find.text('repository-0'), findsOneWidget);

    // 追加読み込みをキャンセル
    await tester.tap(find.text('キャンセル'));
    await tester.pump();

    expect(find.text('追加読み込み中…'), findsNothing);
    expect(find.text('もっと読み込む'), findsOneWidget);

    // 既存の結果を維持
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-1'), findsOneWidget);
    expect(find.text('2件表示 / 初回総件数 3件'), findsOneWidget);

    // キャンセル済みのAPIが遅れて成功
    requests[1].complete(
      SearchPage(
        items: [resultPage(count: 3).items.last],
        totalCount: 3,
        incompleteResults: false,
        page: 2,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    // 古い応答を採用しない
    expect(find.text('repository-2'), findsNothing);
    expect(find.text('もっと読み込む'), findsOneWidget);
    expect(find.text('2件表示 / 初回総件数 3件'), findsOneWidget);

    // 再び追加読み込みする
    await tester.tap(find.text('もっと読み込む'));
    await tester.pump();

    expect(requests, hasLength(3));
    expect(queries, ['flutter', 'flutter', 'flutter']);

    // 今度は正常完了
    requests[2].complete(
      SearchPage(
        items: [resultPage(count: 3).items.last],
        totalCount: 3,
        incompleteResults: false,
        page: 2,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-1'), findsOneWidget);
    expect(find.text('repository-2'), findsOneWidget);
    expect(find.text('3件表示 / 初回総件数 3件'), findsOneWidget);
    expect(find.text('これ以上の結果はありません。'), findsOneWidget);
  });
  testWidgets('初回検索キャンセル後に古い応答を無視して再検索できる', (tester) async {
    await start(tester);

    // ① flutterで検索開始
    await search(tester, 'flutter');

    expect(requests, hasLength(1));
    expect(find.text('検索中…'), findsOneWidget);
    expect(find.text('送信済みの検索語：flutter'), findsOneWidget);

    // ② 検索中にキャンセル
    await tester.tap(find.text('キャンセル'));
    await tester.pump();

    expect(find.text('キーワードを入力して検索してください。'), findsOneWidget);
    expect(find.text('送信済みの検索語：flutter'), findsNothing);

    // ③ キャンセル済みの古い検索が後から成功
    requests[0].complete(resultPage(count: 2));
    await tester.pump();

    // 古い結果は表示されない
    expect(find.text('repository-0'), findsNothing);
    expect(find.text('キーワードを入力して検索してください。'), findsOneWidget);

    // ④ 新しい検索を開始
    await search(tester, 'dart');

    expect(queries, ['flutter', 'dart']);
    expect(find.text('検索中…'), findsOneWidget);

    // ⑤ 新しい検索が成功
    requests[1].complete(resultPage(count: 1));
    await tester.pump();

    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('送信済みの検索語：dart'), findsOneWidget);
    expect(find.text('検索中…'), findsNothing);
  });
  testWidgets('追加読み込み後も初回検索時の総件数を区別して表示する', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    // 初回検索：表示2件、総件数3件
    requests[0].complete(
      SearchPage(
        items: resultPage(count: 2).items,
        totalCount: 3,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const NextPage(2),
      ),
    );

    await tester.pump();

    expect(find.text('2件表示 / 初回総件数 3件'), findsOneWidget);

    // 追加読み込み
    await tester.tap(find.text('もっと読み込む'));
    await tester.pump();

    // 追加取得時点では総件数が5件に増加
    requests[1].complete(
      SearchPage(
        items: resultPage(count: 5).items.skip(2).toList(),
        totalCount: 5,
        incompleteResults: false,
        page: 2,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    // 取得済み5件と初回の総件数3件を区別
    expect(find.text('5件表示 / 初回総件数 3件'), findsOneWidget);

    expect(find.text('検索結果の一部を表示しています。'), findsNothing);
  });
  testWidgets('追加読み込み中に総件数が減っても初回値を明示する', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    // 初回：2件取得、総件数3件
    requests[0].complete(
      SearchPage(
        items: resultPage(count: 2).items,
        totalCount: 3,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const NextPage(2),
      ),
    );

    await tester.pump();

    expect(find.text('2件表示 / 初回総件数 3件'), findsOneWidget);

    // 追加読み込みを開始
    await tester.tap(find.text('もっと読み込む'));
    await tester.pump();

    expect(requests, hasLength(2));

    // 追加取得時には総件数が1件に減少。
    // 2ページ目には結果が存在しない。
    requests[1].complete(
      SearchPage(
        items: const [],
        totalCount: 1,
        incompleteResults: false,
        page: 2,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    // 取得済みの2件は保持
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-1'), findsOneWidget);

    // 初回検索時の総件数として3件を表示
    expect(find.text('2件表示 / 初回総件数 3件'), findsOneWidget);

    // 追加読み込みは終了
    expect(find.text('これ以上の結果はありません。'), findsOneWidget);
  });
  testWidgets('新規検索が描画前に成功してもスクロール位置をリセットする', (tester) async {
    await start(tester);

    // 検索A：30件取得
    await search(tester, 'long');

    requests[0].complete(resultPage(count: 30));
    await tester.pump();

    // 一覧を途中までスクロール
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();

    final oldOffset = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;

    expect(oldOffset, greaterThan(0));

    // 検索Bを開始
    // 今回はsearch()ヘルパーを使用しない。
    await tester.enterText(input, 'new');
    await tester.tap(submit);

    expect(queries, ['long', 'new']);

    // Loading画面をpumpする前にAPI応答を返す
    requests[1].complete(resultPage(count: 30));

    // 非同期処理を進めるが、画面はまだ描画しない
    await Future<void>.value();

    // 新しい検索結果を画面へ反映
    await tester.pump();

    expect(find.text('送信済みの検索語：new'), findsOneWidget);

    // 検索Bの一覧は先頭から表示されるべき
    final newOffset = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;

    expect(newOffset, 0);
  });

  testWidgets('UI01: GitHubの1000件上限を通常終了と区別して表示', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    final base = resultPage(count: 1);

    requests.single.complete(
      SearchPage(
        items: base.items,
        totalCount: 1500,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.githubLimitReached),
      ),
    );

    await tester.pump();

    expect(find.text('GitHub検索APIの取得上限（1,000件）に達しました。'), findsOneWidget);

    expect(find.text('これ以上の結果はありません。'), findsNothing);
  });

  testWidgets('UI02: 通常終了では1000件上限の案内を表示しない', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    final base = resultPage(count: 1);

    requests.single.complete(
      SearchPage(
        items: base.items,
        totalCount: 1,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    expect(find.text('これ以上の結果はありません。'), findsOneWidget);

    expect(find.text('GitHub検索APIの取得上限（1,000件）に達しました。'), findsNothing);
  });
  testWidgets('VH03: 検索結果に番号を表示し、開いた項目を閲覧済みにする', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    final page = resultPage(count: 2);
    requests.single.complete(page);
    await tester.pump();

    // 検索結果には表示順の番号が付く。
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);

    // 最初は閲覧済みがない。
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);

    // 1件目を開く。
    await tester.tap(find.text('repository-0'));
    await tester.pump();

    final viewed = tester.container().read(viewedRepositoryProvider);

    expect(viewed.contains(page.items[0].key.id), isTrue);
    expect(viewed.contains(page.items[1].key.id), isFalse);

    // 一覧へ戻る。
    // 詳細画面が表示されていることを確認する。
    // 画面遷移のアニメーションを進める。
    await tester.pump(const Duration(milliseconds: 500));

    // 詳細画面が実際に存在することを確認。
    final detailFinder = find.byType(RepositoryDetailScreen);
    expect(detailFinder, findsOneWidget);

    // 詳細画面から検索一覧へ戻る。
    Navigator.of(tester.element(detailFinder)).pop();

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // 閲覧済みチェックが1件表示される。
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    // 番号は変わらない。
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
  });

  testWidgets('VH04: 追加読み込み後も31番以降の連番を表示', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    // 1ページ目は30件。
    final firstPage = resultPage(count: 30);

    requests[0].complete(
      SearchPage(
        items: firstPage.items,
        totalCount: 40,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: const NextPage(2),
      ),
    );

    await tester.pump();

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);

    // 一覧の末尾までスクロールして追加読み込み。
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );

    final moreButton = find.widgetWithText(OutlinedButton, 'もっと読み込む');

    await tester.scrollUntilVisible(moreButton, 300, scrollable: scrollable);

    // スクロール後の描画と位置を確定させる。
    await tester.pumpAndSettle();
    await tester.ensureVisible(moreButton);
    await tester.pump();

    expect(moreButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(moreButton).onPressed, isNotNull);

    await tester.tap(moreButton);
    await tester.pump();

    expect(requests, hasLength(2));

    expect(requests, hasLength(2));

    // 2ページ目は新しい10件。
    final secondItems = [
      for (var i = 30; i < 40; i++)
        RepositorySummary(
          key: RepositoryKey(id: 1000 + i, owner: 'test', name: 'extra-$i'),
          avatarUrl: '',
          language: 'Dart',
          starCount: 0,
          forkCount: 0,
          openIssueAndPullRequestCount: 0,
        ),
    ];

    requests[1].complete(
      SearchPage(
        items: secondItems,
        totalCount: 40,
        incompleteResults: false,
        page: 2,
        perPage: 30,
        navigation: const PageEnd(SearchEndReason.exhausted),
      ),
    );

    await tester.pump();

    // ListViewは画面外の行をまだ構築していないため、
    // 対象の番号までスクロールして検証する。
    await tester.scrollUntilVisible(
      find.text('31.'),
      250,
      scrollable: scrollable,
    );

    expect(find.text('31.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('40.'),
      250,
      scrollable: scrollable,
    );

    expect(find.text('40.'), findsOneWidget);
    expect(find.text('41.'), findsNothing);
  });

  testWidgets('VH05: 再検索で同じリポジトリが現れたら閲覧済みを維持', (tester) async {
    await start(tester);
    await search(tester, 'first');

    final firstPage = resultPage(count: 2);
    requests[0].complete(firstPage);
    await tester.pump();

    expect(find.byIcon(Icons.check_circle_outline), findsNothing);

    // 最初の検索結果の1件目を開く。
    await tester.tap(find.text('repository-0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final detailFinder = find.byType(RepositoryDetailScreen);
    expect(detailFinder, findsOneWidget);

    final viewed = tester.container().read(viewedRepositoryProvider);

    expect(viewed.contains(firstPage.items[0].key.id), isTrue);
    expect(viewed.contains(firstPage.items[1].key.id), isFalse);

    // 詳細画面から一覧へ戻る。
    Navigator.of(tester.element(detailFinder)).pop();

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    // 別の検索語で再検索。
    await search(tester, 'second');

    // 同じリポジトリが検索結果に再び含まれる。
    requests[1].complete(resultPage(count: 2));
    await tester.pump();

    // 閲覧履歴は再検索で失われない。
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    expect(
      tester
          .container()
          .read(viewedRepositoryProvider)
          .contains(firstPage.items[0].key.id),
      isTrue,
    );

    // 番号は新しい検索結果の表示順。
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);

    expect(queries, ['first', 'second']);
  });

  testWidgets('VH07: 文字倍率2倍でも番号とリポジトリ名が正しい順序で表示され、番号用の余分な固定幅を確保しない。', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await start(tester);
    await search(tester, 'flutter');

    // 通常のページ件数で検索結果を返す。
    requests[0].complete(resultPage(count: 30));
    await tester.pump();

    // 番号欄の幅は全行共通なので、1番目で確認できる。

    final numberFinder = find.text('1.');
    final nameFinder = find.text('repository-0');

    expect(numberFinder, findsOneWidget);
    expect(nameFinder, findsOneWidget);

    final numberRect = tester.getRect(numberFinder);
    final nameRect = tester.getRect(nameFinder);

    // 番号の右側にリポジトリ名がある。
    expect(numberRect.right, lessThan(nameRect.left));

    // 番号のための旧固定幅は不要。
    expect(numberRect.width, lessThan(122));

    // フォルダアイコンが削除されている。
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byIcon(Icons.folder_outlined),
      ),
      findsNothing,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('LY01: 初期状態は上配置で、下配置に変更できる', (tester) async {
    await startWithLayout(tester);

    final prompt = find.text('キーワードを入力して検索してください。');

    expect(tester.getTopLeft(input).dy, lessThan(tester.getTopLeft(prompt).dy));

    await choosePosition(tester, SearchPanelPosition.bottom);

    expect(
      tester.getTopLeft(input).dy,
      greaterThan(tester.getTopLeft(prompt).dy),
    );
    expect(layoutStore.saved, SearchPanelPosition.bottom);
    expect(layoutStore.writes, [SearchPanelPosition.bottom]);
  });

  testWidgets('LY02: 配置変更しても検索状態・入力・スクロール・API回数を維持する', (tester) async {
    await startWithLayout(tester);
    await search(tester, 'long');

    requests.single.complete(resultPage(count: 30));
    await tester.pump();

    final listFinder = find.byType(ListView);

    await tester.drag(listFinder, const Offset(0, -650));
    await tester.pumpAndSettle();

    // 検索結果とは異なる未送信の入力を残す。
    await tester.enterText(input, 'draft');
    tester.testTextInput.hide();
    await tester.pump();

    final beforeList = tester.widget<ListView>(listFinder);
    final beforeOffset = beforeList.controller!.offset;
    final beforeCount = beforeList.childrenDelegate.estimatedChildCount;

    expect(beforeOffset, greaterThan(0));
    expect(queries, ['long']);

    await choosePosition(tester, SearchPanelPosition.bottom);

    final afterList = tester.widget<ListView>(listFinder);

    expect(afterList.controller!.offset, closeTo(beforeOffset, 0.01));
    expect(afterList.childrenDelegate.estimatedChildCount, beforeCount);

    expect(tester.widget<TextFormField>(input).controller!.text, 'draft');
    expect(find.text('送信済みの検索語：long'), findsOneWidget);
    expect(queries, ['long']);

    expect(
      tester.getTopLeft(input).dy,
      greaterThan(tester.getTopLeft(listFinder).dy),
    );
  });

  testWidgets('LY03: 保存した配置を画面再生成時に復元できる', (tester) async {
    await startWithLayout(tester);
    await choosePosition(tester, SearchPanelPosition.bottom);

    expect(layoutStore.saved, SearchPanelPosition.bottom);

    // 画面とProviderScopeを破棄し、同じ永続Storeで再起動する。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await startWithLayout(tester);

    final prompt = find.text('キーワードを入力して検索してください。');

    expect(
      tester.getTopLeft(input).dy,
      greaterThan(tester.getTopLeft(prompt).dy),
    );

    // 復元はreadだけであり、新たなwriteを発生させない。
    expect(layoutStore.writes, [SearchPanelPosition.bottom]);
    expect(queries, isEmpty);
  });

  testWidgets('LY04: 標準配置へ戻すと上配置になり、設定も保存される', (tester) async {
    await startWithLayout(tester);

    await choosePosition(tester, SearchPanelPosition.bottom);
    await choosePosition(tester, SearchPanelPosition.top);

    final prompt = find.text('キーワードを入力して検索してください。');

    expect(tester.getTopLeft(input).dy, lessThan(tester.getTopLeft(prompt).dy));
    expect(layoutStore.saved, SearchPanelPosition.top);
    expect(layoutStore.writes, [
      SearchPanelPosition.bottom,
      SearchPanelPosition.top,
    ]);
  });

  testWidgets('LY05: 設定保存失敗時は直前の配置に戻る', (tester) async {
    await startWithLayout(tester);

    layoutStore.failWrites = true;

    await choosePosition(tester, SearchPanelPosition.bottom);

    final prompt = find.text('キーワードを入力して検索してください。');

    expect(tester.getTopLeft(input).dy, lessThan(tester.getTopLeft(prompt).dy));

    expect(layoutStore.saved, SearchPanelPosition.top);
    expect(layoutStore.writes, [SearchPanelPosition.bottom]);

    expect(find.text('検索欄の配置を保存できませんでした。'), findsOneWidget);
  });

  testWidgets('UX01: 検索アイコンを入力欄内に表示し、検索できる', (tester) async {
    await start(tester);

    final field = find.byType(TextFormField);
    final button = find.byKey(const Key('search-submit-button'));

    expect(field, findsOneWidget);
    expect(button, findsOneWidget);

    // 検索ボタンは入力欄の領域内にある。
    expect(tester.getRect(field).contains(tester.getCenter(button)), isTrue);

    await tester.enterText(field, 'flutter');
    await tester.tap(button);
    await tester.pump();

    expect(queries, ['flutter']);

    requests.single.complete(resultPage());
    await tester.pump();

    expect(find.text('repository-0'), findsOneWidget);
  });

  testWidgets('UI03: 件数表示を簡潔にし初回総件数を維持する', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    requests.single.complete(resultPage(count: 30));
    await tester.pump();

    final countLabel = find.byKey(const Key('search-result-count'));

    expect(countLabel, findsOneWidget);

    expect(find.text('30件表示 / 初回総件数 30件'), findsOneWidget);

    expect(queries, ['flutter']);
  });
  testWidgets('UI04: 大きな総件数を桁区切りで表示する', (tester) async {
    await start(tester);
    await search(tester, 'flutter');

    final page = resultPage(count: 1);

    requests.single.complete(
      SearchPage(
        items: page.items,
        totalCount: 1234567,
        incompleteResults: false,
        page: 1,
        perPage: 30,
        navigation: page.navigation, // 追加
      ),
    );

    await tester.pump();

    expect(find.text('1件表示 / 初回総件数 1,234,567件'), findsOneWidget);
  });

  for (final (position, locale) in localizedLayoutCases) {
    testWidgets(
      'UX02: 長い検索語でも一覧を維持し全文を確認できる(${position.name}, ${locale.languageCode})',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 800));
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;

        addTearDown(() async {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.binding.setSurfaceSize(null);
        });

        layoutStore.saved = position;
        await startWithLayout(tester, locale: locale);

        final query = List.filled(60, 'flutter').join(' ');

        await search(tester, query);
        requests.single.complete(resultPage(count: 30));
        await tester.pump();

        final preview = find.byKey(const Key('submitted-query-label'));

        expect(preview, findsOneWidget);

        final text = tester.widget<Text>(preview);
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);

        // 検索結果の表示領域が残っている。
        final list = find.byType(ListView);
        expect(list, findsOneWidget);
        expect(tester.getSize(list).height, greaterThan(0));

        // 省略表示をタップして全文を確認。
        await tester.tap(find.byKey(const Key('submitted-query-open')));
        await tester.pumpAndSettle();

        final fullText = tester.widget<SelectableText>(
          find.byKey(const Key('submitted-query-full')),
        );
        expect(fullText.data, query);

        // ダイアログを閉じても検索状態は維持する。
        await tester.tap(find.byKey(const Key('submitted-query-close')));
        await tester.pumpAndSettle();

        expect(queries, [query]);
      },
    );
  }
  for (final (position, locale) in localizedLayoutCases) {
    testWidgets(
      'RT01: 画面回転時も検索状態と配置を維持する (${position.name}, ${locale.languageCode})',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 800);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;

        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        layoutStore.saved = position;
        await startWithLayout(tester, locale: locale);

        await search(tester, 'flutter');
        requests.single.complete(resultPage(count: 30));
        await tester.pumpAndSettle();

        final layout = find.byKey(const Key('search-main-layout'));
        final panel = find.byKey(const Key('search-controls-panel'));
        final list = find.byType(ListView);

        // 縦画面では上下配置。
        expect(tester.widget<Flex>(layout).direction, Axis.vertical);

        // 未送信の入力を残しておく。
        await tester.enterText(input, 'draft');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();

        final controller = tester.widget<ListView>(list).controller!;

        controller.jumpTo(200);
        await tester.pumpAndSettle();

        final originalScrollPosition = controller.position;

        // 横画面へ回転。
        tester.view.physicalSize = const Size(800, 390);
        await tester.pumpAndSettle();

        expect(tester.widget<Flex>(layout).direction, Axis.horizontal);

        final panelRect = tester.getRect(panel);
        final listRect = tester.getRect(list);

        if (position == SearchPanelPosition.top) {
          expect(panelRect.right, lessThan(listRect.left));
        } else {
          expect(panelRect.left, greaterThan(listRect.right));
        }

        // 検索結果を表示できる高さが残っている。
        expect(listRect.height, greaterThan(0));

        // 入力内容と送信済み検索語を維持。
        expect(tester.widget<TextFormField>(input).controller!.text, 'draft');
        expect(
          find.text(
            locale.languageCode == 'ja'
                ? '送信済みの検索語：flutter'
                : 'Submitted query: flutter',
          ),
          findsOneWidget,
        );

        // スクロール状態を作り直さない。
        expect(controller.position, same(originalScrollPosition));
        expect(controller.offset, greaterThan(0));

        // APIの追加要求や設定の書き込みは発生しない。
        expect(queries, ['flutter']);
        expect(layoutStore.writes, isEmpty);
        expect(tester.takeException(), isNull);

        // 再び縦画面へ戻す。
        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();

        expect(tester.widget<Flex>(layout).direction, Axis.vertical);

        expect(tester.widget<TextFormField>(input).controller!.text, 'draft');

        expect(controller.position, same(originalScrollPosition));
        expect(controller.offset, greaterThan(0));
        expect(queries, ['flutter']);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (position, locale) in localizedLayoutCases) {
    testWidgets('KB01: 横画面でキーボードを表示しても検索状態を維持する'
        ' (${position.name}, ${locale.languageCode})', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 390);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      layoutStore.saved = position;
      await startWithLayout(tester, locale: locale);

      await search(tester, 'flutter');
      requests.single.complete(resultPage(count: 30));
      await tester.pumpAndSettle();

      final list = find.byType(ListView);

      final controller = tester.widget<ListView>(list).controller!;

      controller.jumpTo(200);
      await tester.pumpAndSettle();

      final originalPosition = controller.position;
      final originalOffset = controller.offset;

      expect(originalOffset, greaterThan(0));

      // 未送信の入力を用意する。
      await tester.enterText(input, 'draft');
      await tester.pump();

      // キーボードが画面下部270dpを占有する状態を再現。
      tester.view.viewInsets = const FakeViewPadding(bottom: 270);

      await tester.pumpAndSettle();

      // 入力に集中できる画面へ切り替わる。
      expect(find.byType(AppBar), findsNothing);
      expect(list, findsNothing);
      expect(input, findsOneWidget);

      // 非表示になっても一覧Widgetは破棄しない。
      expect(find.byType(ListView, skipOffstage: false), findsOneWidget);

      expect(controller.position, same(originalPosition));

      expect(tester.widget<TextFormField>(input).controller!.text, 'draft');

      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      expect(
        find.byKey(const Key('search-submit-button')).hitTestable(),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);

      // キーボードを閉じる。
      tester.testTextInput.hide();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();

      // 元の画面とスクロール位置へ復帰する。
      expect(find.byType(AppBar), findsOneWidget);
      expect(list, findsOneWidget);

      expect(controller.position, same(originalPosition));

      expect(controller.offset, closeTo(originalOffset, 0.01));

      expect(
        find.text(
          locale.languageCode == 'ja'
              ? '送信済みの検索語：flutter'
              : 'Submitted query: flutter',
        ),
        findsOneWidget,
      );

      expect(tester.widget<TextFormField>(input).controller!.text, 'draft');

      // 表示切り替えだけではAPI通信・設定保存を行わない。
      expect(queries, ['flutter']);
      expect(layoutStore.writes, isEmpty);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('LS01: 英語環境で検索画面を操作できる', (tester) async {
    await startWithLayout(tester, locale: const Locale('en', 'US'));

    expect(find.text('Repository Search'), findsOneWidget);
    expect(find.text('Keyword'), findsOneWidget);
    expect(find.text('Enter a keyword to search.'), findsOneWidget);

    // 空入力時のエラーも英語で表示する。
    await search(tester, '  ');

    expect(find.text('Please enter a search keyword.'), findsOneWidget);
    expect(queries, isEmpty);

    // 正常な検索。
    await search(tester, 'flutter');

    expect(find.text('Searching…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Submitted query: flutter'), findsOneWidget);

    final page = resultPage(count: 2);
    requests.single.complete(page);
    await tester.pumpAndSettle();

    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('test/repository-1 / Not specified'), findsOneWidget);

    expect(
      find.text('Showing 2 / Initial total: ${page.totalCount}'),
      findsOneWidget,
    );

    // 送信済み検索語の全文表示。
    await tester.tap(find.byKey(const Key('submitted-query-open')));
    await tester.pumpAndSettle();

    expect(find.text('Submitted search query'), findsOneWidget);

    final fullText = tester.widget<SelectableText>(
      find.byKey(const Key('submitted-query-full')),
    );

    expect(fullText.data, 'flutter');
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.byKey(const Key('submitted-query-close')));
    await tester.pumpAndSettle();

    expect(find.text('repository-0'), findsOneWidget);
    expect(queries, ['flutter']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LS02: 未対応言語では検索画面を英語で表示する', (tester) async {
    await startWithLayout(tester, locale: const Locale('fr', 'FR'));

    expect(find.text('Repository Search'), findsOneWidget);
    expect(find.text('Keyword'), findsOneWidget);
    expect(find.text('Enter a keyword to search.'), findsOneWidget);

    final context = tester.element(input);

    expect(Localizations.localeOf(context), const Locale('en'));

    expect(queries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LS03: 言語変更時も検索状態と入力内容を維持する', (tester) async {
    await startWithLayout(tester);

    await search(tester, 'flutter');
    requests.single.complete(resultPage(count: 30));
    await tester.pumpAndSettle();

    expect(find.text('リポジトリ検索'), findsOneWidget);
    expect(find.text('送信済みの検索語：flutter'), findsOneWidget);

    // 未送信の入力を保持する。
    await tester.enterText(input, 'draft');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    final list = find.byType(ListView);
    final controller = tester.widget<ListView>(list).controller!;

    controller.jumpTo(200);
    await tester.pumpAndSettle();

    final originalOffset = controller.offset;

    expect(controller.offset, greaterThan(0));

    // 日本語から英語へ変更。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    expect(find.text('Repository Search'), findsOneWidget);
    expect(find.text('Submitted query: flutter'), findsOneWidget);
    expect(find.text('リポジトリ検索'), findsNothing);

    expect(tester.widget<TextFormField>(input).controller!.text, 'draft');

    expect(tester.widget<ListView>(list).controller, same(controller));
    expect(controller.offset, closeTo(originalOffset, 0.01));

    // 日本語に戻す。
    tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];

    await tester.pumpAndSettle();

    expect(find.text('リポジトリ検索'), findsOneWidget);
    expect(find.text('送信済みの検索語：flutter'), findsOneWidget);

    expect(tester.widget<TextFormField>(input).controller!.text, 'draft');

    expect(tester.widget<ListView>(list).controller, same(controller));
    expect(controller.offset, closeTo(originalOffset, 0.01));

    // 言語変更だけでは通信や設定保存を行わない。
    expect(queries, ['flutter']);
    expect(layoutStore.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LS04: 言語変更時に表示済みの入力エラーも翻訳する', (tester) async {
    await startWithLayout(tester);

    await search(tester, '  ');

    expect(find.text('検索キーワードを入力してください。'), findsOneWidget);

    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    expect(find.text('Keyword'), findsOneWidget);

    expect(find.text('Please enter a search keyword.'), findsOneWidget);

    expect(find.text('検索キーワードを入力してください。'), findsNothing);

    expect(queries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LE02: 検索エラーを言語変更後も保持して再試行できる', (tester) async {
    await startWithLayout(tester);

    await search(tester, 'flutter');

    requests.single.completeError(
      const ApiFailure(
        kind: ApiFailureKind.rateLimited,
        reason: ApiFailureReason.blockedBeforeSend,
      ),
    );

    await tester.pumpAndSettle();

    const jaMessage =
        'GitHubへの送信を一時停止しています。'
        '再試行可能な時刻は不明です。';

    const enMessage =
        'Requests to GitHub are temporarily paused. '
        'The retry time is unknown.';

    expect(find.text(jaMessage), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);

    // 未送信の入力も保持する。
    await tester.enterText(input, 'draft');

    // エラー表示中に英語へ変更。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    expect(find.text(enMessage), findsOneWidget);
    expect(find.text(jaMessage), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Submitted query: flutter'), findsOneWidget);

    expect(tester.widget<TextFormField>(input).controller!.text, 'draft');

    // 言語変更だけでは再検索しない。
    expect(queries, ['flutter']);
    expect(layoutStore.writes, isEmpty);

    // 利用者による明示的な再試行。
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(queries, ['flutter', 'flutter']);
    expect(find.text(enMessage), findsNothing);

    requests.last.complete(resultPage());
    await tester.pumpAndSettle();

    expect(find.text('repository-0'), findsOneWidget);

    expect(tester.widget<TextFormField>(input).controller!.text, 'draft');

    expect(tester.takeException(), isNull);
  });

  for (final (locale, expectedMessage) in [
    (const Locale('ja', 'JP'), '検索キーワードを入力してください。'),
    (const Locale('en', 'US'), 'Please enter a search keyword.'),
  ]) {
    testWidgets('LS05: 空欄エラーを現在の言語で読み上げ通知する'
        ' (${locale.languageCode})', (tester) async {
      // 読み上げ通知に対応する環境を再現する。
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(supportsAnnounce: true);

      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await startWithLayout(tester, locale: locale);

      // 空白のみを入力する。
      await tester.enterText(input, '  ');
      await tester.pumpAndSettle();

      // 検索操作前の通知は検証対象から除外する。
      tester.takeAnnouncements();

      await tester.tap(submit);
      await tester.pumpAndSettle();

      // 画面に翻訳済みのエラーを表示する。
      expect(find.text(expectedMessage), findsOneWidget);

      final messages = tester
          .takeAnnouncements()
          .map((announcement) => announcement.message)
          .toList();

      // 読み上げ通知にも翻訳済み文言を使用する。
      expect(messages, contains(expectedMessage));

      // 内部識別子を通知しない。
      expect(messages, isNot(contains('keywordRequired')));

      // 不正な入力によるAPI通信は発生しない。
      expect(queries, isEmpty);
      expect(layoutStore.writes, isEmpty);

      expect(tester.takeException(), isNull);
    });
  }
}
