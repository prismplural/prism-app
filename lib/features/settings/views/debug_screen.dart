import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/app_database.dart' hide Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_group_repair_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Placeholder — pending changes count (sync now managed by Rust layer).
final _pendingChangesCountProvider = FutureProvider<int>((ref) async {
  return 0;
});

/// Developer-oriented debug screen with database reset, sync info, and
/// build details.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  StressProgress? _progress;
  StressPreset? _currentPreset;
  bool _isGenerating = false;
  bool _isClearing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeIdAsync = ref.watch(nodeIdProvider);
    final pendingAsync = ref.watch(_pendingChangesCountProvider);
    final lastSyncTime = ref.watch(lastSyncTimeProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.debugTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          // ── Danger Zone ─────────────────────────────
          PrismSurface(
            fillColor: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.debugDangerZone,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: context.l10n.debugResetDatabase,
                    icon: AppIcons.deleteForever,
                    tone: PrismButtonTone.destructive,
                    expanded: true,
                    onPressed: () => _confirmReset(context),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: context.l10n.debugExportData,
                    icon: AppIcons.fileUploadOutlined,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    onPressed: () {
                      PrismToast.show(
                        context,
                        message: context.l10n.debugComingSoon,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Stress Testing ─────────────────────────
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.debugStressTestingTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.debugStressTestingDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (_isGenerating && _progress != null) ...[
                  LinearProgressIndicator(value: _progress!.fraction),
                  const SizedBox(height: 4),
                  Text(
                    '${_progress!.phase}... ${_progress!.current}/${_progress!.total}'
                    '${_currentPreset != null ? ' • ~${_currentPreset!.estimatedSizeMb}MB' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: context.l10n.debugGenerateStressData,
                    icon: AppIcons.speed,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    isLoading: _isGenerating,
                    enabled: !_isGenerating,
                    onPressed: () => _showPresetPicker(context),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: _isClearing
                        ? context.l10n.debugClearingStressData
                        : context.l10n.debugClearStressData,
                    icon: AppIcons.deleteForever,
                    tone: PrismButtonTone.destructive,
                    expanded: true,
                    isLoading: _isClearing,
                    enabled: !_isGenerating && !_isClearing,
                    onPressed: () => _confirmClearStressData(context),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── CRDT Sync State ─────────────────────────
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.debugSyncState,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _DebugRow(
                  label: context.l10n.debugPendingChanges,
                  value: pendingAsync.when(
                    loading: () => '...',
                    error: (e, _) => 'Error',
                    data: (count) => '$count',
                  ),
                ),
                const Divider(height: 16),
                _DebugRow(
                  label: context.l10n.debugLastSync,
                  value: lastSyncTime != null
                      ? _formatDateTime(lastSyncTime)
                      : context.l10n.debugNeverSynced,
                ),
                const Divider(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: PrismButton(
                    label: context.l10n.debugOpenSyncLog,
                    icon: AppIcons.receiptLongOutlined,
                    tone: PrismButtonTone.outlined,
                    expanded: true,
                    onPressed: () =>
                        context.push(AppRoutePaths.settingsSyncDebug),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Build Info ──────────────────────────────
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.debugBuildInfo,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    PrismInlineIconButton(
                      icon: AppIcons.copy,
                      iconSize: 18,
                      tooltip: context.l10n.debugCopyBuildInfo,
                      onPressed: () {
                        const text =
                            'Prism ${BuildInfo.appVersion}\n'
                            'git: ${BuildInfo.gitDescribe}\n'
                            'branch: ${BuildInfo.gitBranch}\n'
                            'built: ${BuildInfo.builtAt}';
                        Clipboard.setData(const ClipboardData(text: text));
                        PrismToast.show(
                          context,
                          message: context.l10n.debugBuildInfoCopied,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DebugRow(
                  label: context.l10n.debugAppVersion,
                  value: BuildInfo.appVersion,
                ),
                const Divider(height: 16),
                _DebugRow(
                  label: context.l10n.debugGit,
                  value: BuildInfo.gitDescribe,
                  warn: BuildInfo.isDirty || BuildInfo.isLocalDev,
                ),
                const Divider(height: 16),
                _DebugRow(
                  label: context.l10n.debugBranch,
                  value: BuildInfo.gitBranch,
                ),
                const Divider(height: 16),
                _DebugRow(
                  label: context.l10n.debugBuilt,
                  value: BuildInfo.builtAt,
                ),
                const Divider(height: 16),
                _DebugRow(
                  label: context.l10n.debugPackage,
                  value: 'prism_plurality',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Tools ────────────────────────────────────
          PrismSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.l10n.debugTools,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PrismListRow(
                  leading: Icon(AppIcons.healing),
                  title: Text(context.l10n.debugTimelineSanitization),
                  subtitle: Text(
                    context.l10n.debugTimelineSanitizationSubtitle,
                  ),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () =>
                      context.push(AppRoutePaths.settingsTimelineSanitization),
                ),
                PrismListRow(
                  leading: Icon(AppIcons.group),
                  title: const Text('PluralKit group tester'),
                  subtitle: const Text(
                    'Preview live groups and seed a repair review card',
                  ),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () => _showPluralKitGroupTester(context),
                ),
                PrismListRow(
                  leading: Icon(AppIcons.gridView),
                  title: const Text('Component Gallery'),
                  subtitle: const Text('Preview all shared widgets'),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () =>
                      context.push(AppRoutePaths.settingsComponentGallery),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Node ID ─────────────────────────────────
          PrismSectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.debugDevice,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                nodeIdAsync.when(
                  loading: () => const PrismLoadingState(),
                  error: (e, _) => Text(context.l10n.errorWithDetail(e)),
                  data: (nodeId) {
                    final displayId =
                        nodeId ?? context.l10n.debugNodeIdUnavailable;
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.debugNodeId,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                displayId,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (nodeId != null)
                          PrismInlineIconButton(
                            icon: AppIcons.copy,
                            iconSize: 18,
                            tooltip: context.l10n.debugCopyNodeId,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: nodeId));
                              PrismToast.show(
                                context,
                                message: context.l10n.debugNodeIdCopied,
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPluralKitGroupTester(BuildContext context) async {
    final tokenController = TextEditingController();

    try {
      await PrismSheet.show<void>(
        context: context,
        title: 'PluralKit group tester',
        subtitle:
            'Uses a one-off token for this sheet. The token is not saved.',
        maxHeightFactor: 0.92,
        builder: (sheetContext) {
          var isBusy = false;
          String? errorText;
          PkRepairReferenceData? referenceData;
          PkGroupRepairReport? lastReport;
          String? seedSummary;

          Future<void> fetchReference(StateSetter setSheetState) async {
            final token = tokenController.text.trim();
            if (token.isEmpty) {
              setSheetState(() => errorText = 'Paste a PluralKit token first.');
              return;
            }

            setSheetState(() {
              isBusy = true;
              errorText = null;
            });
            try {
              final data = await ref
                  .read(pluralKitSyncServiceProvider)
                  .fetchRepairReferenceData(token: token);
              setSheetState(() {
                referenceData = data;
                seedSummary = null;
              });
            } catch (error) {
              setSheetState(() {
                errorText = 'Could not fetch PluralKit data: $error';
              });
            } finally {
              setSheetState(() => isBusy = false);
            }
          }

          Future<void> runRepair(StateSetter setSheetState) async {
            final token = tokenController.text.trim();
            if (token.isEmpty) {
              setSheetState(() => errorText = 'Paste a PluralKit token first.');
              return;
            }

            setSheetState(() {
              isBusy = true;
              errorText = null;
            });
            try {
              final report = await ref
                  .read(pkGroupRepairControllerProvider.notifier)
                  .run(token: token, allowStoredToken: false);
              setSheetState(() => lastReport = report);
              if (sheetContext.mounted) {
                PrismToast.show(
                  sheetContext,
                  message:
                      'Repair complete: ${report.pendingReviewCount} pending review item(s).',
                );
              }
            } catch (error) {
              setSheetState(() {
                errorText = 'Repair failed: $error';
              });
            } finally {
              setSheetState(() => isBusy = false);
            }
          }

          Future<void> seedReview(StateSetter setSheetState) async {
            final data = referenceData;
            if (data == null) {
              setSheetState(() {
                errorText = 'Fetch PluralKit groups before seeding a review.';
              });
              return;
            }
            if (data.groups.isEmpty) {
              setSheetState(() {
                errorText = 'This token did not return any PluralKit groups.';
              });
              return;
            }

            setSheetState(() {
              isBusy = true;
              errorText = null;
            });
            try {
              final summary = await _seedPkGroupReviewFixture(data);
              final report = await ref
                  .read(pkGroupRepairControllerProvider.notifier)
                  .run(
                    token: tokenController.text.trim(),
                    allowStoredToken: false,
                  );
              setSheetState(() {
                seedSummary = summary;
                lastReport = report;
              });
              if (sheetContext.mounted) {
                PrismToast.show(sheetContext, message: summary);
              }
            } catch (error) {
              setSheetState(() {
                errorText = 'Seed failed: $error';
              });
            } finally {
              setSheetState(() => isBusy = false);
            }
          }

          return StatefulBuilder(
            builder: (context, setSheetState) {
              final theme = Theme.of(context);
              final data = referenceData;
              final groups = data?.groups ?? const <PKGroup>[];
              final previewGroups = groups.take(8).toList(growable: false);

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrismTextField(
                      controller: tokenController,
                      labelText: 'PluralKit token',
                      hintText: 'Paste token',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: PrismButton(
                            label: 'Fetch groups',
                            icon: AppIcons.cloudDownload,
                            tone: PrismButtonTone.outlined,
                            enabled: !isBusy,
                            isLoading: isBusy,
                            onPressed: () =>
                                unawaited(fetchReference(setSheetState)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PrismButton(
                            label: 'Run repair',
                            icon: AppIcons.healing,
                            tone: PrismButtonTone.filled,
                            enabled: !isBusy,
                            onPressed: () =>
                                unawaited(runRepair(setSheetState)),
                          ),
                        ),
                      ],
                    ),
                    if (data != null) ...[
                      const SizedBox(height: 16),
                      PrismSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.system.name ?? data.system.id,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${data.groups.length} group(s), '
                              '${data.members.length} member(s)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (previewGroups.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              for (final group in previewGroups)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _PkDebugGroupPreview(group: group),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      PrismButton(
                        label: 'Seed repair review from first group',
                        icon: AppIcons.addCircle,
                        tone: PrismButtonTone.outlined,
                        expanded: true,
                        enabled: !isBusy && groups.isNotEmpty,
                        onPressed: () => unawaited(seedReview(setSheetState)),
                      ),
                    ],
                    if (lastReport != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Last repair: ${lastReport!.pendingReviewCount} pending, '
                        '${lastReport!.duplicateSetsMerged} merged, '
                        '${lastReport!.backfilledEntries} backfilled.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (seedSummary != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        seedSummary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    PrismButton(
                      label: 'Open PluralKit setup',
                      icon: AppIcons.arrowForward,
                      tone: PrismButtonTone.subtle,
                      expanded: true,
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        context.push(AppRoutePaths.settingsPluralkit);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      tokenController.dispose();
    }
  }

  Future<String> _seedPkGroupReviewFixture(PkRepairReferenceData data) async {
    final group = data.groups.firstWhere(
      (group) => group.memberIds != null,
      orElse: () => data.groups.first,
    );
    final membersByUuid = {
      for (final member in data.members) member.uuid: member,
    };
    final memberUuids = (group.memberIds ?? const <String>[])
        .where(membersByUuid.containsKey)
        .take(12)
        .toList(growable: false);
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final reviewGroupId = 'debug-pk-review-${_debugSafeId(group.uuid)}';

    await db.transaction(() async {
      await db
          .into(db.memberGroups)
          .insertOnConflictUpdate(
            MemberGroupsCompanion.insert(
              id: reviewGroupId,
              name: 'Debug review: ${group.displayName ?? group.name}',
              description: drift.Value(group.description),
              colorHex: drift.Value(
                group.color == null ? null : '#${group.color}',
              ),
              createdAt: now,
              pluralkitId: drift.Value(group.id),
              syncSuppressed: const drift.Value(true),
              suspectedPkGroupUuid: drift.Value(group.uuid),
            ),
          );

      for (final memberUuid in memberUuids) {
        final member = membersByUuid[memberUuid]!;
        var localMemberId = await _localMemberIdForPkUuid(db, memberUuid);
        localMemberId ??= 'debug-pk-member-${_debugSafeId(memberUuid)}';

        await db
            .into(db.members)
            .insertOnConflictUpdate(
              MembersCompanion.insert(
                id: localMemberId,
                name: member.displayName ?? member.name,
                pronouns: drift.Value(member.pronouns),
                bio: drift.Value(member.description),
                customColorHex: drift.Value(
                  member.color == null ? null : '#${member.color}',
                ),
                customColorEnabled: drift.Value(member.color != null),
                createdAt: now,
                pluralkitUuid: drift.Value(member.uuid),
                pluralkitId: drift.Value(member.id),
                displayName: drift.Value(member.displayName),
                birthday: drift.Value(member.birthday),
                proxyTagsJson: drift.Value(member.proxyTagsJson),
              ),
            );

        await db
            .into(db.memberGroupEntries)
            .insertOnConflictUpdate(
              MemberGroupEntriesCompanion.insert(
                id: 'debug-pk-review-entry-${_debugSafeId(group.uuid)}-${_debugSafeId(memberUuid)}',
                groupId: reviewGroupId,
                memberId: localMemberId,
                pkGroupUuid: drift.Value(group.uuid),
                pkMemberUuid: drift.Value(memberUuid),
                isDeleted: const drift.Value(false),
              ),
            );
      }
    });

    final memberText = memberUuids.length == 1 ? 'member' : 'members';
    return 'Seeded review card for ${group.displayName ?? group.name} '
        'with ${memberUuids.length} $memberText.';
  }

  Future<String?> _localMemberIdForPkUuid(
    AppDatabase db,
    String pkMemberUuid,
  ) async {
    final row =
        await (db.select(db.members)
              ..where((member) => member.pluralkitUuid.equals(pkMemberUuid))
              ..limit(1))
            .getSingleOrNull();
    return row?.id;
  }

  String _debugSafeId(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmReset(BuildContext context) async {
    // First confirmation.
    final first = await PrismDialog.confirm(
      context: context,
      title: context.l10n.debugResetDatabaseConfirm1Title,
      message: context.l10n.debugResetDatabaseConfirm1Message,
      confirmLabel: context.l10n.continueLabel,
      destructive: true,
    );

    if (!first || !context.mounted) return;

    // Second confirmation.
    final second = await PrismDialog.confirm(
      context: context,
      title: context.l10n.debugResetDatabaseConfirm2Title,
      message: context.l10n.debugResetDatabaseConfirm2Message,
      confirmLabel: context.l10n.debugDeleteEverything,
      destructive: true,
    );

    if (!second || !context.mounted) return;

    try {
      await ref
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.all);
      if (!context.mounted) return;
      PrismToast.show(context, message: context.l10n.debugDatabaseResetSuccess);
    } catch (e) {
      if (!context.mounted) return;
      PrismToast.error(context, message: context.l10n.debugFailedToReset(e));
    }
  }

  static const _availablePresets = [
    StressPreset.medium,
    StressPreset.large,
    StressPreset.extreme,
    StressPreset.huge,
    StressPreset.massive,
  ];

  Future<void> _showPresetPicker(BuildContext context) async {
    const presets = _availablePresets;
    final preset = await PrismSheet.show<StressPreset>(
      context: context,
      title: context.l10n.debugSelectPreset,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in presets)
            PrismListRow(
              title: Text(p.label),
              subtitle: Text(
                '${p.members} members, ${p.sessions} sessions '
                '\u2022 ~${p.estimatedSizeMb}MB, ~${p.estimatedSeconds}s',
              ),
              onTap: () => Navigator.pop(context, p),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );

    if (preset == null || !mounted) return;

    final db = ref.read(databaseProvider);
    final generator = StressDataGenerator(db);
    final hasExisting = await generator.hasExistingData();

    if (!context.mounted) return;

    if (hasExisting) {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: context.l10n.debugDatabaseNotEmpty,
        message: context.l10n.debugDatabaseNotEmptyMessage,
      );
      if (!confirmed || !mounted) return;
    }

    unawaited(_runGeneration(preset));
  }

  Future<void> _runGeneration(StressPreset preset) async {
    setState(() {
      _isGenerating = true;
      _progress = null;
      _currentPreset = preset;
    });

    try {
      final db = ref.read(databaseProvider);
      final generator = StressDataGenerator(db);

      await for (final progress in generator.generate(preset)) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      }

      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.debugStressGenerated(preset.label),
        );
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.debugGenerationFailed(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _progress = null;
          _currentPreset = null;
        });
      }
    }
  }

  Future<void> _confirmClearStressData(BuildContext context) async {
    final db = ref.read(databaseProvider);
    final generator = StressDataGenerator(db);
    final hasStress = await generator.hasStressData();

    if (!hasStress) {
      if (context.mounted) {
        PrismToast.show(context, message: context.l10n.debugNoStressData);
      }
      return;
    }

    if (!context.mounted) return;

    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.debugClearStressDataTitle,
      message: context.l10n.debugClearStressDataMessage,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isClearing = true);
    try {
      await generator.clearStressData();
      if (context.mounted) {
        PrismToast.show(context, message: context.l10n.debugStressDataCleared);
      }
    } catch (e) {
      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.debugFailedToClearStress(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }
}

class _PkDebugGroupPreview extends StatelessWidget {
  const _PkDebugGroupPreview({required this.group});

  final PKGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = group.memberIds;
    final memberText = members == null
        ? 'members hidden'
        : '${members.length} members';

    return Row(
      children: [
        if (group.color != null)
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _parsePkColor(group.color!) ?? theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          )
        else
          Icon(
            AppIcons.group,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.displayName ?? group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${group.id} · $memberText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

  Color? _parsePkColor(String color) {
    final normalized = color.replaceFirst('#', '');
    if (normalized.length != 6) return null;
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}

class _DebugRow extends StatelessWidget {
  const _DebugRow({
    required this.label,
    required this.value,
    this.warn = false,
  });

  final String label;
  final String value;

  /// Tint the value in the warning color to flag values that should not be
  /// trusted in production (e.g. a dirty working-tree build, or a value
  /// that fell back to the `dev` default because the build wrapper wasn't
  /// used).
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: warn
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
