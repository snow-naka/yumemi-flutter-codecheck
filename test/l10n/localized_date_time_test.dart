import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yumemi_app/l10n/localized_date_time.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  for (final (locale, minutes, seconds) in [
    ('ja', '2026/11/22 12:05', '2026/11/22 12:05:09'),
    ('en', '11/22/2026 12:05', '11/22/2026 12:05:09'),
  ]) {
    test('LF01: 端末時刻を言語に応じて表示する ($locale)', () {
      // 実行環境のタイムゾーンに依存しないテストデータ。
      final local = DateTime(2026, 11, 22, 12, 5, 9);
      final utc = local.toUtc();

      expect(formatDeviceDateTime(utc, localeName: locale), minutes);

      expect(
        formatDeviceDateTime(utc, localeName: locale, includeSeconds: true),
        seconds,
      );

      // ローカル日時を渡した場合も同じ表示になる。
      expect(
        formatDeviceDateTime(local, localeName: locale, includeSeconds: true),
        seconds,
      );
    });
  }
}
