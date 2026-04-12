import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
<<<<<<< HEAD
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Modal sheet that prompts for the app PIN when the cached DEK is missing
/// but other credentials exist (e.g. after an app update that introduced
/// Signal-style key caching).
=======
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';

/// Modal sheet that prompts for the 6-digit sync PIN when the cached DEK is
/// missing but other credentials exist (e.g. after an app update or restart).
///
/// Replaces [SyncPasswordSheet] in devices set up with PIN-based auth.
/// The PIN is used as the Argon2id password for the key hierarchy.
>>>>>>> worktree-agent-a6254940
class SyncPinSheet extends ConsumerStatefulWidget {
  const SyncPinSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
<<<<<<< HEAD
      isDismissible: true,
=======
      isDismissible: false, // User must enter their PIN to proceed
>>>>>>> worktree-agent-a6254940
      builder: (_) => const SyncPinSheet(),
    );
  }

  @override
  ConsumerState<SyncPinSheet> createState() => _SyncPinSheetState();
}

<<<<<<< HEAD
class _SyncPinSheetState extends ConsumerState<SyncPinSheet> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final pin = _controller.text.trim();
    if (pin.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final success = await ref
        .read(syncHealthProvider.notifier)
        .attemptUnlock(pin);
=======
class _SyncPinSheetState extends ConsumerState<SyncPinSheet>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;
  bool _isLoading = false;
  bool _hasError = false;

  // Brute-force throttling
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  static const _maxAttempts = 5;
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

  String get _subtitle {
    if (_isLockedOut) {
      return 'Too many attempts. Try again in ${_lockoutSecondsRemaining}s';
    }
    if (_hasError) return 'Incorrect PIN. Try again.';
    return 'Enter your 6-digit PIN to unlock sync';
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength || _isLoading || _isLockedOut) return;
    Haptics.light();
    setState(() {
      _pin += digit;
      _hasError = false;
    });
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
>>>>>>> worktree-agent-a6254940

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
<<<<<<< HEAD
      setState(() {
        _isLoading = false;
        _error = context.l10n.settingsSyncPinWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
=======
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        final multiplier = _failedAttempts ~/ _maxAttempts;
        _lockedUntil = DateTime.now().add(
          Duration(seconds: _baseLockoutSeconds * multiplier),
        );
      }
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
    setState(() => _pin = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
>>>>>>> worktree-agent-a6254940
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
<<<<<<< HEAD
          Icon(
            AppIcons.lockOutline,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.settingsSyncPinTitle,
=======
          Icon(AppIcons.lockOutline, size: 40, color: accentColor),
          const SizedBox(height: 12),
          Text(
            'Unlock sync',
>>>>>>> worktree-agent-a6254940
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
<<<<<<< HEAD
            context.l10n.settingsSyncPinBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          PrismTextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enabled: !_isLoading,
            onSubmitted: (_) => _unlock(),
            labelText: context.l10n.settingsSyncPinFieldLabel,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            errorText: _error,
          ),
          const SizedBox(height: 16),
          PrismButton(
            label: context.l10n.settingsSyncPinUnlock,
            onPressed: _unlock,
            isLoading: _isLoading,
          ),
=======
            _subtitle,
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
                  children: _buildRow(row, theme, accentColor),
                ),
              )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
>>>>>>> worktree-agent-a6254940
        ],
      ),
    );
  }
<<<<<<< HEAD
=======

  List<Widget> _buildRow(int row, ThemeData theme, Color accentColor) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return _SheetNumpadButton(
          label: digit,
          onTap: () => _onDigit(digit),
          theme: theme,
        );
      });
    }
    return [
      const SizedBox(width: 64, height: 64),
      _SheetNumpadButton(
        label: '0',
        onTap: () => _onDigit('0'),
        theme: theme,
      ),
      _SheetNumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        theme: theme,
      ),
    ];
  }
}

class _SheetNumpadButton extends StatelessWidget {
  const _SheetNumpadButton({
    this.label,
    this.icon,
    required this.onTap,
    required this.theme,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        ),
        child: label != null
            ? Text(
                label!,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, size: 22, color: theme.colorScheme.onSurface),
      ),
    );
  }
>>>>>>> worktree-agent-a6254940
}
