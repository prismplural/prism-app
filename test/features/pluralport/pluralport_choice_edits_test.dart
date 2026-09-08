import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';

Json _source({required bool multiselect, required List<String> selection}) => {
  'pluralport_version': '0.1',
  'producer': {'app': 'Example', 'app_id': 'example'},
  'systems': [
    {'id': 'system', 'name': 'System'},
  ],
  'members': [
    {'id': 'member', 'system_id': 'system', 'name': 'Member'},
  ],
  'custom_fields': [
    {
      'id': 'field',
      'system_id': 'system',
      'name': 'Choice',
      'field_type': multiselect ? 'multiselect' : 'select',
      'options': ['A', 'B'],
    },
  ],
  'custom_field_values': [
    {
      'id': 'value',
      'field_id': 'field',
      'subject_type': 'member',
      'subject_id': 'member',
      'value': multiselect ? selection : selection.single,
      'extensions': {
        'foreign': {
          'future_choice_data': {'keep': true},
        },
      },
    },
  ],
};

PluralPortBundle _exportAfterEdit(
  Json source,
  void Function(Json config, Json value) edit,
) {
  final plan = PluralPortMapper.plan(PluralPortBundle(source));
  final native = PluralPortMapper.clone(plan.native);
  final field = PluralPortMapper.rows(native, 'customFields').single;
  final config = (jsonDecode(field['typeConfigJson'] as String) as Map)
      .cast<String, dynamic>();
  final value = PluralPortMapper.rows(native, 'customFieldValues').single;
  edit(config, value);
  field['typeConfigJson'] = jsonEncode(config);
  return PluralPortExporter(native, 'local').build([plan.archive]);
}

List<String> _selectedLabels(Json native) {
  final field = PluralPortMapper.rows(native, 'customFields').single;
  final config = jsonDecode(field['typeConfigJson'] as String) as Map;
  final labels = {
    for (final option in (config['options'] as List).cast<Map>())
      option['id']: option['label'],
  };
  final value = PluralPortMapper.rows(native, 'customFieldValues').single;
  final selected = jsonDecode(value['value'] as String) as Map;
  return (selected['options'] as List)
      .map((id) => labels[id] as String)
      .toList();
}

void main() {
  test('select choice values follow renamed options through reimport', () {
    final bundle = _exportAfterEdit(
      _source(multiselect: false, selection: ['A']),
      (config, _) {
        ((config['options'] as List).first as Map)['label'] = 'Renamed';
      },
    );

    expect(
      PluralPortMapper.rows(bundle.envelope, 'custom_fields').single['options'],
      ['Renamed', 'B'],
    );
    expect(
      PluralPortMapper.rows(
        bundle.envelope,
        'custom_field_values',
      ).single['value'],
      'Renamed',
    );
    final reimport = PluralPortMapper.plan(bundle);
    expect(_selectedLabels(reimport.native), ['Renamed']);
  });

  test('multiselect values follow simultaneous option and value edits', () {
    final bundle = _exportAfterEdit(
      _source(multiselect: false, selection: ['A']),
      (config, value) {
        config['allowsMultiple'] = true;
        ((config['options'] as List).first as Map)['label'] = 'Renamed';
        final secondId = ((config['options'] as List)[1] as Map)['id'];
        value['value'] = jsonEncode({
          'options': [secondId],
        });
      },
    );

    expect(
      PluralPortMapper.rows(
        bundle.envelope,
        'custom_fields',
      ).single['field_type'],
      'multiselect',
    );
    expect(
      PluralPortMapper.rows(
        bundle.envelope,
        'custom_field_values',
      ).single['value'],
      ['B'],
    );
    final reimport = PluralPortMapper.plan(bundle);
    expect(_selectedLabels(reimport.native), ['B']);
  });

  test(
    'deleted options are removed from multiselect values without dropping metadata',
    () {
      final bundle = _exportAfterEdit(
        _source(multiselect: true, selection: ['A', 'B']),
        (config, _) {
          ((config['options'] as List).first as Map)['isDeleted'] = true;
        },
      );

      expect(
        PluralPortMapper.rows(
          bundle.envelope,
          'custom_fields',
        ).single['options'],
        ['B'],
      );
      final value = PluralPortMapper.rows(
        bundle.envelope,
        'custom_field_values',
      ).single;
      expect(value['value'], ['B']);
      expect(
        ((value['extensions'] as Map)['foreign'] as Map)['future_choice_data'],
        {'keep': true},
      );
      final reimport = PluralPortMapper.plan(bundle);
      expect(_selectedLabels(reimport.native), ['B']);
    },
  );
}
