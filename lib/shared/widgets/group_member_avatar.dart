import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Data for a single member in a group avatar.
class GroupAvatarMember {
  final Uint8List? avatarImageData;
  final String emoji;
  final bool customColorEnabled;
  final String? customColorHex;

  const GroupAvatarMember({
    this.avatarImageData,
    this.emoji = '❔',
    this.customColorEnabled = false,
    this.customColorHex,
  });
}

/// A circular avatar that composites multiple member emoji/images inside
/// a single glass circle. Supports 1–4 members visually.
///
/// - 1 member: delegates to [MemberAvatar]
/// - 2 members: side-by-side, each taking half the circle
/// - 3 members: top row of 2, bottom row of 1 centered
/// - 4 members: 2×2 grid
///
/// Any members beyond 4 are ignored visually (data model supports unlimited).
class GroupMemberAvatar extends StatelessWidget {
  const GroupMemberAvatar({
    super.key,
    required this.members,
    this.size = 40,
    this.tint,
  });

  final List<GroupAvatarMember> members;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return SizedBox.square(dimension: size);
    }

    if (members.length == 1) {
      final m = members.first;
      return MemberAvatar(
        avatarImageData: m.avatarImageData,
        emoji: m.emoji,
        customColorEnabled: m.customColorEnabled,
        customColorHex: m.customColorHex,
        size: size,
        tintOverride: tint,
      );
    }

    final visible = members.take(4).toList();
    final tintColor = tint ?? Theme.of(context).colorScheme.primary;

    return TintedGlassSurface.circle(
      size: size,
      tint: tintColor,
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: _buildLayout(visible, size),
        ),
      ),
    );
  }

  Widget _buildLayout(List<GroupAvatarMember> visible, double containerSize) {
    final itemSize = containerSize * 0.48;

    switch (visible.length) {
      case 2:
        // Diagonal overlap: first member top-left, second bottom-right
        final dualSize = containerSize * 0.6;
        final offset = containerSize * 0.18;
        return Stack(
          children: [
            Positioned(
              top: offset * 0.3,
              left: offset * 0.3,
              child: _miniAvatar(visible[0], dualSize),
            ),
            Positioned(
              bottom: offset * 0.3,
              right: offset * 0.3,
              child: _miniAvatar(visible[1], dualSize),
            ),
          ],
        );
      case 3:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniAvatar(visible[0], itemSize * 0.9),
                _miniAvatar(visible[1], itemSize * 0.9),
              ],
            ),
            _miniAvatar(visible[2], itemSize * 0.9),
          ],
        );
      case 4:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniAvatar(visible[0], itemSize * 0.85),
                _miniAvatar(visible[1], itemSize * 0.85),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniAvatar(visible[2], itemSize * 0.85),
                _miniAvatar(visible[3], itemSize * 0.85),
              ],
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _miniAvatar(GroupAvatarMember member, double itemSize) {
    if (member.avatarImageData != null && member.avatarImageData!.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          member.avatarImageData!,
          width: itemSize,
          height: itemSize,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _miniEmoji(member.emoji, itemSize),
        ),
      );
    }
    return _miniEmoji(member.emoji, itemSize);
  }

  Widget _miniEmoji(String emoji, double itemSize) {
    return SizedBox.square(
      dimension: itemSize,
      child: Center(
        child: MemberAvatar.centeredEmoji(
          emoji,
          fontSize: itemSize * 0.6,
        ),
      ),
    );
  }
}
