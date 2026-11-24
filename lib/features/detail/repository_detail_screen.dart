import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/api_failure.dart';
import '../../models/repository_models.dart';
import 'repository_detail_provider.dart';
import '../../providers.dart';

class RepositoryDetailScreen extends ConsumerWidget {
  const RepositoryDetailScreen({super.key, required this.summary});

  final RepositorySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = repositoryDetailProvider(summary.key);
    final state = ref.watch(provider);
    final detail = state.isLoading ? null : state.asData?.value;
    final shownSummary = detail?.summary ?? summary;

    return Scaffold(
      appBar: AppBar(title: const Text('リポジトリ詳細')),
      body: _RepositoryDetailActions(
        key: ValueKey(summary.key),
        repositoryKey: summary.key,
        requestKey: detail?.summary.key,
        builder: (context, coreButton, issueControls) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ① 基本情報
                KeyedSubtree(
                  key: const ValueKey('detail-section-basic'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OwnerAvatar(url: shownSummary.avatarUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shownSummary.name,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(shownSummary.fullName, softWrap: true),
                            const SizedBox(height: 4),
                            Text('言語：${shownSummary.language ?? '未指定'}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ② 詳細情報 + Core API更新
                KeyedSubtree(
                  key: const ValueKey('detail-section-statistics'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ResponsiveDetailRow(
                        info: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (detail != null) ...[
                              Text('Star数：${detail.summary.starCount}'),
                              Text('Watcher数：${detail.watcherCount}'),
                              Text('Fork数：${detail.summary.forkCount}'),
                            ],
                            Text(
                              'Open Issue＋PR数：'
                              '${shownSummary.openIssueAndPullRequestCount}',
                            ),
                          ],
                        ),
                        action: coreButton,
                      ),
                      if (state.isLoading) ...[
                        const SizedBox(height: 8),
                        const Center(child: CircularProgressIndicator()),
                        const Text('詳細情報を取得中…'),
                      ] else if (state.hasError) ...[
                        const SizedBox(height: 8),
                        Text(
                          state.error is ApiFailure
                              ? (state.error! as ApiFailure).safeMessage
                              : '詳細情報の処理中に問題が発生しました。',
                        ),
                        OutlinedButton(
                          key: const Key('retry-repository-detail'),
                          onPressed: () => ref.invalidate(provider),
                          child: const _AccessibleActionLabel(
                            visibleLabel: '再試行',
                            semanticLabel: 'リポジトリ詳細情報の取得を再試行',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ③ Open Issue情報 + Search API取得
                KeyedSubtree(
                  key: const ValueKey('detail-section-issues'),
                  child: issueControls,
                ),

                const SizedBox(height: 12),

                // API利用の注意事項
                Text(
                  '※ Open Issue数の取得・再取得・再試行には、'
                  '操作ごとにGitHub Search APIを1回使用します。'
                  'APIのレート制限に影響します。',
                  key: const Key('open-issues-api-notice'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResponsiveDetailRow extends StatelessWidget {
  const _ResponsiveDetailRow({required this.info, required this.action});

  final Widget info;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

        final minHorizontalWidth = 340.0 * textScale;

        // 横幅が不足する場合は従来どおり縦並び。
        if (!constraints.hasBoundedWidth ||
            constraints.maxWidth < minHorizontalWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [info, const SizedBox(height: 8), action],
          );
        }

        // 横並びではボタンの幅を必要最小限にする。
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: info),

            const SizedBox(width: 12),

            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
              child: action,
            ),
          ],
        );
      },
    );
  }
}

class _OwnerAvatar extends StatelessWidget {
  const _OwnerAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);

    const fallback = CircleAvatar(radius: 32, child: Icon(Icons.person));

    // 不正なURLやHTTPS以外のURLでは画像を取得しない。
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return fallback;
    }

    return ClipOval(
      child: Image.network(
        url,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        semanticLabel: 'オーナーアイコン',
        loadingBuilder: (context, child, progress) {
          return progress == null ? child : fallback;
        },
        errorBuilder: (context, error, stackTrace) {
          return fallback;
        },
      ),
    );
  }
}

typedef _DetailActionsBuilder = Widget Function(
  BuildContext context,
  Widget coreButton,
  Widget issueControls,
);

class _AccessibleActionLabel extends StatelessWidget {
  const _AccessibleActionLabel({
    required this.visibleLabel,
    required this.semanticLabel,
  });

  final String visibleLabel;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Text(visibleLabel, textAlign: TextAlign.center),
    );
  }
}

class _RepositoryDetailActions extends ConsumerStatefulWidget {
  const _RepositoryDetailActions({
    super.key,
    required this.repositoryKey,
    required this.requestKey,
    required this.builder,
  });

