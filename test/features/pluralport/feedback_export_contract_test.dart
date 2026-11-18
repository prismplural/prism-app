import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';

void main() {
  Json member({String color = 'A1B2C3', bool enabled = true}) => {
    'id': 'synthetic-member',
    'name': 'Synthetic',
    'customColorEnabled': enabled,
    'customColorHex': color,
  };
  PluralPortExporter exporter(Json row) => PluralPortExporter({
    'headmates': [row],
  }, '00000000-0000-4000-8000-000000000001');

  test('contract: UI-style RGB member color exports as portable HexColor', () {
    final row = exporter(member()).convert('members', member());
    expect(row['color'], '#A1B2C3');
  });

  test('counterexample: already-prefixed member color is portable', () {
    final row = member(color: '#A1B2C3');
    expect(exporter(row).convert('members', row)['color'], '#A1B2C3');
  });

  test('disabled custom color is intentionally absent', () {
    final row = member(enabled: false);
    expect(exporter(row).convert('members', row)['color'], isNull);
  });

  test('supported choice projects portable labels, not opaque native IDs', () {
    final definition = <String, dynamic>{
      'id': 'choice',
      'name': 'Synthetic choice',
      'fieldType': 4,
      'fieldTypeId': 'choice',
      'typeConfigJson': jsonEncode({
        'runtimeType': 'choice',
        'allowsMultiple': false,
        'options': [
          {'id': 'option-a', 'label': 'Alpha'},
        ],
      }),
    };
    final codec = exporter(member());
    final field = codec.convert('custom_fields', definition);
    expect(field['field_type'], 'select');
    expect(field['options'], ['Alpha']);
    final value = codec.convert('custom_field_values', {
      'id': 'value',
      'customFieldId': 'choice',
      'memberId': 'synthetic-member',
      'value': jsonEncode({
        'options': ['option-a'],
      }),
    }, fieldDefinition: definition);
    expect(value['value'], 'Alpha');
  });

  test(
    'unsupported slider intentionally projects JSON and retains native evidence',
    () {
      final definition = <String, dynamic>{
        'id': 'slider',
        'name': 'Synthetic slider',
        'fieldTypeId': 'slider',
        'typeConfigJson': jsonEncode({'runtimeType': 'slider', 'max': 10}),
      };
      final codec = exporter(member());
      final field = codec.convert('custom_fields', definition);
      expect(field['field_type'], 'json');
      expect(
        ((field['extensions'] as Map)['prism'] as Map)['native'],
        definition,
      );
      final value = codec.convert('custom_field_values', {
        'id': 'value',
        'customFieldId': 'slider',
        'memberId': 'synthetic-member',
        'value': jsonEncode({'value': 7}),
      }, fieldDefinition: definition);
      expect(value['value'], {'value': 7});
    },
  );

  test('synthetic PNG survives extensionless ZIP asset without encryption', () {
    final png = image.encodePng(image.Image(width: 1, height: 1));
    final row = {...member(), 'profilePhotoData': base64Encode(png)};
    final bundle = exporter(row).build([]);
    final decoded = PluralPortBundle.decode(bundle.encode());
    final record = PluralPortMapper.rows(decoded.envelope, 'members').single;
    final asset = PluralPortMapper.rows(
      decoded.envelope,
      'assets',
    ).singleWhere((a) => a['id'] == record['avatar_asset_id']);
    final path = asset['bundle_path'] as String;
    expect(path, matches(RegExp(r'^assets/[0-9a-f]{64}$')));
    final bytes = decoded.files[path]!;
    expect(bytes, orderedEquals(png));
    expect(image.decodePng(bytes)!.width, 1);
    expect(asset['mime_type'], isNull); // profile exporter currently omits it
    expect(
      asset['data_base64'],
      isNull,
    ); // ZIP proposal, not inline JSON transport
    expect(decoded.envelope['pluralport_version'], '0.1');
    expect(decoded.envelope.containsKey('openplural_version'), isFalse);
  });
}
