import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/modal_side_sheet_marker.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/selected_member_picker.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

enum _SessionTimingMode { startEarlier, startNow, pastSession }

/// Modal for creating a new fronting session with full details.
///
/// Opens via [PrismSheet.showFullScreen] for consistency with other modals.
class AddFrontSessionSheet extends ConsumerStatefulWidget {
  const AddFrontSessionSheet({
    super.key,
    required this.scrollController,
    this.initialHistorical = false,
  });

  final ScrollController scrollController;
  final bool initialHistorical;

  /// Opens the sheet using the standard full-screen modal pattern.
  static Future<bool?> show(
    BuildContext context, {
    bool initialHistorical = false,
  }) {
    return PrismSheet.showFullScreen<bool>(
      context: context,
      builder: (context, scrollController) => AddFrontSessionSheet(
        scrollController: scrollController,
        initialHistorical: initialHistorical,
      ),
    );
  }

  @override
  ConsumerState<AddFrontSessionSheet> createState() =>
      _AddFrontSessionSheetState();
}

/// State for [AddFrontSessionSheet].
///
/// Per spec §2.5 the old "primary + co-fronter picker" UX is replaced by a
/// single multi-select: the user picks one or more members and each selection
/// becomes its own session with the same start time.
///
/// Differences from the old shape:
/// - `_selectedIds` is now a multi-value set (was single primary + separate
///   co-fronter set).
/// - `_coFrontMode` toggle is removed — adding a co-fronter to an existing
///   front is now done by opening this sheet and selecting the member.
/// - `addCoFronter` is no longer called; we always call `startFronting(ids)`.
///
/// TODO(§2.5): Phase 3 — polish multi-select grid to show "already fronting"
/// members as deselect-to-end, with "— ends session" hint under deselection.
class _AddFrontSessionSheetState extends ConsumerState<AddFrontSessionSheet>
    with WidgetsBindingObserver {
  static const _unknownId = '__unknown__';

  // Multi-select set: each id becomes its own session row.
  // `_unknownId` sentinel represents Unknown fronter (single, exclusive).
  final Set<String> _selectedIds = {};

  FrontConfidence? _confidence;
  final _notesController = TextEditingController();
  final _notesFocus = FocusNode();
  final _notesKey = GlobalKey();
  late DateTime _startTime;
  DateTime? _endTime;
  late _SessionTimingMode _timingMode;
  bool _saving = false;

  /// Per-action override of the add-front behavior. Initialised from the
  /// `add_front_default_behavior` system setting on first build (see
  /// [_resolvedMode]) and toggled by the segmented control. NEVER written
  /// back to the setting — the segmented control is a per-submit override
  /// only.
  ///
  /// Null until the user touches the segmented control; once non-null, the
  /// user's local pick is sticky for the rest of the sheet's lifetime.
  FrontStartBehavior? _modeOverride;

  /// The mode to use for the next submit: explicit override if set,
  /// otherwise the persisted preference (with [FrontStartBehavior.additive]
  /// as a fallback if settings haven't loaded yet).
  FrontStartBehavior _resolvedMode(FrontStartBehavior preferenceDefault) =>
      _modeOverride ?? preferenceDefault;

  bool get _frontAsUnknown =>
      _selectedIds.length == 1 && _selectedIds.contains(_unknownId);
  // The real member IDs to pass to startFronting (excludes the Unknown sentinel).
  List<String> get _memberIds =>
      _selectedIds.where((id) => id != _unknownId).toList();
  bool get _canSubmit => _selectedIds.isNotEmpty;
  bool get _isDirty => _notesController.text.trim().isNotEmpty;
  bool get _isHistorical => _timingMode == _SessionTimingMode.pastSession;
  bool get _isStartEarlier => _timingMode == _SessionTimingMode.startEarlier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timingMode = widget.initialHistorical
        ? _SessionTimingMode.pastSession
        : _SessionTimingMode.startNow;
    if (_isHistorical) {
      _startTime = DateTime.now().subtract(const Duration(hours: 1));
      _endTime = DateTime.now();
    } else {
      _startTime = DateTime.now();
      _endTime = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notesFocus.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Fires on every frame of the keyboard animation. Scroll the focused
    // field into view so it tracks alongside the keyboard.
    if (_notesFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _notesKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// Submits one or more sessions for the selected members.
  ///
  /// Branches on [mode]:
  /// - [FrontStartBehavior.additive]: existing behavior — `startFronting`
  ///   creates one row per selected member, leaving any other active
  ///   sessions untouched.
  /// - [FrontStartBehavior.replace]: `replaceFronting` ends every active
  ///   normal session AND starts the new ones in a single transaction
  ///   with one captured `now` (atomic — a crash mid-block leaves the
  ///   prior state intact, not "no fronts at all").
  ///
  /// If the Unknown sentinel is the only selection, passes
  /// `[unknownSentinelMemberId]` — the mutation service auto-creates the
  /// sentinel member if it doesn't exist, then writes a single session
  /// row attributed to it.
  Future<void> _submit(FrontStartBehavior mode) async {
    if (_saving || !_canSubmit) return;
    setState(() => _saving = true);

    try {
      final notifier = ref.read(frontingNotifierProvider.notifier);
      final trimmedNotes = _notesController.text.trim();

      // Multi-member: each id gets its own session row sharing start_time.
      // The Unknown sentinel id is treated like any other member id — the
      // mutation service auto-creates the sentinel member if needed.
      final ids = _frontAsUnknown
          ? <String>[unknownSentinelMemberId]
          : _memberIds;
      final notes = trimmedNotes.isNotEmpty ? trimmedNotes : null;

      if (_isHistorical) {
        final endTime = _endTime;
        if (endTime == null || !endTime.isAfter(_startTime)) {
          PrismToast.error(
            context,
            message: context.l10n.frontingEndTimeMustBeAfterStart,
          );
          return;
        }
        await notifier.logHistoricalFronting(
          ids,
          startTime: _startTime,
          endTime: endTime,
          confidence: _confidence,
          notes: notes,
        );
      } else {
        switch (mode) {
          case FrontStartBehavior.additive:
            await notifier.startFronting(
              ids,
              startTime: _isStartEarlier ? _startTime : null,
              confidence: _confidence,
              notes: notes,
            );
          case FrontStartBehavior.replace:
            await notifier.replaceFronting(
              ids,
              startTime: _isStartEarlier ? _startTime : null,
              confidence: _confidence,
              notes: notes,
            );
        }
      }
      Haptics.success();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorCreatingSession(e),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setTimingMode(_SessionTimingMode timingMode) {
    setState(() {
      _timingMode = timingMode;
      switch (timingMode) {
        case _SessionTimingMode.startEarlier:
          _startTime = DateTime.now().subtract(const Duration(minutes: 15));
          _endTime = null;
        case _SessionTimingMode.startNow:
          _startTime = DateTime.now();
          _endTime = null;
        case _SessionTimingMode.pastSession:
          _startTime = DateTime.now().subtract(const Duration(hours: 1));
          _endTime = DateTime.now();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final frontingTerms = watchFrontingTerms(context, ref);
    final membersAsync = ref.watch(activeMemberListProvider);
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final activeSessions = activeSessionsAsync.whenOrNull(data: (s) => s) ?? [];
    // Per-member model: each session is one member's continuous presence.
    final frontingMemberIds = <String>{
      for (final s in activeSessions)
        if (s.memberId != null) s.memberId!,
    };

    // Read the persisted default for the segmented control's initial state.
    // Falls back to additive while the stream is loading. The segmented
    // control's selected value is _modeOverride ?? settingDefault, so:
    //   - first build before user touches it: tracks the persisted setting
    //   - after user toggles: stays on their pick for the rest of this sheet
    //   - when sheet closes: nothing is written back to the setting
    final settingsAsync = ref.watch(systemSettingsProvider);
    final settingDefault =
        settingsAsync.whenOrNull(data: (s) => s.addFrontDefaultBehavior) ??
        FrontStartBehavior.additive;
    final mode = _resolvedMode(settingDefault);

    return ListenableBuilder(
      listenable: _notesController,
      builder: (context, _) => UnsavedChangesGuard<bool>(
        hasUnsavedChanges: _isDirty,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight < 100) return const SizedBox.shrink();
            return Column(
              children: [
                PrismSheetTopBar(
                  title: _isHistorical
                      ? frontingTerms.logPastAction
                      : frontingTerms.sessionSingular,
                  trailing: PrismGlassIconButton(
                    icon: AppIcons.check,
                    tooltip: _isHistorical
                        ? frontingTerms.logPastAction
                        : frontingTerms.logAction,
                    onPressed: (_saving || !_canSubmit)
                        ? null
                        : () => _submit(mode),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: widget.scrollController,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      8,
                      24,
                      24 + modalBottomInsetOf(context),
                    ),
                    children: [
                      if (!_isHistorical)
                        PrismSegmentedControl<FrontStartBehavior>(
                          key: const Key('addFrontModeSegmentedControl'),
                          segments: [
                            PrismSegment(
                              value: FrontStartBehavior.additive,
                              label: frontingTerms.addAction,
                            ),
                            PrismSegment(
                              value: FrontStartBehavior.replace,
                              label: frontingTerms.replaceCurrentAction,
                            ),
                          ],
                          selected: mode,
                          onChanged: (m) => setState(() => _modeOverride = m),
                        ),
                      const SizedBox(height: 24),
                      // Section header — multi-select replaces primary + co-fronter.
                      // TODO(§2.5): Phase 3 — show "already fronting" members as
                      // deselect-to-end with "— ends session" hint per spec §2.5.
                      Text(
                        frontingTerms.activePluralLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      membersAsync.when(
                        loading: () => const PrismLoadingState(),
                        error: (e, _) => Text('Error: $e'),
                        data: (members) {
                          final selectableMembers = members
                              .where((m) => m.id != unknownSentinelMemberId)
                              .toList(growable: false);
                          return _MemberGrid(
                            members: selectableMembers,
                            selectedIds: _selectedIds,
                            unknownId: _unknownId,
                            pluralTerm: terms.pluralLower,
                            frontingMemberIds: frontingMemberIds,
                            activeSectionLabel:
                                frontingTerms.activeSectionLabel,
                            onToggle: (id) {
                              setState(() {
                                if (id == _unknownId) {
                                  // Unknown is exclusive — clear other selections.
                                  _selectedIds
                                    ..clear()
                                    ..add(_unknownId);
                                } else {
                                  // Deselect Unknown when picking a real member.
                                  _selectedIds.remove(_unknownId);
                                  if (_selectedIds.contains(id)) {
                                    _selectedIds.remove(id);
                                  } else {
                                    _selectedIds.add(id);
                                  }
                                }
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        frontingTerms.timeLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrismSegmentedControl<_SessionTimingMode>(
                        key: const Key('sessionTimeSegmentedControl'),
                        segments: [
                          PrismSegment(
                            value: _SessionTimingMode.startEarlier,
                            label: context.l10n.frontingSessionTimeStartEarlier,
                          ),
                          PrismSegment(
                            value: _SessionTimingMode.startNow,
                            label: context.l10n.frontingSessionTimeStartNow,
                          ),
                          PrismSegment(
                            value: _SessionTimingMode.pastSession,
                            label: frontingTerms.sessionSingular,
                          ),
                        ],
                        selected: _timingMode,
                        onChanged: (timingMode) {
                          if (_saving) return;
                          _setTimingMode(timingMode);
                        },
                      ),
                      if (_isStartEarlier || _isHistorical) ...[
                        const SizedBox(height: 16),
                        PrismDateTimePills(
                          label: context.l10n.frontingStart,
                          dateTime: _startTime,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          onChanged: (dt) => setState(() => _startTime = dt),
                        ),
                        if (_isHistorical) ...[
                          const SizedBox(height: 16),
                          PrismDateTimePills(
                            label: context.l10n.frontingEnd,
                            dateTime: _endTime ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onChanged: (dt) => setState(() => _endTime = dt),
                          ),
                        ],
                      ],
                      const SizedBox(height: 24),

                      // Confidence level picker
                      Text(
                        context.l10n.frontingConfidenceLevel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ConfidencePicker(
                        selected: _confidence,
                        onSelect: (c) => setState(() => _confidence = c),
                      ),
                      const SizedBox(height: 24),

                      // Notes
                      Text(
                        context.l10n.frontingNotes,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrismTextField(
                        key: _notesKey,
                        controller: _notesController,
                        focusNode: _notesFocus,
                        hintText: context.l10n.frontingNotesHint,
                        maxLines: 6,
                        minLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Multi-select grid for choosing who's fronting.
///
/// Switches between a large grid (≤12 members) and a compact picker with
/// search (>12 members). Each tap toggles a member in the parent's [selectedIds]
/// set via [onToggle]. The Unknown sentinel is exclusive — tapping it clears
/// all other selections.
///
/// Per spec §2.5: the old single-select primary + co-fronter picker is replaced
/// by this unified multi-select. Each selected member will become its own
/// session row with the same start_time.
class _MemberGrid extends ConsumerStatefulWidget {
  const _MemberGrid({
    required this.members,
    required this.selectedIds,
    required this.unknownId,
    required this.onToggle,
    required this.pluralTerm,
    required this.activeSectionLabel,
    this.frontingMemberIds = const {},
  });

  final List<Member> members;
  final Set<String> selectedIds;
  final String unknownId;
  final ValueChanged<String> onToggle;
  final String pluralTerm;
  final String activeSectionLabel;
  final Set<String> frontingMemberIds;

  /// Threshold above which we switch to compact picker + search.
  static const int _compactThreshold = 12;

  @override
  ConsumerState<_MemberGrid> createState() => _MemberGridState();
}

class _MemberGridState extends ConsumerState<_MemberGrid> {
  @override
  Widget build(BuildContext context) {
    if (widget.members.length > _MemberGrid._compactThreshold) {
      return _buildCompactList(context);
    }
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    return _buildLargeGrid(context, prefer);
  }

  // ---------------------------------------------------------------------------
  // Large grid (≤12 members): 3 columns, big avatars, multi-select
  // ---------------------------------------------------------------------------

  Widget _buildLargeGrid(BuildContext context, bool prefer) {
    final theme = Theme.of(context);
    final inSideSheet = ModalSideSheetMarker.of(context);
    // Always include the Unknown tile.
    final totalCount = widget.members.length + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: inSideSheet
              ? const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 128,
                  mainAxisExtent: 126,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 8,
                )
              : const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 0.94,
                ),
          itemCount: totalCount,
          itemBuilder: (context, index) {
            if (index == totalCount - 1) {
              return _gridUnknownTile(theme);
            }
            return _gridMemberTile(theme, widget.members[index], prefer);
          },
        ),
      ],
    );
  }

  Widget _gridMemberTile(ThemeData theme, Member member, bool prefer) {
    final isSelected = widget.selectedIds.contains(member.id);
    final isFronting = widget.frontingMemberIds.contains(member.id);
    final memberName = member.effectiveName(preferDisplayName: prefer);
    return GestureDetector(
      key: Key('addFrontMemberTile-${member.id}'),
      onTap: () => widget.onToggle(member.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(16),
                ),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Opacity(
              opacity: isFronting && !isSelected ? 0.5 : 1.0,
              child: MemberAvatar(
                memberId: member.id,
                avatarImageData: member.avatarImageData,
                memberName: memberName,
                emoji: member.emoji,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                size: 72,
                tintOverride: isFronting
                    ? AppColors.fronting(theme.brightness)
                    : null,
                deferAvatarLookup: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              memberName,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (isFronting) ...[
              const SizedBox(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.fronting(
                    theme.brightness,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(
                    PrismShapes.of(context).radius(8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.flashOn,
                      size: 10,
                      color: AppColors.fronting(theme.brightness),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      widget.activeSectionLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.fronting(theme.brightness),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gridUnknownTile(ThemeData theme) {
    final isSelected = widget.selectedIds.contains(widget.unknownId);
    return GestureDetector(
      key: const Key('addFrontUnknownTile'),
      onTap: () => widget.onToggle(widget.unknownId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(16),
                ),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: PrismShapes.of(context).avatarShape(),
                borderRadius: PrismShapes.of(context).avatarBorderRadius(),
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                AppIcons.questionMarkRounded,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.unknown,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Compact list (>12 members): multi-select search sheet
  // ---------------------------------------------------------------------------

  Widget _buildCompactList(BuildContext context) {
    watchMemberSearchGroupSources(ref);
    final unknownSelected = widget.selectedIds.contains(widget.unknownId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unknownSelected)
          _CompactUnknownSelection(
            onPressed: () => _openSearch(context, widget.members),
          )
        else
          SelectedMultiMemberPicker(
            key: const Key('addFrontSessionSelectedMemberPicker'),
            members: widget.members,
            selectedMemberIds: widget.selectedIds
                .where((id) => id != widget.unknownId)
                .toSet(),
            onPressed: () => _openSearch(context, widget.members),
          ),
      ],
    );
  }

  /// Opens [MemberSearchSheet] in multi-select mode.
  Future<void> _openSearch(
    BuildContext context,
    List<Member> candidates,
  ) async {
    final groups = readMemberSearchGroups(ref, candidates);
    final result = await MemberSearchSheet.showMulti(
      context,
      members: candidates,
      termPlural: widget.pluralTerm,
      groups: groups,
      specialRows: [
        MemberSearchSpecialRow(
          rowKey: 'fronting-unknown',
          title: context.l10n.unknown,
          leading: const MemberAvatar(emoji: '\u2754', size: 36),
          onTap: () => Navigator.of(context).pop(<String>{widget.unknownId}),
        ),
      ],
      initialSelected: widget.selectedIds
          .where((id) => id != widget.unknownId)
          .toSet(),
    );

    if (!mounted || result == null) return;
    // The search sheet returns the new authoritative selection (excluding the
    // Unknown sentinel, which is rendered separately on the grid). Compute the
    // symmetric difference vs. what was selected before the sheet opened, then
    // emit one toggle per id whose membership actually changed. Iterating
    // `result` and calling `onToggle` for every id would invert the selection
    // for already-selected members and leave deselected members untouched.
    final previousSelected = widget.selectedIds
        .where((id) => id != widget.unknownId)
        .toSet();
    final confirmedSelected = result.toSet();
    final toToggle = previousSelected.difference(confirmedSelected)
      ..addAll(confirmedSelected.difference(previousSelected));
    for (final id in toToggle) {
      widget.onToggle(id);
    }
  }
}

class _CompactUnknownSelection extends StatelessWidget {
  const _CompactUnknownSelection({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(PrismShapes.of(context).radius(16));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: radius,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const MemberAvatar(emoji: '\u2754', size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.unknown,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  AppIcons.chevronRight,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfidencePicker extends StatelessWidget {
  const _ConfidencePicker({required this.selected, required this.onSelect});

  final FrontConfidence? selected;
  final ValueChanged<FrontConfidence?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      FrontConfidence.unsure: l10n.frontingConfidenceUnsure,
      FrontConfidence.strong: l10n.frontingConfidenceStrong,
      FrontConfidence.certain: l10n.frontingConfidenceCertain,
    };
    return PrismSegmentedControl<FrontConfidence>(
      segments: FrontConfidence.values.map((c) {
        return PrismSegment(value: c, label: labels[c]!);
      }).toList(),
      selected: selected ?? FrontConfidence.unsure,
      onChanged: onSelect,
    );
  }
}
