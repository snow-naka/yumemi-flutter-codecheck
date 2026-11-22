import 'github_rate_limit_evaluator.dart';
import 'github_rate_limit_policy.dart';
import 'github_rate_limit_headers.dart';

final class GitHubRateLimitCoordinator {
  GitHubRateLimitCoordinator(this.policy);

  final GitHubRateLimitPolicy policy;
  static const _unknownPrimaryCooldown = Duration(hours: 1);
  static const _expiredPrimaryResetCooldown = Duration(minutes: 1);
  int _secondaryFailureCount = 0;
  static const _maxSecondaryFailureCount = 7;
  static const _maxSecondaryBackoffSeconds = 3600;

  // 403/429の本文受信と制限判定が完了した後、
  // 1つのHTTP応答につき1回だけ呼び出す。
  void recordRateLimitOccurrence({
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
        final fallback = decision.primaryResetExpired
            ? _expiredPrimaryResetCooldown
            : _unknownPrimaryCooldown;

        final until = decision.retryAt ?? now.toUtc().add(fallback);

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

  // 正常応答について、従来どおりPrimary残数を観測する。
  void observeSuccessfulResponse({
    required int statusCode,
    required GitHubRateLimitHeaders headers,
    required GitHubApiResource requestedResource,
    required DateTime now,
  }) {
    if (statusCode < 200 || statusCode >= 300) {
      return;
    }

    observePrimaryExhaustion(
      headers: headers,
      requestedResource: requestedResource,
      now: now,
    );
  }

  // HTTPステータスとは独立して、Primary残数0を送信制御へ反映する。
  // 404・422など、要求自体が失敗した場合にも使用できる。
  void observePrimaryExhaustion({
    required GitHubRateLimitHeaders headers,
    required GitHubApiResource requestedResource,
    required DateTime now,
  }) {
    if (headers.remaining != 0) {
      return;
    }

    final current = now.toUtc();
    final resetAt = headers.resetAt?.toUtc();

    if (resetAt == null) {
      policy.blockResourceUntil(
        requestedResource,
        current.add(_unknownPrimaryCooldown),
      );
      return;
    }

    // 期限切れのResetでは新しい停止を登録しない。
    if (resetAt.isAfter(current)) {
      policy.blockResourceUntil(requestedResource, resetAt);
    }
  }

  void observeRetryAfter({
    required int statusCode,
    required GitHubRateLimitHeaders headers,
    required GitHubApiResource requestedResource,
    required DateTime now,
  }) {
    if (statusCode != 403 && statusCode != 429 && statusCode != 503) {
      return;
    }

    final delay = headers.retryAfter;

    if (delay == null || delay.inMicroseconds <= 0) {
      return;
    }

    final until = now.toUtc().add(delay);

    // 503はサーバー側の一時的な利用不能。
    // Secondary制限と判断せず、要求先のリソースだけ停止する。
    if (statusCode == 503) {
      policy.blockResourceUntil(requestedResource, until);
      return;
    }

    // 以下は既存の403・429の動作を維持する。
    if (headers.remaining == 0) {
      policy.blockResourceUntil(requestedResource, until);
    } else {
      policy.blockAllUntil(until);
    }
  }
}
