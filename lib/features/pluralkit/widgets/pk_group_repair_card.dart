import 'dart:async';

import 'package:flutter/material.dart';

import 'package:prism_plurality/features/pluralkit/providers/pk_group_repair_provider.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
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
    final report = state.lastReport;
    final repairDetailLines = report == null
        ? const <String>[]
        : _repairDetailLines(report);
    final statusTone = _statusTone(theme);
    final primaryLabel = hasStoredToken == false
        ? 'Run local repair'
        : 'Run repair';
    final showTemporaryTokenAction =
        onUseTemporaryToken != null &&
        (hasStoredToken != true || report?.referenceError != null);
    final showResetPkGroupsOnlyAction =
        !state.isRunning &&
        (state.pendingReviewCount > 0 ||
            report?.requiresReconnectForMissingPkGroupIdentity == true);
    final resetLabel = isConnected
        ? 'Reset PK groups and re-import'
        : 'Reset PK groups only';

    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      accentColor: statusTone.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(statusTone.icon, color: statusTone.color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PluralKit group repair',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _headline(report),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismChip(
                label: _statusChipLabel(),
                selected: true,
                tintColor: statusTone.color,
                onTap: null,
              ),
              PrismChip(
                label: _tokenChipLabel(),
                selected: hasStoredToken == true,
                tintColor: hasStoredToken == true
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
                onTap: null,
              ),
              if (report != null)
                PrismChip(
                  label: _lastRunModeLabel(report.referenceMode),
                  selected: true,
                  tintColor: theme.colorScheme.tertiary,
                  onTap: null,
                ),
              PrismChip(
                label: _enablementChipLabel(),
                selected: pkGroupSyncV2Enabled == true,
                tintColor: _enablementColor(theme),
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrismListRow(
            dense: true,
            padding: EdgeInsets.zero,
            leading: Icon(statusTone.icon, size: 18, color: statusTone.color),
            title: const Text('Current status'),
            subtitle: Text(_currentStatusText(report)),
          ),
          const SizedBox(height: 10),
          PrismListRow(
            dense: true,
            padding: EdgeInsets.zero,
            leading: Icon(
              AppIcons.warningAmberRounded,
              size: 18,
              color: state.pendingReviewCount > 0
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: const Text('Pending review'),
            subtitle: Text(_pendingReviewText()),
          ),
          if (state.pendingReviewItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final item in state.pendingReviewItems) ...[
              _ReviewItemCard(
                item: item,
                isRunning: state.isRunning,
                onMergeReviewItemIntoCanonical: onMergeReviewItemIntoCanonical,
                onKeepReviewItemLocalOnly: onKeepReviewItemLocalOnly,
                onDismissReviewItem: onDismissReviewItem,
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (report != null) ...[
            const SizedBox(height: 10),
            PrismListRow(
              dense: true,
              padding: EdgeInsets.zero,
              leading: Icon(
                AppIcons.schedule,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: const Text('Last run'),
              subtitle: Text(_lastRunSummary(report)),
            ),
            if (repairDetailLines.isNotEmpty) ...[
              const SizedBox(height: 10),
              PrismSurface(
                tone: PrismSurfaceTone.accent,
                accentColor: theme.colorScheme.primary,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What changed',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (
                      var index = 0;
                      index < repairDetailLines.length;
                      index++
                    ) ...[
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
                              repairDetailLines[index],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (index != repairDetailLines.length - 1)
                        const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ],
          ],
          if (_referenceRecommendation() case final recommendation?) ...[
            const SizedBox(height: 14),
            PrismSurface(
              tone: PrismSurfaceTone.accent,
              accentColor: theme.colorScheme.secondary,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.link,
                    color: theme.colorScheme.secondary,
                    size: 18,
                  ),
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
          ],
          if (report?.referenceError case final referenceError?) ...[
            const SizedBox(height: 12),
            PrismSurface(
              fillColor: theme.colorScheme.secondaryContainer,
              borderColor: theme.colorScheme.secondary.withValues(alpha: 0.28),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.warningAmberRounded,
                    color: theme.colorScheme.onSecondaryContainer,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Live PK lookup failed on the last run, so Prism fell back '
                      'to the local repair pass. ${_compactError(referenceError)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (state.error case final error?) ...[
            const SizedBox(height: 12),
            PrismSurface(
              fillColor: theme.colorScheme.errorContainer,
              borderColor: theme.colorScheme.error.withValues(alpha: 0.28),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.errorOutline,
                    color: theme.colorScheme.onErrorContainer,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Repair failed: ${_compactError(error)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          PrismSurface(
            tone: PrismSurfaceTone.accent,
            accentColor: _enablementColor(theme),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _enablementIcon(),
                      color: _enablementColor(theme),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PK group sync v2 cutover',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _enablementHeadline(),
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
                  leading: Icon(
                    _enablementIcon(),
                    color: _enablementColor(theme),
                    size: 18,
                  ),
                  title: const Text('Shared enablement'),
                  subtitle: Text(_enablementStatusText()),
                ),
                if (_enablementRecommendation() case final recommendation?) ...[
                  const SizedBox(height: 8),
                  Text(
                    recommendation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_canEnablePkGroupSyncV2) ...[
                  const SizedBox(height: 12),
                  PrismButton(
                    label: 'Enable PK group sync',
                    icon: AppIcons.checkCircle,
                    onPressed: () =>
                        unawaited(_confirmEnablePkGroupSyncV2(context)),
                    tone: PrismButtonTone.filled,
                    expanded: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrismButton(
            label: primaryLabel,
            icon: AppIcons.autoFixHigh,
            onPressed: onRunRepair,
            isLoading: state.isRunning,
            enabled: !state.isRunning,
            tone: PrismButtonTone.filled,
            expanded: true,
          ),
          if (showTemporaryTokenAction) ...[
            const SizedBox(height: 8),
            PrismButton(
              label: 'Use temporary token',
              icon: AppIcons.link,
              onPressed: onUseTemporaryToken!,
              enabled: !state.isRunning,
              tone: PrismButtonTone.outlined,
              expanded: true,
            ),
          ],
          if (showResetPkGroupsOnlyAction) ...[
            const SizedBox(height: 8),
            PrismButton(
              label: resetLabel,
              icon: AppIcons.restartAlt,
              onPressed: () => unawaited(_confirmResetPkGroupsOnly(context)),
              enabled: !state.isRunning,
              tone: PrismButtonTone.destructive,
              expanded: true,
            ),
          ],
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

  String _headline(PkGroupRepairReport? report) {
    if (state.isRunning) {
      return 'Scanning linked groups, repairing obvious duplicates, and '
          'cross-checking live PK groups when a token is available.';
    }
    if (state.pendingReviewCount > 0) {
      return 'Ambiguous imported groups are currently suppressed so Prism '
          'does not create duplicate sync links.';
    }
    if (report?.requiresReconnectForMissingPkGroupIdentity == true) {
      return 'Local repair can still restore directly provable PK links, but '
          'reconnecting PluralKit is still required to reconstruct missing PK '
          'group identity automatically.';
    }
    if (report != null && _hasRepairChanges(report)) {
      return 'The last run made concrete local repair changes. Review the '
          'summary below before enabling PK-backed group sync.';
    }
    if (report != null) {
      return 'The last run completed. You can rerun repair after reconnecting '
          'or importing more PluralKit data.';
    }
    return 'Fixes obvious PK group duplicates locally and flags ambiguous '
        'matches for follow-up review.';
  }

  String _statusChipLabel() {
    if (state.isRunning) return 'Repair running';
    if (state.error != null) return 'Retry needed';
    if (state.pendingReviewCount > 0) {
      return '${state.pendingReviewCount} pending review';
    }
    if (state.lastReport != null) return 'Last run complete';
    return 'Ready to run';
  }

  String _tokenChipLabel() {
    if (hasStoredToken == true) return 'Token-backed ready';
    if (hasStoredToken == false) return 'Local-only until token';
    return 'Checking token access';
  }

  String _enablementChipLabel() {
    if (pkGroupSyncV2Enabled == true) return 'PK sync v2 enabled';
    if (pkGroupSyncV2Enabled == false) return 'PK sync v2 off';
    return 'Checking cutover';
  }

  String _currentStatusText(PkGroupRepairReport? report) {
    if (state.isRunning) {
      return 'Repair is running now.';
    }
    if (state.error != null) {
      return 'The last manual run failed. Retry below when you are ready.';
    }
    if (state.pendingReviewCount > 0) {
      return '${_countPhrase(state.pendingReviewCount, "group", "groups")} '
          'still need review before they can be linked or cleared.';
    }
    if (report == null) {
      return 'No repair run has been recorded in this app session yet.';
    }
    if (report.requiresReconnectForMissingPkGroupIdentity) {
      return 'The last run finished the safe local repair pass, but missing PK '
          'group identity still needs a live PluralKit reference source to be '
          'reconstructed automatically.';
    }
    if (_hasRepairChanges(report)) {
      return 'The last run changed local PK group data. See the last-run '
          'summary below for the exact repairs applied.';
    }
    return 'The last run did not find any new PK group repairs to apply.';
  }

  String _enablementHeadline() {
    if (pkGroupSyncV2Enabled == true) {
      return 'PK-backed group sync is enabled for this sync group. '
          'Manual/local-only groups still stay local.';
    }
    if (_canEnablePkGroupSyncV2) {
      return 'Local repair prerequisites are satisfied. The remaining safety '
          'boundary is explicit operator confirmation of cutover.';
    }
    return 'PK-backed group sync stays off until repair is complete and you '
        'explicitly confirm that legacy devices are no longer paired.';
  }

  String _enablementStatusText() {
    if (pkGroupSyncV2Enabled == null) {
      return 'Loading the shared cutover setting for this sync group.';
    }
    if (pkGroupSyncV2Enabled == true) {
      return 'Enabled for this sync group after explicit confirmation.';
    }
    if (state.isRunning) {
      return 'Unavailable while repair is still running.';
    }
    if (state.lastReport == null) {
      return 'Unavailable until a repair run completes in this app session.';
    }
    if (state.pendingReviewCount > 0) {
      return 'Unavailable until pending review items are resolved or kept '
          'local-only.';
    }
    return 'Ready to enable after explicit cutover confirmation.';
  }

  String? _enablementRecommendation() {
    if (pkGroupSyncV2Enabled == null) return null;
    if (pkGroupSyncV2Enabled == true) {
      return 'This only affects PK-backed group sync. Manual/local-only groups '
          'remain unaffected.';
    }
    if (state.lastReport == null) {
      return 'Run repair first. Prism keeps PK group sync v2 off until this '
          'client has completed a repair pass.';
    }
    if (state.pendingReviewCount > 0) {
      return 'Resolve each pending review item or explicitly keep it '
          'local-only before enabling cutover.';
    }
    return 'Only enable after every legacy 0.4.0+1-era device in this sync '
        'group has been upgraded, reset/re-paired, removed, or after you '
        'moved testing to a fresh sync group.';
  }

  String _pendingReviewText() {
    if (state.pendingReviewCount == 0) {
      return 'No ambiguous PK group matches are waiting for review.';
    }
    return '${_countPhrase(state.pendingReviewCount, "group", "groups")} '
        'still need follow-up review.';
  }

  String _lastRunModeLabel(PkGroupRepairReferenceMode mode) {
    return switch (mode) {
      PkGroupRepairReferenceMode.none => 'Local-only run',
      PkGroupRepairReferenceMode.storedToken => 'Stored-token run',
      PkGroupRepairReferenceMode.providedToken => 'Temporary-token run',
    };
  }

  String _lastRunSummary(PkGroupRepairReport report) {
    final prefix = switch (report.referenceMode) {
      PkGroupRepairReferenceMode.none => 'Local run',
      PkGroupRepairReferenceMode.storedToken => 'Stored-token run',
      PkGroupRepairReferenceMode.providedToken => 'Temporary-token run',
    };
    final fragments = _summaryRepairFragments(report);

    if (fragments.isEmpty) {
      return '$prefix found no new PK group changes to apply.';
    }

    return '$prefix ${_joinFragments(fragments)}.';
  }

  List<String> _summaryRepairFragments(PkGroupRepairReport report) {
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

  List<String> _repairDetailLines(PkGroupRepairReport report) {
    return <String>[
      if (report.parentReferencesRehomed > 0)
        'Updated ${_countPhrase(report.parentReferencesRehomed, "child-group parent link", "child-group parent links")} to point at the surviving group.',
      if (report.entriesRehomed > 0)
        'Moved ${_countPhrase(report.entriesRehomed, "group membership", "group memberships")} onto the surviving group.',
      if (report.duplicateGroupsSoftDeleted > 0)
        'Removed ${_countPhrase(report.duplicateGroupsSoftDeleted, "duplicate local group", "duplicate local groups")}.',
      if (report.entryConflictsSoftDeleted > 0)
        'Removed ${_countPhrase(report.entryConflictsSoftDeleted, "conflicting group membership", "conflicting group memberships")} while merging duplicates.',
      if (report.ambiguousGroupsSuppressed > 0)
        'Suppressed ${_countPhrase(report.ambiguousGroupsSuppressed, "ambiguous group", "ambiguous groups")} for review before sync can continue.',
      if (report.backfilledEntries > 0)
        'Restored ${_countPhrase(report.backfilledEntries, "missing PK membership link", "missing PK membership links")}.',
      if (report.aliasesRecorded > 0)
        'Recorded ${_countPhrase(report.aliasesRecorded, "legacy group alias", "legacy group aliases")} so older group IDs still resolve.',
    ];
  }

  String? _referenceRecommendation() {
    if (hasStoredToken == false &&
        state.lastReport?.requiresReconnectForMissingPkGroupIdentity == true) {
      return 'This looks like import-only PK data with no local PK-linked '
          'groups left to use as repair references. Prism can still repair '
          'directly linked rows locally, but reconnecting PluralKit or using '
          'a temporary token is the only way to reconstruct missing PK group '
          'identity automatically.';
    }
    if (hasStoredToken == true && state.lastReport?.referenceError == null) {
      return null;
    }
    if (hasStoredToken == true && state.lastReport?.referenceError != null) {
      return 'A stored token exists, but the last live reference lookup failed. '
          'Reconnect PluralKit or use a temporary token if you want a full '
          'token-backed repair pass.';
    }
    if (hasStoredToken == false && !isConnected) {
      return 'Reconnect PluralKit above or use a temporary token for a fuller '
          'repair pass. Local repair still handles the obvious duplicates.';
    }
    if (hasStoredToken == false) {
      return 'A token-backed repair run is recommended when you can provide '
          'one. Until then, Prism will only run the safe local repair pass.';
    }
    return 'Repair can run locally now. Live PK cross-checks appear once '
        'token access is confirmed.';
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
    final confirmed = await PrismSheet.show<bool>(
      context: context,
      title: 'Enable PK sync v2?',
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
                      'Only enable this after every legacy 0.4.0+1-era device '
                      'has been upgraded, reset/re-paired, removed, or after '
                      'you moved to a fresh sync group.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'If any device is unaccounted for, keep this off. '
                'Manual/local-only groups stay local either way.',
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
                    label: 'Cancel',
                    tone: PrismButtonTone.outlined,
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                  ),
                  PrismButton(
                    label: 'Enable PK sync v2',
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
    final action = await PrismSheet.show<String>(
      context: context,
      title: 'Reset PK groups only?',
      maxHeightFactor: 0.84,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final detail = isConnected
            ? 'Prism will remove PK-linked and repair-suppressed groups, keep '
                  'manual/local-only groups, clear deferred PK membership ops, '
                  'and then re-import your current PK groups.'
            : 'Prism will remove PK-linked and repair-suppressed groups, keep '
                  'manual/local-only groups, and clear deferred PK membership '
                  'ops. Reconnect PluralKit or import again afterward to rebuild '
                  'them.';
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
                'Export data first if you want a full backup before the reset.',
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
                    label: 'Cancel',
                    tone: PrismButtonTone.outlined,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                  PrismButton(
                    label: 'Export data first',
                    tone: PrismButtonTone.outlined,
                    onPressed: () => Navigator.of(sheetContext).pop('export'),
                  ),
                  PrismButton(
                    label: isConnected
                        ? 'Reset and re-import'
                        : 'Reset PK groups',
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

  String _compactError(String value) {
    return value
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '')
        .trim();
  }
}

class _ReviewItemCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final actionPreview = _actionPreview(context);

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
                  ),
                  l10n.pluralkitRepairLocalOnlyMembers(
                    item.extraLocalMemberIds.length,
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
                label: l10n.pluralkitRepairMergeIntoCanonical,
                icon: AppIcons.autoFixHigh,
                onPressed: () =>
                    unawaited(onMergeReviewItemIntoCanonical(item.groupId)),
                enabled: !isRunning,
                tone: PrismButtonTone.filled,
              ),
              PrismButton(
                label: l10n.pluralkitRepairKeepLocalOnly,
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

  String _actionPreview(BuildContext context) {
    final l10n = context.l10n;
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
