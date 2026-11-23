import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/features/detail/repository_detail_cache.dart';
import 'package:yumemi_app/models/repository_models.dart';

RepositoryDetail makeDetail(int id) {
  final summary = RepositorySummary(
    key: RepositoryKey(id: id, owner: 'sample', name: 'repository-$id'),
    avatarUrl: '',
    language: 'Dart',
    starCount: 10,
    forkCount: 2,
    openIssueAndPullRequestCount: 1,
  );

  return RepositoryDetail(summary: summary, watcherCount: 3);
}

void main() {
  test('DC01: 15分以内は再利用し期限到達時に失効する', () {
    final start = DateTime.utc(2026, 11, 23, 12);
    var now = start;

    final cache = RepositoryDetailCache(now: () => now);
    final detail = makeDetail(1);
    final key = detail.summary.key;

    cache.put(key, detail);

    now = start.add(const Duration(minutes: 14));
    expect(cache.getFresh(key), same(detail));

    now = start.add(const Duration(minutes: 15));
    expect(cache.getFresh(key), isNull);

    expect(cache.length, 0);
  });

  test('DC02: 上限超過時は最も古く利用されたデータを削除', () {
    final cache = RepositoryDetailCache(capacity: 2);

    final a = makeDetail(1);
    final b = makeDetail(2);
    final c = makeDetail(3);

    cache.put(a.summary.key, a);
    cache.put(b.summary.key, b);

    // Aを再利用したのでBが最も古くなる。
    expect(cache.getFresh(a.summary.key), same(a));

    cache.put(c.summary.key, c);

    expect(cache.length, 2);
    expect(cache.getFresh(a.summary.key), same(a));
    expect(cache.getFresh(b.summary.key), isNull);
    expect(cache.getFresh(c.summary.key), same(c));
  });

  test('DC03: 手動更新用の無効化は対象だけに作用', () {
    final cache = RepositoryDetailCache();

    final a = makeDetail(1);
    final b = makeDetail(2);

    cache.put(a.summary.key, a);
    cache.put(b.summary.key, b);

    cache.invalidate(a.summary.key);

    expect(cache.getFresh(a.summary.key), isNull);
    expect(cache.getFresh(b.summary.key), same(b));

    cache.clear();
    expect(cache.length, 0);
  });

  test('DC09: 容量超過時は期限切れを優先し有効なLRUを保持する', () {
    final start = DateTime.utc(2026, 11, 23, 12);
    var now = start;

    final cache = RepositoryDetailCache(
      capacity: 2,
      ttl: const Duration(minutes: 15),
      now: () => now,
    );

    final a = makeDetail(1);
    final b = makeDetail(2);
    final c = makeDetail(3);

    // 0分：Aを保存。有効期限は15分。
    cache.put(a.summary.key, a);

    // 5分：Bを保存。有効期限は20分。
    now = start.add(const Duration(minutes: 5));
    cache.put(b.summary.key, b);

    // 14分：Aを参照してLRU順を更新。
    now = start.add(const Duration(minutes: 14));
    expect(cache.getFresh(a.summary.key), same(a));

    // 16分：Aは期限切れ、Bはまだ有効。
    // Cを保存すると容量が3件になり、整理が必要。
    now = start.add(const Duration(minutes: 16));
    cache.put(c.summary.key, c);

    // 期限切れのAが削除される。
    expect(cache.getFresh(a.summary.key), isNull);

    // 有効なBは、LRU順が古くても保持される。
    expect(cache.getFresh(b.summary.key), same(b));

    // 新しく保存したCも保持される。
    expect(cache.getFresh(c.summary.key), same(c));

    expect(cache.length, 2);
  });
}
