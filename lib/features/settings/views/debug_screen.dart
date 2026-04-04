import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Placeholder — pending changes count (sync now managed by Rust layer).
final _pendingChangesCountProvider = FutureProvider<int>((ref) async {
  return 0;
});

/// Developer-oriented debug screen with database reset, sync info, and
/// build details.
class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nodeIdAsync = ref.watch(nodeIdProvider);
    final pendingAsync = ref.watch(_pendingChangesCountProvider);
    final lastSyncTime = ref.watch(lastSyncTimeProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Debug', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          // ── Danger Zone ─────────────────────────────
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Danger Zone',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        AppIcons.deleteForever,
                        color: theme.colorScheme.error,
                      ),
                      label: Text(
                        'Reset Database',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.error),
                      ),
                      onPressed: () => _confirmReset(context, ref),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(AppIcons.fileUploadOutlined),
                      label: const Text('Export Data'),
                      onPressed: () {
                        PrismToast.show(context, message: 'Coming soon');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── CRDT Sync State ─────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sync State',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DebugRow(
                    label: 'Pending changes',
                    value: pendingAsync.when(
                      loading: () => '...',
                      error: (e, _) => 'Error',
                      data: (count) => '$count',
                    ),
                  ),
                  const Divider(height: 16),
                  _DebugRow(
                    label: 'Last sync',
                    value: lastSyncTime != null
                        ? _formatDateTime(lastSyncTime)
                        : 'Never',
                  ),
                  const Divider(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(AppIcons.receiptLongOutlined),
                      label: const Text('Open Sync Debug Log'),
                      onPressed: () =>
                          context.push(AppRoutePaths.settingsSyncDebug),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Build Info ──────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Build Info',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _DebugRow(label: 'App version', value: '0.1.0'),
                  const Divider(height: 16),
                  const _DebugRow(label: 'Package', value: 'prism_plurality'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Tools ────────────────────────────────────
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Tools',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PrismListRow(
                  leading: Icon(AppIcons.healing),
                  title: const Text('Timeline Sanitization'),
                  subtitle: const Text('Scan for and fix timeline issues'),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () => context.push(
                    AppRoutePaths.settingsTimelineSanitization,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Node ID ─────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  nodeIdAsync.when(
                    loading: () => const PrismLoadingState(),
                    error: (e, _) => Text('Error: $e'),
                    data: (nodeId) {
                      final displayId =
                          nodeId ?? 'Unavailable — not yet paired';
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Node ID',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  displayId,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (nodeId != null)
                            IconButton(
                              icon: Icon(AppIcons.copy, size: 18),
                              tooltip: 'Copy Node ID',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: nodeId),
                                );
                                PrismToast.show(
                                  context,
                                  message: 'Node ID copied to clipboard',
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    // First confirmation.
    final first = await PrismDialog.confirm(
      context: context,
      title: 'Reset Database',
      message:
          'Are you sure you want to delete all data? '
          'This action cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
    );

    if (!first || !context.mounted) return;

    // Second confirmation.
    final second = await PrismDialog.confirm(
      context: context,
      title: 'Really delete all data?',
      message:
          'This will permanently erase all members, sessions, '
          'conversations, messages, and polls. There is no undo.',
      confirmLabel: 'Delete Everything',
      destructive: true,
    );

    if (!second || !context.mounted) return;

    try {
      await ref
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.all);
      if (!context.mounted) return;
      PrismToast.show(context, message: 'Database reset successfully');
    } catch (e) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Failed to reset: $e');
    }
  }
}

class _DebugRow extends StatelessWidget {
  const _DebugRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
