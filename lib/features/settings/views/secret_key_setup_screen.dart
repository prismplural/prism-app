import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/widgets/secret_key_reveal_content.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class SecretKeySetupScreen extends ConsumerStatefulWidget {
  final String? mnemonic;
  final VoidCallback onComplete;

  const SecretKeySetupScreen({
    super.key,
    required this.mnemonic,
    required this.onComplete,
  });

  @override
  ConsumerState<SecretKeySetupScreen> createState() =>
      _SecretKeySetupScreenState();
}

class _SecretKeySetupScreenState extends ConsumerState<SecretKeySetupScreen> {
  bool _hasSaved = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final mnemonic = (widget.mnemonic ?? ref.read(pendingMnemonicProvider))?.trim();
    if (mnemonic == null || mnemonic.isEmpty) {
      return PrismPageScaffold(
        topBar: PrismTopBar(title: l10n.secretKeyUnavailableTitle),
        bodyPadding: EdgeInsets.zero,
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  AppIcons.duotoneKey,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.secretKeyUnavailableMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.secretKeyUnavailableHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                PrismButton(
                  onPressed: widget.onComplete,
                  label: l10n.secretKeyBackToSync,
                  tone: PrismButtonTone.filled,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(title: l10n.secretKeyTitle),
      bodyPadding: EdgeInsets.zero,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SecretKeyRevealContent(
              mnemonic: mnemonic,
              hasSaved: _hasSaved,
              onHasSavedChanged: (v) => setState(() => _hasSaved = v),
            ),
            const SizedBox(height: 16),
            PrismButton(
              onPressed: widget.onComplete,
              enabled: _hasSaved,
              label: l10n.continueLabel,
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
      ),
    );
  }
}
