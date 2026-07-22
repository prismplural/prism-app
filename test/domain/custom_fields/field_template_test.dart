import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

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

  group('FieldTemplate fromDomain / toDomainFields round-trip', () {
    test('group + choice(2 colored options) + scale + slider', () {
      final group = makeField(
        id: 'g1',
        name: 'My Group',
        fieldTypeId: 'group',
        fieldType: CustomFieldType.text,
        typeConfig: const GroupConfig(icon: '🌟'),
      );
      final choice = makeField(
        id: 'c1',
        name: 'Mood',
        fieldTypeId: 'choice',
        fieldType: CustomFieldType.choice,
        parentFieldId: 'g1',
        typeConfig: const ChoiceConfig(
          options: [
            ChoiceOption(id: 'o1', label: 'Happy', colorHex: '#ff0000', sortOrder: 0),
            ChoiceOption(id: 'o2', label: 'Sad', colorHex: '#0000ff', sortOrder: 1),
          ],
          allowsMultiple: true,
        ),
      );
      final scale = makeField(
        id: 's1',
        name: 'Energy',
        fieldTypeId: 'scale',
        fieldType: CustomFieldType.text,
        parentFieldId: 'g1',
        typeConfig: const ScaleConfig(emoji: '⚡', steps: 7),
      );
      final slider = makeField(
        id: 'sl1',
        name: 'Comfort',
        fieldTypeId: 'slider',
        fieldType: CustomFieldType.text,
        typeConfig: const SliderConfig(
          mode: SliderMode.labeled,
          leftLabel: 'None',
          rightLabel: 'Full',
        ),
      );

      final template = FieldTemplate.fromDomain([group, choice, scale, slider]);

      // entries in same order
      expect(template.entries.length, 4);
      expect(template.entries[0].name, 'My Group');
      expect(template.entries[0].fieldTypeId, 'group');
      expect(template.entries[0].parentIndex, isNull);

      expect(template.entries[1].name, 'Mood');
      expect(template.entries[1].fieldTypeId, 'choice');
      expect(template.entries[1].parentIndex, 0); // points at group

      expect(template.entries[2].name, 'Energy');
      expect(template.entries[2].fieldTypeId, 'scale');
      expect(template.entries[2].parentIndex, 0);

      expect(template.entries[3].name, 'Comfort');
      expect(template.entries[3].fieldTypeId, 'slider');
      expect(template.entries[3].parentIndex, isNull); // top-level

      // option ids and sortOrder stripped from compactConfig
      final choiceConfig = template.entries[1].compactConfig!;
      final opts = choiceConfig['options'] as List<dynamic>;
      expect(opts.length, 2);
      final opt0 = opts[0] as Map<String, dynamic>;
      expect(opt0.containsKey('id'), isFalse, reason: 'id stripped');
      expect(opt0.containsKey('sortOrder'), isFalse, reason: 'sortOrder stripped');
      expect(opt0['label'], 'Happy');
      expect(opt0['colorHex'], '#ff0000');

      // defaults omitted from compactConfig
      final scaleConfig = template.entries[2].compactConfig!;
      expect(scaleConfig.containsKey('hideTitleOnProfile'), isFalse);

      // toDomainFields
      final fields = template.toDomainFields();
      expect(fields.length, 4);

      // fresh ids differ from originals
      final ids = fields.map((f) => f.id).toSet();
      expect(ids.contains('g1'), isFalse);
      expect(ids.contains('c1'), isFalse);
      expect(ids.contains('s1'), isFalse);
      expect(ids.contains('sl1'), isFalse);
      expect(ids.length, 4); // all unique

      // parent structure preserved
      expect(fields[1].parentFieldId, fields[0].id); // choice → group
      expect(fields[2].parentFieldId, fields[0].id); // scale → group
      expect(fields[3].parentFieldId, isNull);

      // names and fieldTypeIds preserved
      expect(fields[0].name, 'My Group');
      expect(fields[0].fieldTypeId, 'group');
      expect(fields[1].name, 'Mood');
      expect(fields[1].fieldTypeId, 'choice');
      expect(fields[2].name, 'Energy');
      expect(fields[2].fieldTypeId, 'scale');
      expect(fields[3].name, 'Comfort');
      expect(fields[3].fieldTypeId, 'slider');

      // config round-trips
      expect(fields[0].typeConfig, isA<GroupConfig>());
      final gc = fields[0].typeConfig! as GroupConfig;
      expect(gc.icon, '🌟');

      expect(fields[1].typeConfig, isA<ChoiceConfig>());
      final cc = fields[1].typeConfig! as ChoiceConfig;
      expect(cc.options.length, 2);
      expect(cc.options[0].label, 'Happy');
      expect(cc.options[0].colorHex, '#ff0000');
      expect(cc.options[1].label, 'Sad');
      expect(cc.options[1].colorHex, '#0000ff');
      // fresh option ids assigned
      expect(cc.options[0].id, isNotEmpty);
      expect(cc.options[1].id, isNotEmpty);
      expect(cc.options[0].id, isNot(cc.options[1].id));
      // sortOrder restored from array index
      expect(cc.options[0].sortOrder, 0);
      expect(cc.options[1].sortOrder, 1);
      expect(cc.allowsMultiple, isTrue);

      expect(fields[2].typeConfig, isA<ScaleConfig>());
      final sc = fields[2].typeConfig! as ScaleConfig;
      expect(sc.emoji, '⚡');
      expect(sc.steps, 7);

      expect(fields[3].typeConfig, isA<SliderConfig>());
      final slc = fields[3].typeConfig! as SliderConfig;
      expect(slc.mode, SliderMode.labeled);
      expect(slc.leftLabel, 'None');
      expect(slc.rightLabel, 'Full');

      // createdAt is recent
      expect(
        fields[0].createdAt.isAfter(now.subtract(const Duration(seconds: 5))),
        isTrue,
      );

      // displayOrder = 0
      for (final f in fields) {
        expect(f.displayOrder, 0);
      }
    });

    test('unknown typeConfigRaw round-trips untouched', () {
      const rawJson = '{"runtimeType":"futureThing","fancyKey":42}';
      final field = makeField(
        id: 'u1',
        name: 'Future Field',
        fieldTypeId: 'futureThing',
        fieldType: CustomFieldType.text,
        unknownTypeConfigRaw: rawJson,
      );

      final template = FieldTemplate.fromDomain([field]);
      expect(template.entries[0].rawConfigJson, rawJson);
      expect(template.entries[0].compactConfig, isNull);

      final fields = template.toDomainFields();
      expect(fields[0].unknownTypeConfigRaw, rawJson);
      expect(fields[0].typeConfig, isNull);
    });

    test('single non-group field — no parentIndex', () {
      final field = makeField(
        id: 'tx1',
        name: 'Notes',
        fieldTypeId: 'text',
        fieldType: CustomFieldType.text,
        typeConfig: const TextConfig(),
      );

      final template = FieldTemplate.fromDomain([field]);
      expect(template.entries[0].parentIndex, isNull);

      final fields = template.toDomainFields();
      expect(fields[0].parentFieldId, isNull);
      expect(fields[0].fieldTypeId, 'text');
    });

    test('child whose parent is not in list is promoted (parentIndex null)', () {
      final child = makeField(
        id: 'child1',
        name: 'Orphaned Child',
        fieldTypeId: 'text',
        fieldType: CustomFieldType.text,
        parentFieldId: 'missing-parent-id',
      );

      final template = FieldTemplate.fromDomain([child]);
      // Parent not in list → promoted to top-level
      expect(template.entries[0].parentIndex, isNull);

      final fields = template.toDomainFields();
      expect(fields[0].parentFieldId, isNull);
    });

    test('omits hideTitleOnProfile:false and empty extra from compactConfig', () {
      final field = makeField(
        id: 'sc1',
        name: 'Scale',
        fieldTypeId: 'scale',
        fieldType: CustomFieldType.text,
        typeConfig: const ScaleConfig(hideTitleOnProfile: false),
      );

      final template = FieldTemplate.fromDomain([field]);
      final config = template.entries[0].compactConfig!;
      expect(config.containsKey('hideTitleOnProfile'), isFalse);
      expect(config.containsKey('extra'), isFalse);
    });

    test('preserves hideTitleOnProfile:true in compactConfig', () {
      final field = makeField(
        id: 'sc2',
        name: 'Scale',
        fieldTypeId: 'scale',
        fieldType: CustomFieldType.text,
        typeConfig: const ScaleConfig(hideTitleOnProfile: true),
      );

      final template = FieldTemplate.fromDomain([field]);
      final config = template.entries[0].compactConfig!;
      expect(config['hideTitleOnProfile'], isTrue);
    });

    test('version is 1', () {
      final field = makeField(
        id: 'tx2',
        name: 'X',
        fieldTypeId: 'text',
        fieldType: CustomFieldType.text,
      );
      final template = FieldTemplate.fromDomain([field]);
      expect(template.version, 1);
    });

    test('legacy type field type enum derived correctly via registry', () {
      final choiceField = makeField(
        id: 'ch1',
        name: 'Pick',
        fieldTypeId: 'choice',
        fieldType: CustomFieldType.choice,
        typeConfig: const ChoiceConfig(),
      );

      final template = FieldTemplate.fromDomain([choiceField]);
      final fields = template.toDomainFields();
      expect(fields[0].fieldType, CustomFieldType.choice);
    });

    test('unknown fieldTypeId falls back to text enum, preserves fieldTypeId', () {
      const rawJson = '{"runtimeType":"mysteryType"}';
      final field = makeField(
        id: 'unk1',
        name: 'Mystery',
        fieldTypeId: 'mysteryType',
        fieldType: CustomFieldType.text,
        unknownTypeConfigRaw: rawJson,
      );

      final template = FieldTemplate.fromDomain([field]);
      final fields = template.toDomainFields();
      expect(fields[0].fieldType, CustomFieldType.text); // fallback
      expect(fields[0].fieldTypeId, 'mysteryType'); // preserved
    });
  });

  // ── Fix 4: datePrecision round-trip ─────────────────────────────────────────

  group('Fix4: datePrecision round-trip', () {
    test('date field with year precision survives fromDomain→toDomainFields', () {
      final field = makeField(
        id: 'd1',
        name: 'Birthday',
        fieldTypeId: 'date',
        fieldType: CustomFieldType.date,
      ).copyWith(datePrecision: DatePrecision.year);

      final template = FieldTemplate.fromDomain([field]);
      final fields = template.toDomainFields();
      expect(fields[0].datePrecision, DatePrecision.year);
    });

    test('date field with timestamp precision survives round-trip', () {
      final field = makeField(
        id: 'd2',
        name: 'Logged At',
        fieldTypeId: 'date',
        fieldType: CustomFieldType.date,
      ).copyWith(datePrecision: DatePrecision.timestamp);

      final template = FieldTemplate.fromDomain([field]);
      final fields = template.toDomainFields();
      expect(fields[0].datePrecision, DatePrecision.timestamp);
    });

    test('date field with null precision stays null', () {
      final field = makeField(
        id: 'd3',
        name: 'Date',
        fieldTypeId: 'date',
        fieldType: CustomFieldType.date,
      );

      final template = FieldTemplate.fromDomain([field]);
      final fields = template.toDomainFields();
      expect(fields[0].datePrecision, isNull);
    });

    test('datePrecision survives toJson/fromJson round-trip', () {
      final field = makeField(
        id: 'd4',
        name: 'Anniversary',
        fieldTypeId: 'date',
        fieldType: CustomFieldType.date,
      ).copyWith(datePrecision: DatePrecision.monthYear);

      final original = FieldTemplate.fromDomain([field]);
      final json = original.toJson();
      final restored = FieldTemplate.fromJson(json);
      final fields = restored.toDomainFields();
      expect(fields[0].datePrecision, DatePrecision.monthYear);
    });

    test('non-date field: datePrecision not emitted, not restored', () {
      final field = makeField(
        id: 'tx5',
        name: 'Notes',
        fieldTypeId: 'text',
        fieldType: CustomFieldType.text,
      );

      final template = FieldTemplate.fromDomain([field]);
      expect(template.entries[0].datePrecision, isNull);
      final fields = template.toDomainFields();
      expect(fields[0].datePrecision, isNull);
    });
  });

  group('FieldTemplate JSON serialization (raw toJson/fromJson)', () {
    test('toJson / fromJson round-trip', () {
      final group = makeField(
        id: 'g1',
        name: 'Group',
        fieldTypeId: 'group',
        fieldType: CustomFieldType.text,
        typeConfig: const GroupConfig(icon: '🌟'),
      );
      final child = makeField(
        id: 'c1',
        name: 'Choice',
        fieldTypeId: 'choice',
        fieldType: CustomFieldType.choice,
        parentFieldId: 'g1',
        typeConfig: const ChoiceConfig(
          options: [
            ChoiceOption(id: 'o1', label: 'A', sortOrder: 0),
          ],
        ),
      );

      final original = FieldTemplate.fromDomain([group, child]);
      final json = original.toJson();
      final restored = FieldTemplate.fromJson(json);

      expect(restored.version, original.version);
      expect(restored.entries.length, original.entries.length);
      expect(restored.entries[0].name, original.entries[0].name);
      expect(restored.entries[1].parentIndex, original.entries[1].parentIndex);

      // Decode domain fields again — should produce same structure
      final fields = restored.toDomainFields();
      expect(fields[0].name, 'Group');
      expect(fields[1].parentFieldId, fields[0].id);
    });
  });
}
