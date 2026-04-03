import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

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
  });

  final PinInputMode mode;
  final VoidCallback onSuccess;

  /// When [mode] is [PinInputMode.confirm], this is the PIN to match against.
  final String? pinToConfirm;

  @override
  ConsumerState<PinInputScreen> createState() => _PinInputScreenState();
}

class _PinInputScreenState extends ConsumerState<PinInputScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;

  // Brute-force throttling
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  static const _maxAttemptsBeforeLockout = 5;
  static const _baseLockoutSeconds = 30;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

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
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String get _title {
    return switch (widget.mode) {
      PinInputMode.set => 'Set PIN',
      PinInputMode.confirm => 'Confirm PIN',
      PinInputMode.unlock => 'Enter PIN',
    };
  }

  String get _subtitle {
    if (_isLockedOut) {
      return 'Too many attempts. Try again in ${_lockoutRemainingSeconds}s';
    }
    return switch (widget.mode) {
      PinInputMode.set => 'Choose a $_pinLength-digit PIN',
      PinInputMode.confirm => 'Re-enter your PIN to confirm',
      PinInputMode.unlock => 'Enter your PIN to unlock',
    };
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength || _isLockedOut) return;
    Haptics.light();
    setState(() => _pin += digit);
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
        widget.onSuccess();
      case PinInputMode.confirm:
        if (_pin == widget.pinToConfirm) {
          widget.onSuccess();
        } else {
          _showError();
        }
      case PinInputMode.unlock:
        final service = ref.read(pinLockServiceProvider);
        final valid = await service.verifyStoredPin(_pin);
        if (valid) {
          _failedAttempts = 0;
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
    final showBiometric = widget.mode == PinInputMode.unlock && biometricAvailable;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // Title
            Text(
              _title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
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
                  );
                }),
              ),
            ),
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
                        children: _buildRow(row, showBiometric, theme),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRow(int row, bool showBiometric, ThemeData theme) {
    if (row < 3) {
      // Rows 0-2: digits 1-9
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return _NumpadButton(
          label: digit,
          onTap: () => _onDigit(digit),
        );
      });
    }
    // Row 3: biometric / 0 / backspace
    return [
      if (showBiometric)
        _NumpadButton(
          icon: AppIcons.fingerprint,
          onTap: _onBiometric,
        )
      else
        const SizedBox(width: 72, height: 72),
      _NumpadButton(
        label: '0',
        onTap: () => _onDigit('0'),
      ),
      _NumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
      ),
    ];
  }
}

class _NumpadButton extends StatelessWidget {
  const _NumpadButton({
    this.label,
    this.icon,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        child: label != null
            ? Text(
                label!,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, size: 24, color: theme.colorScheme.onSurface),
      ),
    );
  }
}
