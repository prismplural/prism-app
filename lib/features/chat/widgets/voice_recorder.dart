import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/chat/providers/voice_recording_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Replaces the text field area during active voice recording.
///
/// Auto-starts recording on mount. Shows a cancel button, live waveform with
/// elapsed time, and a send button. The send button requires at least 1 second
/// of recording before it becomes active.
class VoiceRecorder extends ConsumerStatefulWidget {
  const VoiceRecorder({
    super.key,
    required this.onSend,
    required this.onCancel,
  });

  /// Called when the user sends the recording. Provides the encoded audio
  /// bytes, duration in milliseconds, and a base64-encoded waveform summary.
  final void Function(Uint8List audioBytes, int durationMs, String waveformB64) onSend;

  /// Called when the user cancels the recording.
  final VoidCallback onCancel;

  @override
  ConsumerState<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends ConsumerState<VoiceRecorder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(voiceRecordingProvider.notifier).startRecording();
    });
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _handleSend() async {
    final state = await ref.read(voiceRecordingProvider.notifier).stopRecording();
    if (state.status == VoiceRecordingStatus.done && state.audioBytes != null) {
      widget.onSend(state.audioBytes!, state.durationMs, state.waveformB64);
    }
  }

  Future<void> _handleCancel() async {
    await ref.read(voiceRecordingProvider.notifier).cancelRecording();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceRecordingProvider);
    final theme = Theme.of(context);
    final isProcessing = state.status == VoiceRecordingStatus.processing;
    final canSend = state.elapsedMs >= 1000 && !isProcessing;

    return TintedGlassSurface(
      borderRadius: BorderRadius.circular(19),
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            // Cancel button
            _CancelButton(
              enabled: !isProcessing,
              onPressed: _handleCancel,
            ),
            const SizedBox(width: 4),

            // Waveform + elapsed (center)
            Expanded(
              child: isProcessing
                  ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: CustomPaint(
                            painter: _WaveformPainter(
                              samples: state.amplitudeSamples,
                              color: theme.colorScheme.primary,
                            ),
                            size: const Size(double.infinity, 28),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(state.elapsedMs),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 4),

            // Send button
            _VoiceSendButton(
              canSend: canSend,
              isProcessing: isProcessing,
              onPressed: canSend ? _handleSend : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cancel button
// ---------------------------------------------------------------------------

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Cancel recording',
      button: true,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: TintedGlassSurface.circle(
              size: 34,
              child: Icon(
                AppIcons.close,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Send button — mirrors _SendButton from message_input.dart
// ---------------------------------------------------------------------------

class _VoiceSendButton extends StatefulWidget {
  const _VoiceSendButton({
    required this.canSend,
    required this.isProcessing,
    required this.onPressed,
  });

  final bool canSend;
  final bool isProcessing;
  final VoidCallback? onPressed;

  @override
  State<_VoiceSendButton> createState() => _VoiceSendButtonState();
}

class _VoiceSendButtonState extends State<_VoiceSendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Semantics(
      label: 'Send voice note',
      button: true,
      enabled: widget.canSend,
      child: GestureDetector(
        onTapDown: widget.canSend ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.canSend
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : (_) {
                HapticFeedback.heavyImpact();
              },
        onTapCancel: () => setState(() => _pressed = false),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.9 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                sizeCurve: Curves.easeInOut,
                firstCurve: Curves.easeOut,
                secondCurve: Curves.easeOut,
                crossFadeState: widget.canSend
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                layoutBuilder: (top, topKey, bottom, bottomKey) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(key: bottomKey, child: bottom),
                      Positioned(key: topKey, child: top),
                    ],
                  );
                },
                // Idle / disabled: plain glass, no tint
                firstChild: TintedGlassSurface.circle(
                  size: 34,
                  child: Icon(
                    AppIcons.arrowUpwardRounded,
                    size: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
                // Ready: primary-tinted glass with accent icon
                secondChild: widget.isProcessing
                    ? TintedGlassSurface.circle(
                        size: 34,
                        tint: primary,
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primary,
                          ),
                        ),
                      )
                    : TintedGlassSurface.circle(
                        size: 34,
                        tint: primary,
                        child: Icon(
                          AppIcons.arrowUpwardRounded,
                          size: 20,
                          color: primary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Waveform painter
// ---------------------------------------------------------------------------

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    const barWidth = 3.0;
    const barGap = 2.0;
    final maxBars = (size.width / (barWidth + barGap)).floor();
    final visibleSamples = samples.length > maxBars
        ? samples.sublist(samples.length - maxBars)
        : samples;

    // Normalize to 0.0-1.0
    final minVal = visibleSamples.reduce((a, b) => a < b ? a : b);
    final maxVal = visibleSamples.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const minHeight = 4.0;
    final maxHeight = size.height * 0.85;

    for (var i = 0; i < visibleSamples.length; i++) {
      final normalized =
          range < 0.01 ? 0.5 : (visibleSamples[i] - minVal) / range;
      final barHeight = minHeight + normalized * (maxHeight - minHeight);
      final x = i * (barWidth + barGap);
      final y = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.samples != samples;
}
