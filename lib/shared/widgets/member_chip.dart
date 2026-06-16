import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

enum MemberChipStyle { filled, inline }

class MemberChip extends StatelessWidget {
  const MemberChip({
    super.key,
    required this.member,
    this.selected = true,
    this.onTap,
    this.style = MemberChipStyle.filled,
    this.avatarSize = 20,
    this.deferAvatarLookup = true,
    this.labelMaxLines = 2,
  });

  final Member member;
  final bool selected;
  final VoidCallback? onTap;
  final MemberChipStyle style;
  final double avatarSize;
  final bool deferAvatarLookup;
  final int labelMaxLines;

  @override
  Widget build(BuildContext context) {
    final scaledAvatarSize = MediaQuery.textScalerOf(context).scale(avatarSize);
    return PrismChip(
      label: member.name,
      selected: selected,
      onTap: onTap,
      avatar: MemberAvatar(
        memberId: member.id,
        memberName: member.name,
        emoji: member.emoji,
        avatarImageData: member.avatarImageData,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: scaledAvatarSize,
        deferAvatarLookup: deferAvatarLookup,
      ),
      selectedColor: memberChipSelectedColor(member),
      labelMaxLines: labelMaxLines,
      variant: style == MemberChipStyle.inline
          ? PrismChipVariant.inline
          : PrismChipVariant.filled,
    );
  }
}

Color? memberChipSelectedColor(Member member) {
  return member.customColorEnabled && member.customColorHex != null
      ? AppColors.fromHex(member.customColorHex!)
      : null;
}
