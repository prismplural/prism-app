import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_term_choice_grid.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

typedef _TermOption = ({SystemTerminology term, bool useEnglish});

/// Widget for selecting the system's preferred terminology for members.
///
/// In non-English device locales the picker shows both the translated options
/// and a second "In English" section, so Spanglish (and equivalent) users can
/// pick a standard English term while keeping the rest of the UI in their
/// language.
class TerminologyPicker extends ConsumerStatefulWidget {
  const TerminologyPicker({
    required this.current,
    this.currentUseEnglish = false,
    this.customTerminology,
    this.customPluralTerminology,
    super.key,
  });

  final SystemTerminology current;
  final bool currentUseEnglish;
  final String? customTerminology;
  final String? customPluralTerminology;

  @override
  ConsumerState<TerminologyPicker> createState() => _TerminologyPickerState();
}

class _TerminologyPickerState extends ConsumerState<TerminologyPicker> {
  late SystemTerminology _selected;
  late bool _useEnglish;
  late TextEditingController _customController;
  late TextEditingController _customPluralController;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _useEnglish = widget.currentUseEnglish;
    _customController = TextEditingController(
      text: widget.customTerminology ?? '',
    );
    _customPluralController = TextEditingController(
      text: widget.customPluralTerminology ?? '',
    );
  }

  @override
  void didUpdateWidget(TerminologyPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      _selected = widget.current;
    }
    if (oldWidget.currentUseEnglish != widget.currentUseEnglish) {
      _useEnglish = widget.currentUseEnglish;
    }
    if (oldWidget.customTerminology != widget.customTerminology) {
      _customController.text = widget.customTerminology ?? '';
    }
    if (oldWidget.customPluralTerminology != widget.customPluralTerminology) {
      _customPluralController.text = widget.customPluralTerminology ?? '';
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _customPluralController.dispose();
    super.dispose();
  }

  void _onChanged(_TermOption option) {
    setState(() {
      _selected = option.term;
      _useEnglish = option.useEnglish;
    });
    ref
        .read(settingsNotifierProvider.notifier)
        .updateTerminology(
          option.term,
          customTerminology: option.term == SystemTerminology.custom
              ? _customController.text
              : null,
          customPluralTerminology: option.term == SystemTerminology.custom
              ? _customPluralController.text
              : null,
          useEnglish: option.useEnglish,
        );
  }

  void _onCustomSubmitted() {
    ref
        .read(settingsNotifierProvider.notifier)
        .updateTerminology(
          SystemTerminology.custom,
          customTerminology: _customController.text.trim(),
          customPluralTerminology: _customPluralController.text.trim(),
          useEnglish: false,
        );
  }

  /// Localized (singular, plural) labels for the given terminology option.
  ({String singular, String plural}) _localizedLabels(
    BuildContext context,
    SystemTerminology t,
  ) {
    return switch (t) {
      SystemTerminology.members => (
        singular: context.l10n.settingsTerminologyOptionMembersSingular,
        plural: context.l10n.settingsTerminologyOptionMembers,
      ),
      SystemTerminology.headmates => (
        singular: context.l10n.settingsTerminologyOptionHeadmatesSingular,
        plural: context.l10n.settingsTerminologyOptionHeadmates,
      ),
      SystemTerminology.alters => (
        singular: context.l10n.settingsTerminologyOptionAltersSingular,
        plural: context.l10n.settingsTerminologyOptionAlters,
      ),
      SystemTerminology.parts => (
        singular: context.l10n.settingsTerminologyOptionPartsSingular,
        plural: context.l10n.settingsTerminologyOptionParts,
      ),
      SystemTerminology.facets => (
        singular: context.l10n.settingsTerminologyOptionFacetsSingular,
        plural: context.l10n.settingsTerminologyOptionFacets,
      ),
      SystemTerminology.custom => (
        singular: context.l10n.terminologyCustomTermsSubtitle,
        plural: context.l10n.settingsTerminologyOptionCustom,
      ),
    };
  }

  /// Hardcoded English (singular, plural) labels — always English regardless
  /// of device locale.
  static ({String singular, String plural}) _englishLabels(
    SystemTerminology t,
  ) {
    return switch (t) {
      SystemTerminology.members => (singular: 'member', plural: 'Members'),
      SystemTerminology.headmates => (
        singular: 'headmate',
        plural: 'Headmates',
      ),
      SystemTerminology.alters => (singular: 'alter', plural: 'Alters'),
      SystemTerminology.parts => (singular: 'part', plural: 'Parts'),
      SystemTerminology.facets => (singular: 'facet', plural: 'Facets'),
      SystemTerminology.custom => (singular: 'custom term', plural: 'Custom'),
    };
  }

  PrismTermChoice<_TermOption> _choice(
    BuildContext context,
    SystemTerminology term, {
    required bool useEnglish,
  }) {
    final labels = useEnglish
        ? _englishLabels(term)
        : _localizedLabels(context, term);
    return PrismTermChoice<_TermOption>(
      value: (term: term, useEnglish: useEnglish),
      label: labels.plural,
      subtitle: labels.singular,
      semanticLabel: '${labels.plural}, ${labels.singular}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    const standardTerms = [
      SystemTerminology.members,
      SystemTerminology.headmates,
      SystemTerminology.alters,
      SystemTerminology.parts,
      SystemTerminology.facets,
    ];
    // In English locale all items use useEnglish:false — normalize so the
    // selection always matches an item even if the user previously picked an
    // English-labelled term while in a non-English locale.
    final currentValue = (
      term: _selected,
      useEnglish: isEnglish ? false : _useEnglish,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrismTermChoiceGrid<_TermOption>(
          density: PrismTermChoiceGridDensity.compact,
          selected: currentValue,
          choices: [
            for (final term in standardTerms)
              _choice(context, term, useEnglish: false),
            if (isEnglish)
              _choice(context, SystemTerminology.custom, useEnglish: false),
          ],
          onSelected: _onChanged,
        ),
        if (!isEnglish) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.terminologyEnglishOptionsLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          PrismTermChoiceGrid<_TermOption>(
            density: PrismTermChoiceGridDensity.compact,
            selected: currentValue,
            choices: [
              for (final term in standardTerms)
                _choice(context, term, useEnglish: true),
            ],
            onSelected: _onChanged,
          ),
          const SizedBox(height: 8),
          PrismTermChoiceGrid<_TermOption>(
            density: PrismTermChoiceGridDensity.compact,
            selected: currentValue,
            choices: [
              _choice(context, SystemTerminology.custom, useEnglish: false),
            ],
            onSelected: _onChanged,
          ),
        ],
        if (_selected == SystemTerminology.custom) ...[
          const SizedBox(height: 12),
          PrismTextField(
            controller: _customController,
            labelText: context.l10n.settingsTerminologyCustomSingularLabel,
            hintText: context.l10n.settingsTerminologyCustomSingularHint,
            isDense: true,
            onSubmitted: (_) => _onCustomSubmitted(),
            onChanged: (_) => _onCustomSubmitted(),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: _customPluralController,
            labelText: context.l10n.settingsTerminologyCustomPluralLabel,
            hintText: _customController.text.isNotEmpty
                ? '${_customController.text}s'
                : context.l10n.settingsTerminologyCustomPluralHint,
            isDense: true,
            onSubmitted: (_) => _onCustomSubmitted(),
            onChanged: (_) => _onCustomSubmitted(),
            textInputAction: TextInputAction.done,
          ),
        ],

        // Live preview
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.settingsTerminologyPreviewLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '"${context.l10n.terminologyAddButton(terms.singular)}" \u2022 "${terms.plural}" \u2022 "${context.l10n.terminologySelectPrompt(terms.singularLower)}"',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
