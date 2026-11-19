import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/fake_github_repository_gateway.dart';
import 'data/github_repository_gateway.dart';

final githubRepositoryGatewayProvider = Provider<GitHubRepositoryGateway>(
  (ref) => FakeGitHubRepositoryGateway(),
);
