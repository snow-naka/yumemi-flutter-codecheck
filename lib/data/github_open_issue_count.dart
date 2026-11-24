import 'dart:convert';

import '../models/api_failure.dart';
import '../models/repository_models.dart';

Uri buildOpenIssueCountUri(RepositoryKey key) {
  return Uri.https('api.github.com', '/search/issues', {
    'q': 'repo:${key.owner}/${key.name} is:issue is:open',
    'per_page': '1',
  });
}

int parseOpenIssueCount(List<int> bodyBytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bodyBytes));

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }

    final total = decoded['total_count'];
    final incomplete = decoded['incomplete_results'];
    final items = decoded['items'];

    // 件数が不確かなら、0件などと表示しない。
    if (total is! int ||
        total < 0 ||
        incomplete is! bool ||
        incomplete ||
        items is! List) {
      throw const FormatException('Invalid issue search result');
    }
    // per_page=1かつ最初のページを取得しているため、
    // total_count=0ならitemsは空、正数なら1件であることを要求。
    final expectedItems = total == 0 ? 0 : 1;

    if (items.length != expectedItems) {
      throw const FormatException('Inconsistent issue search result');
    }
    return total;
  } on FormatException {
    throw const ApiFailure(
      kind: ApiFailureKind.invalidResponse,
      reason: ApiFailureReason.issueCountUnverified,
    );
  }
}
