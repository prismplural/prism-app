import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class _SyncEntityCounts {
  const _SyncEntityCounts({required this.total, required this.last24h});

  final int total;
  final int last24h;
}

final _syncEntityCountsProvider = FutureProvider.autoDispose<_SyncEntityCounts>(
  (ref) async {
    final db = ref.watch(databaseProvider);

    const tables = [
      'members',
      'fronting_sessions',
      'conversations',
      'chat_messages',
      'polls',
      'poll_options',
      'poll_votes',
      'habits',
      'habit_completions',
      'member_groups',
      'member_group_entries',
      'custom_fields',
      'custom_field_values',
      'notes',
      'front_session_comments',
      'conversation_categories',
      'reminders',
      'friends',
    ];

    const dateColumns = <String, String>{
      'members': 'created_at',
      'fronting_sessions': 'start_time',
      'conversations': 'created_at',
      'chat_messages': 'timestamp',
      'polls': 'created_at',
      'poll_votes': 'voted_at',
      'habits': 'created_at',
      'habit_completions': 'created_at',
      'member_groups': 'created_at',
      'custom_fields': 'created_at',
      'notes': 'created_at',
      'front_session_comments': 'created_at',
      'conversation_categories': 'created_at',
      'reminders': 'created_at',
      'friends': 'created_at',
    };

    final totalParts = tables.map(
      (table) => 'SELECT COUNT(*) AS c FROM $table WHERE is_deleted = 0',
    );
    final totalSql =
        'SELECT SUM(c) AS total FROM (${totalParts.join(' UNION ALL ')})';
    final totalResult = await db.customSelect(totalSql).getSingle();
    final total = totalResult.read<int>('total');

    final cutoffMs = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final cutoffSec = cutoffMs ~/ 1000;
    final recentParts = dateColumns.entries.map((entry) {
      final tableCutoff = entry.key == 'chat_messages' ? cutoffMs : cutoffSec;
      return 'SELECT COUNT(*) AS c FROM ${entry.key} '
          'WHERE is_deleted = 0 AND ${entry.value} >= $tableCutoff';
    });
    final recentSql =
        'SELECT SUM(c) AS total FROM (${recentParts.join(' UNION ALL ')})';
    final recentResult = await db.customSelect(recentSql).getSingle();
    final last24h = recentResult.read<int>('total');

    return _SyncEntityCounts(total: total, last24h: last24h);
  },
);

/// Advanced sync recovery and diagnostics screen.
class SyncTroubleshootingScreen extends ConsumerWidget {
  const SyncTroubleshootingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final relayUrl = ref.watch(relayUrlProvider).value;
    final syncId = ref.watch(syncIdProvider).value;
    final deviceId = ref.watch(syncDeviceIdProvider).value;
    final nodeId = ref.watch(nodeIdProvider).value;
    final hasDeviceSecret =
        ref.watch(syncDeviceSecretPresentProvider).value ?? false;
    final syncStatus = ref.watch(syncStatusProvider);
    final handleAsync = ref.watch(prismSyncHandleProvider);
    final handle = handleAsync.value;

    final isConfigured = hasCompletePersistentSyncIdentity(
      relayUrl: relayUrl,
      syncId: syncId,
      deviceId: deviceId,
      hasDeviceSecret: hasDeviceSecret,
    );
    final hasActiveHandle = handle != null;

    final canSyncNow = isConfigured && hasActiveHandle && !syncStatus.isSyncing;
    VoidCallback? syncNowCallback;
    if (canSyncNow) {
      final h = handle;
      syncNowCallback = () => _syncNow(ref, context, h);
    }
    final hasSupportInfo =
        (syncId != null && syncId.isNotEmpty) ||
        (relayUrl != null && relayUrl.isNotEmpty) ||
        (nodeId != null && nodeId.isNotEmpty);
    final hasAttentionItems =
        syncStatus.lastError != null || syncStatus.quarantinedBatchCount > 0;

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
            PrismSection(
              title: context.l10n.syncTroubleshootingActions,
              child: PrismGroupedSectionCard(
                child: Column(
                  children: _withRowDividers([
                    PrismSettingsRow(
                      icon: AppIcons.sync,
                      title: context.l10n.syncTroubleshootingForceSync,
                      subtitle:
                          context.l10n.syncTroubleshootingForceSyncSubtitle,
                      enabled: syncNowCallback != null,
                      showChevron: false,
                      onTap: syncNowCallback,
                    ),
                    PrismSettingsRow(
                      icon: AppIcons.restartAlt,
                      title: context.l10n.syncTroubleshootingResetSync,
                      subtitle:
                          context.l10n.syncTroubleshootingResetSyncSubtitle,
                      enabled: isConfigured || hasActiveHandle,
                      destructive: true,
                      showChevron: false,
                      onTap: () => _confirmReset(context, ref),
                    ),
                    PrismSettingsRow(
                      icon: AppIcons.helpOutline,
                      title: context.l10n.syncTroubleshootingTipsTitle,
                      subtitle: context.l10n.syncTroubleshootingTipsSubtitle,
                      onTap: () => context.push(
                        AppRoutePaths.settingsSyncTroubleshootingTips,
                      ),
                    ),
                  ]),
                ),
              ),
            ),

