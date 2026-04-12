import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class PreferencesStep extends ConsumerStatefulWidget {
  const PreferencesStep({super.key});

  @override
  ConsumerState<PreferencesStep> createState() => _PreferencesStepState();
}

class _PreferencesStepState extends ConsumerState<PreferencesStep> {
  final _customSingularController = TextEditingController();
  final _customPluralController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-populate from state so values survive back/forward navigation.
    final onboarding = ref.read(onboardingProvider);
    _customSingularController.text = onboarding.customTermSingular ?? '';
    _customPluralController.text = onboarding.customTermPlural ?? '';
  }

  @override
  void dispose() {
    _customSingularController.dispose();
    _customPluralController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Terminology section
          Text(
            context.l10n.onboardingPreferencesTerminology,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 10),

          // 2x3 grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3,
            children: SystemTerminology.values.map((term) {
              final isSelected = onboarding.selectedTerminology == term;
              return GestureDetector(
                onTap: () => notifier.setTerminology(term),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primary.withValues(alpha: 0.2)
                        : isDark
                            ? AppColors.warmWhite.withValues(alpha: 0.1)
                            : AppColors.parchmentElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      term == SystemTerminology.custom
                          ? context.l10n.onboardingPreferencesCustomTerminology
                          : term.pluralForm,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isSelected
                            ? primary
                            : isDark
                                ? AppColors.warmWhite.withValues(alpha: 0.8)
                                : AppColors.warmBlack.withValues(alpha: 0.8),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // Custom terminology fields
          if (onboarding.selectedTerminology == SystemTerminology.custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _customSingularController,
                    hint: context.l10n.onboardingPreferencesSingularHint,
                    onChanged: notifier.setCustomTermSingular,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    controller: _customPluralController,
                    hint: context.l10n.onboardingPreferencesPluralHint,
                    onChanged: notifier.setCustomTermPlural,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // Accent color section
          Text(
            context.l10n.onboardingPreferencesAccentColor,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 10),

          // Color grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: predefinedColors.length,
            itemBuilder: (context, index) {
              final hex = predefinedColors[index];
              final color = hexToColor(hex);
              final isSelected = onboarding.accentColorHex == hex;

              return GestureDetector(
                onTap: () => notifier.setAccentColor(hex),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Per-member colors toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.1)
                  : AppColors.parchmentElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.onboardingPreferencesPerMemberColors,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.warmBlack,
                        ),
                      ),
                      Text(
                        context.l10n.onboardingPreferencesPerMemberColorsSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.mutedTextDark
                              : AppColors.mutedTextLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: onboarding.usePerMemberColors,
                  onChanged: notifier.setUsePerMemberColors,
                  activeTrackColor: primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.1)
            : AppColors.parchmentElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: PrismTextField(
        controller: controller,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark
              ? AppColors.warmWhite.withValues(alpha: 0.35)
              : AppColors.warmBlack.withValues(alpha: 0.35),
          fontSize: 14,
        ),
        fieldStyle: PrismTextFieldStyle.borderless,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onChanged: onChanged,
      ),
    );
  }
}
