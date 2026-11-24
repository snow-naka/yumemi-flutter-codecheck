import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'issue_count_fetch_mode_provider.dart';
import 'issue_count_fetch_preferences.dart';

class IssueCountFetchModeMenu extends ConsumerWidget {
  const IssueCountFetchModeMenu({super.key});

  Future<void> _changeMode(
    BuildContext context,
    WidgetRef ref,
    IssueCountFetchMode mode,
  ) async {
    final saved = await ref
        .read(issueCountFetchModeProvider.notifier)
        .changeMode(mode);

    if (!context.mounted || saved) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).issueCountFetchModeSaveFailed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(issueCountFetchModeProvider);
    final current = state.asData?.value;

    final isSaving = current?.isSaving ?? false;
    final readFailed = current?.readFailed ?? false;

    final enabled = !state.isLoading && current != null && !isSaving;

    final tooltip = state.isLoading
        ? l10n.issueCountFetchModeLoading
        : isSaving
        ? l10n.issueCountFetchModeSaving
        : readFailed
        ? '${l10n.issueCountFetchMode}\n'
              '${l10n.issueCountFetchModeReadFailed}'
        : l10n.issueCountFetchMode;

    return PopupMenuButton<IssueCountFetchMode>(
      key: const Key('issue-count-fetch-mode-menu'),
      tooltip: tooltip,
      enabled: enabled,
      icon: Icon(readFailed ? Icons.warning_amber_rounded : Icons.sync),
      onSelected: (mode) {
        unawaited(_changeMode(context, ref, mode));
      },
      itemBuilder: (_) => [
        PopupMenuItem<IssueCountFetchMode>(
          enabled: false,
          child: Text(l10n.issueCountFetchMode),
        ),
        if (readFailed)
          PopupMenuItem<IssueCountFetchMode>(
            enabled: false,
            child: Text(l10n.issueCountFetchModeReadFailed),
          ),
        CheckedPopupMenuItem<IssueCountFetchMode>(
          key: const Key('issue-fetch-mode-automatic'),
          value: IssueCountFetchMode.automatic,
          checked: current?.mode == IssueCountFetchMode.automatic,
          child: Text(l10n.issueCountFetchModeAutomatic),
        ),
        CheckedPopupMenuItem<IssueCountFetchMode>(
          key: const Key('issue-fetch-mode-manual'),
          value: IssueCountFetchMode.manual,
          checked: current?.mode == IssueCountFetchMode.manual,
          child: Text(l10n.issueCountFetchModeManual),
        ),
      ],
    );
  }
}
