import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/devtools/api_diagnostics.dart';
import 'package:yumemi_app/devtools/api_diagnostics_screen.dart';
import 'package:yumemi_app/providers.dart';

void main() {
  testWidgets('DI01: 診断情報を画面に反映する', (tester) async {
    final store = InMemoryApiDiagnostics();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiDiagnosticsProvider.overrideWithValue(store)],
        child: const MaterialApp(home: ApiDiagnosticsScreen()),
      ),
    );

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiDiagnosticsProvider.overrideWithValue(store)],
        child: const MaterialApp(home: ApiDiagnosticsScreen()),
      ),
    );

    await tester.tap(find.text('詳細 / HTTP 429'));
    await tester.pumpAndSettle();

    expect(find.text('120秒'), findsOneWidget);

    await tester.tap(find.byTooltip('履歴を消去'));
    await tester.pumpAndSettle();

    expect(find.text('通信履歴はまだありません'), findsOneWidget);
    expect(store.value, isEmpty);
  });
}
