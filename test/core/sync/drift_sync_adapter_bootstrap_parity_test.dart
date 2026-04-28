import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter_bootstrap.dart';

void main() {
  // Parity test: every entity registered on `DriftSyncAdapter` must have a
  // fetcher in `bootstrapFetchersFor`. If someone adds a new synced entity to
  // the adapter without extending the bootstrap map, first-device setup will
  // silently skip it and the joiner device will be missing that table — this
  // test fails CI before that can ship.
  test('bootstrap map covers every entity registered on the adapter', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final adapter = syncAdapter.adapter;

    final adapterTables =
        adapter.entities.map((e) => e.tableName).toSet();
    final bootstrapTables = bootstrapFetchersFor(adapter, db).keys.toSet();

    final missingFromBootstrap = adapterTables.difference(bootstrapTables);
    expect(
      missingFromBootstrap,
      isEmpty,
      reason: 'The following adapter-registered tables are missing from '
          'bootstrapFetchersFor and will be skipped during first-device '
          'seed: $missingFromBootstrap. Add them to '
          'bootstrapFetchersFor in drift_sync_adapter_bootstrap.dart.',
    );

    final extrasInBootstrap = bootstrapTables.difference(adapterTables);
    expect(
      extrasInBootstrap,
      isEmpty,
      reason: 'bootstrapFetchersFor references tables the adapter does not '
          'know about: $extrasInBootstrap. Either remove them from the '
          'bootstrap map or register them on the adapter.',
    );

    // Double-check each bootstrap table resolves to a non-null entity — this
    // guards against silent mismatches between keys that compare-equal but
    // point at different registrations.
    for (final tableName in bootstrapTables) {
      expect(
        adapter.entityForTable(tableName),
        isNotNull,
        reason: 'bootstrap map has an entry for "$tableName" but the '
            'adapter has no entity registered for it.',
      );
    }
  });

  test(
    'bootstrap map returns empty SyncRow lists for an empty database',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fetchers = bootstrapFetchersFor(syncAdapter.adapter, db);

      for (final entry in fetchers.entries) {
        final rows = await entry.value();
        expect(
          rows,
          isEmpty,
          reason: 'Fresh database should have no rows in ${entry.key}',
        );
      }
    },
  );

  test('buildBootstrapRecords wraps rows with table + entity_id', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final adapter = syncAdapter.adapter;

    // Seed one members row so we can observe the wrapper shape.
    await adapter.applyFields('members', 'm-1', <String, dynamic>{
      'name': 'Ada',
      'emoji': '✨',
      'is_active': true,
      'created_at': DateTime.utc(2026, 3, 18).toIso8601String(),
      'display_order': 1,
      'is_admin': false,
      'custom_color_enabled': false,
      'markdown_enabled': true,
      'pluralkit_sync_ignored': false,
      'is_deleted': false,
    });

    final fetchers = bootstrapFetchersFor(adapter, db);
    final records = await buildBootstrapRecords(fetchers);

    final members =
        records.where((r) => r['table'] == 'members').toList();
    expect(members, hasLength(1));
    final row = members.single;
    expect(row['entity_id'], 'm-1');
    expect(row['fields'], isA<Map<String, dynamic>>());
    expect((row['fields'] as Map)['name'], 'Ada');
  });
}
