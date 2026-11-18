import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'search_controller.dart';
import 'search_state.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _input = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    if (ref.read(searchControllerProvider) is SearchLoading) return;
    if (!_formKey.currentState!.validate()) return;
    unawaited(ref.read(searchControllerProvider.notifier).search(_input.text));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final loading = state is SearchLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Repository Search')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _input,
                  decoration: const InputDecoration(labelText: 'キーワード'),
                  textInputAction: TextInputAction.search,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '検索キーワードを入力してください。'
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: loading ? null : _submit,
                child: const Text('検索'),
              ),
              if (state.query != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('送信済みの検索語：${state.query}'),
                ),
              Expanded(child: _content(state)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(SearchState state) {
    return switch (state) {
      SearchInitial() => const Center(child: Text('キーワードを入力して検索してください。')),
      SearchLoading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('検索中…'),
          ],
        ),
      ),
      SearchFailure(:final query, :final failure) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(failure.safeMessage),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => unawaited(
                ref.read(searchControllerProvider.notifier).search(query),
              ),
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
      SearchSuccess(:final result) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result.incompleteResults) const Text('検索結果が不完全な可能性があります。'),
          Text('表示中：${result.items.length}件（総件数：${result.totalCount}件）'),
          if (result.totalCount > result.items.length &&
              result.items.isNotEmpty)
            const Text('1ページ分の結果を表示しています。'),
          const SizedBox(height: 8),
          Expanded(
            child: result.items.isEmpty
                ? Center(
                    child: Text(
                      result.incompleteResults
                          ? '表示できる結果がありません。検索結果が不完全な可能性があります。'
                          : '一致するリポジトリは見つかりませんでした。',
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: result.items.length,
                    itemBuilder: (context, index) {
                      final repository = result.items[index];
                      return ListTile(
                        key: ValueKey(repository.key),
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(repository.name),
                        subtitle: Text(
                          '${repository.fullName} / ${repository.language ?? '未指定'}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    };
  }
}
