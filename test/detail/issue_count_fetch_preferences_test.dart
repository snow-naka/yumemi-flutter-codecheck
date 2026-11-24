import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yumemi_app/features/detail/issue_count_fetch_preferences.dart';

const _key = 'detail.issue_count_fetch_mode.v1';

class _FakePreferences implements SharedPreferencesAsync {
  _FakePreferences({this.failRead = false, this.failWrite = false});

  final Map<String, String> values = {};

  final bool failRead;
  final bool failWrite;

  @override
  Future<String?> getString(String key) async {
    if (failRead) {
      throw StateError('Read failed');
    }
    return values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    if (failWrite) {
      throw StateError('Write failed');
    }
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePreferences preferences;
  late SharedPreferencesIssueCountFetchModeStore store;

  setUp(() {
    preferences = _FakePreferences();
    store = SharedPreferencesIssueCountFetchModeStore(preferences: preferences);
  });

  test('IP01: 設定未保存時は自動取得', () async {
    expect(await store.read(), IssueCountFetchMode.automatic);
    expect(preferences.values, isEmpty);
  });

  test('IP02: 保存済みの自動取得設定を読み込む', () async {
    preferences.values[_key] = 'automatic';

    expect(await store.read(), IssueCountFetchMode.automatic);
  });

  test('IP03: 保存済みの手動取得設定を読み込む', () async {
    preferences.values[_key] = 'manual';

    expect(await store.read(), IssueCountFetchMode.manual);
  });

  test('IP04: 未知の設定値では手動取得にする', () async {
    preferences.values[_key] = 'unknown';

    expect(await store.read(), IssueCountFetchMode.manual);

    // 不明な保存値を読み込み時に勝手に変更しない。
    expect(preferences.values[_key], 'unknown');
  });

  test('IP05: 手動取得を保存して再読み込みできる', () async {
    await store.write(IssueCountFetchMode.manual);

    expect(preferences.values[_key], 'manual');

    final reopenedStore = SharedPreferencesIssueCountFetchModeStore(
      preferences: preferences,
    );

    expect(await reopenedStore.read(), IssueCountFetchMode.manual);
  });

  test('IP06: 自動取得への変更を保存できる', () async {
    await store.write(IssueCountFetchMode.manual);
    await store.write(IssueCountFetchMode.automatic);

    expect(preferences.values[_key], 'automatic');

    final reopenedStore = SharedPreferencesIssueCountFetchModeStore(
      preferences: preferences,
    );

    expect(await reopenedStore.read(), IssueCountFetchMode.automatic);
  });

  test('IP07: 読み込み失敗を呼び出し側に伝える', () async {
    preferences = _FakePreferences(failRead: true);

    store = SharedPreferencesIssueCountFetchModeStore(preferences: preferences);

    await expectLater(store.read(), throwsA(isA<StateError>()));
  });

  test('IP08: 保存失敗を呼び出し側に伝える', () async {
    preferences = _FakePreferences(failWrite: true);
    preferences.values[_key] = 'manual';

    store = SharedPreferencesIssueCountFetchModeStore(preferences: preferences);

    await expectLater(
      store.write(IssueCountFetchMode.automatic),
      throwsA(isA<StateError>()),
    );

    expect(preferences.values[_key], 'manual');
  });
}
