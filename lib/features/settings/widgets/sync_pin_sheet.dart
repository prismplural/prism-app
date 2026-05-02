import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/crypto/bip39_validate.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two-step modal sheet that prompts for the 12-word BIP39 recovery
/// phrase and then the 6-digit PIN to unlock the sync key hierarchy.
///
/// Used when the cached DEK is missing but other credentials still
/// exist (e.g. after an app update, restart, or keychain wipe). The
/// mnemonic is no longer stored on the device, so we have to collect
/// both inputs from the user — step 1 collects the recovery phrase,
/// step 2 reuses the existing numpad.
enum _SyncPinStep { enterMnemonic, enterPin }

class SyncPinSheet extends ConsumerStatefulWidget {
  const SyncPinSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
      isDismissible: false, // User must unlock to proceed
      builder: (_) => const SyncPinSheet(),
    );
  }

  @override
  ConsumerState<SyncPinSheet> createState() => _SyncPinSheetState();
}

class _SyncPinSheetState extends ConsumerState<SyncPinSheet>
    with TickerProviderStateMixin {
  _SyncPinStep _step = _SyncPinStep.enterMnemonic;

  // Step 1 — mnemonic entry
  final _mnemonicController = TextEditingController();
  String? _mnemonicError;
  String? _mnemonic;
  bool _mnemonicBusy = false;
  bool _lostPhraseExpanded = false;

  // Step 2 — PIN entry
  static const _pinLength = 6;
  late final PinBuffer _pin = PinBuffer(length: _pinLength);
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
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _dotScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
    ]).animate(_dotController);
    // Rebuild when the mnemonic text changes so the "Continue" button's
    // enabled state tracks the current word count.
    _mnemonicController.addListener(_onMnemonicChanged);
    _loadLockoutState();
  }

  void _onMnemonicChanged() {
    if (!mounted) return;
    // A cheap rebuild keeps `wordsEntered` / `canContinue` in sync with
    // whatever the user has typed so far.
    setState(() {});
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
        _prefsKeyLockedUntil,
        _lockedUntil!.millisecondsSinceEpoch,
      );
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
    // Clear controller text so the mnemonic isn't resident in memory
    // longer than it has to be.
    _mnemonicController.removeListener(_onMnemonicChanged);
    _mnemonicController.clear();
    _mnemonicController.dispose();
    _mnemonic = null;
    _pin.clear();
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

  String _pinSubtitle(BuildContext context) {
    if (_isLockedOut) {
      return 'Too many attempts. Try again in ${_lockoutSecondsRemaining}s';
    }
    if (_hasError) return context.l10n.syncPinSheetUnlockFailed;
    return context.l10n.syncPinSheetSubtitle;
  }

  // ── Step 1 actions ────────────────────────────────────────────────────

  Future<void> _submitMnemonic() async {
    final normalized = PrismMnemonicField.normalize(_mnemonicController.text);
    if (normalized.isEmpty) {
      setState(() => _mnemonicError = context.l10n.syncPinSheetMnemonicInvalid);
      return;
    }

    setState(() {
      _mnemonicBusy = true;
      _mnemonicError = null;
    });

    if (!validateBip39Mnemonic(normalized)) {
      if (!mounted) return;
      setState(() {
        _mnemonicBusy = false;
        _mnemonicError = context.l10n.syncPinSheetMnemonicInvalid;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _mnemonic = normalized;
      _mnemonicBusy = false;
      _step = _SyncPinStep.enterPin;
    });
  }

  // ── Step 2 actions ────────────────────────────────────────────────────

  void _onDigit(String digit) {
    if (_isLoading || _isLockedOut || !_pin.appendDigit(digit)) return;
    Haptics.light();
    setState(() {
      _hasError = false;
    });
    final mode = VisualEffectsModeX.of(context, ref);
    if (mode.useAnimations) {
      setState(() => _lastFilledDotIndex = _pin.length - 1);
      _dotController.forward(from: 0);
    }
    if (_pin.isFull) {
      _onPinComplete();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isLoading) return;
    Haptics.selection();
    setState(_pin.removeLast);
  }

  Future<void> _onPinComplete() async {
    if (_isLockedOut) {
      _showError();
      return;
    }
    final mnemonic = _mnemonic;
    if (mnemonic == null) {
      // Defensive: shouldn't happen — step 2 isn't reachable without it.
      setState(() {
        _step = _SyncPinStep.enterMnemonic;
        _pin.clear();
        _hasError = false;
      });
      return;
    }

    final pin = _pin.consumeStringAndClear();
    setState(() => _isLoading = true);

    final success = await ref
        .read(syncHealthProvider.notifier)
        .attemptUnlock(pin: pin, mnemonic: mnemonic);

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
      _pin.clear();
      _lastFilledDotIndex = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SecureScope(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + bottomInset,
        ),
        child: switch (_step) {
          _SyncPinStep.enterMnemonic => _buildMnemonicStep(theme),
          _SyncPinStep.enterPin => _buildPinStep(theme),
        },
      ),
    );
  }

  Widget _buildMnemonicStep(ThemeData theme) {
    final accentColor = theme.colorScheme.primary;
    final l10n = context.l10n;
    final wordsEntered = PrismMnemonicField.normalize(
      _mnemonicController.text,
    ).split(' ').where((w) => w.isNotEmpty).length;
    final canContinue = wordsEntered == 12 && !_mnemonicBusy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(AppIcons.key, size: 40, color: accentColor),
        const SizedBox(height: 12),
        Text(
          l10n.syncPinSheetTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.syncPinSheetMnemonicSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        PrismMnemonicField(
          controller: _mnemonicController,
          errorText: _mnemonicError,
          enabled: !_mnemonicBusy,
          autofocus: true,
          onSubmitted: (_) {
            if (canContinue) _submitMnemonic();
          },
        ),
        const SizedBox(height: 20),
        PrismButton(
          label: l10n.syncPinSheetMnemonicContinue,
          tone: PrismButtonTone.filled,
          onPressed: canContinue ? _submitMnemonic : () {},
          enabled: canContinue,
          isLoading: _mnemonicBusy,
        ),
        const SizedBox(height: 12),
        // Lost your phrase? — inline expandable explainer.
        Align(
          alignment: Alignment.center,
          child: PrismButton(
            label: l10n.syncPinSheetLostPhrase,
            tone: PrismButtonTone.subtle,
            density: PrismControlDensity.compact,
            onPressed: () =>
                setState(() => _lostPhraseExpanded = !_lostPhraseExpanded),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _lostPhraseExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              l10n.syncPinSheetLostPhraseBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinStep(ThemeData theme) {
    final accentColor = theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: context.l10n.syncPinSheetBack,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
            density: PrismControlDensity.compact,
            enabled: !_isLoading,
            onPressed: _isLoading
                ? () {}
                : () => setState(() {
                    _step = _SyncPinStep.enterMnemonic;
                    _pin.clear();
                    _hasError = false;
                  }),
          ),
        ),
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
          _pinSubtitle(context),
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
      PinNumpadButton(label: '0', onTap: () => _onDigit('0'), size: 64),
      PinNumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        size: 64,
        semanticLabel: context.l10n.delete,
      ),
    ];
  }
}
