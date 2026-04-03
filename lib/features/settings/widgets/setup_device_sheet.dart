import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

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

class _SetupDeviceSheetContentState
    extends ConsumerState<_SetupDeviceSheetContent> {
  // State for the "Scan Joiner's QR" flow
  bool _scanningJoinerQr = false;
  bool _joinerScanned = false;
  bool _approvingRequest = false;
  String? _approvalQrData; // base64-encoded approval response QR
  String? _joinerError;
  MobileScannerController? _joinerScannerController;

  MobileScannerController _ensureJoinerScanner() {
    return _joinerScannerController ??= MobileScannerController();
  }

  @override
  void dispose() {
    _joinerScannerController?.dispose();
    super.dispose();
  }

  void _reset() {
    _joinerScannerController?.dispose();
    _joinerScannerController = null;
    setState(() {
      _scanningJoinerQr = false;
      _joinerScanned = false;
      _approvingRequest = false;
      _approvalQrData = null;
      _joinerError = null;
    });
  }

  Future<void> _approveJoinerRequest(Uint8List requestBytes) async {
    setState(() {
      _approvingRequest = true;
      _joinerError = null;
    });

    try {
      final jsonString = await ffi.approvePairingRequest(
        handle: widget.handle,
        requestBytes: requestBytes,
      );
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final rawBytes = (json['qr_payload'] as List<dynamic>).cast<int>();

      // Drain store after approval (may mutate epoch / credentials)
      await drainRustStore(widget.handle);

      // Upload ephemeral snapshot for the joiner device
      try {
        await ffi.uploadPairingSnapshot(
          handle: widget.handle,
          ttlSecs: BigInt.from(86400),
        );
      } catch (e) {
        debugPrint('[PAIRING] Snapshot upload failed (non-fatal): $e');
      }

      if (!mounted) return;
      setState(() {
        _approvalQrData = base64Encode(rawBytes);
        _approvingRequest = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joinerError = e.toString();
        _approvingRequest = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }

  Widget _buildContent() {
    // If we have an approval QR result, show it (scan-joiner flow complete)
    if (_approvalQrData != null) {
      return _ApprovalResponseView(
        qrData: _approvalQrData!,
        onDone: _reset,
      );
    }

    // If we're scanning a joiner's QR
    if (_scanningJoinerQr) {
      return _JoinerQrScannerView(
        ensureScanner: _ensureJoinerScanner,
        scanned: _joinerScanned,
        approving: _approvingRequest,
        error: _joinerError,
        onBack: _reset,
        onScanned: (bytes) {
          setState(() => _joinerScanned = true);
          _approveJoinerRequest(bytes);
        },
      );
    }

    // Default: show the scan joiner prompt
    return _ScanJoinerPrompt(
      onStartScan: () => setState(() => _scanningJoinerQr = true),
    );
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
          icon: Icons.qr_code_scanner,
          onPressed: onStartScan,
        ),
      ],
    );
  }
}

/// Camera view for scanning the joiner's PairingRequest QR.
class _JoinerQrScannerView extends StatelessWidget {
  const _JoinerQrScannerView({
    required this.ensureScanner,
    required this.scanned,
    required this.approving,
    required this.error,
    required this.onBack,
    required this.onScanned,
  });

  final MobileScannerController Function() ensureScanner;
  final bool scanned;
  final bool approving;
  final String? error;
  final VoidCallback onBack;
  final void Function(Uint8List bytes) onScanned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (approving) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Approving request...'),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new, size: 14),
            label: const Text('Back'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Scan the joiner's pairing request QR code.",
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
                      message: 'Invalid pairing request QR code.',
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

/// Shows the approval response QR for the joiner to scan.
class _ApprovalResponseView extends StatelessWidget {
  const _ApprovalResponseView({required this.qrData, required this.onDone});

  final String qrData;
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
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Request approved. Show this QR to the joining device.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warmWhite,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: qrData,
            size: 220,
            backgroundColor: AppColors.warmWhite,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'The joining device should scan this approval QR, then enter the sync password to finish pairing.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'An encrypted snapshot will be temporarily uploaded and '
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
        PrismButton(label: 'Done', icon: Icons.check, onPressed: onDone),
      ],
    );
  }
}
