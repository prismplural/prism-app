import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, this.onSyncDevice});

  final VoidCallback? onSyncDevice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FeatureRow(
            icon: AppIcons.duotoneEncryption,
            title: context.l10n.onboardingWelcomePrivateTitle,
            description: context.l10n.onboardingWelcomePrivateDescription,
            isDark: isDark,
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            icon: AppIcons.duotoneSync,
            title: context.l10n.onboardingWelcomeSyncTitle,
            description: context.l10n.onboardingWelcomeSyncDescription,
            isDark: isDark,
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            icon: AppIcons.duotoneTheme,
            title: context.l10n.onboardingWelcomeBuiltForYouTitle,
            description: context.l10n.onboardingWelcomeBuiltForYouDescription,
            isDark: isDark,
          ),
          const SizedBox(height: 32),
          if (onSyncDevice != null)
            GestureDetector(
              onTap: onSyncDevice,
              child: Text(
                context.l10n.onboardingWelcomeSyncLink,
                style: TextStyle(
                  color: isDark
                      ? AppColors.mutedTextDark
                      : AppColors.mutedTextLight,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: isDark
                      ? AppColors.mutedTextDark
                      : AppColors.mutedTextLight,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.isDark,
  });

  final PhosphorIconData icon;
  final String title;
  final String description;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.prismPurple.withValues(alpha: 0.15),
          ),
          child: Center(
            child: PhosphorIcon(
              icon,
              size: 24,
              color: isDark
                  ? AppColors.prismPurple
                  : AppColors.prismPurpleLight,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDark
                      ? AppColors.warmWhite
                      : AppColors.warmBlack,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: isDark
                      ? AppColors.mutedTextDark
                      : AppColors.mutedTextLight,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
