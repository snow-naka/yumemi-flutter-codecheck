import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/features/detail/open_issue_count_cache.dart';
import 'package:yumemi_app/models/repository_models.dart';

void main() {
  const keyA = RepositoryKey(id: 1, owner: 'sample', name: 'example-a');

  const keyB = RepositoryKey(id: 2, owner: 'sample', name: 'example-b');

  test('IC09: 取得日時とIssue数を保持し自動失効しない', () {
    final start = DateTime.utc(2026, 11, 23, 12);
    var now = start;

    final cache = OpenIssueCountCache(now: () => now);

    expect(cache.get(keyA), isNull);

    cache.put(keyA, 7);

    expect(cache.get(keyA)?.count, 7);
    expect(cache.get(keyA)?.fetchedAt, start);

    // 15分を過ぎてもIssue数は失効しない。
    now = start.add(const Duration(hours: 2));

    expect(cache.get(keyA)?.count, 7);
    expect(cache.get(keyA)?.fetchedAt, start);
  });

  test('IC10: リポジトリ別に保存し明示更新だけで値を変更', () {
    final start = DateTime.utc(2026, 11, 23, 12);
    var now = start;

    final cache = OpenIssueCountCache(now: () => now);

    cache.put(keyA, 7);
    cache.put(keyB, 0);

    expect(cache.length, 2);
    expect(cache.get(keyA)?.count, 7);
    expect(cache.get(keyB)?.count, 0);

    // Aだけ再取得したときの更新を模擬。
    now = start.add(const Duration(minutes: 20));
    cache.put(keyA, 9);

    expect(cache.get(keyA)?.count, 9);
    expect(cache.get(keyA)?.fetchedAt, now);

    // Bの取得済み情報には影響しない。
    expect(cache.get(keyB)?.count, 0);
    expect(cache.get(keyB)?.fetchedAt, start);

    cache.clear();

    expect(cache.length, 0);
  });
}
