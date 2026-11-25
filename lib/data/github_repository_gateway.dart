import '../models/repository_models.dart';

// HTTP送信前にキャンセルされた要求を表す。
// 利用者向けのAPIエラーとは区別する。
final class QueuedRequestCanceled implements Exception {
  const QueuedRequestCanceled();
}

abstract interface class GitHubRepositoryGateway {
  Future<SearchPage> searchRepositories(
    String query, {
    int page = 1,
    int perPage = 30,
    bool Function()? isCanceled,
  });

  Future<RepositoryDetail> getRepository(RepositoryKey key);
  // PRを除いたOpen Issue数を取得する。自動取得・手動取得で共用する。
  Future<int> getOpenIssueCount(
    RepositoryKey key, {
    bool Function()? isCanceled,
  });
}
