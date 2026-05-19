import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

/// Avatar widget for member groups — mirrors [MemberAvatar]'s composition
/// (tinted glass surface + accent ring + inset image) with an optional
/// emoji badge in the bottom-right when [showEmojiOnAvatar] is set.
class GroupAvatar extends ConsumerWidget {
  const GroupAvatar({
    super.key,
    required this.group,
    required this.size,
    this.showEmojiOnAvatar = true,
    this.showBorder = false,
    this.tintOverride,
  });

  final MemberGroup group;
  final double size;

  /// When true and the group has both an avatar image and an emoji, renders
  /// the emoji as a small badge in the bottom-right corner of the avatar.
  final bool showEmojiOnAvatar;

  final bool showBorder;

  /// When set, overrides the derived group color for the glass tint.
  /// Takes precedence over [MemberGroup.colorHex].
  final Color? tintOverride;

  bool get _hasAvatar =>
      group.avatarImageData != null && group.avatarImageData!.isNotEmpty;
  bool get _hasEmoji => group.emoji != null && group.emoji!.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = MemberAvatar(
      avatarImageData: group.avatarImageData,
      memberName: group.name,
      emoji: group.emoji ?? '❔',
      customColorEnabled:
          group.colorHex != null && group.colorHex!.isNotEmpty,
      customColorHex: group.colorHex,
      tintOverride: tintOverride,
      size: size,
      showBorder: showBorder,
    );

    if (_hasAvatar && _hasEmoji && showEmojiOnAvatar) {
      final badgeSize = (size * 0.25).clamp(16.0, 32.0);
      final theme = Theme.of(context);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            bottom: 0,
            right: 0,
            child: _EmojiSmallBadge(
              emoji: group.emoji!,
              badgeSize: badgeSize,
              surfaceColor: theme.colorScheme.surface,
            ),
          ),
        ],
      );
    }

    return avatar;
  }
}

class _EmojiSmallBadge extends StatelessWidget {
  const _EmojiSmallBadge({
    required this.emoji,
    required this.badgeSize,
    required this.surfaceColor,
  });

  final String emoji;
  final double badgeSize;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: surfaceColor,
        border: Border.all(color: surfaceColor, width: 2),
      ),
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(fontSize: badgeSize * 0.55),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
