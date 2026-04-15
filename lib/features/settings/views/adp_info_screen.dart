import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Educational screen explaining how data is protected in Prism.
///
/// Prose-first: lead + body set the plain-language promise; a collapsible
/// "How it works" section surfaces the technical cryptographic detail for
/// users who want it.  No status indicators or checklist tiles.
class AdpInfoScreen extends StatelessWidget {
  const AdpInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.settingsEncryptionPrivacy,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 24, 16, NavBarInset.of(context)),
        children: [
          // ── Lock icon ──────────────────────────────────────────────────────
          Center(
            child: Icon(
              AppIcons.duotoneLock,
              size: 56,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),

          // ── Lead ───────────────────────────────────────────────────────────
          Text(
            context.l10n.encryptionPrivacyIntroTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // ── Body ───────────────────────────────────────────────────────────
          Text(
            context.l10n.encryptionPrivacyIntroBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // ── Zero-knowledge note ────────────────────────────────────────────
          PrismSurface(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  AppIcons.cloudOffOutlined,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                     context.l10n.encryptionPrivacySyncNote,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── "How it works" collapsible ────────────────────────────────────
          PrismExpandableSection(
            leading: Icon(
              AppIcons.shieldOutlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              context.l10n.encryptionPrivacyHowItWorks,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              _TechItem(
                title: context.l10n.encryptionPrivacyDatabaseTitle,
                body: context.l10n.encryptionPrivacyDatabaseBody,
              ),
              _TechItem(
                title: context.l10n.encryptionPrivacyMessageTitle,
                body: context.l10n.encryptionPrivacyMessageBody,
              ),
              _TechItem(
                title: context.l10n.encryptionPrivacyPostQuantumTitle,
                body: context.l10n.encryptionPrivacyPostQuantumBody,
              ),
              _TechItem(
                title: context.l10n.encryptionPrivacyRecoveryTitle,
                body: context.l10n.encryptionPrivacyRecoveryBody,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// A single technical detail row inside the "How it works" expansion.
class _TechItem extends StatelessWidget {
  const _TechItem({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(body, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
