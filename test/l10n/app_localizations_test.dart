import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/l10n/app_localizations.dart';

void main() {
  const cases = [
    (
      deviceLocale: Locale('ja', 'JP'),
      expectedLocale: Locale('ja'),
      expectedTitle: 'リポジトリ検索',
      expectedBackTooltip: '戻る',
    ),
    (
      deviceLocale: Locale('en', 'US'),
      expectedLocale: Locale('en'),
      expectedTitle: 'Repository Search',
      expectedBackTooltip: 'Back',
    ),
    (
      deviceLocale: Locale('fr', 'FR'),
      expectedLocale: Locale('en'),
      expectedTitle: 'Repository Search',
      expectedBackTooltip: 'Back',
    ),
  ];

  for (final testCase in cases) {
    testWidgets('L01: 端末言語に応じた翻訳を取得できる'
        ' (${testCase.deviceLocale})', (tester) async {
      tester.platformDispatcher.localesTestValue = [testCase.deviceLocale];

      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              expect(Localizations.localeOf(context), testCase.expectedLocale);

              expect(
                MaterialLocalizations.of(context).backButtonTooltip,
                testCase.expectedBackTooltip,
              );

              return Scaffold(
                body: Text(AppLocalizations.of(context).appTitle),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text(testCase.expectedTitle), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  }
}
