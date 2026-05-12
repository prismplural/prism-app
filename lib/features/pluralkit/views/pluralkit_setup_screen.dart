import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_sync_event_log_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_file_import_screen.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_mapping_screen.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_direction_picker.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_summary_card.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_system_profile_disclosure.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// PluralKit integration setup and sync management screen.
class PluralKitSetupScreen extends ConsumerStatefulWidget {
  const PluralKitSetupScreen({super.key});

  @override
  ConsumerState<PluralKitSetupScreen> createState() =>
      _PluralKitSetupScreenState();
}

class _PluralKitSetupScreenState extends ConsumerState<PluralKitSetupScreen> {
  final _tokenController = TextEditingController();
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void dispose() {
    _tokenController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldownTimer(PluralKitSyncState syncState) {
    _cooldownTimer?.cancel();
    if (syncState.lastManualSyncDate == null) return;

    final elapsed = DateTime.now()
        .difference(syncState.lastManualSyncDate!)
        .inSeconds;
    final remaining = 60 - elapsed;
    if (remaining <= 0) return;

    if (!mounted) return;
    setState(() => _cooldownSeconds = remaining);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _connect() async {
    final token = _tokenController.text;
    if (token.trim().isEmpty) return;

    await ref.read(pluralKitSyncProvider.notifier).setToken(token);
    _tokenController.clear();

    // First-pull disclosure: if the token successfully connected and we haven't
    // shown the system-profile prompt for this PK system before, offer to
    // import name/description/tag/avatar into system_settings.
    final syncState = ref.read(pluralKitSyncProvider);
    if (syncState.isConnected && syncState.syncError == null) {
      await _loadPersistedSyncPreferences();
      final mode = ref.read(pkSyncModeProvider);
      final direction = ref.read(pkSyncDirectionProvider);
      if (mode == PkSyncMode.fullSync && direction.pullEnabled) {
        await _maybeShowProfileDisclosure();
      }
    }
  }

  Future<void> _loadPersistedSyncPreferences() async {
    await ref.read(pkSyncModeProvider.notifier).load();
    await ref.read(pkSyncDirectionProvider.notifier).load();
  }

  bool _canCurrentSyncDrainDestructivePush({
    required PluralKitSyncState syncState,
    required PkSyncMode mode,
    required PkSyncDirection direction,
  }) {
    if (mode != PkSyncMode.fullSync) return false;
    if (!direction.pushEnabled) return false;
    if (direction.pullEnabled && syncState.lastSyncDate == null) return false;
    return true;
  }

  Future<bool> _confirmPluralKitDeleteRisk() async {
    final PkDeleteRiskPreview preview;
    try {
      preview = await ref
          .read(pluralKitSyncProvider.notifier)
          .previewPendingDestructivePush();
    } catch (_) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.pluralkitDeleteRiskPreviewFailed,
        );
      }
      return false;
    }

    if (!mounted) return false;
    if (!preview.hasRemovals || !preview.isSignificant) return true;

