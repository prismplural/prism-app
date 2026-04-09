import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Provider that fetches image bytes for a media attachment.
///
/// TODO(batch-5): Wire up to `downloadManagerProvider.getMedia(...)` once the
/// media download infrastructure is available. For now returns null (shows
/// placeholder).
final _imageDataProvider =
    FutureProvider.autoDispose.family<Uint8List?, MediaAttachment>(
  (ref, attachment) async {
    // Stub: real implementation will use DownloadManager to fetch encrypted
    // media from the relay and decrypt it locally.
    return null;
  },
);

/// Displays an image attachment with progressive loading.
///
/// Shows a BlurHash/aspect-ratio placeholder while the image downloads,
/// then crossfades to the actual image. Tapping calls [onTap] (for the
/// full-screen viewer in Batch 8).
class ImageBubble extends ConsumerWidget {
  const ImageBubble({
    super.key,
    required this.attachment,
    this.onTap,
    this.accentColor,
  });

  final MediaAttachment attachment;
  final VoidCallback? onTap;
  final Color? accentColor;

  static const _maxHeight = 300.0;
  static const _borderRadius = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.70;

    // Compute aspect-ratio-constrained size.
    final aspectWidth = attachment.width?.toDouble() ?? maxWidth;
    final aspectHeight = attachment.height?.toDouble() ?? _maxHeight;
    final aspectRatio = aspectWidth / aspectHeight;
    final constrainedWidth = maxWidth.clamp(0.0, maxWidth);
    final constrainedHeight =
        (constrainedWidth / aspectRatio).clamp(0.0, _maxHeight);

    final mediaAsync = ref.watch(_imageDataProvider(attachment));

    return Semantics(
      label: 'Image attachment',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_borderRadius),
          child: SizedBox(
            width: constrainedWidth,
            height: constrainedHeight,
            child: mediaAsync.when(
              data: (bytes) {
                if (bytes != null) {
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    width: constrainedWidth,
                    height: constrainedHeight,
                  );
                }
                return _buildPlaceholder(
                  context,
                  constrainedWidth,
                  constrainedHeight,
                );
              },
              loading: () => _buildPlaceholder(
                context,
                constrainedWidth,
                constrainedHeight,
              ),
              error: (_, _) => _buildErrorPlaceholder(
                context,
                constrainedWidth,
                constrainedHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Placeholder shown while the image loads. Uses the accent color or a
  /// neutral grey to hint at the content area. When BlurHash decoding is
  /// wired up, this will show the decoded preview instead.
  Widget _buildPlaceholder(
    BuildContext context,
    double width,
    double height,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? AppColors.charcoalElevated
        : AppColors.parchmentElevated;
    final tintedColor = accentColor != null
        ? Color.alphaBlend(accentColor!.withValues(alpha: 0.12), baseColor)
        : baseColor;

    return Container(
      width: width,
      height: height,
      color: tintedColor,
      child: Center(
        child: Icon(
          AppIcons.imageOutlined,
          size: 32,
          color: (accentColor ?? AppColors.warmBlack).withValues(alpha: 0.3),
        ),
      ),
    );
  }

  /// Placeholder shown when the image fails to load.
  Widget _buildErrorPlaceholder(
    BuildContext context,
    double width,
    double height,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark
        ? AppColors.charcoalElevated
        : AppColors.parchmentElevated;

    return Container(
      width: width,
      height: height,
      color: baseColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.errorOutline,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Failed to load',
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
