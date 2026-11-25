enum GitHubApiResource { search, core }

class GitHubRateLimitPolicy {
  final _blockedUntil = <GitHubApiResource, DateTime>{};
  final _unknownDeadlineResources = <GitHubApiResource>{};
  bool _sharedUnknownDeadline = false;
  DateTime? _sharedBlockedUntil;

  // 特定のAPI種類だけを停止する。
  void blockResourceUntil(GitHubApiResource resource, DateTime until) {
    final target = until.toUtc();
    final previous = _blockedUntil[resource];

    if (previous == null || target.isAfter(previous)) {
      _blockedUntil[resource] = target;
    }
  }

  // 共通の制限によって両方を停止する。
  void blockAllUntil(DateTime until) {
    final target = until.toUtc();

    if (_sharedBlockedUntil == null || target.isAfter(_sharedBlockedUntil!)) {
      _sharedBlockedUntil = target;
    }
  }

  // 現在有効な制限のうち、最も遅い解除時刻を返す。
  // 制限がなければnull。
  DateTime? retryAt(GitHubApiResource resource, DateTime now) {
    final current = now.toUtc();
    DateTime? latest;

    for (final until in [_blockedUntil[resource], _sharedBlockedUntil]) {
      if (until == null || !until.isAfter(current)) {
        continue;
      }

      if (latest == null || until.isAfter(latest)) {
        latest = until;
      }
    }

    return latest;
  }

  // 期限不明の停止または未経過の停止期限があれば送信を許可しない。
  bool canRequest(GitHubApiResource resource, DateTime now) {
    if (_sharedUnknownDeadline ||
        _unknownDeadlineResources.contains(resource)) {
      return false;
    }

    return retryAt(resource, now) == null;
  }

  // 解除時刻が不明な特定Resourceの制限。
  void blockResourceWithoutDeadline(GitHubApiResource resource) {
    _unknownDeadlineResources.add(resource);
  }

  // 解除時刻が不明な共通制限。
  void blockAllWithoutDeadline() {
    _sharedUnknownDeadline = true;
  }
}
