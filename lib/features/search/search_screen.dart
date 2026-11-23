import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../devtools/api_diagnostics_screen.dart';
import '../../models/repository_models.dart';
import '../detail/repository_detail_provider.dart';
import '../detail/repository_detail_screen.dart';
import 'search_controller.dart';
import 'search_state.dart';
import 'viewed_repository_provider.dart';

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
    final current = ref.read(searchControllerProvider);

    // 初回検索中・追加読み込み中は新しい検索を受け付けない。
    if (current is SearchLoading ||
        (current is SearchResults && current.loadMore is LoadMoreLoading)) {
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // 新規検索では、描画タイミングに関係なく一覧を先頭へ戻す。
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }

    unawaited(ref.read(searchControllerProvider.notifier).search(_input.text));
  }

  void _openDetail(RepositorySummary repository) {
    FocusScope.of(context).unfocus();
    // 詳細画面を開いたリポジトリを閲覧済みにする。
    ref.read(viewedRepositoryProvider.notifier).markViewed(repository.key);

    // キャッシュの有効期限を確認するため再評価。
    ref.invalidate(repositoryDetailProvider(repository.key));
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RepositoryDetailScreen(summary: repository),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final viewedKeys = ref.watch(viewedRepositoryProvider);
    final busy =
        state is SearchLoading ||
        (state is SearchResults && state.loadMore is LoadMoreLoading);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repository Search'),
        actions: [
          if (kDebugMode)
            IconButton(
              key: const Key('open-api-diagnostics'),
              tooltip: 'API通信インスペクター',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ApiDiagnosticsScreen(),
                  ),
                );
              },
            ),
        ],
      ),

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
                onPressed: busy ? null : _submit,
                child: const Text('検索'),
              ),
              if (state.query != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('送信済みの検索語：${state.query}'),
                ),
              Expanded(child: _content(state, viewedKeys)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(SearchState state, Set<RepositoryKey> viewedKeys) {
    return switch (state) {
      SearchIdle() => const Center(child: Text('キーワードを入力して検索してください。')),

      SearchLoading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('検索中…'),
            TextButton(
              onPressed: () =>
                  ref.read(searchControllerProvider.notifier).cancel(),
              child: const Text('キャンセル'),
            ),
          ],
        ),
      ),

      SearchFailure(:final query, :final problem) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_problemMessage(problem)),
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

      SearchEmpty(:final totalCount, :final incompleteResults) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (incompleteResults) const Text('検索結果が不完全な可能性があります。'),
          Text('表示中：0件（総件数：$totalCount件）'),
          Expanded(
            child: Center(
              child: Text(
                incompleteResults
                    ? '表示できる結果がありません。検索結果が不完全な可能性があります。'
                    : totalCount == 0
                    ? '一致するリポジトリは見つかりませんでした。'
                    : 'このページには表示できるリポジトリがありません。',
              ),
            ),
          ),
        ],
      ),

      SearchResults(
        :final items,
        :final totalCount,
        :final incompleteResults,
        :final loadMore,
      ) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (incompleteResults) const Text('検索結果が不完全な可能性があります。'),
            Text(
              '表示中：${items.length}件'
              '（初回検索時の総件数：$totalCount件）',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemCount: items.length + 1,
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return _loadMoreFooter(loadMore);
                  }

                  final repository = items[index];

                  return ListTile(
                    key: ValueKey(repository.key),
                    onTap: () => _openDetail(repository),
                    leading: SizedBox(
                      width: 68,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${index + 1}.',
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.folder_outlined),
                        ],
                      ),
                    ),
                    trailing: viewedKeys.contains(repository.key)
                        ? const Icon(
                            Icons.check_circle_outline,
                            semanticLabel: '閲覧済み',
                          )
                        : null,
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

  String _problemMessage(SearchProblem problem) {
    return switch (problem) {
      ApiSearchProblem(:final failure) => failure.safeMessage,
      UnexpectedSearchProblem() => '検索処理中に問題が発生しました。',
    };
  }

  Widget _loadMoreFooter(LoadMoreState loadMore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: switch (loadMore) {
        LoadMoreAvailable() => Center(
          child: OutlinedButton(
            onPressed: () => unawaited(
              ref.read(searchControllerProvider.notifier).loadMore(),
            ),
            child: const Text('もっと読み込む'),
          ),
        ),

        LoadMoreLoading() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const Text('追加読み込み中…'),
            TextButton(
              onPressed: () =>
                  ref.read(searchControllerProvider.notifier).cancel(),
              child: const Text('キャンセル'),
            ),
          ],
        ),

        LoadMoreFailure(:final problem) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_problemMessage(problem)),
            OutlinedButton(
              onPressed: () => unawaited(
                ref.read(searchControllerProvider.notifier).retryLoadMore(),
              ),
              child: const Text('追加読み込みを再試行'),
            ),
          ],
        ),
        LoadMoreEnd(:final reason) => Center(
          child: Text(switch (reason) {
            SearchEndReason.githubLimitReached =>
              'GitHub検索APIの取得上限（1,000件）に達しました。',
            SearchEndReason.exhausted => 'これ以上の結果はありません。',
          }),
        ),
      },
    );
  }
}
