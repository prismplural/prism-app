import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class FeaturesStep extends ConsumerWidget {
  const FeaturesStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FeatureToggle(
                  icon: AppIcons.duotoneChat,
                  isDark: isDark,
                  primary: primary,
                  title: context.l10n.onboardingFeaturesChat,
                  description: context.l10n.onboardingFeaturesChatDescription(
                    terms.pluralLower,
                  ),
                  value: onboarding.chatEnabled,
                  onChanged: (v) => notifier.setFeatureToggle(chatEnabled: v),
                ),
                const SizedBox(height: 12),
                _FeatureToggle(
                  icon: AppIcons.duotonePolls,
                  isDark: isDark,
                  primary: primary,
                  title: context.l10n.onboardingFeaturesPolls,
                  description: context.l10n.onboardingFeaturesPollsDescription,
                  value: onboarding.pollsEnabled,
                  onChanged: (v) => notifier.setFeatureToggle(pollsEnabled: v),
                ),
                const SizedBox(height: 12),
                _FeatureToggle(
                  icon: AppIcons.duotoneHabits,
                  isDark: isDark,
                  primary: primary,
                  title: context.l10n.onboardingFeaturesHabits,
                  description: context.l10n.onboardingFeaturesHabitsDescription,
                  value: onboarding.habitsEnabled,
                  onChanged: (v) => notifier.setFeatureToggle(habitsEnabled: v),
                ),
                const SizedBox(height: 12),
                _FeatureToggle(
                  icon: AppIcons.duotoneSleep,
                  isDark: isDark,
                  primary: primary,
                  title: context.l10n.onboardingFeaturesSleepTracking,
                  description:
                      context.l10n.onboardingFeaturesSleepTrackingDescription,
                  value: onboarding.sleepTrackingEnabled,
                  onChanged: (v) =>
                      notifier.setFeatureToggle(sleepTrackingEnabled: v),
                ),
                const SizedBox(height: 12),
                _FeatureToggle(
                  icon: AppIcons.duotoneNotes,
                  isDark: isDark,
                  primary: primary,
                  title: context.l10n.onboardingFeaturesNotes,
                  description: context.l10n.onboardingFeaturesNotesDescription,
                  value: onboarding.notesEnabled,
                  onChanged: (v) => notifier.setFeatureToggle(notesEnabled: v),
                ),
                const SizedBox(height: 12),
                _FeatureToggle(
                  icon: AppIcons.navBoards,
                  isDark: isDark,
                  primary: primary,
                  title: context.l10n.onboardingFeaturesBoards,
                  description:
                      context.l10n.onboardingFeaturesBoardsDescription,
                  value: onboarding.boardsEnabled,
                  onChanged: (v) =>
                      notifier.setFeatureToggle(boardsEnabled: v),
                ),
                const SizedBox(height: 12),
                _FeatureToggle(
                  icon: AppIcons.duotoneReminders,
                  isDark: isDark,
                  primary: primary,
                  title: context.l10n.onboardingFeaturesReminders,
                  description: context.l10n
                      .onboardingFeaturesRemindersDescription(
                        terms.pluralLower,
                      ),
                  value: onboarding.remindersEnabled,
                  onChanged: (v) =>
                      notifier.setFeatureToggle(remindersEnabled: v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeatureToggle extends StatelessWidget {
  const _FeatureToggle({
    required this.icon,
    required this.isDark,
    required this.primary,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final PhosphorIconData icon;
  final bool isDark;
  final Color primary;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.1)
            : AppColors.parchmentElevated,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.15),
            ),
            child: Center(child: PhosphorIcon(icon, size: 22, color: primary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
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
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: primary.withValues(alpha: 0.5),
            activeThumbColor: primary,
            inactiveTrackColor: isDark
                ? AppColors.warmWhite.withValues(alpha: 0.08)
                : AppColors.warmBlack.withValues(alpha: 0.08),
            inactiveThumbColor: isDark
                ? AppColors.warmWhite.withValues(alpha: 0.4)
                : AppColors.warmBlack.withValues(alpha: 0.4),
            trackOutlineColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return primary.withValues(alpha: 0.15);
              }
              return isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.1)
                  : AppColors.warmBlack.withValues(alpha: 0.1);
            }),
          ),
        ],
      ),
    );
  }
}
