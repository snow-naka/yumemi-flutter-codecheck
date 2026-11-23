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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _OwnerAvatar(url: shownSummary.avatarUrl)),
            const SizedBox(height: 16),
            Text(
              shownSummary.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(shownSummary.fullName),
            Text('言語：${shownSummary.language ?? '未指定'}'),
            Text('Open Issue＋PR数：${shownSummary.openIssueAndPullRequestCount}'),
            const SizedBox(height: 16),
            if (state.isLoading) ...[
              const Center(child: CircularProgressIndicator()),
              const Text('詳細情報を取得中…'),
            ] else if (state.hasError) ...[
              Text(
                state.error is ApiFailure
                    ? (state.error! as ApiFailure).safeMessage
                    : '詳細情報の処理中に問題が発生しました。',
              ),
              OutlinedButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('再試行'),
              ),
            ] else if (detail != null) ...[
              Text('Star数：${detail.summary.starCount}'),
              Text('Watcher数：${detail.watcherCount}'),
              Text('Fork数：${detail.summary.forkCount}'),
            ],
            const SizedBox(height: 16),
            _RepositoryDetailActions(
              key: ValueKey(summary.key),
              repositoryKey: summary.key,
              requestKey: detail?.summary.key,
            ),
          ],
        ),
      ),
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

class _RepositoryDetailActions extends ConsumerStatefulWidget {
  const _RepositoryDetailActions({
    super.key,
    required this.repositoryKey,
    required this.requestKey,
  });

  final RepositoryKey repositoryKey;
  final RepositoryKey? requestKey;

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
        ? 'Issue数を再取得（検索APIを1回使用）'
        : _error != null
        ? 'Issue数を再試行（検索APIを1回使用）'
        : 'Issue数を取得（検索APIを1回使用）';

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _routePopped = true;
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.requestKey != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loading ? null : _refreshDetail,
                child: const Text('詳細情報を更新（Core APIを使用）'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(status),
          if (_fetchedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '取得日時：${_fetchedAt!.toLocal().toString().substring(0, 16)}（端末時刻）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loading || _routePopped || widget.requestKey == null
                ? null
                : _load,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
