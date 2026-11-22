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

import '../search/search_test_support.dart';

void main() {
  late List<String> searches;
  late List<RepositoryKey> keys;
  late List<Completer<RepositoryDetail>> requests;
  late FakeGitHubRepositoryGateway fake;
  late List<RepositoryKey> issueKeys;
  late List<Completer<int>> issueRequests;

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

  Future<ProviderContainer> start(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
        child: const MyApp(),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'submitted');
    await tester.tap(find.widgetWithText(FilledButton, '検索'));
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
    await tester.pageBack();
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
        ],
        child: MaterialApp(home: RepositoryDetailScreen(summary: summary)),
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
        const ApiFailure(kind: ApiFailureKind.network, safeMessage: '仮の詳細取得失敗'),
      );
      await tester.pump();
      expect(find.text('仮の詳細取得失敗'), findsOneWidget);
      expect(find.text('repository-0'), findsOneWidget);
      expect(find.textContaining('Watcher数：'), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(keys, hasLength(1));
      expect(container.read(searchControllerProvider), same(searchState));
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(keys, hasLength(2));
      expect(find.text('詳細情報を取得中…'), findsOneWidget);
      expect(find.text('仮の詳細取得失敗'), findsNothing);
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
        const ApiFailure(
          kind: ApiFailureKind.network,
          safeMessage: 'detail failed',
        ),
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

  testWidgets('closing a successful detail clears its cache before reopening', (
    tester,
  ) async {
    final container = await start(tester);
    final summary =
        (container.read(searchControllerProvider) as SearchResults).items.first;
    await open(tester);
    requests.single.complete(
      RepositoryDetail(summary: summary, watcherCount: 8),
    );
    await tester.pump();
    await back(tester);
    expect(
      container.read(repositoryDetailProvider(summary.key).exists),
      isFalse,
    );
    await open(tester);
    expect(keys, hasLength(2));
    expect(find.textContaining('Watcher数：'), findsNothing);
    requests.last.complete(RepositoryDetail(summary: summary, watcherCount: 9));
    await tester.pump();
    expect(find.text('Watcher数：9'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(FilledButton, '検索'));
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

    final button = find.widgetWithText(OutlinedButton, 'Issue数を取得（検索APIを1回使用）');

    // 連続して押しても要求は1回だけ。
    await tester.tap(button);
    await tester.tap(button);
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

    await tester.tap(find.text('Issue数を取得（検索APIを1回使用）'));
    await tester.pump();

    issueRequests.single.completeError(
      const ApiFailure(
        kind: ApiFailureKind.rateLimited,
        safeMessage: 'テスト用の送信待機エラー',
      ),
    );
    await tester.pump();

    expect(find.text('テスト用の送信待機エラー'), findsOneWidget);

    expect(find.text('Watcher数：8'), findsOneWidget);

    // 自動再試行は行わない。
    expect(issueKeys, hasLength(1));

    // 利用者が明示的に再試行する。
    await tester.tap(find.text('Issue数を再試行（検索APIを1回使用）'));
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubRepositoryGatewayProvider.overrideWithValue(gateway)],
        child: const MyApp(),
      ),
    );

    // 1. Fakeで検索・詳細画面を表示する。
    await tester.enterText(find.byType(TextFormField), 'submitted');
    await tester.tap(find.widgetWithText(FilledButton, '検索'));
    await tester.pump();

    await tester.tap(find.text('repository-0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Issue数を取得（検索APIを1回使用）'), findsOneWidget);

    // 2. 別のHTTP検索でGatewayのキューを塞ぐ。
    final holdingSearch = httpGateway.searchRepositories('queue-holder');

    await tester.pump();

    expect(sentPaths, ['/search/repositories']);

    // 3. Issue検索を要求する。まだ送信はできない。
    await tester.tap(find.text('Issue数を取得（検索APIを1回使用）'));
    await tester.pump();

    expect(sentPaths, ['/search/repositories']);

    // 4. 詳細画面から戻る。
    await tester.pageBack();
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
