import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

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
            title: 'Track fronting',
            description:
                "Log who's here and look back at patterns over time.",
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _NextStepRow(
            icon: AppIcons.duotoneChat,
            title: 'Talk to each other',
            description:
                'Leave messages for whoever fronts next, or chat in real time.',
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _NextStepRow(
            icon: AppIcons.duotonePolls,
            title: 'Decide together',
            description:
                'Polls, votes \u2014 the democracy your system deserves.',
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
