import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yumemi_app/data/http_github_repository_gateway.dart';
import 'package:yumemi_app/data/github_rate_limit_policy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/features/detail/repository_detail_provider.dart';
import 'package:yumemi_app/features/detail/repository_detail_screen.dart';
import 'package:yumemi_app/features/search/search_controller.dart';
import 'package:yumemi_app/features/search/search_state.dart';
import 'package:yumemi_app/main.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/providers.dart';
import 'package:yumemi_app/l10n/app_localizations.dart';
import 'package:yumemi_app/features/detail/issue_count_fetch_preferences.dart';
import 'package:yumemi_app/l10n/localized_date_time.dart';

import 'issue_count_fetch_mode_test_support.dart';
import '../search/search_test_support.dart';

void main() {
  late List<String> searches;
  late List<RepositoryKey> keys;
  late List<Completer<RepositoryDetail>> requests;
  late FakeGitHubRepositoryGateway fake;
  late List<RepositoryKey> issueKeys;
  late List<Completer<int>> issueRequests;
  final issueButtonFinder = find.byKey(const Key('load-open-issues'));

  final refreshButtonFinder = find.byKey(
    const Key('refresh-repository-detail'),
  );
  setUp(() {
    searches = [];
    keys = [];
    requests = [];
    issueKeys = [];
    issueRequests = [];
    fake = FakeGitHubRepositoryGateway(
      searchHandler: (query, {required page, required perPage}) async {
        searches.add(query);
        return resultPage(count: 30);
      },
      detailHandler: (key) {
        keys.add(key);
        final pending = Completer<RepositoryDetail>();
        requests.add(pending);
        return pending.future;
      },
      openIssueCountHandler: (key) {
        issueKeys.add(key);
        final pending = Completer<int>();
        issueRequests.add(pending);
        return pending.future;
      },
    );
  });

  void expectAccessibleButton(
    WidgetTester tester,
    Finder button, {
    required String visibleText,
    required String semanticLabel,
  }) {
    expect(button, findsOneWidget);

    expect(
      find.descendant(of: button, matching: find.text(visibleText)),
      findsOneWidget,
    );

    expect(tester.getSemantics(button).label, semanticLabel);
  }

  Future<ProviderContainer> start(
    WidgetTester tester, {
    Locale locale = const Locale('ja', 'JP'),
    IssueCountFetchMode mode = IssueCountFetchMode.manual,
    Future<void>? modeReadGate,
    bool modeReadFails = false,
  }) async {
    tester.platformDispatcher.localesTestValue = [locale];

    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final modeStore = TestIssueCountFetchModeStore(
      mode: mode,
      readGate: modeReadGate,
      failRead: modeReadFails,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          githubRepositoryGatewayProvider.overrideWithValue(fake),
          issueCountFetchModeStoreProvider.overrideWithValue(modeStore),
        ],
        child: const MyApp(),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'submitted');

    await tester.tap(find.byKey(const Key('search-submit-button')));

    await tester.pump();

    return tester.container();
  }

  Future<void> open(WidgetTester tester, {String name = 'repository-0'}) async {
    await tester.tap(find.text(name));
    await tester.pump();
    final route = ModalRoute.of(
      tester.element(find.byType(RepositoryDetailScreen, skipOffstage: false)),
    )!;
    // インジケーターは動き続けるため、画面遷移の完了だけを待つ。
    for (
      var frame = 0;
      route.animation!.status != AnimationStatus.completed && frame < 200;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(route.animation!.status, AnimationStatus.completed);
    await tester.pump();
  }

  Future<void> back(WidgetTester tester) async {
    final route = ModalRoute.of(
      tester.element(find.byType(RepositoryDetailScreen)),
    )!;
    final animation = route.animation!;
    await tester.tap(find.byType(BackButton));
    for (
      var frame = 0;
      animation.status != AnimationStatus.dismissed && frame < 200;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(animation.status, AnimationStatus.dismissed);
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpAvatarCase(WidgetTester tester, String avatarUrl) async {
    final summary = RepositorySummary(
      key: const RepositoryKey(id: 100, owner: 'sample', name: 'example'),
      avatarUrl: avatarUrl,
      language: 'Dart',
      starCount: 10,
      forkCount: 2,
      openIssueAndPullRequestCount: 1,
    );

    // 詳細取得を保留し、渡された概要のアイコンを確認する。
    final pending = Completer<RepositoryDetail>();

    final avatarFake = FakeGitHubRepositoryGateway(
      detailHandler: (_) => pending.future,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          githubRepositoryGatewayProvider.overrideWithValue(avatarFake),
          issueCountFetchModeStoreProvider.overrideWithValue(
            TestIssueCountFetchModeStore(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RepositoryDetailScreen(summary: summary),
        ),
      ),
    );
  }

  testWidgets('selected summary is shown while only its detail is pending', (
    tester,
  ) async {
    final container = await start(tester);
    final searchState =
        container.read(searchControllerProvider) as SearchResults;
    await open(tester);
    expect(keys, [searchState.items.first.key]);
    expect(find.text('repository-0'), findsOneWidget);
    expect(find.text('言語：Dart'), findsOneWidget);
    expect(find.text('詳細情報を取得中…'), findsOneWidget);
    expect(find.textContaining('Watcher数：'), findsNothing);
    expect(find.textContaining('Star数：'), findsNothing);
    final old = searchState.items.first;
    final updated = RepositorySummary(
      key: old.key,
      avatarUrl: '',
      language: 'Rust',
      starCount: 321,
      forkCount: 12,
      openIssueAndPullRequestCount: 7,
    );
    requests.single.complete(
      RepositoryDetail(summary: updated, watcherCount: 8),
    );
    await tester.pump();
    expect(find.text('言語：Rust'), findsOneWidget);
    expect(find.text('Star数：321'), findsOneWidget);
    expect(find.text('Watcher数：8'), findsOneWidget);
    expect(find.text('Open Issue＋PR数：7'), findsOneWidget);
    expect(container.read(searchControllerProvider), same(searchState));
    expect(searches, ['submitted']);
  });

  testWidgets(
    'failure stays visible without auto retry; manual retry changes only detail',
    (tester) async {
      final container = await start(tester);
      final searchState =
          container.read(searchControllerProvider) as SearchResults;
      await open(tester);
      requests.single.completeError(
        const ApiFailure(kind: ApiFailureKind.network),
      );
      await tester.pump();
      expect(find.text('GitHubとの通信に失敗しました。'), findsOneWidget);
      expect(find.text('repository-0'), findsOneWidget);
      expect(find.textContaining('Watcher数：'), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(keys, hasLength(1));
      expect(container.read(searchControllerProvider), same(searchState));
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(keys, hasLength(2));
      expect(find.text('詳細情報を取得中…'), findsOneWidget);
      expect(find.text('GitHubとの通信に失敗しました。'), findsNothing);
      requests.last.complete(
        RepositoryDetail(summary: searchState.items.first, watcherCount: 8),
      );
      await tester.pump();
      expect(find.text('Watcher数：8'), findsOneWidget);
      expect(container.read(searchControllerProvider), same(searchState));
      expect(searches, ['submitted']);
    },
  );

  testWidgets(
    'return preserves submitted query, draft, results and exact scroll offset',
    (tester) async {
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final container = await start(tester);
      await tester.scrollUntilVisible(
        find.text('repository-12'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'unsubmitted draft');
      await tester.pump();
      final offset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      final searchState =
          container.read(searchControllerProvider) as SearchResults;
      await open(tester, name: 'repository-12');
      requests.single.completeError(
        const ApiFailure(kind: ApiFailureKind.network),
      );
      await tester.pump();
      await back(tester);
      expect(container.read(searchControllerProvider), same(searchState));
      expect(find.text('送信済みの検索語：submitted'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'unsubmitted draft',
      );
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        offset,
      );
      expect(offset, greaterThan(0));
      expect(searches, ['submitted']);
    },
  );

  testWidgets(
    'leaving during loading discards late response and reopening refetches',
    (tester) async {
      final container = await start(tester);
      final searchState =
          container.read(searchControllerProvider) as SearchResults;
      final summary = searchState.items.first;
      await open(tester);
      await back(tester);
      expect(
        container.read(repositoryDetailProvider(summary.key).exists),
        isFalse,
      );
      await open(tester);
      expect(keys, hasLength(2));
      requests.first.complete(
        RepositoryDetail(summary: summary, watcherCount: 99),
      );
      await tester.pump();
      expect(find.text('詳細情報を取得中…'), findsOneWidget);
      expect(find.text('Watcher数：99'), findsNothing);
      requests.last.complete(
        RepositoryDetail(summary: summary, watcherCount: 8),
      );
      await tester.pump();
      expect(find.text('Watcher数：8'), findsOneWidget);
      expect(searches, ['submitted']);
    },
  );

  testWidgets('DC04: 同じ詳細を開き直すたびにCoreから取得する', (tester) async {
    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    // 1回目は詳細APIを取得。
    await open(tester);

    expect(keys, [summary.key]);
    expect(requests, hasLength(1));

    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );

    await tester.pump();

    expect(find.text('Watcher数：8'), findsOneWidget);

    // 詳細画面を閉じる。
    await back(tester);

    // 詳細Providerは破棄される。
    expect(
      container.read(repositoryDetailProvider(summary.key).exists),
      isFalse,
    );

    // 同じリポジトリを再び開く。
    await open(tester);
    await tester.pump();

    expect(keys, [summary.key, summary.key]);
    expect(find.text('詳細情報を取得中…'), findsOneWidget);
    expect(find.text('Watcher数：8'), findsNothing);
    requests.last.complete(RepositoryDetail(summary: summary, watcherCount: 9));
    await tester.pump();
    expect(find.text('Watcher数：9'), findsOneWidget);
    expect(issueRequests, isEmpty);
  });

  testWidgets('unexpected detail errors do not claim to be network failures', (
    tester,
  ) async {
    final container = await start(tester);
    final searchState = container.read(searchControllerProvider);
    await open(tester);
    requests.single.completeError(StateError('internal bug'));
    await tester.pump();
    expect(find.text('詳細情報の処理中に問題が発生しました。'), findsOneWidget);
    expect(find.textContaining('internal bug'), findsNothing);
    expect(container.read(searchControllerProvider), same(searchState));
  });

  testWidgets(
    'default Fake detail retries explicitly and displays zero and null values',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];

      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            githubRepositoryGatewayProvider.overrideWithValue(
              FakeGitHubRepositoryGateway(delay: Duration.zero),
            ),
          ],
          child: const MyApp(),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'riverpod');
      await tester.tap(find.byKey(const Key('search-submit-button')));
      await tester.pump();
      final container = tester.container();
      final searchState = container.read(searchControllerProvider);
      await open(tester, name: 'riverpod-sample');
      expect(find.text('言語：未指定'), findsOneWidget);
      expect(find.text('仮の詳細取得失敗です。再試行してください。'), findsOneWidget);
      expect(find.textContaining('Watcher数：'), findsNothing);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(find.text('Star数：0'), findsOneWidget);
      expect(find.text('Watcher数：0'), findsOneWidget);
      expect(find.text('Fork数：0'), findsOneWidget);
      expect(find.text('Open Issue＋PR数：0'), findsOneWidget);
      expect(container.read(searchControllerProvider), same(searchState));
      await back(tester);
      expect(find.text('送信済みの検索語：riverpod'), findsOneWidget);
    },
  );

  testWidgets('IC05: Issue数は操作時だけ取得し二重要求しない', (tester) async {
    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    // 詳細取得を完了させる。
    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();

    // 詳細画面を開いただけではIssue検索しない。
    expect(issueKeys, isEmpty);
    expect(find.text('Open Issue数（PR除外）：未取得'), findsOneWidget);

    final button = issueButtonFinder;

    // 連続して押しても要求は1回だけ。
    await tester.tap(button);

    // 1回目のタップ直後
    expect(issueKeys, hasLength(1), reason: '1回目のタップ');

    // 画面を再構築
    await tester.pump();

    // 取得中はボタンが無効になるはず
    expect(
      tester.widget<OutlinedButton>(button).onPressed,
      isNull,
      reason: '取得中はボタンを無効にする',
    );

    await tester.tap(button);

    // 2回目でも要求は増えないはず
    expect(issueKeys, hasLength(1), reason: '2回目のタップ');
    await tester.pump();

    expect(issueKeys, [summary.key]);
    expect(issueRequests, hasLength(1));

    expect(find.text('Open Issue数（PR除外）：取得中…'), findsOneWidget);

    // 通信完了。
    issueRequests.single.complete(7);
    await tester.pump();

    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);

    // 既存の詳細情報は維持される。
    expect(find.text('Watcher数：8'), findsOneWidget);
    expect(find.text('Star数：${summary.starCount}'), findsOneWidget);
  });

  testWidgets('IC06: Issue数の取得失敗は詳細情報を壊さない', (tester) async {
    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();

    await tester.tap(issueButtonFinder);
    await tester.pump();

    issueRequests.single.completeError(
      const ApiFailure(kind: ApiFailureKind.rateLimited),
    );
    await tester.pump();

    expect(find.text('GitHub APIの利用制限中です。'), findsOneWidget);

    expect(find.text('Watcher数：8'), findsOneWidget);

    // 自動再試行は行わない。
    expect(issueKeys, hasLength(1));

    // 利用者が明示的に再試行する。
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys, hasLength(2));

    issueRequests.last.complete(12);
    await tester.pump();

    expect(find.text('Open Issue数（PR除外）：12'), findsOneWidget);
    expect(find.text('Watcher数：8'), findsOneWidget);
  });

  testWidgets('AV01: アイコンURLが空なら代替表示する', (tester) async {
    await pumpAvatarCase(tester, '');

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('AV02: 不正URLとHTTP URLでは画像通信しない', (tester) async {
    for (final url in [
      'not a valid URL',
      'http://example.com/avatar.png',
      'https:///avatar.png',
    ]) {
      await pumpAvatarCase(tester, url);

      expect(find.byIcon(Icons.person), findsOneWidget, reason: 'URL: $url');
      expect(find.byType(Image), findsNothing, reason: 'URL: $url');
    }
  });

  testWidgets('AV03: 画像取得失敗時の代替アイコンが設定されている', (tester) async {
    const url = 'https://avatars.githubusercontent.com/u/12345678';

    await pumpAvatarCase(tester, url);

    // 正常なHTTPS URLではNetworkImageを使用する。
    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);

    final image = tester.widget<Image>(imageFinder);

    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, url);

    // 画像取得が失敗した場合の表示を直接検証する。
    final errorBuilder = image.errorBuilder;
    expect(errorBuilder, isNotNull);

    final fallback = errorBuilder!(
      tester.element(imageFinder),
      StateError('Simulated image failure'),
      StackTrace.empty,
    );

    expect(fallback, isA<CircleAvatar>());

    final avatar = fallback as CircleAvatar;
    expect(avatar.child, isA<Icon>());
    expect((avatar.child! as Icon).icon, Icons.person);
  });

  testWidgets('IC07: 戻る操作後のキュー待ちIssue検索は送信しない', (tester) async {
    final sentPaths = <String>[];
    final heldResponse = Completer<http.Response>();

    final client = MockClient((request) async {
      sentPaths.add(request.url.path);

      if (request.url.path == '/search/repositories') {
        // キューを塞ぐため、HTTP応答を保留する。
        return heldResponse.future;
      }

      if (request.url.path == '/search/issues') {
        return http.Response(
          '{"total_count":7,"incomplete_results":false,"items":[{"number":1}]}',
          200,
        );
      }

      throw StateError('Unexpected HTTP request: ${request.url}');
    });
    addTearDown(client.close);

    final httpGateway = HttpGitHubRepositoryGateway(
      client: client,
      policy: GitHubRateLimitPolicy(),
      now: () => DateTime.utc(2026, 11, 22, 12),
    );

    final gateway = _IssueViaHttpGateway(httpGateway);

    tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];

    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubRepositoryGatewayProvider.overrideWithValue(gateway)],
        child: const MyApp(),
      ),
    );

    // 1. Fakeで検索・詳細画面を表示する。
    await tester.enterText(find.byType(TextFormField), 'submitted');
    await tester.tap(find.byKey(const Key('search-submit-button')));
    await tester.pump();

    await tester.tap(find.text('repository-0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(issueButtonFinder, findsOneWidget);

    // 2. 別のHTTP検索でGatewayのキューを塞ぐ。
    final holdingSearch = httpGateway.searchRepositories('queue-holder');

    await tester.pump();

    expect(sentPaths, ['/search/repositories']);

    // 3. Issue検索を要求する。まだ送信はできない。
    await tester.tap(issueButtonFinder);
    expect(
      find.text('Issue数の取得中に問題が発生しました。', skipOffstage: false),
      findsNothing,
    );
    await tester.pump();

    expect(sentPaths, ['/search/repositories']);

    // 4. 詳細画面から戻る。
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 16));

    // 退場アニメーション中なのでWidgetはまだ存在する。
    expect(
      find.byType(RepositoryDetailScreen, skipOffstage: false),
      findsOneWidget,
    );

    // 5. 戻るアニメーションが終わる前に先行HTTPを完了。
    heldResponse.complete(
      http.Response(
        '{"total_count":0,"incomplete_results":false,"items":[]}',
        200,
      ),
    );

    await tester.pump();
    await holdingSearch;
    await tester.pump();

    // 6. Issue検索はHTTP送信されない。
    expect(sentPaths, ['/search/repositories']);

    // 画面の退場完了後も不要な送信がない。
    await tester.pump(const Duration(milliseconds: 400));

    expect(sentPaths, ['/search/repositories']);
  });

  testWidgets('IC08: Issue＋PR数は詳細取得中・失敗中も保持し成功後に更新', (tester) async {
    final container = await start(tester);

    final state = container.read(searchControllerProvider) as SearchResults;

    final summary = state.items.first;

    // 検索結果から得た件数は7。
    expect(summary.openIssueAndPullRequestCount, 7);

    await open(tester);

    // 1. 詳細取得中も検索概要の件数を表示する。
    expect(find.text('Open Issue＋PR数：7'), findsOneWidget);
    expect(find.text('詳細情報を取得中…'), findsOneWidget);
    expect(issueKeys, isEmpty);

    // 2. 詳細取得に失敗しても7件を維持する。
    requests.single.completeError(
      const ApiFailure(kind: ApiFailureKind.network),
    );

    await tester.pump();

    expect(find.text('GitHubとの通信に失敗しました。'), findsOneWidget);
    expect(find.text('Open Issue＋PR数：7'), findsOneWidget);
    expect(issueKeys, isEmpty);

    // 3. 詳細情報を手動で再取得する。
    await tester.tap(find.text('再試行'));
    await tester.pump();

    expect(requests, hasLength(2));
    expect(find.text('Open Issue＋PR数：7'), findsOneWidget);

    // 4. 詳細APIから新しい件数9を受信する。
    final updatedSummary = RepositorySummary(
      key: summary.key,
      avatarUrl: summary.avatarUrl,
      language: summary.language,
      starCount: summary.starCount,
      forkCount: summary.forkCount,
      openIssueAndPullRequestCount: 9,
    );

    requests.last.complete(
      RepositoryDetail(summary: updatedSummary, watcherCount: 8),
    );

    await tester.pump();

    expect(find.text('Open Issue＋PR数：9'), findsOneWidget);
    expect(find.text('Open Issue＋PR数：7'), findsNothing);

    // この一連の処理ではIssue検索APIを使用しない。
    expect(issueKeys, isEmpty);
    expect(container.read(searchControllerProvider), same(state));
  });

  testWidgets('IC11: 詳細更新・画面再表示でもIssue数を保持', (tester) async {
    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    // 1. 初回の詳細取得。
    await open(tester);

    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();

    // 2. PR除外Issue数を明示取得。
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys, [summary.key]);

    issueRequests.single.complete(7);
    await tester.pump();

    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);
    expect(find.textContaining('取得日時：'), findsOneWidget);

    // 3. 詳細情報だけを手動更新。
    final refreshButton = refreshButtonFinder;

    await tester.ensureVisible(refreshButton);
    await tester.tap(refreshButton);
    await tester.pump();

    expect(requests, hasLength(2));
    expect(issueRequests, hasLength(1));

    // 詳細取得中でもIssue数は残る。
    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);

    requests.last.complete(RepositoryDetail(summary: summary, watcherCount: 9));
    await tester.pump();

    expect(find.text('Watcher数：9'), findsOneWidget);

    // PR除外Issue数は更新されない。
    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);
    expect(issueRequests, hasLength(1));

    // 4. 開き直すと詳細だけを再取得し、Issue数・取得日時は表示を維持する。
    await back(tester);
    await open(tester);
    await tester.pump();

    expect(find.text('Watcher数：9'), findsNothing);
    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);
    expect(find.textContaining('取得日時：'), findsOneWidget);
    expect(requests, hasLength(3));
    requests.last.complete(
      RepositoryDetail(summary: summary, watcherCount: 10),
    );
    await tester.pump();
    expect(find.text('Watcher数：10'), findsOneWidget);
    expect(issueRequests, hasLength(1));
  });

  testWidgets('IC13: 改名後は詳細APIで確認した名前をIssue検索に使用', (tester) async {
    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    final renamedKey = RepositoryKey(
      id: summary.key.id,
      owner: 'renamed-owner',
      name: 'renamed-repository',
    );

    await open(tester);

    // 検索時と同じIDだが、詳細APIでは名前が変わっている。
    requests.single.complete(
      RepositoryDetail(
        summary: RepositorySummary(
          key: renamedKey,
          avatarUrl: summary.avatarUrl,
          language: summary.language,
          starCount: summary.starCount,
          forkCount: summary.forkCount,
          openIssueAndPullRequestCount: summary.openIssueAndPullRequestCount,
        ),
        watcherCount: 8,
      ),
    );

    await tester.pump();

    expect(find.text('renamed-owner/renamed-repository'), findsOneWidget);

    // ボタンを押すまではIssue検索しない。
    expect(issueKeys, isEmpty);

    await tester.tap(issueButtonFinder);
    await tester.pump();

    // 古いowner/nameではなく詳細APIの新しい名前を使う。
    expect(issueKeys, [renamedKey]);

    issueRequests.single.complete(7);
    await tester.pump();

    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);
  });

  testWidgets('IC14: 旧名の再利用・詳細取得失敗では別IDの詳細を表示せずIssueを送らない', (tester) async {
    final container = await start(tester);
    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;
    final issueButton = issueButtonFinder;

    await open(tester);
    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();
    await back(tester);
    await open(tester);
    expect(keys, [summary.key, summary.key]);
    expect(tester.widget<OutlinedButton>(issueButton).onPressed, isNull);

    // 同じowner/nameを、現在は別のリポジトリIDが使っている。
    requests.last.complete(
      RepositoryDetail(
        summary: RepositorySummary(
          key: RepositoryKey(
            id: summary.key.id + 1,
            owner: summary.key.owner,
            name: summary.key.name,
          ),
          avatarUrl: '',
          language: 'Other',
          starCount: 99,
          forkCount: 0,
          openIssueAndPullRequestCount: 77,
        ),
        watcherCount: 99,
      ),
    );
    await tester.pump();
    expect(find.text('検索時と異なるリポジトリが返されました。'), findsOneWidget);
    expect(find.text('Watcher数：99'), findsNothing);
    expect(
      find.text('Open Issue＋PR数：${summary.openIssueAndPullRequestCount}'),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(issueButton).onPressed, isNull);

    await tester.tap(find.text('再試行'));
    await tester.pump();
    requests.last.completeError(const ApiFailure(kind: ApiFailureKind.network));
    await tester.pump();
    expect(find.text('GitHubとの通信に失敗しました。'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(issueButton).onPressed, isNull);
    expect(issueKeys, isEmpty);
  });

  testWidgets('IC15: Issue取得と詳細更新は再描画前から両方向に排他する', (tester) async {
    final container = await start(tester);
    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;
    await open(tester);
    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 1),
    );
    await tester.pump();

    final refresh = refreshButtonFinder;
    final issue = issueButtonFinder;
    final previousRefresh = tester.widget<OutlinedButton>(refresh).onPressed!;
    await tester.tap(issue);
    previousRefresh(); // 同じフレームのボタンも要求を追加できない。
    await tester.pump();
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);
    expect(requests, hasLength(1));
    issueRequests.single.complete(7);
    await tester.pump();

    final cache = container.read(openIssueCountCacheProvider);
    final saved = cache.get(summary.key)!;
    expect(saved.count, 7);
    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);
    final reload = issueButtonFinder;
    final previousReload = tester.widget<OutlinedButton>(reload).onPressed!;
    await tester.tap(refresh);
    previousReload();
    await tester.pump();
    expect(tester.widget<OutlinedButton>(reload).onPressed, isNull);
    expect(requests, hasLength(2));
    expect(issueRequests, hasLength(1));

    requests.last.complete(RepositoryDetail(summary: summary, watcherCount: 2));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(reload).onPressed, isNotNull);
    expect(cache.get(summary.key), same(saved));

    await tester.tap(reload);
    issueRequests.last.completeError(
      const ApiFailure(kind: ApiFailureKind.network),
    );
    await tester.pump();
    expect(find.text('GitHubとの通信に失敗しました。'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
    expect(cache.get(summary.key), same(saved));
  });

  testWidgets('IC16: 画面を閉じた後のIssue応答は以前の件数・取得日時を変更しない', (tester) async {
    final container = await start(tester);
    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;
    final cache = container.read(openIssueCountCacheProvider)
      ..put(summary.key, 5);
    final saved = cache.get(summary.key);
    await open(tester);
    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 1),
    );
    await tester.pump();
    await tester.tap(issueButtonFinder);
    await tester.pump();
    await back(tester);
    await open(tester);
    issueRequests.single.complete(99);
    await tester.pump();
    expect(cache.get(summary.key), same(saved));
    expect(find.text('Open Issue数（PR除外）：5'), findsOneWidget);
    expect(find.textContaining('取得日時：'), findsOneWidget);
    expect(issueRequests, hasLength(1));
  });

  testWidgets('DL01: 狭い画面ではIssue情報とボタンを縦に並べる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await start(tester);
    await open(tester);

    final info = find.text('Open Issue数（PR除外）：未取得');
    final button = find.byKey(const Key('load-open-issues'));

    expect(info, findsOneWidget);
    expect(button, findsOneWidget);

    expect(
      tester.getTopLeft(button).dy,
      greaterThan(tester.getBottomLeft(info).dy),
    );
  });

  testWidgets('DL02: 広い画面ではIssue情報とボタンを左右に並べる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await start(tester);
    await open(tester);

    final info = find.text('Open Issue数（PR除外）：未取得');
    final button = find.byKey(const Key('load-open-issues'));

    expect(
      tester.getTopLeft(button).dx,
      greaterThan(tester.getTopRight(info).dx),
    );
  });

  testWidgets('AX01: 詳細更新とIssue取得の表示・読み上げ名', (tester) async {
    final container = await start(tester);
    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();

    final coreButton = find.byKey(const Key('refresh-repository-detail'));
    final issueButton = find.byKey(const Key('load-open-issues'));

    expectAccessibleButton(
      tester,
      coreButton,
      visibleText: '更新',
      semanticLabel: 'リポジトリ詳細情報を更新',
    );

    expectAccessibleButton(
      tester,
      issueButton,
      visibleText: '取得',
      semanticLabel: 'Open Issue数を取得',
    );

    // Issue数取得に成功した後は「再取得」に変わる。
    await tester.tap(issueButton);
    await tester.pump();

    issueRequests.single.complete(12);
    await tester.pump();

    expectAccessibleButton(
      tester,
      issueButton,
      visibleText: '再取得',
      semanticLabel: 'Open Issue数を再取得',
    );
  });

  testWidgets('AX02: Issue取得失敗時の再試行の表示・読み上げ名', (tester) async {
    final container = await start(tester);
    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();

    final issueButton = find.byKey(const Key('load-open-issues'));

    await tester.tap(issueButton);
    await tester.pump();

    issueRequests.single.completeError(
      const ApiFailure(kind: ApiFailureKind.network),
    );
    await tester.pump();

    expectAccessibleButton(
      tester,
      issueButton,
      visibleText: '再試行',
      semanticLabel: 'Open Issue数の取得を再試行',
    );
  });

  testWidgets('AX03: 詳細取得失敗時の再試行の表示・読み上げ名', (tester) async {
    await start(tester);
    await open(tester);

    requests.single.completeError(
      const ApiFailure(kind: ApiFailureKind.network),
    );
    await tester.pump();

    expectAccessibleButton(
      tester,
      find.byKey(const Key('retry-repository-detail')),
      visibleText: '再試行',
      semanticLabel: 'リポジトリ詳細情報の取得を再試行',
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('BW01: 横画面で操作ボタンが必要以上に広がらない'
        ' (scale=$scale)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 390));

      tester.platformDispatcher.textScaleFactorTestValue = scale;

      addTearDown(() async {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });

      final container = await start(tester);

      final summary = (container.read(
        searchControllerProvider,
      ) as SearchResults).items.first;

      await open(tester);

      requests.single.complete(
        RepositoryDetail(summary: summary, watcherCount: 8),
      );

      await tester.pumpAndSettle();

      final coreButton = find.byKey(const Key('refresh-repository-detail'));

      final issueButton = find.byKey(const Key('load-open-issues'));

      final statistics = find.byKey(const Key('detail-section-statistics'));

      final issues = find.byKey(const Key('detail-section-issues'));

      final coreRect = tester.getRect(coreButton);
      final issueRect = tester.getRect(issueButton);
      final statisticsRect = tester.getRect(statistics);
      final issuesRect = tester.getRect(issues);

      // ボタンが最大幅いっぱいまで広がっていない。
      expect(coreRect.width, lessThan(statisticsRect.width * 0.4));

      expect(issueRect.width, lessThan(issuesRect.width * 0.4));

      // 右端に配置されている。
      expect(coreRect.right, closeTo(statisticsRect.right, 1));

      expect(issueRect.right, closeTo(issuesRect.right, 1));

      // レイアウト変更による追加通信はない。
      expect(keys, hasLength(1));
      expect(issueKeys, isEmpty);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('LD01: 英語環境で詳細情報とIssue数を表示できる', (tester) async {
    final container = await start(tester, locale: const Locale('en', 'US'));

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    expect(find.text('Repository details'), findsOneWidget);
    expect(find.text('Language: Dart'), findsOneWidget);
    expect(find.text('Loading repository details…'), findsOneWidget);

    final updated = RepositorySummary(
      key: summary.key,
      avatarUrl: '',
      language: 'Dart',
      starCount: 12345,
      forkCount: 1234,
      openIssueAndPullRequestCount: 3456,
    );

    requests.single.complete(
      RepositoryDetail(summary: updated, watcherCount: 2345),
    );

    await tester.pumpAndSettle();

    // 英語表示と数値の桁区切り。
    expect(find.text('Stars: 12,345'), findsOneWidget);
    expect(find.text('Watchers: 2,345'), findsOneWidget);
    expect(find.text('Forks: 1,234'), findsOneWidget);
    expect(find.text('Open issues + PRs: 3,456'), findsOneWidget);

    expect(
      find.text('Open issues (excluding PRs): Not fetched'),
      findsOneWidget,
    );

    // 表示文言と読み上げ文言を検証。
    expectAccessibleButton(
      tester,
      refreshButtonFinder,
      visibleText: 'Refresh',
      semanticLabel: 'Refresh repository details',
    );

    expectAccessibleButton(
      tester,
      issueButtonFinder,
      visibleText: 'Fetch',
      semanticLabel: 'Fetch open issue count',
    );

    // Issue数を取得。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(find.text('Open issues (excluding PRs): Fetching…'), findsOneWidget);

    expect(
      tester.widget<OutlinedButton>(refreshButtonFinder).onPressed,
      isNull,
    );

    issueRequests.single.complete(12000);
    await tester.pumpAndSettle();

    expect(find.text('Open issues (excluding PRs): 12,000'), findsOneWidget);

    expect(find.textContaining('Fetched: '), findsOneWidget);
    expect(find.textContaining('(device time)'), findsOneWidget);

    expectAccessibleButton(
      tester,
      issueButtonFinder,
      visibleText: 'Fetch again',
      semanticLabel: 'Fetch open issue count again',
    );

    // API利用上の注意書きも英語で表示。
    final notice = tester.widget<Text>(
      find.byKey(const Key('open-issues-api-notice')),
    );

    expect(notice.data, contains('uses the GitHub Search API'));

    expect(keys, [summary.key]);
    expect(issueKeys, [summary.key]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LD02: 英語環境でIssue取得失敗後に再試行できる', (tester) async {
    final container = await start(tester, locale: const Locale('en', 'US'));

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );

    await tester.pumpAndSettle();

    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    // Issue数の取得に失敗。
    issueRequests.single.completeError(
      const ApiFailure(kind: ApiFailureKind.network),
    );

    await tester.pumpAndSettle();

    expect(find.text('Failed to communicate with GitHub.'), findsOneWidget);

    expect(
      find.text('Open issues (excluding PRs): Not fetched'),
      findsOneWidget,
    );

    expectAccessibleButton(
      tester,
      issueButtonFinder,
      visibleText: 'Retry',
      semanticLabel: 'Retry fetching open issue count',
    );

    expect(issueKeys, [summary.key]);

    // 明示的に再試行する。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(find.text('Open issues (excluding PRs): Fetching…'), findsOneWidget);

    expect(issueKeys, [summary.key, summary.key]);

    // 0件は未取得ではなく正常な取得結果として扱う。
    issueRequests.last.complete(0);
    await tester.pumpAndSettle();

    expect(find.text('Open issues (excluding PRs): 0'), findsOneWidget);

    expect(find.text('Open issues (excluding PRs): Not fetched'), findsNothing);

    expect(find.text('Failed to communicate with GitHub.'), findsNothing);

    expectAccessibleButton(
      tester,
      issueButtonFinder,
      visibleText: 'Fetch again',
      semanticLabel: 'Fetch open issue count again',
    );

    expect(keys, [summary.key]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LD03: 詳細・Issue取得中の言語変更でも状態を維持する', (tester) async {
    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    expect(find.text('リポジトリ詳細'), findsOneWidget);
    expect(find.text('詳細情報を取得中…'), findsOneWidget);

    // 詳細取得中に英語へ変更。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    // 詳細取得中はインジケーターが動き続けるため、
    // pumpAndSettleは使用しない。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Repository details'), findsOneWidget);
    expect(find.text('Loading repository details…'), findsOneWidget);

    expect(keys, [summary.key]);

    // 言語変更前に開始した要求を完了させる。
    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );

    await tester.pumpAndSettle();

    expect(find.text('Watchers: 8'), findsOneWidget);

    // Issue数の取得を開始。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(find.text('Open issues (excluding PRs): Fetching…'), findsOneWidget);

    // Issue取得中に日本語へ戻す。
    tester.platformDispatcher.localesTestValue = [const Locale('ja', 'JP')];

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Open Issue数（PR除外）：取得中…'), findsOneWidget);

    // 言語変更によって排他制御が解除されない。
    expect(tester.widget<OutlinedButton>(issueButtonFinder).onPressed, isNull);
    expect(
      tester.widget<OutlinedButton>(refreshButtonFinder).onPressed,
      isNull,
    );

    expect(keys, [summary.key]);
    expect(issueKeys, [summary.key]);

    // 言語変更前のIssue要求を完了させる。
    issueRequests.single.complete(7);
    await tester.pumpAndSettle();

    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);

    final cache = container.read(openIssueCountCacheProvider);
    final saved = cache.get(summary.key);

    expect(saved, isNotNull);
    expect(saved!.count, 7);

    // 取得完了後、再び英語へ変更。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    expect(find.text('Repository details'), findsOneWidget);
    expect(find.text('Watchers: 8'), findsOneWidget);

    expect(find.text('Open issues (excluding PRs): 7'), findsOneWidget);

    expect(find.textContaining('Fetched: '), findsOneWidget);

    // キャッシュも更新されていない。
    expect(cache.get(summary.key), same(saved));

    expectAccessibleButton(
      tester,
      issueButtonFinder,
      visibleText: 'Fetch again',
      semanticLabel: 'Fetch open issue count again',
    );

    // 言語変更だけではAPI通信を追加しない。
    expect(searches, ['submitted']);
    expect(keys, [summary.key]);
    expect(issueKeys, [summary.key]);

    expect(tester.takeException(), isNull);
  });
  testWidgets('LE03: 詳細取得エラーの言語変更と再試行', (tester) async {
    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    requests.single.completeError(
      const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        reason: ApiFailureReason.repositoryMismatch,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('検索時と異なるリポジトリが返されました。'), findsOneWidget);

    // 詳細取得失敗中に英語へ変更。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pumpAndSettle();

    expect(
      find.text('The returned repository differs from the search result.'),
      findsOneWidget,
    );

    expect(find.text('検索時と異なるリポジトリが返されました。'), findsNothing);

    expect(find.text(summary.name), findsOneWidget);

    final retry = find.byKey(const Key('retry-repository-detail'));

    expectAccessibleButton(
      tester,
      retry,
      visibleText: 'Retry',
      semanticLabel: 'Retry loading repository details',
    );

    // 言語変更による追加通信はない。
    expect(keys, [summary.key]);
    expect(issueKeys, isEmpty);

    // 詳細取得に失敗している間はIssue取得もできない。
    expect(tester.widget<OutlinedButton>(issueButtonFinder).onPressed, isNull);

    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();

    expect(keys, [summary.key, summary.key]);

    requests.last.complete(RepositoryDetail(summary: summary, watcherCount: 8));

    await tester.pumpAndSettle();

    expect(find.text('Watchers: 8'), findsOneWidget);

    expect(
      find.text('The returned repository differs from the search result.'),
      findsNothing,
    );

    expect(issueKeys, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final (label, error, jaMessage, enMessage) in [
    (
      'API failure',
      const ApiFailure(kind: ApiFailureKind.network),
      'GitHubとの通信に失敗しました。',
      'Failed to communicate with GitHub.',
    ),
    (
      'unexpected failure',
      StateError('INTERNAL_ISSUE_ERROR'),
      'Issue数の取得中に問題が発生しました。',
      'An unexpected error occurred while fetching the issue count.',
    ),
  ]) {
    testWidgets('LE04: Issue再取得失敗後の言語変更とキャッシュ保持 ($label)', (tester) async {
      final container = await start(tester);

      final summary = (container.read(
        searchControllerProvider,
      ) as SearchResults).items.first;

      await open(tester);

      requests.single.complete(
        RepositoryDetail(summary: summary, watcherCount: 8),
      );

      await tester.pumpAndSettle();

      // 最初のIssue取得は成功させる。
      await tester.ensureVisible(issueButtonFinder);
      await tester.tap(issueButtonFinder);
      await tester.pump();

      issueRequests.single.complete(7);
      await tester.pumpAndSettle();

      final cache = container.read(openIssueCountCacheProvider);
      final saved = cache.get(summary.key);

      expect(saved, isNotNull);
      expect(saved!.count, 7);

      // Issue再取得時に失敗させる。
      await tester.ensureVisible(issueButtonFinder);
      await tester.tap(issueButtonFinder);
      await tester.pump();

      issueRequests.last.completeError(error);
      await tester.pumpAndSettle();

      expect(find.text(jaMessage), findsOneWidget);
      expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);
      expect(find.textContaining('取得日時：'), findsOneWidget);

      expect(cache.get(summary.key), same(saved));

      // エラー表示中に英語へ変更。
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

      await tester.pumpAndSettle();

      expect(find.text(enMessage), findsOneWidget);
      expect(find.text(jaMessage), findsNothing);

      // 前回取得済みの値は保持する。
      expect(find.text('Open issues (excluding PRs): 7'), findsOneWidget);
      expect(find.textContaining('Fetched: '), findsOneWidget);
      expect(cache.get(summary.key), same(saved));

      // 元の例外の内容を画面に露出しない。
      expect(find.textContaining('INTERNAL_ISSUE_ERROR'), findsNothing);

      expectAccessibleButton(
        tester,
        issueButtonFinder,
        visibleText: 'Fetch again',
        semanticLabel: 'Fetch open issue count again',
      );

      // 言語変更では通信を追加しない。
      expect(keys, [summary.key]);
      expect(issueKeys, [summary.key, summary.key]);

      // 明示的な再取得で正常状態へ戻る。
      await tester.ensureVisible(issueButtonFinder);
      await tester.tap(issueButtonFinder);
      await tester.pump();

      issueRequests.last.complete(9);
      await tester.pumpAndSettle();

      expect(find.text('Open issues (excluding PRs): 9'), findsOneWidget);
      expect(find.text(enMessage), findsNothing);
      expect(cache.get(summary.key)!.count, 9);

      expect(keys, hasLength(1));
      expect(issueKeys, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, brightness) in const [
    (Size(320, 800), Brightness.light),
    (Size(800, 390), Brightness.light),
    (Size(800, 390), Brightness.dark),
  ]) {
    testWidgets('LR01: 英語・文字倍率2倍でも詳細画面を操作できる'
        ' (${size.width}x${size.height}, ${brightness.name})', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;

      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final container = await start(tester, locale: const Locale('en', 'US'));

      final summary = (container.read(
        searchControllerProvider,
      ) as SearchResults).items.first;

      await open(tester);

      // 詳細取得中に画面サイズと文字倍率を変更。
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;

      await tester.pump();

      expect(find.text('Loading repository details…'), findsOneWidget);

      expect(tester.takeException(), isNull);

      requests.single.complete(
        RepositoryDetail(summary: summary, watcherCount: 12345),
      );

      await tester.pumpAndSettle();

      expect(find.text('Watchers: 12,345'), findsOneWidget);

      final statistics = find.byKey(const Key('detail-section-statistics'));

      final issues = find.byKey(const Key('detail-section-issues'));

      void expectButtonLayout(Finder button, Finder section) {
        final buttonRect = tester.getRect(button);
        final sectionRect = tester.getRect(section);

        if (size.width > size.height) {
          // 横画面では右寄せ、最大幅40%。
          expect(
            buttonRect.width,
            lessThanOrEqualTo(sectionRect.width * 0.4 + 1),
          );

          expect(buttonRect.right, closeTo(sectionRect.right, 1));
        } else {
          // 狭い縦画面では全幅表示。
          expect(buttonRect.width, closeTo(sectionRect.width, 1));
        }
      }

      // Core API更新ボタンの配置と操作領域。
      await tester.ensureVisible(refreshButtonFinder);
      await tester.pumpAndSettle();

      expectButtonLayout(refreshButtonFinder, statistics);

      expect(refreshButtonFinder.hitTestable(), findsOneWidget);

      // Issue取得ボタンも操作可能。
      await tester.ensureVisible(issueButtonFinder);
      await tester.pumpAndSettle();

      expectButtonLayout(issueButtonFinder, issues);

      expect(issueButtonFinder.hitTestable(), findsOneWidget);

      await tester.tap(issueButtonFinder);
      await tester.pump();

      issueRequests.single.complete(12345);
      await tester.pumpAndSettle();

      expect(find.text('Open issues (excluding PRs): 12,345'), findsOneWidget);

      // 長い「Fetch again」でもレイアウトを維持する。
      await tester.ensureVisible(issueButtonFinder);
      await tester.pumpAndSettle();

      expectButtonLayout(issueButtonFinder, issues);

      expectAccessibleButton(
        tester,
        issueButtonFinder,
        visibleText: 'Fetch again',
        semanticLabel: 'Fetch open issue count again',
      );

      expect(issueButtonFinder.hitTestable(), findsOneWidget);

      // 画面下部のAPI利用上の注意書きまで読める。
      final notice = find.byKey(const Key('open-issues-api-notice'));

      await tester.ensureVisible(notice);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(RepositoryDetailScreen)))
            .brightness,
        brightness,
      );

      final viewport = tester.getRect(find.byType(SingleChildScrollView));

      final noticeRect = tester.getRect(notice);

      expect(noticeRect.top, greaterThanOrEqualTo(viewport.top - 1));

      expect(noticeRect.bottom, lessThanOrEqualTo(viewport.bottom + 1));

      // 表示条件の変更で不要な通信を行わない。
      expect(keys, [summary.key]);
      expect(issueKeys, [summary.key]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('DM03: テーマ変更時も詳細・Issue取得状態を維持する', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final container = await start(tester);

    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;

    await open(tester);

    Brightness currentBrightness() =>
        Theme.of(tester.element(find.byType(RepositoryDetailScreen)))
            .brightness;

    expect(currentBrightness(), Brightness.light);
    expect(find.text('詳細情報を取得中…'), findsOneWidget);

    // 詳細取得中にダークモードへ変更。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(currentBrightness(), Brightness.dark);
    expect(find.text('詳細情報を取得中…'), findsOneWidget);
    expect(keys, [summary.key]);

    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );

    await tester.pumpAndSettle();

    expect(find.text('Watcher数：8'), findsOneWidget);

    // Issue数の取得を開始。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(find.text('Open Issue数（PR除外）：取得中…'), findsOneWidget);

    // Issue取得中にライトモードへ変更。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(currentBrightness(), Brightness.light);

    expect(find.text('Open Issue数（PR除外）：取得中…'), findsOneWidget);

    // テーマ変更で排他制御が解除されない。
    expect(
      tester.widget<OutlinedButton>(refreshButtonFinder).onPressed,
      isNull,
    );

    expect(tester.widget<OutlinedButton>(issueButtonFinder).onPressed, isNull);

    expect(keys, [summary.key]);
    expect(issueKeys, [summary.key]);

    issueRequests.single.complete(7);
    await tester.pumpAndSettle();

    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);

    final cache = container.read(openIssueCountCacheProvider);
    final saved = cache.get(summary.key);

    expect(saved, isNotNull);
    expect(saved!.count, 7);

    // 取得完了後に再びダークモードへ変更。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

    await tester.pumpAndSettle();

    expect(currentBrightness(), Brightness.dark);
    expect(find.text('Watcher数：8'), findsOneWidget);

    expect(find.text('Open Issue数（PR除外）：7'), findsOneWidget);

    expect(find.textContaining('取得日時：'), findsOneWidget);

    expectAccessibleButton(
      tester,
      issueButtonFinder,
      visibleText: '再取得',
      semanticLabel: 'Open Issue数を再取得',
    );

    // キャッシュの再生成や追加通信が発生しない。
    expect(cache.get(summary.key), same(saved));
    expect(searches, ['submitted']);
    expect(keys, [summary.key]);
    expect(issueKeys, [summary.key]);

    expect(tester.takeException(), isNull);
  });

  Future<void> completeDetail(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final searchState =
        container.read(searchControllerProvider) as SearchResults;

    requests.last.complete(
      RepositoryDetail(summary: searchState.items.first, watcherCount: 8),
    );

    await tester.pump();
    await tester.pump();
  }

  AppLocalizations detailL10n(WidgetTester tester) {
    return AppLocalizations.of(
      tester.element(find.byType(RepositoryDetailScreen)),
    );
  }

  Future<ProviderContainer> openWithIssueCountForRefresh(
    WidgetTester tester, {
    IssueCountFetchMode mode = IssueCountFetchMode.automatic,
    int count = 15,
  }) async {
    final container = await start(tester, mode: mode);

    await open(tester);
    await completeDetail(tester, container);

    if (mode == IssueCountFetchMode.manual) {
      expect(issueKeys, isEmpty);

      await tester.ensureVisible(issueButtonFinder);
      await tester.tap(issueButtonFinder);
      await tester.pump();
    }

    expect(keys.length, 1);
    expect(issueKeys.length, 1);

    issueRequests.single.complete(count);
    await tester.pumpAndSettle();

    expect(find.text(detailL10n(tester).openIssueCount(count)), findsOneWidget);

    return container;
  }

  Future<void> tapDetailRefresh(WidgetTester tester) async {
    await tester.ensureVisible(refreshButtonFinder);
    await tester.tap(refreshButtonFinder);
    await tester.pump();
  }

  testWidgets('IA01: 詳細取得成功後にIssue数を自動取得する', (tester) async {
    final container = await start(tester, mode: IssueCountFetchMode.automatic);

    await open(tester);

    expect(keys.length, 1);
    expect(issueKeys, isEmpty);

    await completeDetail(tester, container);

    expect(issueKeys, [keys.single]);

    // Issue取得中も詳細情報を表示する。
    expect(find.text(detailL10n(tester).watcherCount(8)), findsOneWidget);

    expect(find.text(detailL10n(tester).openIssuesLoading), findsOneWidget);

    expect(tester.widget<OutlinedButton>(issueButtonFinder).onPressed, isNull);

    expect(
      tester.widget<OutlinedButton>(refreshButtonFinder).onPressed,
      isNull,
    );

    issueRequests.single.complete(12);
    await tester.pumpAndSettle();

    expect(find.text(detailL10n(tester).openIssueCount(12)), findsOneWidget);

    expect(issueKeys.length, 1);

    expect(
      container.read(openIssueCountCacheProvider).get(keys.single)?.count,
      12,
    );
  });

  testWidgets('IA02: 手動モードではIssue数を自動取得しない', (tester) async {
    final container = await start(tester, mode: IssueCountFetchMode.manual);

    await open(tester);
    await completeDetail(tester, container);

    expect(issueKeys, isEmpty);

    expect(find.text(detailL10n(tester).openIssuesNotFetched), findsOneWidget);

    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys, [keys.single]);

    issueRequests.single.complete(5);
    await tester.pumpAndSettle();

    expect(find.text(detailL10n(tester).openIssueCount(5)), findsOneWidget);
  });

  for (final mode in IssueCountFetchMode.values) {
    final automatic = mode == IssueCountFetchMode.automatic;
    final id = automatic ? 'IA03' : 'IA04';

    testWidgets('$id: 設定読み込み完了まで自動取得を保留する (${mode.name})', (tester) async {
      final gate = Completer<void>();

      final container = await start(
        tester,
        mode: mode,
        modeReadGate: gate.future,
      );

      await open(tester);
      await completeDetail(tester, container);

      // 詳細取得が先に完了してもIssue取得は始めない。
      expect(issueKeys, isEmpty);

      expect(find.text(detailL10n(tester).watcherCount(8)), findsOneWidget);

      gate.complete();

      await tester.pump();
      await tester.pump();

      if (automatic) {
        expect(issueKeys, [keys.single]);

        issueRequests.single.complete(6);
        await tester.pumpAndSettle();

        expect(find.text(detailL10n(tester).openIssueCount(6)), findsOneWidget);
      } else {
        await tester.pumpAndSettle();

        expect(issueKeys, isEmpty);

        expect(
          find.text(detailL10n(tester).openIssuesNotFetched),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('IA05: 設定読み込み失敗時は自動取得しない', (tester) async {
    final container = await start(
      tester,
      mode: IssueCountFetchMode.automatic,
      modeReadFails: true,
    );

    await open(tester);
    await completeDetail(tester, container);

    expect(issueKeys, isEmpty);

    // 手動取得は引き続き利用できる。
    expect(
      tester.widget<OutlinedButton>(issueButtonFinder).onPressed,
      isNotNull,
    );

    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys, [keys.single]);

    issueRequests.single.complete(7);
    await tester.pumpAndSettle();
  });

  testWidgets('IA06: キャッシュがある場合は自動取得しない', (tester) async {
    final container = await start(tester, mode: IssueCountFetchMode.automatic);

    await open(tester);
    await completeDetail(tester, container);

    expect(issueKeys.length, 1);

    issueRequests.single.complete(15);
    await tester.pumpAndSettle();

    await back(tester);
    await open(tester);

    // 詳細情報は開き直すたびに取得する。
    expect(keys.length, 2);

    await completeDetail(tester, container);

    // Issue数は既存キャッシュを使用する。
    expect(issueKeys.length, 1);

    expect(find.text(detailL10n(tester).openIssueCount(15)), findsOneWidget);

    expect(
      tester.widget<OutlinedButton>(issueButtonFinder).onPressed,
      isNotNull,
    );
  });

  testWidgets('IA07: Issue取得失敗後の再描画で自動再試行しない', (tester) async {
    final container = await start(tester, mode: IssueCountFetchMode.automatic);

    await open(tester);
    await completeDetail(tester, container);

    expect(issueKeys.length, 1);

    issueRequests.single.completeError(StateError('Test issue failure'));

    await tester.pump();
    await tester.pump();

    expect(find.text(detailL10n(tester).unexpectedIssueError), findsOneWidget);

    // 言語変更による再描画。
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // テーマ変更による再描画。
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(issueKeys.length, 1);
    expect(keys.length, 1);

    expect(find.text(detailL10n(tester).unexpectedIssueError), findsOneWidget);

    // 詳細情報は失わない。
    expect(find.text(detailL10n(tester).watcherCount(8)), findsOneWidget);

    // 利用者による再試行は許可する。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys.length, 2);

    issueRequests.last.complete(9);
    await tester.pumpAndSettle();

    expect(find.text(detailL10n(tester).openIssueCount(9)), findsOneWidget);
  });

  testWidgets('IA08: 手動取得後は設定読み込みが完了しても重複取得しない', (tester) async {
    final gate = Completer<void>();

    final container = await start(
      tester,
      mode: IssueCountFetchMode.automatic,
      modeReadGate: gate.future,
    );

    await open(tester);
    await completeDetail(tester, container);

    expect(issueKeys, isEmpty);

    // 設定読み込み中に利用者が手動取得する。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys.length, 1);

    // 手動取得が失敗した場合でも勝手に再取得しない。
    issueRequests.single.completeError(StateError('Test issue failure'));

    await tester.pump();

    gate.complete();

    await tester.pump();
    await tester.pump();

    expect(issueKeys.length, 1);

    expect(find.text(detailL10n(tester).unexpectedIssueError), findsOneWidget);

    expect(
      tester.widget<OutlinedButton>(issueButtonFinder).onPressed,
      isNotNull,
    );
  });

  testWidgets('IA09: 詳細取得の再試行成功後にIssue数を自動取得する', (tester) async {
    final container = await start(tester, mode: IssueCountFetchMode.automatic);

    await open(tester);

    requests.single.completeError(StateError('Test detail failure'));

    await tester.pump();
    await tester.pump();

    expect(issueKeys, isEmpty);

    final retry = find.byKey(const Key('retry-repository-detail'));

    expect(retry, findsOneWidget);

    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();

    expect(keys.length, 2);
    expect(issueKeys, isEmpty);

    await completeDetail(tester, container);

    expect(issueKeys, [keys.last]);

    issueRequests.single.complete(10);
    await tester.pumpAndSettle();

    expect(find.text(detailL10n(tester).openIssueCount(10)), findsOneWidget);
  });

  testWidgets('IA10: 画面離脱後の自動取得結果をキャッシュしない', (tester) async {
    final container = await start(tester, mode: IssueCountFetchMode.automatic);

    await open(tester);
    await completeDetail(tester, container);

    expect(issueKeys.length, 1);

    final key = keys.single;

    // Issue取得が完了していない状態で画面を閉じる。
    await back(tester);

    issueRequests.single.complete(99);

    await tester.pump();
    await tester.pump();

    expect(container.read(openIssueCountCacheProvider).get(key), isNull);
  });

  testWidgets('IR01: 自動モードでは詳細更新時にIssue数も再取得する', (tester) async {
    final container = await openWithIssueCountForRefresh(tester);

    final key = keys.single;

    await tapDetailRefresh(tester);

    expect(keys.length, 2);

    // 詳細取得が完了するまではIssue数を再取得しない。
    expect(issueKeys.length, 1);

    await completeDetail(tester, container);

    // キャッシュがあっても明示的な詳細更新では再取得する。
    expect(issueKeys, [key, key]);

    expect(find.text(detailL10n(tester).openIssuesLoading), findsOneWidget);

    issueRequests.last.complete(25);
    await tester.pumpAndSettle();

    expect(find.text(detailL10n(tester).openIssueCount(25)), findsOneWidget);

    expect(container.read(openIssueCountCacheProvider).get(key)?.count, 25);

    expect(keys.length, 2);
    expect(issueKeys.length, 2);
  });

  testWidgets('IR02: 手動モードでは詳細更新時にIssue数を再取得しない', (tester) async {
    final container = await openWithIssueCountForRefresh(
      tester,
      mode: IssueCountFetchMode.manual,
    );

    final key = keys.single;
    final cache = container.read(openIssueCountCacheProvider);
    final previous = cache.get(key)!;

    await tapDetailRefresh(tester);

    expect(keys.length, 2);
    expect(issueKeys.length, 1);

    await completeDetail(tester, container);
    await tester.pumpAndSettle();

    expect(issueKeys.length, 1);

    expect(find.text(detailL10n(tester).openIssueCount(15)), findsOneWidget);

    // 取得日時も含めて以前のキャッシュを維持する。
    expect(cache.get(key), same(previous));

    // 手動での再取得は引き続き可能。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys.length, 2);

    issueRequests.last.complete(20);
    await tester.pumpAndSettle();

    expect(cache.get(key)?.count, 20);
  });

  testWidgets('IR03: 詳細更新失敗後の再試行成功時にIssue数を取得する', (tester) async {
    final container = await openWithIssueCountForRefresh(tester);

    final key = keys.single;
    final cache = container.read(openIssueCountCacheProvider);
    final previous = cache.get(key)!;

    await tapDetailRefresh(tester);

    expect(keys.length, 2);

    requests.last.completeError(StateError('Test detail refresh failure'));

    await tester.pumpAndSettle();

    // 詳細更新が失敗した場合はIssue数を取得しない。
    expect(issueKeys.length, 1);
    expect(cache.get(key), same(previous));

    final retry = find.byKey(const Key('retry-repository-detail'));

    expect(retry, findsOneWidget);

    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();

    expect(keys.length, 3);
    expect(issueKeys.length, 1);

    await completeDetail(tester, container);

    // 詳細取得が成功した後にIssue数を再取得する。
    expect(issueKeys.length, 2);

    issueRequests.last.complete(30);
    await tester.pumpAndSettle();

    expect(find.text(detailL10n(tester).openIssueCount(30)), findsOneWidget);

    expect(cache.get(key)?.count, 30);
  });

  testWidgets('IR04: Issue再取得失敗時は以前の件数と取得日時を維持する', (tester) async {
    final container = await openWithIssueCountForRefresh(tester);

    final key = keys.single;
    final cache = container.read(openIssueCountCacheProvider);
    final previous = cache.get(key)!;

    final l10n = detailL10n(tester);

    final previousTimeLabel = l10n.issueFetchedAt(
      formatDeviceDateTime(previous.fetchedAt, localeName: l10n.localeName),
    );

    expect(find.text(previousTimeLabel), findsOneWidget);

    await tapDetailRefresh(tester);
    await completeDetail(tester, container);

    expect(issueKeys.length, 2);

    issueRequests.last.completeError(StateError('Test issue refresh failure'));

    await tester.pumpAndSettle();

    // 以前の取得結果と取得日時を維持する。
    expect(cache.get(key), same(previous));

    expect(find.text(detailL10n(tester).openIssueCount(15)), findsOneWidget);

    expect(find.text(previousTimeLabel), findsOneWidget);

    expect(find.text(detailL10n(tester).unexpectedIssueError), findsOneWidget);

    // 詳細情報も失わない。
    expect(find.text(detailL10n(tester).watcherCount(8)), findsOneWidget);

    // 自動再試行は行わない。
    await tester.pump(const Duration(seconds: 1));

    expect(issueKeys.length, 2);

    // 利用者による再試行は可能。
    await tester.ensureVisible(issueButtonFinder);
    await tester.tap(issueButtonFinder);
    await tester.pump();

    expect(issueKeys.length, 3);

    issueRequests.last.complete(35);
    await tester.pumpAndSettle();

    expect(cache.get(key)?.count, 35);

    expect(find.text(detailL10n(tester).unexpectedIssueError), findsNothing);
  });

  testWidgets('IR05: 再描画前の詳細更新とIssue取得の競合を防ぐ', (tester) async {
    final container = await openWithIssueCountForRefresh(tester);

    final refreshAction = tester
        .widget<OutlinedButton>(refreshButtonFinder)
        .onPressed!;

    final issueAction = tester
        .widget<OutlinedButton>(issueButtonFinder)
        .onPressed!;

    // 再描画を挟まず連続実行する。
    refreshAction();
    issueAction();

    await tester.pump();

    expect(keys.length, 2);

    // 直後の手動Issue取得は拒否される。
    expect(issueKeys.length, 1);

    await completeDetail(tester, container);

    // 詳細更新成功後に自動取得だけが開始される。
    expect(issueKeys.length, 2);

    issueRequests.last.complete(40);
    await tester.pumpAndSettle();

    expect(keys.length, 2);
    expect(issueKeys.length, 2);

    expect(find.text(detailL10n(tester).openIssueCount(40)), findsOneWidget);
  });

  testWidgets('IR06: 再描画前のIssue取得と詳細更新の競合を防ぐ', (tester) async {
    await openWithIssueCountForRefresh(tester);

    final refreshAction = tester
        .widget<OutlinedButton>(refreshButtonFinder)
        .onPressed!;

    final issueAction = tester
        .widget<OutlinedButton>(issueButtonFinder)
        .onPressed!;

    // 反対の順序でも再描画を挟まず連続実行する。
    issueAction();
    refreshAction();

    await tester.pump();

    expect(issueKeys.length, 2);

    // 詳細更新は開始されない。
    expect(keys.length, 1);

    expect(
      tester.widget<OutlinedButton>(refreshButtonFinder).onPressed,
      isNull,
    );

    issueRequests.last.complete(45);
    await tester.pumpAndSettle();

    expect(keys.length, 1);
    expect(issueKeys.length, 2);

    expect(find.text(detailL10n(tester).openIssueCount(45)), findsOneWidget);

    // Issue取得完了後は両方の操作を再び許可する。
    expect(
      tester.widget<OutlinedButton>(refreshButtonFinder).onPressed,
      isNotNull,
    );

    expect(
      tester.widget<OutlinedButton>(issueButtonFinder).onPressed,
      isNotNull,
    );
  });

  testWidgets('IR07: 詳細更新中の画面離脱後はIssue数を自動取得しない', (tester) async {
    final container = await openWithIssueCountForRefresh(tester);

    final key = keys.single;
    final cache = container.read(openIssueCountCacheProvider);
    final previous = cache.get(key)!;

    await tapDetailRefresh(tester);

    expect(keys.length, 2);
    expect(issueKeys.length, 1);

    // 詳細更新が完了する前に画面から離脱する。
    await back(tester);

    expect(find.byType(RepositoryDetailScreen), findsNothing);

    // 画面離脱後に詳細取得の結果が返る。
    await completeDetail(tester, container);
    await tester.pumpAndSettle();

    // 後続の自動Issue取得は開始されない。
    expect(issueKeys.length, 1);

    // 既存キャッシュにも影響を与えない。
    expect(cache.get(key), same(previous));
  });
}

class _IssueViaHttpGateway extends FakeGitHubRepositoryGateway {
  _IssueViaHttpGateway(this.httpGateway)
    : super(
        delay: Duration.zero,
        searchHandler: (query, {required page, required perPage}) async =>
            resultPage(count: 1),
        detailHandler: (key) async => RepositoryDetail(
          summary: resultPage(count: 1).items.first,
          watcherCount: 8,
        ),
      );

  final HttpGitHubRepositoryGateway httpGateway;

  @override
  Future<int> getOpenIssueCount(
    RepositoryKey key, {
    bool Function()? isCanceled,
  }) {
    return httpGateway.getOpenIssueCount(key, isCanceled: isCanceled);
  }
}
