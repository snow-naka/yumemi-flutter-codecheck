import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'api_diagnostics.dart';
import '../l10n/localized_date_time.dart';

class ApiDiagnosticsScreen extends ConsumerWidget {
  const ApiDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatDecimal = MaterialLocalizations.of(context).formatDecimal;

    String formatNullableCount(int? value) =>
        value == null ? '-' : formatDecimal(value);

    if (!kDebugMode) {
      return Scaffold(body: Center(child: Text(l10n.diagnosticDebugOnly)));
    }

    final store = ref.watch(apiDiagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.apiDiagnosticsTitle),
        actions: [
          IconButton(
            key: const Key('clear-api-diagnostics'),
            tooltip: l10n.diagnosticClearHistory,
            icon: const Icon(Icons.delete_outline),
            onPressed: store.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<ApiDiagnosticEvent>>(
        valueListenable: store,
        builder: (context, events, child) {
          if (events.isEmpty) {
            return Center(child: Text(l10n.diagnosticEmptyHistory));
          }

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              // 新しい通信を上に表示する。
              final event = events[events.length - 1 - index];

              final status = event.httpStatus == null
                  ? _outcomeLabel(l10n, event.outcome)
                  : 'HTTP ${event.httpStatus}';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ExpansionTile(
                  title: Text(
                    l10n.diagnosticEventTitle(
                      _operationLabel(l10n, event.operation),
                      status,
                    ),
                  ),
                  subtitle: Text(
                    l10n.diagnosticRecordedAt(
                      _dateTime(l10n, event.recordedAt),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow(
                            l10n.diagnosticResult,
                            _outcomeLabel(l10n, event.outcome),
                          ),
                          _detailRow(
                            l10n.diagnosticRemainingLimit,
                            '${formatNullableCount(event.rateLimitRemaining)}'
                            ' / ${formatNullableCount(event.rateLimitLimit)}',
                          ),
                          _detailRow(
                            'GitHub Reset',
                            _dateTime(l10n, event.rateLimitResetAt),
                          ),
                          _detailRow(
                            'Retry-After',
                            event.retryAfter == null
                                ? l10n.diagnosticNotReported
                                : l10n.diagnosticRetryAfterSeconds(
                                    event.retryAfter!.inSeconds,
                                  ),
                          ),
                          _detailRow(
                            l10n.diagnosticPolicyRetryAt,
                            (event.outcome ==
                                            ApiDiagnosticOutcome
                                                .blockedByRateLimit ||
                                        event.outcome ==
                                            ApiDiagnosticOutcome
                                                .policyBlockedAfterResponse) &&
                                    event.policyRetryAt == null
                                ? l10n.diagnosticUnknownRetryAt
                                : _dateTime(l10n, event.policyRetryAt),
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

  static String _operationLabel(
    AppLocalizations l10n,
    ApiDiagnosticOperation operation,
  ) {
    return switch (operation) {
      ApiDiagnosticOperation.search => l10n.search,
      ApiDiagnosticOperation.detail => l10n.diagnosticDetailOperation,
    };
  }

  static String _outcomeLabel(
    AppLocalizations l10n,
    ApiDiagnosticOutcome outcome,
  ) {
    return switch (outcome) {
      ApiDiagnosticOutcome.policyBlockedAfterResponse =>
        l10n.diagnosticPolicyBlockedAfterResponse,

      ApiDiagnosticOutcome.response => l10n.diagnosticResponse,

      ApiDiagnosticOutcome.blockedByRateLimit =>
        l10n.diagnosticBlockedByRateLimit,

      ApiDiagnosticOutcome.canceledBeforeSend =>
        l10n.diagnosticCanceledBeforeSend,

      ApiDiagnosticOutcome.timeout => l10n.diagnosticTimeout,

      ApiDiagnosticOutcome.networkFailure => l10n.diagnosticNetworkFailure,
    };
  }

  static String _dateTime(AppLocalizations l10n, DateTime? value) {
    if (value == null) return l10n.diagnosticNotRecorded;

    return l10n.diagnosticDeviceTime(
      formatDeviceDateTime(
        value,
        localeName: l10n.localeName,
        includeSeconds: true,
      ),
    );
  }
}
