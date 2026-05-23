import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
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
    this.specialRows = const [],
    this.searchTitle,
    this.searchLabel,
    this.preferredDirection = BlurPopupDirection.down,
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
  final List<MemberSelectorPopupSpecialRow> specialRows;
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

    final visibleRows = <_MemberSelectorPopupRow>[
      _SearchPopupRow(),
      for (final row in specialRows) _SpecialPopupRow(row),
      for (final member in members) _MemberPopupRow(member),
    ];
    final logicalRows = preferredDirection == BlurPopupDirection.up
        ? visibleRows.reversed.toList(growable: false)
        : visibleRows;

    return BlurPopupAnchor(
      key: manualAnchorKey,
      trigger: isManual ? BlurPopupTrigger.manual : BlurPopupTrigger.tap,
      preferredDirection: preferredDirection,
      width: width,
      maxHeight: maxHeight,
      semanticLabel: semanticLabel,
      onBeforeShow: onBeforeShow,
      itemCount: logicalRows.length,
      itemBuilder: (popupContext, index, close) =>
          _buildRow(context, popupContext, logicalRows[index], close),
      child: isManual ? (anchorChild ?? child) : child,
    );
  }

  Widget _buildRow(
    BuildContext parentContext,
    BuildContext popupContext,
    _MemberSelectorPopupRow row,
    VoidCallback close,
  ) {
    return switch (row) {
      _SearchPopupRow() => _buildSearchRow(parentContext, popupContext, close),
      _SpecialPopupRow(row: final specialRow) => _buildSpecialRow(
        popupContext,
        specialRow,
        close,
      ),
      _MemberPopupRow(member: final member) => _buildMemberRow(
        popupContext,
        member,
        close,
      ),
    };
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
          groups: groups,
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

    return PrismListRow(
      key: ValueKey('member-selector-popup-${member.id}'),
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: MemberAvatar(
        avatarImageData: member.avatarImageData,
        memberName: member.name,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: avatarSize,
      ),
      selected: isSelected,
      title: Text(
        member.name,
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
  }

  Color _selectedColor(ThemeData theme, Member member) {
    if (member.customColorEnabled && member.customColorHex != null) {
      return AppColors.fromHex(member.customColorHex!);
    }
    return theme.colorScheme.primary;
  }
}

sealed class _MemberSelectorPopupRow {
  const _MemberSelectorPopupRow();
}

final class _SearchPopupRow extends _MemberSelectorPopupRow {}

final class _SpecialPopupRow extends _MemberSelectorPopupRow {
  const _SpecialPopupRow(this.row);

  final MemberSelectorPopupSpecialRow row;
}

final class _MemberPopupRow extends _MemberSelectorPopupRow {
  const _MemberPopupRow(this.member);

  final Member member;
}
