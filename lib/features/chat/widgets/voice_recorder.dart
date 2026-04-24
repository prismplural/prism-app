import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/chat/providers/voice_recording_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Pill-shaped waveform display that visually replaces the chat text field
/// while a voice note is being recorded. Same minHeight/borderRadius/fill as
/// the chat text field so the swap is seamless.
///
/// Auto-starts recording on mount. Cancel and send are rendered separately by
/// the parent as [VoiceRecorderCancelButton] and [VoiceRecorderSendButton].
class VoiceRecorder extends ConsumerStatefulWidget {
  const VoiceRecorder({super.key, required this.onCancel, this.height = 38});

  /// Called when the user cancels — includes auto-cancel on permission or
  /// recording errors (see [ref.listen] block in [build]).
  final VoidCallback onCancel;

  /// Pill height; defaults to 38 to match the text field.
  final double height;

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

  Widget _buildContent(BuildContext context) {
    final state = ref.watch(voiceRecordingProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPreparing = state.status == VoiceRecordingStatus.preparing;

    final fillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.08)
        : AppColors.warmWhite.withValues(alpha: 0.65);
    final borderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.1)
        : AppColors.warmBlack.withValues(alpha: 0.06);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.height),
      child: Container(
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).pill(widget.height),
          ),
          border: Border.all(
            color: borderColor,
            width: PrismTokens.hairlineBorderWidth,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: isPreparing
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PrismSpinner(color: theme.colorScheme.primary, size: 14),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.l10n.voicePreparingNote,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13.5,
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
                      height: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Duration(milliseconds: state.elapsedMs).toVoiceFormat(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Cancel button rendered alongside [VoiceRecorder] — matches the chat row's
/// 38px circle buttons. Stops the recording and invokes [onCancel].
class VoiceRecorderCancelButton extends ConsumerWidget {
  const VoiceRecorderCancelButton({
    super.key,
    required this.size,
    required this.onCancel,
  });

  final double size;
  final VoidCallback onCancel;

  Future<void> _handleTap(WidgetRef ref) async {
    await ref.read(voiceRecordingProvider.notifier).cancelRecording();
    onCancel();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(voiceRecordingProvider);
    final enabled = state.status != VoiceRecordingStatus.preparing;

    return Semantics(
      label: context.l10n.chatVoiceRecorderCancel,
      button: true,
      enabled: enabled,
      child: Tooltip(
        message: context.l10n.chatVoiceRecorderCancel,
        child: GestureDetector(
          onTap: enabled ? () => _handleTap(ref) : null,
          child: TintedGlassSurface(
            width: size,
            height: size,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(size / 2),
            ),
            child: Icon(
              AppIcons.close,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// Send button rendered alongside [VoiceRecorder] — matches the chat row's
/// 38px send button. Enables after ≥ 1s of recording.
class VoiceRecorderSendButton extends ConsumerStatefulWidget {
  const VoiceRecorderSendButton({
    super.key,
    required this.size,
    required this.onSend,
  });

  final double size;
  final void Function(Uint8List audioBytes, int durationMs, String waveformB64)
  onSend;

  @override
  ConsumerState<VoiceRecorderSendButton> createState() =>
      _VoiceRecorderSendButtonState();
}

class _VoiceRecorderSendButtonState
    extends ConsumerState<VoiceRecorderSendButton> {
  bool _pressed = false;

  Future<void> _handleTap() async {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final state = ref.watch(voiceRecordingProvider);
    final isPreparing = state.status == VoiceRecordingStatus.preparing;
    final canSend =
        state.status == VoiceRecordingStatus.recording &&
        state.elapsedMs >= 1000;
    final showActiveState = canSend || isPreparing;

    return Semantics(
      label: isPreparing
          ? context.l10n.voicePreparingNote
          : context.l10n.chatVoiceRecorderSend,
      button: true,
      enabled: canSend,
      child: Tooltip(
        message: isPreparing
            ? context.l10n.voicePreparingNote
            : context.l10n.chatVoiceRecorderSend,
        child: GestureDetector(
          onTapDown: canSend
              ? (_) => setState(() => _pressed = true)
              : (_) => HapticFeedback.heavyImpact(),
          onTapUp: canSend
              ? (_) {
                  setState(() => _pressed = false);
                  _handleTap();
                }
              : null,
          onTapCancel: () => setState(() => _pressed = false),
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
              firstChild: TintedGlassSurface(
                width: widget.size,
                height: widget.size,
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(widget.size / 2),
                ),
                child: Icon(
                  AppIcons.arrowUpwardRounded,
                  size: 19,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
              secondChild: isPreparing
                  ? TintedGlassSurface(
                      width: widget.size,
                      height: widget.size,
                      borderRadius: BorderRadius.circular(
                        PrismShapes.of(context).radius(widget.size / 2),
                      ),
                      tint: primary,
                      child: PrismSpinner(color: primary, size: 18),
                    )
                  : TintedGlassSurface(
                      width: widget.size,
                      height: widget.size,
                      borderRadius: BorderRadius.circular(
                        PrismShapes.of(context).radius(widget.size / 2),
                      ),
                      tint: primary,
                      child: Icon(
                        AppIcons.arrowUpwardRounded,
                        size: 19,
                        color: primary,
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
  late final _WaveformModel _model;

  Duration _lastTick = Duration.zero;

  static const _animDuration = 150.0;

  @override
  void initState() {
    super.initState();
    _model = _WaveformModel(
      samples: List.of(widget.samples),
      barProgress: List.filled(widget.samples.length, 1.0, growable: true),
      color: widget.color,
    );
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(_AnimatedWaveform old) {
    super.didUpdateWidget(old);
    _model.color = widget.color;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    // Cap per-frame delta so a GC pause or dropped frame doesn't cause bars
    // to jump instead of animating through the skipped time smoothly.
    if (dt > 50.0) dt = 50.0;

    final newSamples = widget.samples;
    while (_model.barProgress.length < newSamples.length) {
      _model.barProgress.add(0.0);
    }

    var dirty = false;

    for (var i = 0; i < _model.barProgress.length; i++) {
      if (_model.barProgress[i] < 1.0) {
        _model.barProgress[i] = (_model.barProgress[i] + dt / _animDuration)
            .clamp(0.0, 1.0);
        dirty = true;
      }
    }

    if (dirty) {
      _model.update(newSamples);
    }
  }

  @override
  Widget build(BuildContext context) {
    _model.color = widget.color;
    return CustomPaint(
      painter: _WaveformPainter(_model),
      size: Size(double.infinity, widget.height),
    );
  }
}

/// Holds mutable waveform state and notifies the painter to repaint
/// without triggering a widget rebuild.
class _WaveformModel extends ChangeNotifier {
  _WaveformModel({
    required List<double> samples,
    required this.barProgress,
    required this.color,
  }) : _samples = samples;

  List<double> _samples;
  List<double> barProgress;
  Color color;

  List<double> get samples => _samples;

  void update(List<double> newSamples) {
    _samples = newSamples;
    notifyListeners();
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this._model) : super(repaint: _model);

  final _WaveformModel _model;

  static const _barWidth = 3.0;
  static const _barGap = 2.0;
  static const _minHeight = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = _model.samples;
    if (samples.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final maxBars = (size.width / (_barWidth + _barGap)).floor();
    if (maxBars == 0) {
      canvas.restore();
      return;
    }

    final startIndex = samples.length > maxBars ? samples.length - maxBars : 0;
    final visibleCount = samples.length - startIndex;

    var minVal = double.infinity;
    var maxVal = -double.infinity;
    for (var i = startIndex; i < samples.length; i++) {
      final v = samples[i];
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    final range = (maxVal - minVal).abs();

    final paint = Paint()
      ..color = _model.color
      ..style = PaintingStyle.fill;
    final maxHeight = size.height * 0.85;
    const barStep = _barWidth + _barGap;

    // Bars are right-aligned: the newest sample always occupies the rightmost
    // slot. No horizontal animation — only bar height is animated.
    final firstSlot = maxBars - visibleCount;

    for (var i = 0; i < visibleCount; i++) {
      final sampleIndex = startIndex + i;
      final sample = samples[sampleIndex];
      final normalized = range < 0.01 ? 0.5 : (sample - minVal) / range;
      final targetHeight = _minHeight + normalized * (maxHeight - _minHeight);

      final growProgress = sampleIndex < _model.barProgress.length
          ? Curves.easeOut.transform(_model.barProgress[sampleIndex])
          : 1.0;
      final barHeight = _minHeight + (targetHeight - _minHeight) * growProgress;

      final x = (firstSlot + i) * barStep;
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
  bool shouldRepaint(_WaveformPainter old) => false;
}
