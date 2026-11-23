import '../../models/repository_models.dart';

/// PRを除いたOpen Issue数と取得日時。
final class OpenIssueCountEntry {
  const OpenIssueCountEntry({required this.count, required this.fetchedAt});

  final int count;
  final DateTime fetchedAt;
}

/// アプリ起動中だけ保持するIssue数キャッシュ。
///
/// 詳細情報キャッシュとは独立しており、
/// 自動失効・自動再取得は行わない。
final class OpenIssueCountCache {
  OpenIssueCountCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  final Map<RepositoryKey, OpenIssueCountEntry> _entries = {};

  int get length => _entries.length;

  OpenIssueCountEntry? get(RepositoryKey key) {
    return _entries[key];
  }

  void put(RepositoryKey key, int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count');
    }

    _entries[key] = OpenIssueCountEntry(
      count: count,
      fetchedAt: _now().toUtc(),
    );
  }

  void clear() {
    _entries.clear();
  }
}
