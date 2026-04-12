import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class CompleteStep extends StatelessWidget {
  const CompleteStep({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _NextStepRow(
            icon: AppIcons.duotoneFronting,
            title: context.l10n.onboardingCompleteTrackFrontingTitle,
            description: context.l10n.onboardingCompleteTrackFrontingDescription,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _NextStepRow(
            icon: AppIcons.duotoneChat,
            title: context.l10n.onboardingCompleteChatTitle,
            description: context.l10n.onboardingCompleteChatDescription,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _NextStepRow(
            icon: AppIcons.duotonePolls,
            title: context.l10n.onboardingCompletePollsTitle,
            description: context.l10n.onboardingCompletePollsDescription,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _NextStepRow extends StatelessWidget {
  const _NextStepRow({
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.prismPurple.withValues(alpha: 0.15),
          ),
          child: Center(
            child: PhosphorIcon(
              icon,
              size: 22,
              color: isDark
                  ? AppColors.prismPurple
                  : AppColors.prismPurpleLight,
            ),
          ),
        ),
        const SizedBox(width: 14),
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
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: isDark
                      ? AppColors.mutedTextDark
                      : AppColors.mutedTextLight,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
