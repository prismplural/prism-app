import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Displays a voice note attachment inside a chat message bubble.
///
/// Shows a play/pause button and a waveform progress indicator (falls back to a
/// linear fill bar when no waveform data is available).
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({
    super.key,
    required this.durationMs,
    this.waveformB64 = '',
    this.isPlaying = false,
    this.progress = 0.0,
    this.speed = 1.0,
    this.isLoading = false,
    this.hasError = false,
    this.onPlayPause,
    this.onRetry,
    this.onSeek,
    this.onSpeedTap,
  });

  /// Duration of the voice note in milliseconds.
  final int durationMs;

  /// Base64-encoded waveform samples (one byte per sample, 0–255).
  final String waveformB64;

  /// Whether the voice note is currently playing.
  final bool isPlaying;

  /// Playback progress from 0.0 to 1.0.
  final double progress;

  /// Current playback speed (1.0, 1.5, or 2.0).
  final double speed;

  /// Whether the audio file is loading (downloading/decrypting).
  final bool isLoading;

  /// Whether a download or playback error occurred.
  final bool hasError;

  /// Called when the play/pause button is tapped.
  final VoidCallback? onPlayPause;

  /// Called when the error icon is tapped to retry a failed download.
  /// If null and [hasError] is true, [onPlayPause] is used as fallback.
  final VoidCallback? onRetry;

  /// Called when the user seeks to a position (0.0 to 1.0).
  final ValueChanged<double>? onSeek;

  /// Called when the speed chip is tapped to cycle speed.
  final VoidCallback? onSpeedTap;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  List<double>? _samples;
  String _cachedB64 = '';

  List<double>? _getSamples() {
    if (widget.waveformB64 == _cachedB64) return _samples;
    _cachedB64 = widget.waveformB64;
    if (widget.waveformB64.isEmpty) {
      _samples = null;
      return null;
    }
    try {
      final bytes = base64.decode(widget.waveformB64);
      _samples = [for (final b in bytes) b / 255.0];
    } catch (_) {
      _samples = null;
    }
    return _samples;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationText = Duration(
      milliseconds: widget.durationMs,
    ).toVoiceFormat();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final samples = _getSamples();
    final hasWaveform = samples != null && samples.isNotEmpty;
    final speedStr = widget.speed == widget.speed.roundToDouble()
        ? widget.speed.toInt().toString()
        : widget.speed.toString();

    return Semantics(
      label: context.l10n.chatVoiceNoteSemantics(durationText),
      child: TintedGlassSurface(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play/pause button — minimum 44px touch target
            Semantics(
              label: widget.isLoading
                  ? context.l10n.chatVoiceNoteLoading(durationText)
                  : widget.hasError
                  ? context.l10n.chatVoiceNoteError
                  : widget.isPlaying
                  ? context.l10n.chatVoiceNotePause(durationText)
                  : context.l10n.chatVoiceNotePlay(durationText),
              button: true,
              child: SizedBox(
                width: 44,
                height: 44,
                child: widget.isLoading
                    ? Center(
                        child: PrismSpinner(
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                      )
                    : widget.hasError
                    ? IconButton(
                        tooltip: context.l10n.chatVoiceNoteError,
                        icon: Icon(
                          AppIcons.refresh,
                          size: 22,
                          color: theme.colorScheme.error,
                        ),
                        onPressed: widget.onRetry ?? widget.onPlayPause,
                        padding: EdgeInsets.zero,
                      )
                    : IconButton(
                        tooltip: widget.isPlaying
                            ? context.l10n.chatVoiceNotePause(durationText)
                            : context.l10n.chatVoiceNotePlay(durationText),
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

            // Waveform or progress bar
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
                    if (hasWaveform)
                      SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _PlaybackWaveformPainter(
                            samples: samples,
                            progress: widget.progress,
                            playedColor: theme.colorScheme.primary,
                            unplayedColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.15),
                          ),
                        ),
                      )
                    else
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
              PrismButton(
                label: '${speedStr}x',
                onPressed: widget.onSpeedTap ?? () {},
                enabled: widget.onSpeedTap != null,
                tone: PrismButtonTone.subtle,
                density: PrismControlDensity.compact,
                semanticLabel: context.l10n.chatVoiceNoteSpeed(speedStr),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _PlaybackWaveformPainter extends CustomPainter {
  const _PlaybackWaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  static const _barWidth = 3.0;
  static const _barGap = 2.0;
  static const _minHeight = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0) return;

    final maxBars = (size.width / (_barWidth + _barGap)).floor();
    if (maxBars == 0) return;

    // Downsample to fit available bar slots by averaging buckets.
    final List<double> resampled;
    if (samples.length <= maxBars) {
      resampled = samples;
    } else {
      resampled = List.generate(maxBars, (i) {
        final start = (i * samples.length / maxBars).floor();
        final end = ((i + 1) * samples.length / maxBars)
            .ceil()
            .clamp(start + 1, samples.length);
        var sum = 0.0;
        for (var j = start; j < end; j++) {
          sum += samples[j];
        }
        return sum / (end - start);
      });
    }

    final maxHeight = size.height * 0.85;
    final progressIndex = (progress * resampled.length).round();
    final playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = unplayedColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < resampled.length; i++) {
      final normalized = resampled[i].clamp(0.0, 1.0);
      final barHeight = _minHeight + normalized * (maxHeight - _minHeight);
      final x = i * (_barWidth + _barGap);
      final y = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        i < progressIndex ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PlaybackWaveformPainter old) =>
      old.progress != progress ||
      old.samples != samples ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}
