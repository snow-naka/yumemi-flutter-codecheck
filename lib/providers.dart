import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'devtools/api_diagnostics.dart';
import 'data/github_rate_limit_policy.dart';
import 'data/github_repository_gateway.dart';
import 'data/http_github_repository_gateway.dart';
import 'features/detail/open_issue_count_cache.dart';

final apiDiagnosticsProvider = Provider<InMemoryApiDiagnostics>((ref) {
  final store = InMemoryApiDiagnostics(maxEntries: 20);

  ref.onDispose(store.dispose);

  return store;
});
// HTTPクライアントの生成と破棄を管理する。
final githubHttpClientProvider = Provider<http.Client>((ref) {
  final ioClient = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  final client = IOClient(ioClient);

  // 所有するProviderが破棄されたときに閉じる。
  ref.onDispose(client.close);

  return client;
});

// 検索と詳細取得で同一のGatewayを共有する。
final githubRepositoryGatewayProvider = Provider<GitHubRepositoryGateway>((
  ref,
) {
  final client = ref.watch(githubHttpClientProvider);

  return HttpGitHubRepositoryGateway(
    client: client,
    policy: GitHubRateLimitPolicy(),
    diagnostics: kDebugMode
        ? ref.watch(apiDiagnosticsProvider)
        : const NoopApiDiagnosticsSink(),
  );
});

final openIssueCountCacheProvider = Provider<OpenIssueCountCache>((ref) {
  final cache = OpenIssueCountCache();

  ref.onDispose(cache.clear);

  return cache;
});
