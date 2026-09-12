import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/crypto/bip39_validate.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/numpad_keyboard_listener.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';
import 'package:prism_plurality/features/settings/widgets/secret_key_reveal_content.dart';

/// Two-step modal sheet used to recover `wrapped_dek` when the keychain
/// slot is missing but the engine is still unlocked (runtime DEK cache
/// survived). Collects mnemonic + PIN, calls `attemptRewrap` on the
/// `syncHealthProvider` notifier, and dismisses on success.
enum _SyncRewrapStep { enterMnemonic, revealReplacement, enterPin }

class SyncRewrapSheet extends ConsumerStatefulWidget {
  const SyncRewrapSheet({super.key});

  @visibleForTesting
  static Future<String> Function()? debugGenerateSecretKeyOverride;

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
      isDismissible: false,
      builder: (_) => const SyncRewrapSheet(),
    );
  }

  @override
  ConsumerState<SyncRewrapSheet> createState() => _SyncRewrapSheetState();
}

class _SyncRewrapSheetState extends ConsumerState<SyncRewrapSheet>
    with TickerProviderStateMixin {
  _SyncRewrapStep _step = _SyncRewrapStep.enterMnemonic;

  // Step 1 — mnemonic entry
  final _mnemonicController = TextEditingController();
  String? _mnemonicError;
  String? _mnemonic;
  bool _mnemonicBusy = false;
  bool _disconnectBusy = false;
  String? _replacementMnemonic;
  bool _replacementSaved = false;
  bool _usingReplacementMnemonic = false;

  // Step 2 — PIN entry
  static const _pinLength = 6;
  late final PinBuffer _pin = PinBuffer(length: _pinLength);
  late final PinBuffer _firstPin = PinBuffer(length: _pinLength);
  bool _isLoading = false;
  bool _confirmingPin = false;
  String? _pinError;

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
    _mnemonicController.addListener(_onMnemonicChanged);
  }

  void _onMnemonicChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _mnemonicController.removeListener(_onMnemonicChanged);
    _mnemonicController.clear();
    _mnemonicController.dispose();
    _mnemonic = null;
    _replacementMnemonic = null;
    _pin.clear();
    _firstPin.clear();
    _shakeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  String _pinSubtitle(BuildContext context) {
    final error = _pinError;
    if (error != null) return error;
    if (_confirmingPin) return context.l10n.pinLockConfirmTitle;
    return context.l10n.syncRewrapSheetPinSubtitle;
  }

  void _resetPinEntry() {
    _pin.clear();
    _firstPin.clear();
    _confirmingPin = false;
    _pinError = null;
    _lastFilledDotIndex = null;
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
      _usingReplacementMnemonic = false;
      _mnemonicBusy = false;
      _step = _SyncRewrapStep.enterPin;
    });
  }

  Future<void> _generateReplacementPhrase() async {
    setState(() {
      _mnemonicBusy = true;
      _mnemonicError = null;
    });
    try {
      final generate =
          SyncRewrapSheet.debugGenerateSecretKeyOverride ??
          ffi.generateSecretKey;
      final replacement = await generate();
      if (!mounted) return;
      setState(() {
        _replacementMnemonic = replacement;
        _replacementSaved = false;
        _mnemonicBusy = false;
        _step = _SyncRewrapStep.revealReplacement;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _mnemonicBusy = false);
      PrismToast.error(context, message: context.l10n.syncRewrapSheetFailed);
    }
  }

  void _continueWithReplacementPhrase() {
    final replacement = _replacementMnemonic;
    if (!_replacementSaved || replacement == null) return;
    setState(() {
      _mnemonic = replacement;
      _usingReplacementMnemonic = true;
      _step = _SyncRewrapStep.enterPin;
    });
  }

  void _discardReplacementPhrase() {
    setState(() {
      _replacementMnemonic = null;
      _replacementSaved = false;
      _usingReplacementMnemonic = false;
      _step = _SyncRewrapStep.enterMnemonic;
    });
  }

  Future<void> _disconnectSync() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.resetDataConfirmSyncTitle,
      message: context.l10n.resetDataConfirmSync,
      confirmLabel: context.l10n.resetDataConfirmSync2,
      cancelLabel: context.l10n.cancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _disconnectBusy = true);
    try {
      await ref
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.sync);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _disconnectBusy = false);
      PrismToast.error(context, message: context.l10n.syncRewrapSheetFailed);
    }
  }

  // ── Step 2 actions ────────────────────────────────────────────────────

  void _onDigit(String digit) {
    if (_isLoading || !_pin.appendDigit(digit)) return;
    Haptics.light();
    setState(() {
      _pinError = null;
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
    final mnemonic = _mnemonic;
    if (mnemonic == null) {
      setState(() {
        _step = _SyncRewrapStep.enterMnemonic;
        _resetPinEntry();
      });
      return;
    }

    if (!_confirmingPin) {
      setState(() {
        _firstPin.replaceWith(_pin);
        _pin.clear();
        _confirmingPin = true;
        _pinError = null;
        _lastFilledDotIndex = null;
      });
      return;
    }

    if (!_firstPin.contentEquals(_pin)) {
      setState(() {
        _resetPinEntry();
        _pinError = context.l10n.settingsChangePinMismatch;
      });
      _showError();
      return;
    }

    final pin = _firstPin.consumeStringAndClear();
    _pin.clear();
    setState(() => _isLoading = true);

    final success = await ref
        .read(syncHealthProvider.notifier)
        .attemptRewrap(pin: pin, mnemonic: mnemonic);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isLoading = false;
        _confirmingPin = false;
        _pinError = context.l10n.syncRewrapSheetFailed;
      });
      _showError();
    }
  }

  void _showError() {
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0);
    setState(() {
      _pin.clear();
      _firstPin.clear();
      _confirmingPin = false;
      _lastFilledDotIndex = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = modalBottomInsetOf(context);

    // Only the explicit backup surface allows screenshots.
    return SecureScope(
      allowAndroidScreenCapture: _step == _SyncRewrapStep.revealReplacement,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + bottomInset,
        ),
        child: switch (_step) {
          _SyncRewrapStep.enterMnemonic => _buildMnemonicStep(theme),
          _SyncRewrapStep.revealReplacement => _buildReplacementPhraseStep(
            theme,
          ),
          _SyncRewrapStep.enterPin => _buildPinStep(theme),
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
    final canContinue =
        wordsEntered == 12 && !_mnemonicBusy && !_disconnectBusy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(AppIcons.key, size: 40, color: accentColor),
        const SizedBox(height: 12),
        Text(
          l10n.syncRewrapSheetTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.syncRewrapSheetMnemonicSubtitle,
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
        PrismButton(
          label: l10n.syncPinSheetLostPhrase,
          tone: PrismButtonTone.subtle,
          onPressed: _mnemonicBusy ? () {} : _generateReplacementPhrase,
          enabled: !_mnemonicBusy && !_disconnectBusy,
        ),
        const SizedBox(height: 12),
        PrismButton(
          label: l10n.resetDataConfirmSync2,
          tone: PrismButtonTone.outlined,
          onPressed: _disconnectBusy ? () {} : _disconnectSync,
          enabled: !_disconnectBusy && !_mnemonicBusy,
          isLoading: _disconnectBusy,
        ),
      ],
    );
  }

  Widget _buildReplacementPhraseStep(ThemeData theme) {
    final replacement = _replacementMnemonic;
    if (replacement == null) {
      return const SizedBox.shrink();
    }
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
            onPressed: _discardReplacementPhrase,
          ),
        ),
        Text(
          context.l10n.onboardingRecoveryPhraseTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.onboardingRecoveryPhraseSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SecretKeyRevealContent(
          mnemonic: replacement,
          hasSaved: _replacementSaved,
          onHasSavedChanged: (saved) {
            setState(() => _replacementSaved = saved);
          },
          requireInteraction: true,
        ),
        const SizedBox(height: 20),
        PrismButton(
          label: context.l10n.syncPinSheetMnemonicContinue,
          tone: PrismButtonTone.filled,
          onPressed: _replacementSaved ? _continueWithReplacementPhrase : () {},
          enabled: _replacementSaved,
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
                    _step = _usingReplacementMnemonic
                        ? _SyncRewrapStep.revealReplacement
                        : _SyncRewrapStep.enterMnemonic;
                    _resetPinEntry();
                  }),
          ),
        ),
        Icon(AppIcons.lockOutline, size: 40, color: accentColor),
        const SizedBox(height: 12),
        Text(
          context.l10n.syncRewrapSheetTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          _pinSubtitle(context),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _pinError != null
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
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
        if (!_isLoading)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: NumpadKeyboardListener(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                enabled: !_isLoading,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var row = 0; row < 4; row++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _buildRow(row),
                        ),
                      ),
                  ],
                ),
              ),
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
