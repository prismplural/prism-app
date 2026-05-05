import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_image/crop_image.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class PrismImageCropRequest {
  const PrismImageCropRequest({
    required this.sourceBytes,
    required this.title,
    required this.doneButtonTitle,
    required this.cancelButtonTitle,
    required this.aspectRatio,
  });

  final Uint8List sourceBytes;
  final String title;
  final String doneButtonTitle;
  final String cancelButtonTitle;
  final double aspectRatio;
}

Future<ui.Image?> showPrismImageCropper(
  BuildContext context,
  PrismImageCropRequest request,
) {
  return Navigator.of(context, rootNavigator: true).push<ui.Image>(
    MaterialPageRoute<ui.Image>(
      fullscreenDialog: true,
      builder: (_) => _PrismImageCropScreen(request: request),
    ),
  );
}

class _PrismImageCropScreen extends StatefulWidget {
  const _PrismImageCropScreen({required this.request});

  final PrismImageCropRequest request;

  @override
  State<_PrismImageCropScreen> createState() => _PrismImageCropScreenState();
}

class _PrismImageCropScreenState extends State<_PrismImageCropScreen> {
  late final CropController _controller = CropController(
    aspectRatio: widget.request.aspectRatio,
    defaultCrop: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
  );
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final bitmap = await _controller.croppedBitmap();
      if (!mounted) {
        bitmap.dispose();
        return;
      }
      Navigator.of(context).pop(bitmap);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      PrismToast.error(
        context,
        message: context.l10n.imageCropProcessingError,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final borderRadius = BorderRadius.circular(PrismShapes.of(context).radius(28));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: widget.request.cancelButtonTitle,
          icon: Icon(AppIcons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.request.title),
        actions: [
          IconButton(
            tooltip: widget.request.doneButtonTitle,
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? PrismSpinner(
                    size: 18,
                    color: colors.primary,
                  )
                : Icon(AppIcons.check),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: borderRadius,
                  ),
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: CropImage(
                      controller: _controller,
                      image: Image.memory(widget.request.sourceBytes),
                      paddingSize: 24,
                      minimumImageSize: 72,
                      gridColor: colors.onSurface.withValues(alpha: 0.88),
                      gridInnerColor: colors.onSurface.withValues(alpha: 0.52),
                      gridCornerColor: colors.primary,
                      scrimColor: colors.scrim.withValues(alpha: 0.7),
                      gridCornerSize: 28,
                      gridThinWidth: 1.5,
                      gridThickWidth: 3.5,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  PrismButton(
                    icon: AppIcons.restartAlt,
                    label: context.l10n.imageCropRotateLeft,
                    density: PrismControlDensity.compact,
                    tone: PrismButtonTone.outlined,
                    onPressed: _controller.rotateLeft,
                  ),
                  PrismButton(
                    icon: AppIcons.refresh,
                    label: context.l10n.imageCropRotateRight,
                    density: PrismControlDensity.compact,
                    tone: PrismButtonTone.outlined,
                    onPressed: _controller.rotateRight,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
