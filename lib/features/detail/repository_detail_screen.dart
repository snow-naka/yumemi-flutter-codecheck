import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/api_failure.dart';
import '../../models/repository_models.dart';
import 'repository_detail_provider.dart';

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
            const Center(child: CircleAvatar(child: Icon(Icons.person))),
            const SizedBox(height: 16),
            Text(
              shownSummary.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(shownSummary.fullName),
            Text('言語：${shownSummary.language ?? '未指定'}'),
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
              Text(
                'Open Issue＋PR数：${detail.summary.openIssueAndPullRequestCount}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
