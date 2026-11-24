import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/features/detail/issue_count_fetch_mode_provider.dart';
import 'package:yumemi_app/features/detail/issue_count_fetch_preferences.dart';

final class _FakeStore implements IssueCountFetchModeStore {
  IssueCountFetchMode mode = IssueCountFetchMode.automatic;

  bool failRead = false;
  bool failWrite = false;

  int readCalls = 0;
  int writeCalls = 0;

  Completer<void>? readGate;
  Completer<void>? writeGate;

  @override
  Future<IssueCountFetchMode> read() async {
    readCalls++;

    final gate = readGate;
    if (gate != null) {
      await gate.future;
    }

    if (failRead) {
      throw StateError('Read failed');
    }

    return mode;
  }

  @override
  Future<void> write(IssueCountFetchMode mode) async {
    writeCalls++;

    final gate = writeGate;
    if (gate != null) {
      await gate.future;
    }

    if (failWrite) {
      throw StateError('Write failed');
    }

    this.mode = mode;
  }
}

void main() {
  late _FakeStore store;
  late ProviderContainer container;

  final provider = issueCountFetchModeProvider;

  IssueCountFetchModeState current() => container.read(provider).requireValue;

  IssueCountFetchModeNotifier notifier() => container.read(provider.notifier);

  Future<IssueCountFetchModeState> initialize() =>
      container.read(provider.future);

  setUp(() {
    store = _FakeStore();

    container = ProviderContainer(
      overrides: [issueCountFetchModeStoreProvider.overrideWithValue(store)],
    );

    addTearDown(container.dispose);
  });

  test('IM01: 読み込み完了まで設定変更を禁止する', () async {
    store.readGate = Completer<void>();

    final pending = initialize();

    expect(container.read(provider).isLoading, isTrue);

    expect(await notifier().changeMode(IssueCountFetchMode.manual), isFalse);

    expect(store.writeCalls, 0);

    store.readGate!.complete();
    await pending;

    expect(current().mode, IssueCountFetchMode.automatic);
    expect(current().allowsAutomaticFetch, isTrue);
  });

  test('IM02: 保存済みの手動取得設定を復元する', () async {
    store.mode = IssueCountFetchMode.manual;

    await initialize();

    expect(current().mode, IssueCountFetchMode.manual);
    expect(current().allowsAutomaticFetch, isFalse);
    expect(current().readFailed, isFalse);

    // 同じProviderContainerでは設定を再読み込みしない。
    await initialize();

    expect(store.readCalls, 1);
  });

  test('IM03: 読み込み失敗時は手動取得にする', () async {
    store.failRead = true;

    await initialize();

    expect(current().mode, IssueCountFetchMode.manual);
    expect(current().readFailed, isTrue);
    expect(current().allowsAutomaticFetch, isFalse);
    expect(store.writeCalls, 0);
  });

  test('IM04: 保存成功後に設定変更を確定する', () async {
    await initialize();

    store.writeGate = Completer<void>();

    final pending = notifier().changeMode(IssueCountFetchMode.manual);

    expect(current().mode, IssueCountFetchMode.automatic);
    expect(current().isSaving, isTrue);
    expect(current().allowsAutomaticFetch, isFalse);
    expect(store.mode, IssueCountFetchMode.automatic);

    store.writeGate!.complete();

    expect(await pending, isTrue);
    expect(current().mode, IssueCountFetchMode.manual);
    expect(current().isSaving, isFalse);
    expect(current().allowsAutomaticFetch, isFalse);
    expect(store.mode, IssueCountFetchMode.manual);
    expect(store.writeCalls, 1);
  });

  test('IM05: 保存失敗時は変更前の設定を維持する', () async {
    store.mode = IssueCountFetchMode.manual;

    await initialize();

    store.failWrite = true;

    expect(await notifier().changeMode(IssueCountFetchMode.automatic), isFalse);

    expect(current().mode, IssueCountFetchMode.manual);
    expect(current().isSaving, isFalse);
    expect(current().allowsAutomaticFetch, isFalse);
    expect(store.mode, IssueCountFetchMode.manual);

    // 保存失敗後も再試行できる。
    store.failWrite = false;

    expect(await notifier().changeMode(IssueCountFetchMode.automatic), isTrue);

    expect(current().allowsAutomaticFetch, isTrue);
    expect(store.mode, IssueCountFetchMode.automatic);
  });

  test('IM06: 保存中の重複変更を拒否する', () async {
    await initialize();

    store.writeGate = Completer<void>();

    final first = notifier().changeMode(IssueCountFetchMode.manual);

    expect(current().isSaving, isTrue);

    expect(await notifier().changeMode(IssueCountFetchMode.automatic), isFalse);

    expect(store.writeCalls, 1);

    store.writeGate!.complete();

    expect(await first, isTrue);
    expect(current().mode, IssueCountFetchMode.manual);
  });

  test('IM07: 同一設定を不要に再保存しない', () async {
    await initialize();

    expect(await notifier().changeMode(IssueCountFetchMode.automatic), isTrue);

    expect(store.writeCalls, 0);
    expect(current().allowsAutomaticFetch, isTrue);
  });

  test('IM08: 読み込み失敗後も設定を再設定できる', () async {
    store.failRead = true;

    await initialize();

    expect(current().readFailed, isTrue);
    expect(current().mode, IssueCountFetchMode.manual);

    // フォールバックと同じ設定でも明示的な選択は保存する。
    expect(await notifier().changeMode(IssueCountFetchMode.manual), isTrue);

    expect(current().readFailed, isFalse);
    expect(store.mode, IssueCountFetchMode.manual);
    expect(store.writeCalls, 1);
    expect(current().allowsAutomaticFetch, isFalse);

    expect(await notifier().changeMode(IssueCountFetchMode.automatic), isTrue);

    expect(current().allowsAutomaticFetch, isTrue);
    expect(store.writeCalls, 2);
  });
}
