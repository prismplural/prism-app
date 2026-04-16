import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum _Step { enterMnemonic, verify, warn, newPin, success }

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
  _Step _step = _Step.enterMnemonic;
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
  String? _mnemonic;

  // Step 2
  final _currentController = TextEditingController();
  String? _currentError;

  // Stash verified PIN separately from the live text controller so that
  // step 4 always uses the value that was actually checked by ffi.unlock.
  String? _verifiedCurrentPin;

  // Step 4
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _newFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  String? _newError;
  String? _confirmError;
  String? _submitError;

  // Held between steps 2 and 4, zeroed on completion.
  List<int>? _secretKeyBytes;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _newFocusNode.dispose();
    _confirmFocusNode.dispose();
    _zeroSecretKey();
    _mnemonic = null;
    super.dispose();
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
    final raw = _mnemonicController.text.trim();
    if (raw.isEmpty) {
      setState(() => _mnemonicError = context.l10n.changePinMnemonicRequired);
      return;
    }

    // Normalize whitespace (multiple spaces, newlines) to a single space.
    final normalized = raw
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .join(' ');

    setState(() {
      _isLoading = true;
      _mnemonicError = null;
    });

    // Validate the mnemonic by attempting to convert it to bytes.
    // This catches invalid words and bad checksums before we prompt for PIN.
    try {
      await ref.read(pairingCeremonyApiProvider).validateMnemonic(normalized);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _mnemonicError = context.l10n.changePinMnemonicInvalid;
      });
      return;
    }

    if (!mounted) return;
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
      setState(() =>
          _currentError = 'Too many attempts. Try again in ${secs}s.');
      return;
    }

    final pin = _currentController.text;
    if (pin.isEmpty) {
      setState(
          () => _currentError = context.l10n.settingsChangePinCurrentRequired);
      return;
    }

    final mnemonic = _mnemonic;
    if (mnemonic == null) {
      setState(() {
        _step = _Step.enterMnemonic;
        _mnemonicError = context.l10n.settingsChangePinSessionExpired;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _currentError = null;
    });

    List<int>? secretKeyBytes;
    try {
      secretKeyBytes = await ffi.mnemonicToBytes(mnemonic: mnemonic);
      if (!mounted) {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        return;
      }

      final handle = ref.read(prismSyncHandleProvider).value;
      if (handle == null) {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        setState(() {
          _isLoading = false;
          _currentError = context.l10n.settingsChangePinEngineUnavailable;
        });
        return;
      }

      try {
        await ffi.unlock(
          handle: handle,
          password: pin,
          secretKey: secretKeyBytes,
        );
      } on Exception {
        // Use a generic verification error so we don't disclose whether
        // the PIN or the mnemonic was wrong.
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        if (!mounted) return;
        _failedVerifyAttempts++;
        if (_failedVerifyAttempts >= _maxVerifyAttempts) {
          _verifyLockedUntil = DateTime.now()
              .add(const Duration(seconds: _verifyLockoutSeconds));
        }
        setState(() {
          _isLoading = false;
          _currentError = context.l10n.changePinVerificationFailed;
        });
        return;
      }

      if (!mounted) {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        return;
      }
      setState(() {
        _isLoading = false;
        _secretKeyBytes = secretKeyBytes;
        _verifiedCurrentPin = pin;
        secretKeyBytes = null; // ownership transferred to _secretKeyBytes
        _step = _Step.warn;
      });
    } catch (e) {
      secretKeyBytes?.fillRange(0, secretKeyBytes!.length, 0);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _currentError = context.l10n.settingsChangePinGenericError(e.toString());
      });
    }
  }

  // ── Step 4: change PIN ────────────────────────────────────────────────────

  Future<void> _changePin() async {
    // Guard: secretKey must be present from step 2. If somehow absent
    // (hot-reload, state restore), send the user back to re-enter mnemonic.
    if (_secretKeyBytes == null || _verifiedCurrentPin == null) {
      setState(() {
        _step = _Step.enterMnemonic;
        _mnemonicError = context.l10n.settingsChangePinSessionExpired;
      });
      return;
    }

    final newPin = _newController.text;
    final confirmPin = _confirmController.text;

    String? newErr;
    String? confirmErr;

    if (newPin.isEmpty) {
      newErr = context.l10n.settingsChangePinNewRequired;
    } else if (newPin.length != 6) {
      // SyncPinSheet requires exactly 6 digits — a different length would make
      // the sync password impossible to enter via the unlock sheet.
      newErr = context.l10n.settingsChangePinInvalidLength;
    } else if (newPin == _verifiedCurrentPin) {
      newErr = context.l10n.settingsChangePinSamePin;
    } else if (newPin != confirmPin) {
      confirmErr = context.l10n.settingsChangePinMismatch;
    }

    if (newErr != null || confirmErr != null) {
      setState(() {
        _newError = newErr;
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

    try {
      final service = ref.read(sharingServiceProvider);
      if (service == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _submitError = context.l10n.settingsChangePinEngineUnavailable;
        });
        return;
      }

      // Pass the secretKey directly — flutter_rust_bridge copies into Rust.
      // We zero _secretKeyBytes in the finally block regardless of outcome.
      await service.changePassword(
        oldPassword: _verifiedCurrentPin!,
        newPassword: newPin,
        secretKey: _secretKeyBytes!,
        db: ref.read(databaseProvider),
      );

      // Also update the local app-lock PIN hash so that the unlock PIN
      // stays in sync with the sync encryption PIN.
      final pinService = ref.read(pinLockServiceProvider);
      await pinService.storePin(newPin);

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
      _zeroSecretKey();
      _mnemonic = null;
    }
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

    return SafeArea(
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
        PrismTextField(
          controller: _mnemonicController,
          hintText: context.l10n.changePinMnemonicHint,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.none,
          autofocus: true,
          enabled: !_isLoading,
          minLines: 3,
          maxLines: 5,
          errorText: _mnemonicError,
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
        Text(
          context.l10n.settingsChangePinVerifyBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PrismTextField(
          controller: _currentController,
          labelText: context.l10n.settingsChangePinCurrentLabel,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          enabled: !_isLoading,
          onSubmitted: (_) => _verifyCurrent(),
          errorText: _currentError,
        ),
        const SizedBox(height: 20),
        PrismButton(
          label: context.l10n.settingsChangePinContinue,
          onPressed: _verifyCurrent,
          isLoading: _isLoading,
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
          onPressed: () => setState(() => _step = _Step.newPin),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          context.l10n.settingsChangePinNewBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PrismTextField(
          controller: _newController,
          labelText: context.l10n.settingsChangePinNewLabel,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          enabled: !_isLoading,
          focusNode: _newFocusNode,
          onSubmitted: (_) => _confirmFocusNode.requestFocus(),
          errorText: _newError,
        ),
        const SizedBox(height: 16),
        PrismTextField(
          controller: _confirmController,
          labelText: context.l10n.settingsChangePinConfirmLabel,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !_isLoading,
          focusNode: _confirmFocusNode,
          onSubmitted: (_) => _changePin(),
          errorText: _confirmError,
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
        const SizedBox(height: 20),
        PrismButton(
          label: context.l10n.settingsChangePinAction,
          onPressed: _changePin,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildSuccessStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(
          AppIcons.checkCircleOutline,
          size: 56,
          color: Colors.green,
        ),
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
