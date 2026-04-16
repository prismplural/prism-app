import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/chat/providers/voice_recording_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
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
  final void Function(Uint8List audioBytes, int durationMs, String waveformB64)
  onSend;

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

  @override
  Widget build(BuildContext context) {
    ref.listen<VoiceRecordingState>(voiceRecordingProvider, (previous, next) {
      if (!mounted) {
        return;
      }

      final l10n = context.l10n;
      final textDirection = Directionality.of(context);
      if (previous?.status != next.status) {
        switch (next.status) {
          case VoiceRecordingStatus.recording:
            SemanticsService.sendAnnouncement(
              View.of(context),
              l10n.voiceRecordingStartedAnnouncement,
              textDirection,
            );
            break;
          case VoiceRecordingStatus.preparing:
            SemanticsService.sendAnnouncement(
              View.of(context),
              l10n.voicePreparingNote,
              textDirection,
            );
            break;
          case VoiceRecordingStatus.readyToSend:
            SemanticsService.sendAnnouncement(
              View.of(context),
              l10n.voiceRecordingReadyAnnouncement,
              textDirection,
            );
            break;
          case VoiceRecordingStatus.idle:
          case VoiceRecordingStatus.error:
          case VoiceRecordingStatus.unsupported:
            break;
        }
      }

      if ((next.status == VoiceRecordingStatus.error ||
              next.status == VoiceRecordingStatus.unsupported) &&
          mounted) {
        final msg = switch (next.errorType) {
          VoiceRecordingError.permissionDenied => l10n.voiceMicPermissionDenied,
          VoiceRecordingError.permissionBlocked =>
            l10n.voiceMicPermissionBlocked,
          VoiceRecordingError.tooShort =>
            next.errorMessage ?? l10n.voiceRecordingFailed,
          VoiceRecordingError.unsupported =>
            next.errorMessage ?? l10n.voiceRecordingFailed,
          _ => next.errorMessage ?? l10n.voiceRecordingFailed,
        };
        PrismToast.error(context, message: msg);
        ref.read(voiceRecordingProvider.notifier).reset();
        widget.onCancel();
      }
    });

    return _buildContent(context);
  }

  Future<void> _handleSend() async {
    final currentState = ref.read(voiceRecordingProvider);
    if (currentState.status != VoiceRecordingStatus.recording) {
      return;
    }

    final state = await ref
        .read(voiceRecordingProvider.notifier)
        .stopRecording();
    final artifact = state.artifact;
    if (state.status == VoiceRecordingStatus.readyToSend && artifact != null) {
      widget.onSend(artifact.bytes, artifact.durationMs, artifact.waveformB64);
    }
  }

  Future<void> _handleCancel() async {
    await ref.read(voiceRecordingProvider.notifier).cancelRecording();
    widget.onCancel();
  }

  Widget _buildContent(BuildContext context) {
    final state = ref.watch(voiceRecordingProvider);
    final theme = Theme.of(context);
    final isPreparing = state.status == VoiceRecordingStatus.preparing;
    final canSend =
        state.status == VoiceRecordingStatus.recording &&
        state.elapsedMs >= 1000;

    return TintedGlassSurface(
      borderRadius: BorderRadius.circular(19),
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            _CancelButton(enabled: !isPreparing, onPressed: _handleCancel),
            const SizedBox(width: 4),
            Expanded(
              child: isPreparing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PrismSpinner(
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            context.l10n.voicePreparingNote,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _AnimatedWaveform(
                            samples: state.amplitudeSamples,
                            color: theme.colorScheme.primary,
                            height: 28,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Duration(
                            milliseconds: state.elapsedMs,
                          ).toVoiceFormat(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 4),
            _VoiceSendButton(
              canSend: canSend,
              isPreparing: isPreparing,
              onPressed: canSend ? _handleSend : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.chatVoiceRecorderCancel,
      button: true,
      enabled: enabled,
      child: Tooltip(
        message: context.l10n.chatVoiceRecorderCancel,
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
      ),
    );
  }
}

class _VoiceSendButton extends StatefulWidget {
  const _VoiceSendButton({
    required this.canSend,
    required this.isPreparing,
    required this.onPressed,
  });

  final bool canSend;
  final bool isPreparing;
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
    final showActiveState = widget.canSend || widget.isPreparing;

    return Semantics(
      label: widget.isPreparing
          ? context.l10n.voicePreparingNote
          : context.l10n.chatVoiceRecorderSend,
      button: true,
      enabled: widget.canSend,
      child: Tooltip(
        message: widget.isPreparing
            ? context.l10n.voicePreparingNote
            : context.l10n.chatVoiceRecorderSend,
        child: GestureDetector(
          onTapDown: widget.canSend
              ? (_) => setState(() => _pressed = true)
              : (_) => HapticFeedback.heavyImpact(),
          onTapUp: widget.canSend
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                }
              : null,
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
                  crossFadeState: showActiveState
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
                  firstChild: TintedGlassSurface.circle(
                    size: 34,
                    child: Icon(
                      AppIcons.arrowUpwardRounded,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.35,
                      ),
                    ),
                  ),
                  secondChild: widget.isPreparing
                      ? TintedGlassSurface.circle(
                          size: 34,
                          tint: primary,
                          child: PrismSpinner(color: primary, size: 18),
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
      ),
    );
  }
}

class _AnimatedWaveform extends StatefulWidget {
  const _AnimatedWaveform({
    required this.samples,
    required this.color,
    required this.height,
  });

  final List<double> samples;
  final Color color;
  final double height;

  @override
  State<_AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<_AnimatedWaveform>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Animation progress [0..1] per sample index. Grows as new samples arrive.
  final List<double> _barProgress = [];

  /// Tracks elapsed time so we can advance animations per frame.
  Duration _lastTick = Duration.zero;

  static const _animDuration = 150.0; // ms per bar grow-in

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000.0; // ms
    _lastTick = elapsed;

    // Grow progress list to match sample count.
    while (_barProgress.length < widget.samples.length) {
      _barProgress.add(0.0);
    }

    // Advance all in-flight animations.
    var needsRepaint = false;
    for (var i = 0; i < _barProgress.length; i++) {
      if (_barProgress[i] < 1.0) {
        _barProgress[i] = (_barProgress[i] + dt / _animDuration).clamp(0.0, 1.0);
        needsRepaint = true;
      }
    }

    if (needsRepaint) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(
        samples: widget.samples,
        barProgress: _barProgress,
        color: widget.color,
      ),
      size: Size(double.infinity, widget.height),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.barProgress,
    required this.color,
  });

  final List<double> samples;
  final List<double> barProgress;
  final Color color;

  static const _barWidth = 3.0;
  static const _barGap = 2.0;
  static const _minHeight = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final maxBars = (size.width / (_barWidth + _barGap)).floor();
    // Include one extra bar on the left during scroll so it slides out
    // smoothly instead of disappearing abruptly.
    final extraLeft = samples.length > maxBars ? 1 : 0;
    final startIndex = samples.length > maxBars
        ? samples.length - maxBars - extraLeft
        : 0;
    final visibleCount = samples.length - startIndex;

    // Compute normalization over the visible window.
    var minVal = double.infinity;
    var maxVal = -double.infinity;
    for (var i = startIndex; i < samples.length; i++) {
      final v = samples[i];
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    final range = (maxVal - minVal).abs();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final maxHeight = size.height * 0.85;

    const barStep = _barWidth + _barGap;

    // Newest bar's animation progress drives the smooth slide.
    final newestProgress = (barProgress.length >= samples.length)
        ? Curves.easeOut.transform(barProgress[samples.length - 1])
        : 1.0;

    // Right-aligned: bars fill from the right edge and slide left.
    // baseSlot is the slot index of the first visible bar (bar i=0).
    // As the newest bar animates in (0→1), everything shifts left by one slot.
    final double baseSlot;
    if (samples.length > maxBars) {
      // Scrolling phase: slide the extra left bar off-screen.
      baseSlot = -newestProgress;
    } else {
      // Filling phase: right-align, newest bar enters at right edge.
      // At progress=0 the new bar is one slot past the right edge;
      // at progress=1 it settles into the rightmost visible slot.
      baseSlot = (maxBars - visibleCount).toDouble() +
          (1.0 - newestProgress);
    }

    for (var i = 0; i < visibleCount; i++) {
      final sampleIndex = startIndex + i;
      final sample = samples[sampleIndex];
      final normalized = range < 0.01
          ? 0.5
          : (sample - minVal) / range;
      final targetHeight = _minHeight + normalized * (maxHeight - _minHeight);

      // Per-bar grow-in animation.
      final progress = sampleIndex < barProgress.length
          ? Curves.easeOut.transform(barProgress[sampleIndex])
          : 1.0;
      final barHeight = _minHeight + (targetHeight - _minHeight) * progress;

      final x = (baseSlot + i) * barStep;

      final y = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true;
}
