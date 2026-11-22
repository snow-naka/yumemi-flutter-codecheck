import 'github_rate_limit_policy.dart';

final class GitHubRateLimitHeaders {
  const GitHubRateLimitHeaders({
    required this.remaining,
    required this.resetAt,
    required this.retryAfter,
    required this.resource,
    this.limit,
  });

  final int? remaining;
  final DateTime? resetAt;
  final Duration? retryAfter;
  final GitHubApiResource? resource;
  final int? limit;

  static GitHubRateLimitHeaders parse(Map<String, String> headers) {
    // HTTPヘッダー名は大文字・小文字を区別しない。
    final values = {
      for (final entry in headers.entries)
        entry.key.toLowerCase(): entry.value.trim(),
    };

    final rawRemaining = int.tryParse(values['x-ratelimit-remaining'] ?? '');

    final remaining = rawRemaining != null && rawRemaining >= 0
        ? rawRemaining
        : null;

    // Unix秒をUTCのDateTimeに変換する。
    final resetSeconds = int.tryParse(values['x-ratelimit-reset'] ?? '');

    DateTime? resetAt;
    if (resetSeconds != null &&
        resetSeconds >= 0 &&
        resetSeconds <= 253402300799) {
      resetAt = DateTime.fromMillisecondsSinceEpoch(
        resetSeconds * 1000,
        isUtc: true,
      );
    }

    // GitHubが案内する秒数形式を扱う。
    final retrySeconds = int.tryParse(values['retry-after'] ?? '');
    final rawLimit = int.tryParse(values['x-ratelimit-limit'] ?? '');
    final limit = rawLimit != null && rawLimit >= 0 ? rawLimit : null;

    final retryAfter = retrySeconds != null && retrySeconds >= 0
        ? Duration(seconds: retrySeconds)
        : null;

    final resource = switch (values['x-ratelimit-resource']?.toLowerCase()) {
      'search' => GitHubApiResource.search,
      'core' => GitHubApiResource.core,
      _ => null,
    };

    return GitHubRateLimitHeaders(
      remaining: remaining,
      resetAt: resetAt,
      retryAfter: retryAfter,
      resource: resource,
      limit: limit,
    );
  }
}
