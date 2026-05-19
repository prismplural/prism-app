import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Tap-to-pick avatar tile for group editing.
///
/// Renders precedence: avatar image (non-empty) → emoji centered → folder fallback.
/// When avatar is set AND emoji is set AND [showEmojiOnAvatar] is true, the emoji
/// renders as a small bottom-right badge anchored to the avatar.
///
/// The host is responsible for showing a "Remove photo" affordance when there's
/// an avatar — pass [onRemoveImage] and we'll render a labeled InkWell row below
/// the tile when an avatar is present.
class GroupAvatarPicker extends StatelessWidget {
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
  final double badgeSize;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  bool get _hasAvatar =>
      avatarImageData != null && avatarImageData!.isNotEmpty;
  bool get _hasEmoji => emoji != null && emoji!.isNotEmpty;

  Widget _buildTileContent(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTint = accentColor ?? theme.colorScheme.primary;

    if (_hasAvatar) {
      Widget image = ClipOval(
        child: Image.memory(
          avatarImageData!,
          fit: BoxFit.cover,
          width: tileSize,
          height: tileSize,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) {
            // If image fails to decode, fall back to emoji or folder icon.
            if (_hasEmoji) {
              return _buildEmojiFallback(context, effectiveTint);
            }
            return _buildFolderFallback(context, effectiveTint);
          },
        ),
      );

      if (_hasEmoji && showEmojiOnAvatar) {
        image = Stack(
          clipBehavior: Clip.none,
          children: [
            image,
            Positioned(
              bottom: 0,
              right: 0,
              child: _buildEmojiSmallBadge(context, theme),
            ),
          ],
        );
      }

      return image;
    }

    if (_hasEmoji) {
      return _buildEmojiFallback(context, effectiveTint);
    }

    return _buildFolderFallback(context, effectiveTint);
  }

  Widget _buildEmojiFallback(BuildContext context, Color tint) {
    return TintedGlassSurface.circle(
      size: tileSize,
      tint: tint,
      child: Center(
        child: Text(
          emoji!,
          style: TextStyle(fontSize: tileSize * 0.5),
        ),
      ),
    );
  }

  Widget _buildFolderFallback(BuildContext context, Color tint) {
    return TintedGlassSurface.circle(
      size: tileSize,
      tint: tint,
      child: Center(
        child: Icon(AppIcons.folderOutlined, size: tileSize * 0.4),
      ),
    );
  }

  Widget _buildEmojiSmallBadge(BuildContext context, ThemeData theme) {
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surface,
        border: Border.all(
          color: theme.colorScheme.surface,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          emoji!,
          style: TextStyle(fontSize: badgeSize * 0.55),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tile = Semantics(
      button: true,
      image: _hasAvatar,
      label: 'Group photo. Tap to change.',
      child: SizedBox(
        width: tileSize,
        height: tileSize,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPickImage,
            customBorder: const CircleBorder(),
            child: _buildTileContent(context),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        tile,
        if (_hasAvatar) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: onRemoveImage,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.deleteOutline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    // TODO(task-13): replace with l10n.memberGroupRemovePhoto
                    'Remove photo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
