import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'issue_count_fetch_preferences.dart';

final class IssueCountFetchModeState {
  const IssueCountFetchModeState({
    required this.mode,
    this.isSaving = false,
    this.readFailed = false,
  });

  final IssueCountFetchMode mode;
  final bool isSaving;
  final bool readFailed;

  // 設定保存中や読み込み失敗時は自動取得を開始しない。
  bool get allowsAutomaticFetch =>
      mode == IssueCountFetchMode.automatic && !isSaving && !readFailed;
}

final issueCountFetchModeProvider =
    AsyncNotifierProvider<
      IssueCountFetchModeNotifier,
      IssueCountFetchModeState
    >(IssueCountFetchModeNotifier.new, retry: (retryCount, error) => null);

final class IssueCountFetchModeNotifier
    extends AsyncNotifier<IssueCountFetchModeState> {
  @override
  Future<IssueCountFetchModeState> build() async {
    try {
      final mode = await ref.read(issueCountFetchModeStoreProvider).read();

      return IssueCountFetchModeState(mode: mode);
    } catch (_) {
      // 読み込み失敗時は意図しない自動通信を避ける。
      return const IssueCountFetchModeState(
        mode: IssueCountFetchMode.manual,
        readFailed: true,
      );
    }
  }

  Future<bool> changeMode(IssueCountFetchMode mode) async {
    final snapshot = state;
    final previous = snapshot.asData?.value;

    // 読み込み中・保存中の変更を禁止する。
    if (snapshot.isLoading || previous == null || previous.isSaving) {
      return false;
    }

    if (previous.mode == mode && !previous.readFailed) {
      return true;
    }

    final operationRef = ref;

    // 保存成功までは変更前の設定を維持する。
    state = AsyncData(
      IssueCountFetchModeState(
        mode: previous.mode,
        isSaving: true,
        readFailed: previous.readFailed,
      ),
    );

    try {
      await operationRef.read(issueCountFetchModeStoreProvider).write(mode);
    } catch (_) {
      if (!operationRef.mounted) return false;

      state = AsyncData(previous);
      return false;
    }

    if (!operationRef.mounted) return false;

    state = AsyncData(IssueCountFetchModeState(mode: mode));

    return true;
  }
}
