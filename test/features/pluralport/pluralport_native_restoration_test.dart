import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'harness.dart';

void main() {
  test('rejects an empty resolved Prism identity', () {
    final bundle = PluralPortBundle({
      'pluralport_version': '0.1',
      'producer': {'app': 'Prism'},
      'members': [
        {
          'id': 'valid',
          'name': 'M',
          'source_refs': [
            {'app': 'prism', 'collection': 'headmates', 'id': ''},
          ],
        },
      ],
    });
    expect(() => PluralPortMapper.plan(bundle), throwsFormatException);
  });
  for (final key in ['reminders', 'conversationCategories', 'friends']) {
    test('reimport respects deleted $key', () async {
      final db = makeDb();
      addTearDown(db.close);
      final native =
          jsonDecode(
                File(
                  'test/features/pluralport/fixtures/complex_native.json',
                ).readAsStringSync(),
              )
              as Json;
      final records = (native[key] as List)
          .map(
            (r) =>
                Map<String, dynamic>.from(r as Map)..remove('targetMemberId'),
          )
          .toList();
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
        supportDirectory: () async => Directory.systemTemp,
      );
      final bundle = PluralPortBundle({
        'pluralport_version': '0.1',
        'producer': {'app': 'Prism'},
        'extensions': {
          'prism': {
            'native_modules': {key: records},
          },
        },
      });
      await service.importPlan(PluralPortMapper.plan(bundle));
      final table = {
        'reminders': 'reminders',
        'conversationCategories': 'conversation_categories',
        'friends': 'friends',
      }[key]!;
      await db.customStatement('UPDATE $table SET is_deleted = 1');
      await service.importPlan(PluralPortMapper.plan(bundle));
      expect(
        await db
            .customSelect('SELECT id FROM $table WHERE is_deleted = 0')
            .get(),
        isEmpty,
      );
      final exported = await service.exportBundle();
      final modules =
          ((exported.envelope['extensions'] as Map)['prism']
                  as Map)['native_modules']
              as Map;
      expect(modules[key], isEmpty);
    });
  }
  for (final family in ['headmates', 'customFields']) {
    test('rejects self-parenting native $family before writing', () {
      final native = PluralPortMapper.emptyNative();
      native[family] = [
        {
          'id': 'row',
          'name': 'Row',
          'createdAt': '2026-01-01T00:00:00Z',
          if (family == 'headmates') 'parentSystemId': 'row',
          if (family == 'customFields') 'parentFieldId': 'row',
          if (family == 'customFields') 'fieldType': 0,
        },
      ];
      final bundle = PluralPortExporter(native, 'system').build([]);
      expect(() => PluralPortMapper.plan(bundle), throwsFormatException);
    });
  }
}
