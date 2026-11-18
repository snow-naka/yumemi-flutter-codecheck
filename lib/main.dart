import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
      title: 'Repository Search',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: Scaffold(
        appBar: AppBar(title: const Text('Repository Search')),
        body: const SizedBox.shrink(),
      ),
    );
  }
}
