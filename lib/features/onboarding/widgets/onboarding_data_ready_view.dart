import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class OnboardingDataReadyView extends StatelessWidget {
  const OnboardingDataReadyView({
    super.key,
    required this.title,
    required this.description,
    required this.summaryLabel,
    required this.actionLabel,
    required this.onAction,
    this.counts,
    this.notice,
  });

  final String title;
  final String description;
  final String summaryLabel;
  final String actionLabel;
  final VoidCallback onAction;
  final OnboardingDataCounts? counts;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(AppIcons.checkCircleOutline, color: AppColors.success, size: 56),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.mutedTextDark
                  : AppColors.mutedTextLight,
            ),
            textAlign: TextAlign.center,
          ),
          if (notice != null) ...[const SizedBox(height: 12), notice!],
          if (counts != null) ...[
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.1)
                    : AppColors.parchmentElevated,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summaryLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.mutedTextDark
                          : AppColors.mutedTextLight,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OnboardingCountRow(label: context.l10n.onboardingDataReadyMembers, count: counts!.members),
                  OnboardingCountRow(
                    label: context.l10n.onboardingDataReadyFrontingSessions,
                    count: counts!.frontingSessions,
                  ),
                  OnboardingCountRow(
                    label: context.l10n.onboardingDataReadyConversations,
                    count: counts!.conversations,
                  ),
                  OnboardingCountRow(label: context.l10n.onboardingDataReadyMessages, count: counts!.messages),
                  OnboardingCountRow(label: context.l10n.onboardingDataReadyHabits, count: counts!.habits),
                  OnboardingCountRow(label: context.l10n.onboardingDataReadyNotes, count: counts!.notes),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            child: PrismButton(
              onPressed: onAction,
              label: actionLabel,
              tone: PrismButtonTone.filled,
              expanded: true,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class OnboardingCountRow extends StatelessWidget {
  const OnboardingCountRow({
    required this.label,
    required this.count,
    // Optional override for the count widget (e.g. an animated tween).
    this.countWidget,
    super.key,
  });

  final String label;
  final int count;
  final Widget? countWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.mutedTextDark
                    : AppColors.mutedTextLight,
              ),
            ),
          ),
          countWidget ??
              Text(
                '$count',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
                  fontWeight: FontWeight.w700,
                ),
              ),
        ],
      ),
    );
  }
}
