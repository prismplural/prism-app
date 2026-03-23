import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
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
        child = _EnterUrlView(
          key: const ValueKey('enter-url'),
          onBack: widget.onBack,
          onUrlSubmitted: (url) =>
              ref.read(devicePairingProvider.notifier).setUrl(url),
        );
      case PairingStep.enterPassword:
        child = _PasswordView(
          key: const ValueKey('password'),
          onBack: () => ref.read(devicePairingProvider.notifier).reset(),
        );
      case PairingStep.connecting:
        child = const _ConnectingView(key: ValueKey('connecting'));
      case PairingStep.success:
        child = _WelcomeBackView(
          key: const ValueKey('success'),
          counts: pairingState.counts,
          onGetStarted: () async {
            await ref
                .read(devicePairingProvider.notifier)
                .completeOnboarding();
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

class _EnterUrlView extends StatefulWidget {
  const _EnterUrlView({
    super.key,
    required this.onBack,
    required this.onUrlSubmitted,
  });

  final VoidCallback onBack;
  final void Function(String) onUrlSubmitted;

  @override
  State<_EnterUrlView> createState() => _EnterUrlViewState();
}

class _EnterUrlViewState extends State<_EnterUrlView> {
  bool _manualEntry = false;
  final _urlController = TextEditingController();
  bool _scanned = false;
  MobileScannerController? _scannerController;

  MobileScannerController _ensureScanner() {
    return _scannerController ??= MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submitUrl(String url) {
    if (url.trim().isEmpty) {
      PrismToast.show(context, message: 'Please enter the invite URL.');
      return;
    }
    widget.onUrlSubmitted(url.trim());
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
          const SizedBox(height: 20),
          const Icon(Icons.qr_code_2, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Join your sync group',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'On your existing device, open "Set Up Another Device" and share the invite. Then scan or paste it here.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          if (_manualEntry) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _urlController,
                maxLines: 4,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'Paste invite URL here...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ActionButton(
              label: 'Join',
              color: Colors.purple,
              onPressed: () => _submitUrl(_urlController.text),
            ),
          ] else ...[
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
                    setState(() => _scanned = true);
                    _submitUrl(raw);
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              if (!_manualEntry) {
                _scannerController?.stop();
              }
              setState(() {
                _manualEntry = !_manualEntry;
                _scanned = false;
                if (!_manualEntry) {
                  // Dispose old controller and create fresh one when switching back
                  _scannerController?.dispose();
                  _scannerController = null;
                }
              });
            },
            child: Text(
              _manualEntry ? 'Scan QR code instead' : 'Enter URL manually',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
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
          const Icon(Icons.lock_outline, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Enter your password',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your sync password to finish enrolling this device.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _passwordController,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white),
              autofocus: true,
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white.withValues(alpha: 0.5),
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
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 24),
            Text(
              'Pairing and syncing...',
              style: TextStyle(
                color: Colors.white,
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

class _WelcomeBackView extends StatelessWidget {
  const _WelcomeBackView({
    super.key,
    required this.counts,
    required this.onGetStarted,
  });

  final SyncCounts? counts;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Welcome Back!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your device has been paired and your data is ready.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          if (counts != null) ...[
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Synced data',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CountRow(label: 'Members', count: counts!.members),
                  _CountRow(
                    label: 'Fronting sessions',
                    count: counts!.frontingSessions,
                  ),
                  _CountRow(
                    label: 'Conversations',
                    count: counts!.conversations,
                  ),
                  _CountRow(label: 'Messages', count: counts!.messages),
                  _CountRow(label: 'Habits', count: counts!.habits),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          _ActionButton(
            label: 'Get Started',
            color: Colors.green,
            onPressed: onGetStarted,
          ),
          const SizedBox(height: 16),
        ],
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
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
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

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
              color: Colors.white.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
