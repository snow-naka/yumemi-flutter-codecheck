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
  String get issueCountFetchMode => 'Open issue count fetch mode';

  @override
  String get issueCountFetchModeAutomatic => 'Automatic (on opening details)';

  @override
  String get issueCountFetchModeManual => 'Manual (on demand)';

  @override
  String get issueCountFetchModeLoading => 'Loading fetch mode';

  @override
  String get issueCountFetchModeSaving => 'Saving fetch mode';

  @override
  String get issueCountFetchModeReadFailed =>
      'Could not load the fetch mode. Manual fetching is used.';

  @override
  String get issueCountFetchModeSaveFailed =>
      'Could not save the issue count fetch mode.';

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

  @override
  String get detailTitle => 'Repository details';

  @override
  String repositoryLanguage(String language) {
    return 'Language: $language';
  }

  @override
  String starCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Stars: $countString';
  }

  @override
  String watcherCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Watchers: $countString';
  }

  @override
  String forkCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Forks: $countString';
  }

  @override
  String openIssueAndPullRequestCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Open issues + PRs: $countString';
  }

  @override
  String get detailLoading => 'Loading repository details…';

  @override
  String get unexpectedDetailError =>
      'An unexpected error occurred while loading repository details.';

  @override
  String get retryDetailSemantics => 'Retry loading repository details';

  @override
  String get ownerAvatar => 'Repository owner avatar';

  @override
  String get openIssuesLoading => 'Open issues (excluding PRs): Fetching…';

  @override
  String openIssueCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Open issues (excluding PRs): $countString';
  }

  @override
  String get openIssuesNotFetched => 'Open issues (excluding PRs): Not fetched';

  @override
  String get refresh => 'Refresh';

  @override
  String get fetch => 'Fetch';

  @override
  String get fetchAgain => 'Fetch again';

  @override
  String get refreshDetailSemantics => 'Refresh repository details';

  @override
  String get fetchOpenIssuesSemantics => 'Fetch open issue count';

  @override
  String get refetchOpenIssuesSemantics => 'Fetch open issue count again';

  @override
  String get retryOpenIssuesSemantics => 'Retry fetching open issue count';

  @override
  String issueFetchedAt(String dateTime) {
    return 'Fetched: $dateTime (device time)';
  }

  @override
  String get unexpectedIssueError =>
      'An unexpected error occurred while fetching the issue count.';

  @override
  String get openIssuesApiNotice =>
      'Automatically fetching, manually fetching, fetching again, or retrying the open issue count uses the GitHub Search API and affects its rate limit. Displaying cached counts does not require an additional request.';

  @override
  String get apiNetworkError => 'Failed to communicate with GitHub.';

  @override
  String get apiTimeoutError => 'The request timed out.';

  @override
  String get apiInvalidResponse =>
      'The GitHub API returned an invalid response.';

  @override
  String get apiRateLimited => 'The GitHub API rate limit has been reached.';

  @override
  String get apiHttpError => 'The GitHub API returned an error.';

  @override
  String get apiInvalidSearchCondition => 'Invalid search parameters.';

  @override
  String get apiInvalidRepositoryKey => 'Invalid repository specification.';

  @override
  String get apiIssueCountUnverified =>
      'Could not verify the open issue count.';

  @override
  String get apiRepositoryMismatch =>
      'The returned repository differs from the search result.';

  @override
  String get apiBlockedBeforeSendUnknown =>
      'Requests to GitHub are temporarily paused. The retry time is unknown.';

  @override
  String get apiBlockedBeforeSendKnown =>
      'Requests to GitHub are temporarily paused. Please try again later.';

  @override
  String get apiSimulatedSearchFailure =>
      'Simulated search failure. Please search again.';

  @override
  String get apiSimulatedRepositoryNotFound =>
      'Could not retrieve the simulated repository.';

  @override
  String get apiSimulatedDetailFailure =>
      'Simulated detail request failure. Please try again.';

  @override
  String get diagnosticDebugOnly =>
      'This screen is available only in debug builds.';

  @override
  String get diagnosticClearHistory => 'Clear history';

  @override
  String get diagnosticEmptyHistory => 'No request history yet.';

  @override
  String get diagnosticDetailOperation => 'Detail';

  @override
  String diagnosticEventTitle(String operation, String status) {
    return '$operation / $status';
  }

  @override
  String diagnosticRecordedAt(String dateTime) {
    return 'Recorded: $dateTime';
  }

  @override
  String get diagnosticResult => 'Result';

  @override
  String get diagnosticRemainingLimit => 'Remaining / Limit';

  @override
  String get diagnosticNotReported => 'Not reported';

  @override
  String diagnosticRetryAfterSeconds(int seconds) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$secondsString s';
  }

  @override
  String get diagnosticPolicyRetryAt => 'App retry time';

  @override
  String get diagnosticUnknownRetryAt =>
      'Resume time unknown (requests paused)';

  @override
  String get diagnosticPolicyBlockedAfterResponse =>
      'Requests paused after response';

  @override
  String get diagnosticResponse => 'HTTP response';

  @override
  String get diagnosticBlockedByRateLimit => 'Blocked before sending';

  @override
  String get diagnosticCanceledBeforeSend => 'Canceled before sending';

  @override
  String get diagnosticTimeout => 'Timeout';

  @override
  String get diagnosticNetworkFailure => 'Network failure';

  @override
  String get diagnosticNotRecorded => 'Not recorded';

  @override
  String diagnosticDeviceTime(String dateTime) {
    return '$dateTime (device time)';
  }
}
