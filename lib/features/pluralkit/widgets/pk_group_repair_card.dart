import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/pluralkit/providers/pk_group_repair_provider.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

class PkGroupRepairCard extends StatelessWidget {
  const PkGroupRepairCard({
    super.key,
    required this.state,
    required this.isConnected,
    required this.hasStoredToken,
    required this.onRunRepair,
    required this.onDismissReviewItem,
    required this.onKeepReviewItemLocalOnly,
    required this.onMergeReviewItemIntoCanonical,
    required this.pkGroupSyncV2Enabled,
    required this.onEnablePkGroupSyncV2,
    required this.onResetPkGroupsOnly,
    required this.onExportDataFirst,
    this.onUseTemporaryToken,
  });

  final PkGroupRepairState state;
  final bool isConnected;
  final bool? hasStoredToken;
  final VoidCallback onRunRepair;
  final Future<void> Function(String groupId) onDismissReviewItem;
  final Future<void> Function(String groupId) onKeepReviewItemLocalOnly;
  final Future<void> Function(String groupId) onMergeReviewItemIntoCanonical;
  final bool? pkGroupSyncV2Enabled;
  final Future<void> Function() onEnablePkGroupSyncV2;
  final Future<void> Function() onResetPkGroupsOnly;
  final VoidCallback onExportDataFirst;
  final VoidCallback? onUseTemporaryToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final report = state.lastReport;
    final repairDetailLines = report == null
        ? const <String>[]
        : _repairDetailLines(l10n, report);
    final statusTone = _statusTone(theme);
    final primaryLabel = hasStoredToken == false
        ? l10n.pluralkitRepairRunLocal
        : l10n.pluralkitRepairRun;
    final showTemporaryTokenAction =
        onUseTemporaryToken != null &&
        (hasStoredToken != true || report?.referenceError != null);
    final showResetPkGroupsOnlyAction =
        !state.isRunning &&
        (state.pendingReviewCount > 0 ||
            report?.requiresReconnectForMissingPkGroupIdentity == true);
    final resetLabel = isConnected
        ? l10n.pluralkitRepairResetAndReimport
        : l10n.pluralkitRepairResetOnly;
    final enablementColor = _enablementColor(theme);
    final enablementIcon = _enablementIcon();
    final referenceRecommendation = _referenceRecommendation(l10n);
    final referenceError = report?.referenceError;
    final referenceErrorText = referenceError == null
        ? null
        : l10n.pluralkitRepairReferenceError(_compactError(referenceError));
    final repairErrorText = state.error == null
        ? null
        : l10n.pluralkitRepairError(_compactError(state.error!));

    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      accentColor: statusTone.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RepairCardHeader(
            statusTone: statusTone,
            title: l10n.pluralkitRepairCardTitle,
            headline: _headline(l10n, report),
          ),
          _RepairStatusChips(
            statusLabel: _statusChipLabel(l10n),
            statusColor: statusTone.color,
            tokenLabel: _tokenChipLabel(l10n),
            tokenSelected: hasStoredToken == true,
            tokenTintColor: hasStoredToken == true
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
            lastRunModeLabel: report == null
                ? null
                : _lastRunModeLabel(l10n, report.referenceMode),
            lastRunModeColor: theme.colorScheme.tertiary,
            enablementLabel: _enablementChipLabel(l10n),
            enablementSelected: pkGroupSyncV2Enabled == true,
            enablementColor: enablementColor,
          ),
          _RepairStatusRows(
            statusTone: statusTone,
            currentStatusLabel: l10n.pluralkitRepairCurrentStatus,
            currentStatusText: _currentStatusText(l10n, report),
            pendingReviewCount: state.pendingReviewCount,
            pendingReviewLabel: l10n.pluralkitRepairPendingReview,
            pendingReviewText: _pendingReviewText(l10n),
          ),
          if (state.pendingReviewItems.isNotEmpty)
            _PendingReviewItemsSection(
              items: state.pendingReviewItems,
              isRunning: state.isRunning,
              onMergeReviewItemIntoCanonical: onMergeReviewItemIntoCanonical,
              onKeepReviewItemLocalOnly: onKeepReviewItemLocalOnly,
              onDismissReviewItem: onDismissReviewItem,
            ),
          if (report != null)
            _RepairLastRunSection(
              title: l10n.pluralkitRepairLastRun,
              summary: _lastRunSummary(l10n, report),
              detailTitle: l10n.pluralkitRepairWhatChanged,
              detailLines: repairDetailLines,
            ),
          if (referenceRecommendation != null)
            _ReferenceRecommendationSurface(
              recommendation: referenceRecommendation,
            ),
          if (referenceErrorText != null)
            _RepairMessageSurface(
              message: referenceErrorText,
              icon: AppIcons.warningAmberRounded,
              fillColor: theme.colorScheme.secondaryContainer,
              borderColor: theme.colorScheme.secondary.withValues(alpha: 0.28),
              contentColor: theme.colorScheme.onSecondaryContainer,
            ),
          if (repairErrorText != null)
            _RepairMessageSurface(
              message: repairErrorText,
              icon: AppIcons.errorOutline,
              fillColor: theme.colorScheme.errorContainer,
              borderColor: theme.colorScheme.error.withValues(alpha: 0.28),
              contentColor: theme.colorScheme.onErrorContainer,
            ),
          _RepairCutoverSection(
            accentColor: enablementColor,
            icon: enablementIcon,
            title: l10n.pluralkitRepairCutoverTitle,
            headline: _enablementHeadline(l10n),
            statusTitle: l10n.pluralkitRepairSharedEnablement,
            statusText: _enablementStatusText(l10n),
            recommendation: _enablementRecommendation(l10n),
            canEnable: _canEnablePkGroupSyncV2,
            enableLabel: l10n.pluralkitRepairEnablePkGroupSync,
            onEnablePressed: () =>
                unawaited(_confirmEnablePkGroupSyncV2(context)),
          ),
          _RepairActionButtons(
            primaryLabel: primaryLabel,
            isRunning: state.isRunning,
            onRunRepair: onRunRepair,
            showTemporaryTokenAction: showTemporaryTokenAction,
            temporaryTokenLabel: l10n.pluralkitRepairUseTemporaryToken,
            onUseTemporaryToken: onUseTemporaryToken,
            showResetPkGroupsOnlyAction: showResetPkGroupsOnlyAction,
            resetLabel: resetLabel,
            onResetPkGroupsOnly: () =>
                unawaited(_confirmResetPkGroupsOnly(context)),
          ),
        ],
      ),
    );
  }

  _RepairStatusTone _statusTone(ThemeData theme) {
    if (state.isRunning) {
      return _RepairStatusTone(
        color: theme.colorScheme.primary,
        icon: AppIcons.autoFixHigh,
      );
    }
    if (state.error != null) {
      return _RepairStatusTone(
        color: theme.colorScheme.error,
        icon: AppIcons.errorOutline,
      );
    }
    if (state.pendingReviewCount > 0) {
      return _RepairStatusTone(
        color: theme.colorScheme.secondary,
        icon: AppIcons.warningAmberRounded,
      );
    }
    return _RepairStatusTone(
      color: theme.colorScheme.primary,
      icon: AppIcons.buildCircleOutlined,
    );
  }

  bool get _canEnablePkGroupSyncV2 =>
      pkGroupSyncV2Enabled == false &&
      !state.isRunning &&
      state.lastReport != null &&
      state.pendingReviewCount == 0;

  String _headline(AppLocalizations l10n, PkGroupRepairReport? report) {
    if (state.isRunning) {
      return l10n.pluralkitRepairHeadlineRunning;
    }
    if (state.pendingReviewCount > 0) {
      return l10n.pluralkitRepairHeadlinePending;
    }
    if (report?.requiresReconnectForMissingPkGroupIdentity == true) {
      return l10n.pluralkitRepairHeadlineReconnectRequired;
    }
    if (report != null && _hasRepairChanges(report)) {
      return l10n.pluralkitRepairHeadlineChanged;
    }
    if (report != null) {
      return l10n.pluralkitRepairHeadlineCompleted;
    }
    return l10n.pluralkitRepairHeadlineDefault;
  }

  String _statusChipLabel(AppLocalizations l10n) {
    if (state.isRunning) return l10n.pluralkitRepairStatusRunning;
    if (state.error != null) return l10n.pluralkitRepairStatusRetryNeeded;
    if (state.pendingReviewCount > 0) {
      return l10n.pluralkitRepairStatusPendingReview(state.pendingReviewCount);
    }
    if (state.lastReport != null) {
      return l10n.pluralkitRepairStatusLastRunComplete;
    }
    return l10n.pluralkitRepairStatusReadyToRun;
  }

  String _tokenChipLabel(AppLocalizations l10n) {
    if (hasStoredToken == true) return l10n.pluralkitRepairTokenBackedReady;
    if (hasStoredToken == false) return l10n.pluralkitRepairLocalOnlyUntilToken;
    return l10n.pluralkitRepairCheckingTokenAccess;
  }

  String _enablementChipLabel(AppLocalizations l10n) {
    if (pkGroupSyncV2Enabled == true) {
      return l10n.pluralkitRepairCutoverEnabledChip;
    }
    if (pkGroupSyncV2Enabled == false) {
      return l10n.pluralkitRepairCutoverOffChip;
    }
    return l10n.pluralkitRepairCheckingCutover;
  }

  String _currentStatusText(
    AppLocalizations l10n,
    PkGroupRepairReport? report,
  ) {
    if (state.isRunning) {
      return l10n.pluralkitRepairCurrentRunning;
    }
    if (state.error != null) {
      return l10n.pluralkitRepairCurrentError;
    }
    if (state.pendingReviewCount > 0) {
      return l10n.pluralkitRepairCurrentPending(state.pendingReviewCount);
    }
    if (report == null) {
      return l10n.pluralkitRepairCurrentNoRun;
    }
    if (report.requiresReconnectForMissingPkGroupIdentity) {
      return l10n.pluralkitRepairCurrentReconnectRequired;
    }
    if (_hasRepairChanges(report)) {
      return l10n.pluralkitRepairCurrentChanged;
    }
    return l10n.pluralkitRepairCurrentNoChanges;
  }

  String _enablementHeadline(AppLocalizations l10n) {
    if (pkGroupSyncV2Enabled == true) {
      return l10n.pluralkitRepairCutoverHeadlineEnabled;
    }
    if (_canEnablePkGroupSyncV2) {
      return l10n.pluralkitRepairCutoverHeadlineReady;
    }
    return l10n.pluralkitRepairCutoverHeadlineBlocked;
  }

  String _enablementStatusText(AppLocalizations l10n) {
    if (pkGroupSyncV2Enabled == null) {
      return l10n.pluralkitRepairCutoverStatusLoading;
    }
    if (pkGroupSyncV2Enabled == true) {
      return l10n.pluralkitRepairCutoverStatusEnabled;
    }
    if (state.isRunning) {
      return l10n.pluralkitRepairCutoverStatusRunning;
    }
    if (state.lastReport == null) {
      return l10n.pluralkitRepairCutoverStatusNoRun;
    }
    if (state.pendingReviewCount > 0) {
      return l10n.pluralkitRepairCutoverStatusPending;
    }
    return l10n.pluralkitRepairCutoverStatusReady;
  }

  String? _enablementRecommendation(AppLocalizations l10n) {
    if (pkGroupSyncV2Enabled == null) return null;
    if (pkGroupSyncV2Enabled == true) {
      return l10n.pluralkitRepairCutoverRecommendationEnabled;
    }
    if (state.lastReport == null) {
      return l10n.pluralkitRepairCutoverRecommendationRunFirst;
    }
    if (state.pendingReviewCount > 0) {
      return l10n.pluralkitRepairCutoverRecommendationPending;
    }
    return l10n.pluralkitRepairCutoverRecommendationReady;
  }

  String _pendingReviewText(AppLocalizations l10n) {
    if (state.pendingReviewCount == 0) {
      return l10n.pluralkitRepairPendingNone;
    }
    return l10n.pluralkitRepairPendingCount(state.pendingReviewCount);
  }

  String _lastRunModeLabel(
    AppLocalizations l10n,
    PkGroupRepairReferenceMode mode,
  ) {
    return switch (mode) {
      PkGroupRepairReferenceMode.none => l10n.pluralkitRepairModeLocalOnlyRun,
      PkGroupRepairReferenceMode.storedToken =>
        l10n.pluralkitRepairModeStoredTokenRun,
      PkGroupRepairReferenceMode.providedToken =>
        l10n.pluralkitRepairModeTemporaryTokenRun,
    };
  }

  String _lastRunPrefix(
    AppLocalizations l10n,
    PkGroupRepairReferenceMode mode,
  ) {
    return switch (mode) {
      PkGroupRepairReferenceMode.none => l10n.pluralkitRepairLastRunPrefixLocal,
      PkGroupRepairReferenceMode.storedToken =>
        l10n.pluralkitRepairLastRunPrefixStoredToken,
      PkGroupRepairReferenceMode.providedToken =>
        l10n.pluralkitRepairLastRunPrefixTemporaryToken,
    };
  }

  String _lastRunSummary(AppLocalizations l10n, PkGroupRepairReport report) {
    final prefix = _lastRunPrefix(l10n, report.referenceMode);
    final fragments = _summaryRepairFragments(l10n, report);

    if (fragments.isEmpty) {
      return l10n.pluralkitRepairLastRunNoChanges(prefix);
    }

    return l10n.pluralkitRepairLastRunChanged(
      prefix,
      _joinFragments(l10n, fragments),
    );
  }

  List<String> _summaryRepairFragments(
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

  List<String> _repairDetailLines(
    AppLocalizations l10n,
    PkGroupRepairReport report,
  ) {
    return <String>[
      if (report.parentReferencesRehomed > 0)
        l10n.pluralkitRepairDetailUpdatedParentLinks(
          report.parentReferencesRehomed,
        ),
      if (report.entriesRehomed > 0)
        l10n.pluralkitRepairDetailMovedMemberships(report.entriesRehomed),
      if (report.duplicateGroupsSoftDeleted > 0)
        l10n.pluralkitRepairDetailRemovedDuplicateGroups(
          report.duplicateGroupsSoftDeleted,
        ),
      if (report.entryConflictsSoftDeleted > 0)
        l10n.pluralkitRepairDetailRemovedConflictingMemberships(
          report.entryConflictsSoftDeleted,
        ),
      if (report.ambiguousGroupsSuppressed > 0)
        l10n.pluralkitRepairDetailSuppressedAmbiguousGroups(
          report.ambiguousGroupsSuppressed,
        ),
      if (report.backfilledEntries > 0)
        l10n.pluralkitRepairDetailRestoredMissingMemberships(
          report.backfilledEntries,
        ),
      if (report.aliasesRecorded > 0)
        l10n.pluralkitRepairDetailRecordedLegacyAliases(report.aliasesRecorded),
    ];
  }

  String? _referenceRecommendation(AppLocalizations l10n) {
    if (hasStoredToken == false &&
        state.lastReport?.requiresReconnectForMissingPkGroupIdentity == true) {
      return l10n.pluralkitRepairReferenceImportOnly;
    }
    if (hasStoredToken == true && state.lastReport?.referenceError == null) {
      return null;
    }
    if (hasStoredToken == true && state.lastReport?.referenceError != null) {
      return l10n.pluralkitRepairReferenceStoredTokenFailed;
    }
    if (hasStoredToken == false && !isConnected) {
      return l10n.pluralkitRepairReferenceReconnectOrToken;
    }
    if (hasStoredToken == false) {
      return l10n.pluralkitRepairReferenceTokenRecommended;
    }
    return l10n.pluralkitRepairReferenceLocalNow;
  }

  Color _enablementColor(ThemeData theme) {
    if (pkGroupSyncV2Enabled == true) return theme.colorScheme.primary;
    if (_canEnablePkGroupSyncV2) return theme.colorScheme.tertiary;
    return theme.colorScheme.secondary;
  }

  IconData _enablementIcon() {
    if (pkGroupSyncV2Enabled == true) return AppIcons.checkCircle;
    if (_canEnablePkGroupSyncV2) return AppIcons.checkCircle;
    return AppIcons.warningAmberRounded;
  }

  Future<void> _confirmEnablePkGroupSyncV2(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await PrismSheet.show<bool>(
      context: context,
      title: l10n.pluralkitRepairConfirmEnableTitle,
      maxHeightFactor: 0.8,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.warningAmberRounded,
                    color: theme.colorScheme.secondary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.pluralkitRepairConfirmEnableBody,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.pluralkitRepairConfirmEnableFootnote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  PrismButton(
                    label: l10n.cancel,
                    tone: PrismButtonTone.outlined,
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                  ),
                  PrismButton(
                    label: l10n.pluralkitRepairConfirmEnableAction,
                    tone: PrismButtonTone.filled,
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    await onEnablePkGroupSyncV2();
  }

  Future<void> _confirmResetPkGroupsOnly(BuildContext context) async {
    final l10n = context.l10n;
    final action = await PrismSheet.show<String>(
      context: context,
      title: l10n.pluralkitRepairConfirmResetTitle,
      maxHeightFactor: 0.84,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final detail = isConnected
            ? l10n.pluralkitRepairConfirmResetConnectedBody
            : l10n.pluralkitRepairConfirmResetDisconnectedBody;
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.warningAmberRounded,
                    color: theme.colorScheme.secondary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(detail, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.pluralkitRepairConfirmResetExportHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  PrismButton(
                    label: l10n.cancel,
                    tone: PrismButtonTone.outlined,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                  PrismButton(
                    label: l10n.pluralkitRepairConfirmResetExportFirst,
                    tone: PrismButtonTone.outlined,
                    onPressed: () => Navigator.of(sheetContext).pop('export'),
                  ),
                  PrismButton(
                    label: isConnected
                        ? l10n.pluralkitRepairConfirmResetActionConnected
                        : l10n.pluralkitRepairConfirmResetActionDisconnected,
                    tone: PrismButtonTone.destructive,
                    onPressed: () => Navigator.of(sheetContext).pop('reset'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (action == 'export') {
      onExportDataFirst();
      return;
    }
    if (action != 'reset') return;
    await onResetPkGroupsOnly();
  }

  bool _hasRepairChanges(PkGroupRepairReport report) {
    return report.backfilledEntries > 0 ||
        report.duplicateSetsMerged > 0 ||
        report.duplicateGroupsSoftDeleted > 0 ||
        report.parentReferencesRehomed > 0 ||
        report.entriesRehomed > 0 ||
        report.entryConflictsSoftDeleted > 0 ||
        report.aliasesRecorded > 0 ||
        report.ambiguousGroupsSuppressed > 0;
  }

  String _joinFragments(AppLocalizations l10n, List<String> fragments) {
    if (fragments.length == 1) return fragments.first;
    if (fragments.length == 2) {
      return l10n.pluralkitRepairJoinPair(fragments.first, fragments.last);
    }

    final head = fragments.sublist(0, fragments.length - 1).join(', ');
    return l10n.pluralkitRepairJoinSerial(fragments.last, head);
  }

  String _compactError(String value) {
    return value
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '')
        .trim();
  }
}

class _RepairCardHeader extends StatelessWidget {
  const _RepairCardHeader({
    required this.statusTone,
    required this.title,
    required this.headline,
  });

  final _RepairStatusTone statusTone;
  final String title;
  final String headline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(statusTone.icon, color: statusTone.color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                headline,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RepairStatusChips extends StatelessWidget {
  const _RepairStatusChips({
    required this.statusLabel,
    required this.statusColor,
    required this.tokenLabel,
    required this.tokenSelected,
    required this.tokenTintColor,
    required this.lastRunModeLabel,
    required this.lastRunModeColor,
    required this.enablementLabel,
    required this.enablementSelected,
    required this.enablementColor,
  });

  final String statusLabel;
  final Color statusColor;
  final String tokenLabel;
  final bool tokenSelected;
  final Color tokenTintColor;
  final String? lastRunModeLabel;
  final Color lastRunModeColor;
  final String enablementLabel;
  final bool enablementSelected;
  final Color enablementColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PrismChip(
            label: statusLabel,
            selected: true,
            tintColor: statusColor,
            onTap: null,
          ),
          PrismChip(
            label: tokenLabel,
            selected: tokenSelected,
            tintColor: tokenTintColor,
            onTap: null,
          ),
          if (lastRunModeLabel != null)
            PrismChip(
              label: lastRunModeLabel!,
              selected: true,
              tintColor: lastRunModeColor,
              onTap: null,
            ),
          PrismChip(
            label: enablementLabel,
            selected: enablementSelected,
            tintColor: enablementColor,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _RepairStatusRows extends StatelessWidget {
  const _RepairStatusRows({
    required this.statusTone,
    required this.currentStatusLabel,
    required this.currentStatusText,
    required this.pendingReviewCount,
    required this.pendingReviewLabel,
    required this.pendingReviewText,
  });

  final _RepairStatusTone statusTone;
  final String currentStatusLabel;
  final String currentStatusText;
  final int pendingReviewCount;
  final String pendingReviewLabel;
  final String pendingReviewText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrismListRow(
            dense: true,
            padding: EdgeInsets.zero,
            leading: Icon(statusTone.icon, size: 18, color: statusTone.color),
            title: Text(currentStatusLabel),
            subtitle: Text(currentStatusText),
          ),
          const SizedBox(height: 10),
          PrismListRow(
            dense: true,
            padding: EdgeInsets.zero,
            leading: Icon(
              AppIcons.warningAmberRounded,
              size: 18,
              color: pendingReviewCount > 0
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(pendingReviewLabel),
            subtitle: Text(pendingReviewText),
          ),
        ],
      ),
    );
  }
}

class _PendingReviewItemsSection extends StatelessWidget {
  const _PendingReviewItemsSection({
    required this.items,
    required this.isRunning,
    required this.onMergeReviewItemIntoCanonical,
    required this.onKeepReviewItemLocalOnly,
    required this.onDismissReviewItem,
  });

  final List<PkGroupReviewItem> items;
  final bool isRunning;
  final Future<void> Function(String groupId) onMergeReviewItemIntoCanonical;
  final Future<void> Function(String groupId) onKeepReviewItemLocalOnly;
  final Future<void> Function(String groupId) onDismissReviewItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        for (final item in items) ...[
          _ReviewItemCard(
            item: item,
            isRunning: isRunning,
            onMergeReviewItemIntoCanonical: onMergeReviewItemIntoCanonical,
            onKeepReviewItemLocalOnly: onKeepReviewItemLocalOnly,
            onDismissReviewItem: onDismissReviewItem,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RepairLastRunSection extends StatelessWidget {
  const _RepairLastRunSection({
    required this.title,
    required this.summary,
    required this.detailTitle,
    required this.detailLines,
  });

  final String title;
  final String summary;
  final String detailTitle;
  final List<String> detailLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrismListRow(
            dense: true,
            padding: EdgeInsets.zero,
            leading: Icon(
              AppIcons.schedule,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(title),
            subtitle: Text(summary),
          ),
          if (detailLines.isNotEmpty) ...[
            const SizedBox(height: 10),
            _RepairDetailLinesSurface(title: detailTitle, lines: detailLines),
          ],
        ],
      ),
    );
  }
}

class _RepairDetailLinesSurface extends StatelessWidget {
  const _RepairDetailLinesSurface({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismSurface(
      tone: PrismSurfaceTone.accent,
      accentColor: theme.colorScheme.primary,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < lines.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '- ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Text(
                    lines[index],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (index != lines.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _ReferenceRecommendationSurface extends StatelessWidget {
  const _ReferenceRecommendationSurface({required this.recommendation});

  final String recommendation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: PrismSurface(
        tone: PrismSurfaceTone.accent,
        accentColor: theme.colorScheme.secondary,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.link, color: theme.colorScheme.secondary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                recommendation,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepairMessageSurface extends StatelessWidget {
  const _RepairMessageSurface({
    required this.message,
    required this.icon,
    required this.fillColor,
    required this.borderColor,
    required this.contentColor,
  });

  final String message;
  final IconData icon;
  final Color fillColor;
  final Color borderColor;
  final Color contentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PrismSurface(
        fillColor: fillColor,
        borderColor: borderColor,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: contentColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: contentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepairCutoverSection extends StatelessWidget {
  const _RepairCutoverSection({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.headline,
    required this.statusTitle,
    required this.statusText,
    required this.recommendation,
    required this.canEnable,
    required this.enableLabel,
    required this.onEnablePressed,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String headline;
  final String statusTitle;
  final String statusText;
  final String? recommendation;
  final bool canEnable;
  final String enableLabel;
  final VoidCallback onEnablePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PrismSurface(
        tone: PrismSurfaceTone.accent,
        accentColor: accentColor,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: accentColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headline,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            PrismListRow(
              dense: true,
              padding: EdgeInsets.zero,
              leading: Icon(icon, color: accentColor, size: 18),
              title: Text(statusTitle),
              subtitle: Text(statusText),
            ),
            if (recommendation != null) ...[
              const SizedBox(height: 8),
              Text(
                recommendation!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (canEnable) ...[
              const SizedBox(height: 12),
              PrismButton(
                label: enableLabel,
                icon: AppIcons.checkCircle,
                onPressed: onEnablePressed,
                tone: PrismButtonTone.filled,
                expanded: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RepairActionButtons extends StatelessWidget {
  const _RepairActionButtons({
    required this.primaryLabel,
    required this.isRunning,
    required this.onRunRepair,
    required this.showTemporaryTokenAction,
    required this.temporaryTokenLabel,
    required this.onUseTemporaryToken,
    required this.showResetPkGroupsOnlyAction,
    required this.resetLabel,
    required this.onResetPkGroupsOnly,
  });

  final String primaryLabel;
  final bool isRunning;
  final VoidCallback onRunRepair;
  final bool showTemporaryTokenAction;
  final String temporaryTokenLabel;
  final VoidCallback? onUseTemporaryToken;
  final bool showResetPkGroupsOnlyAction;
  final String resetLabel;
  final VoidCallback onResetPkGroupsOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrismButton(
            label: primaryLabel,
            icon: AppIcons.autoFixHigh,
            onPressed: onRunRepair,
            isLoading: isRunning,
            enabled: !isRunning,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          if (showTemporaryTokenAction) ...[
            const SizedBox(height: 8),
            PrismButton(
              label: temporaryTokenLabel,
              icon: AppIcons.link,
              onPressed: onUseTemporaryToken!,
              enabled: !isRunning,
              tone: PrismButtonTone.outlined,
              expanded: true,
            ),
          ],
          if (showResetPkGroupsOnlyAction) ...[
            const SizedBox(height: 8),
            PrismButton(
              label: resetLabel,
              icon: AppIcons.restartAlt,
              onPressed: onResetPkGroupsOnly,
              enabled: !isRunning,
              tone: PrismButtonTone.destructive,
              expanded: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewItemCard extends ConsumerWidget {
  const _ReviewItemCard({
    required this.item,
    required this.isRunning,
    required this.onMergeReviewItemIntoCanonical,
    required this.onKeepReviewItemLocalOnly,
    required this.onDismissReviewItem,
  });

  final PkGroupReviewItem item;
  final bool isRunning;
  final Future<void> Function(String groupId) onMergeReviewItemIntoCanonical;
  final Future<void> Function(String groupId) onKeepReviewItemLocalOnly;
  final Future<void> Function(String groupId) onDismissReviewItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final terms = watchTerminology(context, ref);
    final actionPreview = _actionPreview(context, ref);

    return PrismSurface(
      tone: PrismSurfaceTone.accent,
      accentColor: theme.colorScheme.secondary,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumns = constraints.maxWidth >= 560;
              final localPanel = _ComparisonPanel(
                title: l10n.pluralkitRepairThisGroup,
                name: item.name,
                description: item.description,
                colorHex: item.colorHex,
                chips: [
                  l10n.pluralkitRepairSharedPkMembers(
                    item.sharedPkMemberUuids.length,
                    terms.singularLower,
                    terms.pluralLower,
                  ),
                  l10n.pluralkitRepairLocalOnlyMembers(
                    item.extraLocalMemberIds.length,
                    terms.singularLower,
                    terms.pluralLower,
                  ),
                ],
              );
              final candidatePanel = _ComparisonPanel(
                title: item.candidateName == null
                    ? l10n.pluralkitRepairPluralKitGroup
                    : l10n.pluralkitRepairPkGroup,
                name: item.candidateName ?? item.suspectedPkGroupUuid,
                description: item.candidateDescription,
                colorHex: item.candidateColorHex,
                chips: item.hasCandidateComparison
                    ? [
                        l10n.pluralkitRepairSharedPkMembers(
                          item.sharedPkMemberUuids.length,
                          terms.singularLower,
                          terms.pluralLower,
                        ),
                        l10n.pluralkitRepairOnlyInPkMembers(
                          item.onlyInCandidateMemberUuids.length,
                        ),
                      ]
                    : [l10n.pluralkitRepairReconnectForComparison],
              );

              if (!useColumns) {
                return Column(
                  children: [
                    localPanel,
                    const SizedBox(height: 8),
                    candidatePanel,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: localPanel),
                  const SizedBox(width: 8),
                  Expanded(child: candidatePanel),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            l10n.pluralkitRepairSuspectedPkUuid(item.suspectedPkGroupUuid),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            actionPreview,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: l10n.pluralkitRepairUsePluralKitMatch,
                icon: AppIcons.autoFixHigh,
                onPressed: () =>
                    unawaited(onMergeReviewItemIntoCanonical(item.groupId)),
                enabled: !isRunning,
                tone: PrismButtonTone.filled,
              ),
              PrismButton(
                label: l10n.pluralkitRepairKeepMyPrismGroup,
                icon: AppIcons.lockOutline,
                onPressed: () =>
                    unawaited(onKeepReviewItemLocalOnly(item.groupId)),
                enabled: !isRunning,
                tone: PrismButtonTone.outlined,
              ),
              PrismButton(
                label: l10n.pluralkitRepairDismissFalsePositive,
                icon: AppIcons.checkCircle,
                onPressed: () => unawaited(onDismissReviewItem(item.groupId)),
                enabled: !isRunning,
                tone: PrismButtonTone.outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _actionPreview(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final terms = readTerminology(context, ref);
    final fragments = <String>[
      l10n.pluralkitRepairPreviewLinkLocalGroup,
      if (item.sharedPkMemberUuids.isNotEmpty)
        l10n.pluralkitRepairPreviewPreserveShared(
          item.sharedPkMemberUuids.length,
        ),
      if (item.extraLocalMemberIds.isNotEmpty)
        l10n.pluralkitRepairPreviewKeepLocalOnly(
          item.extraLocalMemberIds.length,
        ),
      if (item.onlyInCandidateMemberUuids.isNotEmpty)
        l10n.pluralkitRepairPreviewLeavePkOnly(
          item.onlyInCandidateMemberUuids.length,
          terms.singularLower,
          terms.pluralLower,
        ),
    ];
    return l10n.pluralkitRepairMergeActionPreview(
      _joinPreviewFragments(fragments),
    );
  }

  static String _joinPreviewFragments(List<String> fragments) {
    if (fragments.length == 1) return fragments.first;
    return fragments.join(' · ');
  }
}

class _ComparisonPanel extends StatelessWidget {
  const _ComparisonPanel({
    required this.title,
    required this.name,
    required this.description,
    required this.colorHex,
    required this.chips,
  });

  final String title;
  final String name;
  final String? description;
  final String? colorHex;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatchColor = colorHex == null
        ? theme.colorScheme.onSurfaceVariant
        : AppColors.fromHex(colorHex!);
    final description = this.description?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: swatchColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final chip in chips)
              _ComparisonChip(label: chip, color: theme.colorScheme.secondary),
          ],
        ),
      ],
    );
  }
}

class _ComparisonChip extends StatelessWidget {
  const _ComparisonChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(PrismTokens.radiusPill),
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RepairStatusTone {
  const _RepairStatusTone({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}
