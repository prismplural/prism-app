import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';

/// The mode of the PIN input screen.
enum PinInputMode {
  /// Setting a new PIN.
  set,

  /// Confirming a newly set PIN.
  confirm,

  /// Unlocking the app with an existing PIN.
  unlock,
}

/// Full-screen PIN input with dot indicators, numpad, and optional biometric.
class PinInputScreen extends ConsumerStatefulWidget {
  const PinInputScreen({
    super.key,
    required this.mode,
    required this.onSuccess,
    this.pinToConfirm,
    this.onPinEntered,
    this.embedded = false,
  });

  final PinInputMode mode;
  final VoidCallback onSuccess;

  /// When [mode] is [PinInputMode.confirm], this is the PIN to match against.
  final String? pinToConfirm;

  /// Called with the entered PIN when the PIN is accepted (before [onSuccess]).
  /// Useful for callers that need to capture the PIN value, e.g. to pass as
  /// [pinToConfirm] in a follow-up confirm phase.
  final void Function(String pin)? onPinEntered;

  /// When [true], renders without the [Material]/[SafeArea] wrapper, title, and
  /// subtitle — suitable for embedding inside a larger scaffold (e.g. onboarding).
  final bool embedded;

  @override
  ConsumerState<PinInputScreen> createState() => _PinInputScreenState();
}

class _PinInputScreenState extends ConsumerState<PinInputScreen>
    with TickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;

  // Brute-force throttling
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  static const _maxAttemptsBeforeLockout = 5;
  static const _baseLockoutSeconds = 30;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  late AnimationController _dotController;
  late Animation<double> _dotScaleAnim;
  int? _lastFilledDotIndex;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _dotScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
    ]).animate(_dotController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  String _title(BuildContext context) {
    final l10n = context.l10n;
    return switch (widget.mode) {
      PinInputMode.set => l10n.pinLockSetTitle,
      PinInputMode.confirm => l10n.pinLockConfirmTitle,
      PinInputMode.unlock => l10n.pinLockEnterTitle,
    };
  }

  String _subtitle(BuildContext context) {
    if (_isLockedOut) {
      return 'Too many attempts. Try again in ${_lockoutRemainingSeconds}s';
    }
    final l10n = context.l10n;
    return switch (widget.mode) {
      PinInputMode.set => l10n.pinLockSetSubtitle,
      PinInputMode.confirm => l10n.pinLockConfirmSubtitle,
      PinInputMode.unlock => l10n.pinLockUnlockSubtitle,
    };
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength || _isLockedOut) return;
    Haptics.light();
    setState(() => _pin += digit);
    final mode = VisualEffectsModeX.of(context, ref);
    if (mode.useAnimations) {
      setState(() => _lastFilledDotIndex = _pin.length - 1);
      _dotController.forward(from: 0);
    }
    if (_pin.length == _pinLength) {
      _onPinComplete();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    Haptics.selection();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  bool get _isLockedOut {
    if (_lockedUntil == null) return false;
    if (DateTime.now().isAfter(_lockedUntil!)) {
      _lockedUntil = null;
      return false;
    }
    return true;
  }

  int get _lockoutRemainingSeconds {
    if (_lockedUntil == null) return 0;
    return _lockedUntil!.difference(DateTime.now()).inSeconds.clamp(0, 9999);
  }

  Future<void> _onPinComplete() async {
    if (_isLockedOut) {
      _showError();
      return;
    }

    switch (widget.mode) {
      case PinInputMode.set:
        widget.onPinEntered?.call(_pin);
        widget.onSuccess();
      case PinInputMode.confirm:
        if (_pin == widget.pinToConfirm) {
          widget.onPinEntered?.call(_pin);
          widget.onSuccess();
        } else {
          _showError();
        }
      case PinInputMode.unlock:
        final service = ref.read(pinLockServiceProvider);
        final valid = await service.verifyStoredPin(_pin);
        if (valid) {
          _failedAttempts = 0;
          widget.onPinEntered?.call(_pin);
          widget.onSuccess();
        } else {
          _failedAttempts++;
          if (_failedAttempts >= _maxAttemptsBeforeLockout) {
            final multiplier = (_failedAttempts ~/ _maxAttemptsBeforeLockout);
            final lockoutSeconds = _baseLockoutSeconds * multiplier;
            _lockedUntil = DateTime.now().add(Duration(seconds: lockoutSeconds));
          }
          _showError();
        }
    }
  }

  void _showError() {
    setState(() => _lastFilledDotIndex = null);
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0);
    setState(() => _pin = '');
  }

  Future<void> _onBiometric() async {
    final service = ref.read(pinLockServiceProvider);
    final success = await service.authenticateBiometric();
    if (success && mounted) {
      widget.onSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final biometricAvailable =
        ref.watch(isBiometricAvailableProvider).value ?? false;
    final biometricEnabled = ref.watch(biometricLockEnabledProvider);
    final showBiometric = widget.mode == PinInputMode.unlock && biometricAvailable && biometricEnabled;
    final clampedSize = ((MediaQuery.of(context).size.width - 80) / 3).clamp(56.0, 72.0);

    final content = Column(
      children: [
        if (widget.embedded)
          const Spacer()
        else
          const Spacer(flex: 2),
        if (!widget.embedded) ...[
          // Title
          Text(
            _title(context),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _subtitle(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 40),
        ],
        // Dot indicators with shake animation
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pinLength, (i) {
              final filled = i < _pin.length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: AnimatedBuilder(
                  animation: _dotScaleAnim,
                  builder: (context, child) => Transform.scale(
                    scale: i == _lastFilledDotIndex ? _dotScaleAnim.value : 1.0,
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? accentColor
                          : accentColor.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        if (widget.embedded)
          const Spacer()
        else
          const Spacer(flex: 2),
        // Numpad
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              for (var row = 0; row < 4; row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _buildRow(row, showBiometric, theme, clampedSize),
                  ),
                ),
            ],
          ),
        ),
        const Spacer(),
      ],
    );

    if (widget.embedded) return content;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(child: content),
    );
  }

  List<Widget> _buildRow(int row, bool showBiometric, ThemeData theme, double clampedSize) {
    if (row < 3) {
      // Rows 0-2: digits 1-9
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return PinNumpadButton(
          label: digit,
          onTap: () => _onDigit(digit),
          size: clampedSize,
        );
      });
    }
    // Row 3: biometric / 0 / backspace
    return [
      if (showBiometric)
        PinNumpadButton(
          icon: AppIcons.fingerprint,
          onTap: _onBiometric,
          size: clampedSize,
          semanticLabel: context.l10n.pinLockBiometricTitle,
        )
      else
        ExcludeSemantics(child: SizedBox(width: clampedSize, height: clampedSize)),
      PinNumpadButton(
        label: '0',
        onTap: () => _onDigit('0'),
        size: clampedSize,
      ),
      PinNumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        size: clampedSize,
        semanticLabel: context.l10n.delete,
      ),
    ];
  }
}