            if (hasSupportInfo)
              PrismSection(
                title: context.l10n.syncTroubleshootingSupportInfo,
                child: PrismGroupedSectionCard(
                  child: Column(
                    children: _withRowDividers([
                      if (syncId != null && syncId.isNotEmpty)
                        _CopyableSupportRow(
                          icon: AppIcons.tag,
                          label: context.l10n.syncTroubleshootingSyncId,
                          value: syncId,
                          onCopy: () => _copySupportValue(
                            context,
                            context.l10n.syncTroubleshootingSyncId,
                            syncId,
                          ),
                        ),
                      if (relayUrl != null && relayUrl.isNotEmpty)
                        _CopyableSupportRow(
                          icon: AppIcons.link,
                          label: context.l10n.syncTroubleshootingRelayUrl,
                          value: relayUrl,
                          onCopy: () => _copySupportValue(
                            context,
                            context.l10n.syncTroubleshootingRelayUrl,
                            relayUrl,
                          ),
                        ),
                      if (nodeId != null && nodeId.isNotEmpty)
                        _CopyableSupportRow(
                          icon: AppIcons.fingerprint,
                          label: context.l10n.syncNodeIdLabel,
                          value: nodeId,
                          onCopy: () => _copySupportValue(
                            context,
                            context.l10n.syncNodeIdLabel,
                            nodeId,
                          ),
                        ),
                    ]),
                  ),
                ),
              ),

