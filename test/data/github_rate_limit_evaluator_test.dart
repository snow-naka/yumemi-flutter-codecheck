import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/github_rate_limit_evaluator.dart';
import 'package:yumemi_app/data/github_rate_limit_headers.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 12);

  test('RE01: Primary制限を判定', () {
    final reset = now.add(const Duration(minutes: 2));

    final decision = GitHubRateLimitEvaluator.evaluate(
      statusCode: 403,
      headers: GitHubRateLimitHeaders.parse({
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
      }),
      now: now,
    );

    expect(decision.kind, GitHubRateLimitKind.primary);
    expect(decision.retryAt, reset);
  });

  test('RE02: 通常の403をレート制限と誤判定しない', () {
    final decision = GitHubRateLimitEvaluator.evaluate(
      statusCode: 403,
      headers: GitHubRateLimitHeaders.parse({}),
      now: now,
    );

    expect(decision.isRateLimited, isFalse);
    expect(decision.retryAt, isNull);
  });

  test('RE03: Secondary制限はRetry-Afterを利用', () {
    final decision = GitHubRateLimitEvaluator.evaluate(
      statusCode: 403,
      headers: GitHubRateLimitHeaders.parse({'retry-after': '45'}),
      now: now,
      secondaryLimitIndicated: true,
    );

    expect(decision.kind, GitHubRateLimitKind.secondary);
    expect(decision.retryAt, now.add(const Duration(seconds: 45)));
  });

  test('RE04: Secondary制限で待機情報がなければ60秒', () {
    final decision = GitHubRateLimitEvaluator.evaluate(
      statusCode: 403,
      headers: GitHubRateLimitHeaders.parse({}),
      now: now,
      secondaryLimitIndicated: true,
    );

    expect(decision.kind, GitHubRateLimitKind.secondary);
    expect(decision.retryAt, now.add(const Duration(minutes: 1)));
  });

  test('RE05: 詳細不明の429は安全側に停止', () {
    final decision = GitHubRateLimitEvaluator.evaluate(
      statusCode: 429,
      headers: GitHubRateLimitHeaders.parse({}),
      now: now,
    );

    expect(decision.kind, GitHubRateLimitKind.unknown429);
    expect(decision.retryAt, now.add(const Duration(minutes: 1)));
  });

  test('RE06: Primary制限でResetが不明なら解除時刻は不明', () {
    final decision = GitHubRateLimitEvaluator.evaluate(
      statusCode: 403,
      headers: GitHubRateLimitHeaders.parse({'x-ratelimit-remaining': '0'}),
      now: now,
    );

    expect(decision.kind, GitHubRateLimitKind.primary);
    expect(decision.retryAt, isNull);
  });
}
