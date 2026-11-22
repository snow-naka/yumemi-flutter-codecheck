import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 12);

  test('RL01: 検索だけを制限して詳細は許可', () {
    final policy = GitHubRateLimitPolicy();

    policy.blockResourceUntil(
      GitHubApiResource.search,
      now.add(const Duration(minutes: 2)),
    );

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);

    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);
  });

  test('RL02: 共通制限では両方停止', () {
    final policy = GitHubRateLimitPolicy();

    policy.blockAllUntil(now.add(const Duration(minutes: 1)));

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);

    expect(policy.canRequest(GitHubApiResource.core, now), isFalse);
  });

  test('RL03: 解除時刻に到達すると送信可能', () {
    final policy = GitHubRateLimitPolicy();
    final until = now.add(const Duration(minutes: 2));

    policy.blockResourceUntil(GitHubApiResource.search, until);

    expect(
      policy.canRequest(
        GitHubApiResource.search,
        until.subtract(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );

    expect(policy.canRequest(GitHubApiResource.search, until), isTrue);
  });

  test('RL04: 複数制限では遅い解除時刻を優先', () {
    final policy = GitHubRateLimitPolicy();

    final early = now.add(const Duration(minutes: 1));
    final late = now.add(const Duration(minutes: 3));

    policy.blockAllUntil(early);

    policy.blockResourceUntil(GitHubApiResource.search, late);

    expect(policy.retryAt(GitHubApiResource.search, now), late);

    expect(policy.retryAt(GitHubApiResource.core, now), early);

    // 短い制限を追加しても、長い制限を短縮しない。
    policy.blockResourceUntil(GitHubApiResource.search, early);

    expect(policy.retryAt(GitHubApiResource.search, now), late);
  });
  test('RL05: 解除時刻不明のPrimary制限では送信を止める', () {
    final policy = GitHubRateLimitPolicy();

    policy.blockResourceWithoutDeadline(GitHubApiResource.search);

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);

    expect(policy.canRequest(GitHubApiResource.core, now), isTrue);

    // 時間が経過しただけでは自動解除しない。
    expect(
      policy.canRequest(
        GitHubApiResource.search,
        now.add(const Duration(days: 1)),
      ),
      isFalse,
    );
  });

  test('RL06: 解除時刻不明の共通制限では両方停止', () {
    final policy = GitHubRateLimitPolicy();

    policy.blockAllWithoutDeadline();

    expect(policy.canRequest(GitHubApiResource.search, now), isFalse);

    expect(policy.canRequest(GitHubApiResource.core, now), isFalse);
  });

  test('RL07: 解除時刻不明の制限は日時付き制限より優先', () {
    final policy = GitHubRateLimitPolicy();

    policy.blockResourceUntil(
      GitHubApiResource.search,
      now.add(const Duration(minutes: 1)),
    );

    policy.blockResourceWithoutDeadline(GitHubApiResource.search);

    expect(
      policy.canRequest(
        GitHubApiResource.search,
        now.add(const Duration(minutes: 2)),
      ),
      isFalse,
    );
  });
}
