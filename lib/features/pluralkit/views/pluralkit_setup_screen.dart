import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_group_repair_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_reset_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_file_import_screen.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_mapping_screen.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_group_repair_card.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_direction_picker.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_summary_card.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_system_profile_disclosure.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
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
      await _maybeShowProfileDisclosure();
    }
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
    await ref.read(pluralKitSyncProvider.notifier).performFullImport();
  }

  Future<void> _importFromFile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PkFileImportScreen()));
  }

  Future<void> _syncRecent() async {
    final direction = ref.read(pkSyncDirectionProvider);
    final summary = await ref
        .read(pluralKitSyncProvider.notifier)
        .syncRecentData(isManual: true, direction: direction);
    if (!mounted) return;
    if (summary != null) {
      ref.read(pkLastSyncSummaryProvider.notifier).set(summary);
    }
    final syncState = ref.read(pluralKitSyncProvider);
    _startCooldownTimer(syncState);
  }

  Future<void> _runGroupRepair({String? token}) async {
    final l10n = context.l10n;
    try {
      final report = await ref
          .read(pkGroupRepairControllerProvider.notifier)
          .run(token: token, allowStoredToken: token == null);
      if (!mounted) return;
      _showRepairToast(report);
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: l10n.pluralkitRepairFailedToast(
          _formatRepairError(error.toString()),
        ),
      );
    }
  }

  Future<void> _dismissGroupReview(String groupId) async {
    final l10n = context.l10n;
    await _runGroupReviewAction(
      () => ref
          .read(pkGroupRepairControllerProvider.notifier)
          .dismissReviewItem(groupId),
      successMessage: l10n.pluralkitRepairReviewDismissed,
      errorMessage: l10n.pluralkitRepairDismissReviewFailed,
    );
  }

  Future<void> _keepGroupLocalOnly(String groupId) async {
    final l10n = context.l10n;
    await _runGroupReviewAction(
      () => ref
          .read(pkGroupRepairControllerProvider.notifier)
          .keepReviewItemLocalOnly(groupId),
      successMessage: l10n.pluralkitRepairKeepLocalOnlySuccess,
      errorMessage: l10n.pluralkitRepairKeepLocalOnlyFailed,
    );
  }

  Future<void> _mergeGroupIntoCanonical(String groupId) async {
    final l10n = context.l10n;
    await _runGroupReviewAction(
      () => ref
          .read(pkGroupRepairControllerProvider.notifier)
          .mergeReviewItemIntoCanonical(groupId),
      successMessage: l10n.pluralkitRepairMergedSuccess,
      errorMessage: l10n.pluralkitRepairMergeFailed,
    );
  }

  Future<void> _runGroupReviewAction(
    Future<void> Function() action, {
    required String successMessage,
    required String Function(String error) errorMessage,
  }) async {
    try {
      await action();
      if (!mounted) return;
      PrismToast.success(context, message: successMessage);
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: errorMessage(_formatRepairError(error.toString())),
      );
    }
  }

  Future<void> _enablePkGroupSyncV2() async {
    final l10n = context.l10n;
    final repairState = ref.read(pkGroupRepairControllerProvider).asData?.value;
    final settings = ref.read(systemSettingsProvider).asData?.value;

    if (settings == null) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: l10n.pluralkitRepairCutoverSettingsLoadingError,
      );
      return;
    }

    if (settings.pkGroupSyncV2Enabled) {
      if (!mounted) return;
      PrismToast.show(
        context,
        message: l10n.pluralkitRepairCutoverAlreadyEnabled,
      );
      return;
    }

    if (repairState == null || repairState.isRunning) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: l10n.pluralkitRepairCutoverRepairLoadingError,
      );
      return;
    }

    if (repairState.lastReport == null) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: l10n.pluralkitRepairCutoverRunRepairFirstError,
      );
      return;
    }

    if (repairState.pendingReviewCount > 0) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: l10n.pluralkitRepairCutoverPendingReviewError(
          repairState.pendingReviewCount,
        ),
      );
      return;
    }

    try {
      await ref
          .read(systemSettingsRepositoryProvider)
          .updatePkGroupSyncV2Enabled(true);
      final syncHandle = ref.read(prismSyncHandleProvider).asData?.value;
      if (syncHandle != null) {
        await catchUpPkBackedSyncOnceAfterCutover(
          syncHandle,
          ref.read(databaseProvider),
        );
      }
      if (!mounted) return;
      PrismToast.success(
        context,
        message: l10n.pluralkitRepairCutoverEnabledSuccess,
      );
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: l10n.pluralkitRepairCutoverEnableFailed(
          _formatRepairError(error.toString()),
        ),
      );
    }
  }

  Future<void> _resetPkGroupsOnly() async {
    final l10n = context.l10n;
    final syncState = ref.read(pluralKitSyncProvider);

    try {
      final result = await ref
          .read(pkGroupResetServiceProvider)
          .resetPkGroupsOnly();
      ref.invalidate(pkGroupRepairControllerProvider);

      if (!mounted) return;

      if (!result.changedAnything) {
        PrismToast.show(
          context,
          message: l10n.pluralkitRepairResetNoGroupsNeeded,
        );
        return;
      }

      if (!syncState.isConnected) {
        PrismToast.success(
          context,
          message: l10n.pluralkitRepairResetFinishedReconnect(
            _pkGroupResetSummary(l10n, result),
          ),
        );
        return;
      }

      try {
        await ref.read(pluralKitSyncProvider.notifier).performFullImport();
        if (!mounted) return;
        PrismToast.success(
          context,
          message: l10n.pluralkitRepairResetFinishedReimported(
            _pkGroupResetSummary(l10n, result),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        PrismToast.show(
          context,
          message: l10n.pluralkitRepairResetFinishedReimportFailed(
            _formatRepairError(error.toString()),
            _pkGroupResetSummary(l10n, result),
          ),
          icon: AppIcons.warningAmberRounded,
          iconColor: Theme.of(context).colorScheme.secondary,
        );
      }
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: l10n.pluralkitRepairResetFailed(
          _formatRepairError(error.toString()),
        ),
      );
    }
  }

  void _openExportDataFirst() {
    context.push(AppRoutePaths.settingsImportExport);
  }

  Future<void> _promptForRepairTokenAndRun() async {
    final controller = TextEditingController();
    try {
      final token = await PrismDialog.show<String>(
        context: context,
        title: context.l10n.pluralkitRepairTemporaryTokenTitle,
        message: context.l10n.pluralkitRepairTemporaryTokenBody,
        builder: (dialogContext) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismTextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                labelText: context.l10n.pluralkitRepairTokenLabel,
                hintText: context.l10n.pluralkitRepairTokenHint,
                isDense: true,
                onSubmitted: (_) {
                  final trimmed = controller.text.trim();
                  if (trimmed.isEmpty) return;
                  Navigator.of(dialogContext).pop(trimmed);
                },
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.pluralkitRepairTemporaryTokenHelp,
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, value, child) {
                  return Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PrismButton(
                        label: context.l10n.cancel,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        tone: PrismButtonTone.outlined,
                      ),
                      PrismButton(
                        label: context.l10n.pluralkitRepairRunTokenBacked,
                        icon: AppIcons.autoFixHigh,
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(value.text.trim()),
                        enabled: value.text.trim().isNotEmpty,
                        tone: PrismButtonTone.filled,
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      );

      if (!mounted || token == null || token.trim().isEmpty) return;
      await _runGroupRepair(token: token.trim());
    } finally {
      controller.dispose();
    }
  }

  void _showRepairToast(PkGroupRepairReport report) {
    final l10n = context.l10n;
    final message = _repairSuccessMessage(l10n, report);
    if (report.referenceError != null || report.pendingReviewCount > 0) {
      PrismToast.show(
        context,
        message: message,
        icon: AppIcons.warningAmberRounded,
        iconColor: Theme.of(context).colorScheme.secondary,
      );
      return;
    }
    PrismToast.success(context, message: message);
  }

  String _repairSuccessMessage(
    AppLocalizations l10n,
    PkGroupRepairReport report,
  ) {
    final outcomeFragments = _repairOutcomeFragments(l10n, report);
    final detailMessage = outcomeFragments.isEmpty
        ? l10n.pluralkitRepairNoNewNeeded
        : '${_sentenceCase(_joinFragments(l10n, outcomeFragments))}.';
    final followUpMessage = _repairFollowUpMessage(l10n, report);

    if (report.referenceError != null) {
      if (followUpMessage != null) {
        return l10n.pluralkitRepairSuccessLocalLookupFailedWithFollowUp(
          detailMessage,
          followUpMessage,
        );
      }
      return l10n.pluralkitRepairSuccessLocalLookupFailed(detailMessage);
    }
    if (followUpMessage != null) {
      return l10n.pluralkitRepairSuccessWithFollowUp(
        detailMessage,
        followUpMessage,
      );
    }
    return l10n.pluralkitRepairSuccess(detailMessage);
  }

  List<String> _repairOutcomeFragments(
    AppLocalizations l10n,
    PkGroupRepairReport report,
  ) {
    final primary = <String>[
      if (report.parentReferencesRehomed > 0)
        l10n.pluralkitRepairSummaryUpdatedParentLinks(
          report.parentReferencesRehomed,
        ),
      if (report.entriesRehomed > 0)
        l10n.pluralkitRepairSummaryMovedMemberships(report.entriesRehomed),
      if (report.duplicateGroupsSoftDeleted > 0)
        l10n.pluralkitRepairSummaryRemovedDuplicateGroups(
          report.duplicateGroupsSoftDeleted,
        ),
      if (report.entryConflictsSoftDeleted > 0)
        l10n.pluralkitRepairSummaryRemovedConflictingMemberships(
          report.entryConflictsSoftDeleted,
        ),
      if (report.ambiguousGroupsSuppressed > 0)
        l10n.pluralkitRepairSummarySuppressedAmbiguousGroups(
          report.ambiguousGroupsSuppressed,
        ),
    ];
    if (primary.isNotEmpty) return primary;

    return <String>[
      if (report.backfilledEntries > 0)
        l10n.pluralkitRepairSummaryRestoredMissingMemberships(
          report.backfilledEntries,
        ),
      if (report.aliasesRecorded > 0)
        l10n.pluralkitRepairSummaryRecordedLegacyAliases(
          report.aliasesRecorded,
        ),
    ];
  }

  String? _repairFollowUpMessage(
    AppLocalizations l10n,
    PkGroupRepairReport report,
  ) {
    if (report.pendingReviewCount <= report.ambiguousGroupsSuppressed ||
        report.pendingReviewCount == 0) {
      return null;
    }

    return l10n.pluralkitRepairFollowUpPendingReview(report.pendingReviewCount);
  }

  String _joinFragments(AppLocalizations l10n, List<String> fragments) {
    if (fragments.length == 1) return fragments.first;
    if (fragments.length == 2) {
      return l10n.pluralkitRepairJoinPair(fragments.first, fragments.last);
    }

    final head = fragments.sublist(0, fragments.length - 1).join(', ');
    return l10n.pluralkitRepairJoinSerial(fragments.last, head);
  }

  String _sentenceCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _pkGroupResetSummary(
    AppLocalizations l10n,
    PkGroupResetResult result,
  ) {
    final fragments = <String>[
      if (result.groupsReset > 0)
        l10n.pluralkitRepairResetSummaryRemovedGroups(result.groupsReset),
      if (result.promotedChildGroups > 0)
        l10n.pluralkitRepairResetSummaryPromotedChildGroups(
          result.promotedChildGroups,
        ),
      if (result.deferredOpsCleared > 0)
        l10n.pluralkitRepairResetSummaryClearedDeferredOps(
          result.deferredOpsCleared,
        ),
    ];
    if (fragments.isEmpty) {
      return l10n.pluralkitRepairResetSummaryNoGroupsNeeded;
    }
    return '${_sentenceCase(_joinFragments(l10n, fragments))}.';
  }

  String _formatRepairError(String value) {
    return value
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pkGroupRepairBootstrapProvider);
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

          const SizedBox(height: 24),
          _SectionHeader(title: context.l10n.pluralkitRepairSection),
          const SizedBox(height: 8),
          _buildGroupRepairSection(syncState, theme),

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

    return Column(
      children: [
        PrismButton(
          onPressed: _importFromPK,
          icon: AppIcons.cloudDownload,
          label: context.l10n.pluralkitImportButton,
          tone: PrismButtonTone.filled,
          expanded: true,
          enabled: !syncState.isSyncing,
        ),
        const SizedBox(height: 8),
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

  Widget _buildGroupRepairSection(
    PluralKitSyncState syncState,
    ThemeData theme,
  ) {
    final repairStateAsync = ref.watch(pkGroupRepairControllerProvider);
    final hasStoredTokenAsync = ref.watch(pkGroupRepairHasStoredTokenProvider);
    final systemSettingsAsync = ref.watch(systemSettingsProvider);
    final hasStoredToken = syncState.isConnected
        ? true
        : hasStoredTokenAsync.asData?.value;
    final pkGroupSyncV2Enabled =
        systemSettingsAsync.asData?.value.pkGroupSyncV2Enabled;

    return repairStateAsync.when(
      loading: () => PrismSectionCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            PrismSpinner(color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.pluralkitRepairLoadingStatus,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      error: (error, _) => PkGroupRepairCard(
        state: PkGroupRepairState(
          error: context.l10n.pluralkitRepairStatusLoadFailed(
            _formatRepairError(error.toString()),
          ),
        ),
        isConnected: syncState.isConnected,
        hasStoredToken: hasStoredToken,
        pkGroupSyncV2Enabled: pkGroupSyncV2Enabled,
        onRunRepair: () => unawaited(_runGroupRepair()),
        onUseTemporaryToken: () => unawaited(_promptForRepairTokenAndRun()),
        onDismissReviewItem: _dismissGroupReview,
        onKeepReviewItemLocalOnly: _keepGroupLocalOnly,
        onMergeReviewItemIntoCanonical: _mergeGroupIntoCanonical,
        onEnablePkGroupSyncV2: _enablePkGroupSyncV2,
        onResetPkGroupsOnly: _resetPkGroupsOnly,
        onExportDataFirst: _openExportDataFirst,
      ),
      data: (repairState) => PkGroupRepairCard(
        state: repairState,
        isConnected: syncState.isConnected,
        hasStoredToken: hasStoredToken,
        pkGroupSyncV2Enabled: pkGroupSyncV2Enabled,
        onRunRepair: () => unawaited(_runGroupRepair()),
        onUseTemporaryToken: () => unawaited(_promptForRepairTokenAndRun()),
        onDismissReviewItem: _dismissGroupReview,
        onKeepReviewItemLocalOnly: _keepGroupLocalOnly,
        onMergeReviewItemIntoCanonical: _mergeGroupIntoCanonical,
        onEnablePkGroupSyncV2: _enablePkGroupSyncV2,
        onResetPkGroupsOnly: _resetPkGroupsOnly,
        onExportDataFirst: _openExportDataFirst,
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
    final direction = ref.watch(pkSyncDirectionProvider);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
