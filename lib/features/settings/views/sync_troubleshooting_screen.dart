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
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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
        ? context.l10n.syncTroubleshootingNotConfigured
        : hasActiveHandle
        ? context.l10n.syncTroubleshootingConnected
        : context.l10n.syncTroubleshootingConfiguredLocally;
    final connectionSubtitle = !isConfigured
        ? context.l10n.syncTroubleshootingNotConfiguredSubtitle
        : hasActiveHandle
        ? context.l10n.syncTroubleshootingConnectedSubtitle
        : context.l10n.syncTroubleshootingConfiguredLocallySubtitle;

    final canSyncNow = isConfigured && hasActiveHandle && !syncStatus.isSyncing;
    VoidCallback? syncNowCallback;
    if (canSyncNow) {
      final h = handle;
      syncNowCallback = () => _syncNow(ref, context, h);
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.syncTroubleshootingTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: SyncToastListener(
        child: ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            // -- Connection Status --
            _SectionHeader(title: context.l10n.syncTroubleshootingConnectionStatus),
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
            _SectionHeader(title: context.l10n.syncTroubleshootingLastSync),
            PrismListRow(
              leading: Icon(AppIcons.schedule),
              title: Text(context.l10n.syncTroubleshootingLastSuccessful),
              subtitle: Text(
                syncStatus.lastSyncAt != null
                    ? _formatDateTime(syncStatus.lastSyncAt!)
                    : context.l10n.syncTroubleshootingNeverSynced,
              ),
            ),

            // -- Last Error --
            if (syncStatus.lastError != null) ...[
              PrismListRow(
                leading: Icon(
                  AppIcons.errorOutline,
                  color: theme.colorScheme.error,
                ),
                title: Text(context.l10n.syncTroubleshootingLastError),
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
            PrismListRow(
              leading: Icon(AppIcons.infoOutline),
              title: Text(context.l10n.syncTroubleshootingCurrentState),
              subtitle: Text(syncStatus.isSyncing ? context.l10n.syncTroubleshootingSyncing : context.l10n.syncTroubleshootingIdle),
            ),
            if (syncStatus.pendingOps > 0)
              PrismListRow(
                leading: Icon(AppIcons.pendingOutlined),
                title: Text(context.l10n.syncTroubleshootingPendingOps),
                subtitle: Text(context.l10n.syncTroubleshootingPendingOpsValue(syncStatus.pendingOps)),
              ),
            if (syncId != null && syncId.isNotEmpty)
              PrismListRow(
                leading: Icon(AppIcons.tag),
                title: Text(context.l10n.syncTroubleshootingSyncId),
                subtitle: Text(
                  syncId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            if (relayUrl != null && relayUrl.isNotEmpty)
              PrismListRow(
                leading: Icon(AppIcons.link),
                title: Text(context.l10n.syncTroubleshootingRelayUrl),
                subtitle: Text(
                  relayUrl,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),

            const Divider(height: 32, indent: 16, endIndent: 16),

            // -- Actions --
            _SectionHeader(title: context.l10n.syncTroubleshootingActions),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: syncNowCallback ?? () {},
                enabled: syncNowCallback != null,
                icon: AppIcons.sync,
                label: context.l10n.syncTroubleshootingForceSync,
                tone: PrismButtonTone.filled,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => context.push(AppRoutePaths.settingsSyncDebug),
                icon: AppIcons.receiptLongOutlined,
                label: context.l10n.syncTroubleshootingOpenEventLog,
                tone: PrismButtonTone.outlined,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => _confirmReset(context, ref),
                enabled: isConfigured || hasActiveHandle,
                icon: AppIcons.restartAlt,
                label: context.l10n.syncTroubleshootingResetSync,
                tone: PrismButtonTone.destructive,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PrismButton(
                onPressed: () => _confirmRepair(context, ref),
                enabled: isConfigured || hasActiveHandle,
                icon: AppIcons.personOffOutlined,
                label: context.l10n.syncTroubleshootingRepair,
                tone: PrismButtonTone.destructive,
              ),
            ),
            const Divider(height: 32, indent: 16, endIndent: 16),

            // -- Common Issues --
            _SectionHeader(title: context.l10n.syncTroubleshootingCommonIssues),
            _TroubleshootingTile(
              icon: AppIcons.syncProblem,
              title: context.l10n.syncTroubleshootingIssue1Title,
              description: context.l10n.syncTroubleshootingIssue1Description,
            ),
            _TroubleshootingTile(
              icon: AppIcons.copyAll,
              title: context.l10n.syncTroubleshootingIssue2Title,
              description: context.l10n.syncTroubleshootingIssue2Description,
            ),
            _TroubleshootingTile(
              icon: AppIcons.wifiOff,
              title: context.l10n.syncTroubleshootingIssue3Title,
              description: context.l10n.syncTroubleshootingIssue3Description,
            ),
            _TroubleshootingTile(
              icon: AppIcons.speed,
              title: context.l10n.syncTroubleshootingIssue4Title,
              description: context.l10n.syncTroubleshootingIssue4Description,
            ),
            _TroubleshootingTile(
              icon: AppIcons.personOffOutlined,
              title: context.l10n.syncTroubleshootingIssue5Title,
              description: context.l10n.syncTroubleshootingIssue5Description,
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
        PrismToast.show(context, message: context.l10n.syncTroubleshootingFinished);
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: context.l10n.syncTroubleshootingFailed(e));
      }
    }
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    PrismDialog.confirm(
      context: context,
      title: context.l10n.syncTroubleshootingResetTitle,
      message: context.l10n.syncTroubleshootingResetMessage,
      confirmLabel: context.l10n.syncTroubleshootingResetConfirm,
      destructive: true,
    ).then((confirmed) async {
      if (!confirmed) return;
      await ref
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.sync);
      if (!context.mounted) return;
      PrismToast.show(context, message: context.l10n.syncTroubleshootingResetSuccess);
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
            title: context.l10n.syncTroubleshootingRepairTitle,
            message: context.l10n.syncTroubleshootingRepairMessage,
            actions: [
              PrismButton(
                label: context.l10n.cancel,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              PrismButton(
                label: context.l10n.syncTroubleshootingRepairNow,
                onPressed: () => Navigator.of(dialogContext).pop('repair'),
                tone: PrismButtonTone.destructive,
              ),
              PrismButton(
                label: context.l10n.syncTroubleshootingExportFirst,
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
      PrismToast.show(context, message: context.l10n.syncTroubleshootingCredentialsCleared);
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
