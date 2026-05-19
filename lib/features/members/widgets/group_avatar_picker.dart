import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
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
  final double badgeSize;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  @override
  State<GroupAvatarPicker> createState() => _GroupAvatarPickerState();
}

class _GroupAvatarPickerState extends State<GroupAvatarPicker> {
  bool _imageDecodeFailed = false;

  bool get _hasAvatar =>
      widget.avatarImageData != null && widget.avatarImageData!.isNotEmpty;
  bool get _hasEmoji => widget.emoji != null && widget.emoji!.isNotEmpty;

  @override
  void didUpdateWidget(GroupAvatarPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset failure flag when the image bytes change so a newly picked
    // image gets a fresh decode attempt.
    if (oldWidget.avatarImageData != widget.avatarImageData) {
      _imageDecodeFailed = false;
    }
  }

  Widget _buildTileContent(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTint = widget.accentColor ?? theme.colorScheme.primary;

    if (_hasAvatar) {
      Widget image = ClipOval(
        child: Image.memory(
          widget.avatarImageData!,
          fit: BoxFit.cover,
          width: widget.tileSize,
          height: widget.tileSize,
          cacheWidth:
              (widget.tileSize * MediaQuery.devicePixelRatioOf(context))
                  .round(),
          cacheHeight:
              (widget.tileSize * MediaQuery.devicePixelRatioOf(context))
                  .round(),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) {
            // Suppress the emoji badge on decode failure — otherwise the fallback emoji and the badge double up.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_imageDecodeFailed) {
                setState(() => _imageDecodeFailed = true);
              }
            });
            return _hasEmoji
                ? _buildEmojiFallback(context, effectiveTint)
                : _buildFolderFallback(context, effectiveTint);
          },
        ),
      );

      if (_hasEmoji && widget.showEmojiOnAvatar && !_imageDecodeFailed) {
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
      size: widget.tileSize,
      tint: tint,
      child: Center(
        child: Text(
          widget.emoji!,
          style: TextStyle(fontSize: widget.tileSize * 0.5),
        ),
      ),
    );
  }

  Widget _buildFolderFallback(BuildContext context, Color tint) {
    return TintedGlassSurface.circle(
      size: widget.tileSize,
      tint: tint,
      child: Center(
        child: Icon(AppIcons.folderOutlined, size: widget.tileSize * 0.4),
      ),
    );
  }

  Widget _buildEmojiSmallBadge(BuildContext context, ThemeData theme) {
    return Container(
      width: widget.badgeSize,
      height: widget.badgeSize,
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
          widget.emoji!,
          style: TextStyle(fontSize: widget.badgeSize * 0.55),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final tile = Semantics(
      button: true,
      image: _hasAvatar,
      label: l10n.memberGroupAvatarPickerSemantic,
      child: SizedBox(
        width: widget.tileSize,
        height: widget.tileSize,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPickImage,
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
            onTap: widget.onRemoveImage,
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
                    l10n.memberGroupRemovePhoto,
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
