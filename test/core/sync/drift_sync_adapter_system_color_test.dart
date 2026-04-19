import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

/// Regression: `system_color` is a nullable TEXT column on `system_settings`
/// that sync'd devices must agree on. The adapter encode (toSyncFields /
/// readRow) and decode (applyFields) must round-trip the value faithfully
/// — including the null case.
void main() {
  group('system_settings.system_color CRDT round-trip', () {
    late database.AppDatabase db;

    setUp(() {
      db = database.AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('remote system_color change applies and round-trips', () async {
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final settings = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'system_settings',
      );

      await settings.applyFields('singleton', {
        'system_color': 'ff0000',
        'is_deleted': false,
      });

      final row = await (db.select(db.systemSettingsTable)
            ..where((t) => t.id.equals('singleton')))
          .getSingleOrNull();

      expect(row, isNotNull);
      expect(row!.systemColor, 'ff0000');

      // Reverse direction — readRow must emit the same value.
      final fields = await settings.readRow('singleton');
      expect(fields, isNotNull);
      expect(fields!['system_color'], 'ff0000');
    });

    test('null system_color round-trips as null', () async {
      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final settings = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'system_settings',
      );

      await settings.applyFields('singleton', {
        'system_color': null,
        'is_deleted': false,
      });

      final fields = await settings.readRow('singleton');
      expect(fields, isNotNull);
      expect(fields!['system_color'], isNull);
    });
  });
}
