import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/features/settings/widgets/change_pin_sheet.dart';
import 'package:prism_plurality/features/settings/widgets/setup_device_sheet.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

// ---------------------------------------------------------------------------
// Sync entity counts provider
// ---------------------------------------------------------------------------

@visibleForTesting
bool canTriggerManualSync({
  required bool hasHandle,
  required bool hasRelayUrl,
  required bool isSyncActive,
  required bool isHandleLoading,
}) {
  if (isSyncActive || isHandleLoading) return false;
  return hasHandle || hasRelayUrl;
}

class SyncEntityCounts {
  const SyncEntityCounts({required this.total, required this.last24h});
  final int total;
  final int last24h;
}

final syncEntityCountsProvider = FutureProvider.autoDispose<SyncEntityCounts>((
  ref,
) async {
  final db = ref.watch(databaseProvider);

  // All synced entity tables with is_deleted column.
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

  // Tables mapped to the date column to use for "last 24h" filtering.
  // Tables without a date column are excluded from the 24h count.
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

  // Build a single SQL query: total count across all tables.
  final totalParts = tables.map(
    (t) => 'SELECT COUNT(*) AS c FROM $t WHERE is_deleted = 0',
  );
  final totalSql =
      'SELECT SUM(c) AS total FROM (${totalParts.join(' UNION ALL ')})';

  final totalResult = await db.customSelect(totalSql).getSingle();
  final total = totalResult.read<int>('total');

  // Build a single SQL query: count of entities with a recent date.
  final cutoff =
      DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch ~/
      1000;
  final recentParts = dateColumns.entries.map(
    (e) =>
        'SELECT COUNT(*) AS c FROM ${e.key} '
        'WHERE is_deleted = 0 AND ${e.value} >= $cutoff',
  );
  final recentSql =
      'SELECT SUM(c) AS total FROM (${recentParts.join(' UNION ALL ')})';

  final recentResult = await db.customSelect(recentSql).getSingle();
  final last24h = recentResult.read<int>('total');

  return SyncEntityCounts(total: total, last24h: last24h);
});

class SyncSettingsScreen extends ConsumerWidget {
  const SyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relayUrlAsync = ref.watch(relayUrlProvider);
    final syncIdAsync = ref.watch(syncIdProvider);
    final relayUrl = relayUrlAsync.value;
    final syncId = syncIdAsync.value;
    // Use the FFI handle as the primary "configured" signal. Its AsyncData
    // is set synchronously inside `createHandle` and is not invalidated when
    // the keychain-backed FutureProviders below are invalidated, so it does
    // not have the stale-cache flicker that `(relayUrl, syncId)` does. Fall
    // back to the keychain values so we still consider a device configured
    // before the handle finishes building (e.g. during initial app start
    // before `prismSyncHandleProvider.build` resolves).
    //
    // Phase 4A: chosen over widening the loading guard because handle-based
    // gating eliminates the flicker entirely rather than masking it with a
    // spinner during invalidate.
    final handleAsyncForGate = ref.watch(prismSyncHandleProvider);
    final hasActiveHandle = handleAsyncForGate.value != null;
    final hasKeychainCreds =
        relayUrl != null &&
        relayUrl.isNotEmpty &&
        syncId != null &&
        syncId.isNotEmpty;
    final isConfigured = hasActiveHandle || hasKeychainCreds;
    final syncHealth = ref.watch(syncHealthProvider);

    if (syncHealth == SyncHealthState.disconnected) {
      return PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.syncTitle,
          showBackButton: true,
        ),
        body: _StateMessageView(
          icon: AppIcons.syncDisabled,
          title: context.l10n.syncDisconnectedTitle,
          message: context.l10n.syncDisconnectedMessage,
          actionLabel: context.l10n.syncSetUpSyncButton,
          onAction: () => context.push(AppRoutePaths.syncSetup),
        ),
      );
    }

    if ((relayUrlAsync.isLoading || syncIdAsync.isLoading) &&
        !relayUrlAsync.hasValue &&
        !syncIdAsync.hasValue &&
        !isConfigured) {
      return PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.syncTitle,
          showBackButton: true,
        ),
        body: const PrismLoadingState(),
      );
    }

    final loadError = relayUrlAsync.hasError
        ? relayUrlAsync.error
        : syncIdAsync.hasError
        ? syncIdAsync.error
        : null;

    if (loadError != null && !isConfigured) {
      return PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.syncTitle,
          showBackButton: true,
        ),
        body: _StateMessageView(
          icon: AppIcons.syncProblem,
          title: context.l10n.syncUnableToLoad,
          message: '$loadError',
          actionLabel: context.l10n.tryAgain,
          onAction: () {
            ref.invalidate(relayUrlProvider);
            ref.invalidate(syncIdProvider);
          },
        ),
      );
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.syncTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: isConfigured
          ? SyncToastListener(
              child: _ConfiguredView(
                relayUrl: relayUrl ?? '',
                syncId: syncId ?? '',
              ),
            )
          : const _SetupView(),
    );
  }
}

