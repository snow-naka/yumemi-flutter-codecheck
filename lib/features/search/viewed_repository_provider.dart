import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/repository_models.dart';

final viewedRepositoryProvider =
    NotifierProvider<ViewedRepositoryController, Set<RepositoryKey>>(
      ViewedRepositoryController.new,
    );

class ViewedRepositoryController extends Notifier<Set<RepositoryKey>> {
  @override
  Set<RepositoryKey> build() {
    return Set<RepositoryKey>.unmodifiable({});
  }

  /// 詳細画面を開いたリポジトリを閲覧済みにする。
  void markViewed(RepositoryKey key) {
    if (state.contains(key)) return;

    state = Set<RepositoryKey>.unmodifiable({...state, key});
  }

  /// 閲覧済みか判定する。
  bool isViewed(RepositoryKey key) {
    return state.contains(key);
  }

  /// 閲覧履歴を明示的に消去する場合に使用。
  void clear() {
    state = Set<RepositoryKey>.unmodifiable({});
  }
}
