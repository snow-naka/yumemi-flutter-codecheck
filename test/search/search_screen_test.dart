import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/main.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';

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
    expect(find.text('表示中：2件（総件数：3件）'), findsOneWidget);
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
    expect(find.text('表示中：3件（総件数：3件）'), findsOneWidget);
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
    expect(find.text('表示中：2件（総件数：3件）'), findsOneWidget);

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
    expect(find.text('表示中：2件（総件数：3件）'), findsOneWidget);

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
    expect(find.text('表示中：3件（総件数：3件）'), findsOneWidget);
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
}
