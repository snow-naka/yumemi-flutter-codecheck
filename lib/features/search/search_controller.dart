import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/api_failure.dart';
import '../../providers.dart';
import 'search_state.dart';

// 詳細へ移動しても検索結果を保持するため、自動破棄しない。
final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchInitial();

  Future<void> search(String input) async {
    if (state is SearchLoading) return;
    final query = input.trim();
    if (query.isEmpty) return;

    final requestRef = ref;
    final gateway = requestRef.read(githubRepositoryGatewayProvider);
    state = SearchLoading(query);
    try {
      final result = await gateway.searchRepositories(query);
      // 無効化・破棄前の要求が、新しい検索状態を上書きしないようにする。
      if (!requestRef.mounted) return;
      state = SearchSuccess(query, result);
    } on ApiFailure catch (failure) {
      if (!requestRef.mounted) return;
      state = SearchFailure(query, failure);
    }
  }
}
