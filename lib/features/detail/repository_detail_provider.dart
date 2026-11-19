import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/repository_models.dart';
import '../../providers.dart';

final repositoryDetailProvider = FutureProvider.autoDispose
    .family<RepositoryDetail, RepositoryKey>(
      (ref, key) =>
          ref.watch(githubRepositoryGatewayProvider).getRepository(key),
      // Issue #3の暫定方針。エラー種別ごとの再試行はPhase 2で設計する。
      retry: (retryCount, error) => null,
    );
