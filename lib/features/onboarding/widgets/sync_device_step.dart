import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class SyncDeviceStep extends ConsumerStatefulWidget {
  const SyncDeviceStep({
    super.key,
    required this.onBack,
    required this.onComplete,
  });

  final VoidCallback onBack;
  final VoidCallback onComplete;

  @override
  ConsumerState<SyncDeviceStep> createState() => _SyncDeviceStepState();
}

class _SyncDeviceStepState extends ConsumerState<SyncDeviceStep> {
  @override
  Widget build(BuildContext context) {
    final pairingState = ref.watch(devicePairingProvider);

    Widget child;
    switch (pairingState.step) {
      case PairingStep.enterUrl:
        child = _JoinPromptView(
          key: const ValueKey('join-prompt'),
          onBack: widget.onBack,
          onRequestToJoin: () =>
              ref.read(devicePairingProvider.notifier).generateRequest(),
        );
      case PairingStep.showingRequest:
        child = _ShowingRequestView(
          key: const ValueKey('showing-request'),
          qrPayload: pairingState.requestQrPayload!,
          onBack: () => ref.read(devicePairingProvider.notifier).reset(),
          onApprovalScanned: (bytes) => ref
              .read(devicePairingProvider.notifier)
              .setApprovalQrBytes(bytes),
        );
      case PairingStep.enterPassword:
        child = _PasswordView(
          key: const ValueKey('password'),
          onBack: () => ref.read(devicePairingProvider.notifier).reset(),
        );
      case PairingStep.connecting:
        child = const _ConnectingView(key: ValueKey('connecting'));
      case PairingStep.success:
        child = OnboardingDataReadyView(
          key: const ValueKey('success'),
          title: 'Welcome Back!',
          description: 'Your device has been paired and your data is ready.',
          summaryLabel: 'Synced data',
          counts: pairingState.counts != null
              ? OnboardingDataCounts(
                  members: pairingState.counts!.members,
                  frontingSessions: pairingState.counts!.frontingSessions,
                  conversations: pairingState.counts!.conversations,
                  messages: pairingState.counts!.messages,
                  habits: pairingState.counts!.habits,
                )
              : null,
          notice: pairingState.syncIncomplete
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sync,
                        size: 18,
                        color: Colors.amber.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Some data is still syncing and will appear shortly.',
                          style: TextStyle(
                            color: Colors.amber.withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          actionLabel: 'Get Started',
          onAction: () async {
            await ref.read(devicePairingProvider.notifier).completeOnboarding();
            widget.onComplete();
          },
        );
      case PairingStep.error:
        child = _ErrorView(
          key: const ValueKey('error'),
          message: pairingState.errorMessage ?? 'An unknown error occurred.',
          onTryAgain: () => ref.read(devicePairingProvider.notifier).reset(),
        );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}

/// Simple prompt to request joining a sync group.
class _JoinPromptView extends StatelessWidget {
  const _JoinPromptView({
    super.key,
    required this.onBack,
    required this.onRequestToJoin,
  });

  final VoidCallback onBack;
  final VoidCallback onRequestToJoin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(label: 'Back', onTap: onBack),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.devices, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Join your sync group',
            style: TextStyle(
              color: AppColors.warmWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Create a pairing request on this device and have an existing device approve it.',
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _ActionButton(
            label: 'Request to Join',
            color: Colors.purple,
            onPressed: onRequestToJoin,
          ),
          const SizedBox(height: 8),
          Text(
            'Show a QR code for your existing device to scan and approve.',
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Displays the joiner's PairingRequest QR and provides a button to scan
/// the approval response from the existing device.
class _ShowingRequestView extends StatefulWidget {
  const _ShowingRequestView({
    super.key,
    required this.qrPayload,
    required this.onBack,
    required this.onApprovalScanned,
  });

  final List<int> qrPayload;
  final VoidCallback onBack;
  final void Function(List<int> bytes) onApprovalScanned;

  @override
  State<_ShowingRequestView> createState() => _ShowingRequestViewState();
}

class _ShowingRequestViewState extends State<_ShowingRequestView> {
  bool _scanning = false;
  bool _scanned = false;
  MobileScannerController? _scannerController;

  MobileScannerController _ensureScanner() {
    return _scannerController ??= MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return _buildApprovalScanner();
    }

    // Encode QR payload as base64 for the QR code display
    final qrData = base64Encode(widget.qrPayload);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(label: 'Back', onTap: widget.onBack),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.qr_code, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Show this to your existing device',
            style: TextStyle(
              color: AppColors.warmWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'On your existing device, open "Set Up Another Device" and choose "Scan Joiner\'s QR". Then scan this code.',
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
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
          ),
          const SizedBox(height: 24),
          _ActionButton(
            label: 'Scan Approval',
            color: Colors.purple,
            onPressed: () => setState(() => _scanning = true),
          ),
          const SizedBox(height: 8),
          Text(
            'After your existing device approves, it will show an approval QR. Tap above to scan it.',
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildApprovalScanner() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(
              label: 'Back',
              onTap: () {
                _scannerController?.stop();
                _scannerController?.dispose();
                _scannerController = null;
                setState(() {
                  _scanning = false;
                  _scanned = false;
                });
              },
            ),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.qr_code_scanner, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Scan approval QR',
            style: TextStyle(
              color: AppColors.warmWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Scan the approval QR code shown on your existing device.',
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 280,
              child: MobileScanner(
                controller: _ensureScanner(),
                onDetect: (capture) {
                  if (_scanned) return;
                  final barcode = capture.barcodes.firstOrNull;
                  final raw = barcode?.rawValue;
                  if (raw == null) return;
                  // Decode the base64 approval QR back to bytes
                  try {
                    final bytes = base64Decode(raw);
                    setState(() => _scanned = true);
                    widget.onApprovalScanned(bytes);
                  } catch (_) {
                    PrismToast.show(
                      context,
                      message: 'Invalid approval QR code.',
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PasswordView extends ConsumerStatefulWidget {
  const _PasswordView({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_PasswordView> createState() => _PasswordViewState();
}

class _PasswordViewState extends ConsumerState<_PasswordView> {
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(label: 'Back', onTap: widget.onBack),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.lock_outline, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Enter your password',
            style: TextStyle(
              color: AppColors.warmWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your sync password to finish enrolling this device.',
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: AppColors.warmWhite.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _passwordController,
              obscureText: _obscure,
              style: const TextStyle(color: AppColors.warmWhite),
              autofocus: true,
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(
                  color: AppColors.warmWhite.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.warmWhite.withValues(alpha: 0.5),
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _ActionButton(
            label: 'Finish Pairing',
            color: Colors.purple,
            onPressed: _connect,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _connect() {
    final password = _passwordController.text;
    if (password.isEmpty) {
      PrismToast.show(context, message: 'Please enter your password.');
      return;
    }
    ref.read(devicePairingProvider.notifier).connect(password);
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.warmWhite),
            SizedBox(height: 24),
            Text(
              'Pairing and syncing...',
              style: TextStyle(
                color: AppColors.warmWhite,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'This may take a moment while the device is enrolled.',
              style: TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.message,
    required this.onTryAgain,
  });

  final String message;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Pairing failed',
            style: TextStyle(
              color: AppColors.warmWhite,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.75),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _ActionButton(
            label: 'Try Again',
            color: Colors.redAccent,
            tone: PrismButtonTone.destructive,
            onPressed: onTryAgain,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.tone = PrismButtonTone.filled,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;
  final PrismButtonTone tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: PrismButton(
        onPressed: onPressed,
        label: label,
        tone: tone,
        expanded: true,
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_back_ios_new,
              size: 14,
              color: AppColors.warmWhite.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.warmWhite.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
