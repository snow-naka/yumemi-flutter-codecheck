import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'api_diagnostics.dart';

class ApiDiagnosticsScreen extends ConsumerWidget {
  const ApiDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('開発ビルド専用の画面です')));
    }

    final store = ref.watch(apiDiagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API通信インスペクター'),
        actions: [
          IconButton(
            key: const Key('clear-api-diagnostics'),
            tooltip: '履歴を消去',
            icon: const Icon(Icons.delete_outline),
            onPressed: store.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<ApiDiagnosticEvent>>(
        valueListenable: store,
        builder: (context, events, child) {
          if (events.isEmpty) {
            return const Center(child: Text('通信履歴はまだありません'));
          }

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              // 新しい通信を上に表示する。
              final event = events[events.length - 1 - index];

              final status = event.httpStatus == null
                  ? _outcomeLabel(event.outcome)
                  : 'HTTP ${event.httpStatus}';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ExpansionTile(
                  title: Text('${_operationLabel(event.operation)} / $status'),
                  subtitle: Text('記録：${_dateTime(event.recordedAt)}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow('結果', _outcomeLabel(event.outcome)),
                          _detailRow(
                            '残り / 上限',
                            '${event.rateLimitRemaining ?? "-"}'
                                ' / ${event.rateLimitLimit ?? "-"}',
                          ),
                          _detailRow(
                            'GitHub Reset',
                            _dateTime(event.rateLimitResetAt),
                          ),
                          _detailRow(
                            'Retry-After',
                            event.retryAfter == null
                                ? '未通知'
                                : '${event.retryAfter!.inSeconds}秒',
                          ),
                          _detailRow(
                            'アプリ側の再試行目安',
                            (event.outcome ==
                                            ApiDiagnosticOutcome
                                                .blockedByRateLimit ||
                                        event.outcome ==
                                            ApiDiagnosticOutcome
                                                .policyBlockedAfterResponse) &&
                                    event.policyRetryAt == null
                                ? '解除時刻不明（送信停止中）'
                                : _dateTime(event.policyRetryAt),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value),
        ],
      ),
    );
  }

  static String _operationLabel(ApiDiagnosticOperation operation) {
    return switch (operation) {
      ApiDiagnosticOperation.search => '検索',
      ApiDiagnosticOperation.detail => '詳細',
    };
  }

  static String _outcomeLabel(ApiDiagnosticOutcome outcome) {
    return switch (outcome) {
      ApiDiagnosticOutcome.policyBlockedAfterResponse => '応答後の送信制限',
      ApiDiagnosticOutcome.response => 'HTTP応答',
      ApiDiagnosticOutcome.blockedByRateLimit => '送信前に制限',
      ApiDiagnosticOutcome.canceledBeforeSend => '送信前キャンセル',
      ApiDiagnosticOutcome.timeout => 'タイムアウト',
      ApiDiagnosticOutcome.networkFailure => '通信失敗',
    };
  }

  static String _dateTime(DateTime? value) {
    if (value == null) return '未記録';

    final local = value.toLocal();

    String two(int n) => n.toString().padLeft(2, '0');

    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
        '（端末時刻）';
  }
}
