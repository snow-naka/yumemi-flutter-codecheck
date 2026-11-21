import 'github_rate_limit_evaluator.dart';
import 'github_rate_limit_policy.dart';
import 'github_rate_limit_headers.dart';

final class GitHubRateLimitCoordinator {
  GitHubRateLimitCoordinator(this.policy);

  final GitHubRateLimitPolicy policy;
  static const _unknownPrimaryCooldown = Duration(hours: 1);

  void apply({
    required GitHubRateLimitDecision decision,
    required GitHubApiResource requestedResource,
    required DateTime now,
  }) {
    switch (decision.kind) {
      case GitHubRateLimitKind.none:
        return;

      case GitHubRateLimitKind.primary:
        // Resetが不明なら60分間の暫定停止。
        // この日時はGitHubが通知したReset時刻ではない。
        final until =
            decision.retryAt ?? now.toUtc().add(_unknownPrimaryCooldown);

        policy.blockResourceUntil(requestedResource, until);
        return;

      case GitHubRateLimitKind.secondary:
      case GitHubRateLimitKind.unknown429:
        final until = decision.retryAt;

        if (until == null) {
          policy.blockAllWithoutDeadline();
        } else {
          policy.blockAllUntil(until);
        }
        return;
    }
  }

  // 正常応答の残数を見て、次回の要求を予防的に停止する。
  void observeSuccessfulResponse({
    required int statusCode,
    required GitHubRateLimitHeaders headers,
    required GitHubApiResource requestedResource,
    required DateTime now,
  }) {
    // エラー応答は既存のEvaluatorで処理する。
    if (statusCode < 200 || statusCode >= 300) {
      return;
    }

    // 残数が0と確認できた場合だけ制限を登録する。
    if (headers.remaining != 0) {
      return;
    }

    final resetAt = headers.resetAt;

    if (resetAt == null) {
      policy.blockResourceUntil(
        requestedResource,
        now.toUtc().add(_unknownPrimaryCooldown),
      );
      return;
    }

    // リセット時刻が既に過ぎていれば、新しい停止は登録しない。
    if (resetAt.isAfter(now.toUtc())) {
      policy.blockResourceUntil(requestedResource, resetAt);
    }
  }
}
