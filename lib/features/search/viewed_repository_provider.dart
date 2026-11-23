import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/repository_models.dart';

final viewedRepositoryProvider =
    NotifierProvider<ViewedRepositoryController, Set<int>>(
      ViewedRepositoryController.new,
    );

class ViewedRepositoryController extends Notifier<Set<int>> {
  @override
  Set<int> build() => const <int>{};

  void markViewed(RepositoryKey key) {
    if (state.contains(key.id)) return;

    state = Set<int>.unmodifiable({...state, key.id});
  }

  bool isViewed(RepositoryKey key) {
    return state.contains(key.id);
  }

  void clear() {
    state = const <int>{};
  }
}
