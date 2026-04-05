import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FeatureRow(
            icon: AppIcons.duotoneEncryption,
            title: 'Private by default',
            description:
                'Not even we can read your data. Everything stays on your device unless you choose to sync.',
            isDark: isDark,
          ),
          SizedBox(height: 20),
          _FeatureRow(
            icon: AppIcons.duotoneSync,
            title: 'Sync across devices',
            description:
                'End-to-end encrypted. The server only sees noise.',
            isDark: isDark,
          ),
          SizedBox(height: 20),
          _FeatureRow(
            icon: AppIcons.duotoneTheme,
            title: 'Built for you',
            description:
                'Your words, your colors, your features. Prism adapts to how your system works.',
            isDark: isDark,
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
