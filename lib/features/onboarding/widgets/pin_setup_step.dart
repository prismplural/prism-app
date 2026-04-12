import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Onboarding step that collects a new 6-digit PIN, then confirms it.
///
/// Renders [PinInputScreen] in set mode, then confirm mode. When both match,
/// calls [onPinConfirmed] with the PIN. If key derivation throws, shows an
/// error toast so the user can retry.
class PinSetupStep extends ConsumerStatefulWidget {
  const PinSetupStep({
    super.key,
    required this.onPinConfirmed,
  });

  /// Called with the confirmed PIN once both entries match. This callback
  /// is async — it performs key derivation and keychain writes.
  final Future<void> Function(String pin) onPinConfirmed;

  @override
  ConsumerState<PinSetupStep> createState() => _PinSetupStepState();
}

class _PinSetupStepState extends ConsumerState<PinSetupStep> {
  String? _firstPin;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_firstPin == null) {
      return _RawPinEntry(
        mode: PinInputMode.set,
        onPinEntered: (pin) {
          setState(() => _firstPin = pin);
        },
      );
    } else {
      return _RawPinEntry(
        mode: PinInputMode.confirm,
        pinToConfirm: _firstPin,
        onPinEntered: (pin) async {
          setState(() => _isProcessing = true);
          try {
            await widget.onPinConfirmed(pin);
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _isProcessing = false;
              _firstPin = null; // Reset to let user retry
            });
            // ignore: use_build_context_synchronously
            PrismToast.error(
              context,
              message: 'Setup failed. Please try again.',
            );
          }
        },
      );
    }
  }
}

/// Raw PIN entry widget that captures the PIN and calls [onPinEntered].
///
/// This replicates the core of [PinInputScreen] but exposes the PIN value
/// in the callback rather than a plain VoidCallback.
class _RawPinEntry extends ConsumerStatefulWidget {
  const _RawPinEntry({
    required this.mode,
    required this.onPinEntered,
    this.pinToConfirm,
  });

  final PinInputMode mode;
  final String? pinToConfirm;
  final void Function(String pin) onPinEntered;

  @override
  ConsumerState<_RawPinEntry> createState() => _RawPinEntryState();
}

class _RawPinEntryState extends ConsumerState<_RawPinEntry>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;

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

  String get _title => switch (widget.mode) {
    PinInputMode.set => 'Set PIN',
    PinInputMode.confirm => 'Confirm PIN',
    PinInputMode.unlock => 'Enter PIN',
  };

  String get _subtitle => switch (widget.mode) {
    PinInputMode.set => 'Choose a $_pinLength-digit PIN',
    PinInputMode.confirm => 'Re-enter your PIN to confirm',
    PinInputMode.unlock => 'Enter your PIN to unlock',
  };

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    setState(() => _pin += digit);
    if (_pin.length == _pinLength) {
      _onPinComplete();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _onPinComplete() {
    if (widget.mode == PinInputMode.confirm) {
      if (_pin == widget.pinToConfirm) {
        widget.onPinEntered(_pin);
      } else {
        _shakeController.forward(from: 0);
        setState(() => _pin = '');
      }
    } else {
      widget.onPinEntered(_pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  for (var row = 0; row < 4; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _buildRow(row, theme),
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

  List<Widget> _buildRow(int row, ThemeData theme) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return _NumpadButton(label: digit, onTap: () => _onDigit(digit));
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      _NumpadButton(label: '0', onTap: () => _onDigit('0')),
      _NumpadButton(
        icon: Icons.backspace_outlined,
        onTap: _onBackspace,
      ),
    ];
  }
}

class _NumpadButton extends StatelessWidget {
  const _NumpadButton({this.label, this.icon, required this.onTap});

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
