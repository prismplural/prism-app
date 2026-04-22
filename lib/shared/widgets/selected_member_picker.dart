import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

const double _kSelectedMemberPickerMaxHeight = 320;

class SelectedMemberPicker extends ConsumerWidget {
  const SelectedMemberPicker({
    super.key,
    required this.selectedMemberId,
    required this.onPressed,
    this.includeUnknown = true,
    this.unknownSelected = false,
    this.showPronouns = true,
    this.members,
  });

  final String? selectedMemberId;
  final VoidCallback onPressed;
  final bool includeUnknown;
  final bool unknownSelected;
  final bool showPronouns;
  final List<Member>? members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providedMembers = members;
    if (providedMembers != null) {
      return _SelectedMemberPickerBody(
        selectedMemberId: selectedMemberId,
        onPressed: onPressed,
        includeUnknown: includeUnknown,
        unknownSelected: unknownSelected,
        showPronouns: showPronouns,
        members: providedMembers,
      );
    }

    final membersAsync = ref.watch(activeMembersProvider);
    return membersAsync.when(
      loading: () => const SizedBox(height: 56, child: PrismLoadingState()),
      error: (e, _) => Text(context.l10n.errorWithDetail(e)),
      data: (members) => _SelectedMemberPickerBody(
        selectedMemberId: selectedMemberId,
        onPressed: onPressed,
        includeUnknown: includeUnknown,
        unknownSelected: unknownSelected,
        showPronouns: showPronouns,
        members: members,
      ),
    );
  }
}

class _SelectedMemberPickerBody extends ConsumerWidget {
  const _SelectedMemberPickerBody({
    required this.selectedMemberId,
    required this.onPressed,
    required this.includeUnknown,
    required this.unknownSelected,
    required this.showPronouns,
    required this.members,
  });

  final String? selectedMemberId;
  final VoidCallback onPressed;
  final bool includeUnknown;
  final bool unknownSelected;
  final bool showPronouns;
  final List<Member> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = watchTerminology(context, ref);
    final selected = selectedMemberId != null
        ? members.where((m) => m.id == selectedMemberId).firstOrNull
        : null;

    if (selected == null && !(includeUnknown && unknownSelected)) {
      return _EmptyPickerButton(
        label: context.l10n.selectMember(terms.singular),
        onPressed: onPressed,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _PickerAddButton(onPressed: onPressed),
        ),
        const SizedBox(height: 8),
        if (includeUnknown && unknownSelected)
          const _SelectedUnknownTile()
        else if (selected != null)
          _SelectedMemberTile(member: selected, showPronouns: showPronouns),
      ],
    );
  }
}

class SelectedMultiMemberPicker extends ConsumerWidget {
  const SelectedMultiMemberPicker({
    super.key,
    required this.selectedMemberIds,
    required this.onPressed,
    this.showPronouns = true,
    this.members,
    this.maxHeight = _kSelectedMemberPickerMaxHeight,
  });

  final Set<String> selectedMemberIds;
  final VoidCallback onPressed;
  final bool showPronouns;
  final List<Member>? members;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providedMembers = members;
    if (providedMembers != null) {
      return _SelectedMultiMemberPickerBody(
        selectedMemberIds: selectedMemberIds,
        onPressed: onPressed,
        showPronouns: showPronouns,
        members: providedMembers,
        maxHeight: maxHeight,
      );
    }

    final membersAsync = ref.watch(activeMembersProvider);
    return membersAsync.when(
      loading: () => const SizedBox(height: 56, child: PrismLoadingState()),
      error: (e, _) => Text(context.l10n.errorWithDetail(e)),
      data: (members) => _SelectedMultiMemberPickerBody(
        selectedMemberIds: selectedMemberIds,
        onPressed: onPressed,
        showPronouns: showPronouns,
        members: members,
        maxHeight: maxHeight,
      ),
    );
  }
}

class _SelectedMultiMemberPickerBody extends ConsumerWidget {
  const _SelectedMultiMemberPickerBody({
    required this.selectedMemberIds,
    required this.onPressed,
    required this.showPronouns,
    required this.members,
    required this.maxHeight,
  });

  final Set<String> selectedMemberIds;
  final VoidCallback onPressed;
  final bool showPronouns;
  final List<Member> members;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = watchTerminology(context, ref);
    final selectedMembers = members
        .where((member) => selectedMemberIds.contains(member.id))
        .toList();

    if (selectedMembers.isEmpty) {
      return _EmptyPickerButton(
        label: context.l10n.selectMembers(terms.plural),
        onPressed: onPressed,
      );
    }

    final listHeight = math.min(maxHeight, selectedMembers.length * 72.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _PickerAddButton(onPressed: onPressed),
        ),
        const SizedBox(height: 8),
        SizedBox(
          key: const Key('selectedMemberPickerList'),
          height: listHeight,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: selectedMembers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _SelectedMemberTile(
              member: selectedMembers[index],
              showPronouns: showPronouns,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPickerButton extends StatelessWidget {
  const _EmptyPickerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: PrismButton(
        key: const Key('selectedMemberPickerSelectButton'),
        label: label,
        icon: AppIcons.add,
        tone: PrismButtonTone.outlined,
        onPressed: onPressed,
      ),
    );
  }
}

class _PickerAddButton extends StatelessWidget {
  const _PickerAddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PrismIconButton(
      key: const Key('selectedMemberPickerAddButton'),
      icon: AppIcons.add,
      tooltip: context.l10n.search,
      semanticLabel: context.l10n.search,
      onPressed: onPressed,
    );
  }
}

class _SelectedMemberTile extends StatelessWidget {
  const _SelectedMemberTile({required this.member, required this.showPronouns});

  final Member member;
  final bool showPronouns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(16)),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            MemberAvatar(
              avatarImageData: member.avatarImageData,
              memberName: member.name,
              emoji: member.emoji,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name, style: theme.textTheme.titleSmall),
                  if (showPronouns && member.pronouns != null)
                    Text(
                      member.pronouns!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedUnknownTile extends StatelessWidget {
  const _SelectedUnknownTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(16)),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
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
          ],
        ),
      ),
    );
  }
}
