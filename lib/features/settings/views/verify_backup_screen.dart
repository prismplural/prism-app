import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:prism_plurality/core/crypto/bip39_validate.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/security/pin_lockout_state.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/sync_pin_sheet.dart';
import 'package:prism_plurality/features/settings/widgets/sync_rewrap_sheet.dart';
import 'package:prism_plurality/features/settings/widgets/verify_backup_result_view.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/numpad_keyboard_listener.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_cell.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

enum _VerifyStep { enterPhrase, enterPin, result }

class VerifyBackupScreen extends ConsumerStatefulWidget {
  const VerifyBackupScreen({super.key});

  @override
  ConsumerState<VerifyBackupScreen> createState() => VerifyBackupScreenState();
}

/// Public so widget tests can reach [pinIsEmpty] via `tester.state<...>()`.
class VerifyBackupScreenState extends ConsumerState<VerifyBackupScreen>
    with WidgetsBindingObserver {
  _VerifyStep _step = _VerifyStep.enterPhrase;
  String? _mnemonic;
  late final PinBuffer _pin = PinBuffer(length: 6);
  VerifyBackupResult? _result;

  late final PinLockoutState _lockout = PinLockoutState(
    prefsScope: 'prism.verify_backup',
  );

  MobileScannerController? _scannerController;

  @visibleForTesting
  bool get pinIsEmpty => _pin.isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockout.load().then((_) {
      if (mounted) setState(() {});
    });

    // If wrapped_dek was wiped (rare iOS keychain anomaly) flip the engine
    // to needsRewrap on entry so the recovery banner shows up before the
    // user wastes a PIN attempt.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final hasWrappedDek = await ref.read(
          syncWrappedDekPresentProvider.future,
        );
        if (!hasWrappedDek && mounted) {
          ref
              .read(syncHealthProvider.notifier)
              .setState(SyncHealthState.needsRewrap);
        }
      } catch (_) {
        // Provider read failure is non-fatal — the banner reflects whatever
        // state the engine already reported.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // PIN alone is the credential; the mnemonic by itself does not unlock
      // anything. Keep _mnemonic so the user doesn't have to retype 12 words.
      _pin.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.clear();
    _mnemonic = null;
    unawaited(_disposeScanner());
    super.dispose();
  }

  Future<void> _resetToPhrase() async {
    _pin.clear();
    await _disposeScanner();
    if (!mounted) return;
    setState(() {
      _mnemonic = null;
      _result = null;
      _step = _VerifyStep.enterPhrase;
    });
  }

  void _resetToPin() {
    _pin.clear();
    setState(() {
      _result = null;
      _step = _VerifyStep.enterPin;
    });
  }

  MobileScannerController _ensureScanner() {
    return _scannerController ??= MobileScannerController();
  }

  Future<void> _disposeScanner() async {
    final scanner = _scannerController;
    if (scanner == null) return;
    _scannerController = null;

    try {
      await scanner.stop();
    } catch (_) {}

    try {
      await scanner.dispose();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final syncHealth = ref.watch(syncHealthProvider);

    final handle = ref.watch(prismSyncHandleProvider).value;
    final relayUrl = ref.watch(relayUrlProvider).value ?? '';
    final syncId = ref.watch(syncIdProvider).value;
    final deviceId = ref.watch(syncDeviceIdProvider).value;
    final hasDeviceSecret =
        ref.watch(syncDeviceSecretPresentProvider).value ?? false;
    final hasWrappedDek =
        ref.watch(syncWrappedDekPresentProvider).value ?? false;

    final canVerify =
        handle != null &&
        hasCompletePersistentSyncIdentity(
          relayUrl: relayUrl,
          syncId: syncId,
          deviceId: deviceId,
          hasDeviceSecret: hasDeviceSecret,
        ) &&
        hasWrappedDek;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.verifyBackupScreenTitle,
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHealthBanner(context, syncHealth),
            if (!canVerify)
              _buildEmptyState(context)
            else
              _buildStepContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Text(
          l10n.verifyBackupNoActiveInstall,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildHealthBanner(BuildContext context, SyncHealthState health) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    String? bannerText;
    Widget? bannerButton;

    switch (health) {
      case SyncHealthState.needsPassword:
        bannerText = l10n.verifyBackupLockedBanner;
        bannerButton = PrismButton(
          label: l10n.verifyBackupUnlockButton,
          onPressed: () => SyncPinSheet.show(context),
          tone: PrismButtonTone.filled,
        );
      case SyncHealthState.runtimeDekRestoreDeferred:
        bannerText = l10n.verifyBackupRuntimeDeferredBanner;
        bannerButton = PrismButton(
          label: l10n.verifyBackupUnlockButton,
          onPressed: () {
            ref
                .read(syncHealthProvider.notifier)
                .setState(SyncHealthState.needsPassword);
            SyncPinSheet.show(context);
          },
          tone: PrismButtonTone.filled,
        );
      case SyncHealthState.awaitingDeviceUnlock:
        bannerText = l10n.verifyBackupAwaitingUnlockBanner;
      case SyncHealthState.needsRewrap:
        bannerText = l10n.verifyBackupNeedsRewrapBanner;
        bannerButton = PrismButton(
          label: l10n.verifyBackupNeedsRewrapButton,
          onPressed: () => SyncRewrapSheet.show(context),
          tone: PrismButtonTone.filled,
        );
      default:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            bannerText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          if (bannerButton != null) ...[
            const SizedBox(height: 12),
            bannerButton,
          ],
        ],
      ),
    );
  }

  Widget _buildStepContent(BuildContext context) {
    final l10n = context.l10n;
    return switch (_step) {
      _VerifyStep.enterPhrase => _buildPhraseStep(context),
      _VerifyStep.enterPin => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepIndicator(context, 2, l10n.verifyBackupStepPin),
          _VerifyPinView(
            mnemonic: _mnemonic!,
            pin: _pin,
            lockout: _lockout,
            onMatch: (mnemonic) {
              setState(() {
                _result = VerifyBackupMatchResult(
                  mnemonic: mnemonic,
                  verifiedAt: DateTime.now(),
                );
                _step = _VerifyStep.result;
              });
            },
            onNoMatch: () {
              setState(() {
                _result = const VerifyBackupNoMatchResult();
                _step = _VerifyStep.result;
              });
            },
            onBack: _resetToPhrase,
          ),
        ],
      ),
      _VerifyStep.result => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepIndicator(context, 3, context.l10n.verifyBackupStepResult),
          const SizedBox(height: 16),
          VerifyBackupResultView(
            result: _result!,
            onDone: () => Navigator.of(context).pop(),
            onTryDifferent: _resetToPhrase,
            onReenterPin: _resetToPin,
          ),
        ],
      ),
    };
  }

  Widget _buildPhraseStep(BuildContext context) {
    final l10n = context.l10n;
    return _VerifyPhraseView(
      stepIndicator: _buildStepIndicator(
        context,
        1,
        l10n.verifyBackupStepPhrase,
      ),
      ensureScanner: _ensureScanner,
      disposeScanner: _disposeScanner,
      onSubmit: (mnemonic) async {
        await _disposeScanner();
        if (!mounted) return;
        setState(() {
          _mnemonic = mnemonic;
          _step = _VerifyStep.enterPin;
        });
      },
    );
  }

  Widget _buildStepIndicator(BuildContext context, int step, String name) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final steps = [
      (l10n.verifyBackupStepPhrase, 1),
      (l10n.verifyBackupStepPin, 2),
      (l10n.verifyBackupStepResult, 3),
    ];

    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.verifyBackupStepIndicatorLabel(step, name),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              Text(
                '${steps[i].$2} ${steps[i].$1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: steps[i].$2 == step
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: steps[i].$2 == step
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VerifyPhraseView extends StatefulWidget {
  const _VerifyPhraseView({
    required this.stepIndicator,
    required this.ensureScanner,
    required this.disposeScanner,
    required this.onSubmit,
  });

  final Widget stepIndicator;
  final MobileScannerController Function() ensureScanner;
  final Future<void> Function() disposeScanner;
  final Future<void> Function(String mnemonic) onSubmit;

  @override
  State<_VerifyPhraseView> createState() => _VerifyPhraseViewState();
}

class _VerifyPhraseViewState extends State<_VerifyPhraseView> {
  final _controller = TextEditingController();
  String? _error;
  bool _scanning = false;
  bool _scanHandled = false;

  @override
  void dispose() {
    unawaited(widget.disposeScanner());
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final normalized = PrismMnemonicField.normalize(_controller.text);
    if (normalized.isEmpty) {
      setState(() => _error = context.l10n.changePinMnemonicRequired);
      return;
    }
    if (!validateBip39Mnemonic(normalized)) {
      setState(() => _error = context.l10n.changePinMnemonicInvalid);
      return;
    }
    await widget.onSubmit(normalized);
  }

  Future<void> _stopScanning({String? error}) async {
    await widget.disposeScanner();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _error = error;
    });
  }

  void _startScanning() {
    setState(() {
      _error = null;
      _scanHandled = false;
      _scanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (_scanning) {
      return _buildScanView(context);
    }

    return SecureScope(
      allowAndroidScreenCapture: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.stepIndicator,
          const SizedBox(height: 16),
          Text(
            l10n.setupDeviceEnterMnemonicTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.setupDeviceEnterMnemonicSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          PrismMnemonicField(
            controller: _controller,
            hintText: l10n.changePinMnemonicHint,
            errorText: _error,
            autofocus: true,
            onSubmitted: (_) => unawaited(_submit()),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PrismButton(
                  label: l10n.setupDeviceMnemonicContinue,
                  onPressed: () => unawaited(_submit()),
                  tone: PrismButtonTone.filled,
                ),
              ),
              const SizedBox(width: 12),
              PrismButton(
                label: l10n.verifyBackupScanQrButton,
                onPressed: _startScanning,
                icon: AppIcons.qrCode,
                tone: PrismButtonTone.subtle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanView(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return SecureScope(
      allowAndroidScreenCapture: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PrismButton(
              label: l10n.back,
              onPressed: () => unawaited(_stopScanning()),
              icon: AppIcons.arrowBackIosNew,
              tone: PrismButtonTone.subtle,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(16),
            ),
            child: SizedBox(
              height: 280,
              child: MobileScanner(
                controller: widget.ensureScanner(),
                onDetect: (capture) async {
                  if (_scanHandled) return;
                  final raw = capture.barcodes.firstOrNull?.rawValue;
                  if (raw == null) return;
                  final normalized = PrismMnemonicField.normalize(raw);
                  _scanHandled = true;
                  if (validateBip39Mnemonic(normalized)) {
                    await widget.onSubmit(normalized);
                  } else {
                    await _stopScanning(error: l10n.verifyBackupScanInvalid);
                  }
                },
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _VerifyPinView extends ConsumerStatefulWidget {
  const _VerifyPinView({
    required this.mnemonic,
    required this.pin,
    required this.lockout,
    required this.onMatch,
    required this.onNoMatch,
    required this.onBack,
  });

  final String mnemonic;
  final PinBuffer pin;
  final PinLockoutState lockout;
  final void Function(String mnemonic) onMatch;
  final VoidCallback onNoMatch;
  final VoidCallback onBack;

  @override
  ConsumerState<_VerifyPinView> createState() => _VerifyPinViewState();
}

class _VerifyPinViewState extends ConsumerState<_VerifyPinView>
    with TickerProviderStateMixin {
  static const _pinLength = 6;

  bool _checking = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  late final AnimationController _dotController;
  late final Animation<double> _dotScaleAnim;
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
  }

  @override
  void dispose() {
    widget.pin.clear();
    _shakeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_checking || widget.lockout.isLockedOut) return;
    if (!widget.pin.appendDigit(digit)) return;
    setState(() {
      _lastFilledDotIndex = widget.pin.length - 1;
    });
    _dotController.forward(from: 0);
    if (widget.pin.isFull) {
      _onPinComplete();
    }
  }

  void _onBackspace() {
    if (widget.pin.isEmpty || _checking) return;
    setState(widget.pin.removeLast);
  }

  void _shake() {
    _shakeController.forward(from: 0);
    widget.pin.clear();
    setState(() => _lastFilledDotIndex = null);
  }

  Future<void> _pauseForFeedback() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _onPinComplete() async {
    if (widget.lockout.isLockedOut) {
      _shake();
      return;
    }
    setState(() => _checking = true);

    final pinCopy = PinBuffer(length: widget.pin.length)
      ..replaceWith(widget.pin);

    try {
      final result = await ref
          .read(syncHealthProvider.notifier)
          .verifyMnemonicPin(pin: pinCopy, mnemonic: widget.mnemonic);

      if (!mounted) return;

      switch (result) {
        case VerifyMnemonicPinMatch():
          await widget.lockout.clear();
          await _pauseForFeedback();
          if (!mounted) return;
          widget.onMatch(widget.mnemonic);
        case VerifyMnemonicPinNoMatch():
          await widget.lockout.recordFailure();
          if (!mounted) return;
          widget.pin.clear();
          setState(() => _checking = false);
          widget.onNoMatch();
        case VerifyMnemonicPinNeedsRewrap():
          if (mounted) {
            widget.pin.clear();
            ref
                .read(syncHealthProvider.notifier)
                .setState(SyncHealthState.needsRewrap);
            setState(() => _checking = false);
          }
        case VerifyMnemonicPinHandleUnavailable():
          if (mounted) {
            widget.pin.clear();
            setState(() => _checking = false);
          }
        case VerifyMnemonicPinError():
          // Infrastructure error — do NOT increment lockout. Show a toast
          // and stay on the PIN step so the user can retry.
          if (mounted) {
            widget.pin.clear();
            setState(() => _checking = false);
            PrismToast.error(
              context,
              message: context.l10n.syncSetupVerifyPinTransientError,
            );
          }
      }
    } finally {
      pinCopy.clear();
    }
  }

  String _subtitle(BuildContext context) {
    if (widget.lockout.isLockedOut) {
      return context.l10n.syncSetupVerifyPinLockedOut(
        widget.lockout.secondsRemaining,
      );
    }
    if (_checking) return context.l10n.verifyBackupValidating;
    return context.l10n.syncSetupVerifyPinSubtitle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final accentColor = theme.colorScheme.primary;

    return SecureScope(
      allowAndroidScreenCapture: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step indicator handled in parent
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: PrismButton(
              label: l10n.back,
              onPressed: widget.onBack,
              icon: AppIcons.arrowBackIosNew,
              tone: PrismButtonTone.subtle,
            ),
          ),
          const SizedBox(height: 24),
          Icon(AppIcons.lockOutline, color: accentColor, size: 40),
          const SizedBox(height: 16),
          Text(
            l10n.syncSetupVerifyPinTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _subtitle(context),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          // PIN dots with shake
          AnimatedBuilder(
            animation: _shakeAnimation,
            builder: (context, child) => Transform.translate(
              offset: Offset(_shakeAnimation.value, 0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < widget.pin.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: AnimatedBuilder(
                    animation: _dotScaleAnim,
                    builder: (context, child) => Transform.scale(
                      scale: i == _lastFilledDotIndex
                          ? _dotScaleAnim.value
                          : 1.0,
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
          const SizedBox(height: 32),
          if (!_checking)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 296),
                child: NumpadKeyboardListener(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  enabled: !_checking && !widget.lockout.isLockedOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: PrismSpinner(color: theme.colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRow(int row, ThemeData theme) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return PinNumpadCell(
          label: digit,
          onTap: () => _onDigit(digit),
          theme: theme,
        );
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      PinNumpadCell(label: '0', onTap: () => _onDigit('0'), theme: theme),
      PinNumpadCell(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        theme: theme,
      ),
    ];
  }
}
