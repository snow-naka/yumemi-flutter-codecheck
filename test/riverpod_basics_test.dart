import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:yumemi_app/main.dart' as app;

// 学習用の状態と依存先。本番の検索・詳細のProviderではない。
final _incrementAmountProvider = Provider<int>((ref) => 1);
final _counterProvider = NotifierProvider<_Counter, int>(_Counter.new);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() {
    state += ref.read(_incrementAmountProvider);
  }
}

void main() {
  testWidgets('watch rebuilds its consumer; read does not subscribe', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _CounterExample()));

    expect(find.text('watch: 0'), findsOneWidget);
    expect(find.text('read: 0'), findsOneWidget);

    await tester.tap(find.text('Increment'));
    await tester.pump();

    expect(find.text('watch: 1'), findsOneWidget);
    expect(find.text('read: 0'), findsOneWidget);
    expect(tester.container().read(_counterProvider), 1);

    await tester.tap(find.text('Increment'));
    await tester.pump();

    expect(find.text('watch: 2'), findsOneWidget);
    expect(find.text('read: 0'), findsOneWidget);
    expect(tester.container().read(_counterProvider), 2);
  });

  testWidgets('override changes the dependency without changing the consumer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [_incrementAmountProvider.overrideWithValue(5)],
        child: const _CounterExample(),
      ),
    );

    await tester.tap(find.text('Increment'));
    await tester.pump();

    expect(find.text('watch: 5'), findsOneWidget);
    expect(find.text('read: 0'), findsOneWidget);
  });

  test('overrides and state do not leak into another container', () {
    final overridden = ProviderContainer.test(
      overrides: [_incrementAmountProvider.overrideWithValue(5)],
    );
    final normal = ProviderContainer.test();

    overridden.read(_counterProvider.notifier).increment();
    expect(overridden.read(_counterProvider), 5);
    expect(normal.read(_counterProvider), 0);

    normal.read(_counterProvider.notifier).increment();
    expect(normal.read(_counterProvider), 1);
    expect(overridden.read(_counterProvider), 5);
  });

  testWidgets('MyApp uses the externally supplied scope', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [_incrementAmountProvider.overrideWithValue(7)],
        child: const app.MyApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    expect(find.byType(ProviderScope), findsOneWidget);
    expect(container.read(_incrementAmountProvider), 7);
  });

  testWidgets('app scope disables automatic retry but permits invalidation', (
    tester,
  ) async {
    var attempts = 0;
    final failure = Exception('Learning example failure');
    final failingProvider = FutureProvider<int>((ref) async {
      attempts++;
      throw failure;
    });

    app.main();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    final subscription = container.listen(failingProvider, (_, _) {});
    addTearDown(subscription.close);

    await tester.pump();
    expect(subscription.read().asError?.error, same(failure));
    expect(attempts, 1);

    // Widgetテストの仮想時間を進める。実時間の待機は行わない。
    await tester.pump(const Duration(seconds: 30));
    expect(subscription.read().asError?.error, same(failure));
    expect(attempts, 1);

    container.invalidate(failingProvider);
    await tester.pump();
    expect(subscription.read().asError?.error, same(failure));
    expect(attempts, 2);
  });
}

class _CounterExample extends StatelessWidget {
  const _CounterExample();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [_WatchedCount(), _ReadCount(), _IncrementButton()],
        ),
      ),
    );
  }
}

class _WatchedCount extends ConsumerWidget {
  const _WatchedCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(_counterProvider);
    return Text('watch: $count');
  }
}

class _ReadCount extends ConsumerWidget {
  const _ReadCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 比較用の例。更新に追随する本番表示にはwatchを使う。
    final count = ref.read(_counterProvider);
    return Text('read: $count');
  }
}

class _IncrementButton extends ConsumerWidget {
  const _IncrementButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => ref.read(_counterProvider.notifier).increment(),
      child: const Text('Increment'),
    );
  }
}
