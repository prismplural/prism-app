import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

enum _Step { verify, warn, newPassword, success }

/// Full-screen sheet for changing the sync encryption password.
///
/// Flow:
///   1. Verify current password (ffi.unlock)
///   2. Impact warning ("other devices will need to re-enter password")
///   3. Enter + confirm new password (SharingService.changePassword)
///   4. Success confirmation
class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  static Future<void> show(BuildContext context) {
    return PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, scrollController) =>
          ChangePasswordSheet(scrollController: scrollController),
    );
  }

  @override
  ConsumerState<ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  _Step _step = _Step.verify;
  bool _isLoading = false;

  // Step 1
  final _currentController = TextEditingController();
  bool _obscureCurrent = true;
  String? _currentError;

  // Stash verified password separately from the live text controller so that
  // step 3 always uses the value that was actually checked by ffi.unlock.
  String? _verifiedCurrentPassword;

  // Step 3
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _newFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
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

  // ── Step 1: verify current password ──────────────────────────────────────

  Future<void> _verifyCurrent() async {
    final password = _currentController.text;
    if (password.isEmpty) {
      setState(() => _currentError = 'Enter your current password.');
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
          _currentError =
              'Secret Key not found on this device. Re-pair to restore it.';
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
          _currentError = 'Sync engine not available.';
        });
        return;
      }

      try {
        await ffi.unlock(
          handle: handle,
          password: password,
          secretKey: secretKeyBytes,
        );
      } on Exception catch (e) {
        final msg = e.toString();
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
        if (!mounted) return;
        // "secretbox open failed — wrong password or corrupted data" is the
        // known error from the crypto layer on a bad password.
        final isWrongPassword = msg.contains('wrong password') ||
            msg.contains('secretbox open failed');
        setState(() {
          _isLoading = false;
          _currentError = isWrongPassword
              ? 'Incorrect password. Please try again.'
              : 'Verification failed: $msg';
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
        _verifiedCurrentPassword = password;
        secretKeyBytes = null; // ownership transferred to _secretKeyBytes
        _step = _Step.warn;
      });
    } catch (e) {
      secretKeyBytes?.fillRange(0, secretKeyBytes!.length, 0);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _currentError = 'An error occurred: $e';
      });
    }
  }

  // ── Step 3: change password ───────────────────────────────────────────────

  Future<void> _changePassword() async {
    // Guard: secretKey must be present from step 1. If somehow absent
    // (hot-reload, state restore), send the user back to verify.
    if (_secretKeyBytes == null || _verifiedCurrentPassword == null) {
      setState(() {
        _step = _Step.verify;
        _currentError = 'Session expired — please verify again.';
      });
      return;
    }

    final newPw = _newController.text;
    final confirmPw = _confirmController.text;

    String? newErr;
    String? confirmErr;

    if (newPw.isEmpty) {
      newErr = 'Enter a new password.';
    } else if (newPw == _verifiedCurrentPassword) {
      newErr = 'Your sync password is already set to that.';
    } else if (newPw != confirmPw) {
      confirmErr = "Passwords don't match.";
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
          _submitError = 'Sync engine not available.';
        });
        return;
      }

      // Pass the secretKey directly — flutter_rust_bridge copies into Rust.
      // We zero _secretKeyBytes in the finally block regardless of outcome.
      await service.changePassword(
        oldPassword: _verifiedCurrentPassword!,
        newPassword: newPw,
        secretKey: _secretKeyBytes!,
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
          ? 'Another device recently changed settings \u2014 please try again.'
          : 'Failed to change password: $msg';

      setState(() {
        _isLoading = false;
        _submitError = errorText;
      });
    } finally {
      _zeroSecretKey();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    switch (_step) {
      case _Step.verify:
        body = _buildVerifyStep(theme);
      case _Step.warn:
        body = _buildWarnStep(theme);
      case _Step.newPassword:
        body = _buildNewPasswordStep(theme);
      case _Step.success:
        body = _buildSuccessStep(theme);
    }

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(title: 'Change Password'),
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
          'Enter your current sync password to continue.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PrismTextField(
          controller: _currentController,
          labelText: 'Current password',
          obscureText: _obscureCurrent,
          autofocus: true,
          enabled: !_isLoading,
          onSubmitted: (_) => _verifyCurrent(),
          errorText: _currentError,
          suffix: PrismFieldIconButton(
            icon: _obscureCurrent ? AppIcons.visibilityOff : AppIcons.visibility,
            tooltip: _obscureCurrent ? 'Show password' : 'Hide password',
            onPressed: () =>
                setState(() => _obscureCurrent = !_obscureCurrent),
          ),
        ),
        const SizedBox(height: 20),
        PrismButton(
          label: 'Continue',
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
          'Your other devices will need to enter the new password when they next open Prism.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        PrismButton(
          label: 'Change Password',
          tone: PrismButtonTone.filled,
          onPressed: () => setState(() => _step = _Step.newPassword),
        ),
        const SizedBox(height: 12),
        PrismButton(
          label: 'Cancel',
          tone: PrismButtonTone.subtle,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'Choose a new sync password.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PrismTextField(
          controller: _newController,
          labelText: 'New password',
          obscureText: _obscureNew,
          autofocus: true,
          enabled: !_isLoading,
          focusNode: _newFocusNode,
          onSubmitted: (_) => _confirmFocusNode.requestFocus(),
          errorText: _newError,
          suffix: PrismFieldIconButton(
            icon: _obscureNew ? AppIcons.visibilityOff : AppIcons.visibility,
            tooltip: _obscureNew ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => _obscureNew = !_obscureNew),
          ),
        ),
        const SizedBox(height: 16),
        PrismTextField(
          controller: _confirmController,
          labelText: 'Confirm new password',
          obscureText: _obscureConfirm,
          enabled: !_isLoading,
          focusNode: _confirmFocusNode,
          onSubmitted: (_) => _changePassword(),
          errorText: _confirmError,
          suffix: PrismFieldIconButton(
            icon:
                _obscureConfirm ? AppIcons.visibilityOff : AppIcons.visibility,
            tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
            onPressed: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
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
          label: 'Change Password',
          onPressed: _changePassword,
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
          'Password changed',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your sync password has been updated on this device.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        PrismButton(
          label: 'Done',
          tone: PrismButtonTone.filled,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
