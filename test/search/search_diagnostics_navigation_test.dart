import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/devtools/api_diagnostics.dart';
import 'package:yumemi_app/features/search/search_screen.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/l10n/app_localizations.dart';

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
}
