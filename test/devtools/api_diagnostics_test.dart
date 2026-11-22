import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/devtools/api_diagnostics.dart';

void main() {
  ApiDiagnosticEvent event(int status) {
    return ApiDiagnosticEvent(
      recordedAt: DateTime.utc(2026, 11, 22, 12),
      operation: ApiDiagnosticOperation.search,
      outcome: ApiDiagnosticOutcome.response,
      httpStatus: status,
    );
  }

  test('AD01: 直近の指定件数だけ保持する', () {
    final store = InMemoryApiDiagnostics(maxEntries: 2);
    addTearDown(store.dispose);

    store.record(event(200));
    store.record(event(403));
    store.record(event(429));

    expect(store.value.length, 2);
    expect(store.value.map((e) => e.httpStatus).toList(), [403, 429]);
  });

  test('AD02: 記録追加を通知し、一覧の外部変更を禁止する', () {
    final store = InMemoryApiDiagnostics();
    addTearDown(store.dispose);

    var notifications = 0;
    store.addListener(() => notifications++);

    store.record(event(200));

    expect(notifications, 1);
    expect(store.value.single.httpStatus, 200);

    expect(() => store.value.add(event(429)), throwsUnsupportedError);

    store.clear();

    expect(store.value, isEmpty);
    expect(notifications, 2);
  });

  test('AD03: 破棄後の診断通知は無視する', () {
    final store = InMemoryApiDiagnostics();

    store.record(event(200));
    store.dispose();

    // 診断先が破棄されても例外を発生させない。
    expect(() => store.record(event(429)), returnsNormally);
    expect(store.value.length, 1);
  });
}
