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
              const SizedBox(height: 16),
              _OpenIssueCountSection(repositoryKey: shownSummary.key),
            ],
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

class _OpenIssueCountSection extends ConsumerStatefulWidget {
  const _OpenIssueCountSection({required this.repositoryKey});

  final RepositoryKey repositoryKey;

  @override
  ConsumerState<_OpenIssueCountSection> createState() =>
      _OpenIssueCountSectionState();
}

class _OpenIssueCountSectionState
    extends ConsumerState<_OpenIssueCountSection> {
  bool _loading = false;
  bool _routePopped = false;
  int? _count;
  String? _error;
  Future<void> _load() async {
    // 二重タップや連続操作による重複要求を防ぐ。
    if (_loading || _routePopped) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final gateway = ref.read(githubRepositoryGatewayProvider);

    try {
      final count = await gateway.getOpenIssueCount(
        widget.repositoryKey,
        isCanceled: () => !mounted || _routePopped,
      );

      if (!mounted) return;

      setState(() {
        _count = count;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;

      setState(() {
        _error = failure.safeMessage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || _routePopped) return;

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
          Text(status),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loading ? null : _load,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
