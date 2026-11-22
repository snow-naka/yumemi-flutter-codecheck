import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/github_rate_limit_guard.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';
import 'package:yumemi_app/models/api_failure.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 12);

  test('RG01: 制限がなければ送信可能', () {
    final policy = GitHubRateLimitPolicy();
    final guard = GitHubRateLimitGuard(policy);

    expect(() => guard.check(GitHubApiResource.search, now), returnsNormally);

    expect(() => guard.check(GitHubApiResource.core, now), returnsNormally);
  });

  test('RG02: 解除時刻付き制限はApiFailureで拒否', () {
    final policy = GitHubRateLimitPolicy();
    final guard = GitHubRateLimitGuard(policy);

    final until = now.add(const Duration(minutes: 2));

    policy.blockResourceUntil(GitHubApiResource.search, until);

    expect(
      () => guard.check(GitHubApiResource.search, now),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.rateLimited)
            .having((e) => e.retryAt, 'retryAt', until),
      ),
    );

    // 検索制限は詳細取得に影響しない。
    expect(() => guard.check(GitHubApiResource.core, now), returnsNormally);
  });

  test('RG03: 解除時刻不明でも送信を拒否', () {
    final policy = GitHubRateLimitPolicy();
    final guard = GitHubRateLimitGuard(policy);

    policy.blockResourceWithoutDeadline(GitHubApiResource.search);

    expect(
      () => guard.check(GitHubApiResource.search, now),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.kind, 'kind', ApiFailureKind.rateLimited)
            .having((e) => e.retryAt, 'retryAt', isNull),
      ),
    );

    // 時間経過だけで解除しない。
    expect(
      () => guard.check(
        GitHubApiResource.search,
        now.add(const Duration(days: 1)),
      ),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('RG04: 共通制限なら検索・詳細を両方拒否', () {
    final policy = GitHubRateLimitPolicy();
    final guard = GitHubRateLimitGuard(policy);

    policy.blockAllUntil(now.add(const Duration(minutes: 1)));

    expect(
      () => guard.check(GitHubApiResource.search, now),
      throwsA(isA<ApiFailure>()),
    );

    expect(
      () => guard.check(GitHubApiResource.core, now),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('RG05: 解除時刻に到達したら送信可能', () {
    final policy = GitHubRateLimitPolicy();
    final guard = GitHubRateLimitGuard(policy);

    final until = now.add(const Duration(minutes: 2));

    policy.blockResourceUntil(GitHubApiResource.search, until);

    expect(
      () => guard.check(
        GitHubApiResource.search,
        until.subtract(const Duration(milliseconds: 1)),
      ),
      throwsA(isA<ApiFailure>()),
    );

    expect(() => guard.check(GitHubApiResource.search, until), returnsNormally);
  });
}
