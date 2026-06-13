import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_current_fronters_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_first_sync_deferred_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_sync_event_log_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_file_import_screen.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_link_management_screen.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_mapping_screen.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_direction_picker.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_summary_card.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
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

  /// Expected length of a PluralKit token (`pk;token` emits a 64-character
  /// base64-ish string). Soft signal only: a mismatch shows an inline
  /// warning but never blocks submitting, since PK could change the format.
  static const int _pkTokenExpectedLength = 64;

  /// The token as it would be submitted: ALL whitespace stripped, including
  /// internal newlines that PDF viewers and email clients inject into
  /// copied tokens.
  String get _strippedToken =>
      _tokenController.text.replaceAll(RegExp(r'\s+'), '');

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke/paste so the token-length warning under the
    // field tracks the current input.
    _tokenController.addListener(_onTokenChanged);
  }

  void _onTokenChanged() {
    if (mounted) setState(() {});
  }

  /// True once the user has interacted with the direction picker, OR once a
  /// non-default preserved value has been loaded from a prior session.
  /// Gates the Continue button on the direction step — the wizard is meant
  /// to force the choice (see spec "direction-first"). Bug I3.
  bool _directionTouched = false;

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
    final token = _strippedToken;
    if (token.isEmpty) return;

    await ref.read(pluralKitSyncProvider.notifier).setToken(token);

    // Clear the field only once the auth result is known to be GOOD. The old
    // unconditional clear meant a 401 wiped the pasted token and forced a
    // full re-paste. setToken sets syncError
    // on every failure path and clears it on success, so a null syncError
    // here means the token validated and was persisted.
    if (!mounted) return;
    final syncState = ref.read(pluralKitSyncProvider);
    if (syncState.syncError == null) {
      _tokenController.clear();
    }

    // NOTE: profile disclosure no longer fires here. It moves to the mapping
    // screen's resolution path (T16) so the user picks a direction before any
    // disclosure prompt appears. The helper is left in place so T16 can call
    // it from the mapping screen.
  }

  Widget _buildDirectionStep(ThemeData theme) {
    final mode = ref.watch(pkSyncModeProvider);
    final direction = ref.watch(pkSyncDirectionProvider);
    final sleepBehavior = ref.watch(pkSleepSyncBehaviorProvider);
    // Pre-mark touched if the user had previously persisted a non-default
    // direction (resumed from a prior session). The provider defaults to
    // `pullOnly` until `load()` resolves — once it does, any non-default
    // value reflects a deliberate prior choice. This avoids forcing a
    // re-tap for users who already picked something. See bug I3.
    if (!_directionTouched && direction != PkSyncDirection.pullOnly) {
      // Defer the state change out of build to avoid setState-in-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_directionTouched) {
          setState(() => _directionTouched = true);
        }
      });
    }
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.pluralkitDirectionStepHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Mode segmented control
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
          const SizedBox(height: 8),
          Text(
            mode == PkSyncMode.liveFrontsOnly
                ? context.l10n.pluralkitModeLiveOnlyCaption
                : context.l10n.pluralkitModeFullSyncCaption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // Direction picker
          SizedBox(
            width: double.infinity,
            child: PkSyncDirectionPicker(
              selected: direction,
              onChanged: (d) {
                if (!_directionTouched) {
                  setState(() => _directionTouched = true);
                }
                ref.read(pkSyncDirectionProvider.notifier).setDirection(d);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.pluralkitDirectionCaption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildSleepSyncBehaviorPicker(theme, sleepBehavior),
          const SizedBox(height: 16),
          // Continue button advances the direction gate. Disabled until the
          // user has interacted with the picker (or a non-default preserved
          // value was loaded). The whole point of the direction step is to
          // force the choice — see spec "direction-first" / bug I3.
          PrismButton(
            onPressed: () async {
              await ref.read(pluralKitSyncProvider.notifier).confirmDirection();
            },
            enabled: _directionTouched,
            label: context.l10n.pluralkitDirectionContinue,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMigrationBlockedNotice(ThemeData theme) {
    return PrismSurface(
      fillColor: theme.colorScheme.errorContainer,
      borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            AppIcons.warningAmber,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.pluralkitMigrationBlockedNotice,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPullOnlyHeadsUp(ThemeData theme) {
    final frontersAsync = ref.watch(pkCurrentFrontersProvider);

    // While loading, show nothing (avoids layout shift).
    if (frontersAsync is AsyncLoading) return const SizedBox.shrink();

    // On error or null result, suppress the banner entirely.
    final pkSwitch = frontersAsync.value;
    if (pkSwitch == null) return const SizedBox.shrink();

    // An empty switch (nobody currently fronting in PK) — no banner needed.
    if (pkSwitch.members.isEmpty) return const SizedBox.shrink();

    // Resolve display names from the rich memberDetails if available;
    // fall back to the 5-char short ID so we never show a blank name.
    final names = pkSwitch.memberDetails.isNotEmpty
        ? pkSwitch.memberDetails
              .map((m) => m.displayName ?? m.name ?? m.id)
              .join(', ')
        : pkSwitch.members.join(', ');

    return PrismSurface(
      fillColor: theme.colorScheme.secondaryContainer,
      borderColor: theme.colorScheme.secondary.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            AppIcons.sync,
            color: theme.colorScheme.onSecondaryContainer,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.pluralkitPullOnlyHeadsUp(names),
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeferredSyncBannerIfNeeded(ThemeData theme) {
    final deferredAsync = ref.watch(pkFirstSyncDeferredProvider);
    return deferredAsync.when(
      loading: () => const SizedBox.shrink(),
      // ignore: avoid_unused_parameters
      error: (e, s) => const SizedBox.shrink(),
      data: (isDeferred) {
        if (!isDeferred) return const SizedBox.shrink();
        return Column(
          children: [
            PrismSurface(
              fillColor: theme.colorScheme.tertiaryContainer,
              borderColor: theme.colorScheme.tertiary.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    AppIcons.sync,
                    color: theme.colorScheme.onTertiaryContainer,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.pluralkitFirstSyncDeferred,
                      style: TextStyle(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: theme.colorScheme.onTertiaryContainer,
                    onPressed: () {
                      ref.read(pkFirstSyncDeferredProvider.notifier).clear();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
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
    // F03: switch-level removals (full DELETEs + live-referenced member-removal
    // PATCHes) share the "switches" line — both remove PluralKit switch data.
    final switchRemovals =
        preview.switchesToDelete + preview.switchMemberRemovals;
    final items = <String>[
      if (preview.membersToDelete > 0)
        context.l10n.pluralkitDeleteRiskMembers(preview.membersToDelete),
      if (switchRemovals > 0)
        context.l10n.pluralkitDeleteRiskSwitches(switchRemovals),
      if (preview.groupMembershipsToRemove > 0)
        context.l10n.pluralkitDeleteRiskGroupMemberships(
          preview.groupMembershipsToRemove,
        ),
      if (preview.memberProxyTagsToRemove > 0)
        context.l10n.pluralkitDeleteRiskProxyTags(
          preview.memberProxyTagsToRemove,
        ),
    ];

    if (items.length <= 1) return items.isEmpty ? '' : items.first;
    if (items.length == 2) {
      return context.l10n.pluralkitDeleteRiskJoinTwo(items[0], items[1]);
    }
    if (items.length == 3) {
      return context.l10n.pluralkitDeleteRiskJoinThree(
        items[0],
        items[1],
        items[2],
      );
    }
    final head = items.take(items.length - 1).join(', ');
    return context.l10n.pluralkitDeleteRiskJoinTwo(head, items.last);
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

  Future<void> _openLinkManagementScreen() async {
    // Invalidate so the management screen fetches fresh PK data and locals.
    ref.invalidate(pkLinkManagementControllerProvider);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PkLinkManagementScreen(),
      ),
    );
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
    final migrationBlocked = ref.watch(frontingMigrationWritesBlockedProvider);

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

          // -- Migration-blocked notice --
          // When the fronting migration is blocking writes AND the wizard is
          // in progress (direction or mapping step), show a notice in place of
          // the wizard sections. Steady-state sections (canAutoSync) render
          // normally since those writes are also gated at the service layer.
          if (migrationBlocked &&
              (syncState.needsDirection || syncState.needsMapping)) ...[
            const SizedBox(height: 16),
            _buildMigrationBlockedNotice(theme),
          ] else ...[
            // -- Direction step (gated on needsDirection) --
            if (syncState.needsDirection) ...[
              const SizedBox(height: 24),
              _SectionHeader(title: context.l10n.pluralkitDirectionStepHeading),
              const SizedBox(height: 8),
              _buildDirectionStep(theme),
            ],

            // -- Mapping gate banner (gated on needsMapping) --
            if (syncState.needsMapping) ...[
              const SizedBox(height: 16),
              _buildMappingBanner(theme),

              // Pull-only heads-up: shown when direction is pullOnly AND
              // mapping is pending. The banner is driven by live PK fronter
              // data from pkCurrentFrontersProvider; it suppresses itself
              // when the fetch fails or returns an empty switch.
              if (ref.watch(pkSyncDirectionProvider) ==
                  PkSyncDirection.pullOnly) ...[
                const SizedBox(height: 8),
                _buildPullOnlyHeadsUp(theme),
              ],
            ],
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
            // Deferred-sync banner: shown when the user tapped "Decide later"
            // in the Who's fronting? sheet (T10 writes the prefs flag).
            _buildDeferredSyncBannerIfNeeded(theme),
            if (syncState.isSyncing)
              _buildSyncProgress(syncState, theme)
            else
              _buildSyncActions(syncState, theme),
            const SizedBox(height: 16),
            _buildSyncNavigationRows(theme),
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
          // Soft warning when the (whitespace-stripped) input doesn't look
          // like a PK token. Submitting stays allowed — see
          // [_pkTokenExpectedLength].
          if (_strippedToken.isNotEmpty &&
              _strippedToken.length != _pkTokenExpectedLength) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.pluralkitTokenLengthWarning(
                _strippedToken.length,
                _pkTokenExpectedLength,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade700,
              ),
            ),
          ],
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

  Widget _buildSyncNavigationRows(ThemeData theme) {
    return PrismSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          PrismListRow(
            key: const ValueKey('pkLinkManagementEntryRow'),
            leading: Icon(AppIcons.link, color: theme.colorScheme.primary),
            title: Text(context.l10n.pkLinkManagementEntryRowTitle),
            subtitle: Text(context.l10n.pkLinkManagementEntryRowSubtitle),
            showChevron: true,
            onTap: _openLinkManagementScreen,
          ),
          PrismListRow(
            key: const ValueKey('pkMapNewMembersEntryRow'),
            leading: Icon(AppIcons.people, color: theme.colorScheme.primary),
            title: Text(context.l10n.pkMapNewMembersEntryRowTitle),
            subtitle: Text(context.l10n.pkMapNewMembersEntryRowSubtitle),
            showChevron: true,
            onTap: _openMappingScreen,
          ),
          PrismListRow(
            key: const ValueKey('pkImportFromFileEntryRow'),
            leading: Icon(
              AppIcons.fileUploadOutlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(context.l10n.pluralkitImportFromFile),
            subtitle: Text(context.l10n.pkImportFromFileEntryRowSubtitle),
            showChevron: true,
            onTap: _importFromFile,
          ),
        ],
      ),
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
    final sleepBehavior = ref.watch(pkSleepSyncBehaviorProvider);
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
          const SizedBox(height: 16),
          _buildSleepSyncBehaviorPicker(theme, sleepBehavior),
        ],
      ),
    );
  }

  Widget _buildSleepSyncBehaviorPicker(
    ThemeData theme,
    PkSleepSyncBehavior sleepBehavior,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.pluralkitSleepSyncBehaviorDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: PrismSegmentedControl<PkSleepSyncBehavior>(
            segments: [
              PrismSegment(
                value: PkSleepSyncBehavior.clearFronters,
                label: context.l10n.pluralkitSleepSyncClearFronters,
              ),
              PrismSegment(
                value: PkSleepSyncBehavior.leaveUnchanged,
                label: context.l10n.pluralkitSleepSyncLeaveUnchanged,
              ),
            ],
            selected: sleepBehavior,
            onChanged: (next) {
              ref.read(pkSleepSyncBehaviorProvider.notifier).setBehavior(next);
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sleepBehavior == PkSleepSyncBehavior.leaveUnchanged
              ? context.l10n.pluralkitSleepSyncLeaveUnchangedDescription
              : context.l10n.pluralkitSleepSyncClearFrontersDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