  final RepositoryKey repositoryKey;
  final RepositoryKey? requestKey;
  final _DetailActionsBuilder builder;

  @override
  ConsumerState<_RepositoryDetailActions> createState() =>
      _RepositoryDetailActionsState();
}

class _RepositoryDetailActionsState
    extends ConsumerState<_RepositoryDetailActions> {
  bool _loading = false;
  bool _routePopped = false;
  int? _count;
  String? _error;
  DateTime? _fetchedAt;
  int _requestGeneration = 0;

  @override
  void didUpdateWidget(covariant _RepositoryDetailActions oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.requestKey != widget.requestKey) {
      ++_requestGeneration;
      _loading = false;
      _error = null;
    }
  }

  @override
  void initState() {
    super.initState();

    // 詳細画面を開き直したとき、以前取得したIssue数を復元。
    final cached = ref
        .read(openIssueCountCacheProvider)
        .get(widget.repositoryKey);

    _count = cached?.count;
    _fetchedAt = cached?.fetchedAt;
  }

  // 再描画前の連続タップでも、現在の詳細取得状態で排他を判定する。
  bool get _canStartRequest {
    if (!mounted || _routePopped || _loading || widget.requestKey == null) {
      return false;
    }
    final detail = ref.read(repositoryDetailProvider(widget.repositoryKey));
    return !detail.isLoading &&
        detail.asData?.value.summary.key == widget.requestKey;
  }

  void _refreshDetail() {
    if (!_canStartRequest) return;
    ref.invalidate(repositoryDetailProvider(widget.repositoryKey));
  }

  Future<void> _load() async {
    final target = widget.requestKey;

    if (target == null || !_canStartRequest) return;

    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final gateway = ref.read(githubRepositoryGatewayProvider);

    try {
      final count = await gateway.getOpenIssueCount(
        target,
        isCanceled: () =>
            !mounted ||
            _routePopped ||
            generation != _requestGeneration ||
            widget.requestKey != target,
      );

      // 画面を離れた場合はキャッシュも画面も更新しない。
      if (!mounted ||
          _routePopped ||
          generation != _requestGeneration ||
          widget.requestKey != target) {
        return;
      }

      // PR除外Issue数と取得日時をキャッシュへ保存。
      final cache = ref.read(openIssueCountCacheProvider);
      cache.put(widget.repositoryKey, count);

      final saved = cache.get(widget.repositoryKey)!;

      setState(() {
        _count = saved.count;
        _fetchedAt = saved.fetchedAt;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted ||
          _routePopped ||
          generation != _requestGeneration ||
          widget.requestKey != target) {
        return;
      }

      setState(() {
        // 前回取得済みのIssue数と取得日時は維持する。
        _error = failure.safeMessage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted ||
          _routePopped ||
          generation != _requestGeneration ||
          widget.requestKey != target) {
        return;
      }

      setState(() {
        _error = 'Issue数の取得中に問題が発生しました。';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String status;

    if (_loading) {
      status = 'Open Issue数（PR除外）：取得中…';
    } else if (_count != null) {
      status = 'Open Issue数（PR除外）：$_count';
    } else {
      status = 'Open Issue数（PR除外）：未取得';
    }

    final buttonLabel = _count != null
        ? '再取得'
        : _error != null
        ? '再試行'
        : '取得';

    final issueSemanticLabel = _count != null
        ? 'Open Issue数を再取得'
        : _error != null
        ? 'Open Issue数の取得を再試行'
        : 'Open Issue数を取得';

    // 統計情報セクションの右側
    final Widget coreButton = widget.requestKey != null
        ? SizedBox(
            child: OutlinedButton(
              key: const Key('refresh-repository-detail'),
              onPressed: _loading ? null : _refreshDetail,
              child: const _AccessibleActionLabel(
                visibleLabel: '更新',
                semanticLabel: 'リポジトリ詳細情報を更新',
              ),
            ),
          )
        : const SizedBox.shrink();

    // Issue情報セクションの右側

    final issueControls = _ResponsiveDetailRow(
      info: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          if (_fetchedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '取得日時：'
              '${_fetchedAt!.toLocal().toString().substring(0, 16)}'
              '（端末時刻）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
        ],
      ),
      action: SizedBox(
        child: OutlinedButton(
          key: const Key('load-open-issues'),
          onPressed: _loading || _routePopped || widget.requestKey == null
              ? null
              : _load,
          child: _AccessibleActionLabel(
            visibleLabel: buttonLabel,
            semanticLabel: issueSemanticLabel,
          ),
        ),
      ),
    );

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _routePopped = true;
        }
      },
      child: widget.builder(context, coreButton, issueControls),
    );
  }
}
