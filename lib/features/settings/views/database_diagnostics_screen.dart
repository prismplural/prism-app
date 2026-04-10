import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/database_health_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/database_diagnostics_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Advanced diagnostics screen for inspecting database state.
class DatabaseDiagnosticsScreen extends ConsumerWidget {
  const DatabaseDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nodeIdAsync = ref.watch(nodeIdProvider);
    final hlcAsync = ref.watch(crdtLatestHlcProvider);
    final dbPathAsync = ref.watch(dbPathProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Database Diagnostics',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          // ── Record Counts ──────────────────────────
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Record Counts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _CountRow(
                  label: 'Members',
                  countAsync: ref.watch(memberCountProvider),
                ),
                const Divider(height: 16),
                _CountRow(
                  label: 'Fronting Sessions',
                  countAsync: ref.watch(sessionCountProvider),
                ),
                const Divider(height: 16),
                _CountRow(
                  label: 'Conversations',
                  countAsync: ref.watch(conversationCountProvider),
                ),
                const Divider(height: 16),
                _CountRow(
                  label: 'Polls',
                  countAsync: ref.watch(pollCountProvider),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── CRDT / Sync Info ───────────────────────
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync Internals',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Node ID',
                  valueAsync: nodeIdAsync.whenData(
                    (v) => v ?? 'Unavailable — not yet paired',
                  ),
                  copyable: true,
                ),
                const Divider(height: 16),
                _InfoRow(
                  label: 'Latest HLC',
                  valueAsync: hlcAsync.whenData(
                    (v) => v ?? 'No changes recorded',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Database Path ──────────────────────────
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Database File',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                dbPathAsync.when(
                  loading: () => const PrismLoadingState(),
                  error: (e, _) => Text('Error: $e'),
                  data: (path) => SelectableText(
                    path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Integrity Check ────────────────────────
          Center(
            child: PrismButton(
              label: 'Check Integrity',
              icon: AppIcons.verifiedOutlined,
              tone: PrismButtonTone.filled,
              onPressed: () {
                ref.invalidate(healthReportProvider);
                PrismDialog.show(
                  context: context,
                  title: 'Integrity Check',
                  builder: (_) => const _HealthReportDialogContent(),
                  actions: [
                    PrismButton(
                      onPressed: () => Navigator.of(context).pop(),
                      label: 'Close',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.countAsync});

  final String label;
  final AsyncValue<int> countAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        countAsync.when(
          loading: () => const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, _) => Text(
            'Error',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          data: (count) => Text(
            '$count',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthReportDialogContent extends ConsumerWidget {
  const _HealthReportDialogContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(healthReportProvider);

    return SizedBox(
      width: double.maxFinite,
      child: reportAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: PrismLoadingState(),
        ),
        error: (e, _) => Text('Error running check: $e'),
        data: (report) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    report.isHealthy
                        ? AppIcons.checkCircle
                        : AppIcons.warningAmber,
                    color: report.isHealthy ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    report.isHealthy ? 'Database OK' : 'Issues Found',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Records: ${_formatCounts(report.recordCounts)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (report.issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                ...report.issues.map(
                  (issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          AppIcons.errorOutline,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            issue,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatCounts(Map<String, int> counts) {
    final main = <String>[];
    if (counts.containsKey('members')) {
      main.add('${counts['members']} members');
    }
    if (counts.containsKey('sessions')) {
      main.add('${counts['sessions']} sessions');
    }
    if (counts.containsKey('conversations')) {
      main.add('${counts['conversations']} conversations');
    }
    if (counts.containsKey('messages')) {
      main.add('${counts['messages']} messages');
    }
    return main.join(', ');
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.valueAsync,
    this.copyable = false,
  });

  final String label;
  final AsyncValue<String> valueAsync;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        valueAsync.when(
          loading: () => const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (value) => Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (copyable)
                PrismInlineIconButton(
                  icon: AppIcons.copy,
                  iconSize: 18,
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    PrismToast.show(context, message: 'Copied to clipboard');
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
