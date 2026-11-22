import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/github_rate_limit_coordinator.dart';
import 'package:yumemi_app/data/github_rate_limit_evaluator.dart';
import 'package:yumemi_app/data/github_rate_limit_headers.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 12);

  GitHubRateLimitDecision decide(
    int statusCode, {
    Map<String, String> headers = const {},
    bool secondary = false,
  }) {
    return GitHubRateLimitEvaluator.evaluate(
      statusCode: statusCode,
      headers: GitHubRateLimitHeaders.parse(headers),
      now: now,
      secondaryLimitIndicated: secondary,
    );
  }

  test('RC01: Primary制限を検索APIだけに反映', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);
    final reset = now.add(const Duration(minutes: 2));

    coordinator.apply(
      requestedResource: GitHubApiResource.search,
      decision: decide(
        403,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
        },
      ),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);
    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);
    expect(policy.retryAt(GitHubApiResource.search, now), reset);
    expect(policy.canRequest(GitHubApiResource.search, reset), isTrue);
  });

  test('RC02: Secondary制限では両方停止', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    coordinator.apply(
      requestedResource: GitHubApiResource.search,
      decision: decide(403, headers: {'retry-after': '45'}, secondary: true),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);
    expect(policy.canRequest(GitHubApiResource.core, now), isFalse);

    final retryAt = now.add(const Duration(seconds: 45));
    expect(policy.canRequest(GitHubApiResource.core, retryAt), isTrue);
  });

  test('RC03: 不明な429は共通停止', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    coordinator.apply(
      requestedResource: GitHubApiResource.core,
      decision: decide(429),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);
    expect(policy.canRequest(GitHubApiResource.core, now), isFalse);
    expect(
      policy.retryAt(GitHubApiResource.search, now),
      now.add(const Duration(minutes: 1)),
    );
  });

  test('RC04: Reset不明のPrimary制限は60分後に再要求可能', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    coordinator.apply(
      requestedResource: GitHubApiResource.search,
      decision: decide(403, headers: {'x-ratelimit-remaining': '0'}),
      now: now,
    );

    final fallback = now.add(const Duration(hours: 1));

    expect(policy.retryAt(GitHubApiResource.search, now), fallback);
    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);
    expect(
      policy.canRequest(
        GitHubApiResource.search,
        fallback.subtract(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
    expect(policy.canRequest(GitHubApiResource.search, fallback), isTrue);
    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);
  });

  test('RC05: 通常の403では停止しない', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    coordinator.apply(
      requestedResource: GitHubApiResource.search,
      decision: decide(403),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isTrue);
    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);
  });

  test('RC06: 後から短い制限が届いても短縮しない', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    for (final minutes in [3, 1]) {
      final reset = now.add(Duration(minutes: minutes));

      coordinator.apply(
        requestedResource: GitHubApiResource.search,
        decision: decide(
          403,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          },
        ),
        now: now,
      );
    }

    expect(
      policy.retryAt(GitHubApiResource.search, now),
      now.add(const Duration(minutes: 3)),
    );
  });

  test('RC07: 正常応答でも残数0なら検索を停止', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);
    final reset = now.add(const Duration(minutes: 2));

    coordinator.observeSuccessfulResponse(
      statusCode: 200,
      requestedResource: GitHubApiResource.search,
      headers: GitHubRateLimitHeaders.parse({
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
      }),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);
    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);
    expect(policy.canRequest(GitHubApiResource.search, reset), isTrue);
  });

  test('RC08: 正常応答で残数があれば停止しない', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    coordinator.observeSuccessfulResponse(
      statusCode: 200,
      requestedResource: GitHubApiResource.search,
      headers: GitHubRateLimitHeaders.parse({'x-ratelimit-remaining': '5'}),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isTrue);
  });

  test('RC09: 正常応答のReset不明でも60分間停止', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    coordinator.observeSuccessfulResponse(
      statusCode: 200,
      requestedResource: GitHubApiResource.search,
      headers: GitHubRateLimitHeaders.parse({'x-ratelimit-remaining': '0'}),
      now: now,
    );

    final fallback = now.add(const Duration(hours: 1));

    expect(policy.retryAt(GitHubApiResource.search, now), fallback);
    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);
    expect(policy.canRequest(GitHubApiResource.search, fallback), isTrue);
    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);
  });
  test('RC10: エラー応答は正常応答用の処理では登録しない', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    coordinator.observeSuccessfulResponse(
      statusCode: 403,
      requestedResource: GitHubApiResource.search,
      headers: GitHubRateLimitHeaders.parse({'x-ratelimit-remaining': '0'}),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isTrue);
  });

  test('RC11: 過去のReset時刻では新しい停止を登録しない', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);
    final past = now.subtract(const Duration(minutes: 1));

    coordinator.observeSuccessfulResponse(
      statusCode: 200,
      requestedResource: GitHubApiResource.search,
      headers: GitHubRateLimitHeaders.parse({
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '${past.millisecondsSinceEpoch ~/ 1000}',
      }),
      now: now,
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isTrue);
  });

  test('RC12: 過去のResetを持つPrimaryエラーは60秒停止', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    final past = now.subtract(const Duration(minutes: 1));

    coordinator.apply(
      requestedResource: GitHubApiResource.search,
      decision: decide(
        403,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${past.millisecondsSinceEpoch ~/ 1000}',
        },
      ),
      now: now,
    );

    expect(
      policy.retryAt(GitHubApiResource.search, now),
      now.add(const Duration(minutes: 1)),
    );
  });

  test('RC13: 暫定停止で既存の長い制限を短縮しない', () {
    final policy = GitHubRateLimitPolicy();
    final coordinator = GitHubRateLimitCoordinator(policy);

    final existing = now.add(const Duration(hours: 2));

    policy.blockResourceUntil(GitHubApiResource.search, existing);

    coordinator.observeSuccessfulResponse(
      statusCode: 200,
      requestedResource: GitHubApiResource.search,
      headers: GitHubRateLimitHeaders.parse({'x-ratelimit-remaining': '0'}),
      now: now,
    );

    expect(policy.retryAt(GitHubApiResource.search, now), existing);
  });
}
