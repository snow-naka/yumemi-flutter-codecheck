import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/github_rate_limit_headers.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';

void main() {
  test('RH01: Primary制限のヘッダーを解析', () {
    final headers = GitHubRateLimitHeaders.parse({
      'X-RateLimit-Remaining': '0',
      'X-RateLimit-Reset': '1795262400',
      'X-RateLimit-Resource': 'search',
    });

    expect(headers.remaining, 0);
    expect(
      headers.resetAt,
      DateTime.fromMillisecondsSinceEpoch(1795262400 * 1000, isUtc: true),
    );
    expect(headers.resource, GitHubApiResource.search);
  });

  test('RH02: Retry-Afterを秒数として解析', () {
    final headers = GitHubRateLimitHeaders.parse({'Retry-After': '60'});

    expect(headers.retryAfter, const Duration(seconds: 60));
  });

  test('RH03: 未知・不正な値を安全に処理', () {
    final headers = GitHubRateLimitHeaders.parse({
      'x-ratelimit-remaining': '-1',
      'x-ratelimit-reset': 'invalid',
      'retry-after': '-5',
      'x-ratelimit-resource': 'unknown',
    });

    expect(headers.remaining, isNull);
    expect(headers.resetAt, isNull);
    expect(headers.retryAfter, isNull);
    expect(headers.resource, isNull);
  });

  test('RH04: ヘッダー欠落でも解析できる', () {
    final headers = GitHubRateLimitHeaders.parse({});

    expect(headers.remaining, isNull);
    expect(headers.resetAt, isNull);
    expect(headers.retryAfter, isNull);
    expect(headers.resource, isNull);
  });
}
