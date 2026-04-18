import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

/// Regression: `system_avatar_data` is a Blob column that crosses the CRDT
/// wire as base64. The adapter encode (toSyncFields) and decode (applyFields)
/// must round-trip the exact bytes.
void main() {
  group('system_settings.system_avatar_data CRDT round-trip', () {
    late database.AppDatabase db;

    setUp(() {
      db = database.AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'base64-encoded blob bytes written via applyFields survive readRow',
      () async {
        final syncAdapter = buildSyncAdapterWithCompletion(db);
        final settings = syncAdapter.adapter.entities.singleWhere(
          (e) => e.tableName == 'system_settings',
        );

        final payload = Uint8List.fromList(
          List<int>.generate(256, (i) => i & 0xff),
        );
        final encoded = base64Encode(payload);

        await settings.applyFields('singleton', {
          'system_avatar_data': encoded,
          'is_deleted': false,
        });

        final row = await (db.select(db.systemSettingsTable)
              ..where((t) => t.id.equals('singleton')))
            .getSingleOrNull();

        expect(row, isNotNull);
        expect(row!.systemAvatarData, isNotNull);
        expect(row.systemAvatarData, equals(payload));

        // And the reverse direction — readRow must emit the same base64.
        final fields = await settings.readRow('singleton');
        expect(fields, isNotNull);
        expect(fields!['system_avatar_data'], equals(encoded));
      },
    );

    test('null blob round-trips as null', () async {
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final settings = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'system_settings',
      );

      await settings.applyFields('singleton', {
        'system_avatar_data': null,
        'is_deleted': false,
      });

      final fields = await settings.readRow('singleton');
      expect(fields, isNotNull);
      expect(fields!['system_avatar_data'], isNull);
    });
  });
}
