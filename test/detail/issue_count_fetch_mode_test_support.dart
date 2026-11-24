import 'package:yumemi_app/features/detail/issue_count_fetch_preferences.dart';

final class TestIssueCountFetchModeStore implements IssueCountFetchModeStore {
  TestIssueCountFetchModeStore({
    this.mode = IssueCountFetchMode.manual,
    this.readGate,
    this.failRead = false,
  });

  IssueCountFetchMode mode;
  final Future<void>? readGate;
  final bool failRead;

  @override
  Future<IssueCountFetchMode> read() async {
    final gate = readGate;
    if (gate != null) {
      await gate;
    }

    if (failRead) {
      throw StateError('Test read failure');
    }

    return mode;
  }

  @override
  Future<void> write(IssueCountFetchMode mode) async {
    this.mode = mode;
  }
}
