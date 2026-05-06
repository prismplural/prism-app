import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/accent_color_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

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
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(10),
          ),
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
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
        final isSelected =
            onboarding.selectedTerminology == term &&
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

  String _frontBehaviorLabel(
    BuildContext context,
    FrontStartBehavior behavior,
  ) {
    return switch (behavior) {
      FrontStartBehavior.additive =>
        context.l10n.onboardingFrontBehaviorAdditive,
      FrontStartBehavior.replace => context.l10n.onboardingFrontBehaviorReplace,
    };
  }

  Widget _frontBehaviorCard({
    required BuildContext context,
    required String title,
    required String description,
    required FrontStartBehavior value,
    required ValueChanged<FrontStartBehavior> onChanged,
    required bool isDark,
    required Color primary,
    required ThemeData theme,
  }) {
    final selectedDescription = switch (value) {
      FrontStartBehavior.additive =>
        context.l10n.onboardingFrontBehaviorAdditiveDescription,
      FrontStartBehavior.replace =>
        context.l10n.onboardingFrontBehaviorReplaceDescription,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.1)
            : AppColors.parchmentElevated,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.warmWhite : AppColors.warmBlack,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.mutedTextDark
                  : AppColors.mutedTextLight,
            ),
          ),
          const SizedBox(height: 12),
          PrismSegmentedControl<FrontStartBehavior>(
            segments: [
              PrismSegment(
                value: FrontStartBehavior.additive,
                label: _frontBehaviorLabel(
                  context,
                  FrontStartBehavior.additive,
                ),
              ),
              PrismSegment(
                value: FrontStartBehavior.replace,
                label: _frontBehaviorLabel(context, FrontStartBehavior.replace),
              ),
            ],
            selected: value,
            onChanged: onChanged,
          ),
          const SizedBox(height: 10),
          Text(
            selectedDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
    final currentSettings = ref
        .watch(systemSettingsProvider)
        .whenOrNull(data: (settings) => settings);
    final addFrontBehavior =
        onboarding.addFrontDefaultBehavior ??
        currentSettings?.addFrontDefaultBehavior ??
        FrontStartBehavior.additive;
    final quickFrontBehavior =
        onboarding.quickFrontDefaultBehavior ??
        currentSettings?.quickFrontDefaultBehavior ??
        FrontStartBehavior.additive;
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );

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
          Text(
            context.l10n.onboardingFrontBehaviorSection,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.8)
                  : AppColors.warmBlack.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 10),
          _frontBehaviorCard(
            context: context,
            title: context.l10n.onboardingAddFrontBehaviorTitle,
            description: context.l10n.onboardingAddFrontBehaviorDescription,
            value: addFrontBehavior,
            onChanged: notifier.setAddFrontDefaultBehavior,
            isDark: isDark,
            primary: primary,
            theme: theme,
          ),
          const SizedBox(height: 12),
          _frontBehaviorCard(
            context: context,
            title: context.l10n.onboardingQuickFrontBehaviorTitle,
            description: context.l10n.onboardingQuickFrontBehaviorDescription,
            value: quickFrontBehavior,
            onChanged: notifier.setQuickFrontDefaultBehavior,
            isDark: isDark,
            primary: primary,
            theme: theme,
          ),
          const SizedBox(height: 24),

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
                isSelected:
                    onboarding.selectedTerminology == SystemTerminology.custom,
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

          // Color grid — shared with settings so presets + custom picker +
          // legibility warning stay in sync across the app.
          AccentColorPicker(
            currentHex: onboarding.accentColorHex,
            onChanged: notifier.setAccentColor,
          ),

          const SizedBox(height: 24),

          // Per-member colors toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.warmWhite.withValues(alpha: 0.1)
                  : AppColors.parchmentElevated,
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.onboardingPreferencesPerMemberColors(
                          terms.singular,
                          terms.singularLower,
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.warmBlack,
                        ),
                      ),
                      Text(
                        context.l10n
                            .onboardingPreferencesPerMemberColorsSubtitle(
                              terms.singularLower,
                            ),
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
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(10)),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
