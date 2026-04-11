import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

class SetupDeviceSheet {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Sync engine not available');
      return;
    }

    final relayUrl =
        await ref.read(relayUrlProvider.future) ?? AppConstants.defaultRelayUrl;

    if (!context.mounted) return;

    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, sc) => _SetupDeviceSheetContent(
        handle: handle,
        relayUrl: relayUrl,
        scrollController: sc,
      ),
    );
  }
}

class _SetupDeviceSheetContent extends ConsumerStatefulWidget {
  const _SetupDeviceSheetContent({
    required this.handle,
    required this.relayUrl,
    this.scrollController,
  });

  final ffi.PrismSyncHandle handle;
  final String relayUrl;
  final ScrollController? scrollController;

  @override
  ConsumerState<_SetupDeviceSheetContent> createState() =>
      _SetupDeviceSheetContentState();
}

enum _InitiatorStep {
  prompt,
  scanning,
  connecting,
  sasVerification,
  passwordEntry,
  completing,
  done,
  error,
}

class _SetupDeviceSheetContentState
    extends ConsumerState<_SetupDeviceSheetContent> {
  _InitiatorStep _step = _InitiatorStep.prompt;
  bool _joinerScanned = false;
  String? _sasWords;
  String? _sasDecimal;
  String? _error;
  MobileScannerController? _joinerScannerController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  MobileScannerController _ensureJoinerScanner() {
    return _joinerScannerController ??= MobileScannerController();
  }

  @override
  void dispose() {
    _joinerScannerController?.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _reset() {
    _joinerScannerController?.dispose();
    _joinerScannerController = null;
    _passwordController.clear();
    setState(() {
      _step = _InitiatorStep.prompt;
      _joinerScanned = false;
      _sasWords = null;
      _sasDecimal = null;
      _error = null;
      _obscurePassword = true;
    });
  }

  Future<void> _startInitiatorCeremony(Uint8List tokenBytes) async {
    setState(() {
      _step = _InitiatorStep.connecting;
      _error = null;
    });

    try {
      final pairingApi = ref.read(pairingCeremonyApiProvider);
      final jsonString = await pairingApi.startInitiatorCeremony(
        handle: widget.handle,
        tokenBytes: tokenBytes,
      );
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final sasWords = json['sas_words'] as String;
      final sasDecimal = json['sas_decimal'] as String;

      if (!mounted) return;
      setState(() {
        _sasWords = sasWords;
        _sasDecimal = sasDecimal;
        _step = _InitiatorStep.sasVerification;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _InitiatorStep.error;
      });
    }
  }

  Future<void> _completeInitiator() async {
    final password = _passwordController.text;
    if (password.trim().isEmpty) {
      setState(() {
        _error = 'Password cannot be empty.';
        _step = _InitiatorStep.error;
      });
      return;
    }

    setState(() {
      _step = _InitiatorStep.completing;
      _error = null;
    });

    try {
      // Upload the ephemeral snapshot BEFORE sending credentials. The joiner
      // can't register or try to bootstrap until it receives the credentials
      // from completeInitiatorCeremony, so uploading first guarantees the
      // snapshot is on the relay by the time the joiner's bootstrap_from_snapshot
      // runs. Otherwise the joiner races ahead, finds no snapshot, and ends
      // up with zero records (and silently fails "Get Started" because the
      // completeOnboarding guard requires at least one member to exist).
      //
      // The snapshot is encrypted with the current (pre-rekey) epoch key,
      // which matches what the credential bundle will ship to the joiner.
      //
      // Fatal on failure: if the snapshot doesn't land on the relay we must
      // NOT release credentials. Otherwise the joiner registers, finds no
      // snapshot, falls through to an empty syncNow (first-device data is
      // still local-only), and ends up with zero records — the exact bug
      // this fix is meant to prevent. Let the error propagate to the outer
      // catch so the initiator flow shows an error state instead of a
      // confusing "synced but empty" success.
      await ffi.uploadPairingSnapshot(
        handle: widget.handle,
        ttlSecs: BigInt.from(86400),
      );

      final pairingApi = ref.read(pairingCeremonyApiProvider);
      await pairingApi.completeInitiatorCeremony(
        handle: widget.handle,
        password: password,
      );

      // Drain store after completion (may mutate epoch / credentials)
      await drainRustStore(widget.handle);

      if (!mounted) return;
      setState(() {
        _step = _InitiatorStep.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _InitiatorStep.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecureScope(
      child: Column(
        children: [
          const PrismSheetTopBar(title: 'Set Up Another Device'),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return switch (_step) {
      _InitiatorStep.prompt => _ScanJoinerPrompt(
        onStartScan: () => setState(() => _step = _InitiatorStep.scanning),
      ),
      _InitiatorStep.scanning => _JoinerQrScannerView(
        ensureScanner: _ensureJoinerScanner,
        scanned: _joinerScanned,
        error: _error,
        onBack: _reset,
        onScanned: (bytes) {
          setState(() => _joinerScanned = true);
          _startInitiatorCeremony(bytes);
        },
      ),
      _InitiatorStep.connecting => const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to joiner...'),
            ],
          ),
        ),
      ),
      _InitiatorStep.sasVerification => _SasVerificationView(
        sasWords: _sasWords!,
        sasDecimal: _sasDecimal!,
        onConfirm: () => setState(() => _step = _InitiatorStep.passwordEntry),
        onReject: _reset,
      ),
      _InitiatorStep.passwordEntry => _InitiatorPasswordView(
        controller: _passwordController,
        obscure: _obscurePassword,
        onToggleObscure: () =>
            setState(() => _obscurePassword = !_obscurePassword),
        onSubmit: _completeInitiator,
        onBack: () => setState(() => _step = _InitiatorStep.sasVerification),
      ),
      _InitiatorStep.completing => const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Completing pairing...'),
            ],
          ),
        ),
      ),
      _InitiatorStep.done => _InitiatorDoneView(onDone: _reset),
      _InitiatorStep.error => _InitiatorErrorView(
        message: _error ?? 'An unknown error occurred.',
        onTryAgain: _reset,
      ),
    };
  }
}

