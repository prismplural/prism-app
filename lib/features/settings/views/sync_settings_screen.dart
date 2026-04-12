import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/secret_key_reveal_content.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
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
    final isConfigured =
        relayUrl != null &&
        relayUrl.isNotEmpty &&
        syncId != null &&
        syncId.isNotEmpty;
    final syncHealth = ref.watch(syncHealthProvider);

    if (syncHealth == SyncHealthState.disconnected) {
      return PrismPageScaffold(
        topBar: PrismTopBar(title: context.l10n.syncTitle, showBackButton: true),
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
        !syncIdAsync.hasValue) {
      return PrismPageScaffold(
        topBar: PrismTopBar(title: context.l10n.syncTitle, showBackButton: true),
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
        topBar: PrismTopBar(title: context.l10n.syncTitle, showBackButton: true),
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
              child: _ConfiguredView(relayUrl: relayUrl, syncId: syncId),
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
    final nodeId = ref.watch(nodeIdProvider).value;
    final wsConnected = ref.watch(websocketConnectedProvider);

    final quarantinedAsync = ref.watch(quarantinedItemsProvider);

    final isSyncActive = syncStatus.isSyncing;
    final canSyncNow = handle != null && !isSyncActive;

    return ListView(
      padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
      children: [
        // Status card — no section title, stands alone at top
        _StatusCard(
          syncStatus: syncStatus,
          hasActiveHandle: handle != null,
          wsConnected: wsConnected,
        ),

        // Primary actions
        PrismSection(
          title: 'Sync',
          child: PrismSectionCard(
            child: Column(
              children: [
                PrismSettingsRow(
                  icon: AppIcons.sync,
                  title: context.l10n.syncNowTitle,
                  subtitle: isSyncActive
                      ? context.l10n.syncInProgress
                      : context.l10n.syncNowSubtitle,
                  showChevron: false,
                  enabled: canSyncNow,
                  trailing: isSyncActive
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: canSyncNow
                      ? () => _syncNow(context, ref, handle)
                      : null,
                ),
                if (handle != null) ...[
                  const Divider(height: 1),
                  PrismSettingsRow(
                    icon: AppIcons.devices,
                    title: context.l10n.syncSetUpAnotherDevice,
                    subtitle: context.l10n.syncSetUpAnotherDeviceSubtitle,
                    onTap: () => SetupDeviceSheet.show(context, ref),
                  ),
                  const Divider(height: 1),
                  PrismSettingsRow(
                    icon: AppIcons.devicesOther,
                    title: context.l10n.syncManageDevices,
                    subtitle: context.l10n.syncManageDevicesSubtitle,
                    onTap: () => context.push(AppRoutePaths.settingsDevices),
                  ),
                ],
                if (syncHealth == SyncHealthState.healthy) ...[
                  const Divider(height: 1),
                  PrismSettingsRow(
                    icon: AppIcons.passwordOutlined,
                    title: context.l10n.syncChangePassword,
                    subtitle: context.l10n.syncChangePasswordSubtitle,
                    enabled: !isSyncActive,
                    onTap: () => ChangePinSheet.show(context),
                  ),
                  const Divider(height: 1),
                  PrismSettingsRow(
                    icon: AppIcons.key,
                    title: context.l10n.syncViewSecretKey,
                    subtitle: context.l10n.syncViewSecretKeySubtitle,
                    onTap: () => _showSecretKey(context),
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
          child: PrismSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SyncThemeToggle(),
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
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
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
          child: PrismSectionCard(
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
    ffi.PrismSyncHandle handle,
  ) async {
    try {
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

  void _showSecretKey(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          _ViewSecretKeySheet(scrollController: scrollController),
    );
  }
}

/// Sheet that prompts for password confirmation, then reveals the secret key.
class _ViewSecretKeySheet extends ConsumerStatefulWidget {
  const _ViewSecretKeySheet({this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<_ViewSecretKeySheet> createState() =>
      _ViewSecretKeySheetState();
}

class _ViewSecretKeySheetState extends ConsumerState<_ViewSecretKeySheet> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _mnemonic;

  ffi.PrismSyncHandle? get _handle => ref.read(prismSyncHandleProvider).value;

  @override
  void dispose() {
    _pinController.dispose();
    // Clear the mnemonic from memory on dismiss
    _mnemonic = null;
    super.dispose();
  }

  Future<void> _verifyAndReveal() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Read the mnemonic from keychain
      final mnemonicB64 = await secureStorage.read(key: 'prism_sync.mnemonic');
      if (mnemonicB64 == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = context.l10n.syncSecretKeyNotFound;
        });
        return;
      }

      // Decode the mnemonic (base64 → UTF-8)
      String mnemonic;
      try {
        mnemonic = utf8.decode(base64Decode(mnemonicB64));
      } catch (_) {
        // If it's not base64-encoded, use it as-is
        mnemonic = mnemonicB64;
      }

      // Verify the password by re-running unlock on the existing handle.
      // This performs full Argon2id derivation (a few seconds) and throws
      // if the password is wrong. Since the engine is already unlocked,
      // re-unlocking is idempotent and safe.
      final handle = _handle;
      if (handle == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = context.l10n.syncEngineNotAvailable;
        });
        return;
      }

      final secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonic);
      try {
        await ffi.unlock(
          handle: handle,
          password: pin,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = context.l10n.syncIncorrectPassword;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _mnemonic = mnemonic;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = context.l10n.syncAnErrorOccurred(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: _mnemonic != null ? context.l10n.syncSecretKeyTitle : context.l10n.syncVerifyPasswordTitle,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _mnemonic != null
                ? SingleChildScrollView(
                    controller: widget.scrollController,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 16 + bottomInset,
                    ),
                    child: SecretKeyRevealContent(
                      mnemonic: _mnemonic!,
                      hasSaved: true,
                      onHasSavedChanged: (_) {},
                      showSaveConfirmation: false,
                    ),
                  )
                : SingleChildScrollView(
                    controller: widget.scrollController,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 16 + bottomInset,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.l10n.syncVerifyPasswordPrompt,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        PrismTextField(
                          controller: _pinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          enabled: !_isLoading,
                          onSubmitted: (_) => _verifyAndReveal(),
                          hintText: context.l10n.syncPasswordHint,
                          errorText: _error,
                        ),
                        const SizedBox(height: 16),
                        PrismButton(
                          label: context.l10n.syncRevealSecretKey,
                          onPressed: _verifyAndReveal,
                          isLoading: _isLoading,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SyncThemeToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(syncThemeEnabledProvider);

    return PrismSwitchRow(
      icon: AppIcons.paletteOutlined,
      iconColor: Colors.deepPurple,
      title: context.l10n.appearanceSyncThemeTitle,
      subtitle: context.l10n.appearanceSyncThemeSubtitle,
      value: value,
      onChanged: (v) =>
          ref.read(settingsNotifierProvider.notifier).updateSyncThemeEnabled(v),
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
          _DetailRow(label: context.l10n.syncTotal, value: context.l10n.syncEntitiesCount(counts.total)),
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

/// Compact detail row for the Details section.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return PrismListRow(dense: true, title: Text(label), subtitle: Text(value));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.syncStatus,
    required this.hasActiveHandle,
    required this.wsConnected,
  });

  final SyncStatus syncStatus;
  final bool hasActiveHandle;
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
    } else if (hasActiveHandle) {
      statusColor = theme.colorScheme.primary;
      statusIcon = AppIcons.cloudQueue;
      statusText = context.l10n.syncStatusReadyToSync;
      statusDetail = context.l10n.syncStatusWaiting;
    } else {
      statusColor = theme.colorScheme.outline;
      statusIcon = AppIcons.cloudOff;
      statusText = context.l10n.syncStatusNeedsReconnect;
      statusDetail = context.l10n.syncStatusTapToReconnect;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: PrismSectionCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          statusText,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: statusColor,
                          ),
                        ),
                        if (statusDetail.isNotEmpty) ...[
                          Text(
                            '  ·  ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              statusDetail,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          wsConnected
                              ? AppIcons.cellTower
                              : AppIcons.signalWifiOff,
                          size: 13,
                          color: wsConnected
                              ? Colors.green
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          wsConnected
                              ? context.l10n.syncRealTimeConnected
                              : context.l10n.syncRealTimeDisconnected,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: wsConnected
                                ? Colors.green
                                : theme.colorScheme.outline,
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
