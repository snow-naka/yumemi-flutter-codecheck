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

class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    required this.safeMessage,
    this.httpStatus,
    this.retryAt,
  });

  final ApiFailureKind kind;

  // 利用者に表示して安全なメッセージ。
  final String safeMessage;

  // HTTP応答が存在した場合のステータス。
  final int? httpStatus;

  // この時刻より前には再要求しない。
  // 値が存在する場合はUTCで保持する。
  final DateTime? retryAt;

  @override
  String toString() => 'ApiFailure($kind): $safeMessage';
}
