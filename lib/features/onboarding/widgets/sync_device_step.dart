import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';

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
        );
      case PairingStep.waitingForSas:
        child = const _WaitingForSasView(key: ValueKey('waiting-sas'));
      case PairingStep.showingSas:
        child = _SasVerificationView(
          key: const ValueKey('sas-verify'),
          sasWords: pairingState.sasWords!,
          sasDecimal: pairingState.sasDecimal!,
          onConfirm: () =>
              ref.read(devicePairingProvider.notifier).confirmSas(),
          onReject: () => ref.read(devicePairingProvider.notifier).reset(),
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
                        AppIcons.sync,
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

    return SecureScope(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: child,
      ),
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
          Icon(AppIcons.devices, color: AppColors.warmWhite, size: 48),
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

/// Displays the joiner's rendezvous token QR. The initiator scans this,
/// then both sides derive SAS words automatically.
class _ShowingRequestView extends StatelessWidget {
  const _ShowingRequestView({
    super.key,
    required this.qrPayload,
    required this.onBack,
  });

  final List<int> qrPayload;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // Encode token bytes as base64 for the QR code display
    final qrData = base64Encode(qrPayload);

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
          Icon(AppIcons.qrCode, color: AppColors.warmWhite, size: 48),
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
            'On your existing device, open "Set Up Another Device" and scan this code.',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.warmWhite,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Waiting for other device to scan...',
                style: TextStyle(
                  color: AppColors.warmWhite.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Shown while the joiner is waiting for the initiator to scan and derive SAS.
class _WaitingForSasView extends StatelessWidget {
  const _WaitingForSasView({super.key});

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
              'Waiting for security verification...',
              style: TextStyle(
                color: AppColors.warmWhite,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'The other device is connecting. Security codes will appear shortly.',
              style: TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows SAS words for the joiner to verify with the initiator.
class _SasVerificationView extends StatelessWidget {
  const _SasVerificationView({
    super.key,
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
    final words = sasWords.split(' ');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(AppIcons.shieldOutlined, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Verify Security Code',
            style: TextStyle(
              color: AppColors.warmWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Confirm these words match the ones shown on your existing device.',
            style: TextStyle(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.warmWhite.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.warmWhite.withValues(alpha: 0.2),
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
                          style: const TextStyle(
                            color: AppColors.warmWhite,
                            fontSize: 24,
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
                  style: TextStyle(
                    color: AppColors.warmWhite.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _ActionButton(
            label: 'They Match',
            color: Colors.purple,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 8),
          _ActionButton(
            label: 'They Don\'t Match',
            color: Colors.redAccent,
            tone: PrismButtonTone.subtle,
            onPressed: onReject,
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
          Icon(AppIcons.lockOutline, color: AppColors.warmWhite, size: 48),
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
            child: PrismTextField(
              controller: _passwordController,
              obscureText: _obscure,
              style: const TextStyle(color: AppColors.warmWhite),
              autofocus: true,
              onSubmitted: (_) => _connect(),
              hintText: 'Password',
              hintStyle: TextStyle(
                color: AppColors.warmWhite.withValues(alpha: 0.4),
              ),
              fieldStyle: PrismTextFieldStyle.borderless,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffix: PrismFieldIconButton(
                icon: _obscure ? AppIcons.visibilityOff : AppIcons.visibility,
                color: AppColors.warmWhite.withValues(alpha: 0.75),
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
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
    final state = ref.read(devicePairingProvider);
    // If we came through the relay ceremony (SAS verification), use the
    // ceremony completion path. Otherwise fall back to URL-based join.
    if (state.sasWords != null) {
      ref
          .read(devicePairingProvider.notifier)
          .completeJoinerWithPassword(password);
    } else {
      ref.read(devicePairingProvider.notifier).connect(password);
    }
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
          Icon(AppIcons.errorOutline, color: Colors.redAccent, size: 56),
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
              AppIcons.arrowBackIosNew,
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
