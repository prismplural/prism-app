import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum _Step { verify, warn, newPin, success }

/// Full-screen sheet for changing the sync encryption PIN.
///
/// Flow:
///   1. Verify current PIN (ffi.unlock)
///   2. Impact warning ("other devices will need to re-enter PIN")
///   3. Enter + confirm new PIN (SharingService.changePassword)
///   4. Success confirmation
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
  _Step _step = _Step.verify;
  bool _isLoading = false;

  // Step 1
  final _currentController = TextEditingController();
  String? _currentError;

  // Stash verified PIN separately from the live text controller so that
  // step 3 always uses the value that was actually checked by ffi.unlock.
  String? _verifiedCurrentPin;

  // Step 3
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _newFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  String? _newError;
  String? _confirmError;
  String? _submitError;

  // Held between steps 1 and 3, zeroed on completion.
  List<int>? _secretKeyBytes;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _newFocusNode.dispose();
    _confirmFocusNode.dispose();
    _zeroSecretKey();
    super.dispose();
  }

  void _zeroSecretKey() {
    final bytes = _secretKeyBytes;
    if (bytes != null) {
      bytes.fillRange(0, bytes.length, 0);
      _secretKeyBytes = null;
    }
  }

  // ── Step 1: verify current PIN ─────────────────────────────────────────────

  Future<void> _verifyCurrent() async {
    final pin = _currentController.text;
    if (pin.isEmpty) {
      setState(() => _currentError = context.l10n.settingsChangePinCurrentRequired);
      return;
    }

    setState(() {
      _isLoading = true;
      _currentError = null;
    });

    List<int>? secretKeyBytes;
    try {
      final mnemonicB64 =
          await secureStorage.read(key: 'prism_sync.mnemonic');
      if (!mounted) return;
      if (mnemonicB64 == null) {
        setState(() {
          _isLoading = false;
          _currentError = context.l10n.settingsChangePinNoSecretKey;
        });
        return;
      }

      String mnemonic;
      try {
        mnemonic = utf8.decode(base64Decode(mnemonicB64));
      } catch (_) {
        mnemonic = mnemonicB64;
      }

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
      } on Exception catch (e) {
        final msg = e.toString();
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        if (!mounted) return;
        final isWrongPin = msg.contains('wrong password') ||
            msg.contains('secretbox open failed');
        setState(() {
          _isLoading = false;
          _currentError = isWrongPin
              ? context.l10n.settingsChangePinIncorrect
              : context.l10n.settingsChangePinVerifyFailed(msg);
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

  // ── Step 3: change PIN ─────────────────────────────────────────────────────

  Future<void> _changePin() async {
    // Guard: secretKey must be present from step 1. If somehow absent
    // (hot-reload, state restore), send the user back to verify.
    if (_secretKeyBytes == null || _verifiedCurrentPin == null) {
      setState(() {
        _step = _Step.verify;
        _currentError = context.l10n.settingsChangePinSessionExpired;
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
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    switch (_step) {
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
