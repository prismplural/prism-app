import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_term_choice_grid.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

typedef _TermOption = ({SystemTerminology term, bool useEnglish});
typedef _SystemTermOption = ({SystemTermPreset? preset, bool custom});

class TerminologyStep extends ConsumerStatefulWidget {
  const TerminologyStep({super.key});

  @override
  ConsumerState<TerminologyStep> createState() => _TerminologyStepState();
}

class _TerminologyStepState extends ConsumerState<TerminologyStep> {
  final _customSingularController = TextEditingController();
  final _customPluralController = TextEditingController();
  final _customSystemSingularController = TextEditingController();
  final _customSystemPluralController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final onboarding = ref.read(onboardingProvider);
    _customSingularController.text = onboarding.customTermSingular ?? '';
    _customPluralController.text = onboarding.customTermPlural ?? '';
    _customSystemSingularController.text =
        onboarding.customSystemTermSingular ?? '';
    _customSystemPluralController.text =
        onboarding.customSystemTermPlural ?? '';
  }

  @override
  void dispose() {
    _customSingularController.dispose();
    _customPluralController.dispose();
    _customSystemSingularController.dispose();
    _customSystemPluralController.dispose();
    super.dispose();
  }

  static ({String singular, String plural}) _englishLabels(
    SystemTerminology term,
  ) => switch (term) {
    SystemTerminology.members => (singular: 'member', plural: 'Members'),
    SystemTerminology.headmates => (singular: 'headmate', plural: 'Headmates'),
    SystemTerminology.alters => (singular: 'alter', plural: 'Alters'),
    SystemTerminology.parts => (singular: 'part', plural: 'Parts'),
    SystemTerminology.facets => (singular: 'facet', plural: 'Facets'),
    SystemTerminology.custom => (singular: 'custom term', plural: 'Custom'),
  };

  static const _standardTerms = [
    SystemTerminology.members,
    SystemTerminology.headmates,
    SystemTerminology.alters,
    SystemTerminology.parts,
    SystemTerminology.facets,
  ];

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final selectedFrontingPreset =
        onboarding.pendingFrontingTerms.normalized().preset ??
        FrontingTermPreset.fronting;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            label: context.l10n.onboardingPreferencesMemberTerminology,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          if (isEnglish)
            PrismTermChoiceGrid<_TermOption>(
              selected: (
                term: onboarding.selectedTerminology,
                useEnglish: false,
              ),
              choices: [
                for (final term in _standardTerms)
                  _memberChoice(context, term, useEnglish: false),
                _memberChoice(
                  context,
                  SystemTerminology.custom,
                  useEnglish: false,
                ),
              ],
              onSelected: (option) => notifier.setTerminology(
                option.term,
                useEnglish: option.useEnglish,
              ),
            )
          else ...[
            PrismTermChoiceGrid<_TermOption>(
              selected: (
                term: onboarding.selectedTerminology,
                useEnglish: onboarding.terminologyUseEnglish,
              ),
              choices: [
                for (final term in _standardTerms)
                  _memberChoice(context, term, useEnglish: false),
              ],
              onSelected: (option) => notifier.setTerminology(
                option.term,
                useEnglish: option.useEnglish,
              ),
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
            PrismTermChoiceGrid<_TermOption>(
              selected: (
                term: onboarding.selectedTerminology,
                useEnglish: onboarding.terminologyUseEnglish,
              ),
              choices: [
                for (final term in _standardTerms)
                  _memberChoice(context, term, useEnglish: true),
              ],
              onSelected: (option) => notifier.setTerminology(
                option.term,
                useEnglish: option.useEnglish,
              ),
            ),
            const SizedBox(height: 8),
            PrismTermChoiceGrid<_TermOption>(
              selected: (
                term: onboarding.selectedTerminology,
                useEnglish: onboarding.terminologyUseEnglish,
              ),
              choices: [
                _memberChoice(
                  context,
                  SystemTerminology.custom,
                  useEnglish: false,
                ),
              ],
              onSelected: (option) => notifier.setTerminology(
                option.term,
                useEnglish: option.useEnglish,
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
          const SizedBox(height: 24),
          _SectionLabel(
            label: context.l10n.onboardingPreferencesSystemTerminology,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          PrismTermChoiceGrid<_SystemTermOption>(
            selected: onboarding.useCustomSystemTerminology
                ? (preset: null, custom: true)
                : (preset: onboarding.selectedSystemTermPreset, custom: false),
            choices: [
              PrismTermChoice<_SystemTermOption>(
                value: (preset: null, custom: false),
                label: context.l10n.terminologySystemDefaultSingular,
              ),
              for (final preset in systemTermPresetChoices)
                PrismTermChoice<_SystemTermOption>(
                  value: (preset: preset, custom: false),
                  label: resolveSystemTermPreset(context.l10n, preset).singular,
                ),
              PrismTermChoice<_SystemTermOption>(
                value: (preset: null, custom: true),
                label: context.l10n.terminologySystemModeCustom,
              ),
            ],
            onSelected: (option) {
              if (option.custom) {
                notifier.setUseCustomSystemTerminology(true);
              } else if (option.preset == null) {
                notifier.setUseCustomSystemTerminology(false);
              } else {
                notifier.setSystemTermPreset(option.preset!);
              }
            },
          ),
          if (onboarding.useCustomSystemTerminology) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _customSystemSingularController,
                    hint: context.l10n.onboardingPreferencesSystemSingularHint,
                    onChanged: notifier.setCustomSystemTermSingular,
                    isDark: isDark,
                    maxLength: systemTermMaxLength,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    controller: _customSystemPluralController,
                    hint: context.l10n.onboardingPreferencesSystemPluralHint,
                    onChanged: notifier.setCustomSystemTermPlural,
                    isDark: isDark,
                    maxLength: systemTermMaxLength,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          _SectionLabel(
            label: context.l10n.onboardingPreferencesFrontingTerminology,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          PrismTermChoiceGrid<FrontingTermPreset>(
            selected: selectedFrontingPreset,
            choices: [
              for (final preset in frontingTermPresetChoices)
                PrismTermChoice<FrontingTermPreset>(
                  value: preset,
                  label: frontingTermPresetChoiceLabel(preset),
                  subtitle: frontingTermBundleForPreset(
                    preset,
                  ).activePluralLabel,
                ),
            ],
            onSelected: (preset) {
              if (preset == FrontingTermPreset.fronting) {
                notifier.resetFrontingTerms();
              } else {
                notifier.setFrontingTermPreset(preset);
              }
            },
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
    int? maxLength,
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
        maxLength: maxLength,
        onChanged: onChanged,
      ),
    );
  }

  PrismTermChoice<_TermOption> _memberChoice(
    BuildContext context,
    SystemTerminology term, {
    required bool useEnglish,
  }) {
    final labels = useEnglish
        ? _englishLabels(term)
        : term == SystemTerminology.custom
        ? (
            singular: context.l10n.terminologyCustomTermsSubtitle,
            plural: context.l10n.onboardingPreferencesCustomTerminology,
          )
        : (
            singular: resolveTerminology(context.l10n, term).singular,
            plural: resolveTerminology(context.l10n, term).plural,
          );
    return PrismTermChoice<_TermOption>(
      value: (term: term, useEnglish: useEnglish),
      label: _capFirst(labels.plural),
      subtitle: labels.singular,
      semanticLabel: '${labels.plural}, ${labels.singular}',
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

String _capFirst(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
