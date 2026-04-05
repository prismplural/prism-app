import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Terminology section
          Text(
            'Terminology',
            style: TextStyle(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
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
                          ? 'Custom'
                          : term.pluralForm,
                      style: TextStyle(
                        color: isSelected
                            ? primary
                            : isDark
                                ? AppColors.warmWhite.withValues(alpha: 0.8)
                                : AppColors.warmBlack.withValues(alpha: 0.8),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 15,
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
                    hint: 'Singular (e.g. Alter)',
                    onChanged: notifier.setCustomTermSingular,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    controller: _customPluralController,
                    hint: 'Plural (e.g. Alters)',
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
            'Accent Color',
            style: TextStyle(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
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
                        'Per-Member Colors',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.warmBlack,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Let each member have their own accent color',
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
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.1)
            : AppColors.parchmentElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: PrismTextField(
        controller: controller,
        style: TextStyle(
          color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
          fontSize: 14,
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
