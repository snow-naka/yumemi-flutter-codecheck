// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Repository Search'**
  String get appTitle;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @keyword.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get keyword;

  /// No description provided for @keywordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a search keyword.'**
  String get keywordRequired;

  /// No description provided for @searchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter a keyword to search.'**
  String get searchPrompt;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searching;

  /// No description provided for @showFullSearchQuery.
  ///
  /// In en, this message translates to:
  /// **'Show the full search query'**
  String get showFullSearchQuery;

  /// No description provided for @submittedQueryTitle.
  ///
  /// In en, this message translates to:
  /// **'Submitted search query'**
  String get submittedQueryTitle;

  /// The query used for the current search
  ///
  /// In en, this message translates to:
  /// **'Submitted query: {query}'**
  String submittedQueryLabel(String query);

  /// No description provided for @searchPanelPosition.
  ///
  /// In en, this message translates to:
  /// **'Search field position'**
  String get searchPanelPosition;

  /// No description provided for @searchPanelTopDefault.
  ///
  /// In en, this message translates to:
  /// **'Top (default)'**
  String get searchPanelTopDefault;

  /// No description provided for @searchPanelBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get searchPanelBottom;

  /// No description provided for @searchPanelLeftDefault.
  ///
  /// In en, this message translates to:
  /// **'Left (default)'**
  String get searchPanelLeftDefault;

  /// No description provided for @searchPanelRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get searchPanelRight;

  /// No description provided for @searchPanelSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the search field position.'**
  String get searchPanelSaveFailed;

  /// No description provided for @apiDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'API Request Inspector'**
  String get apiDiagnosticsTitle;

  /// Displayed result count and initial total result count
  ///
  /// In en, this message translates to:
  /// **'Showing {displayedCount} / Initial total: {totalCount}'**
  String searchResultCount(int displayedCount, int totalCount);

  /// Result count when there are no displayable results
  ///
  /// In en, this message translates to:
  /// **'Showing: 0 (Total: {totalCount})'**
  String searchEmptyCount(int totalCount);

  /// No description provided for @incompleteResultsWarning.
  ///
  /// In en, this message translates to:
  /// **'Search results may be incomplete.'**
  String get incompleteResultsWarning;

  /// No description provided for @searchEmptyIncomplete.
  ///
  /// In en, this message translates to:
  /// **'No results to display. Search results may be incomplete.'**
  String get searchEmptyIncomplete;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching repositories were found.'**
  String get searchNoMatches;

  /// No description provided for @searchEmptyPage.
  ///
  /// In en, this message translates to:
  /// **'There are no repositories to display on this page.'**
  String get searchEmptyPage;

  /// No description provided for @issueCountFetchMode.
  ///
  /// In en, this message translates to:
  /// **'Open issue count fetch mode'**
  String get issueCountFetchMode;

  /// No description provided for @issueCountFetchModeAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic (on opening details)'**
  String get issueCountFetchModeAutomatic;

  /// No description provided for @issueCountFetchModeManual.
  ///
  /// In en, this message translates to:
  /// **'Manual (on demand)'**
  String get issueCountFetchModeManual;

  /// No description provided for @issueCountFetchModeLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading fetch mode'**
  String get issueCountFetchModeLoading;

  /// No description provided for @issueCountFetchModeSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving fetch mode'**
  String get issueCountFetchModeSaving;

  /// No description provided for @issueCountFetchModeReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the fetch mode. Manual fetching is used.'**
  String get issueCountFetchModeReadFailed;

  /// No description provided for @issueCountFetchModeSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the issue count fetch mode.'**
  String get issueCountFetchModeSaveFailed;

  /// No description provided for @languageUnspecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get languageUnspecified;

  /// No description provided for @viewed.
  ///
  /// In en, this message translates to:
  /// **'Viewed'**
  String get viewed;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @loadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more…'**
  String get loadingMore;

  /// No description provided for @retryLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Retry loading more'**
  String get retryLoadMore;

  /// No description provided for @githubSearchLimitReached.
  ///
  /// In en, this message translates to:
  /// **'The GitHub Search API retrieval limit (1,000 results) has been reached.'**
  String get githubSearchLimitReached;

  /// No description provided for @noMoreResults.
  ///
  /// In en, this message translates to:
  /// **'No more results.'**
  String get noMoreResults;

  /// No description provided for @unexpectedSearchError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred during the search.'**
  String get unexpectedSearchError;

  /// No description provided for @detailTitle.
  ///
  /// In en, this message translates to:
  /// **'Repository details'**
  String get detailTitle;

  /// No description provided for @repositoryLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language: {language}'**
  String repositoryLanguage(String language);

  /// No description provided for @starCount.
  ///
  /// In en, this message translates to:
  /// **'Stars: {count}'**
  String starCount(int count);

  /// No description provided for @watcherCount.
  ///
  /// In en, this message translates to:
  /// **'Watchers: {count}'**
  String watcherCount(int count);

  /// No description provided for @forkCount.
  ///
  /// In en, this message translates to:
  /// **'Forks: {count}'**
  String forkCount(int count);

  /// No description provided for @openIssueAndPullRequestCount.
  ///
  /// In en, this message translates to:
  /// **'Open issues + PRs: {count}'**
  String openIssueAndPullRequestCount(int count);

  /// No description provided for @detailLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading repository details…'**
  String get detailLoading;

  /// No description provided for @unexpectedDetailError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred while loading repository details.'**
  String get unexpectedDetailError;

  /// No description provided for @retryDetailSemantics.
  ///
  /// In en, this message translates to:
  /// **'Retry loading repository details'**
  String get retryDetailSemantics;

  /// No description provided for @ownerAvatar.
  ///
  /// In en, this message translates to:
  /// **'Repository owner avatar'**
  String get ownerAvatar;

  /// No description provided for @openIssuesLoading.
  ///
  /// In en, this message translates to:
  /// **'Open issues (excluding PRs): Fetching…'**
  String get openIssuesLoading;

  /// No description provided for @openIssueCount.
  ///
  /// In en, this message translates to:
  /// **'Open issues (excluding PRs): {count}'**
  String openIssueCount(int count);

  /// No description provided for @openIssuesNotFetched.
  ///
  /// In en, this message translates to:
  /// **'Open issues (excluding PRs): Not fetched'**
  String get openIssuesNotFetched;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @fetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get fetch;

  /// No description provided for @fetchAgain.
  ///
  /// In en, this message translates to:
  /// **'Fetch again'**
  String get fetchAgain;

  /// No description provided for @refreshDetailSemantics.
  ///
  /// In en, this message translates to:
  /// **'Refresh repository details'**
  String get refreshDetailSemantics;

  /// No description provided for @fetchOpenIssuesSemantics.
  ///
  /// In en, this message translates to:
  /// **'Fetch open issue count'**
  String get fetchOpenIssuesSemantics;

  /// No description provided for @refetchOpenIssuesSemantics.
  ///
  /// In en, this message translates to:
  /// **'Fetch open issue count again'**
  String get refetchOpenIssuesSemantics;

  /// No description provided for @retryOpenIssuesSemantics.
  ///
  /// In en, this message translates to:
  /// **'Retry fetching open issue count'**
  String get retryOpenIssuesSemantics;

  /// No description provided for @issueFetchedAt.
  ///
  /// In en, this message translates to:
  /// **'Fetched: {dateTime} (device time)'**
  String issueFetchedAt(String dateTime);

  /// No description provided for @unexpectedIssueError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred while fetching the issue count.'**
  String get unexpectedIssueError;

  /// No description provided for @openIssuesApiNotice.
  ///
  /// In en, this message translates to:
  /// **'Fetching, fetching again, or retrying the open issue count uses one GitHub Search API request per operation and affects the API rate limit.'**
  String get openIssuesApiNotice;

  /// No description provided for @apiNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Failed to communicate with GitHub.'**
  String get apiNetworkError;

  /// No description provided for @apiTimeoutError.
  ///
  /// In en, this message translates to:
  /// **'The request timed out.'**
  String get apiTimeoutError;

  /// No description provided for @apiInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The GitHub API returned an invalid response.'**
  String get apiInvalidResponse;

  /// No description provided for @apiRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The GitHub API rate limit has been reached.'**
  String get apiRateLimited;

  /// No description provided for @apiHttpError.
  ///
  /// In en, this message translates to:
  /// **'The GitHub API returned an error.'**
  String get apiHttpError;

  /// No description provided for @apiInvalidSearchCondition.
  ///
  /// In en, this message translates to:
  /// **'Invalid search parameters.'**
  String get apiInvalidSearchCondition;

  /// No description provided for @apiInvalidRepositoryKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid repository specification.'**
  String get apiInvalidRepositoryKey;

  /// No description provided for @apiIssueCountUnverified.
  ///
  /// In en, this message translates to:
  /// **'Could not verify the open issue count.'**
  String get apiIssueCountUnverified;

  /// No description provided for @apiRepositoryMismatch.
  ///
  /// In en, this message translates to:
  /// **'The returned repository differs from the search result.'**
  String get apiRepositoryMismatch;

  /// No description provided for @apiBlockedBeforeSendUnknown.
  ///
  /// In en, this message translates to:
  /// **'Requests to GitHub are temporarily paused. The retry time is unknown.'**
  String get apiBlockedBeforeSendUnknown;

  /// No description provided for @apiBlockedBeforeSendKnown.
  ///
  /// In en, this message translates to:
  /// **'Requests to GitHub are temporarily paused. Please try again later.'**
  String get apiBlockedBeforeSendKnown;

  /// No description provided for @apiSimulatedSearchFailure.
  ///
  /// In en, this message translates to:
  /// **'Simulated search failure. Please search again.'**
  String get apiSimulatedSearchFailure;

  /// No description provided for @apiSimulatedRepositoryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Could not retrieve the simulated repository.'**
  String get apiSimulatedRepositoryNotFound;

  /// No description provided for @apiSimulatedDetailFailure.
  ///
  /// In en, this message translates to:
  /// **'Simulated detail request failure. Please try again.'**
  String get apiSimulatedDetailFailure;

  /// No description provided for @diagnosticDebugOnly.
  ///
  /// In en, this message translates to:
  /// **'This screen is available only in debug builds.'**
  String get diagnosticDebugOnly;

  /// No description provided for @diagnosticClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get diagnosticClearHistory;

  /// No description provided for @diagnosticEmptyHistory.
  ///
  /// In en, this message translates to:
  /// **'No request history yet.'**
  String get diagnosticEmptyHistory;

  /// No description provided for @diagnosticDetailOperation.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get diagnosticDetailOperation;

  /// No description provided for @diagnosticEventTitle.
  ///
  /// In en, this message translates to:
  /// **'{operation} / {status}'**
  String diagnosticEventTitle(String operation, String status);

  /// No description provided for @diagnosticRecordedAt.
  ///
  /// In en, this message translates to:
  /// **'Recorded: {dateTime}'**
  String diagnosticRecordedAt(String dateTime);

  /// No description provided for @diagnosticResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get diagnosticResult;

  /// No description provided for @diagnosticRemainingLimit.
  ///
  /// In en, this message translates to:
  /// **'Remaining / Limit'**
  String get diagnosticRemainingLimit;

  /// No description provided for @diagnosticNotReported.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get diagnosticNotReported;

  /// No description provided for @diagnosticRetryAfterSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String diagnosticRetryAfterSeconds(int seconds);

  /// No description provided for @diagnosticPolicyRetryAt.
  ///
  /// In en, this message translates to:
  /// **'App retry time'**
  String get diagnosticPolicyRetryAt;

  /// No description provided for @diagnosticUnknownRetryAt.
  ///
  /// In en, this message translates to:
  /// **'Resume time unknown (requests paused)'**
  String get diagnosticUnknownRetryAt;

  /// No description provided for @diagnosticPolicyBlockedAfterResponse.
  ///
  /// In en, this message translates to:
  /// **'Requests paused after response'**
  String get diagnosticPolicyBlockedAfterResponse;

  /// No description provided for @diagnosticResponse.
  ///
  /// In en, this message translates to:
  /// **'HTTP response'**
  String get diagnosticResponse;

  /// No description provided for @diagnosticBlockedByRateLimit.
  ///
  /// In en, this message translates to:
  /// **'Blocked before sending'**
  String get diagnosticBlockedByRateLimit;

  /// No description provided for @diagnosticCanceledBeforeSend.
  ///
  /// In en, this message translates to:
  /// **'Canceled before sending'**
  String get diagnosticCanceledBeforeSend;

  /// No description provided for @diagnosticTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get diagnosticTimeout;

  /// No description provided for @diagnosticNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Network failure'**
  String get diagnosticNetworkFailure;

  /// No description provided for @diagnosticNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get diagnosticNotRecorded;

  /// No description provided for @diagnosticDeviceTime.
  ///
  /// In en, this message translates to:
  /// **'{dateTime} (device time)'**
  String diagnosticDeviceTime(String dateTime);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
