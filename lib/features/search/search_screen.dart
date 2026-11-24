import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../devtools/api_diagnostics_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../models/repository_models.dart';
import '../detail/repository_detail_provider.dart';
import '../detail/repository_detail_screen.dart';
import 'search_controller.dart';
import 'search_state.dart';
import 'viewed_repository_provider.dart';
import 'search_layout_preferences.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _input = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);
  SearchPanelPosition _panelPosition = SearchPanelPosition.top;
  bool _positionChangedByUser = false;
  bool _savingPosition = false;
  Size? _lastResultViewportSize;
  @override
  void initState() {
    super.initState();
    unawaited(_restorePosition());
  }

  Widget _submittedQueryPreview(String query) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: l10n.showFullSearchQuery,
        child: InkWell(
          key: const Key('submitted-query-open'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => _showSubmittedQuery(query),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l10n.submittedQueryLabel(query),
              key: const Key('submitted-query-label'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }

  void _showSubmittedQuery(String query) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocalizations.of(dialogContext).submittedQueryTitle),
          scrollable: true,
          content: SelectableText(
            query,
            key: const Key('submitted-query-full'),
          ),
          actions: [
            TextButton(
              key: const Key('submitted-query-close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(dialogContext).close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restorePosition() async {
    try {
      final position = await ref.read(searchPanelPositionStoreProvider).read();

      // 読み込み中に利用者が設定を変更した場合は上書きしない。
      if (!mounted || _positionChangedByUser) return;

      setState(() {
        _panelPosition = position;
      });
    } catch (_) {
      // 設定を読み込めなければ標準の上配置を維持する。
    }
  }

  Future<void> _changePosition(SearchPanelPosition position) async {
    if (_savingPosition) return;

    final previous = _panelPosition;
    _positionChangedByUser = true;

    setState(() {
      _panelPosition = position;
      _savingPosition = true;
    });

    try {
      await ref.read(searchPanelPositionStoreProvider).write(position);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _panelPosition = previous;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).searchPanelSaveFailed),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingPosition = false;
        });
      }
    }
  }

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

    FocusScope.of(context).unfocus(); // 追加

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

    // 前の画面のautoDisposeが完了する前に開き直しても、詳細を新しく取得する。
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
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider);
    final viewedKeys = ref.watch(viewedRepositoryProvider);
    final busy =
        state is SearchLoading ||
        (state is SearchResults && state.loadMore is LoadMoreLoading);
    final windowSize = MediaQuery.sizeOf(context);

    // 横幅が十分あり、横長の場合は左右に分割する。
    final sideBySide =
        windowSize.width >= 600 && windowSize.width >= windowSize.height * 1.5;

    final trailing = _panelPosition == SearchPanelPosition.bottom;

    final media = MediaQuery.of(context);

    final keyboardVisible = media.viewInsets.bottom > 0;

    final availableHeight =
        media.size.height - media.viewInsets.vertical - media.padding.vertical;

    final textScale = media.textScaler.scale(14) / 14;

    // 通常レイアウトに必要な高さの目安。
    final minNormalHeight = 260.0 + 80.0 * textScale;

    // 横画面でキーボードが表示され、高さが不足した場合。
    final compactInput =
        windowSize.width > windowSize.height &&
        keyboardVisible &&
        availableHeight < minNormalHeight;
    return Scaffold(
      appBar: compactInput
          ? null
          : AppBar(
              title: Text(l10n.appTitle),
              actions: [
                PopupMenuButton<SearchPanelPosition>(
                  key: const Key('search-layout-menu'),
                  tooltip: l10n.searchPanelPosition,
                  enabled: !_savingPosition,
                  icon: const Icon(Icons.tune),
                  onSelected: (position) {
                    unawaited(_changePosition(position));
                  },
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem<SearchPanelPosition>(
                      value: SearchPanelPosition.top,
                      checked: _panelPosition == SearchPanelPosition.top,
                      child: Text(
                        sideBySide
                            ? l10n.searchPanelLeftDefault
                            : l10n.searchPanelTopDefault,
                      ),
                    ),
                    CheckedPopupMenuItem<SearchPanelPosition>(
                      value: SearchPanelPosition.bottom,
                      checked: _panelPosition == SearchPanelPosition.bottom,
                      child: Text(
                        sideBySide
                            ? l10n.searchPanelRight
                            : l10n.searchPanelBottom,
                      ),
                    ),
                  ],
                ),
                if (kDebugMode)
                  IconButton(
                    key: const Key('open-api-diagnostics'),
                    tooltip: l10n.apiDiagnosticsTitle,
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
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: compactInput ? 4 : 16,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 非表示中も、直前の検索結果領域のサイズを維持する。
              final keptResultSize =
                  _lastResultViewportSize ?? const Size(480, 600);

              return Flex(
                key: const Key('search-main-layout'),

                direction: sideBySide ? Axis.horizontal : Axis.vertical,

                crossAxisAlignment: CrossAxisAlignment.stretch,

                verticalDirection: trailing
                    ? VerticalDirection.up
                    : VerticalDirection.down,

                textDirection: trailing ? TextDirection.rtl : TextDirection.ltr,

                spacing: sideBySide && !compactInput ? 12 : 0,

                children: [
                  // 検索操作エリア
                  Flexible(
                    flex: compactInput
                        ? 1
                        : sideBySide
                        ? 2
                        : 0,
                    fit: FlexFit.tight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: compactInput || sideBySide
                            ? constraints.maxHeight
                            : constraints.maxHeight * 0.55,
                      ),
                      child: SingleChildScrollView(
                        key: const Key('search-controls-panel'),
                        primary: false,
                        reverse: !compactInput && !sideBySide && trailing,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          verticalDirection: trailing
                              ? VerticalDirection.up
                              : VerticalDirection.down,
                          children: [
                            _searchControls(state, busy),

                            if (!compactInput && state.query != null)
                              _submittedQueryPreview(state.query!),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 検索結果エリア
                  Flexible(
                    flex: compactInput
                        ? 0
                        : sideBySide
                        ? 3
                        : 1,
                    fit: FlexFit.tight,
                    child: ExcludeFocus(
                      excluding: compactInput,
                      child: TickerMode(
                        enabled: !compactInput,
                        child: Offstage(
                          offstage: compactInput,
                          child: SizedBox(
                            width: compactInput ? 0 : null,
                            height: compactInput ? 0 : null,
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: compactInput
                                  ? keptResultSize.width
                                  : null,
                              maxWidth: compactInput
                                  ? keptResultSize.width
                                  : null,
                              minHeight: compactInput
                                  ? keptResultSize.height
                                  : null,
                              maxHeight: compactInput
                                  ? keptResultSize.height
                                  : null,
                              child: LayoutBuilder(
                                builder: (context, resultConstraints) {
                                  if (!compactInput &&
                                      resultConstraints.hasBoundedWidth &&
                                      resultConstraints.hasBoundedHeight) {
                                    _lastResultViewportSize =
                                        resultConstraints.biggest;
                                  }

                                  return _content(state, viewedKeys);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _resultCountLabel(
    BuildContext context,
    int displayedCount,
    int initialTotalCount,
  ) {
    return Text(
      AppLocalizations.of(context)
          .searchResultCount(displayedCount, initialTotalCount),
      key: const Key('search-result-count'),
    );
  }

  Widget _searchControls(SearchState state, bool busy) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _input,
            decoration: InputDecoration(
              labelText: l10n.keyword,
              suffixIcon: IconButton(
                key: const Key('search-submit-button'),
                tooltip: l10n.search,
                onPressed: busy ? null : _submit,
                icon: const Icon(Icons.search),
              ),
            ),
            textInputAction: TextInputAction.search,
            onFieldSubmitted: (_) => _submit(),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'keywordRequired'
                : null,
            errorBuilder: (context, _) {
              final theme = Theme.of(context);

              return Text(
                AppLocalizations.of(context).keywordRequired,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _content(SearchState state, Set<int> viewedKeys) {
    final l10n = AppLocalizations.of(context);
    return switch (state) {
      SearchIdle() => Center(child: Text(l10n.searchPrompt)),

      SearchLoading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(l10n.searching),
            TextButton(
              onPressed: () =>
                  ref.read(searchControllerProvider.notifier).cancel(),
              child: Text(l10n.cancel),
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
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),

      SearchEmpty(:final totalCount, :final incompleteResults) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (incompleteResults) Text(l10n.incompleteResultsWarning),
          Text(l10n.searchEmptyCount(totalCount)),
          Expanded(
            child: Center(
              child: Text(
                incompleteResults
                    ? l10n.searchEmptyIncomplete
                    : totalCount == 0
                    ? l10n.searchNoMatches
                    : l10n.searchEmptyPage,
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
            if (incompleteResults) Text(l10n.incompleteResultsWarning),
            _resultCountLabel(context, items.length, totalCount),
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
                  final theme = Theme.of(context);

                  return ListTile(
                    key: ValueKey(repository.key),
                    onTap: () => _openDetail(repository),

                    title: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 番号は必要な幅だけ使用する。
                        Text(
                          '${index + 1}.',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          softWrap: false,
                        ),
                        const SizedBox(width: 8),

                        // リポジトリ情報は残りの横幅を使用する。
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(repository.name),
                              Text(
                                '${repository.fullName} / '
                                '${repository.language ?? l10n.languageUnspecified}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // 閲覧済みの表示は維持する。
                    trailing: viewedKeys.contains(repository.key.id)
                        ? Icon(
                            Icons.check_circle_outline,
                            semanticLabel: l10n.viewed,
                          )
                        : null,
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
      UnexpectedSearchProblem() => AppLocalizations.of(
        context,
      ).unexpectedSearchError,
    };
  }

  Widget _loadMoreFooter(LoadMoreState loadMore) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: switch (loadMore) {
        LoadMoreAvailable() => Center(
          child: OutlinedButton(
            onPressed: () => unawaited(
              ref.read(searchControllerProvider.notifier).loadMore(),
            ),
            child: Text(l10n.loadMore),
          ),
        ),

        LoadMoreLoading() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            Text(l10n.loadingMore),
            TextButton(
              onPressed: () =>
                  ref.read(searchControllerProvider.notifier).cancel(),
              child: Text(l10n.cancel),
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
              child: Text(l10n.retryLoadMore),
            ),
          ],
        ),
        LoadMoreEnd(:final reason) => Center(
          child: Text(switch (reason) {
            SearchEndReason.githubLimitReached => l10n.githubSearchLimitReached,
            SearchEndReason.exhausted => l10n.noMoreResults,
          }),
        ),
      },
    );
  }
}
