import '../models/api_failure.dart';
import 'app_localizations.dart';

/// APIエラー情報を現在の表示言語に対応した文言へ変換する。
///
/// HTTPレスポンス本文や元の例外メッセージは表示に使用しない。
String localizeApiFailure(AppLocalizations l10n, ApiFailure failure) {
  return switch (failure.reason) {
    ApiFailureReason.invalidSearchCondition => l10n.apiInvalidSearchCondition,

    ApiFailureReason.invalidRepositoryKey => l10n.apiInvalidRepositoryKey,

    ApiFailureReason.issueCountUnverified => l10n.apiIssueCountUnverified,

    ApiFailureReason.repositoryMismatch => l10n.apiRepositoryMismatch,

    ApiFailureReason.blockedBeforeSend =>
      failure.retryAt == null
          ? l10n.apiBlockedBeforeSendUnknown
          : l10n.apiBlockedBeforeSendKnown,

    ApiFailureReason.simulatedSearchFailure => l10n.apiSimulatedSearchFailure,

    ApiFailureReason.simulatedRepositoryNotFound =>
      l10n.apiSimulatedRepositoryNotFound,

    ApiFailureReason.simulatedDetailFailure => l10n.apiSimulatedDetailFailure,

    null => switch (failure.kind) {
      ApiFailureKind.network => l10n.apiNetworkError,
      ApiFailureKind.timeout => l10n.apiTimeoutError,
      ApiFailureKind.invalidResponse => l10n.apiInvalidResponse,
      ApiFailureKind.rateLimited => l10n.apiRateLimited,

      ApiFailureKind.notFoundOrUnavailable ||
      ApiFailureKind.accessDenied ||
      ApiFailureKind.invalidRequest ||
      ApiFailureKind.serverError ||
      ApiFailureKind.otherHttp => l10n.apiHttpError,
    },
  };
}
