import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/features/settings/providers/sync_setup_provider.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_mnemonic_field.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class SyncSetupScreen extends ConsumerStatefulWidget {
  const SyncSetupScreen({super.key});

  @override
  ConsumerState<SyncSetupScreen> createState() => _SyncSetupScreenState();
}

class _SyncSetupScreenState extends ConsumerState<SyncSetupScreen> {
  final _relayUrlController = TextEditingController();
  final _registrationTokenController = TextEditingController();
  final _mnemonicController = TextEditingController();
  String? _pin;
  bool _showRelayField = false;
  String? _relayUrlError;

  @override
  void initState() {
    super.initState();
    // Pre-fill the registration-token field with any value baked into the
    // binary at build time (see BuildInfo.betaRegistrationToken). Empty when
    // unset, which leaves the field blank for open-source / self-host builds.
    _registrationTokenController.text = BuildInfo.betaRegistrationToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(syncSetupProvider);
    });
  }

  @override
  void dispose() {
    _relayUrlController.dispose();
    _registrationTokenController.dispose();
    _mnemonicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setupState = ref.watch(syncSetupProvider);

    final title = switch (setupState.step) {
      SyncSetupStep.intro => context.l10n.syncSetupIntroTitle,
      SyncSetupStep.enterPhrase =>
        _pin == null
            ? context.l10n.syncPinSheetTitle
            : 'Recovery Phrase',
    };

    return PopScope(
      canPop:
          setupState.step == SyncSetupStep.intro && !setupState.isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !setupState.isProcessing) {
          _goBack(setupState);
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
                            context.l10n.syncSetupRelayUrlError,
                      );
                      return;
                    }
                    setState(() => _relayUrlError = null);
                    ref.read(syncSetupProvider.notifier).setRelayUrl(url);
                  }
                  final token = _registrationTokenController.text.trim();
                  ref
                      .read(syncSetupProvider.notifier)
                      .setRegistrationToken(token.isNotEmpty ? token : null);
                }
                ref.read(syncSetupProvider.notifier).proceedToEnterPhrase();
              },
            ),
            SyncSetupStep.enterPhrase => _EnterPhraseStep(
              key: const ValueKey('enterPhrase'),
              mnemonicController: _mnemonicController,
              pin: _pin,
              isProcessing: setupState.isProcessing,
              currentProgress: setupState.currentProgress,
              error: setupState.error,
              onPinEntered: (pin) => setState(() => _pin = pin),
              onSubmit: _submitPhrase,
            ),
          },
        ),
      ),
    );
  }

  void _goBack(SyncSetupState setupState) {
    if (setupState.step == SyncSetupStep.enterPhrase && _pin != null) {
      setState(() => _pin = null);
      return;
    }
    if (setupState.step == SyncSetupStep.enterPhrase) {
      _mnemonicController.clear();
    }
    ref.read(syncSetupProvider.notifier).goBack();
  }

  Future<void> _submitPhrase() async {
    final pin = _pin;
    if (pin == null) return;

    final success = await ref
        .read(syncSetupProvider.notifier)
        .submitPhrase(_mnemonicController.text, pin);
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
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 32),
          PhosphorIcon(
            AppIcons.duotoneSync,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.syncSetupIntroHeadline,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.syncSetupIntroBody,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Semantics(
            button: true,
            label: 'Toggle relay configuration',
            child: GestureDetector(
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
                    context.l10n.syncSetupSelfHosted,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showRelayField) ...[
            const SizedBox(height: 12),
            PrismTextField(
              controller: relayUrlController,
              labelText: context.l10n.syncSetupRelayUrlLabel,
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
              labelText: context.l10n.syncSetupRegistrationToken,
              hintText: context.l10n.syncSetupRegistrationTokenHint,
              obscureText: true,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.syncSetupRegistrationTokenHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 32),
          PrismButton(
            label: context.l10n.syncSetupButton,
            icon: AppIcons.arrowForward,
            tone: PrismButtonTone.filled,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _EnterPhraseStep extends StatefulWidget {
  const _EnterPhraseStep({
    super.key,
    required this.mnemonicController,
    required this.pin,
    required this.isProcessing,
    required this.currentProgress,
    required this.error,
    required this.onPinEntered,
    required this.onSubmit,
  });

  final TextEditingController mnemonicController;
  final String? pin;
  final bool isProcessing;
  final SyncSetupProgress? currentProgress;
  final String? error;
  final ValueChanged<String> onPinEntered;
  final VoidCallback onSubmit;

  @override
  State<_EnterPhraseStep> createState() => _EnterPhraseStepState();
}

class _EnterPhraseStepState extends State<_EnterPhraseStep> {
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    widget.mnemonicController.addListener(_onMnemonicChanged);
  }

  @override
  void dispose() {
    widget.mnemonicController.removeListener(_onMnemonicChanged);
    super.dispose();
  }

  void _onMnemonicChanged() {
    final normalized = PrismMnemonicField.normalize(
      widget.mnemonicController.text,
    );
    final words = normalized.split(' ');
    final valid =
        words.length == 12 &&
        words.every((w) => w.isNotEmpty);
    if (valid != _canSubmit) {
      setState(() => _canSubmit = valid);
    }
  }

  String? _progressLabel(BuildContext context) => switch (widget.currentProgress) {
    SyncSetupProgress.creatingGroup =>
      context.l10n.syncSetupProgressCreatingGroup,
    SyncSetupProgress.configuringEngine =>
      context.l10n.syncSetupProgressConfiguringEngine,
    SyncSetupProgress.cachingKeys => context.l10n.syncSetupProgressCachingKeys,
    SyncSetupProgress.bootstrappingData =>
      context.l10n.syncSetupProgressBootstrapping,
    SyncSetupProgress.syncing => context.l10n.syncSetupProgressSyncing,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pin = widget.pin;

    if (pin == null) {
      return SafeArea(
        top: false,
        child: PinInputScreen(
          key: const ValueKey('sync-setup-pin'),
          mode: PinInputMode.unlock,
          embedded: true,
          allowBiometric: false,
          onPinEntered: widget.onPinEntered,
          onSuccess: () {},
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter your recovery phrase',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter the 12 words you wrote down when you first set up Prism.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  PrismMnemonicField(
                    controller: widget.mnemonicController,
                    errorText: widget.error,
                    enabled: !widget.isProcessing,
                    autofocus: true,
                    onSubmitted: _canSubmit && !widget.isProcessing
                        ? (_) => widget.onSubmit()
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Lost your recovery phrase? Export your data from Settings, then reset the app to start over.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrismButton(
                  label: context.l10n.syncSetupCompleteButton,
                  icon: AppIcons.check,
                  tone: PrismButtonTone.filled,
                  enabled: _canSubmit,
                  isLoading: widget.isProcessing,
                  onPressed: widget.onSubmit,
                ),
                if (widget.isProcessing && _progressLabel(context) != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _progressLabel(context)!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
