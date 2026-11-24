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
}
