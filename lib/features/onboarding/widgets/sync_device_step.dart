import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_progress_view.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
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
  final _relayUrlController = TextEditingController();
  final _registrationTokenController = TextEditingController(
    text: BuildInfo.betaRegistrationToken,
  );
  bool _showRelayConfiguration = false;
  String? _relayUrlError;

  @override
  void dispose() {
    _relayUrlController.dispose();
    _registrationTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairingState = ref.watch(devicePairingProvider);

    Widget child;
    switch (pairingState.step) {
      case PairingStep.enterUrl:
        child = _JoinPromptView(
          key: const ValueKey('join-prompt'),
          onBack: widget.onBack,
          showRelayConfiguration: _showRelayConfiguration,
          relayUrlController: _relayUrlController,
          registrationTokenController: _registrationTokenController,
          relayUrlError: _relayUrlError,
          onToggleRelayConfiguration: () {
            setState(() {
              _showRelayConfiguration = !_showRelayConfiguration;
              if (!_showRelayConfiguration) {
                _relayUrlError = null;
              }
            });
          },
          onRequestToJoin: _requestToJoin,
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
      case PairingStep.enterPin:
        child = _PairingPinCapture(
          key: const ValueKey('pin'),
          onBack: () => ref.read(devicePairingProvider.notifier).reset(),
          onPinEntered: (pin) => ref
              .read(devicePairingProvider.notifier)
              .completeJoinerWithPin(pin),
        );
      case PairingStep.connecting:
        child = const SyncProgressView(key: ValueKey('connecting'));
      case PairingStep.success:
        child = OnboardingDataReadyView(
          key: const ValueKey('success'),
          title: context.l10n.onboardingSyncWelcomeBackTitle,
          description: context.l10n.onboardingSyncWelcomeBackDescription,
          summaryLabel: context.l10n.onboardingDataReadySyncedData,
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
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(10),
                    ),
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
                          context.l10n.onboardingSyncDataStillSyncing,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.amber.withValues(alpha: 0.9),
                              ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          actionLabel: context.l10n.onboardingGetStarted,
          onAction: () async {
            await ref.read(devicePairingProvider.notifier).completeOnboarding();
            widget.onComplete();
          },
        );
      case PairingStep.error:
        child = _ErrorView(
          key: const ValueKey('error'),
          message:
              pairingState.errorMessage ??
              context.l10n.onboardingSyncUnknownError,
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

  Future<void> _requestToJoin() async {
    final relayUrl = _relayUrlController.text.trim();
    if (_showRelayConfiguration && relayUrl.isNotEmpty) {
      if (!relayUrl.startsWith('https://')) {
        setState(() => _relayUrlError = context.l10n.syncSetupRelayUrlError);
        return;
      }
    }

    if (_relayUrlError != null) {
      setState(() => _relayUrlError = null);
    }

    // Always pass the typed token (not gated on the "self-hosted" toggle).
    // The field is pre-filled with BuildInfo.betaRegistrationToken for beta
    // builds, and the joiner can override a stale bundle token from the
    // initiator (see service.rs::complete_bootstrap_join).
    final typedToken = _registrationTokenController.text.trim();
    await ref
        .read(devicePairingProvider.notifier)
        .generateRequest(
          relayUrl: relayUrl.isEmpty ? null : relayUrl,
          registrationToken: typedToken.isEmpty ? null : typedToken,
        );
  }
}

/// Simple prompt to request joining a sync group.
class _JoinPromptView extends StatelessWidget {
  const _JoinPromptView({
    super.key,
    required this.onBack,
    required this.onRequestToJoin,
    required this.showRelayConfiguration,
    required this.relayUrlController,
    required this.registrationTokenController,
    required this.relayUrlError,
    required this.onToggleRelayConfiguration,
  });

  final VoidCallback onBack;
  final VoidCallback onRequestToJoin;
  final bool showRelayConfiguration;
  final TextEditingController relayUrlController;
  final TextEditingController registrationTokenController;
  final String? relayUrlError;
  final VoidCallback onToggleRelayConfiguration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(label: context.l10n.back, onTap: onBack),
          ),
          const SizedBox(height: 20),
          Icon(AppIcons.devices, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          Text(
            context.l10n.onboardingSyncJoinYourGroup,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.warmWhite,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.onboardingSyncJoinDescription,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Semantics(
            button: true,
            label: context.l10n.syncSetupSelfHosted,
            child: InkWell(
              onTap: onToggleRelayConfiguration,
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      showRelayConfiguration
                          ? AppIcons.expandLess
                          : AppIcons.expandMore,
                      size: 18,
                      color: AppColors.warmWhite.withValues(alpha: 0.72),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.syncSetupSelfHosted,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.warmWhite.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showRelayConfiguration) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warmWhite.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(18),
                ),
                border: Border.all(
                  color: AppColors.warmWhite.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrismTextField(
                    controller: relayUrlController,
                    labelText: context.l10n.syncSetupRelayUrlLabel,
                    hintText: AppConstants.defaultRelayUrl,
                    keyboardType: TextInputType.url,
                    errorText: relayUrlError,
                  ),
                  const SizedBox(height: 12),
                  PrismTextField(
                    controller: registrationTokenController,
                    labelText: context.l10n.syncSetupRegistrationToken,
                    hintText: context.l10n.syncSetupRegistrationTokenHint,
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.syncSetupRegistrationTokenHelp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warmWhite.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          _ActionButton(
            label: context.l10n.onboardingSyncRequestToJoin,
            color: Colors.purple,
            onPressed: onRequestToJoin,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.onboardingSyncRequestToJoinHint,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.warmWhite.withValues(alpha: 0.5),
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
            child: _BackLink(label: context.l10n.back, onTap: onBack),
          ),
          const SizedBox(height: 20),
          Icon(AppIcons.qrCode, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          Text(
            context.l10n.onboardingSyncShowToExistingDevice,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.warmWhite,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.onboardingSyncScanInstructions,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warmWhite,
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(16),
                ),
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
              const PrismSpinner(color: AppColors.warmWhite, size: 16),
              const SizedBox(width: 12),
              Text(
                context.l10n.onboardingSyncWaitingForScan,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.warmWhite.withValues(alpha: 0.7),
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
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PrismSpinner(
              color: AppColors.warmWhite,
              size: 52,
              dotCount: 8,
              duration: Duration(milliseconds: 3000),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.onboardingSyncWaitingForVerification,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.warmWhite,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.onboardingSyncWaitingForVerificationSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warmWhite.withValues(alpha: 0.6),
              ),
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
    final theme = Theme.of(context);
    final words = sasWords.split(' ');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(AppIcons.shieldOutlined, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          Text(
            context.l10n.onboardingSyncVerifySecurityCode,
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppColors.warmWhite,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.onboardingSyncVerifyDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.warmWhite.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(16),
              ),
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.warmWhite.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _ActionButton(
            label: context.l10n.onboardingSyncTheyMatch,
            color: Colors.purple,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 8),
          _ActionButton(
            label: context.l10n.onboardingSyncTheyDontMatch,
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

/// PIN entry widget for the pairing flow that captures the 6-digit pin
/// and forwards it to the pairing notifier.
class _PairingPinCapture extends StatefulWidget {
  const _PairingPinCapture({
    super.key,
    required this.onPinEntered,
    required this.onBack,
  });

  final void Function(String pin) onPinEntered;
  final VoidCallback onBack;

  @override
  State<_PairingPinCapture> createState() => _PairingPinCaptureState();
}

class _PairingPinCaptureState extends State<_PairingPinCapture>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

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
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    setState(() => _pin += digit);
    if (_pin.length == _pinLength) {
      widget.onPinEntered(_pin);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(label: context.l10n.back, onTap: widget.onBack),
          ),
          const SizedBox(height: 24),
          Icon(AppIcons.lockOutline, color: AppColors.warmWhite, size: 48),
          const SizedBox(height: 16),
          Text(
            context.l10n.onboardingSyncEnterPassword,
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppColors.warmWhite,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.onboardingSyncEnterPasswordDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.warmWhite.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // PIN dot indicators
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      // Intentionally circular even in angular mode — progress indicator convention.
                      shape: BoxShape.circle,
                      color: filled
                          ? AppColors.warmWhite
                          : AppColors.warmWhite.withValues(alpha: 0.2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 32),
          // Numpad
          for (var row = 0; row < 4; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _buildRow(row),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _buildRow(int row) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return _NumpadButton(label: digit, onTap: () => _onDigit(digit));
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      _NumpadButton(label: '0', onTap: () => _onDigit('0')),
      _NumpadButton(icon: AppIcons.backspaceOutlined, onTap: _onBackspace),
    ];
  }
}

class _NumpadButton extends StatelessWidget {
  const _NumpadButton({this.label, this.icon, required this.onTap});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          // Intentionally circular even in angular mode — progress indicator convention.
          shape: BoxShape.circle,
          color: Color(0x22FFFFFF),
        ),
        child: label != null
            ? Text(
                label!,
                style: const TextStyle(
                  color: AppColors.warmWhite,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, size: 24, color: AppColors.warmWhite),
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
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(AppIcons.errorOutline, color: Colors.redAccent, size: 56),
          const SizedBox(height: 16),
          Text(
            'Pairing failed',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.warmWhite,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.warmWhite.withValues(alpha: 0.75),
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
    final theme = Theme.of(context);
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.warmWhite.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
