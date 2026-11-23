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

import 'search_test_support.dart';

void main() {
  late List<String> queries;
  late List<Completer<SearchPage>> requests;
  late FakeGitHubRepositoryGateway fake;
  final input = find.byType(TextFormField);
  final submit = find.widgetWithText(FilledButton, '検索');

  setUp(() {
    queries = [];
    requests = [];
    fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) {
        queries.add(query);
        final pending = Completer<SearchPage>();
        requests.add(pending);
        return pending.future;
      },
    );
  });

  Future<void> start(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
      child: const MyApp(),
    ),
  );

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(input, query);
    await tester.tap(submit);
    await tester.pump();
  }

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
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
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
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
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
        const ApiFailure(
          kind: ApiFailureKind.network,
          safeMessage: 'テスト用の取得失敗',
        ),
      );
      await tester.pump();
      expect(find.text('テスト用の取得失敗'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.enterText(input, 'edited');
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(queries, ['failed', 'failed']);
      expect(find.text('テスト用の取得失敗'), findsNothing);
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
    requests[1].completeError(
      const ApiFailure(
        kind: ApiFailureKind.network,
        safeMessage: 'テスト用の追加読み込み失敗',
      ),
    );

    await tester.pump();

    // 既存結果が消えず、再試行ボタンが表示される
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('repository-1'), findsOneWidget);
    expect(find.text('表示中：2件（初回検索時の総件数：3件）'), findsOneWidget);
    expect(find.text('テスト用の追加読み込み失敗'), findsOneWidget);
    expect(find.text('追加読み込みを再試行'), findsOneWidget);

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
    expect(find.text('表示中：3件（初回検索時の総件数：3件）'), findsOneWidget);
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
    expect(find.text('表示中：2件（初回検索時の総件数：3件）'), findsOneWidget);

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
    expect(find.text('表示中：2件（初回検索時の総件数：3件）'), findsOneWidget);

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
    expect(find.text('表示中：3件（初回検索時の総件数：3件）'), findsOneWidget);
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

    expect(find.text('表示中：2件（初回検索時の総件数：3件）'), findsOneWidget);

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
    expect(find.text('表示中：5件（初回検索時の総件数：3件）'), findsOneWidget);

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

    expect(find.text('表示中：2件（初回検索時の総件数：3件）'), findsOneWidget);

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
    expect(find.text('表示中：2件（初回検索時の総件数：3件）'), findsOneWidget);

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

    expect(viewed.contains(page.items[0].key), isTrue);
    expect(viewed.contains(page.items[1].key), isFalse);

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

    await tester.scrollUntilVisible(
      find.text('もっと読み込む'),
      300,
      scrollable: scrollable,
    );

    await tester.tap(find.text('もっと読み込む'));
    await tester.pump();

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

    expect(viewed.contains(firstPage.items[0].key), isTrue);
    expect(viewed.contains(firstPage.items[1].key), isFalse);

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
          .contains(firstPage.items[0].key),
      isTrue,
    );

    // 番号は新しい検索結果の表示順。
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);

    expect(queries, ['first', 'second']);
  });
}
