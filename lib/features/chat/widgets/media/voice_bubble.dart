import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Displays a voice note attachment as a styled horizontal bar.
///
/// Shows a play icon, waveform placeholder, and duration text. Actual
/// playback will be wired up in Batch 8.
class VoiceBubble extends StatelessWidget {
  const VoiceBubble({
    super.key,
    required this.attachment,
    this.accentColor,
  });

  final MediaAttachment attachment;
  final Color? accentColor;

  static const _borderRadius = 12.0;
  static const _minTouchTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = _formatDuration(attachment.durationMs);

    return Semantics(
      label: 'Voice note, $duration',
      child: TintedGlassSurface(
        tint: accentColor,
        borderRadius: BorderRadius.circular(_borderRadius),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _minTouchTarget,
            maxWidth: 240,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play button placeholder.
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (accentColor ?? theme.colorScheme.primary)
                      .withValues(alpha: 0.15),
                ),
                child: Icon(
                  AppIcons.playArrowRounded,
                  size: 20,
                  color: accentColor ?? theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              // Waveform placeholder bars.
              Expanded(child: _buildWaveformPlaceholder(theme)),
              const SizedBox(width: 10),
              // Duration text.
              Text(
                duration,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a series of small bars as a waveform placeholder.
  Widget _buildWaveformPlaceholder(ThemeData theme) {
    final barColor =
        (accentColor ?? theme.colorScheme.primary).withValues(alpha: 0.25);
    // Fixed pattern of bar heights to suggest a waveform.
    const heights = [0.3, 0.5, 0.8, 0.6, 1.0, 0.7, 0.4, 0.6, 0.9, 0.5, 0.3, 0.7];

    return SizedBox(
      height: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final h in heights)
            Container(
              width: 3,
              height: 24 * h,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }

  /// Format milliseconds as "M:SS".
  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '0:00';
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
