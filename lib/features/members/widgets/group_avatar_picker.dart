import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/group_avatar.dart';

/// Tap-to-pick avatar tile for group editing.
///
/// Renders a [GroupAvatar] preview with two corner badges:
///   - Camera badge (bottom-right) — always present when [onPickImage] is set;
///     tapping the whole tile fires [onPickImage].
///   - Remove badge (top-right, ×) — only when [avatarImageData] is set;
///     tapping that badge fires [onRemoveImage].
///
/// Mirrors the `_MemberAvatarPreview` pattern in member_profile_header.dart.
class GroupAvatarPicker extends StatefulWidget {
  const GroupAvatarPicker({
    super.key,
    required this.avatarImageData,
    required this.emoji,
    required this.showEmojiOnAvatar,
    required this.onPickImage,
    required this.onRemoveImage,
    this.accentColor,
    this.tileSize = 88,
    this.badgeSize = 22,
  });

  final Uint8List? avatarImageData;
  final String? emoji;
  final bool showEmojiOnAvatar;
  final Color? accentColor;
  final double tileSize;

  /// Size of the emoji-on-avatar badge rendered inside [GroupAvatar].
  final double badgeSize;

  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  @override
  State<GroupAvatarPicker> createState() => _GroupAvatarPickerState();
}

class _GroupAvatarPickerState extends State<GroupAvatarPicker> {
  bool get _hasAvatar =>
      widget.avatarImageData != null && widget.avatarImageData!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Synthetic group used solely for rendering — never persisted.
    final syntheticGroup = MemberGroup(
      id: 'preview',
      name: 'preview',
      emoji: widget.emoji,
      colorHex: null,
      avatarImageData: widget.avatarImageData,
      createdAt: DateTime.now(),
    );

    final cameraBadgeSize =
        (widget.tileSize * 0.28).clamp(24.0, 36.0);

    final avatarWidget = GestureDetector(
      onTap: widget.onPickImage,
      behavior: HitTestBehavior.opaque,
      child: GroupAvatar(
        group: syntheticGroup,
        size: widget.tileSize,
        showEmojiOnAvatar: widget.showEmojiOnAvatar,
        tintOverride: widget.accentColor,
      ),
    );

    return Semantics(
      button: true,
      image: _hasAvatar,
      label: l10n.memberGroupAvatarPickerSemantic,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarWidget,
          Positioned(
            right: -2,
            bottom: -2,
            child: IgnorePointer(
              child: Container(
                width: cameraBadgeSize,
                height: cameraBadgeSize,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  AppIcons.cameraAlt,
                  size: cameraBadgeSize * 0.55,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          if (_hasAvatar)
            Positioned(
              right: -4,
              top: -4,
              child: Material(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onRemoveImage,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      AppIcons.close,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
