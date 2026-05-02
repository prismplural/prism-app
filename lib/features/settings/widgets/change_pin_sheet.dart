import 'dart:typed_data' as typed_data;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/crypto/bip39_validate.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/security/secret_bytes.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum _Step { enterMnemonic, verify, warn, newPin, success }

enum _NewPinPhase { newPin, confirmPin }

@visibleForTesting
typedef ChangePinMnemonicToBytes =
    Future<typed_data.Uint8List> Function({required List<int> mnemonic});

@visibleForTesting
typedef ChangePinUnlock =
    Future<void> Function({
      required ffi.PrismSyncHandle handle,
      required List<int> password,
      required List<int> secretKey,
    });

/// Full-screen sheet for changing the sync encryption PIN.
///
/// Flow:
///   1. Enter the BIP39 recovery phrase (not stored on this device).
///   2. Verify current PIN together with the mnemonic (ffi.unlock).
///   3. Impact warning ("other devices will need to re-enter PIN").
///   4. Enter + confirm new PIN (SharingService.changePassword).
///   5. Success confirmation.
class ChangePinSheet extends ConsumerStatefulWidget {
  const ChangePinSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @visibleForTesting
  static ChangePinMnemonicToBytes? debugMnemonicToBytesOverride;

  @visibleForTesting
  static ChangePinUnlock? debugUnlockOverride;

