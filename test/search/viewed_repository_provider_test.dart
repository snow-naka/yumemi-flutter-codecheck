import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/features/search/viewed_repository_provider.dart';
import 'package:yumemi_app/models/repository_models.dart';

void main() {
  const keyA = RepositoryKey(id: 1, owner: 'sample', name: 'example-a');

  const keyB = RepositoryKey(id: 2, owner: 'sample', name: 'example-b');

  test('VH01: 閲覧したリポジトリだけを記録する', () {
    final container = ProviderContainer.test();

    final controller = container.read(viewedRepositoryProvider.notifier);

    expect(container.read(viewedRepositoryProvider), isEmpty);

    controller.markViewed(keyA);

    expect(controller.isViewed(keyA), isTrue);
    expect(controller.isViewed(keyB), isFalse);
    expect(container.read(viewedRepositoryProvider), hasLength(1));

    controller.markViewed(keyB);

    expect(container.read(viewedRepositoryProvider), hasLength(2));
  });

  test('VH02: 同一リポジトリの再閲覧で重複せず履歴を維持', () {
    final container = ProviderContainer.test();

    final controller = container.read(viewedRepositoryProvider.notifier);

    controller.markViewed(keyA);

    // 同じ値を持つ別インスタンスでも同一リポジトリ。
    const equivalentKey = RepositoryKey(
      id: 1,
      owner: 'sample',
      name: 'example-a',
    );

    controller.markViewed(equivalentKey);

    expect(container.read(viewedRepositoryProvider), hasLength(1));
    expect(controller.isViewed(equivalentKey), isTrue);

    // 明示的な消去では履歴が空になる。
    controller.clear();

    expect(container.read(viewedRepositoryProvider), isEmpty);
  });
  test('VH06: 同じIDなら改名後も閲覧済みを維持する', () {
    final container = ProviderContainer.test();
    final controller = container.read(viewedRepositoryProvider.notifier);

    const oldKey = RepositoryKey(id: 100, owner: 'org', name: 'old');

    const renamedKey = RepositoryKey(id: 100, owner: 'org', name: 'renamed');

    controller.markViewed(oldKey);

    expect(controller.isViewed(renamedKey), isTrue);
    expect(container.read(viewedRepositoryProvider), hasLength(1));
  });
}
