import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yumemi_app/data/github_open_issue_count.dart';
import 'package:yumemi_app/models/api_failure.dart';
import 'package:yumemi_app/models/repository_models.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';

void main() {
  test('IC01: PRを除くOpen Issue検索URLを生成する', () {
    const key = RepositoryKey(id: 1, owner: 'sample', name: 'example');

    final uri = buildOpenIssueCountUri(key);

    expect(uri.scheme, 'https');
    expect(uri.host, 'api.github.com');
    expect(uri.path, '/search/issues');
    expect(uri.queryParameters['q'], 'repo:sample/example is:issue is:open');
    expect(uri.queryParameters['per_page'], '1');
  });

  test('IC02: 検索結果からOpen Issue数を取得する', () {
    final body = utf8.encode(
      jsonEncode({
        'total_count': 12,
        'incomplete_results': false,
        'items': [
          {'number': 7},
        ],
      }),
    );

    expect(parseOpenIssueCount(body), 12);

    // 検索結果が0件の場合も正常な0として扱う。
    final empty = utf8.encode(
      jsonEncode({'total_count': 0, 'incomplete_results': false, 'items': []}),
    );

    expect(parseOpenIssueCount(empty), 0);
  });

  test('IC03: 不完全・不正な検索結果を件数として採用しない', () {
    final invalidBodies = [
      '{invalid',
      '{"total_count":12,"incomplete_results":true,"items":[]}',
      '{"total_count":"12","incomplete_results":false,"items":[]}',
      '{"total_count":-1,"incomplete_results":false,"items":[]}',
      '{"total_count":0,"incomplete_results":false}',
    ];

    for (final body in invalidBodies) {
      expect(
        () => parseOpenIssueCount(utf8.encode(body)),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
    }
  });

  test('IC04: Fakeは指定したIssue数を返す', () async {
    const key = RepositoryKey(id: 1, owner: 'sample', name: 'example');

    final calls = <RepositoryKey>[];

    final fake = FakeGitHubRepositoryGateway(
      openIssueCountHandler: (requestedKey) async {
        calls.add(requestedKey);
        return 7;
      },
    );

    // Gatewayを作成しただけでは取得しない。
    expect(calls, isEmpty);

    final count = await fake.getOpenIssueCount(key);

    expect(count, 7);
    expect(calls, [key]);
  });
}
