import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
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

  /// Localized (plural, singular) labels for the given terminology option.
  (String, String) _localizedLabels(BuildContext context, SystemTerminology t) {
    return switch (t) {
      SystemTerminology.members => (
          context.l10n.settingsTerminologyOptionMembers,
          context.l10n.settingsTerminologyOptionMembersSingular,
        ),
      SystemTerminology.headmates => (
          context.l10n.settingsTerminologyOptionHeadmates,
          context.l10n.settingsTerminologyOptionHeadmatesSingular,
        ),
      SystemTerminology.alters => (
          context.l10n.settingsTerminologyOptionAlters,
          context.l10n.settingsTerminologyOptionAltersSingular,
        ),
      SystemTerminology.parts => (
          context.l10n.settingsTerminologyOptionParts,
          context.l10n.settingsTerminologyOptionPartsSingular,
        ),
      SystemTerminology.facets => (
          context.l10n.settingsTerminologyOptionFacets,
          context.l10n.settingsTerminologyOptionFacetsSingular,
        ),
      SystemTerminology.custom => (
          context.l10n.settingsTerminologyOptionCustom,
          context.l10n.settingsTerminologyOptionCustomSingular,
        ),
    };
  }

  /// Hardcoded English (plural, singular) labels — always English regardless
  /// of device locale.
  static (String, String) _englishLabels(SystemTerminology t) {
    return switch (t) {
      SystemTerminology.members => ('Members', 'member'),
      SystemTerminology.headmates => ('Headmates', 'headmate'),
      SystemTerminology.alters => ('Alters', 'alter'),
      SystemTerminology.parts => ('Parts', 'part'),
      SystemTerminology.facets => ('Facets', 'facet'),
      SystemTerminology.custom => ('Custom', 'custom term'),
    };
  }

  List<PrismSelectItem<_TermOption>> _buildItems(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isEnglish = locale.languageCode == 'en';

    // Standard terms (no custom in this list — custom is always at bottom)
    const standardTerms = [
      SystemTerminology.members,
      SystemTerminology.headmates,
      SystemTerminology.alters,
      SystemTerminology.parts,
      SystemTerminology.facets,
    ];

    PrismSelectItem<_TermOption> localizedItem(SystemTerminology t) {
      final (label, singular) = _localizedLabels(context, t);
      return PrismSelectItem(
        value: (term: t, useEnglish: false),
        label: label,
        subtitle: singular,
        fieldLabel: '$label ($singular)',
      );
    }

    PrismSelectItem<_TermOption> englishItem(SystemTerminology t) {
      final (label, singular) = _englishLabels(t);
      return PrismSelectItem(
        value: (term: t, useEnglish: true),
        label: label,
        subtitle: singular,
        fieldLabel: '$label ($singular)',
      );
    }

    final items = <PrismSelectItem<_TermOption>>[];

    if (isEnglish) {
      // English locale: just the 5 standard options (localized == English)
      items.addAll(standardTerms.map(localizedItem));
    } else {
      // Non-English locale: translated section, then English section
      items.addAll(standardTerms.map(localizedItem));
      items.add(PrismSelectItem(
        value: (term: SystemTerminology.custom, useEnglish: true), // sentinel
        label: context.l10n.terminologyEnglishOptionsLabel,
        isHeader: true,
      ));
      items.addAll(standardTerms.map(englishItem));
    }

    // Custom is always last — never deduplicated or hidden
    final (customLabel, customSingular) =
        _localizedLabels(context, SystemTerminology.custom);
    items.add(PrismSelectItem(
      value: (term: SystemTerminology.custom, useEnglish: false),
      label: customLabel,
      subtitle: customSingular,
      fieldLabel: '$customLabel ($customSingular)',
    ));

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final currentValue = (term: _selected, useEnglish: _useEnglish);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrismSelect<_TermOption>(
          value: currentValue,
          labelText: context.l10n.settingsTerminologyPickerLabel,
          isDense: true,
          items: _buildItems(context),
          onChanged: (value) {
            if (value != null) _onChanged(value);
          },
        ),
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
            borderRadius: BorderRadius.circular(8),
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
