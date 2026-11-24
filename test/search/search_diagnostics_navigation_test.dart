import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/devtools/api_diagnostics.dart';
import 'package:yumemi_app/features/search/search_screen.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/l10n/app_localizations.dart';
import 'package:yumemi_app/main.dart';

void main() {
  testWidgets('DI03: 検索画面から診断画面を開き履歴を維持', (tester) async {
    final store = InMemoryApiDiagnostics();
    addTearDown(store.dispose);

    store.record(
      ApiDiagnosticEvent(
        recordedAt: DateTime.utc(2026, 11, 22, 12),
        operation: ApiDiagnosticOperation.search,
        outcome: ApiDiagnosticOutcome.response,
        httpStatus: 200,
        rateLimitLimit: 10,
        rateLimitRemaining: 7,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiDiagnosticsProvider.overrideWithValue(store)],
        child: const MaterialApp(
          locale: Locale('ja'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SearchScreen(),
        ),
      ),
    );

    final button = find.byKey(const Key('open-api-diagnostics'));

    expect(button, findsOneWidget);

    // 検索画面から診断画面へ。
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('API通信インスペクター'), findsOneWidget);
    expect(find.text('検索 / HTTP 200'), findsOneWidget);

    // 検索画面に戻る。
    final backButton = find.byType(BackButton);
    expect(backButton, findsOneWidget);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    expect(find.text('リポジトリ検索'), findsOneWidget);

    // 再び開いても履歴が残る。
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('検索 / HTTP 200'), findsOneWidget);
  });

  testWidgets('DM04: テーマ変更時も診断履歴と展開状態を維持する', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

    tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];

    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiDiagnosticsProvider.overrideWithValue(store)],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-api-diagnostics')));

    await tester.pumpAndSettle();

    final title = find.text('API通信インスペクター');

    Brightness currentBrightness() =>
        Theme.of(tester.element(title)).brightness;

    expect(currentBrightness(), Brightness.light);

    await tester.tap(find.text('検索 / HTTP 200'));
    await tester.pumpAndSettle();

    expect(find.text('結果'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);

    // 展開中にダークモードへ変更。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

    await tester.pumpAndSettle();

    expect(currentBrightness(), Brightness.dark);
    expect(find.text('結果'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);

    expect(store.value, same(originalHistory));
    expect(store.value.single, same(event));

    // ライトモードへ戻す。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

    await tester.pumpAndSettle();

    expect(currentBrightness(), Brightness.light);
    expect(find.text('結果'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);

    expect(store.value, same(originalHistory));
    expect(tester.takeException(), isNull);
  });
}
