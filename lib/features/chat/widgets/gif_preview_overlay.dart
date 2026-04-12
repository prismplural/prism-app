import 'package:flutter/material.dart';

import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// A confirm-before-send overlay shown when tapping a GIF in the picker.
///
/// Displays the GIF at full size with a "Send" button below. Tapping outside
/// or pressing back dismisses the overlay (returns null).
class GifPreviewOverlay extends StatelessWidget {
  const GifPreviewOverlay({super.key, required this.gif});

  final KlipyGif gif;

  /// Show the preview overlay and return the [KlipyGif] if the user confirms,
  /// or null if dismissed.
  static Future<KlipyGif?> show(BuildContext context, KlipyGif gif) {
    return showDialog<KlipyGif>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GifPreviewOverlay(gif: gif),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.8;

    // Compute display dimensions preserving aspect ratio.
    double displayWidth = maxWidth;
    double displayHeight = maxWidth;
    if (gif.width > 0 && gif.height > 0) {
      final aspectRatio = gif.width / gif.height;
      displayWidth = maxWidth;
      displayHeight = maxWidth / aspectRatio;
    }

    return Semantics(
      label: context.l10n.chatGifPreviewSemantics(gif.contentDescription),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: Image.network(
                  gif.previewUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: Icon(AppIcons.imageBroken, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrismButton(
              label: context.l10n.chatGifSendButton,
              tone: PrismButtonTone.filled,
              onPressed: () => Navigator.of(context).pop(gif),
            ),
          ],
        ),
      ),
    );
  }
}
