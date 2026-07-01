import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/utils/member_picker_order.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

class MemberSelectorPopupSpecialRow {
  const MemberSelectorPopupSpecialRow({
    this.key,
    required this.title,
    required this.leading,
    required this.onSelected,
    this.selected = false,
    this.selectedColor,
  });

  final Key? key;
  final String title;
  final Widget leading;
  final VoidCallback onSelected;
  final bool selected;
  final Color? selectedColor;
}

class MemberSelectorPopup extends StatelessWidget {
  const MemberSelectorPopup({
    super.key,
    required this.child,
    required this.members,
    required this.termPlural,
    required this.selectedMemberId,
    required this.onMemberSelected,
    this.groups = const [],
    this.groupsBuilder,
    this.specialRows = const [],
    this.fronterIds = const {},
    this.fronterSectionLabel,
    this.searchTitle,
    this.searchLabel,
    this.preferredDirection,
    this.width = 220,
    this.maxHeight = 320,
    this.avatarSize = 32,
    this.enabled = true,
    this.semanticLabel,
    this.onBeforeShow,
    this.manualAnchorKey,
    this.anchorChild,
  });

  final Widget child;
  final List<Member> members;
  final String termPlural;
  final String? selectedMemberId;
  final ValueChanged<String> onMemberSelected;
  final List<MemberSearchGroup> groups;
  final List<MemberSearchGroup> Function()? groupsBuilder;
  final List<MemberSelectorPopupSpecialRow> specialRows;

  /// Member ids currently fronting. When non-empty, floats those members to the
  /// top of the popup, separated from the rest by a divider.
  final Set<String> fronterIds;

  /// Forwarded to the full search sheet so its floated fronter block can show
  /// a matching section label.
  final String? fronterSectionLabel;
  final String? searchTitle;
  final String? searchLabel;
  final BlurPopupDirection? preferredDirection;
  final double width;
  final double maxHeight;
  final double avatarSize;
  final bool enabled;
  final String? semanticLabel;
  final VoidCallback? onBeforeShow;

  /// When non-null, switches the anchor to [BlurPopupTrigger.manual] and
  /// exposes its state so callers can call `.show()` programmatically.
  final GlobalKey<BlurPopupAnchorState>? manualAnchorKey;

  /// Placeholder child for the anchor when in manual mode (typically an
  /// [Offstage] / [SizedBox.shrink]). Falls back to [child] when null.
  final Widget? anchorChild;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final isManual = manualAnchorKey != null;

    final sections = fronterIds.isEmpty
        ? null
        : partitionMembersForPicker(members, fronterIds);
    final hasFronterSection = sections?.hasFronterSection ?? false;
    final itemCount =
        1 +
        specialRows.length +
        (hasFronterSection
            ? sections!.fronters.length + 1 + sections.others.length
            : members.length);

    return BlurPopupAnchor(
      key: manualAnchorKey,
      trigger: isManual ? BlurPopupTrigger.manual : BlurPopupTrigger.tap,
      preferredDirection: preferredDirection,
      width: width,
      maxHeight: maxHeight,
      semanticLabel: semanticLabel,
      onBeforeShow: onBeforeShow,
      itemCount: itemCount,
      itemBuilder: (popupContext, index, close) {
        final rowIndex = preferredDirection == BlurPopupDirection.up
            ? itemCount - index - 1
            : index;
        return _buildRowAt(
          context,
          popupContext,
          rowIndex,
          close,
          sections: sections,
          hasFronterSection: hasFronterSection,
        );
      },
      child: isManual ? (anchorChild ?? child) : child,
    );
  }

  Widget _buildRowAt(
    BuildContext parentContext,
    BuildContext popupContext,
    int index,
    VoidCallback close, {
    required PickerMemberSections? sections,
    required bool hasFronterSection,
  }) {
    if (index == 0) {
      return _buildSearchRow(parentContext, popupContext, close);
    }

    final specialIndex = index - 1;
    if (specialIndex < specialRows.length) {
      return _buildSpecialRow(popupContext, specialRows[specialIndex], close);
    }

    final memberIndex = specialIndex - specialRows.length;
    if (hasFronterSection) {
      final fronters = sections!.fronters;
      if (memberIndex < fronters.length) {
        return _buildMemberRow(popupContext, fronters[memberIndex], close);
      }
      if (memberIndex == fronters.length) {
        return _buildDividerRow(popupContext);
      }
      return _buildMemberRow(
        popupContext,
        sections.others[memberIndex - fronters.length - 1],
        close,
      );
    }

    return _buildMemberRow(popupContext, members[memberIndex], close);
  }

  Widget _buildDividerRow(BuildContext context) {
    // Decorative boundary between current fronters and the rest of the roster.
    return const ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Divider(height: 1),
      ),
    );
  }

  Widget _buildSearchRow(
    BuildContext parentContext,
    BuildContext popupContext,
    VoidCallback close,
  ) {
    return PrismListRow(
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: Icon(AppIcons.search, size: 20),
      title: Text(searchLabel ?? popupContext.l10n.search),
      onTap: () async {
        close();
        await Future<void>.delayed(Duration.zero);
        if (!parentContext.mounted) return;
        final result = await MemberSearchSheet.showSingle(
          parentContext,
          members: members,
          termPlural: termPlural,
          title: searchTitle,
          groups: groupsBuilder?.call() ?? groups,
          fronterIds: fronterIds,
          fronterSectionLabel: fronterSectionLabel,
        );
        if (!parentContext.mounted || result is! MemberSearchResultSelected) {
          return;
        }
        onMemberSelected(result.memberId);
      },
    );
  }

  Widget _buildSpecialRow(
    BuildContext context,
    MemberSelectorPopupSpecialRow row,
    VoidCallback close,
  ) {
    final theme = Theme.of(context);
    final selectedColor = row.selectedColor ?? theme.colorScheme.primary;

    return PrismListRow(
      key: row.key,
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: row.leading,
      selected: row.selected,
      title: Text(
        row.title,
        style: row.selected
            ? TextStyle(color: selectedColor, fontWeight: FontWeight.w600)
            : null,
      ),
      trailing: row.selected
          ? Icon(AppIcons.check, size: 18, color: selectedColor)
          : null,
      onTap: () {
        close();
        row.onSelected();
      },
    );
  }

  Widget _buildMemberRow(
    BuildContext context,
    Member member,
    VoidCallback close,
  ) {
    final theme = Theme.of(context);
    final isSelected = member.id == selectedMemberId;
    final selectedColor = _selectedColor(theme, member);

    return Consumer(
      builder: (context, ref, _) {
        final prefer = ref.watch(memberNamePreferDisplayProvider);
        final name = member.effectiveName(preferDisplayName: prefer);
        return PrismListRow(
          key: ValueKey('member-selector-popup-${member.id}'),
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          leading: MemberAvatar(
            memberId: member.id,
            avatarImageData: member.avatarImageData,
            memberName: name,
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
            size: avatarSize,
            deferAvatarLookup: true,
          ),
          selected: isSelected,
          title: Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? selectedColor : theme.colorScheme.onSurface,
            ),
          ),
          trailing: isSelected
              ? Icon(AppIcons.check, size: 18, color: selectedColor)
              : null,
          onTap: () {
            close();
            onMemberSelected(member.id);
          },
        );
      },
    );
  }

  Color _selectedColor(ThemeData theme, Member member) {
    if (member.customColorEnabled && member.customColorHex != null) {
      return AppColors.fromHex(member.customColorHex!);
    }
    return theme.colorScheme.primary;
  }
}
