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

    setState(() => _cooldownSeconds = remaining);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
    if (summary != null) {
      ref.read(pkLastSyncSummaryProvider.notifier).set(summary);
    }
    final syncState = ref.read(pluralKitSyncProvider);
    _startCooldownTimer(syncState);
  }

  Future<void> _runGroupRepair({String? token}) async {
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
        message:
            'PluralKit group repair failed: ${_formatRepairError(error.toString())}',
      );
    }
  }

  Future<void> _dismissGroupReview(String groupId) async {
    await _runGroupReviewAction(
      () => ref
          .read(pkGroupRepairControllerProvider.notifier)
          .dismissReviewItem(groupId),
      successMessage: 'Group review dismissed. Sync suppression was cleared.',
      errorPrefix: 'Could not dismiss this repair review item',
    );
  }

  Future<void> _keepGroupLocalOnly(String groupId) async {
    await _runGroupReviewAction(
      () => ref
          .read(pkGroupRepairControllerProvider.notifier)
          .keepReviewItemLocalOnly(groupId),
      successMessage: 'Group kept local-only. It will stay out of sync.',
      errorPrefix: 'Could not keep this group local-only',
    );
  }

  Future<void> _mergeGroupIntoCanonical(String groupId) async {
    await _runGroupReviewAction(
      () => ref
          .read(pkGroupRepairControllerProvider.notifier)
          .mergeReviewItemIntoCanonical(groupId),
      successMessage: 'Group merged into the canonical PK-backed group.',
      errorPrefix: 'Could not merge this group into the canonical PK group',
    );
  }

  Future<void> _runGroupReviewAction(
    Future<void> Function() action, {
    required String successMessage,
    required String errorPrefix,
  }) async {
    try {
      await action();
      if (!mounted) return;
      PrismToast.success(context, message: successMessage);
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: '$errorPrefix: ${_formatRepairError(error.toString())}',
      );
    }
  }

  Future<void> _enablePkGroupSyncV2() async {
    final repairState = ref.read(pkGroupRepairControllerProvider).asData?.value;
    final settings = ref.read(systemSettingsProvider).asData?.value;

    if (settings == null) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message:
            'Could not verify the shared cutover setting yet. Wait for repair '
            'status to finish loading and try again.',
      );
      return;
    }

    if (settings.pkGroupSyncV2Enabled) {
      if (!mounted) return;
      PrismToast.show(
        context,
        message: 'PK group sync v2 is already enabled for this sync group.',
      );
      return;
    }

    if (repairState == null || repairState.isRunning) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message:
            'Repair status is still loading or running. Wait for it to '
            'finish before enabling PK group sync v2.',
      );
      return;
    }

    if (repairState.lastReport == null) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message:
            'Run PluralKit group repair first. PK group sync v2 stays off '
            'until this client completes a repair pass.',
      );
      return;
    }

    if (repairState.pendingReviewCount > 0) {
      if (!mounted) return;
      final noun = repairState.pendingReviewCount == 1 ? 'item' : 'items';
      PrismToast.error(
        context,
        message:
            'Resolve or keep local-only the ${repairState.pendingReviewCount} '
            'pending review $noun before enabling PK group sync v2.',
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
        message:
            'PK group sync v2 enabled for this sync group. Manual/local-only '
            'groups are unchanged.',
      );
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message:
            'Could not enable PK group sync v2: '
            '${_formatRepairError(error.toString())}',
      );
    }
  }

  Future<void> _resetPkGroupsOnly() async {
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
          message:
              'No PK-backed or repair-suppressed groups needed reset on this '
              'device.',
        );
        return;
      }

      if (!syncState.isConnected) {
        PrismToast.success(
          context,
          message:
              'PK group reset finished. ${_pkGroupResetSummary(result)} '
              'Reconnect PluralKit or import from a file to rebuild them.',
        );
        return;
      }

      try {
        await ref.read(pluralKitSyncProvider.notifier).performFullImport();
        if (!mounted) return;
        PrismToast.success(
          context,
          message:
              'PK group reset finished. ${_pkGroupResetSummary(result)} '
              'Current PK groups were re-imported.',
        );
      } catch (error) {
        if (!mounted) return;
        PrismToast.show(
          context,
          message:
              'PK group reset finished, but re-import failed: '
              '${_formatRepairError(error.toString())}. '
              '${_pkGroupResetSummary(result)}',
          icon: AppIcons.warningAmberRounded,
          iconColor: Theme.of(context).colorScheme.secondary,
        );
      }
    } catch (error) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message:
            'Could not reset PK groups: '
            '${_formatRepairError(error.toString())}',
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
        title: 'Temporary PluralKit token',
        message:
            'Use a one-off token for this repair run only. Prism will not save '
            'it or reconnect sync automatically.',
        builder: (dialogContext) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismTextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                labelText: 'PluralKit token',
                hintText: 'Paste a temporary token',
                isDense: true,
                onSubmitted: (_) {
                  final trimmed = controller.text.trim();
                  if (trimmed.isEmpty) return;
                  Navigator.of(dialogContext).pop(trimmed);
                },
              ),
              const SizedBox(height: 12),
              Text(
                'This token is only used to compare your local groups against '
                'current PluralKit groups during repair.',
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
                        label: 'Run token-backed repair',
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
    final message = _repairSuccessMessage(report);
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

  String _repairSuccessMessage(PkGroupRepairReport report) {
    final outcomeFragments = _repairOutcomeFragments(report);
    final detailMessage = outcomeFragments.isEmpty
        ? 'No new PK group repairs were needed.'
        : '${_sentenceCase(_joinFragments(outcomeFragments))}.';
    final followUpMessage = _repairFollowUpMessage(report);

    if (report.referenceError != null) {
      final followUpSuffix = followUpMessage == null ? '' : ' $followUpMessage';
      return 'Repair finished locally. $detailMessage$followUpSuffix Live PK '
          'lookup failed, so a token-backed rerun is still recommended.';
    }
    if (followUpMessage != null) {
      return 'Repair finished. $detailMessage $followUpMessage';
    }
    return 'Repair finished. $detailMessage';
  }

  List<String> _repairOutcomeFragments(PkGroupRepairReport report) {
    final primary = <String>[
      if (report.parentReferencesRehomed > 0)
        'updated ${_countPhrase(report.parentReferencesRehomed, "child-group parent link", "child-group parent links")}',
      if (report.entriesRehomed > 0)
        'moved ${_countPhrase(report.entriesRehomed, "group membership", "group memberships")}',
      if (report.duplicateGroupsSoftDeleted > 0)
        'removed ${_countPhrase(report.duplicateGroupsSoftDeleted, "duplicate local group", "duplicate local groups")}',
      if (report.entryConflictsSoftDeleted > 0)
        'removed ${_countPhrase(report.entryConflictsSoftDeleted, "conflicting group membership", "conflicting group memberships")}',
      if (report.ambiguousGroupsSuppressed > 0)
        'suppressed ${_countPhrase(report.ambiguousGroupsSuppressed, "ambiguous group", "ambiguous groups")} for review',
    ];
    if (primary.isNotEmpty) return primary;

    return <String>[
      if (report.backfilledEntries > 0)
        'restored ${_countPhrase(report.backfilledEntries, "missing PK membership link", "missing PK membership links")}',
      if (report.aliasesRecorded > 0)
        'recorded ${_countPhrase(report.aliasesRecorded, "legacy group alias", "legacy group aliases")}',
    ];
  }

  String? _repairFollowUpMessage(PkGroupRepairReport report) {
    if (report.pendingReviewCount <= report.ambiguousGroupsSuppressed ||
        report.pendingReviewCount == 0) {
      return null;
    }

    final noun = report.pendingReviewCount == 1 ? 'group' : 'groups';
    return '${report.pendingReviewCount} suppressed $noun still need '
        'follow-up review.';
  }

  String _countPhrase(int count, String singular, String plural) {
    final noun = count == 1 ? singular : plural;
    return '$count $noun';
  }

  String _joinFragments(List<String> fragments) {
    if (fragments.length == 1) return fragments.first;
    if (fragments.length == 2) {
      return '${fragments.first} and ${fragments.last}';
    }

    final head = fragments.sublist(0, fragments.length - 1).join(', ');
    return '$head, and ${fragments.last}';
  }

  String _sentenceCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _pkGroupResetSummary(PkGroupResetResult result) {
    final fragments = <String>[
      if (result.groupsReset > 0)
        'removed ${_countPhrase(result.groupsReset, "PK-backed or suppressed group", "PK-backed or suppressed groups")}',
      if (result.promotedChildGroups > 0)
        'promoted ${_countPhrase(result.promotedChildGroups, "local child group", "local child groups")} to root',
      if (result.deferredOpsCleared > 0)
        'cleared ${_countPhrase(result.deferredOpsCleared, "deferred PK membership op", "deferred PK membership ops")}',
    ];
    if (fragments.isEmpty) {
      return 'No PK-backed groups needed reset.';
    }
    return '${_sentenceCase(_joinFragments(fragments))}.';
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
          const _SectionHeader(title: 'Group repair'),
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
            // TODO(l10n)
            const _SectionHeader(title: 'Auto-sync'),
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
              // TODO(l10n)
              label: 'Re-run member mapping',
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
                  text: context.l10n.pluralkitInfoMembers,
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
          PrismButton(
            onPressed: _importFromFile,
            icon: AppIcons.fileUploadOutlined,
            // TODO(l10n)
            label: 'Import from pk;export file',
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
          // TODO(l10n)
          label: 'Import from pk;export file',
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
                'Loading repair status...',
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
          error:
              'Could not load repair status: ${_formatRepairError(error.toString())}',
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
                  // TODO(l10n)
                  'One more step: link your members',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // TODO(l10n)
            "You're connected. Before sync turns on, match each PluralKit "
            'member to a member in Prism — or import them as new. This '
            'prevents duplicates and keeps switch history attached to the '
            'right person.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: _openMappingScreen,
            icon: AppIcons.link,
            // TODO(l10n)
            label: 'Link members',
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
          'Could not load auto-sync settings.',
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
                        'Pull new switches automatically',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'While Prism is open, check PluralKit for new '
                        'switches on an interval. Pauses in the background.',
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
              Text('Check every', style: theme.textTheme.labelLarge),
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
