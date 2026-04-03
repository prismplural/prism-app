import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';

class FeaturesStep extends ConsumerWidget {
  const FeaturesStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FeatureToggle(
            icon: Icons.forum,
            iconColor: Colors.orange,
            title: 'Chat',
            description: 'Internal messaging between system members',
            value: onboarding.chatEnabled,
            onChanged: (v) => notifier.setFeatureToggle(chatEnabled: v),
          ),
          const SizedBox(height: 12),
          _FeatureToggle(
            icon: Icons.poll,
            iconColor: Colors.indigo,
            title: 'Polls',
            description: 'Create polls for system decisions',
            value: onboarding.pollsEnabled,
            onChanged: (v) => notifier.setFeatureToggle(pollsEnabled: v),
          ),
          const SizedBox(height: 12),
          _FeatureToggle(
            icon: Icons.check_circle_outline,
            iconColor: Colors.green,
            title: 'Habits',
            description: 'Track daily habits and routines',
            value: onboarding.habitsEnabled,
            onChanged: (v) => notifier.setFeatureToggle(habitsEnabled: v),
          ),
          const SizedBox(height: 12),
          _FeatureToggle(
            icon: Icons.bedtime,
            iconColor: Colors.blue,
            title: 'Sleep Tracking',
            description: 'Monitor sleep patterns and quality',
            value: onboarding.sleepTrackingEnabled,
            onChanged: (v) =>
                notifier.setFeatureToggle(sleepTrackingEnabled: v),
          ),
        ],
      ),
    );
  }
}

class _FeatureToggle extends StatelessWidget {
  const _FeatureToggle({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.warmWhite.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.warmWhite,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: AppColors.warmWhite.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.warmWhite.withValues(alpha: 0.3),
            activeThumbColor: AppColors.warmWhite,
            inactiveTrackColor: AppColors.warmWhite.withValues(alpha: 0.08),
            inactiveThumbColor: AppColors.warmWhite.withValues(alpha: 0.4),
            trackOutlineColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.warmWhite.withValues(alpha: 0.15);
              }
              return AppColors.warmWhite.withValues(alpha: 0.1);
            }),
          ),
        ],
      ),
    );
  }
}
