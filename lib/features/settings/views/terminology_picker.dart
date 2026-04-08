import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

/// Labels and descriptions for each terminology option.
const _terminologyLabels = <SystemTerminology, (String, String)>{
  SystemTerminology.members: ('Members', 'member'),
  SystemTerminology.headmates: ('Headmates', 'headmate'),
  SystemTerminology.alters: ('Alters', 'alter'),
  SystemTerminology.parts: ('Parts', 'part'),
  SystemTerminology.facets: ('Facets', 'facet'),
  SystemTerminology.custom: ('Custom', 'custom term'),
};

/// Widget for selecting the system's preferred terminology for members.
///
/// Uses a [PrismSelect] with optional custom text fields
/// when [SystemTerminology.custom] is selected. Shows a live preview
/// of how the terminology will appear in the app.
class TerminologyPicker extends ConsumerStatefulWidget {
  const TerminologyPicker({
    required this.current,
    this.customTerminology,
    this.customPluralTerminology,
    super.key,
  });

  final SystemTerminology current;
  final String? customTerminology;
  final String? customPluralTerminology;

  @override
  ConsumerState<TerminologyPicker> createState() => _TerminologyPickerState();
}

class _TerminologyPickerState extends ConsumerState<TerminologyPicker> {
  late SystemTerminology _selected;
  late TextEditingController _customController;
  late TextEditingController _customPluralController;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
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

  void _onChanged(SystemTerminology? value) {
    if (value == null) return;
    setState(() => _selected = value);
    ref
        .read(settingsNotifierProvider.notifier)
        .updateTerminology(
          value,
          customTerminology: value == SystemTerminology.custom
              ? _customController.text
              : null,
          customPluralTerminology: value == SystemTerminology.custom
              ? _customPluralController.text
              : null,
        );
  }

  void _onCustomSubmitted() {
    ref
        .read(settingsNotifierProvider.notifier)
        .updateTerminology(
          SystemTerminology.custom,
          customTerminology: _customController.text.trim(),
          customPluralTerminology: _customPluralController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = ref.watch(terminologyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrismSelect<SystemTerminology>(
          value: _selected,
          labelText: 'Terminology',
          isDense: true,
          items: SystemTerminology.values.map((t) {
            final (label, singular) = _terminologyLabels[t]!;
            return PrismSelectItem(
              value: t,
              label: label,
              subtitle: singular,
              fieldLabel: '$label ($singular)',
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) _onChanged(value);
          },
        ),
        if (_selected == SystemTerminology.custom) ...[
          const SizedBox(height: 12),
          PrismTextField(
            controller: _customController,
            labelText: 'Custom term (singular)',
            hintText: 'e.g. fragment',
            isDense: true,
            onSubmitted: (_) => _onCustomSubmitted(),
            onChanged: (_) => _onCustomSubmitted(),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: _customPluralController,
            labelText: 'Custom term (plural)',
            hintText: _customController.text.isNotEmpty
                ? '${_customController.text}s'
                : 'e.g. fragments',
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
                'Preview',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '"${terms.addButtonText}" \u2022 "${terms.plural}" \u2022 "${terms.selectText}"',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
