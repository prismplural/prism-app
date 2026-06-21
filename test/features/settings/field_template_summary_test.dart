import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/settings/widgets/field_template_summary.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  final now = DateTime.now();

  CustomField makeField({
    required String id,
    required String name,
    required String fieldTypeId,
    required CustomFieldType fieldType,
    String? parentFieldId,
    CustomFieldTypeConfig? typeConfig,
    String? unknownTypeConfigRaw,
  }) => CustomField(
    id: id,
    name: name,
    fieldType: fieldType,
    createdAt: now,
    fieldTypeId: fieldTypeId,
    parentFieldId: parentFieldId,
    typeConfig: typeConfig,
    unknownTypeConfigRaw: unknownTypeConfigRaw,
  );

  test('summary surfaces names, swatches, scale emoji, groups, unknown types', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final group = makeField(
      id: 'g',
      name: 'Stats',
      fieldTypeId: 'group',
      fieldType: CustomFieldType.text,
      typeConfig: const GroupConfig(),
    );
    final choice = makeField(
      id: 'c',
      name: 'Mood',
      fieldTypeId: 'choice',
      fieldType: CustomFieldType.choice,
      parentFieldId: 'g',
      typeConfig: const ChoiceConfig(
        options: [
          ChoiceOption(id: 'o1', label: 'Happy', colorHex: '#ff0000'),
          ChoiceOption(id: 'o2', label: 'Sad'),
        ],
      ),
    );
    final scale = makeField(
      id: 's',
      name: 'Power',
      fieldTypeId: 'scale',
      fieldType: CustomFieldType.text,
      parentFieldId: 'g',
      typeConfig: const ScaleConfig(emoji: '⚡', steps: 7),
    );
    final unknown = makeField(
      id: 'u',
      name: 'Future',
      fieldTypeId: 'futurething',
      fieldType: CustomFieldType.text,
      unknownTypeConfigRaw: '{"x":1}',
    );

    final template = FieldTemplate.fromDomain([group, choice, scale, unknown]);
    final items = summarizeFieldTemplate(l10n, template, groupNameFallback: 'Untitled');

    expect(items.map((i) => i.name).toList(), ['Stats', 'Mood', 'Power', 'Future']);

    expect(items[0].isGroup, isTrue);
    expect(items[0].isChild, isFalse);

    // Only the option that carries a colorHex contributes a swatch.
    expect(items[1].isChild, isTrue);
    expect(items[1].swatches.length, 1);

    expect(items[2].scaleEmoji, '⚡');
    expect(items[2].scaleSteps, 7);

    // Unknown future type: imports as-is, labelled by its raw id.
    expect(items[3].isUnknownType, isTrue);
    expect(items[3].typeLabel, 'futurething');
  });
}
