import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
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

  // ---------------------------------------------------------------------------
  // Hardcoded English term labels (used in non-English mode English section)
  // ---------------------------------------------------------------------------

  static String _englishPlural(SystemTerminology term) => switch (term) {
        SystemTerminology.members => 'Members',
        SystemTerminology.headmates => 'Headmates',
        SystemTerminology.alters => 'Alters',
        SystemTerminology.parts => 'Parts',
        SystemTerminology.facets => 'Facets',
        SystemTerminology.custom => 'Custom',
      };

  // ---------------------------------------------------------------------------
  // Build helpers
  // ---------------------------------------------------------------------------

  Widget _termTile({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required Color primary,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: onTap,
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
            label,
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
  }

  Widget _termGrid({
    required BuildContext context,
    required List<SystemTerminology> terms,
    required bool useEnglish,
    required OnboardingState onboarding,
    required OnboardingNotifier notifier,
    required bool isDark,
    required Color primary,
    required ThemeData theme,
  }) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3,
      children: terms.map((term) {
        final isSelected = onboarding.selectedTerminology == term &&
            onboarding.terminologyUseEnglish == useEnglish;
        final label = useEnglish
            ? _englishPlural(term)
            : (term == SystemTerminology.custom
                ? context.l10n.onboardingPreferencesCustomTerminology
                : resolveTerminology(context.l10n, term).plural);
        return _termTile(
          context: context,
          label: label,
          isSelected: isSelected,
          onTap: () => notifier.setTerminology(term, useEnglish: useEnglish),
          isDark: isDark,
          primary: primary,
          theme: theme,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final locale = Localizations.localeOf(context);
    final isEnglish = locale.languageCode == 'en';

    // Standard terms (custom handled separately)
    const standardTerms = [
      SystemTerminology.members,
      SystemTerminology.headmates,
      SystemTerminology.alters,
      SystemTerminology.parts,
      SystemTerminology.facets,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Terminology section label
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

          if (isEnglish)
            // English locale: single 2×3 grid (5 terms + custom)
            _termGrid(
              context: context,
              terms: [...standardTerms, SystemTerminology.custom],
              useEnglish: false,
              onboarding: onboarding,
              notifier: notifier,
              isDark: isDark,
              primary: primary,
              theme: theme,
            )
          else ...[
            // Non-English locale: localized section
            _termGrid(
              context: context,
              terms: standardTerms,
              useEnglish: false,
              onboarding: onboarding,
              notifier: notifier,
              isDark: isDark,
              primary: primary,
              theme: theme,
            ),
            const SizedBox(height: 12),

            // "In English" section header
            Text(
              context.l10n.terminologyEnglishOptionsLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: isDark
                    ? AppColors.warmWhite.withValues(alpha: 0.55)
                    : AppColors.warmBlack.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),

            // English section
            _termGrid(
              context: context,
              terms: standardTerms,
              useEnglish: true,
              onboarding: onboarding,
              notifier: notifier,
              isDark: isDark,
              primary: primary,
              theme: theme,
            ),
            const SizedBox(height: 8),

            // Custom tile (always localized, always last)
            SizedBox(
              height: 44,
              child: _termTile(
                context: context,
                label: context.l10n.onboardingPreferencesCustomTerminology,
                isSelected: onboarding.selectedTerminology ==
                    SystemTerminology.custom,
                onTap: () => notifier.setTerminology(
                  SystemTerminology.custom,
                  useEnglish: false,
                ),
                isDark: isDark,
                primary: primary,
                theme: theme,
              ),
            ),
          ],

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
