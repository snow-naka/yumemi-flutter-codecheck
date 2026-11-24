import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'features/search/search_screen.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(
    ProviderScope(
      // Issue #3では暫定無効。実通信の再試行方針はPhase 2で再検討する。
      retry: (retryCount, error) => null,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,

      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],

      supportedLocales: AppLocalizations.supportedLocales,

      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),

      home: const SearchScreen(),
    );
  }
}
