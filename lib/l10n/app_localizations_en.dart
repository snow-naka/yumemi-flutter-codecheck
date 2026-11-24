// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Repository Search';

  @override
  String get search => 'Search';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get keyword => 'Keyword';

  @override
  String get keywordRequired => 'Please enter a search keyword.';

  @override
  String get searchPrompt => 'Enter a keyword to search.';

  @override
  String get searching => 'Searching…';

  @override
  String get showFullSearchQuery => 'Show the full search query';

  @override
  String get submittedQueryTitle => 'Submitted search query';

  @override
  String submittedQueryLabel(String query) {
    return 'Submitted query: $query';
  }

  @override
  String get searchPanelPosition => 'Search field position';

  @override
  String get searchPanelTopDefault => 'Top (default)';

  @override
  String get searchPanelBottom => 'Bottom';

  @override
  String get searchPanelLeftDefault => 'Left (default)';

  @override
  String get searchPanelRight => 'Right';

  @override
  String get searchPanelSaveFailed =>
      'Could not save the search field position.';

  @override
  String get apiDiagnosticsTitle => 'API Request Inspector';

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

    return 'Showing $displayedCountString / Initial total: $totalCountString';
  }

  @override
  String searchEmptyCount(int totalCount) {
    final intl.NumberFormat totalCountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalCountString = totalCountNumberFormat.format(totalCount);

    return 'Showing: 0 (Total: $totalCountString)';
  }

  @override
  String get incompleteResultsWarning => 'Search results may be incomplete.';

  @override
  String get searchEmptyIncomplete =>
      'No results to display. Search results may be incomplete.';

  @override
  String get searchNoMatches => 'No matching repositories were found.';

  @override
  String get searchEmptyPage =>
      'There are no repositories to display on this page.';

  @override
  String get languageUnspecified => 'Not specified';

  @override
  String get viewed => 'Viewed';

  @override
  String get loadMore => 'Load more';

  @override
  String get loadingMore => 'Loading more…';

  @override
  String get retryLoadMore => 'Retry loading more';

  @override
  String get githubSearchLimitReached =>
      'The GitHub Search API retrieval limit (1,000 results) has been reached.';

  @override
  String get noMoreResults => 'No more results.';

  @override
  String get unexpectedSearchError =>
      'An unexpected error occurred during the search.';
}
