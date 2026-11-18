// Fake段階で使用する分類。実通信の分類・再試行方針はPhase 2で拡張する。
enum ApiFailureKind { network, notFoundOrUnavailable }

class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    required this.safeMessage,
    this.httpStatus,
  });

  final ApiFailureKind kind;
  final String safeMessage;
  final int? httpStatus;

  @override
  String toString() => 'ApiFailure($kind): $safeMessage';
}
