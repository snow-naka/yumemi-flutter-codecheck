import '../models/repository_models.dart';

abstract interface class GitHubRepositoryGateway {
  Future<SearchPage> searchRepositories(
    String query, {
    int page = 1,
    int perPage = 30,
  });

  Future<RepositoryDetail> getRepository(RepositoryKey key);
}
