enum ApiFailureKind {
  network,
  timeout,
  notFoundOrUnavailable,
  rateLimited,
  accessDenied,
  invalidRequest,
  serverError,
  invalidResponse,
  otherHttp,
}

// エラー種別だけでは表現できない具体的な原因。
enum ApiFailureReason {
  invalidSearchCondition,
  invalidRepositoryKey,
  issueCountUnverified,
  repositoryMismatch,
  blockedBeforeSend,
  simulatedSearchFailure,
  simulatedRepositoryNotFound,
  simulatedDetailFailure,
}

class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    this.reason,
    this.httpStatus,
    this.retryAt,
  });

  final ApiFailureKind kind;

  // 具体的な原因が必要な場合のみ設定する。
  final ApiFailureReason? reason;

  // HTTP応答が存在した場合のステータス。
  final int? httpStatus;

  // この時刻より前には再要求しない。
  // 値が存在する場合はUTCで保持する。
  final DateTime? retryAt;

  @override
  String toString() => reason == null
      ? 'ApiFailure(${kind.name})'
      : 'ApiFailure(${kind.name}, reason: ${reason!.name})';
}