/// Prompt for the "Scan Joiner's QR" flow before the camera opens.
class _ScanJoinerPrompt extends StatelessWidget {
  const _ScanJoinerPrompt({required this.onStartScan});

  final VoidCallback onStartScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The new device can generate a pairing request QR code. '
          'Scan it here to approve the device and share your sync credentials.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        PrismButton(
          label: "Scan Joiner's QR",
          icon: AppIcons.qrCodeScanner,
          onPressed: onStartScan,
        ),
      ],
    );
  }
}

/// Camera view for scanning the joiner's rendezvous token QR.
class _JoinerQrScannerView extends StatelessWidget {
  const _JoinerQrScannerView({
    required this.ensureScanner,
    required this.scanned,
    required this.error,
    required this.onBack,
    required this.onScanned,
  });

  final MobileScannerController Function() ensureScanner;
  final bool scanned;
  final String? error;
  final VoidCallback onBack;
  final void Function(Uint8List bytes) onScanned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: 'Back',
            onPressed: onBack,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Scan the joiner's pairing QR code.",
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: MobileScanner(
              controller: ensureScanner(),
              onDetect: (capture) {
                if (scanned) return;
                final barcode = capture.barcodes.firstOrNull;
                final raw = barcode?.rawValue;
                if (raw == null) return;
                try {
                  final bytes = Uint8List.fromList(base64Decode(raw));
                  onScanned(bytes);
                } catch (_) {
                  if (context.mounted) {
                    PrismToast.show(
                      context,
                      message: 'Invalid pairing QR code.',
                    );
                  }
                }
              },
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Shows SAS words for the initiator to verify with the joiner.
class _SasVerificationView extends StatelessWidget {
  const _SasVerificationView({
    required this.sasWords,
    required this.sasDecimal,
    required this.onConfirm,
    required this.onReject,
  });

  final String sasWords;
  final String sasDecimal;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = sasWords.split(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          AppIcons.shieldOutlined,
          color: theme.colorScheme.primary,
          size: 40,
        ),
        const SizedBox(height: 16),
        Text(
          'Verify Security Code',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Confirm these words match on the joining device.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: words
                    .map(
                      (word) => Text(
                        word,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                sasDecimal,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          label: 'They Match',
          icon: AppIcons.checkCircle,
          onPressed: onConfirm,
        ),
        const SizedBox(height: 8),
        PrismButton(
          label: 'They Don\'t Match',
          icon: AppIcons.close,
          tone: PrismButtonTone.subtle,
          onPressed: onReject,
        ),
      ],
    );
  }
}

/// Password entry for the initiator after SAS verification.
class _InitiatorPasswordView extends StatelessWidget {
  const _InitiatorPasswordView({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: 'Back',
            onPressed: onBack,
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 16),
        Icon(AppIcons.lockOutline, color: theme.colorScheme.primary, size: 40),
        const SizedBox(height: 16),
        Text(
          'Enter Sync Password',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your sync password to complete the pairing.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          obscureText: obscure,
          autofocus: true,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: 'Password',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? AppIcons.visibilityOff : AppIcons.visibility,
              ),
              onPressed: onToggleObscure,
              tooltip: obscure ? 'Show password' : 'Hide password',
            ),
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(
          label: 'Complete Pairing',
          icon: AppIcons.check,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

/// Success view after initiator completes pairing.
class _InitiatorDoneView extends StatelessWidget {
  const _InitiatorDoneView({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(AppIcons.checkCircle, color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pairing complete! The new device is now syncing.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                AppIcons.infoOutline,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'An encrypted snapshot has been uploaded and will be '
                  'automatically deleted after the new device connects '
                  '(or after 24 hours).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrismButton(label: 'Done', icon: AppIcons.check, onPressed: onDone),
      ],
    );
  }
}

/// Error view for the initiator flow.
class _InitiatorErrorView extends StatelessWidget {
  const _InitiatorErrorView({required this.message, required this.onTryAgain});

  final String message;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(AppIcons.errorOutline, color: theme.colorScheme.error, size: 40),
        const SizedBox(height: 16),
        Text(
          'Pairing Failed',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PrismButton(
          label: 'Try Again',
          icon: AppIcons.refresh,
          tone: PrismButtonTone.subtle,
          onPressed: onTryAgain,
        ),
      ],
    );
  }
}
