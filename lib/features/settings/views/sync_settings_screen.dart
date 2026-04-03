import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/features/settings/widgets/setup_device_sheet.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Sync entity counts provider
// ---------------------------------------------------------------------------

class SyncEntityCounts {
  const SyncEntityCounts({required this.total, required this.last24h});
  final int total;
  final int last24h;
}

final syncEntityCountsProvider =
    FutureProvider.autoDispose<SyncEntityCounts>((ref) async {
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
  final totalParts =
      tables.map((t) => 'SELECT COUNT(*) AS c FROM $t WHERE is_deleted = 0');
  final totalSql =
      'SELECT SUM(c) AS total FROM (${totalParts.join(' UNION ALL ')})';

  final totalResult = await db.customSelect(totalSql).getSingle();
  final total = totalResult.read<int>('total');

  // Build a single SQL query: count of entities with a recent date.
  final cutoff = DateTime.now()
      .subtract(const Duration(hours: 24))
      .millisecondsSinceEpoch ~/ 1000;
  final recentParts = dateColumns.entries.map((e) =>
      'SELECT COUNT(*) AS c FROM ${e.key} '
      'WHERE is_deleted = 0 AND ${e.value} >= $cutoff');
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
        topBar: const PrismTopBar(title: 'Sync', showBackButton: true),
        body: _StateMessageView(
          icon: AppIcons.syncDisabled,
          title: 'Sync was disconnected',
          message: 'Set up sync again to reconnect your devices.',
          actionLabel: 'Set Up Sync',
          onAction: () => context.push(AppRoutePaths.syncSetup),
        ),
      );
    }

    if ((relayUrlAsync.isLoading || syncIdAsync.isLoading) &&
        !relayUrlAsync.hasValue &&
        !syncIdAsync.hasValue) {
      return const PrismPageScaffold(
        topBar: PrismTopBar(title: 'Sync', showBackButton: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final loadError = relayUrlAsync.hasError
        ? relayUrlAsync.error
        : syncIdAsync.hasError
        ? syncIdAsync.error
        : null;

    if (loadError != null && !isConfigured) {
      return PrismPageScaffold(
        topBar: const PrismTopBar(title: 'Sync', showBackButton: true),
        body: _StateMessageView(
          icon: AppIcons.syncProblem,
          title: 'Unable to load sync settings',
          message: '$loadError',
          actionLabel: 'Try again',
          onAction: () {
            ref.invalidate(relayUrlProvider);
            ref.invalidate(syncIdProvider);
          },
        ),
      );
    }

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Sync', showBackButton: true),
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
              'Sync is not set up',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Set up end-to-end encrypted sync to keep your data '
              'in sync across all your devices.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PrismButton(
              label: 'Set Up Sync',
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
                  title: 'Sync now',
                  subtitle: isSyncActive
                      ? 'Syncing…'
                      : 'Check for changes and push local updates',
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
                    title: 'Set up another device',
                    subtitle: 'Generate a pairing QR code',
                    onTap: () => SetupDeviceSheet.show(context, ref),
                  ),
                  const Divider(height: 1),
                  PrismSettingsRow(
                    icon: AppIcons.devicesOther,
                    title: 'Manage Devices',
                    subtitle: 'View and revoke linked devices',
                    onTap: () =>
                        context.push(AppRoutePaths.settingsDevices),
                  ),
                ],
                if (syncHealth == SyncHealthState.healthy) ...[
                  const Divider(height: 1),
                  PrismSettingsRow(
                    icon: AppIcons.key,
                    title: 'View Secret Key',
                    subtitle: 'Show your 12-word recovery phrase',
                    onTap: () => _showSecretKey(context),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Sync preferences — centralises sync-behaviour toggles from other screens
        PrismSection(
          title: 'Sync Preferences',
          description:
              'Control what settings are shared across your devices via sync.',
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
            title: 'Sync Issues',
            description:
                'These records could not be applied due to data type '
                'mismatches. Clearing them removes the warning indicator.',
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
                  ListTile(
                    title: Text(
                      'Clear all',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () async {
                      await ref
                          .read(syncQuarantineServiceProvider)
                          .clearAll();
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
          title: 'Details',
          child: PrismSectionCard(
            child: Column(
              children: [
                _SyncEntityCountRows(),
                const Divider(height: 1),
                _DetailRow(label: 'Relay', value: relayUrl),
                const Divider(height: 1),
                _DetailRow(label: 'Sync ID', value: syncId),
                const Divider(height: 1),
                _DetailRow(
                  label: 'Node ID',
                  value: nodeId ?? 'Not initialised',
                ),
                if (syncStatus.lastError != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      AppIcons.errorOutline,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      syncStatus.lastError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1),
                PrismSettingsRow(
                  icon: AppIcons.buildCircleOutlined,
                  title: 'Troubleshooting',
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
        PrismToast.show(context, message: 'Sync finished');
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: 'Sync failed: $e');
      }
    }
  }

  void _showSecretKey(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => _ViewSecretKeySheet(
        scrollController: scrollController,
      ),
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
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;
  String? _mnemonic;

  ffi.PrismSyncHandle? get _handle =>
      ref.read(prismSyncHandleProvider).value;

  @override
  void dispose() {
    _passwordController.dispose();
    // Clear the mnemonic from memory on dismiss
    _mnemonic = null;
    super.dispose();
  }

  Future<void> _verifyAndReveal() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Read the mnemonic from keychain
      final mnemonicB64 = await secureStorage.read(
        key: 'prism_sync.mnemonic',
      );
      if (mnemonicB64 == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Secret Key not found in keychain.';
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
          _error = 'Sync engine not available.';
        });
        return;
      }

      final secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonic);
      try {
        await ffi.unlock(
          handle: handle,
          password: password,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Incorrect password. Please try again.';
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
        _error = 'An error occurred: $e';
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
            title: _mnemonic != null ? 'Secret Key' : 'Verify Password',
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
                          'Enter your sync password to reveal your 12-word recovery phrase.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          autofocus: true,
                          enabled: !_isLoading,
                          onSubmitted: (_) => _verifyAndReveal(),
                          decoration: InputDecoration(
                            hintText: 'Sync password',
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure ? AppIcons.visibilityOff : AppIcons.visibility,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                            errorText: _error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        PrismButton(
                          label: 'Reveal Secret Key',
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
      title: 'Sync theme across devices',
      subtitle: 'Share brightness, style, and accent color via sync',
      value: value,
      onChanged: (v) => ref
          .read(settingsNotifierProvider.notifier)
          .updateSyncThemeEnabled(v),
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
      title: 'Sync navigation layout',
      subtitle: 'Share tab arrangement across devices',
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
    final theme = Theme.of(context);
    final field = item.fieldName ?? 'unknown field';
    return ListTile(
      dense: true,
      leading: Icon(
        AppIcons.warningAmberRounded,
        size: 20,
        color: Colors.amber.shade700,
      ),
      title: Text(
        '${item.entityType} · $field',
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        item.errorMessage ??
            'Expected ${item.expectedType}, got ${item.receivedType}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
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
            label: 'Synced last 24h',
            value: '${counts.last24h} entities',
          ),
          const Divider(height: 1),
          _DetailRow(
            label: 'Total synced',
            value: '${counts.total} entities',
          ),
        ],
      ),
      loading: () => const Column(
        children: [
          _DetailRow(label: 'Synced last 24h', value: '...'),
          Divider(height: 1),
          _DetailRow(label: 'Total synced', value: '...'),
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
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(label, style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      )),
      subtitle: Text(
        value,
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
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
      statusText = 'Sync error';
      statusDetail = syncStatus.lastError!;
    } else if (syncStatus.isSyncing) {
      statusColor = theme.colorScheme.primary;
      statusIcon = AppIcons.sync;
      statusText = 'Syncing';
      statusDetail = 'Sync in progress…';
    } else if (syncStatus.lastSyncAt != null &&
        syncStatus.hasQuarantinedItems) {
      statusColor = Colors.amber.shade700;
      statusIcon = AppIcons.cloudDone;
      statusText = 'Synced with issues';
      statusDetail = _formatTime(syncStatus.lastSyncAt!);
    } else if (syncStatus.lastSyncAt != null) {
      statusColor = Colors.green;
      statusIcon = AppIcons.cloudDone;
      statusText = 'Last synced';
      statusDetail = _formatTime(syncStatus.lastSyncAt!);
    } else if (hasActiveHandle) {
      statusColor = theme.colorScheme.primary;
      statusIcon = AppIcons.cloudQueue;
      statusText = 'Ready to sync';
      statusDetail = 'Waiting for changes.';
    } else {
      statusColor = theme.colorScheme.outline;
      statusIcon = AppIcons.cloudOff;
      statusText = 'Needs reconnect';
      statusDetail = 'Tap Sync Now to reconnect.';
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
                              ? 'Real-time connected'
                              : 'Real-time disconnected',
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

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
