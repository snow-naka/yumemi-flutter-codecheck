// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'リポジトリ検索';

  @override
  String get search => '検索';

  @override
  String get cancel => 'キャンセル';

  @override
  String get retry => '再試行';

  @override
  String get close => '閉じる';

  @override
  String get keyword => 'キーワード';

  @override
  String get keywordRequired => '検索キーワードを入力してください。';

  @override
  String get searchPrompt => 'キーワードを入力して検索してください。';

  @override
  String get searching => '検索中…';

  @override
  String get showFullSearchQuery => '検索語の全文を表示';

  @override
  String get submittedQueryTitle => '送信済みの検索語';

  @override
  String submittedQueryLabel(String query) {
    return '送信済みの検索語：$query';
  }

  @override
  String get searchPanelPosition => '検索欄の配置';

  @override
  String get searchPanelTopDefault => '上に配置（標準）';

  @override
  String get searchPanelBottom => '下に配置';

  @override
  String get searchPanelLeftDefault => '左に配置（標準）';

  @override
  String get searchPanelRight => '右に配置';

  @override
  String get searchPanelSaveFailed => '検索欄の配置を保存できませんでした。';

  @override
  String get apiDiagnosticsTitle => 'API通信インスペクター';

  @override
  String searchResultCount(int displayedCount, int totalCount) {
    final intl.NumberFormat displayedCountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String displayedCountString = displayedCountNumberFormat.format(
      displayedCount,
    );
    final intl.NumberFormat totalCountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalCountString = totalCountNumberFormat.format(totalCount);

    return '$displayedCountString件表示 / 初回総件数 $totalCountString件';
  }

  @override
  String searchEmptyCount(int totalCount) {
    final intl.NumberFormat totalCountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalCountString = totalCountNumberFormat.format(totalCount);

    return '表示中：0件（総件数：$totalCountString件）';
  }

  @override
  String get incompleteResultsWarning => '検索結果が不完全な可能性があります。';

  @override
  String get searchEmptyIncomplete => '表示できる結果がありません。検索結果が不完全な可能性があります。';

  @override
  String get searchNoMatches => '一致するリポジトリは見つかりませんでした。';

  @override
  String get searchEmptyPage => 'このページには表示できるリポジトリがありません。';

  @override
  String get languageUnspecified => '未指定';

  @override
  String get viewed => '閲覧済み';

  @override
  String get loadMore => 'もっと読み込む';

  @override
  String get loadingMore => '追加読み込み中…';

  @override
  String get retryLoadMore => '追加読み込みを再試行';

  @override
  String get githubSearchLimitReached => 'GitHub検索APIの取得上限（1,000件）に達しました。';

  @override
  String get noMoreResults => 'これ以上の結果はありません。';

  @override
  String get unexpectedSearchError => '検索処理中に問題が発生しました。';

  @override
  String get detailTitle => 'リポジトリ詳細';

  @override
  String repositoryLanguage(String language) {
    return '言語：$language';
  }

  @override
  String starCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Star数：$countString';
  }

  @override
  String watcherCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Watcher数：$countString';
  }

  @override
  String forkCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Fork数：$countString';
  }

  @override
  String openIssueAndPullRequestCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Open Issue＋PR数：$countString';
  }

  @override
  String get detailLoading => '詳細情報を取得中…';

  @override
  String get unexpectedDetailError => '詳細情報の処理中に問題が発生しました。';

  @override
  String get retryDetailSemantics => 'リポジトリ詳細情報の取得を再試行';

  @override
  String get ownerAvatar => 'オーナーアイコン';

  @override
  String get openIssuesLoading => 'Open Issue数（PR除外）：取得中…';

  @override
  String openIssueCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Open Issue数（PR除外）：$countString';
  }

  @override
  String get openIssuesNotFetched => 'Open Issue数（PR除外）：未取得';

  @override
  String get refresh => '更新';

  @override
  String get fetch => '取得';

  @override
  String get fetchAgain => '再取得';

  @override
  String get refreshDetailSemantics => 'リポジトリ詳細情報を更新';

  @override
  String get fetchOpenIssuesSemantics => 'Open Issue数を取得';

  @override
  String get refetchOpenIssuesSemantics => 'Open Issue数を再取得';

  @override
  String get retryOpenIssuesSemantics => 'Open Issue数の取得を再試行';

  @override
  String issueFetchedAt(String dateTime) {
    return '取得日時：$dateTime（端末時刻）';
  }

  @override
  String get unexpectedIssueError => 'Issue数の取得中に問題が発生しました。';

  @override
  String get openIssuesApiNotice =>
      '※ Open Issue数の取得・再取得・再試行には、操作ごとにGitHub Search APIを1回使用します。APIのレート制限に影響します。';

  @override
  String get apiNetworkError => 'GitHubとの通信に失敗しました。';

  @override
  String get apiTimeoutError => '通信がタイムアウトしました。';

  @override
  String get apiInvalidResponse => 'GitHub APIの応答形式が不正です。';

  @override
  String get apiRateLimited => 'GitHub APIの利用制限中です。';

  @override
  String get apiHttpError => 'GitHub APIからエラーが返されました。';

  @override
  String get apiInvalidSearchCondition => '検索条件が不正です。';

  @override
  String get apiInvalidRepositoryKey => 'リポジトリの指定が不正です。';

  @override
  String get apiIssueCountUnverified => 'Issue数を確認できませんでした。';

  @override
  String get apiRepositoryMismatch => '検索時と異なるリポジトリが返されました。';

  @override
  String get apiBlockedBeforeSendUnknown =>
      'GitHubへの送信を一時停止しています。再試行可能な時刻は不明です。';

  @override
  String get apiBlockedBeforeSendKnown =>
      'GitHubへの送信を一時停止しています。時間をおいて再試行してください。';

  @override
  String get apiSimulatedSearchFailure => '仮の検索失敗です。もう一度検索してください。';

  @override
  String get apiSimulatedRepositoryNotFound => '対象の仮データを取得できませんでした。';

  @override
  String get apiSimulatedDetailFailure => '仮の詳細取得失敗です。再試行してください。';

  @override
  String get diagnosticDebugOnly => '開発ビルド専用の画面です';

  @override
  String get diagnosticClearHistory => '履歴を消去';

  @override
  String get diagnosticEmptyHistory => '通信履歴はまだありません';

  @override
  String get diagnosticDetailOperation => '詳細';

  @override
  String diagnosticEventTitle(String operation, String status) {
    return '$operation / $status';
  }

  @override
  String diagnosticRecordedAt(String dateTime) {
    return '記録：$dateTime';
  }

  @override
  String get diagnosticResult => '結果';

  @override
  String get diagnosticRemainingLimit => '残り / 上限';

  @override
  String get diagnosticNotReported => '未通知';

  @override
  String diagnosticRetryAfterSeconds(int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$secondsString秒';
  }

  @override
  String get diagnosticPolicyRetryAt => 'アプリ側の再試行目安';

  @override
  String get diagnosticUnknownRetryAt => '解除時刻不明（送信停止中）';

  @override
  String get diagnosticPolicyBlockedAfterResponse => '応答後の送信制限';

  @override
  String get diagnosticResponse => 'HTTP応答';

  @override
  String get diagnosticBlockedByRateLimit => '送信前に制限';

  @override
  String get diagnosticCanceledBeforeSend => '送信前キャンセル';

  @override
  String get diagnosticTimeout => 'タイムアウト';

  @override
  String get diagnosticNetworkFailure => '通信失敗';

  @override
  String get diagnosticNotRecorded => '未記録';

  @override
  String diagnosticDeviceTime(String dateTime) {
    return '$dateTime（端末時刻）';
  }
}
