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
}
