import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum IssueCountFetchMode { automatic, manual }

abstract interface class IssueCountFetchModeStore {
  Future<IssueCountFetchMode> read();
  Future<void> write(IssueCountFetchMode mode);
}

final class SharedPreferencesIssueCountFetchModeStore
    implements IssueCountFetchModeStore {
  SharedPreferencesIssueCountFetchModeStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'detail.issue_count_fetch_mode.v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<IssueCountFetchMode> read() async {
    final value = await _preferences.getString(_key);

    // 未保存の場合は初期設定として自動取得を使用する。
    // 未知の設定値では意図しない自動通信を避ける。
    return switch (value) {
      null || 'automatic' => IssueCountFetchMode.automatic,
      'manual' => IssueCountFetchMode.manual,
      _ => IssueCountFetchMode.manual,
    };
  }

  @override
  Future<void> write(IssueCountFetchMode mode) {
    return _preferences.setString(_key, mode.name);
  }
}

final issueCountFetchModeStoreProvider = Provider<IssueCountFetchModeStore>(
  (ref) => SharedPreferencesIssueCountFetchModeStore(),
);
