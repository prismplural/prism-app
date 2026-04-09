import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blurhash_dart/blurhash_dart.dart';
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
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.70;
    const maxHeight = 300.0;

    // Compute constrained size from source dimensions
    double effectiveWidth = width ?? 240.0;
    double effectiveHeight = height ?? 180.0;

    // Scale down to fit max width
    if (effectiveWidth > maxWidth) {
      final scale = maxWidth / effectiveWidth;
      effectiveWidth = maxWidth;
      effectiveHeight = effectiveHeight * scale;
    }
    // Scale down to fit max height
    if (effectiveHeight > maxHeight) {
      final scale = maxHeight / effectiveHeight;
      effectiveHeight = maxHeight;
      effectiveWidth = effectiveWidth * scale;
    }

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

    // Loading state — show BlurHash placeholder if available, else spinner
    if (blurhash != null && blurhash!.isNotEmpty) {
      return ExcludeSemantics(
        child: _BlurhashPlaceholder(
          blurhash: blurhash!,
          width: w,
          height: h,
        ),
      );
    }

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

class _BlurhashPlaceholder extends StatefulWidget {
  const _BlurhashPlaceholder({
    required this.blurhash,
    required this.width,
    required this.height,
  });

  final String blurhash;
  final double width;
  final double height;

  @override
  State<_BlurhashPlaceholder> createState() => _BlurhashPlaceholderState();
}

class _BlurhashPlaceholderState extends State<_BlurhashPlaceholder> {
  ui.Image? _decoded;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_BlurhashPlaceholder old) {
    super.didUpdateWidget(old);
    if (old.blurhash != widget.blurhash) _decode();
  }

  Future<void> _decode() async {
    const pixelW = 32;
    const pixelH = 32;
    try {
      final blurHash = BlurHash.decode(widget.blurhash);
      final rgbaBytes = blurHash.toImage(pixelW, pixelH).getBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgbaBytes,
        pixelW,
        pixelH,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (mounted) setState(() => _decoded = image);
    } catch (_) {
      // BlurHash decode failure — leave blank
    }
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_decoded != null) {
      return RawImage(
        image: _decoded,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
      );
    }
    return SizedBox(width: widget.width, height: widget.height);
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
