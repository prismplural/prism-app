import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

class TerminologyStep extends ConsumerStatefulWidget {
  const TerminologyStep({super.key});

  @override
  ConsumerState<TerminologyStep> createState() => _TerminologyStepState();
}

class _TerminologyStepState extends ConsumerState<TerminologyStep> {
  final _customSingularController = TextEditingController();
  final _customPluralController = TextEditingController();

  @override
  void initState() {
    super.initState();
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

  static String _englishPlural(SystemTerminology term) => switch (term) {
    SystemTerminology.members => 'Members',
    SystemTerminology.headmates => 'Headmates',
    SystemTerminology.alters => 'Alters',
    SystemTerminology.parts => 'Parts',
    SystemTerminology.facets => 'Facets',
    SystemTerminology.custom => 'Custom',
  };

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
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
          _SectionLabel(
            label: context.l10n.onboardingPreferencesTerminology,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          if (isEnglish)
            _TermGrid(
              terms: [...standardTerms, SystemTerminology.custom],
              useEnglish: false,
              onboarding: onboarding,
              notifier: notifier,
              isDark: isDark,
              primary: primary,
              englishLabelFor: _englishPlural,
            )
          else ...[
            _TermGrid(
              terms: standardTerms,
              useEnglish: false,
              onboarding: onboarding,
              notifier: notifier,
              isDark: isDark,
              primary: primary,
              englishLabelFor: _englishPlural,
            ),
            const SizedBox(height: 12),
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
            _TermGrid(
              terms: standardTerms,
              useEnglish: true,
              onboarding: onboarding,
              notifier: notifier,
              isDark: isDark,
              primary: primary,
              englishLabelFor: _englishPlural,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: _TermTile(
                label: context.l10n.onboardingPreferencesCustomTerminology,
                isSelected:
                    onboarding.selectedTerminology == SystemTerminology.custom,
                onTap: () => notifier.setTerminology(
                  SystemTerminology.custom,
                  useEnglish: false,
                ),
                isDark: isDark,
                primary: primary,
              ),
            ),
          ],
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

class _TermGrid extends StatelessWidget {
  const _TermGrid({
    required this.terms,
    required this.useEnglish,
    required this.onboarding,
    required this.notifier,
    required this.isDark,
    required this.primary,
    required this.englishLabelFor,
  });

  final List<SystemTerminology> terms;
  final bool useEnglish;
  final OnboardingState onboarding;
  final OnboardingNotifier notifier;
  final bool isDark;
  final Color primary;
  final String Function(SystemTerminology term) englishLabelFor;

  @override
  Widget build(BuildContext context) {
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
            ? englishLabelFor(term)
            : (term == SystemTerminology.custom
                  ? context.l10n.onboardingPreferencesCustomTerminology
                  : resolveTerminology(context.l10n, term).plural);
        return _TermTile(
          label: label,
          isSelected: isSelected,
          onTap: () => notifier.setTerminology(term, useEnglish: useEnglish),
          isDark: isDark,
          primary: primary,
        );
      }).toList(),
    );
  }
}

class _TermTile extends StatelessWidget {
  const _TermTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
    required this.primary,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.8)
            : AppColors.warmBlack.withValues(alpha: 0.8),
      ),
    );
  }
}