            if (hasAttentionItems)
              PrismSection(
                title: context.l10n.syncTroubleshootingNeedsAttention,
                child: Column(
                  children: [
                    if (syncStatus.lastError != null)
                      PrismGroupedSectionCard(
                        child: PrismSettingsRow(
                          icon: AppIcons.errorOutline,
                          iconColor: theme.colorScheme.error,
                          title: context.l10n.syncTroubleshootingLastError,
                          subtitle: syncStatus.lastError,
                          showChevron: false,
                        ),
                      ),
                    if (syncStatus.lastError != null &&
                        syncStatus.quarantinedBatchCount > 0)
                      const SizedBox(height: 10),
                    if (syncStatus.quarantinedBatchCount > 0)
                      PrismGroupedSectionCard(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    AppIcons.warningAmberRounded,
                                    color: theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.l10n
                                              .syncQuarantinedBatchBannerTitle(
                                                syncStatus
                                                    .quarantinedBatchCount,
                                              ),
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          context
                                              .l10n
                                              .syncQuarantinedBatchBannerBody,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                height: 1.3,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _QuarantineRepairAction(),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            PrismSection(
              title: context.l10n.syncTroubleshootingActivity,
              child: PrismGroupedSectionCard(
                child: _SyncActivityRows(syncStatus: syncStatus),
              ),
            ),

            PrismSection(
              title: context.l10n.syncTroubleshootingDiagnostics,
              description: context.l10n.syncTroubleshootingDiagnosticsSubtitle,
              child: PrismGroupedSectionCard(
                child: Column(
                  children: [
                    PrismSettingsRow(
                      icon: AppIcons.receiptLongOutlined,
                      title: context.l10n.syncTroubleshootingEventLogTitle,
                      subtitle:
                          context.l10n.syncTroubleshootingEventLogSubtitle,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsSyncDebug),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSettingsRow(
                      icon: AppIcons.lock,
                      title: context.l10n.syncTroubleshootingCryptoStorageTitle,
                      subtitle:
                          context.l10n.syncTroubleshootingCryptoStorageSubtitle,
                      onTap: () => context.push(
                        AppRoutePaths.settingsCryptoStorageDebug,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
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
      await syncNowAfterOutboxDrain(
        db: ref.read(databaseProvider),
        handle: handle,
      );
      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.syncTroubleshootingFinished,
        );
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.syncTroubleshootingFailed(e),
        );
      }
    }
  }

  void _copySupportValue(BuildContext context, String label, String value) {
    unawaited(() async {
      await Clipboard.setData(ClipboardData(text: value));
      if (!context.mounted) return;
      PrismToast.show(
        context,
        message: context.l10n.syncTroubleshootingCopied(label),
      );
    }());
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    unawaited(
      PrismDialog.show<String>(
        context: context,
        title: context.l10n.syncTroubleshootingResetTitle,
        message: context.l10n.syncTroubleshootingResetMessage,
        actions: [
          PrismButton(
            label: context.l10n.cancel,
            tone: PrismButtonTone.outlined,
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
          PrismButton(
            label: context.l10n.syncTroubleshootingBackupFirst,
            tone: PrismButtonTone.filled,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop('backup'),
          ),
          PrismButton(
            label: context.l10n.syncTroubleshootingResetConfirm,
            tone: PrismButtonTone.destructive,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop('reset'),
          ),
        ],
        builder: (dialogContext) => const SizedBox.shrink(),
      ).then((result) async {
        if (result == 'backup') {
          if (!context.mounted) return;
          unawaited(context.push(AppRoutePaths.settingsImportExport));
          return;
        }
        if (result != 'reset') return;
        try {
          await ref
              .read(resetDataNotifierProvider.notifier)
              .reset(ResetCategory.sync);
          if (!context.mounted) return;
          PrismToast.show(
            context,
            message: context.l10n.syncTroubleshootingResetSuccess,
          );
          context.go(AppRoutePaths.settingsSync);
        } catch (e) {
          if (!context.mounted) return;
          PrismToast.error(
            context,
            message: context.l10n.syncTroubleshootingFailed(e),
          );
        }
      }),
    );
  }
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

List<Widget> _withRowDividers(List<Widget> rows) {
  final children = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      children.add(const Divider(height: 1, indent: 60, endIndent: 12));
    }
    children.add(rows[i]);
  }
  return children;
}

class _CopyableSupportRow extends StatelessWidget {
  const _CopyableSupportRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSettingsRow(
      icon: icon,
      title: label,
      subtitleWidget: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.25,
        ),
      ),
      trailing: Icon(
        AppIcons.copyAll,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      ),
      showChevron: false,
      onTap: onCopy,
      onLongPress: onCopy,
      onSecondaryTap: onCopy,
    );
  }
}

class _SyncActivityRows extends ConsumerWidget {
  const _SyncActivityRows({required this.syncStatus});

  final SyncStatus syncStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(_syncEntityCountsProvider);
    final rows = <(String, String)>[
      (
        context.l10n.syncTroubleshootingLastSuccessful,
        syncStatus.lastSyncAt != null
            ? _formatDateTime(syncStatus.lastSyncAt!)
            : context.l10n.syncTroubleshootingNeverSynced,
      ),
      (
        context.l10n.syncTroubleshootingCurrentState,
        syncStatus.isSyncing
            ? context.l10n.syncTroubleshootingSyncing
            : context.l10n.syncTroubleshootingIdle,
      ),
      if (syncStatus.pendingOps > 0)
        (
          context.l10n.syncTroubleshootingPendingOps,
          context.l10n.syncTroubleshootingPendingOpsValue(
            syncStatus.pendingOps,
          ),
        ),
      ...countsAsync.maybeWhen(
        data: (counts) => [
          (
            context.l10n.syncLast24h,
            context.l10n.syncEntitiesCount(counts.last24h),
          ),
          (
            context.l10n.syncTotal,
            context.l10n.syncEntitiesCount(counts.total),
          ),
        ],
        loading: () => [
          (context.l10n.syncLast24h, context.l10n.loading),
          (context.l10n.syncTotal, context.l10n.loading),
        ],
        orElse: () => const <(String, String)>[],
      ),
    ];

    return Column(
      children: _withRowDividers([
        for (final row in rows)
          _ActivityDetailRow(label: row.$1, value: row.$2),
      ]),
    );
  }
}

class _ActivityDetailRow extends StatelessWidget {
  const _ActivityDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class SyncTroubleshootingTipsScreen extends StatelessWidget {
  const SyncTroubleshootingTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.syncTroubleshootingTipsTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(top: 12, bottom: NavBarInset.of(context)),
        children: [
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
    return PrismSurface(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    );
  }
}

/// Phase 1C repair action shown beneath the quarantine banner.
///
/// Owns its own loading state so the button can spinner mid-tap without
/// dragging the rest of the troubleshooting screen into a Future rebuild.
/// Calls [repairQuarantinedBatches] which refreshes the count and kicks an
/// auto-sync on success.
class _QuarantineRepairAction extends ConsumerStatefulWidget {
  @override
  ConsumerState<_QuarantineRepairAction> createState() =>
      _QuarantineRepairActionState();
}

class _QuarantineRepairActionState
    extends ConsumerState<_QuarantineRepairAction> {
  bool _isRepairing = false;

  Future<void> _onRepair() async {
    if (_isRepairing) return;
    setState(() => _isRepairing = true);
    try {
      final repaired = await repairQuarantinedBatches(ref);
      if (!mounted) return;
      PrismToast.show(
        context,
        message: context.l10n.syncQuarantinedBatchRepairSuccess(repaired),
      );
    } catch (e) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: context.l10n.syncQuarantinedBatchRepairFailure(e.toString()),
      );
    } finally {
      if (mounted) {
        setState(() => _isRepairing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrismButton(
          onPressed: _onRepair,
          enabled: !_isRepairing,
          isLoading: _isRepairing,
          icon: AppIcons.buildCircleOutlined,
          label: context.l10n.syncQuarantinedBatchRepairAction,
          tone: PrismButtonTone.filled,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.syncQuarantinedBatchRepairDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
