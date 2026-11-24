import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/api_failure.dart';
import '../../models/repository_models.dart';
import '../../providers.dart';

final repositoryDetailProvider = FutureProvider.autoDispose
    .family<RepositoryDetail, RepositoryKey>((ref, key) async {
      final gateway = ref.watch(githubRepositoryGatewayProvider);
      final detail = await gateway.getRepository(key);
      if (detail.summary.key.id != key.id) {
        throw const ApiFailure(
          kind: ApiFailureKind.invalidResponse,
          reason: ApiFailureReason.repositoryMismatch,
        );
      }
      return detail;
    }, retry: (retryCount, error) => null);