  static Future<void> show(BuildContext context) {
    return PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, scrollController) =>
          ChangePinSheet(scrollController: scrollController),
    );
  }

  @override
  ConsumerState<ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends ConsumerState<ChangePinSheet> {
  static const _pinLength = 6;

  _Step _step = _Step.enterMnemonic;
  _NewPinPhase _newPinPhase = _NewPinPhase.newPin;
  bool _isLoading = false;

  // Step 2 — brute-force throttle (widget-local; user must be authenticated
  // to reach settings, and Argon2id already imposes ~1-2s per attempt).
  int _failedVerifyAttempts = 0;
  DateTime? _verifyLockedUntil;
  static const _maxVerifyAttempts = 5;
  static const _verifyLockoutSeconds = 60;

  bool get _isVerifyLockedOut {
    if (_verifyLockedUntil == null) return false;
    if (DateTime.now().isAfter(_verifyLockedUntil!)) {
      _verifyLockedUntil = null;
      return false;
    }
    return true;
  }

  // Step 1 — recovery phrase entry
  final _mnemonicController = TextEditingController();
  String? _mnemonicError;
  // Dart Strings cannot be zeroed; this is retained only between recovery
  // phrase entry and current-PIN verification, then cleared.
  String? _mnemonic;

  // Step 2
  late final PinBuffer _currentPin = PinBuffer(length: _pinLength);
  String? _currentError;

  // Stash the verified PIN separately from the live entry buffer so that
  // step 4 always compares against the value that was checked by ffi.unlock.
  late final PinBuffer _verifiedCurrentPin = PinBuffer(length: _pinLength);

  // Step 4
  late final PinBuffer _newPin = PinBuffer(length: _pinLength);
  late final PinBuffer _confirmPin = PinBuffer(length: _pinLength);
  String? _newError;
  String? _confirmError;
  String? _submitError;

  // Held between steps 2 and 4, zeroed on completion.
  List<int>? _secretKeyBytes;

  @override
  void dispose() {
    _mnemonicController.clear();
    _mnemonicController.dispose();
    _clearPinBuffers();
    _zeroSecretKey();
    _mnemonic = null;
    super.dispose();
  }

  void _clearPinBuffers() {
    _currentPin.clear();
    _verifiedCurrentPin.clear();
    _newPin.clear();
    _confirmPin.clear();
  }

  void _zeroSecretKey() {
    final bytes = _secretKeyBytes;
    if (bytes != null) {
      bytes.fillRange(0, bytes.length, 0);
      _secretKeyBytes = null;
    }
  }

  // ── Step 1: mnemonic entry ────────────────────────────────────────────────

  Future<void> _submitMnemonic() async {
    final normalized = PrismMnemonicField.normalize(_mnemonicController.text);
    if (normalized.isEmpty) {
      setState(() => _mnemonicError = context.l10n.changePinMnemonicRequired);
      return;
    }

    setState(() {
      _isLoading = true;
      _mnemonicError = null;
    });

    if (!validateBip39Mnemonic(normalized)) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _mnemonicError = context.l10n.changePinMnemonicInvalid;
      });
      return;
    }

    if (!mounted) return;
    _mnemonicController.clear();
    setState(() {
      _isLoading = false;
      _mnemonic = normalized;
      _step = _Step.verify;
    });
  }

  // ── Step 2: verify current PIN ────────────────────────────────────────────

  Future<void> _verifyCurrent() async {
    if (_isVerifyLockedOut) {
      final secs = _verifyLockedUntil!
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 9999);
      setState(() {
        _currentPin.clear();
        _currentError = 'Too many attempts. Try again in ${secs}s.';
      });
      return;
    }

    if (_currentPin.isEmpty) {
      setState(
        () => _currentError = context.l10n.settingsChangePinCurrentRequired,
      );
      return;
    }

    _verifiedCurrentPin.replaceWith(_currentPin);
    typed_data.Uint8List? pinBytes = _currentPin.consumeBytesAndClear();
    final mnemonic = _mnemonic;
    if (mnemonic == null) {
      setState(() {
        _verifiedCurrentPin.clear();
        _step = _Step.enterMnemonic;
        _mnemonicError = context.l10n.settingsChangePinSessionExpired;
      });
      zeroBytesBestEffort(pinBytes);
      pinBytes = null;
      return;
    }

    setState(() {
      _isLoading = true;
      _currentError = null;
    });

    typed_data.Uint8List? mnemonicBytes;
    List<int>? secretKeyBytes;
    try {
      final mnemonicToBytes =
          ChangePinSheet.debugMnemonicToBytesOverride ?? ffi.mnemonicToBytes;
      try {
        mnemonicBytes = secretUtf8Bytes(mnemonic);
        secretKeyBytes = await mnemonicToBytes(mnemonic: mnemonicBytes);
      } finally {
        zeroBytesBestEffort(mnemonicBytes);
        mnemonicBytes = null;
      }
      if (!mounted) {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        return;
      }

      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        setState(() {
          _isLoading = false;
          _verifiedCurrentPin.clear();
          _currentError = context.l10n.settingsChangePinEngineUnavailable;
        });
        return;
      }

      try {
        final unlock = ChangePinSheet.debugUnlockOverride ?? ffi.unlock;
        await unlock(
          handle: handle,
          password: pinBytes,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        // Use a generic verification error so we don't disclose whether
        // the PIN or the mnemonic was wrong.
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        if (!mounted) return;
        _failedVerifyAttempts++;
        if (_failedVerifyAttempts >= _maxVerifyAttempts) {
          _verifyLockedUntil = DateTime.now().add(
            const Duration(seconds: _verifyLockoutSeconds),
          );
        }
        setState(() {
          _isLoading = false;
          _verifiedCurrentPin.clear();
          _currentError = context.l10n.changePinVerificationFailed;
        });
        return;
      }

      if (!mounted) {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        return;
      }
      _mnemonicController.clear();
      setState(() {
        _isLoading = false;
        _secretKeyBytes = secretKeyBytes;
        _mnemonic = null;
        secretKeyBytes = null; // ownership transferred to _secretKeyBytes
        _step = _Step.warn;
      });
    } catch (e) {
      final bytes = secretKeyBytes;
      bytes?.fillRange(0, bytes.length, 0);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _verifiedCurrentPin.clear();
        _currentError = context.l10n.settingsChangePinGenericError(
          e.toString(),
        );
      });
    } finally {
      zeroBytesBestEffort(pinBytes);
    }
  }

  // ── Step 4: change PIN ────────────────────────────────────────────────────

  Future<void> _changePin() async {
    // Guard: secretKey must be present from step 2. If somehow absent
    // (hot-reload, state restore), send the user back to re-enter mnemonic.
    if (_secretKeyBytes == null || !_verifiedCurrentPin.isFull) {
      setState(() {
        _clearPinBuffers();
        _step = _Step.enterMnemonic;
        _mnemonicError = context.l10n.settingsChangePinSessionExpired;
      });
      return;
    }

    String? newErr;
    String? confirmErr;

    if (_newPin.isEmpty) {
      newErr = context.l10n.settingsChangePinNewRequired;
    } else if (!_newPin.isFull) {
      // SyncPinSheet requires exactly 6 digits — a different length would make
      // the sync password impossible to enter via the unlock sheet.
      newErr = context.l10n.settingsChangePinInvalidLength;
    } else if (_newPin.contentEquals(_verifiedCurrentPin)) {
      newErr = context.l10n.settingsChangePinSamePin;
    } else if (!_confirmPin.isFull || !_newPin.contentEquals(_confirmPin)) {
      confirmErr = context.l10n.settingsChangePinMismatch;
    }

    if (newErr != null || confirmErr != null) {
      setState(() {
        _newPin.clear();
        _confirmPin.clear();
        _newPinPhase = _NewPinPhase.newPin;
        _newError = newErr ?? confirmErr;
        _confirmError = confirmErr;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _newError = null;
      _confirmError = null;
      _submitError = null;
    });

    final service = ref.read(sharingServiceProvider);
    if (service == null) {
      setState(() {
        _isLoading = false;
        _submitError = context.l10n.settingsChangePinEngineUnavailable;
        _newPin.clear();
        _confirmPin.clear();
        _newPinPhase = _NewPinPhase.newPin;
      });
      _verifiedCurrentPin.clear();
      _zeroSecretKey();
      return;
    }

    typed_data.Uint8List? newPinBytes;
    try {
      newPinBytes = _newPin.consumeBytesAndClear();
      _confirmPin.clear();
      await service.changePassword(
        newPassword: newPinBytes,
        secretKey: _secretKeyBytes!,
        db: ref.read(databaseProvider),
      );

      // Also update the local app-lock PIN hash so that the unlock PIN
      // stays in sync with the sync encryption PIN.
      final pinService = ref.read(pinLockServiceProvider);
      await pinService.storePinBytes(newPinBytes);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _Step.success;
      });
    } catch (e) {
      if (!mounted) return;

      final msg = e.toString();
      final errorText = msg.contains('generation')
          ? context.l10n.settingsChangePinGenerationConflict
          : context.l10n.settingsChangePinFailed(msg);

      setState(() {
        _isLoading = false;
        _submitError = errorText;
      });
    } finally {
      newPinBytes?.fillRange(0, newPinBytes.length, 0);
      _newPin.clear();
      _confirmPin.clear();
      _verifiedCurrentPin.clear();
      _zeroSecretKey();
      _mnemonicController.clear();
      _mnemonic = null;
    }
  }

  void _onCurrentDigit(String digit) {
    if (_isLoading) return;
    if (_isVerifyLockedOut) {
      _verifyCurrent();
      return;
    }
    if (!_currentPin.appendDigit(digit)) return;
    Haptics.light();
    setState(() => _currentError = null);
    if (_currentPin.isFull) {
      _verifyCurrent();
    }
  }

  void _onCurrentBackspace() {
    if (_currentPin.isEmpty || _isLoading) return;
    Haptics.selection();
    setState(_currentPin.removeLast);
  }

  void _onNewPinDigit(String digit) {
    if (_isLoading) return;
    final activePin = _newPinPhase == _NewPinPhase.newPin
        ? _newPin
        : _confirmPin;
    if (!activePin.appendDigit(digit)) return;
    Haptics.light();
    setState(() {
      _newError = null;
      _confirmError = null;
      _submitError = null;
    });

    if (!activePin.isFull) return;

    if (_newPinPhase == _NewPinPhase.newPin) {
      setState(() {
        _newPinPhase = _NewPinPhase.confirmPin;
        _confirmPin.clear();
      });
      return;
    }

    _changePin();
  }

  void _onNewPinBackspace() {
    if (_isLoading) return;
    final activePin = _newPinPhase == _NewPinPhase.newPin
        ? _newPin
        : _confirmPin;
    if (activePin.isEmpty) return;
    Haptics.selection();
    setState(activePin.removeLast);
  }

  void _returnToNewPinEntry() {
    if (_isLoading) return;
    setState(() {
      _newPin.clear();
      _confirmPin.clear();
      _newPinPhase = _NewPinPhase.newPin;
      _newError = null;
      _confirmError = null;
      _submitError = null;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    switch (_step) {
      case _Step.enterMnemonic:
        body = _buildMnemonicStep(theme);
      case _Step.verify:
        body = _buildVerifyStep(theme);
      case _Step.warn:
        body = _buildWarnStep(theme);
      case _Step.newPin:
        body = _buildNewPinStep(theme);
      case _Step.success:
        body = _buildSuccessStep(theme);
    }

    return SecureScope(
      child: SafeArea(
        child: Column(
          children: [
            PrismSheetTopBar(title: context.l10n.settingsChangePinTitle),
            Expanded(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMnemonicStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          context.l10n.changePinEnterMnemonicTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.changePinEnterMnemonicSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PrismMnemonicField(
          controller: _mnemonicController,
          hintText: context.l10n.changePinMnemonicHint,
          autofocus: true,
          enabled: !_isLoading,
          errorText: _mnemonicError,
          onSubmitted: (_) => _submitMnemonic(),
        ),
        const SizedBox(height: 20),
        PrismButton(
          label: context.l10n.changePinVerifyButton,
          onPressed: _submitMnemonic,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildVerifyStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Icon(AppIcons.lockOutline, size: 40, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          context.l10n.settingsChangePinCurrentLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _currentError ?? context.l10n.settingsChangePinVerifyBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _currentError == null
                ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                : theme.colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _PinDots(
          length: _pinLength,
          filledLength: _currentPin.length,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        _buildPinPad(
          onDigit: _onCurrentDigit,
          onBackspace: _onCurrentBackspace,
        ),
      ],
    );
  }

  Widget _buildWarnStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Icon(
          AppIcons.devicesOther,
          size: 48,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.settingsChangePinWarnBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        PrismButton(
          label: context.l10n.settingsChangePinAction,
          tone: PrismButtonTone.filled,
          onPressed: () => setState(() {
            _newPin.clear();
            _confirmPin.clear();
            _newPinPhase = _NewPinPhase.newPin;
            _newError = null;
            _confirmError = null;
            _submitError = null;
            _step = _Step.newPin;
          }),
        ),
        const SizedBox(height: 12),
        PrismButton(
          label: context.l10n.cancel,
          tone: PrismButtonTone.subtle,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildNewPinStep(ThemeData theme) {
    final isConfirming = _newPinPhase == _NewPinPhase.confirmPin;
    final activeLength = isConfirming ? _confirmPin.length : _newPin.length;
    final errorText = isConfirming ? _confirmError : _newError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isConfirming)
          Align(
            alignment: Alignment.centerLeft,
            child: PrismButton(
              label: context.l10n.back,
              icon: AppIcons.arrowBackIosNew,
              tone: PrismButtonTone.subtle,
              density: PrismControlDensity.compact,
              enabled: !_isLoading,
              onPressed: _returnToNewPinEntry,
            ),
          ),
        const SizedBox(height: 8),
        Icon(AppIcons.lockOutline, size: 40, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          isConfirming
              ? context.l10n.settingsChangePinConfirmLabel
              : context.l10n.settingsChangePinNewLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          errorText ?? context.l10n.settingsChangePinNewBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: errorText == null
                ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                : theme.colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _PinDots(
          length: _pinLength,
          filledLength: activeLength,
          color: theme.colorScheme.primary,
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 12),
          Text(
            _submitError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        _buildPinPad(onDigit: _onNewPinDigit, onBackspace: _onNewPinBackspace),
      ],
    );
  }

  Widget _buildPinPad({
    required void Function(String digit) onDigit,
    required VoidCallback onBackspace,
  }) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var row = 0; row < 4; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _buildPinPadRow(row, onDigit, onBackspace),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildPinPadRow(
    int row,
    void Function(String digit) onDigit,
    VoidCallback onBackspace,
  ) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return PinNumpadButton(
          label: digit,
          onTap: () => onDigit(digit),
          size: 64,
        );
      });
    }
    return [
      const SizedBox(width: 64, height: 64),
      PinNumpadButton(label: '0', onTap: () => onDigit('0'), size: 64),
      PinNumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: onBackspace,
        size: 64,
        semanticLabel: context.l10n.delete,
      ),
    ];
  }

  Widget _buildSuccessStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(AppIcons.checkCircleOutline, size: 56, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          context.l10n.settingsChangePinSuccessTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.settingsChangePinSuccessBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        PrismButton(
          label: context.l10n.done,
          tone: PrismButtonTone.filled,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filledLength,
    required this.color,
  });

  final int length;
  final int filledLength;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final filled = i < filledLength;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : color.withValues(alpha: 0.15),
            ),
          ),
        );
      }),
    );
  }
}
