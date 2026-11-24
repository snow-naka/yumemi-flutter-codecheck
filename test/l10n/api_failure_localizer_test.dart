import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/l10n/api_failure_localizer.dart';
import 'package:yumemi_app/l10n/app_localizations.dart';
import 'package:yumemi_app/models/api_failure.dart';

void main() {
  final cases =
      <(ApiFailureKind, ApiFailureReason?, DateTime?, String, String)>[
        // kindによる翻訳
        (
          ApiFailureKind.network,
          null,
          null,
          'GitHubとの通信に失敗しました。',
          'Failed to communicate with GitHub.',
        ),
        (
          ApiFailureKind.timeout,
          null,
          null,
          '通信がタイムアウトしました。',
          'The request timed out.',
        ),
        (
          ApiFailureKind.invalidResponse,
          null,
          null,
          'GitHub APIの応答形式が不正です。',
          'The GitHub API returned an invalid response.',
        ),
        (
          ApiFailureKind.rateLimited,
          null,
          null,
          'GitHub APIの利用制限中です。',
          'The GitHub API rate limit has been reached.',
        ),

        for (final kind in [
          ApiFailureKind.notFoundOrUnavailable,
          ApiFailureKind.accessDenied,
          ApiFailureKind.invalidRequest,
          ApiFailureKind.serverError,
          ApiFailureKind.otherHttp,
        ])
          (
            kind,
            null,
            null,
            'GitHub APIからエラーが返されました。',
            'The GitHub API returned an error.',
          ),

        // reasonによる翻訳
        (
          ApiFailureKind.invalidRequest,
          ApiFailureReason.invalidSearchCondition,
          null,
          '検索条件が不正です。',
          'Invalid search parameters.',
        ),
        (
          ApiFailureKind.invalidRequest,
          ApiFailureReason.invalidRepositoryKey,
          null,
          'リポジトリの指定が不正です。',
          'Invalid repository specification.',
        ),
        (
          ApiFailureKind.invalidResponse,
          ApiFailureReason.issueCountUnverified,
          null,
          'Issue数を確認できませんでした。',
          'Could not verify the open issue count.',
        ),
        (
          ApiFailureKind.invalidResponse,
          ApiFailureReason.repositoryMismatch,
          null,
          '検索時と異なるリポジトリが返されました。',
          'The returned repository differs from the search result.',
        ),
        (
          ApiFailureKind.rateLimited,
          ApiFailureReason.blockedBeforeSend,
          null,
          'GitHubへの送信を一時停止しています。'
              '再試行可能な時刻は不明です。',
          'Requests to GitHub are temporarily paused. '
              'The retry time is unknown.',
        ),
        (
          ApiFailureKind.rateLimited,
          ApiFailureReason.blockedBeforeSend,
          DateTime.utc(2026, 11, 24, 12),
          'GitHubへの送信を一時停止しています。'
              '時間をおいて再試行してください。',
          'Requests to GitHub are temporarily paused. '
              'Please try again later.',
        ),
        (
          ApiFailureKind.network,
          ApiFailureReason.simulatedSearchFailure,
          null,
          '仮の検索失敗です。もう一度検索してください。',
          'Simulated search failure. Please search again.',
        ),
        (
          ApiFailureKind.notFoundOrUnavailable,
          ApiFailureReason.simulatedRepositoryNotFound,
          null,
          '対象の仮データを取得できませんでした。',
          'Could not retrieve the simulated repository.',
        ),
        (
          ApiFailureKind.network,
          ApiFailureReason.simulatedDetailFailure,
          null,
          '仮の詳細取得失敗です。再試行してください。',
          'Simulated detail request failure. Please try again.',
        ),
      ];

  for (final language in ['ja', 'en']) {
    test('LE01: 全エラー情報を安全に翻訳できる ($language)', () async {
      final l10n = await AppLocalizations.delegate.load(Locale(language));

      for (final (kind, reason, retryAt, ja, en) in cases) {
        final failure = ApiFailure(
          kind: kind,
          reason: reason,
          retryAt: retryAt,
        );

        final message = localizeApiFailure(l10n, failure);

        expect(
          message,
          language == 'ja' ? ja : en,
          reason: '$kind / $reason / $retryAt',
        );
      }
    });
  }
}
