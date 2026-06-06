import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

SyncEvent _eventFromChanges(List<Map<String, dynamic>> changes) {
  return SyncEvent.fromJson({'type': 'RemoteChanges', 'changes': changes});
}

Map<String, dynamic> _memberChange(String id, Map<String, dynamic> fields) {
  return {
    'table': 'members',
    'entity_id': id,
    'is_delete': false,
    'fields': fields,
  };
}

Map<String, dynamic> _memberFields({
  required String name,
  String? pkUuid,
  String? pkId,
  bool isDeleted = false,
  Object? age,
}) {
  return <String, dynamic>{
    'name': name,
    'pronouns': null,
    'emoji': '*',
    'age': ?age,
    'bio': null,
    'avatar_image_data': null,
    'pk_avatar_cached_url': null,
    'is_active': true,
    'created_at': DateTime.utc(2026, 6).toIso8601String(),
    'display_order': 0,
    'is_admin': false,
    'custom_color_enabled': false,
    'custom_color_hex': null,
    'parent_system_id': null,
    'pluralkit_uuid': pkUuid,
    'pluralkit_id': pkId,
    'pluralkit_display_name': null,
    'markdown_enabled': true,
    'display_name': null,
    'birthday': null,
    'proxy_tags_json': null,
    'pk_banner_url': null,
    'profile_header_source': 1,
    'profile_header_layout': 0,
    'profile_header_visible': true,
    'name_style_font': 0,
    'name_style_bold': true,
    'name_style_italic': false,
    'name_style_color_mode': 0,
    'name_style_color_hex': null,
    'profile_header_image_data': null,
    'pk_banner_image_data': null,
    'pk_banner_cached_url': null,
    'pluralkit_sync_ignored': false,
    'delete_push_started_at': null,
    'is_always_fronting': false,
    'is_deleted': isDeleted,
    'board_last_read_at': null,
  };
}

Future<void> _runStrictApply(
  database.AppDatabase db,
  List<Map<String, dynamic>> changes,
) async {
  final wrapped = buildSyncAdapterWithCompletion(db);
  final event = _eventFromChanges(changes);
  await applyRemoteChanges(db, wrapped.adapter, event, strict: true);
}

void main() {
  late database.AppDatabase db;

  setUp(() {
    db = database.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('members strict apply - pairing repro probes', () {
    test('baseline full member payload applies cleanly', () async {
      await _runStrictApply(db, [
        _memberChange('member-1', _memberFields(name: 'Ada')),
      ]);
    });

    test('old integer age payload applies cleanly', () async {
      await _runStrictApply(db, [
        _memberChange('member-1', _memberFields(name: 'Ada', age: 33)),
      ]);

      final row = await (db.select(
        db.members,
      )..where((m) => m.id.equals('member-1'))).getSingle();
      expect(row.age, '33');
    });

    test(
      'deleted stale PK holder before active replacement does not abort pairing',
      () async {
        await _runStrictApply(db, [
          _memberChange(
            'deleted-holder',
            _memberFields(
              name: 'Deleted holder',
              pkUuid: 'pk-member-uuid',
              pkId: 'abcde',
              isDeleted: true,
            ),
          ),
          _memberChange(
            'active-replacement',
            _memberFields(
              name: 'Active replacement',
              pkUuid: 'pk-member-uuid',
              pkId: 'abcde',
            ),
          ),
        ]);

        final rows = await db.select(db.members).get();
        expect(rows, hasLength(2));
        final deleted = rows.singleWhere((row) => row.id == 'deleted-holder');
        final active = rows.singleWhere(
          (row) => row.id == 'active-replacement',
        );
        expect(deleted.isDeleted, isTrue);
        expect(deleted.pluralkitUuid, isNull);
        expect(deleted.pluralkitId, isNull);
        expect(active.pluralkitUuid, 'pk-member-uuid');
        expect(active.pluralkitId, 'abcde');
      },
    );

    test(
      'active duplicate PK holder merges without aborting pairing',
      () async {
        await _runStrictApply(db, [
          _memberChange(
            'active-holder',
            _memberFields(
              name: 'Active holder',
              pkUuid: 'pk-member-uuid',
              pkId: 'abcde',
            ),
          ),
        ]);

        await _runStrictApply(db, [
          _memberChange(
            'active-replacement',
            _memberFields(
              name: 'Active replacement',
              pkUuid: 'pk-member-uuid',
              pkId: 'abcde',
            ),
          ),
        ]);

        final rows = await db.select(db.members).get();
        expect(rows, hasLength(1));
        final active = rows.single;
        expect(active.id, 'active-holder');
        expect(active.name, 'Active replacement');
        expect(active.pluralkitUuid, 'pk-member-uuid');
        expect(active.pluralkitId, 'abcde');
      },
    );

    test(
      'active duplicate PK short-id holder merges without aborting pairing',
      () async {
        await _runStrictApply(db, [
          _memberChange(
            'active-holder',
            _memberFields(name: 'Active holder', pkId: 'abcde'),
          ),
        ]);

        await _runStrictApply(db, [
          _memberChange(
            'active-replacement',
            _memberFields(name: 'Active replacement', pkId: 'abcde'),
          ),
        ]);

        final rows = await db.select(db.members).get();
        expect(rows, hasLength(1));
        final active = rows.single;
        expect(active.id, 'active-holder');
        expect(active.name, 'Active replacement');
        expect(active.pluralkitUuid, isNull);
        expect(active.pluralkitId, 'abcde');
      },
    );

    test(
      'stale PK tombstone after active holder does not abort pairing',
      () async {
        await _runStrictApply(db, [
          _memberChange(
            'active-holder',
            _memberFields(
              name: 'Active holder',
              pkUuid: 'pk-member-uuid',
              pkId: 'abcde',
            ),
          ),
          _memberChange(
            'stale-tombstone',
            _memberFields(
              name: 'Stale tombstone',
              pkUuid: 'pk-member-uuid',
              pkId: 'abcde',
              isDeleted: true,
            ),
          ),
        ]);

        final rows = await db.select(db.members).get();
        expect(rows, hasLength(2));
        final active = rows.singleWhere((row) => row.id == 'active-holder');
        final tombstone = rows.singleWhere(
          (row) => row.id == 'stale-tombstone',
        );
        expect(active.isDeleted, isFalse);
        expect(active.pluralkitUuid, 'pk-member-uuid');
        expect(active.pluralkitId, 'abcde');
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.pluralkitUuid, isNull);
        expect(tombstone.pluralkitId, isNull);
      },
    );
  });
}
