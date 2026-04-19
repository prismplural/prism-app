import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Preview strip for attachments in the message compose area.
///
/// Shows a thumbnail of each attached image with a remove button.
class AttachmentPreview extends StatelessWidget {
  const AttachmentPreview({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  /// List of image byte data for each attachment.
  final List<Uint8List> attachments;

  /// Called with the index of the attachment to remove.
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return _AttachmentThumbnail(
            imageBytes: attachments[index],
            onRemove: () => onRemove(index),
          );
        },
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({
    required this.imageBytes,
    required this.onRemove,
  });

  final Uint8List imageBytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: context.l10n.chatAttachedImagePreview,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(10)),
            child: Image.memory(
              imageBytes,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              semanticLabel: context.l10n.chatAttachedImagePreview,
              errorBuilder: (_, _, _) => Container(
                width: 72,
                height: 72,
                color: theme.brightness == Brightness.dark
                    ? AppColors.charcoalSurface
                    : AppColors.parchmentElevated,
                child: Icon(
                  AppIcons.imageOutlined,
                  size: 24,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          // Remove button — 44px touch target for accessibility
          Positioned(
            top: -8,
            right: -8,
            child: Semantics(
              label: context.l10n.chatRemoveAttachment,
              button: true,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: GestureDetector(
                    onTap: onRemove,
                    child: TintedGlassSurface.circle(
                      size: 24,
                      child: Icon(
                        AppIcons.close,
                        size: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
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