    return PrismDialog.confirm(
      context: context,
      title: context.l10n.pluralkitDeleteRiskTitle,
      message: _formatDeleteRiskMessage(preview),
      confirmLabel: context.l10n.pluralkitDeleteRiskConfirm,
      cancelLabel: context.l10n.pluralkitDeleteRiskCancel,
      destructive: true,
      icon: AppIcons.warningAmber,
    );
  }

  String _formatDeleteRiskMessage(PkDeleteRiskPreview preview) {
    final deleteText = _formatDeleteRiskItems(preview);
    if (preview.totalSkipped > 0) {
      return context.l10n.pluralkitDeleteRiskMessageWithSkipped(
        deleteText,
        preview.totalSkipped,
      );
    }
    return context.l10n.pluralkitDeleteRiskMessage(deleteText);
  }

  String _formatDeleteRiskItems(PkDeleteRiskPreview preview) {
    final items = <String>[
      if (preview.membersToDelete > 0)
        context.l10n.pluralkitDeleteRiskMembers(preview.membersToDelete),
      if (preview.switchesToDelete > 0)
        context.l10n.pluralkitDeleteRiskSwitches(preview.switchesToDelete),
      if (preview.groupMembershipsToRemove > 0)
        context.l10n.pluralkitDeleteRiskGroupMemberships(
          preview.groupMembershipsToRemove,
        ),
    ];

    if (items.length <= 1) return items.isEmpty ? '' : items.first;
    if (items.length == 2) {
      return context.l10n.pluralkitDeleteRiskJoinTwo(items[0], items[1]);
    }
    return context.l10n.pluralkitDeleteRiskJoinThree(
      items[0],
      items[1],
      items[2],
    );
  }

  Future<void> _maybeShowProfileDisclosure() async {
    final notifier = ref.read(pluralKitSyncProvider.notifier);
    final PKSystem? pkSystem;
    try {
      pkSystem = await notifier.fetchSystemProfile();
    } catch (_) {
      return;
    }
    if (pkSystem == null) return;
    // Short-circuit if PK has nothing worth offering.
    final anyField =
        (pkSystem.name?.isNotEmpty ?? false) ||
        (pkSystem.description?.isNotEmpty ?? false) ||
        (pkSystem.tag?.isNotEmpty ?? false) ||
        (pkSystem.avatarUrl?.isNotEmpty ?? false);
    if (!anyField) return;

    // One-shot per PK system: once a user decides (import or skip) we don't
    // show the sheet again on subsequent reconnects with the same systemId.
    final prefs = await SharedPreferences.getInstance();
    final sentinelKey = 'pk_profile_disclosure_shown_${pkSystem.id}';
    if (prefs.getBool(sentinelKey) == true) return;

    final currentSettings = await ref
        .read(systemSettingsRepositoryProvider)
        .getSettings();
    if (!mounted) return;

    final accepted = await PrismSheet.show<Set<PkProfileField>?>(
      context: context,
      builder: (sheetCtx) => PkSystemProfileDisclosureSheet(
        pkSystem: pkSystem!,
        currentPrismSettings: currentSettings,
        onConfirm: (selected) => Navigator.of(sheetCtx).pop(selected),
        onSkip: () => Navigator.of(sheetCtx).pop(<PkProfileField>{}),
      ),
    );

    await prefs.setBool(sentinelKey, true);

    if (accepted != null && accepted.isNotEmpty) {
      await notifier.adoptSystemProfile(pk: pkSystem, accepted: accepted);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.pluralkitDisconnectTitle,
      message: context.l10n.pluralkitDisconnectMessage,
      confirmLabel: context.l10n.pluralkitDisconnect,
      destructive: true,
    );
    if (confirmed) {
      await ref.read(pluralKitSyncProvider.notifier).clearToken();
    }
  }

  Future<void> _openMappingScreen() async {
    // Reset the controller so the mapping screen fetches fresh data.
    ref.invalidate(pkMappingControllerProvider);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PkMappingScreen()));
  }

  Future<void> _importFromPK() async {
    await _loadPersistedSyncPreferences();
    if (!mounted) return;
    final mode = ref.read(pkSyncModeProvider);
    if (mode == PkSyncMode.liveFrontsOnly) {
      final direction = ref.read(pkSyncDirectionProvider);
      await ref
          .read(pluralKitSyncProvider.notifier)
          .syncLiveFrontersOnly(isManual: true, direction: direction);
      return;
    }
    await ref.read(pluralKitSyncProvider.notifier).performFullImport();
  }

  Future<void> _importFromFile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PkFileImportScreen()));
  }

  Future<void> _syncRecent() async {
    await _loadPersistedSyncPreferences();
    if (!mounted) return;
    final direction = ref.read(pkSyncDirectionProvider);
    final mode = ref.read(pkSyncModeProvider);
    final syncStateBeforeSync = ref.read(pluralKitSyncProvider);
    if (_canCurrentSyncDrainDestructivePush(
      syncState: syncStateBeforeSync,
      mode: mode,
      direction: direction,
    )) {
      final confirmed = await _confirmPluralKitDeleteRisk();
      if (!mounted || !confirmed) return;
    }
    final summary = mode == PkSyncMode.liveFrontsOnly
        ? await ref
              .read(pluralKitSyncProvider.notifier)
              .syncLiveFrontersOnly(isManual: true, direction: direction)
        : await ref
              .read(pluralKitSyncProvider.notifier)
              .syncRecentData(isManual: true, direction: direction);
    if (!mounted) return;
    if (summary != null) {
      ref.read(pkLastSyncSummaryProvider.notifier).set(summary);
    }
    final syncState = ref.read(pluralKitSyncProvider);
    _startCooldownTimer(syncState);
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(pluralKitSyncProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.pluralkitTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // -- Section 1: PluralKit Account --
          _SectionHeader(title: context.l10n.pluralkitAccount),
          const SizedBox(height: 8),
          if (syncState.isConnected)
            _buildConnectedCard(syncState, theme)
          else
            _buildTokenInput(syncState, theme),

          if (syncState.syncError != null) ...[
            const SizedBox(height: 8),
            PrismSurface(
              fillColor: theme.colorScheme.errorContainer,
              borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    AppIcons.errorOutline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      syncState.syncError!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // -- Mapping gate banner --
          if (syncState.isConnected && syncState.needsMapping) ...[
            const SizedBox(height: 16),
            _buildMappingBanner(theme),
          ],

          // -- Section 2: Sync Direction --
          if (syncState.canAutoSync) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: context.l10n.pluralkitSyncDirection),
            const SizedBox(height: 8),
            _buildSyncDirectionSection(theme),
          ],

          // -- Section 2b: Auto-poll --
          if (syncState.canAutoSync) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: context.l10n.pluralkitAutoSyncSection),
            const SizedBox(height: 8),
            _buildAutoPollSection(theme),
          ],

          // -- Section 3: Sync Actions --
          if (syncState.canAutoSync) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: context.l10n.pluralkitSyncActions),
            const SizedBox(height: 8),
            if (syncState.isSyncing)
              _buildSyncProgress(syncState, theme)
            else
              _buildSyncActions(syncState, theme),
            const SizedBox(height: 8),
            PrismButton(
              label: context.l10n.pluralkitRerunMemberMapping,
              onPressed: _openMappingScreen,
              icon: AppIcons.people,
              tone: PrismButtonTone.outlined,
              expanded: true,
            ),
          ],

          // -- Section 4: Sync Summary --
          if (syncState.canAutoSync) ...[_buildSyncSummarySection()],

          // -- How It Works --
          const SizedBox(height: 24),
          _SectionHeader(title: context.l10n.pluralkitHowItWorks),
          const SizedBox(height: 8),
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: AppIcons.sync,
                  text: context.l10n.pluralkitInfoSync,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.lockOutline,
                  text: context.l10n.pluralkitInfoToken,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.people,
                  text: context.l10n.pluralkitInfoMembers(
                    readTerminology(context, ref).pluralLower,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: AppIcons.swapVert,
                  text: context.l10n.pluralkitInfoSwitches,
                ),
              ],
            ),
          ),

          // -- Troubleshooting --
          //
          // Sync activity log tile. Disabled when the log is empty (e.g.,
          // the user just landed on the screen and no sync has run yet) so
          // we don't navigate to an empty surface. As soon as the first
          // event lands in the ring buffer, the tile enables and the
          // subtitle flips to the "active" copy.
          const SizedBox(height: 24),
          _SectionHeader(title: context.l10n.syncTroubleshootingLink),
          const SizedBox(height: 8),
          const PrismSectionCard(
            padding: EdgeInsets.zero,
            child: _SyncActivityLogTile(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildConnectedCard(PluralKitSyncState syncState, ThemeData theme) {
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.checkCircle, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(
                context.l10n.pluralkitConnected,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (syncState.lastSyncDate != null) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.pluralkitLastSync(
                _formatDate(syncState.lastSyncDate!),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (syncState.lastManualSyncDate != null) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.pluralkitLastManualSync(
                _formatDate(syncState.lastManualSyncDate!),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _disconnect,
            icon: AppIcons.linkOff,
            label: context.l10n.pluralkitDisconnect,
            tone: PrismButtonTone.destructive,
            expanded: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTokenInput(PluralKitSyncState syncState, ThemeData theme) {
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrismTextField(
            controller: _tokenController,
            obscureText: true,
            labelText: context.l10n.pluralkitTokenLabel,
            hintText: context.l10n.pluralkitPasteTokenHint,
            isDense: true,
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _connect,
            icon: AppIcons.link,
            label: context.l10n.pluralkitConnect,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.pluralkitTokenHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.pluralkitFileImportHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _importFromFile,
            icon: AppIcons.fileUploadOutlined,
            label: context.l10n.pluralkitImportFromFile,
            tone: PrismButtonTone.outlined,
            expanded: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncProgress(PluralKitSyncState syncState, ThemeData theme) {
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: syncState.syncProgress > 0 ? syncState.syncProgress : null,
          ),
          const SizedBox(height: 12),
          Text(syncState.syncStatus, style: theme.textTheme.bodyMedium),
          if (syncState.syncProgress > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${(syncState.syncProgress * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncActions(PluralKitSyncState syncState, ThemeData theme) {
    final canSync = syncState.canManualSync && _cooldownSeconds <= 0;
    final mode = ref.watch(pkSyncModeProvider);

    return Column(
      children: [
        if (mode == PkSyncMode.fullSync) ...[
          PrismButton(
            onPressed: _importFromPK,
            icon: AppIcons.cloudDownload,
            label: context.l10n.pluralkitImportButton,
            tone: PrismButtonTone.filled,
            expanded: true,
            enabled: !syncState.isSyncing,
          ),
          const SizedBox(height: 8),
        ],
        PrismButton(
          onPressed: _syncRecent,
          icon: AppIcons.sync,
          label: _cooldownSeconds > 0
              ? context.l10n.pluralkitSyncRecentCooldown(_cooldownSeconds)
              : context.l10n.pluralkitSyncRecent,
          tone: PrismButtonTone.outlined,
          expanded: true,
          enabled: canSync,
        ),
        const SizedBox(height: 8),
        PrismButton(
          onPressed: _importFromFile,
          icon: AppIcons.fileUploadOutlined,
          label: context.l10n.pluralkitImportFromFile,
          tone: PrismButtonTone.outlined,
          expanded: true,
          enabled: !syncState.isSyncing,
        ),
        if (syncState.syncStatus.isNotEmpty && !syncState.isSyncing) ...[
          const SizedBox(height: 8),
          Text(
            syncState.syncStatus,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMappingBanner(ThemeData theme) {
    final terms = readTerminology(context, ref);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      accentColor: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.people, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.pluralkitMappingBannerTitle(terms.pluralLower),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.pluralkitMappingBannerBody(terms.singularLower),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _openMappingScreen,
            icon: AppIcons.link,
            label: context.l10n.pluralkitMappingBannerButton(terms.pluralLower),
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncDirectionSection(ThemeData theme) {
    final mode = ref.watch(pkSyncModeProvider);
    final direction = ref.watch(pkSyncDirectionProvider);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.pluralkitSyncModeDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrismSegmentedControl<PkSyncMode>(
              segments: [
                PrismSegment(
                  value: PkSyncMode.fullSync,
                  label: context.l10n.pluralkitSyncModeFullSync,
                ),
                PrismSegment(
                  value: PkSyncMode.liveFrontsOnly,
                  label: context.l10n.pluralkitSyncModeLiveFrontsOnly,
                ),
              ],
              selected: mode,
              onChanged: (next) {
                ref.read(pkSyncModeProvider.notifier).setMode(next);
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            mode == PkSyncMode.liveFrontsOnly
                ? context.l10n.pluralkitSyncModeLiveFrontsOnlyDescription
                : context.l10n.pluralkitSyncModeFullSyncDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.pluralkitSyncDirectionDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PkSyncDirectionPicker(
              selected: direction,
              onChanged: (d) {
                ref.read(pkSyncDirectionProvider.notifier).setDirection(d);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoPollSection(ThemeData theme) {
    final settingsAsync = ref.watch(pkAutoPollSettingsProvider);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: settingsAsync.when(
        loading: () => SizedBox(
          height: 48,
          child: Center(
            child: PrismSpinner(color: theme.colorScheme.primary, size: 20),
          ),
        ),
        error: (e, _) => Text(
          context.l10n.pluralkitAutoSyncLoadFailed,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        data: (settings) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.pluralkitAutoSyncTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.pluralkitAutoSyncDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: settings.enabled,
                  onChanged: (value) {
                    ref
                        .read(pkAutoPollSettingsProvider.notifier)
                        .setEnabled(value);
                  },
                ),
              ],
            ),
            if (settings.enabled) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.pluralkitAutoSyncIntervalLabel,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final seconds in pkAutoPollIntervalChoices)
                    PrismChip(
                      label: _formatInterval(seconds),
                      selected: settings.intervalSeconds == seconds,
                      onTap: () {
                        ref
                            .read(pkAutoPollSettingsProvider.notifier)
                            .setIntervalSeconds(seconds);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatInterval(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    return '${minutes}m';
  }

  Widget _buildSyncSummarySection() {
    final summary = ref.watch(pkLastSyncSummaryProvider);
    if (summary == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PkSyncSummaryCard(summary: summary),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return context.l10n.pluralkitJustNow;
    if (diff.inHours < 1) {
      return context.l10n.pluralkitMinutesAgo(diff.inMinutes);
    }
    if (diff.inDays < 1) return context.l10n.pluralkitHoursAgo(diff.inHours);
    return context.l10n.pluralkitDaysAgo(diff.inDays);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Entry-point tile for the PluralKit sync activity log.
///
/// Disabled (and `onTap` is null) while the in-memory ring buffer is empty;
/// the row's subtitle explains why so the dead state isn't silent. As soon
/// as any PK sync event lands in [pkSyncEventLogProvider], the tile flips
/// to enabled and the subtitle switches to the active copy.
class _SyncActivityLogTile extends ConsumerWidget {
  const _SyncActivityLogTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(pkSyncEventLogProvider);
    final hasEvents = events.isNotEmpty;
    return PrismListRow(
      leading: Icon(
        AppIcons.duotoneData,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(context.l10n.settingsPkSyncDebugOpenTile),
      subtitle: Text(
        hasEvents
            ? context.l10n.settingsPkSyncDebugOpenSubtitleActive
            : context.l10n.settingsPkSyncDebugOpenSubtitleEmpty,
      ),
      enabled: hasEvents,
      showChevron: true,
      onTap: hasEvents
          ? () => context.push(AppRoutePaths.settingsPluralkitSyncDebug)
          : null,
    );
  }
}
