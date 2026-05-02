import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

final _websiteUri = Uri.parse('https://prismplural.com');
final _githubUri = Uri.parse('https://github.com/prismplural');
final _discordUri = Uri.parse('https://discord.gg/32Qfhd6jMM');
final _blueskyUri = Uri.parse('https://bsky.app/profile/prismplural.com');
final _tumblrUri = Uri.parse('https://prismplural.tumblr.com/');
final _privacyUri = Uri.parse('https://prismplural.com/privacy/');
final _securityUri = Uri.parse('https://prismplural.com/encryption/');
final _feedbackUri = Uri(
  scheme: 'mailto',
  path: 'hello@prismplural.com',
  queryParameters: {'subject': 'Prism feedback'},
);

/// About info widget for the settings screen.
///
/// Displays the app icon, name, version, description, and external links.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final version = ref
        .watch(_packageInfoProvider)
        .maybeWhen(data: _formatPackageVersion, orElse: _buildInfoVersion);

    return Column(
      children: [
        const SizedBox(height: 8),
        // App icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.prismPurple,
            borderRadius:
                PrismShapes.of(context).cornerStyle == CornerStyle.angular
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
          context.l10n.settingsAboutVersion(version),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            context.l10n.settingsAboutDescription(terms.pluralLower),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PrismChip(
              avatar: Icon(AppIcons.website, size: 18),
              label: context.l10n.settingsAboutWebsite,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _websiteUri)),
            ),
            PrismChip(
              avatar: Icon(AppIcons.githubLogo, size: 18),
              label: context.l10n.settingsAboutGitHub,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _githubUri)),
            ),
            PrismChip(
              avatar: Icon(AppIcons.discordLogo, size: 18),
              label: context.l10n.settingsAboutDiscord,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _discordUri)),
            ),
            PrismChip(
              avatar: Icon(AppIcons.bluesky, size: 18),
              label: context.l10n.settingsAboutBluesky,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _blueskyUri)),
            ),
            PrismChip(
              avatar: Icon(AppIcons.tumblrLogo, size: 18),
              label: context.l10n.settingsAboutTumblr,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _tumblrUri)),
            ),
            PrismChip(
              avatar: Icon(AppIcons.privacyTipOutlined, size: 18),
              label: context.l10n.settingsAboutPrivacy,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _privacyUri)),
            ),
            PrismChip(
              avatar: Icon(AppIcons.enhancedEncryptionOutlined, size: 18),
              label: context.l10n.settingsAboutSecurity,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _securityUri)),
            ),
            PrismChip(
              avatar: Icon(AppIcons.feedbackOutlined, size: 18),
              label: context.l10n.settingsAboutFeedback,
              selected: false,
              onTap: () => unawaited(_openExternalUri(context, _feedbackUri)),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

String _formatPackageVersion(PackageInfo info) {
  final version = info.version.trim();
  if (version.isEmpty) return _buildInfoVersion();

  final buildNumber = info.buildNumber.trim();
  if (buildNumber.isEmpty) return version;

  return '$version+$buildNumber';
}

String _buildInfoVersion() {
  return BuildInfo.appVersion == 'unknown' ? '...' : BuildInfo.appVersion;
}

Future<void> _openExternalUri(BuildContext context, Uri uri) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;
  } catch (_) {
    if (!context.mounted) return;
  }

  PrismToast.show(context, message: context.l10n.settingsAboutLinkOpenFailed);
}
