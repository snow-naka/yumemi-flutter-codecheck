import 'github_rate_limit_headers.dart';

enum GitHubRateLimitKind { none, primary, secondary, unknown429 }

final class GitHubRateLimitDecision {
  const GitHubRateLimitDecision({required this.kind, required this.retryAt});

  final GitHubRateLimitKind kind;
  final DateTime? retryAt;

  bool get isRateLimited => kind != GitHubRateLimitKind.none;
}

final class GitHubRateLimitEvaluator {
  static GitHubRateLimitDecision evaluate({
    required int statusCode,
    required GitHubRateLimitHeaders headers,
    required DateTime now,
    bool secondaryLimitIndicated = false,
  }) {
    final current = now.toUtc();
    final limitedStatus = statusCode == 403 || statusCode == 429;

    if (!limitedStatus) {
      return const GitHubRateLimitDecision(
        kind: GitHubRateLimitKind.none,
        retryAt: null,
      );
    }

    final deadline = _deadline(headers, current);

    // レスポンス本文でSecondary制限と確認された場合。
    if (secondaryLimitIndicated) {
      return GitHubRateLimitDecision(
        kind: GitHubRateLimitKind.secondary,
        retryAt: deadline ?? current.add(const Duration(minutes: 1)),
      );
    }

    // Primary制限。resetが不明なら解除時刻も不明とする。
    if (headers.remaining == 0) {
      final reset = headers.resetAt?.toUtc();

      return GitHubRateLimitDecision(
        kind: GitHubRateLimitKind.primary,
        retryAt: reset != null && reset.isAfter(current) ? deadline : null,
      );
    }

    // 429だがPrimary/Secondaryの区別がつかない場合。
    // 安全側に倒して共通制限候補として扱う。
    if (statusCode == 429) {
      return GitHubRateLimitDecision(
        kind: GitHubRateLimitKind.unknown429,
        retryAt: deadline ?? current.add(const Duration(minutes: 1)),
      );
    }

    // 通常の403はレート制限と断定しない。
    return const GitHubRateLimitDecision(
      kind: GitHubRateLimitKind.none,
      retryAt: null,
    );
  }

  static DateTime? _deadline(GitHubRateLimitHeaders headers, DateTime now) {
    DateTime? latest;

    void consider(DateTime? value) {
      if (value == null || !value.isAfter(now)) return;

      if (latest == null || value.isAfter(latest!)) {
        latest = value;
      }
    }

    if (headers.remaining == 0) {
      consider(headers.resetAt?.toUtc());
    }

    final after = headers.retryAfter;
    if (after != null) {
      consider(now.add(after));
    }

    return latest;
  }
}
