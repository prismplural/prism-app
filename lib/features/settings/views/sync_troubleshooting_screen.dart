import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/shared/theme/app_icons.dart';

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
        ? AppIcons.cloudOffOutlined
        : hasActiveHandle
        ? AppIcons.cloudDoneOutlined
        : AppIcons.cloudSyncOutlined;
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
    if (canSyncNow) {
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
              leading: Icon(AppIcons.schedule),
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
                  AppIcons.errorOutline,
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
                          AppIcons.warningAmberRounded,
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
              leading: Icon(AppIcons.infoOutline),
              title: const Text('Current sync state'),
              subtitle: Text(syncStatus.isSyncing ? 'Syncing…' : 'Idle'),
            ),
            if (syncStatus.pendingOps > 0)
              ListTile(
                leading: Icon(AppIcons.pendingOutlined),
                title: const Text('Pending operations'),
                subtitle: Text('${syncStatus.pendingOps} ops waiting to sync'),
              ),
            if (syncId != null && syncId.isNotEmpty)
              ListTile(
                leading: Icon(AppIcons.tag),
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
                leading: Icon(AppIcons.link),
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
                icon: AppIcons.sync,
                label: 'Force Sync',
                tone: PrismButtonTone.filled,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => context.push(AppRoutePaths.settingsSyncDebug),
                icon: AppIcons.receiptLongOutlined,
                label: 'Open Sync Event Log',
                tone: PrismButtonTone.outlined,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => _confirmReset(context, ref),
                enabled: isConfigured || hasActiveHandle,
                icon: AppIcons.restartAlt,
                label: 'Reset Sync System',
                tone: PrismButtonTone.destructive,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => _confirmRepair(context, ref),
                enabled: isConfigured || hasActiveHandle,
                icon: AppIcons.personOffOutlined,
                label: 'Re-pair Device',
                tone: PrismButtonTone.destructive,
              ),
            ),
            const Divider(height: 32, indent: 16, endIndent: 16),

            // -- Common Issues --
            const _SectionHeader(title: 'Common Issues'),
            _TroubleshootingTile(
              icon: AppIcons.syncProblem,
              title: 'Sync not working?',
              description:
                  'Check that your relay URL and sync ID are correctly configured '
                  'in Sync settings. Both devices must use the same sync ID.',
            ),
            _TroubleshootingTile(
              icon: AppIcons.copyAll,
              title: 'Duplicate data?',
              description:
                  'Try resetting the sync system using the button above. This '
                  'wipes local sync setup and lets you pair again cleanly.',
            ),
            _TroubleshootingTile(
              icon: AppIcons.wifiOff,
              title: 'Connection errors?',
              description:
                  'Verify that your device has network access and that the relay '
                  'server is online. Check the relay URL for typos.',
            ),
            _TroubleshootingTile(
              icon: AppIcons.speed,
              title: 'Sync is slow?',
              description:
                  'Initial sync may take longer with large datasets. Subsequent '
                  'syncs are incremental and should be faster.',
            ),
            _TroubleshootingTile(
              icon: AppIcons.personOffOutlined,
              title: 'Device Identity Mismatch',
              description:
                  'If pairing failed mid-way, your device identity may be inconsistent. '
                  'Use "Re-pair Device" to generate a fresh identity and pair again.',
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
    PrismDialog.confirm(
      context: context,
      title: 'Reset sync system?',
      message:
          'This keeps your local app data, but wipes sync keys, relay '
          'configuration, device identity, and sync history from this device. '
          'You will need to set up sync again afterward.',
      confirmLabel: 'Reset',
      destructive: true,
    ).then((confirmed) async {
      if (!confirmed) return;
      await ref
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.sync);
      if (!context.mounted) return;
      PrismToast.show(context, message: 'Sync system reset');
    });
  }

  void _confirmRepair(BuildContext context, WidgetRef ref) {
    showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PrismTokens.radiusLarge),
          ),
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          child: PrismDialog(
            title: 'Re-pair Device?',
            message:
                'This will clear your sync credentials and require you to '
                'pair again. Any local changes not yet synced will be lost.\n\n'
                'We recommend exporting your data first as a safety net.',
            actions: [
              PrismButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              PrismButton(
                label: 'Re-pair Now',
                onPressed: () => Navigator.of(dialogContext).pop('repair'),
                tone: PrismButtonTone.destructive,
              ),
              PrismButton(
                label: 'Export Data First',
                onPressed: () => Navigator.of(dialogContext).pop('export'),
                tone: PrismButtonTone.filled,
              ),
            ],
            child: const SizedBox.shrink(),
          ),
        );
      },
    ).then((result) async {
      if (result == 'export') {
        if (!context.mounted) return;
        context.push(AppRoutePaths.settingsImportExport);
        return;
      }
      if (result != 'repair') return;
      await ref
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.sync);
      if (!context.mounted) return;
      PrismToast.show(context, message: 'Sync credentials cleared');
      context.go(AppRoutePaths.syncSetup);
    });
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
