import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

// ---------------------------------------------------------------------------
// Single-select variant
// ---------------------------------------------------------------------------

/// Inline expandable picker for selecting a single member.
///
/// Collapsed: shows selected member avatar + name (or placeholder).
/// Expanded: animated list of all active members with selection checkmark.
const double _kInlinePickerMaxExpandedHeight = 320;

class InlineExpandableMemberPicker extends ConsumerStatefulWidget {
  const InlineExpandableMemberPicker({
    super.key,
    required this.selectedMemberId,
    required this.onChanged,
    this.includeUnknown = true,
    this.unknownSelected = false,
    this.onUnknownSelected,
    this.showPronouns = true,
    this.members,
    this.maxExpandedHeight = _kInlinePickerMaxExpandedHeight,
  });

  final String? selectedMemberId;
  final ValueChanged<String?> onChanged;
  final bool includeUnknown;
  final bool unknownSelected;
  final VoidCallback? onUnknownSelected;
  final bool showPronouns;
  final List<Member>? members;
  final double maxExpandedHeight;

  @override
  ConsumerState<InlineExpandableMemberPicker> createState() =>
      _InlineExpandableMemberPickerState();
}

class _InlineExpandableMemberPickerState
    extends ConsumerState<InlineExpandableMemberPicker> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(activeMembersProvider);

    final providedMembers = widget.members;
    if (providedMembers != null) {
      return _buildPicker(context, providedMembers);
    }

    return membersAsync.when(
      loading: () => const SizedBox(height: 56, child: PrismLoadingState()),
      error: (e, _) => Text(context.l10n.errorWithDetail(e)),
      data: (members) => _buildPicker(context, members),
    );
  }

  Widget _buildPicker(BuildContext context, List<Member> members) {
    final selected = widget.selectedMemberId != null
        ? members.where((m) => m.id == widget.selectedMemberId).firstOrNull
        : null;
    final terms = watchTerminology(context, ref);
    final unknownSelected = widget.includeUnknown && widget.unknownSelected;
    final collapsedLabel = unknownSelected
        ? context.l10n.unknown
        : selected?.name ?? context.l10n.selectMember(terms.singular);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsed header
          Semantics(
            button: true,
            expanded: _expanded,
            label: collapsedLabel,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    if (unknownSelected) ...[
                      const MemberAvatar(emoji: '\u2754', size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.unknown,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ] else if (selected != null) ...[
                      MemberAvatar(
                        avatarImageData: selected.avatarImageData,
                        memberName: selected.name,
                        emoji: selected.emoji,
                        customColorEnabled: selected.customColorEnabled,
                        customColorHex: selected.customColorHex,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (widget.showPronouns &&
                                selected.pronouns != null) ...[
                              Text(
                                selected.pronouns!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else ...[
                      const MemberAvatar(emoji: '\u2754', size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.selectAMember(terms.singularLower),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(AppIcons.expandMore),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded list
          if (_expanded) ...[
            const Divider(height: 1),
            _buildExpandedList(
              context,
              itemCount: members.length + (widget.includeUnknown ? 1 : 0),
              itemBuilder: (context, index) {
                if (widget.includeUnknown) {
                  if (index == 0) {
                    return _MemberRow(
                      avatar: const MemberAvatar(emoji: '\u2754', size: 40),
                      name: context.l10n.unknown,
                      pronouns: null,
                      showPronouns: false,
                      isSelected: unknownSelected,
                      onTap: () {
                        final onUnknownSelected = widget.onUnknownSelected;
                        if (onUnknownSelected != null) {
                          onUnknownSelected();
                        } else {
                          widget.onChanged(null);
                        }
                        setState(() => _expanded = false);
                      },
                    );
                  }
                  index -= 1;
                }

                final member = members[index];
                return _MemberRow(
                  avatar: MemberAvatar(
                    avatarImageData: member.avatarImageData,
                    memberName: member.name,
                    emoji: member.emoji,
                    customColorEnabled: member.customColorEnabled,
                    customColorHex: member.customColorHex,
                    size: 40,
                  ),
                  name: member.name,
                  pronouns: member.pronouns,
                  showPronouns: widget.showPronouns,
                  isSelected: member.id == widget.selectedMemberId,
                  onTap: () {
                    widget.onChanged(member.id);
                    setState(() => _expanded = false);
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedList(
    BuildContext context, {
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    final listHeight = math.min(widget.maxExpandedHeight, itemCount * 64.0);
    return SizedBox(
      key: const Key('inlineExpandablePickerList'),
      height: listHeight,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-select variant
// ---------------------------------------------------------------------------

/// Inline expandable picker for selecting multiple members.
///
/// Collapsed states:
///   - Empty: placeholder text
///   - One: avatar + name
///   - Multiple: stacked avatars + count
/// Expanded: list with circle checkboxes, tapping toggles without collapsing.
class InlineExpandableMultiMemberPicker extends ConsumerStatefulWidget {
  const InlineExpandableMultiMemberPicker({
    super.key,
    required this.selectedMemberIds,
    required this.onChanged,
    this.showPronouns = true,
    this.members,
    this.maxExpandedHeight = _kInlinePickerMaxExpandedHeight,
  });

  final Set<String> selectedMemberIds;
  final ValueChanged<Set<String>> onChanged;
  final bool showPronouns;
  final List<Member>? members;
  final double maxExpandedHeight;

  @override
  ConsumerState<InlineExpandableMultiMemberPicker> createState() =>
      _InlineExpandableMultiMemberPickerState();
}

class _InlineExpandableMultiMemberPickerState
    extends ConsumerState<InlineExpandableMultiMemberPicker> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(activeMembersProvider);

    final providedMembers = widget.members;
    if (providedMembers != null) {
      return _buildPicker(context, providedMembers);
    }

    return membersAsync.when(
      loading: () => const SizedBox(height: 56, child: PrismLoadingState()),
      error: (e, _) => Text(context.l10n.errorWithDetail(e)),
      data: (members) => _buildPicker(context, members),
    );
  }

  Widget _buildPicker(BuildContext context, List<Member> members) {
    final selected = members
        .where((m) => widget.selectedMemberIds.contains(m.id))
        .toList();
    final terms = watchTerminology(context, ref);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsed header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  ..._buildCollapsedContent(context, selected, terms.plural),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(AppIcons.expandMore),
                  ),
                ],
              ),
            ),
          ),

          // Expanded list
          if (_expanded) ...[
            const Divider(height: 1),
            SizedBox(
              key: const Key('inlineExpandablePickerList'),
              height: math.min(widget.maxExpandedHeight, members.length * 64.0),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final member = members[index];
                  return _MemberRow(
                    avatar: MemberAvatar(
                      avatarImageData: member.avatarImageData,
                      memberName: member.name,
                      emoji: member.emoji,
                      customColorEnabled: member.customColorEnabled,
                      customColorHex: member.customColorHex,
                      size: 40,
                    ),
                    name: member.name,
                    pronouns: member.pronouns,
                    showPronouns: widget.showPronouns,
                    isSelected: widget.selectedMemberIds.contains(member.id),
                    useCheckbox: true,
                    onTap: () {
                      final updated = Set<String>.from(
                        widget.selectedMemberIds,
                      );
                      if (updated.contains(member.id)) {
                        updated.remove(member.id);
                      } else {
                        updated.add(member.id);
                      }
                      widget.onChanged(updated);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildCollapsedContent(
    BuildContext context,
    List<Member> selected,
    String termPlural,
  ) {
    if (selected.isEmpty) {
      return [
        const MemberAvatar(emoji: '\u2754', size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10n.selectMembers(termPlural),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    if (selected.length == 1) {
      final member = selected.first;
      return [
        MemberAvatar(
          avatarImageData: member.avatarImageData,
          memberName: member.name,
          emoji: member.emoji,
          customColorEnabled: member.customColorEnabled,
          customColorHex: member.customColorHex,
          size: 44,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            member.name,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ];
    }

    // Multiple: stacked avatars
    const avatarSize = 36.0;
    const overlap = 24.0;
    final displayCount = selected.length > 4 ? 4 : selected.length;
    final stackWidth = avatarSize + (displayCount - 1) * overlap;

    return [
      SizedBox(
        width: stackWidth,
        height: avatarSize,
        child: Stack(
          children: [
            for (var i = 0; i < displayCount; i++)
              Positioned(
                left: i * overlap,
                child: MemberAvatar(
                  avatarImageData: selected[i].avatarImageData,
                  memberName: selected[i].name,
                  emoji: selected[i].emoji,
                  customColorEnabled: selected[i].customColorEnabled,
                  customColorHex: selected[i].customColorHex,
                  size: avatarSize,
                  showBorder: true,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          '${selected.length} selected',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Shared row widget
// ---------------------------------------------------------------------------

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.avatar,
    required this.name,
    this.pronouns,
    this.showPronouns = true,
    required this.isSelected,
    this.useCheckbox = false,
    required this.onTap,
  });

  final Widget avatar;
  final String name;
  final String? pronouns;
  final bool showPronouns;
  final bool isSelected;
  final bool useCheckbox;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.bodyLarge),
                  if (showPronouns && pronouns != null)
                    Text(
                      pronouns!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (useCheckbox)
              Icon(
                isSelected
                    ? AppIcons.checkCircle
                    : AppIcons.radioButtonUnchecked,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              )
            else if (isSelected)
              Icon(AppIcons.check, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
