import 'github_rate_limit_evaluator.dart';
import 'github_rate_limit_policy.dart';
import 'github_rate_limit_headers.dart';

final class GitHubRateLimitCoordinator {
  GitHubRateLimitCoordinator(this.policy);

  final GitHubRateLimitPolicy policy;
  static const _unknownPrimaryCooldown = Duration(hours: 1);
  int _secondaryFailureCount = 0;
  static const _maxSecondaryFailureCount = 7;
  static const _maxSecondaryBackoffSeconds = 3600;

  // 403/429の本文受信と制限判定が完了した後、
  // 1つのHTTP応答につき1回だけ呼び出す。
  void recordCompletedRateLimit({
    required GitHubRateLimitDecision decision,
    required DateTime now,
  }) {
    if (decision.kind != GitHubRateLimitKind.secondary &&
        decision.kind != GitHubRateLimitKind.unknown429) {
      return;
    }

    if (_secondaryFailureCount < _maxSecondaryFailureCount) {
      _secondaryFailureCount++;
    }

    // 初回はapply()が登録したサーバー指定期限、
    // または既定の60秒をそのまま使用する。
    if (_secondaryFailureCount == 1) {
      return;
    }

    final calculatedSeconds = 60 * (1 << (_secondaryFailureCount - 1));

    final backoffSeconds = calculatedSeconds > _maxSecondaryBackoffSeconds
        ? _maxSecondaryBackoffSeconds
        : calculatedSeconds;

    policy.blockAllUntil(now.toUtc().add(Duration(seconds: backoffSeconds)));
  }

  // 完全に受信した正常HTTP応答で連続回数をリセット。
  void recordSuccessfulResponse() {
    _secondaryFailureCount = 0;
  }

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

  void observeRetryAfter({
    required int statusCode,
    required GitHubRateLimitHeaders headers,
    required GitHubApiResource requestedResource,
    required DateTime now,
  }) {
    if (statusCode != 403 && statusCode != 429) {
      return;
    }

    final delay = headers.retryAfter;

    if (delay == null || delay.inMicroseconds <= 0) {
      return;
    }

    final until = now.toUtc().add(delay);

    if (headers.remaining == 0) {
      // Primary制限の枠が枯渇している場合。
      policy.blockResourceUntil(requestedResource, until);
    } else {
      // Secondary制限の可能性もあるため共通停止。
      policy.blockAllUntil(until);
    }
  }
}
