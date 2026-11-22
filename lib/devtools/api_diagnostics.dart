import 'package:flutter/foundation.dart';

enum ApiDiagnosticOperation { search, detail }

enum ApiDiagnosticOutcome {
  response,
  blockedByRateLimit,
  policyBlockedAfterResponse,
  canceledBeforeSend,
  timeout,
  networkFailure,
}

@immutable
final class ApiDiagnosticEvent {
  const ApiDiagnosticEvent({
    required this.recordedAt,
    required this.operation,
    required this.outcome,
    this.httpStatus,
    this.rateLimitLimit,
    this.rateLimitRemaining,
    this.rateLimitResetAt,
    this.retryAfter,
    this.policyRetryAt,
    this.responsePreview,
  });

  final DateTime recordedAt;
  final ApiDiagnosticOperation operation;
  final ApiDiagnosticOutcome outcome;

  final int? httpStatus;

  // GitHubから通知された値。
  final int? rateLimitLimit;
  final int? rateLimitRemaining;
  final DateTime? rateLimitResetAt;
  final Duration? retryAfter;

  // アプリ内部のレート制限管理による値。
  final DateTime? policyRetryAt;

  // サイズ制限・情報選別済みのJSONプレビューのみ。
  // HTTPレスポンス本文を無条件に渡さない。
  final String? responsePreview;
}

abstract interface class ApiDiagnosticsSink {
  void record(ApiDiagnosticEvent event);
}

// 診断機能が無効なときに使用。
final class NoopApiDiagnosticsSink implements ApiDiagnosticsSink {
  const NoopApiDiagnosticsSink();

  @override
  void record(ApiDiagnosticEvent event) {}
}

// 直近の診断情報だけをメモリ上に保持する。
final class InMemoryApiDiagnostics
    extends ValueNotifier<List<ApiDiagnosticEvent>>
    implements ApiDiagnosticsSink {
  InMemoryApiDiagnostics({this.maxEntries = 20})
    : assert(maxEntries > 0),
      super(const <ApiDiagnosticEvent>[]);

  final int maxEntries;

  bool _closed = false;

  @override
  void record(ApiDiagnosticEvent event) {
    if (_closed) return;

    final next = [...value, event];

    // 上限を超えたら古い記録から削除。
    if (next.length > maxEntries) {
      next.removeRange(0, next.length - maxEntries);
    }

    value = List.unmodifiable(next);
  }

  void clear() {
    if (_closed) return;
    value = const <ApiDiagnosticEvent>[];
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
