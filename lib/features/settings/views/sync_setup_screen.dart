import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/features/settings/providers/sync_setup_provider.dart';
import 'package:prism_plurality/features/settings/widgets/secret_key_reveal_content.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class SyncSetupScreen extends ConsumerStatefulWidget {
  const SyncSetupScreen({super.key});

  @override
  ConsumerState<SyncSetupScreen> createState() => _SyncSetupScreenState();
}

class _SyncSetupScreenState extends ConsumerState<SyncSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _relayUrlController = TextEditingController();
  final _registrationTokenController = TextEditingController();
  bool _showRelayField = false;
  bool _hasSavedKey = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _passwordError;
  String? _relayUrlError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(syncSetupProvider);
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _relayUrlController.dispose();
    _registrationTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setupState = ref.watch(syncSetupProvider);

    final title = switch (setupState.step) {
      SyncSetupStep.intro => 'Set Up Sync',
      SyncSetupStep.password => 'Create Password',
      SyncSetupStep.secretKey => 'Your Secret Key',
    };

    return PopScope(
      canPop: setupState.step == SyncSetupStep.intro && !setupState.isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !setupState.isProcessing) {
          ref.read(syncSetupProvider.notifier).goBack();
        }
      },
      child: PrismPageScaffold(
        topBar: PrismTopBar(title: title, showBackButton: true),
        bodyPadding: EdgeInsets.zero,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (setupState.step) {
            SyncSetupStep.intro => _IntroStep(
              key: const ValueKey('intro'),
              showRelayField: _showRelayField,
              relayUrlController: _relayUrlController,
              registrationTokenController: _registrationTokenController,
              relayUrlError: _relayUrlError,
              onToggleRelay: () =>
                  setState(() => _showRelayField = !_showRelayField),
              onContinue: () {
                if (_showRelayField) {
                  final url = _relayUrlController.text.trim();
                  if (url.isNotEmpty) {
                    if (!url.startsWith('https://')) {
                      setState(
                        () => _relayUrlError =
                            'Relay URL must start with https://',
                      );
                      return;
                    }
                    setState(() => _relayUrlError = null);
                    ref.read(syncSetupProvider.notifier).setRelayUrl(url);
                  }
                  final token = _registrationTokenController.text.trim();
                  ref.read(syncSetupProvider.notifier).setRegistrationToken(
                    token.isNotEmpty ? token : null,
                  );
                }
                ref.read(syncSetupProvider.notifier).proceedToPassword();
              },
            ),
            SyncSetupStep.password => _PasswordStep(
              key: const ValueKey('password'),
              passwordController: _passwordController,
              confirmPasswordController: _confirmPasswordController,
              obscurePassword: _obscurePassword,
              obscureConfirmPassword: _obscureConfirmPassword,
              error: _passwordError ?? setupState.error,
              onTogglePasswordVisibility: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              onToggleConfirmPasswordVisibility: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
              onContinue: _validateAndProceedToSecretKey,
            ),
            SyncSetupStep.secretKey => _SecretKeyStep(
              key: const ValueKey('secretKey'),
              mnemonic: setupState.mnemonic!,
              hasSaved: _hasSavedKey,
              isProcessing: setupState.isProcessing,
              currentProgress: setupState.currentProgress,
              error: setupState.error,
              onHasSavedChanged: (v) => setState(() => _hasSavedKey = v),
              onComplete: _completeSetup,
            ),
          },
        ),
      ),
    );
  }

  Future<void> _validateAndProceedToSecretKey() async {
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (password.length < 8) {
      setState(() => _passwordError = 'Password must be at least 8 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _passwordError = 'Passwords do not match');
      return;
    }

    setState(() => _passwordError = null);
    await ref.read(syncSetupProvider.notifier).proceedToSecretKey(password);
  }

  Future<void> _completeSetup() async {
    final success = await ref.read(syncSetupProvider.notifier).complete();
    if (success && mounted) {
      context.pop();
    }
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({
    super.key,
    required this.showRelayField,
    required this.relayUrlController,
    required this.registrationTokenController,
    required this.relayUrlError,
    required this.onToggleRelay,
    required this.onContinue,
  });

  final bool showRelayField;
  final TextEditingController relayUrlController;
  final TextEditingController registrationTokenController;
  final String? relayUrlError;
  final VoidCallback onToggleRelay;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 32),
          PhosphorIcon(AppIcons.duotoneSync, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            'Keep your data in sync across all your devices.',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Everything is end-to-end encrypted — the server never sees '
            'your data. You\'ll create a password and receive a recovery '
            'key to keep safe.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          GestureDetector(
            onTap: onToggleRelay,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  showRelayField ? AppIcons.expandLess : AppIcons.expandMore,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Self-hosted relay?',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (showRelayField) ...[
            const SizedBox(height: 12),
            PrismTextField(
              controller: relayUrlController,
              labelText: 'Relay URL',
              hintText: AppConstants.defaultRelayUrl,
              keyboardType: TextInputType.url,
            ),
            if (relayUrlError != null) ...[
              const SizedBox(height: 8),
              Text(
                relayUrlError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            PrismTextField(
              controller: registrationTokenController,
              labelText: 'Registration token',
              hintText: 'Optional',
              obscureText: true,
            ),
            const SizedBox(height: 4),
            Text(
              'Required if your relay has registration gating enabled.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 32),
          PrismButton(
            label: 'Set up sync',
            icon: AppIcons.arrowForward,
            tone: PrismButtonTone.filled,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    super.key,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.error,
    required this.onTogglePasswordVisibility,
    required this.onToggleConfirmPasswordVisibility,
    required this.onContinue,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final String? error;
  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback onToggleConfirmPasswordVisibility;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 32),
          Text(
            'Create a password to protect your encryption keys.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ll need this password each time you set up a new device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          PrismTextField(
            controller: passwordController,
            labelText: 'Password',
            obscureText: obscurePassword,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.next,
            suffix: IconButton(
              onPressed: onTogglePasswordVisibility,
              icon: Icon(
                obscurePassword ? AppIcons.visibilityOff : AppIcons.visibility,
              ),
            ),
          ),
          const SizedBox(height: 16),
          PrismTextField(
            controller: confirmPasswordController,
            labelText: 'Confirm password',
            obscureText: obscureConfirmPassword,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            suffix: IconButton(
              onPressed: onToggleConfirmPasswordVisibility,
              icon: Icon(
                obscureConfirmPassword
                    ? AppIcons.visibilityOff
                    : AppIcons.visibility,
              ),
            ),
            onSubmitted: (_) => onContinue(),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 32),
          PrismButton(
            label: 'Continue',
            icon: AppIcons.arrowForward,
            tone: PrismButtonTone.filled,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _SecretKeyStep extends StatelessWidget {
  const _SecretKeyStep({
    super.key,
    required this.mnemonic,
    required this.hasSaved,
    required this.isProcessing,
    required this.currentProgress,
    required this.error,
    required this.onHasSavedChanged,
    required this.onComplete,
  });

  final String mnemonic;
  final bool hasSaved;
  final bool isProcessing;
  final SyncSetupProgress? currentProgress;
  final String? error;
  final ValueChanged<bool> onHasSavedChanged;
  final VoidCallback onComplete;

  String? get _progressLabel => switch (currentProgress) {
    SyncSetupProgress.creatingGroup => 'Creating sync group...',
    SyncSetupProgress.configuringEngine => 'Configuring encryption...',
    SyncSetupProgress.cachingKeys => 'Securing keys...',
    SyncSetupProgress.bootstrappingData => 'Uploading your data...',
    SyncSetupProgress.syncing => 'Syncing...',
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SecretKeyRevealContent(
            mnemonic: mnemonic,
            hasSaved: hasSaved,
            onHasSavedChanged: onHasSavedChanged,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          PrismButton(
            label: 'Complete setup',
            icon: AppIcons.check,
            tone: PrismButtonTone.filled,
            enabled: hasSaved,
            isLoading: isProcessing,
            onPressed: onComplete,
          ),
          if (isProcessing && _progressLabel != null) ...[
            const SizedBox(height: 16),
            Text(
              _progressLabel!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
