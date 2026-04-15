import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

/// Full-screen image viewer shown when tapping an image in chat.
///
/// Features:
/// - Dark/black background
/// - Pinch to zoom via [InteractiveViewer]
/// - Swipe down to dismiss
/// - Share button in app bar
/// - Smooth fade transition
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.imageBytes,
    this.caption,
  });

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
        pageBuilder: (context, animation, secondaryAnimation) => ImageViewer(
          imageBytes: imageBytes,
          caption: caption,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  double _dragOffset = 0.0;
  bool _isDragging = false;
  bool _isSharing = false;

  Future<void> _shareImage() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/shared_image.png');
      await file.writeAsBytes(widget.imageBytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)]),
      );
    } catch (_) {
      // Sharing may fail on some platforms; silently ignore.
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
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
              label: context.l10n.chatImageViewerShare,
              button: true,
              child: IconButton(
                icon: _isSharing
                    ? const PrismSpinner(
                        color: Colors.white,
                        size: 20,
                      )
                    : Icon(AppIcons.share, color: Colors.white),
                onPressed: _isSharing ? null : _shareImage,
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
                transform:
                    Matrix4.translationValues(0, _dragOffset, 0),
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
                    padding: const EdgeInsets.fromLTRB(
                        16, 12, 16, 32),
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
