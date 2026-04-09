import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A dismissible strip showing a staged image thumbnail above the text field.
class AttachmentPreview extends ConsumerWidget {
  const AttachmentPreview({
    super.key,
    required this.imageBytes,
    required this.onRemove,
  });

  final Uint8List imageBytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            children: [
              // Thumbnail container
              TintedGlassSurface(
                borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
                width: 100,
                height: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.cover,
                    width: 100,
                    height: 100,
                  ),
                ),
              ),

              // Remove button
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? AppColors.warmBlack.withValues(alpha: 0.7)
                          : AppColors.warmWhite.withValues(alpha: 0.85),
                      border: Border.all(
                        color: isDark
                            ? AppColors.warmWhite.withValues(alpha: 0.15)
                            : AppColors.warmBlack.withValues(alpha: 0.08),
                        width: PrismTokens.hairlineBorderWidth,
                      ),
                    ),
                    child: Icon(
                      AppIcons.close,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
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
