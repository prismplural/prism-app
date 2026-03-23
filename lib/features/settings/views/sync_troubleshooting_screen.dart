import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// Full screen for sync debugging and troubleshooting.
///
/// Shows connection status, last sync time, and sync status derived from
/// the FFI SyncStatus provider. Also displays a list of common issues
/// with suggested fixes.
class SyncTroubleshootingScreen extends ConsumerWidget {
  const SyncTroubleshootingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final relayUrl = ref.watch(relayUrlProvider).value;
    final syncId = ref.watch(syncIdProvider).value;
    final syncStatus = ref.watch(syncStatusProvider);
    final handleAsync = ref.watch(prismSyncHandleProvider);
    final handle = handleAsync.value;

    final isConfigured =
        relayUrl != null &&
        relayUrl.isNotEmpty &&
        syncId != null &&
        syncId.isNotEmpty;
    final hasActiveHandle = handle != null;

    final connectionColor = !isConfigured
        ? theme.colorScheme.outline
        : hasActiveHandle
        ? Colors.green
        : theme.colorScheme.primary;
    final connectionIcon = !isConfigured
        ? Icons.cloud_off_outlined
        : hasActiveHandle
        ? Icons.cloud_done_outlined
        : Icons.cloud_sync_outlined;
    final connectionTitle = !isConfigured
        ? 'Not configured'
        : hasActiveHandle
        ? 'Connected'
        : 'Configured locally';
    final connectionSubtitle = !isConfigured
        ? 'This device does not currently have sync set up.'
        : hasActiveHandle
        ? 'Sync engine is active and ready'
        : 'Settings are stored. The engine will reconnect on the next sync.';

    final canSyncNow = isConfigured && hasActiveHandle && !syncStatus.isSyncing;
    VoidCallback? syncNowCallback;
    if (canSyncNow && handle != null) { // ignore: unnecessary_null_comparison
      final h = handle;
      syncNowCallback = () => _syncNow(ref, context, h);
    }

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Sync Troubleshooting',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: SyncToastListener(
        child: ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            // -- Connection Status --
            const _SectionHeader(title: 'Connection Status'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(connectionIcon, size: 32, color: connectionColor),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connectionTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: connectionColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              connectionSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // -- Last Sync Time --
            const _SectionHeader(title: 'Last Sync'),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Last successful sync'),
              subtitle: Text(
                syncStatus.lastSyncAt != null
                    ? _formatDateTime(syncStatus.lastSyncAt!)
                    : 'Never synced',
              ),
            ),

            // -- Last Error --
            if (syncStatus.lastError != null) ...[
              ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: const Text('Last sync error'),
                subtitle: Text(syncStatus.lastError!),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            syncStatus.lastError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // -- Current State --
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Current sync state'),
              subtitle: Text(syncStatus.isSyncing ? 'Syncing…' : 'Idle'),
            ),
            if (syncStatus.pendingOps > 0)
              ListTile(
                leading: const Icon(Icons.pending_outlined),
                title: const Text('Pending operations'),
                subtitle: Text('${syncStatus.pendingOps} ops waiting to sync'),
              ),
            if (syncId != null && syncId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.tag),
                title: const Text('Sync ID'),
                subtitle: Text(
                  syncId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            if (relayUrl != null && relayUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Relay URL'),
                subtitle: Text(
                  relayUrl,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),

            const Divider(height: 32, indent: 16, endIndent: 16),

            // -- Actions --
            const _SectionHeader(title: 'Actions'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: syncNowCallback ?? () {},
                enabled: syncNowCallback != null,
                icon: Icons.sync,
                label: 'Force Sync',
                tone: PrismButtonTone.filled,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => context.push(AppRoutePaths.settingsSyncDebug),
                icon: Icons.receipt_long_outlined,
                label: 'Open Sync Event Log',
                tone: PrismButtonTone.outlined,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => _confirmReset(context, ref),
                enabled: isConfigured || hasActiveHandle,
                icon: Icons.restart_alt,
                label: 'Reset Sync System',
                tone: PrismButtonTone.destructive,
              ),
            ),
            const Divider(height: 32, indent: 16, endIndent: 16),

            // -- Common Issues --
            const _SectionHeader(title: 'Common Issues'),
            const _TroubleshootingTile(
              icon: Icons.sync_problem,
              title: 'Sync not working?',
              description:
                  'Check that your relay URL and sync ID are correctly configured '
                  'in Sync settings. Both devices must use the same sync ID.',
            ),
            const _TroubleshootingTile(
              icon: Icons.copy_all,
              title: 'Duplicate data?',
              description:
                  'Try resetting the sync system using the button above. This '
                  'wipes local sync setup and lets you pair again cleanly.',
            ),
            const _TroubleshootingTile(
              icon: Icons.wifi_off,
              title: 'Connection errors?',
              description:
                  'Verify that your device has network access and that the relay '
                  'server is online. Check the relay URL for typos.',
            ),
            const _TroubleshootingTile(
              icon: Icons.speed,
              title: 'Sync is slow?',
              description:
                  'Initial sync may take longer with large datasets. Subsequent '
                  'syncs are incremental and should be faster.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncNow(
    WidgetRef ref,
    BuildContext context,
    ffi.PrismSyncHandle handle,
  ) async {
    try {
      await ffi.syncNow(handle: handle);
      if (context.mounted) {
        PrismToast.show(context, message: 'Sync finished');
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: 'Sync failed: $e');
      }
    }
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset sync system?'),
        content: const Text(
          'This keeps your local app data, but wipes sync keys, relay '
          'configuration, device identity, and sync history from this device. '
          'You will need to set up sync again afterward.',
        ),
        actions: [
          PrismButton(
            onPressed: () => Navigator.of(ctx).pop(),
            label: 'Cancel',
            tone: PrismButtonTone.subtle,
          ),
          PrismButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref
                  .read(resetDataNotifierProvider.notifier)
                  .reset(ResetCategory.sync);
              if (!context.mounted) return;
              PrismToast.show(context, message: 'Sync system reset');
            },
            label: 'Reset',
            tone: PrismButtonTone.destructive,
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
    final dateStr =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';

    if (diff.inSeconds < 60) return 'Just now ($timeStr)';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago ($timeStr)';
    if (diff.inHours < 24) return '${diff.inHours}h ago ($timeStr)';
    return '$dateStr $timeStr';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TroubleshootingTile extends StatelessWidget {
  const _TroubleshootingTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
