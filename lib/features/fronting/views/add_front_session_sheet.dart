import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/selected_member_picker.dart';

/// Modal for creating a new fronting session with full details.
///
/// Opens via [PrismSheet.showFullScreen] for consistency with other modals.
class AddFrontSessionSheet extends ConsumerStatefulWidget {
  const AddFrontSessionSheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  /// Opens the sheet using the standard full-screen modal pattern.
  static Future<bool?> show(BuildContext context) {
    return PrismSheet.showFullScreen<bool>(
      context: context,
      builder: (context, scrollController) =>
          AddFrontSessionSheet(scrollController: scrollController),
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
  bool _saving = false;

  bool get _frontAsUnknown => _selectedIds.length == 1 && _selectedIds.contains(_unknownId);
  // The real member IDs to pass to startFronting (excludes the Unknown sentinel).
  List<String> get _memberIds =>
      _selectedIds.where((id) => id != _unknownId).toList();
  bool get _canSubmit => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  /// Starts one session per selected member, all sharing the same start time.
  ///
  /// If the Unknown sentinel is the only selection, passes an empty list —
  /// the mutation service creates a single Unknown session (memberId = null).
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);

    try {
      final notifier = ref.read(frontingNotifierProvider.notifier);
      final trimmedNotes = _notesController.text.trim();

      if (_frontAsUnknown) {
        // Unknown fronter — single session with memberId = null.
        // startFronting([]) produces one Unknown row in the mutation service.
        await notifier.startFronting(
          [],
          confidence: _confidence,
          notes: trimmedNotes.isNotEmpty ? trimmedNotes : null,
        );
      } else {
        // Multi-member: each id gets its own session row sharing start_time.
        // Iterating .sessions is correct; do not use .sessions.single because
        // the user may have selected more than one member.
        await notifier.startFronting(
          _memberIds,
          confidence: _confidence,
          notes: trimmedNotes.isNotEmpty ? trimmedNotes : null,
        );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final membersAsync = ref.watch(activeMembersProvider);
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final activeSessions = activeSessionsAsync.whenOrNull(data: (s) => s) ?? [];
    // Per-member model: each session is one member's continuous presence.
    final frontingMemberIds = <String>{
      for (final s in activeSessions)
        if (s.memberId != null) s.memberId!,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 100) return const SizedBox.shrink();
        return Column(
          children: [
            PrismSheetTopBar(
              title: context.l10n.frontingNewSession,
              trailing: PrismGlassIconButton(
                icon: AppIcons.check,
                tooltip: context.l10n.frontingStartSessionTooltip,
                onPressed: (_saving || !_canSubmit) ? null : _submit,
              ),
            ),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                children: [
                  // Section header — multi-select replaces primary + co-fronter.
                  // TODO(§2.5): Phase 3 — show "already fronting" members as
                  // deselect-to-end with "— ends session" hint per spec §2.5.
                  Text(
                    context.l10n.frontingSelectFronter,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  membersAsync.when(
                    loading: () => const PrismLoadingState(),
                    error: (e, _) => Text('Error: $e'),
                    data: (members) => _MemberGrid(
                      members: members,
                      selectedIds: _selectedIds,
                      unknownId: _unknownId,
                      pluralTerm: terms.pluralLower,
                      frontingMemberIds: frontingMemberIds,
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
                    ),
                  ),
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
                  PrismTextField(
                    key: _notesKey,
                    controller: _notesController,
                    focusNode: _notesFocus,
                    labelText: context.l10n.frontingNotes,
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
    this.frontingMemberIds = const {},
  });

  final List<Member> members;
  final Set<String> selectedIds;
  final String unknownId;
  final ValueChanged<String> onToggle;
  final String pluralTerm;
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
    return _buildLargeGrid(context);
  }

  // ---------------------------------------------------------------------------
  // Large grid (≤12 members): 3 columns, big avatars, multi-select
  // ---------------------------------------------------------------------------

  Widget _buildLargeGrid(BuildContext context) {
    final theme = Theme.of(context);
    // Always include the Unknown tile.
    final totalCount = widget.members.length + 1;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: 0.85,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index == totalCount - 1) {
          return _gridUnknownTile(theme);
        }
        return _gridMemberTile(theme, widget.members[index]);
      },
    );
  }

  Widget _gridMemberTile(ThemeData theme, Member member) {
    final isSelected = widget.selectedIds.contains(member.id);
    final isFronting = widget.frontingMemberIds.contains(member.id);
    return GestureDetector(
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
                avatarImageData: member.avatarImageData,
                memberName: member.name,
                emoji: member.emoji,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                size: 72,
                tintOverride: isFronting
                    ? AppColors.fronting(theme.brightness)
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              member.name,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (isFronting) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                      context.l10n.frontingFronting,
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
            const SizedBox(height: 10),
            Text(
              'Unknown',
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
    final searchGroups = watchMemberSearchGroups(ref, widget.members);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectedMultiMemberPicker(
          key: const Key('addFrontSessionSelectedMemberPicker'),
          members: widget.members,
          selectedMemberIds: widget.selectedIds
              .where((id) => id != widget.unknownId)
              .toSet(),
          onPressed: () => _openSearch(context, widget.members, searchGroups),
        ),
      ],
    );
  }

  /// Opens [MemberSearchSheet] in multi-select mode.
  Future<void> _openSearch(
    BuildContext context,
    List<Member> candidates,
    List<MemberSearchGroup> groups,
  ) async {
    final result = await MemberSearchSheet.showMulti(
      context,
      members: candidates,
      termPlural: widget.pluralTerm,
      groups: groups,
      initialSelected: widget.selectedIds
          .where((id) => id != widget.unknownId)
          .toSet(),
    );

    if (!mounted || result == null) return;
    // Replace current non-unknown selections with the new set.
    for (final id in result) {
      widget.onToggle(id);
    }
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
