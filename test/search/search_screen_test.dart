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
}
