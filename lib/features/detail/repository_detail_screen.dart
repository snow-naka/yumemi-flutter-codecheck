import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/api_failure_localizer.dart';
import '../../l10n/app_localizations.dart';
import '../../models/api_failure.dart';
import '../../models/repository_models.dart';
import 'repository_detail_provider.dart';
import '../../providers.dart';
import '../../l10n/localized_date_time.dart';
import 'issue_count_fetch_mode_provider.dart';

import 'dart:async';

class RepositoryDetailScreen extends ConsumerWidget {
  const RepositoryDetailScreen({super.key, required this.summary});

  final RepositorySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = repositoryDetailProvider(summary.key);
    final state = ref.watch(provider);
    final fetchMode = ref.watch(issueCountFetchModeProvider);
    final detail = state.isLoading ? null : state.asData?.value;
    final shownSummary = detail?.summary ?? summary;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.detailTitle)),
      body: _RepositoryDetailActions(
        key: ValueKey(summary.key),
        repositoryKey: summary.key,
        requestKey: detail?.summary.key,
        fetchMode: fetchMode,
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
                            Text(
                              l10n.repositoryLanguage(
                                shownSummary.language ??
                                    l10n.languageUnspecified,
                              ),
                            ),
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
                              Text(l10n.starCount(detail.summary.starCount)),
                              Text(l10n.watcherCount(detail.watcherCount)),
                              Text(l10n.forkCount(detail.summary.forkCount)),
                            ],
                            Text(
                              l10n.openIssueAndPullRequestCount(
                                shownSummary.openIssueAndPullRequestCount,
                              ),
                            ),
                          ],
                        ),
                        action: coreButton,
                      ),
                      if (state.isLoading) ...[
                        const SizedBox(height: 8),
                        const Center(child: CircularProgressIndicator()),
                        Text(l10n.detailLoading),
                      ] else if (state.hasError) ...[
                        const SizedBox(height: 8),
                        Text(
                          state.error is ApiFailure
                              ? localizeApiFailure(
                                  l10n,
                                  state.error! as ApiFailure,
                                )
                              : l10n.unexpectedDetailError,
                        ),
                        OutlinedButton(
                          key: const Key('retry-repository-detail'),
                          onPressed: () => ref.invalidate(provider),
                          child: _AccessibleActionLabel(
                            visibleLabel: l10n.retry,
                            semanticLabel: l10n.retryDetailSemantics,
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
                  l10n.openIssuesApiNotice,
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
        semanticLabel: AppLocalizations.of(context).ownerAvatar,
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

sealed class _IssueLoadProblem {
  const _IssueLoadProblem();
}

final class _IssueApiProblem extends _IssueLoadProblem {
  const _IssueApiProblem(this.failure);

  final ApiFailure failure;
}

final class _UnexpectedIssueProblem extends _IssueLoadProblem {
  const _UnexpectedIssueProblem();
}

class _RepositoryDetailActions extends ConsumerStatefulWidget {
  const _RepositoryDetailActions({
    super.key,
    required this.repositoryKey,
    required this.requestKey,
    required this.fetchMode,
    required this.builder,
  });

  final RepositoryKey repositoryKey;
  final RepositoryKey? requestKey;
  final AsyncValue<IssueCountFetchModeState> fetchMode;
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
  _IssueLoadProblem? _error;
  DateTime? _fetchedAt;
  int _requestGeneration = 0;
  bool _automaticFetchPending = true;
  bool _automaticFetchScheduled = false;
  @override
  void didUpdateWidget(covariant _RepositoryDetailActions oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.requestKey != widget.requestKey) {
      ++_requestGeneration;
      _loading = false;
      _error = null;
    }

    _scheduleAutomaticFetch();
  }

  void _scheduleAutomaticFetch() {
    if (!mounted ||
        _routePopped ||
        !_automaticFetchPending ||
        _automaticFetchScheduled ||
        widget.requestKey == null) {
      return;
    }

    final mode = widget.fetchMode;

    // 設定の読み込み・保存が完了するまで判定を保留する。
    if (mode.isLoading || mode.asData?.value.isSaving == true) {
      return;
    }

    _automaticFetchScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _automaticFetchScheduled = false;

      if (!mounted || _routePopped || !_automaticFetchPending) {
        return;
      }

      // 予約時点ではなく、実行直前の詳細取得状態を確認する。
      if (!_canStartRequest) return;

      // 予約後に設定が変更されている可能性があるため再確認する。
      final latest = ref.read(issueCountFetchModeProvider);
      final current = latest.asData?.value;

      if (latest.isLoading || current?.isSaving == true) {
        return;
      }

      // この詳細表示に対する自動取得の判定は一度だけ行う。
      _automaticFetchPending = false;

      // 手動取得・読み込み失敗時は自動通信しない。
      if (current?.allowsAutomaticFetch != true) {
        return;
      }

      // 取得済みのIssue数があればキャッシュを利用する。
      if (_count != null) return;

      unawaited(_load());
    });
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

    _scheduleAutomaticFetch();
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

    // 手動取得が先に開始された場合も、
    // 後から自動取得を重複実行しない。
    _automaticFetchPending = false;

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
        _error = _IssueApiProblem(failure);
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
        _error = const _UnexpectedIssueProblem();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String status;

    if (_loading) {
      status = l10n.openIssuesLoading;
    } else if (_count != null) {
      status = l10n.openIssueCount(_count!);
    } else {
      status = l10n.openIssuesNotFetched;
    }

    final errorMessage = switch (_error) {
      _IssueApiProblem(:final failure) => localizeApiFailure(l10n, failure),
      _UnexpectedIssueProblem() => l10n.unexpectedIssueError,
      null => null,
    };

    final buttonLabel = _count != null
        ? l10n.fetchAgain
        : _error != null
        ? l10n.retry
        : l10n.fetch;

    final issueSemanticLabel = _count != null
        ? l10n.refetchOpenIssuesSemantics
        : _error != null
        ? l10n.retryOpenIssuesSemantics
        : l10n.fetchOpenIssuesSemantics;

    // 統計情報セクションの右側
    final Widget coreButton = widget.requestKey != null
        ? SizedBox(
            child: OutlinedButton(
              key: const Key('refresh-repository-detail'),
              onPressed: _loading ? null : _refreshDetail,
              child: _AccessibleActionLabel(
                visibleLabel: l10n.refresh,
                semanticLabel: l10n.refreshDetailSemantics,
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
              l10n.issueFetchedAt(
                formatDeviceDateTime(_fetchedAt!, localeName: l10n.localeName),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(errorMessage),
          ],
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