class _SetupView extends StatelessWidget {
  const _SetupView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.duotoneSync,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.syncNotSetUp,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.syncNotSetUpDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PrismButton(
              label: context.l10n.syncSetupButton,
              icon: AppIcons.lockOutline,
              tone: PrismButtonTone.filled,
              onPressed: () => context.push(AppRoutePaths.syncSetup),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateMessageView extends StatelessWidget {
  const _StateMessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PrismButton(
              label: actionLabel,
              icon: AppIcons.refresh,
              tone: PrismButtonTone.filled,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfiguredView extends ConsumerWidget {
  const _ConfiguredView({required this.relayUrl, required this.syncId});

  final String relayUrl;
  final String syncId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final syncStatus = ref.watch(syncStatusProvider);
    final syncHealth = ref.watch(syncHealthProvider);
    final handleAsync = ref.watch(prismSyncHandleProvider);
    final handle = handleAsync.value;
    final isHandleLoading = handleAsync.isLoading && handle == null;
    final nodeId = ref.watch(nodeIdProvider).value;
    final wsConnected = ref.watch(websocketConnectedProvider);

    final quarantinedAsync = ref.watch(quarantinedItemsProvider);

    final isSyncActive = syncStatus.isSyncing;
    final hasRelayUrl = relayUrl.isNotEmpty;
    final canSyncNow = canTriggerManualSync(
      hasHandle: handle != null,
      hasRelayUrl: hasRelayUrl,
      isSyncActive: isSyncActive,
      isHandleLoading: isHandleLoading,
    );

    return ListView(
      padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
      children: [
        // Status card — no section title, stands alone at top
        _StatusCard(
          syncStatus: syncStatus,
          hasActiveHandle: handle != null,
          handleIsLoading: isHandleLoading,
          canAttemptReconnect: hasRelayUrl,
          wsConnected: wsConnected,
        ),

        // Primary actions
        PrismSection(
          title: 'Sync',
          child: PrismGroupedSectionCard(
            child: Column(
              children: [
                PrismSettingsRow(
                  icon: AppIcons.sync,
                  title: context.l10n.syncNowTitle,
                  subtitle: isSyncActive
                      ? context.l10n.syncInProgress
                      : isHandleLoading
                      ? context.l10n.syncStatusWaiting
                      : context.l10n.syncNowSubtitle,
                  showChevron: false,
                  enabled: canSyncNow,
                  trailing: isSyncActive || isHandleLoading
                      ? PrismSpinner(
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        )
                      : null,
                  onTap: canSyncNow
                      ? () => _syncNow(context, ref, handle, relayUrl)
                      : null,
                ),
                if (handle != null) ...[
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  PrismSettingsRow(
                    icon: AppIcons.devices,
                    title: context.l10n.syncSetUpAnotherDevice,
                    subtitle: context.l10n.syncSetUpAnotherDeviceSubtitle,
                    onTap: () => SetupDeviceSheet.show(context, ref),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  PrismSettingsRow(
                    icon: AppIcons.devicesOther,
                    title: context.l10n.syncManageDevices,
                    subtitle: context.l10n.syncManageDevicesSubtitle,
                    onTap: () => context.push(AppRoutePaths.settingsDevices),
                  ),
                ],
                if (syncHealth == SyncHealthState.healthy) ...[
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  PrismSettingsRow(
                    icon: AppIcons.passwordOutlined,
                    title: context.l10n.syncChangePassword,
                    subtitle: context.l10n.syncChangePasswordSubtitle,
                    enabled: !isSyncActive,
                    onTap: () => ChangePinSheet.show(context),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Sync preferences — centralises sync-behaviour toggles from other screens
        PrismSection(
          title: context.l10n.syncPreferencesSection,
          description: context.l10n.syncPreferencesDescription,
          child: PrismGroupedSectionCard(
            child: Column(
              children: [
                _SyncAppearanceToggle(),
                const Divider(height: 1, indent: 60, endIndent: 12),
                _IgnoreSyncedAppearanceToggle(),
                const Divider(height: 1, indent: 60, endIndent: 12),
                _SyncNavigationToggle(),
              ],
            ),
          ),
        ),

        // Quarantine section — only visible when there are stuck records
        if (syncStatus.hasQuarantinedItems)
          PrismSection(
            title: context.l10n.syncIssuesSection,
            description: context.l10n.syncIssuesDescription,
            child: PrismGroupedSectionCard(
              child: Column(
                children: [
                  ...quarantinedAsync.whenOrNull(
                        data: (items) => items
                            .map((item) => _QuarantineItemTile(item: item))
                            .toList(),
                      ) ??
                      [],
                  if (quarantinedAsync.hasValue &&
                      quarantinedAsync.value!.isNotEmpty)
                    const Divider(height: 1),
                  PrismListRow(
                    title: Text(context.l10n.syncClearAll),
                    destructive: true,
                    onTap: () async {
                      await ref.read(syncQuarantineServiceProvider).clearAll();
                      ref.invalidate(quarantinedItemsProvider);
                      ref
                          .read(syncStatusProvider.notifier)
                          .clearQuarantineFlag();
                    },
                  ),
                ],
              ),
            ),
          ),

        // Connection details — always visible, no toggle
        PrismSection(
          title: context.l10n.syncDetailsSection,
          child: PrismGroupedSectionCard(
            child: Column(
              children: [
                _SyncEntityCountRows(),
                const Divider(height: 1),
                _DetailRow(label: context.l10n.syncRelayLabel, value: relayUrl),
                const Divider(height: 1),
                _DetailRow(label: context.l10n.syncIdLabel, value: syncId),
                const Divider(height: 1),
                _DetailRow(
                  label: context.l10n.syncNodeIdLabel,
                  value: nodeId ?? context.l10n.syncNodeIdNotInitialised,
                ),
                if (syncStatus.lastError != null) ...[
                  const Divider(height: 1),
                  PrismListRow(
                    dense: true,
                    leading: Icon(
                      AppIcons.errorOutline,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(syncStatus.lastError!),
                    destructive: true,
                  ),
                ],
                const Divider(height: 1),
                PrismSettingsRow(
                  icon: AppIcons.buildCircleOutlined,
                  title: context.l10n.syncTroubleshootingLink,
                  onTap: () =>
                      context.push(AppRoutePaths.settingsSyncTroubleshooting),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _syncNow(
    BuildContext context,
    WidgetRef ref,
    ffi.PrismSyncHandle? currentHandle,
    String relayUrl,
  ) async {
    try {
      var handle = currentHandle;
      if (handle == null) {
        if (relayUrl.isEmpty) {
          throw StateError('Sync relay URL is missing.');
        }
        handle = await ref
            .read(prismSyncHandleProvider.notifier)
            .createHandle(relayUrl: relayUrl);
      }

      final health = await ref
          .read(prismSyncHandleProvider.notifier)
          .ensureConfigured(handle);
      if (health != SyncHealthState.healthy) {
        if (context.mounted) {
          PrismToast.error(
            context,
            message: _manualSyncUnavailableMessage(health),
          );
        }
        return;
      }

      // If the WebSocket is disconnected, trigger an immediate reconnect
      // (resets exponential backoff) so real-time notifications resume.
      try {
        await ffi.reconnectWebsocket(handle: handle);
      } catch (_) {
        // Non-fatal: the manual sync cycle below will still run.
      }
      await ffi.syncNow(handle: handle);
      if (context.mounted) {
        PrismToast.show(context, message: context.l10n.syncFinished);
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: context.l10n.syncFailed(e));
      }
    }
  }

  String _manualSyncUnavailableMessage(SyncHealthState health) =>
      switch (health) {
        SyncHealthState.needsPassword =>
          'Sync needs your PIN and recovery phrase before it can reconnect.',
        SyncHealthState.disconnected =>
          'Sync credentials are missing. Set up sync again to reconnect.',
        SyncHealthState.unpaired => 'Sync is not set up on this device.',
        SyncHealthState.healthy => 'Sync is not ready yet.',
      };
}

class _SyncAppearanceToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(syncAppearanceEnabledProvider);

    return PrismSwitchRow(
      icon: AppIcons.paletteOutlined,
      iconColor: Colors.deepPurple,
      title: context.l10n.syncAppearanceToggleTitle,
      subtitle: context.l10n.syncAppearanceToggleDescription,
      value: value,
      onChanged: (v) =>
          ref.read(settingsNotifierProvider.notifier).updateSyncThemeEnabled(v),
    );
  }
}

class _IgnoreSyncedAppearanceToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(ignoreSyncedAppearanceProvider);
    final value = asyncValue.whenOrNull(data: (v) => v) ?? false;

    return PrismSwitchRow(
      icon: AppIcons.devicesOther,
      iconColor: Colors.blueGrey,
      title: context.l10n.syncIgnoreAppearanceTitle,
      subtitle: context.l10n.syncIgnoreAppearanceDescription,
      value: value,
      onChanged: (v) =>
          ref.read(ignoreSyncedAppearanceProvider.notifier).set(v),
    );
  }
}

class _SyncNavigationToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(syncNavigationEnabledProvider);

    return PrismSwitchRow(
      icon: AppIcons.tabOutlined,
      iconColor: Colors.teal,
      title: context.l10n.syncNavigationLayoutTitle,
      subtitle: context.l10n.syncNavigationLayoutSubtitle,
      value: value,
      onChanged: (v) => ref
          .read(settingsNotifierProvider.notifier)
          .updateSyncNavigationEnabled(v),
    );
  }
}

/// A single quarantined record shown in the Sync Issues section.
class _QuarantineItemTile extends StatelessWidget {
  const _QuarantineItemTile({required this.item});

  final SyncQuarantineData item;

  @override
  Widget build(BuildContext context) {
    final field = item.fieldName ?? 'unknown field';
    return PrismListRow(
      dense: true,
      leading: Icon(
        AppIcons.warningAmberRounded,
        size: 20,
        color: Colors.amber.shade700,
      ),
      title: Text('${item.entityType} · $field'),
      subtitle: Text(
        item.errorMessage ??
            'Expected ${item.expectedType}, got ${item.receivedType}',
      ),
    );
  }
}

/// Shows synced entity counts (total and last 24h) in the Details section.
class _SyncEntityCountRows extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(syncEntityCountsProvider);

    return countsAsync.when(
      data: (counts) => Column(
        children: [
          _DetailRow(
            label: context.l10n.syncLast24h,
            value: context.l10n.syncEntitiesCount(counts.last24h),
          ),
          const Divider(height: 1),
          _DetailRow(
            label: context.l10n.syncTotal,
            value: context.l10n.syncEntitiesCount(counts.total),
          ),
        ],
      ),
      loading: () => Column(
        children: [
          _DetailRow(label: context.l10n.syncLast24h, value: '...'),
          const Divider(height: 1),
          _DetailRow(label: context.l10n.syncTotal, value: '...'),
        ],
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// Compact detail row for the Details section — label on the left, value on the right.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.syncStatus,
    required this.hasActiveHandle,
    required this.handleIsLoading,
    required this.canAttemptReconnect,
    required this.wsConnected,
  });

  final SyncStatus syncStatus;
  final bool hasActiveHandle;
  final bool handleIsLoading;
  final bool canAttemptReconnect;
  final bool wsConnected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;
    final String statusDetail;

    if (syncStatus.lastError != null) {
      statusColor = theme.colorScheme.error;
      statusIcon = AppIcons.syncProblem;
      statusText = context.l10n.syncStatusError;
      statusDetail = syncStatus.lastError!;
    } else if (syncStatus.isSyncing) {
      statusColor = theme.colorScheme.primary;
      statusIcon = AppIcons.sync;
      statusText = context.l10n.syncStatusSyncing;
      statusDetail = context.l10n.syncStatusSyncInProgress;
    } else if (syncStatus.lastSyncAt != null &&
        syncStatus.hasQuarantinedItems) {
      statusColor = Colors.amber.shade700;
      statusIcon = AppIcons.cloudDone;
      statusText = context.l10n.syncStatusSyncedWithIssues;
      statusDetail = _formatTime(syncStatus.lastSyncAt!, context);
    } else if (syncStatus.lastSyncAt != null) {
      statusColor = Colors.green;
      statusIcon = AppIcons.cloudDone;
      statusText = context.l10n.syncStatusLastSynced;
      statusDetail = _formatTime(syncStatus.lastSyncAt!, context);
    } else if (hasActiveHandle || handleIsLoading) {
      statusColor = theme.colorScheme.primary;
      statusIcon = AppIcons.cloudQueue;
      statusText = context.l10n.syncStatusReadyToSync;
      statusDetail = context.l10n.syncStatusWaiting;
    } else if (canAttemptReconnect) {
      statusColor = theme.colorScheme.outline;
      statusIcon = AppIcons.cloudOff;
      statusText = context.l10n.syncStatusNeedsReconnect;
      statusDetail = context.l10n.syncStatusTapToReconnect;
    } else {
      statusColor = theme.colorScheme.outline;
      statusIcon = AppIcons.cloudOff;
      statusText = context.l10n.syncStatusNeedsReconnect;
      statusDetail = '';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: PrismSectionCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: statusColor,
                      ),
                    ),
                    if (statusDetail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        statusDetail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          wsConnected
                              ? AppIcons.cellTower
                              : AppIcons.signalWifiOff,
                          size: 12,
                          color: wsConnected
                              ? Colors.green
                              : theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          wsConnected
                              ? context.l10n.syncRealTimeConnected
                              : context.l10n.syncRealTimeDisconnected,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: wsConnected
                                ? Colors.green
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ],
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

  String _formatTime(DateTime time, BuildContext context) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return context.l10n.syncJustNow;
    if (diff.inMinutes < 60) return context.l10n.syncMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return context.l10n.syncHoursAgo(diff.inHours);
    return context.l10n.syncDaysAgo(diff.inDays);
  }
}
