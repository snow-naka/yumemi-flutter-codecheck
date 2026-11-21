import '../models/api_failure.dart';
import 'github_rate_limit_policy.dart';

final class GitHubRateLimitGuard {
  const GitHubRateLimitGuard(this.policy);

  final GitHubRateLimitPolicy policy;

  // HTTP送信前に必ず呼び出す。
  // 制限中なら通信せず、ApiFailureを投げる。
  void check(GitHubApiResource resource, DateTime now) {
    if (policy.canRequest(resource, now)) {
      return;
    }

    final until = policy.retryAt(resource, now);

    throw ApiFailure(
      kind: ApiFailureKind.rateLimited,
      safeMessage: until == null
          ? 'GitHub APIの利用制限中です。再試行可能な時刻を確認できません。'
          : 'GitHub APIの利用制限中です。時間をおいて再試行してください。',
      retryAt: until,
    );
  }
}
