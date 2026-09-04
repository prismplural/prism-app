import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

class FrontingDefaultsStep extends ConsumerWidget {
  const FrontingDefaultsStep({super.key});

  String _listViewModeLabel(BuildContext context, FrontingListViewMode mode) {
    return switch (mode) {
      FrontingListViewMode.combinedPeriods =>
        context.l10n.onboardingFrontingViewCombined,
      FrontingListViewMode.perMemberRows =>
        context.l10n.onboardingFrontingViewIndividual,
      FrontingListViewMode.timeline =>
        context.l10n.onboardingFrontingViewTimeline,
    };
  }

  String _listViewModeDescription(
    BuildContext context,
    FrontingListViewMode mode,
    FrontingTermBundle frontingTerms,
  ) {
    return switch (mode) {
      FrontingListViewMode.combinedPeriods =>
        context.l10n.onboardingFrontingViewCombinedDescription(
          frontingTerms.sessionPlural.toLowerCase(),
        ),
      FrontingListViewMode.perMemberRows =>
        context.l10n.onboardingFrontingViewIndividualDescription(
          frontingTerms.sessionSingular.toLowerCase(),
        ),
      FrontingListViewMode.timeline =>
        context.l10n.onboardingFrontingViewTimelineDescription(
          frontingTerms.historyLabel.toLowerCase(),
        ),
    };
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

  String _frontBehaviorDescription(
    BuildContext context,
    FrontStartBehavior behavior,
  ) {
    return switch (behavior) {
      FrontStartBehavior.additive =>
        context.l10n.onboardingFrontBehaviorAdditiveDescription,
      FrontStartBehavior.replace =>
        context.l10n.onboardingFrontBehaviorReplaceDescription,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final settings = ref
        .watch(systemSettingsProvider)
        .whenOrNull(data: (settings) => settings);
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );
    final frontingTerms = resolveFrontingTerms(
      context.l10n,
      onboarding.pendingFrontingTerms,
    );
    final listViewMode =
        onboarding.frontingListViewMode ??
        settings?.frontingListViewMode ??
        FrontingListViewMode.combinedPeriods;
    final addFrontBehavior =
        onboarding.addFrontDefaultBehavior ??
        settings?.addFrontDefaultBehavior ??
        FrontStartBehavior.additive;
    final quickFrontBehavior =
        onboarding.quickFrontDefaultBehavior ??
        settings?.quickFrontDefaultBehavior ??
        FrontStartBehavior.additive;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            label: context.l10n.onboardingFrontingDefaultsHomeViewSection,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            title: context.l10n.onboardingFrontingDefaultsHomeViewTitle,
            description: context.l10n
                .onboardingFrontingDefaultsHomeViewDescription(
                  frontingTerms.historyLabel.toLowerCase(),
                ),
            selectedDescription: _listViewModeDescription(
              context,
              listViewMode,
              frontingTerms,
            ),
            isDark: isDark,
            primary: primary,
            child: PrismSegmentedControl<FrontingListViewMode>(
              segments: FrontingListViewMode.values
                  .map(
                    (mode) => PrismSegment(
                      value: mode,
                      label: _listViewModeLabel(context, mode),
                    ),
                  )
                  .toList(),
              selected: listViewMode,
              onChanged: notifier.setFrontingListViewMode,
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(
            label: context.l10n.onboardingFrontingDefaultsStartingSection,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            title: context.l10n.onboardingAddFrontBehaviorTitle(
              frontingTerms.logAction,
            ),
            description: context.l10n.onboardingAddFrontBehaviorDescription,
            selectedDescription: _frontBehaviorDescription(
              context,
              addFrontBehavior,
            ),
            isDark: isDark,
            primary: primary,
            child: _FrontBehaviorControl(
              selected: addFrontBehavior,
              onChanged: notifier.setAddFrontDefaultBehavior,
              labelFor: (behavior) => _frontBehaviorLabel(context, behavior),
            ),
          ),
          const SizedBox(height: 12),
          _ChoiceCard(
            title: context.l10n.onboardingQuickFrontBehaviorTitle(
              frontingTerms.quickAction,
            ),
            description: context.l10n.onboardingQuickFrontBehaviorDescription(
              terms.singularLower,
              frontingTerms.currentlyActivePhrase,
            ),
            selectedDescription: _frontBehaviorDescription(
              context,
              quickFrontBehavior,
            ),
            isDark: isDark,
            primary: primary,
            child: _FrontBehaviorControl(
              selected: quickFrontBehavior,
              onChanged: notifier.setQuickFrontDefaultBehavior,
              labelFor: (behavior) => _frontBehaviorLabel(context, behavior),
            ),
          ),
        ],
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

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.description,
    required this.selectedDescription,
    required this.isDark,
    required this.primary,
    required this.child,
  });

  final String title;
  final String description;
  final String selectedDescription;
  final bool isDark;
  final Color primary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          child,
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
}

class _FrontBehaviorControl extends StatelessWidget {
  const _FrontBehaviorControl({
    required this.selected,
    required this.onChanged,
    required this.labelFor,
  });

  final FrontStartBehavior selected;
  final ValueChanged<FrontStartBehavior> onChanged;
  final String Function(FrontStartBehavior behavior) labelFor;

  @override
  Widget build(BuildContext context) {
    return PrismSegmentedControl<FrontStartBehavior>(
      segments: FrontStartBehavior.values
          .map(
            (behavior) =>
                PrismSegment(value: behavior, label: labelFor(behavior)),
          )
          .toList(),
      selected: selected,
      onChanged: onChanged,
    );
  }
}
