import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

/// Full-screen image viewer shown when tapping an image in chat.
///
/// Features:
/// - Dark/black background
/// - Pinch to zoom via [InteractiveViewer]
/// - Swipe down to dismiss
/// - Save button in app bar
/// - Smooth fade transition
class ImageViewer extends ConsumerStatefulWidget {
  const ImageViewer({super.key, required this.imageBytes, this.caption});

  /// The decrypted image data to display.
  final Uint8List imageBytes;

  /// Optional caption text shown at the bottom of the viewer.
  final String? caption;

  /// Navigate to the full-screen image viewer.
  static void show(
    BuildContext context, {
    required Uint8List imageBytes,
    String? caption,
  }) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageViewer(imageBytes: imageBytes, caption: caption),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  ConsumerState<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<ImageViewer> {
  double _dragOffset = 0.0;
  bool _isDragging = false;
  bool _isSaving = false;

  Future<void> _saveImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final extension = _imageFileExtensionFor(widget.imageBytes);
      await ref
          .read(prismFileDialogServiceProvider)
          .saveBytes(
            bytes: widget.imageBytes,
            suggestedName: 'prism-image.$extension',
            allowedExtensions: [extension],
            mimeType: 'image/$extension',
          );
    } catch (_) {
      // Saving may fail on some platforms; silently ignore.
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 300 || _dragOffset.abs() > 150) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0.0;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final captionText = widget.caption;

    final opacity = _isDragging
        ? (1.0 - (_dragOffset.abs() / 400).clamp(0.0, 0.5))
        : 1.0;

    return Semantics(
      label: context.l10n.chatImageViewerSemantics(captionText ?? ''),
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: opacity),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Semantics(
            label: context.l10n.chatImageViewerClose,
            button: true,
            child: IconButton(
              icon: Icon(AppIcons.arrowBack, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          actions: [
            Semantics(
              label: context.l10n.save,
              button: true,
              child: IconButton(
                icon: _isSaving
                    ? const PrismSpinner(color: Colors.white, size: 20)
                    : Icon(AppIcons.download, color: Colors.white),
                onPressed: _isSaving ? null : _saveImage,
              ),
            ),
          ],
        ),
        body: GestureDetector(
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image with zoom and drag offset
              AnimatedContainer(
                duration: _isDragging
                    ? Duration.zero
                    : (disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 200)),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, _dragOffset, 0),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Center(
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.contain,
                      semanticLabel:
                          widget.caption ?? context.l10n.chatImageAttachment,
                    ),
                  ),
                ),
              ),

              // Caption overlay at the bottom
              if (captionText != null && captionText.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      captionText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _imageFileExtensionFor(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpeg';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return 'png';
}
