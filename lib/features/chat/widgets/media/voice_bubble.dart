import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Displays a voice note attachment inside a chat message bubble.
///
/// Shows a play/pause button and a waveform-style progress indicator.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({
    super.key,
    required this.durationMs,
    this.isPlaying = false,
    this.progress = 0.0,
    this.speed = 1.0,
    this.isLoading = false,
    this.onPlayPause,
    this.onSeek,
    this.onSpeedTap,
  });

  /// Duration of the voice note in milliseconds.
  final int durationMs;

  /// Whether the voice note is currently playing.
  final bool isPlaying;

  /// Playback progress from 0.0 to 1.0.
  final double progress;

  /// Current playback speed (1.0, 1.5, or 2.0).
  final double speed;

  /// Whether the audio file is loading (downloading/decrypting).
  final bool isLoading;

  /// Called when the play/pause button is tapped.
  final VoidCallback? onPlayPause;

  /// Called when the user seeks to a position (0.0 to 1.0).
  final ValueChanged<double>? onSeek;

  /// Called when the speed chip is tapped to cycle speed.
  final VoidCallback? onSpeedTap;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationText = _formatDuration(widget.durationMs);
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Semantics(
      label: 'Voice note from message, $durationText',
      child: TintedGlassSurface(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play/pause button — minimum 44px touch target
            Semantics(
              label: widget.isLoading
                  ? 'Loading voice note, $durationText'
                  : widget.isPlaying
                      ? 'Pause voice note, $durationText'
                      : 'Play voice note, $durationText',
              button: true,
              child: SizedBox(
                width: 44,
                height: 44,
                child: widget.isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          widget.isPlaying
                              ? AppIcons.stopRounded
                              : AppIcons.playArrowRounded,
                          size: 22,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: widget.onPlayPause,
                        padding: EdgeInsets.zero,
                      ),
              ),
            ),
            const SizedBox(width: 4),

            // Progress bar
            Expanded(
              child: GestureDetector(
                onTapDown: (details) {
                  if (widget.onSeek != null) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final localX = details.localPosition.dx;
                      // Account for button width + padding
                      final barWidth = box.size.width - 80;
                      if (barWidth > 0) {
                        widget.onSeek!((localX / barWidth).clamp(0.0, 1.0));
                      }
                    }
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: AnimatedContainer(
                        duration: disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 100),
                        height: 4,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final barWidth = constraints.maxWidth;
                            return Stack(
                              children: [
                                Container(
                                  width: barWidth,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                Container(
                                  width: barWidth * widget.progress,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Speed indicator chip
            if (widget.isPlaying || widget.onSpeedTap != null)
              Semantics(
                label:
                    'Playback speed ${widget.speed}x. Double tap to change.',
                button: true,
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: GestureDetector(
                      onTap: widget.onSpeedTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${widget.speed == widget.speed.roundToDouble() ? widget.speed.toInt().toString() : widget.speed.toString()}x',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
