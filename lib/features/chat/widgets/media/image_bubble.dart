import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:prism_plurality/features/chat/widgets/media/image_viewer.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Displays an image attachment inside a chat message bubble.
///
/// Shows a loading indicator while decrypting/downloading, a placeholder
/// on error, and opens [ImageViewer] on tap when the image is ready.
class ImageBubble extends StatelessWidget {
  const ImageBubble({
    super.key,
    this.imageBytes,
    this.isLoading = false,
    this.hasError = false,
    this.width,
    this.height,
    this.caption,
    this.blurhash,
  });

  /// Decrypted image bytes, null while loading.
  final Uint8List? imageBytes;

  /// Whether the image is currently being downloaded/decrypted.
  final bool isLoading;

  /// Whether the download/decrypt failed.
  final bool hasError;

  /// Display width constraint.
  final double? width;

  /// Display height constraint.
  final double? height;

  /// Optional caption for the image.
  final String? caption;

  /// Optional blurhash string for placeholder.
  final String? blurhash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveWidth = width ?? 240.0;
    final effectiveHeight = height ?? 180.0;

    return Semantics(
      label: imageBytes != null
          ? 'Image attachment. Double tap to view full screen.'
          : isLoading
              ? 'Image attachment loading.'
              : 'Image attachment failed to load.',
      child: GestureDetector(
        onTap: imageBytes != null
            ? () => ImageViewer.show(
                  context,
                  imageBytes: imageBytes!,
                  caption: caption,
                )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: effectiveWidth,
            height: effectiveHeight,
            child: _buildContent(context, theme, effectiveWidth, effectiveHeight),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    double w,
    double h,
  ) {
    if (imageBytes != null) {
      return Image.memory(
        imageBytes!,
        fit: BoxFit.cover,
        width: w,
        height: h,
        errorBuilder: (_, _, _) => _ErrorPlaceholder(width: w, height: h),
      );
    }

    if (hasError) {
      return _ErrorPlaceholder(width: w, height: h);
    }

    // Loading state — show placeholder with spinner
    return ExcludeSemantics(
      child: Container(
        width: w,
        height: h,
        color: theme.brightness == Brightness.dark
            ? AppColors.charcoalSurface
            : AppColors.parchmentElevated,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      color: theme.brightness == Brightness.dark
          ? AppColors.charcoalSurface
          : AppColors.parchmentElevated,
      child: Center(
        child: Icon(
          AppIcons.imageOutlined,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
