import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:yumemi_app/main.dart' as app;

void main() {
  testWidgets('App starts with a ProviderScope and a minimal Material view', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    app.main();
    await tester.pump();

    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Repository Search'), findsOneWidget);
  });
}
