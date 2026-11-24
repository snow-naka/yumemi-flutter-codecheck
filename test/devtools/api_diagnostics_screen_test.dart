import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/devtools/api_diagnostics.dart';
import 'package:yumemi_app/devtools/api_diagnostics_screen.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/l10n/app_localizations.dart';

void main() {
  Future<void> start(
    WidgetTester tester,
    InMemoryApiDiagnostics store, {
    Locale locale = const Locale('ja', 'JP'),
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];

    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiDiagnosticsProvider.overrideWithValue(store)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ApiDiagnosticsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 実際に選択された言語を検証する。
    expect(
      Localizations.localeOf(tester.element(find.byType(ApiDiagnosticsScreen))),
      Locale(locale.languageCode),
    );
  }

  testWidgets('DI01: 診断情報を画面に反映する', (tester) async {
    final store = InMemoryApiDiagnostics();
    addTearDown(store.dispose);

    await start(tester, store);

    expect(find.text('通信履歴はまだありません'), findsOneWidget);

    store.record(
      ApiDiagnosticEvent(
        recordedAt: DateTime.utc(2026, 11, 22, 12),
        operation: ApiDiagnosticOperation.search,
        outcome: ApiDiagnosticOutcome.response,
        httpStatus: 200,
        rateLimitLimit: 10,
        rateLimitRemaining: 7,
        rateLimitResetAt: DateTime.utc(2026, 11, 22, 12, 5),
      ),
    );

    await tester.pump();

    expect(find.text('検索 / HTTP 200'), findsOneWidget);

    await tester.tap(find.text('検索 / HTTP 200'));
    await tester.pumpAndSettle();

    expect(find.text('7 / 10'), findsOneWidget);
    expect(find.text('GitHub Reset'), findsOneWidget);
  });

  testWidgets('DI02: 429の待機情報を表示して履歴消去', (tester) async {
    final store = InMemoryApiDiagnostics();
    addTearDown(store.dispose);

    store.record(
      ApiDiagnosticEvent(
        recordedAt: DateTime.utc(2026, 11, 22, 12),
        operation: ApiDiagnosticOperation.detail,
        outcome: ApiDiagnosticOutcome.response,
        httpStatus: 429,
        retryAfter: const Duration(seconds: 120),
      ),
    );

    await start(tester, store);

    await tester.tap(find.text('詳細 / HTTP 429'));
    await tester.pumpAndSettle();

    expect(find.text('120秒'), findsOneWidget);

    await tester.tap(find.byTooltip('履歴を消去'));
    await tester.pumpAndSettle();

    expect(find.text('通信履歴はまだありません'), findsOneWidget);
    expect(store.value, isEmpty);
  });

  testWidgets('DI04: 英語環境で診断情報を表示して履歴を消去できる', (tester) async {
    final store = InMemoryApiDiagnostics();
    addTearDown(store.dispose);

    await start(tester, store, locale: const Locale('en', 'US'));

    expect(find.text('API Request Inspector'), findsOneWidget);

    expect(find.text('No request history yet.'), findsOneWidget);

    store.record(
      ApiDiagnosticEvent(
        recordedAt: DateTime.utc(2026, 11, 22, 12),
        operation: ApiDiagnosticOperation.detail,
        outcome: ApiDiagnosticOutcome.response,
        httpStatus: 429,
        rateLimitLimit: 60,
        rateLimitRemaining: 0,
        retryAfter: const Duration(seconds: 120),
      ),
    );

    await tester.pump();

    expect(find.text('Detail / HTTP 429'), findsOneWidget);
    expect(find.textContaining('Recorded: '), findsOneWidget);

    await tester.tap(find.text('Detail / HTTP 429'));
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('HTTP response'), findsOneWidget);
    expect(find.text('Remaining / Limit'), findsOneWidget);
    expect(find.text('0 / 60'), findsOneWidget);
    expect(find.text('GitHub Reset'), findsOneWidget);
    expect(find.text('Retry-After'), findsOneWidget);
    expect(find.text('120 s'), findsOneWidget);
    expect(find.text('App retry time'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear history'));
    await tester.pumpAndSettle();

    expect(find.text('No request history yet.'), findsOneWidget);

    expect(store.value, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final (outcome, label) in [
    (ApiDiagnosticOutcome.response, 'HTTP response'),
    (ApiDiagnosticOutcome.blockedByRateLimit, 'Blocked before sending'),
    (
      ApiDiagnosticOutcome.policyBlockedAfterResponse,
      'Requests paused after response',
    ),
    (ApiDiagnosticOutcome.canceledBeforeSend, 'Canceled before sending'),
    (ApiDiagnosticOutcome.timeout, 'Timeout'),
    (ApiDiagnosticOutcome.networkFailure, 'Network failure'),
  ]) {
    testWidgets('DI05: 英語で通信結果を区別できる (${outcome.name})', (tester) async {
      final store = InMemoryApiDiagnostics();
      addTearDown(store.dispose);

      // 実行環境のタイムゾーンに依存しないよう、
      // 端末時刻を指定してからUTCへ変換する。
      final retryAt = outcome == ApiDiagnosticOutcome.policyBlockedAfterResponse
          ? DateTime(2026, 11, 22, 12, 5).toUtc()
          : null;

      final httpStatus = outcome == ApiDiagnosticOutcome.response ? 200 : null;

      store.record(
        ApiDiagnosticEvent(
          recordedAt: DateTime.utc(2026, 11, 22, 12),
          operation: ApiDiagnosticOperation.search,
          outcome: outcome,
          httpStatus: httpStatus,
          policyRetryAt: retryAt,
        ),
      );

      await start(tester, store, locale: const Locale('en', 'US'));

      final title = httpStatus == null
          ? 'Search / $label'
          : 'Search / HTTP $httpStatus';

      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      expect(find.text(label), findsOneWidget);

      expect(find.text('Not reported'), findsOneWidget);

      expect(find.text('Not recorded'), findsWidgets);

      final unknown = find.text('Resume time unknown (requests paused)');

      if (outcome == ApiDiagnosticOutcome.blockedByRateLimit) {
        expect(unknown, findsOneWidget);
      } else {
        expect(unknown, findsNothing);
      }

      if (retryAt != null) {
        expect(find.text('2026-11-22 12:05:00 (device time)'), findsOneWidget);
      }

      expect(store.value, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('DI06: 言語変更時も診断履歴と展開状態を維持する', (tester) async {
    final store = InMemoryApiDiagnostics();
    addTearDown(store.dispose);

    final event = ApiDiagnosticEvent(
      recordedAt: DateTime.utc(2026, 11, 22, 12),
      operation: ApiDiagnosticOperation.search,
      outcome: ApiDiagnosticOutcome.response,
      httpStatus: 200,
      rateLimitLimit: 10,
      rateLimitRemaining: 7,
    );

    store.record(event);

    final originalHistory = store.value;

    await start(tester, store);

    expect(find.text('API通信インスペクター'), findsOneWidget);

    await tester.tap(find.text('検索 / HTTP 200'));
    await tester.pumpAndSettle();

    expect(find.text('結果'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);

    // 英語に変更する。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    expect(find.text('API Request Inspector'), findsOneWidget);
    expect(find.text('Search / HTTP 200'), findsOneWidget);
    expect(find.text('Result'), findsOneWidget);
    expect(find.text('HTTP response'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);
    expect(find.text('結果'), findsNothing);

    // 履歴そのものは変更しない。
    expect(store.value, same(originalHistory));
    expect(store.value.single, same(event));

    // 日本語に戻す。
    tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];

    await tester.pumpAndSettle();

    expect(find.text('API通信インスペクター'), findsOneWidget);
    expect(find.text('検索 / HTTP 200'), findsOneWidget);
    expect(find.text('結果'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);
    expect(store.value, same(originalHistory));

    expect(tester.takeException(), isNull);
  });
}
