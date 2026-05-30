import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// An overflow-menu action shown as a dropdown in the [ImageViewer] top bar
/// (e.g. "Jump to message", "Delete"). [onSelected] runs after the viewer has
/// dismissed itself, so callbacks should act on the caller's context.
class ImageViewerAction {
  const ImageViewerAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Full-screen image viewer shown when tapping an image in chat.
///
/// Features:
/// - Dark/black background
/// - Pinch to zoom via [InteractiveViewer]
/// - Swipe down to dismiss
/// - Prism glass top bar: back, save, and an optional overflow menu
/// - Smooth fade transition
class ImageViewer extends ConsumerStatefulWidget {
  const ImageViewer({
    super.key,
    required this.imageBytes,
    this.caption,
    this.actions = const [],
  });

  /// The decrypted image data to display.
  final Uint8List imageBytes;

  /// Optional caption text shown at the bottom of the viewer.
  final String? caption;

  /// Optional overflow-menu actions shown as a dropdown in the top bar. When
  /// empty, no menu button is shown. Selecting one dismisses the viewer first,
  /// then invokes the action.
  final List<ImageViewerAction> actions;

  /// Navigate to the full-screen image viewer.
  static void show(
    BuildContext context, {
    required Uint8List imageBytes,
    String? caption,
    List<ImageViewerAction> actions = const [],
  }) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageViewer(
              imageBytes: imageBytes,
              caption: caption,
              actions: actions,
            ),
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
  final GlobalKey<BlurPopupAnchorState> _menuKey = GlobalKey();
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
        body: Stack(
          children: [
            // Image + caption, with swipe-to-dismiss. The top bar is layered
            // separately (outside this detector) so dragging the buttons
            // doesn't dismiss the viewer.
            GestureDetector(
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

            // Prism glass top bar: back, save, optional overflow menu.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PrismTokens.pageHorizontalPadding,
          vertical: 8,
        ),
        child: Row(
          children: [
            PrismGlassIconButton(
              icon: AppIcons.arrowBack,
              onPressed: () => Navigator.of(context).pop(),
              semanticLabel: context.l10n.chatImageViewerClose,
              size: PrismTokens.topBarActionSize,
            ),
            const Spacer(),
            PrismGlassIconButton(
              icon: AppIcons.download,
              onPressed: _isSaving ? null : _saveImage,
              isLoading: _isSaving,
              semanticLabel: context.l10n.save,
              size: PrismTokens.topBarActionSize,
            ),
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(width: 8),
              _buildOverflowMenu(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOverflowMenu(BuildContext context) {
    final theme = Theme.of(context);
    return BlurPopupAnchor(
      key: _menuKey,
      trigger: BlurPopupTrigger.manual,
      width: 210,
      itemCount: widget.actions.length,
      itemBuilder: (context, index, close) {
        final action = widget.actions[index];
        final iconColor = action.destructive
            ? theme.colorScheme.error
            : theme.colorScheme.onSurface;
        return PrismListRow(
          dense: true,
          destructive: action.destructive,
          leading: Icon(action.icon, size: 20, color: iconColor),
          title: Text(action.label),
          onTap: () {
            close();
            _runAction(action);
          },
        );
      },
      child: PrismGlassIconButton(
        icon: AppIcons.moreVert,
        onPressed: () => _menuKey.currentState?.show(),
        semanticLabel: context.l10n.moreOptions,
        size: PrismTokens.topBarActionSize,
      ),
    );
  }

  void _runAction(ImageViewerAction action) {
    // Dismiss the viewer first so the action lands on the surface beneath it
    // (e.g. jump-to-message navigates the conversation; delete returns to the
    // media list), then run the caller-supplied callback.
    Navigator.of(context).pop();
    action.onSelected();
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
