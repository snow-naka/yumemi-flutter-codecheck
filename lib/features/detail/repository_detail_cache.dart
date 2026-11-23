import 'dart:collection';

import '../../models/repository_models.dart';

/// 詳細情報のメモリキャッシュ。
///
/// - 最大100件
/// - 取得成功から15分有効
/// - 容量超過時はLRUで削除
final class RepositoryDetailCache {
  RepositoryDetailCache({
    this.capacity = 100,
    this.ttl = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : assert(capacity > 0),
       assert(ttl > Duration.zero),
       _now = now ?? DateTime.now;

  final int capacity;
  final Duration ttl;
  final DateTime Function() _now;

  // LinkedHashMapは挿入順を保持する。
  // 最後の要素を最も最近利用したものとして扱う。
  final LinkedHashMap<RepositoryKey, _CacheEntry> _entries =
      LinkedHashMap<RepositoryKey, _CacheEntry>();

  int get length => _entries.length;

  RepositoryDetail? getFresh(RepositoryKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;

    final current = _now().toUtc();

    // 期限到達時点からキャッシュは無効。
    if (!current.isBefore(entry.expiresAt)) {
      return null;
    }

    // 利用したデータを末尾へ移動してLRU順を更新。
    _entries[key] = entry;
    return entry.detail;
  }

  void put(RepositoryKey key, RepositoryDetail detail) {
    _entries.remove(key);

    _entries[key] = _CacheEntry(
      detail: detail,
      expiresAt: _now().toUtc().add(ttl),
    );

    // 最も古く利用されたデータから削除する。
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 手動更新時に対象の古いキャッシュを無効化する。
  void invalidate(RepositoryKey key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }
}

final class _CacheEntry {
  const _CacheEntry({required this.detail, required this.expiresAt});

  final RepositoryDetail detail;
  final DateTime expiresAt;
}
