import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
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

class _VoiceBubbleState extends State<VoiceBubble>
    with SingleTickerProviderStateMixin {
  List<double>? _samples;
  String _cachedB64 = '';

  // Smooth playback highlight: interpolate between position poll ticks.
  late final Ticker _ticker;
  double _displayProgress = 0.0;
  double _lastKnownProgress = 0.0;
  Duration _lastKnownTick = Duration.zero;
  Duration _currentTick = Duration.zero;

  // Key for precise seek hit-testing on the waveform canvas.
  final _waveformKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _displayProgress = widget.progress;
    _lastKnownProgress = widget.progress;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VoiceBubble old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) {
      _lastKnownProgress = widget.progress;
      _lastKnownTick = _currentTick;
    }
  }

  void _onTick(Duration elapsed) {
    _currentTick = elapsed;

    if (!widget.isPlaying) {
      if (_displayProgress != widget.progress) {
        setState(() => _displayProgress = widget.progress);
      }
      return;
    }

    // Linearly extrapolate forward from the last real position update.
    final sinceUpdate = elapsed - _lastKnownTick;
    final durationMs = widget.durationMs > 0 ? widget.durationMs : 1;
    final extrapolated = (_lastKnownProgress +
            sinceUpdate.inMilliseconds / durationMs * widget.speed)
        .clamp(0.0, 1.0);

    if ((extrapolated - _displayProgress).abs() > 0.0005) {
      setState(() => _displayProgress = extrapolated);
    }
  }

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
    final samples = _getSamples();
    final hasWaveform = samples != null && samples.isNotEmpty;
    final speedStr = widget.speed == widget.speed.roundToDouble()
        ? widget.speed.toInt().toString()
        : widget.speed.toString();
    final showSpeedChip = widget.isPlaying || widget.onSpeedTap != null;

    return Semantics(
      label: context.l10n.chatVoiceNoteSemantics(durationText),
      child: TintedGlassSurface(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
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

            // Waveform or fallback progress bar, centered vertically.
            // No text below — duration lives in the right slot so the waveform
            // is visually centered in the row.
            Expanded(
              child: GestureDetector(
                onTapDown: (details) {
                  if (widget.onSeek == null) return;
                  final box = _waveformKey.currentContext
                      ?.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final w = box.size.width;
                  if (w <= 0) return;
                  widget.onSeek!(
                    details.localPosition.dx.clamp(0.0, w) / w,
                  );
                },
                child: hasWaveform
                    ? SizedBox(
                        key: _waveformKey,
                        height: 28,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _PlaybackWaveformPainter(
                            samples: samples,
                            progress: _displayProgress,
                            playedColor: theme.colorScheme.primary,
                            unplayedColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.15),
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(2),
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
                                  width: barWidth * _displayProgress,
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
            ),

            // Fixed-width right slot: speed chip (when playing) stacked above
            // duration text. Fixed width prevents the waveform from resizing
            // as the speed label cycles. Speed chip is text-scaling-exempt so
            // its size stays stable across accessibility text-size settings.
            SizedBox(
              width: 64,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showSpeedChip) ...[
                    MediaQuery.withNoTextScaling(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        child: Semantics(
                          button: true,
                          label: context.l10n.chatVoiceNoteSpeed(speedStr),
                          child: GestureDetector(
                            onTap: widget.onSpeedTap,
                            behavior: HitTestBehavior.opaque,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: widget.onSpeedTap != null
                                        ? 0.10
                                        : 0.05,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${speedStr}x',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface
                                        .withValues(
                                      alpha: widget.onSpeedTap != null
                                          ? 0.70
                                          : 0.38,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    durationText,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.end,
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

    // Always resample to exactly maxBars — linear interpolation for upsampling
    // ensures short notes fill the full player width instead of clustering left.
    final resampled = List.generate(maxBars, (i) {
      if (samples.length == 1) return samples[0];
      final t = i / (maxBars - 1) * (samples.length - 1);
      final lo = t.floor().clamp(0, samples.length - 1);
      final hi = (lo + 1).clamp(0, samples.length - 1);
      final frac = t - lo.toDouble();
      return samples[lo] * (1.0 - frac) + samples[hi] * frac;
    });

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
