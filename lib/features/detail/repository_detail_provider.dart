import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/repository_models.dart';
import '../../providers.dart';

final repositoryDetailProvider = FutureProvider.autoDispose
    .family<RepositoryDetail, RepositoryKey>((ref, key) async {
      final cache = ref.read(repositoryDetailCacheProvider);

      // 15分以内の取得済み情報があれば通信しない。
      final cached = cache.getFresh(key);
      if (cached != null) {
        return cached;
      }

      final gateway = ref.watch(githubRepositoryGatewayProvider);

      final detail = await gateway.getRepository(key);

      // 古い要求の完了によってキャッシュを上書きしない。
      if (ref.mounted) {
        cache.put(key, detail);
      }

      return detail;
    }, retry: (retryCount, error) => null);
