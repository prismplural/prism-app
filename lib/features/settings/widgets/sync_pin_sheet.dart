import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modal sheet that prompts for the 6-digit sync PIN when the cached DEK is
/// missing but other credentials exist (e.g. after an app update or restart).
///
/// Replaces [SyncPasswordSheet] in devices set up with PIN-based auth.
/// The PIN is used as the Argon2id password for the key hierarchy.
class SyncPinSheet extends ConsumerStatefulWidget {
  const SyncPinSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
      isDismissible: false, // User must enter their PIN to proceed
      builder: (_) => const SyncPinSheet(),
    );
  }

  @override
  ConsumerState<SyncPinSheet> createState() => _SyncPinSheetState();
}

class _SyncPinSheetState extends ConsumerState<SyncPinSheet>
    with TickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;
  bool _isLoading = false;
  bool _hasError = false;

  // Brute-force throttling — persisted to SharedPreferences so lockout
  // survives sheet dismissal and app restarts.
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  static const _maxAttempts = 5;
  static const _baseLockoutSeconds = 30;
  static const _prefsKeyAttempts = 'prism.sync_pin_failed_attempts';
  static const _prefsKeyLockedUntil = 'prism.sync_pin_locked_until_ms';

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
    _loadLockoutState();
  }

  Future<void> _loadLockoutState() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = prefs.getInt(_prefsKeyAttempts) ?? 0;
    final lockedUntilMs = prefs.getInt(_prefsKeyLockedUntil);
    final lockedUntil = lockedUntilMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lockedUntilMs)
        : null;
    if (!mounted) return;
    setState(() {
      _failedAttempts = attempts;
      _lockedUntil = lockedUntil;
    });
  }

  Future<void> _saveLockoutState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyAttempts, _failedAttempts);
    if (_lockedUntil != null) {
      await prefs.setInt(
          _prefsKeyLockedUntil, _lockedUntil!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_prefsKeyLockedUntil);
    }
  }

  Future<void> _clearLockoutState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyAttempts);
    await prefs.remove(_prefsKeyLockedUntil);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  bool get _isLockedOut {
    if (_lockedUntil == null) return false;
    if (DateTime.now().isAfter(_lockedUntil!)) {
      _lockedUntil = null;
      return false;
    }
    return true;
  }

  int get _lockoutSecondsRemaining {
    if (_lockedUntil == null) return 0;
    return _lockedUntil!.difference(DateTime.now()).inSeconds.clamp(0, 9999);
  }

  String _subtitle(BuildContext context) {
    if (_isLockedOut) {
      return 'Too many attempts. Try again in ${_lockoutSecondsRemaining}s';
    }
    if (_hasError) return 'Incorrect PIN. Try again.';
    return context.l10n.syncPinSheetSubtitle;
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength || _isLoading || _isLockedOut) return;
    Haptics.light();
    setState(() {
      _pin += digit;
      _hasError = false;
    });
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
    if (_pin.isEmpty || _isLoading) return;
    Haptics.selection();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _onPinComplete() async {
    if (_isLockedOut) {
      _showError();
      return;
    }

    setState(() => _isLoading = true);

    final success = await ref
        .read(syncHealthProvider.notifier)
        .attemptUnlock(_pin);

    if (!mounted) return;

    if (success) {
      await _clearLockoutState();
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        final multiplier = _failedAttempts ~/ _maxAttempts;
        _lockedUntil = DateTime.now().add(
          Duration(seconds: _baseLockoutSeconds * multiplier),
        );
      }
      await _saveLockoutState();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      _showError();
    }
  }

  void _showError() {
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0);
    setState(() {
      _pin = '';
      _lastFilledDotIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(AppIcons.lockOutline, size: 40, color: accentColor),
          const SizedBox(height: 12),
          Text(
            context.l10n.syncPinSheetTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _hasError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Dot indicators
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
                      width: 14,
                      height: 14,
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
          const SizedBox(height: 24),
          // Numpad
          if (!_isLoading)
            for (var row = 0; row < 4; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _buildRow(row),
                ),
              )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: PrismLoadingState(),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRow(int row) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return PinNumpadButton(
          label: digit,
          onTap: () => _onDigit(digit),
          size: 64,
        );
      });
    }
    return [
      const SizedBox(width: 64, height: 64),
      PinNumpadButton(
        label: '0',
        onTap: () => _onDigit('0'),
        size: 64,
      ),
      PinNumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        size: 64,
        semanticLabel: context.l10n.delete,
      ),
    ];
  }
}
