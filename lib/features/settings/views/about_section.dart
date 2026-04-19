import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// About info widget for the settings screen.
///
/// Displays the app icon, name, version, description, and placeholder
/// action links (GitHub, Privacy, Feedback).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        const SizedBox(height: 8),
        // App icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.prismPurple,
            borderRadius: PrismShapes.of(context).cornerStyle == CornerStyle.angular
                ? BorderRadius.zero
                : BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Image.asset(
              'assets/icon_layers/Prism-Logo-Foreground.png',
              width: 44,
              height: 44,
            ),
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.settingsAboutAppName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.settingsAboutTagline,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.settingsAboutVersion('0.1.0'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            context.l10n.settingsAboutDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            PrismChip(
              avatar: Icon(AppIcons.code, size: 18),
              label: context.l10n.settingsAboutGitHub,
              selected: false,
              onTap: () {
                PrismToast.show(context, message: context.l10n.settingsAboutGitHubComingSoon);
              },
            ),
            PrismChip(
              avatar: Icon(AppIcons.privacyTipOutlined, size: 18),
              label: context.l10n.settingsAboutPrivacy,
              selected: false,
              onTap: () {
                launchUrl(
                  Uri.parse('https://prismplural.com/privacy'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            PrismChip(
              avatar: Icon(AppIcons.enhancedEncryptionOutlined, size: 18),
              label: context.l10n.settingsAboutSecurity,
              selected: false,
              onTap: () {
                launchUrl(
                  Uri.parse('https://prismplural.com/encryption'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            PrismChip(
              avatar: Icon(AppIcons.feedbackOutlined, size: 18),
              label: context.l10n.settingsAboutFeedback,
              selected: false,
              onTap: () {
                PrismToast.show(context, message: context.l10n.settingsAboutFeedbackComingSoon);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
