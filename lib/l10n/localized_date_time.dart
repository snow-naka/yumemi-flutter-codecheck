import 'package:intl/intl.dart';

/// 日時を端末のタイムゾーンに変換し、
/// 現在の表示言語に対応した24時間表記で返す。
///
/// 診断画面では秒まで、詳細画面では分まで表示する。
String formatDeviceDateTime(
  DateTime value, {
  required String localeName,
  bool includeSeconds = false,
}) {
  final local = value.toLocal();
  final formatter = DateFormat.yMd(localeName);

  if (includeSeconds) {
    formatter.add_Hms();
  } else {
    formatter.add_Hm();
  }

  return formatter.format(local);
}
