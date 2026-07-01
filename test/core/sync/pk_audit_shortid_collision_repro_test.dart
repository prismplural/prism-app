// Regression test for PK merge/write audit finding F3 (2026-06-27).
// Apply-time identity dedup must not over-merge two DISTINCT PluralKit members
// that transiently share a short id (possible under PK Premium, where short ids
// became user-changeable ~Feb 2026). The apply-time matcher
// `_activeMemberRowsByPkIdentityForApply` matches on (uuid OR pluralkit_id), so
// before the fix a routine op for member B whose pluralkit_id collided with a
// different local member A was redirected onto A's row — destroying one member's
// identity. The apply now mirrors importer H12a: a short-id-only match carrying
// a different non-empty uuid is a recycled-short-id conflict, so only the stale
// short id is cleared and both members survive.
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
}) {
  return <String, dynamic>{
    'name': name,
    'pronouns': null,
    'emoji': '*',
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

Future<void> _apply(
  database.AppDatabase db,
  List<Map<String, dynamic>> changes,
) async {
  final wrapped = buildSyncAdapterWithCompletion(db);
  await applyRemoteChanges(db, wrapped.adapter, _eventFromChanges(changes),
      strict: true);
}

void main() {
  late database.AppDatabase db;
  setUp(() => db = database.AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
      'AUDIT: two DISTINCT PK members sharing a short id must NOT merge '
      '(short-id reuse under PK Premium)', () async {
    // Member A: fully imported, uuid U_A, short id "abcde".
    await _apply(db, [
      _memberChange('member-a',
          _memberFields(name: 'Alice', pkUuid: 'uuid-AAAA', pkId: 'abcde')),
    ]);

    // Member B: a DIFFERENT PK member, uuid U_B. Under PK Premium the short id
    // "abcde" was freed by A (renamed) and reassigned to B; B's op carries the
    // colliding short id. This is a routine remote op, not a malformed one.
    await _apply(db, [
      _memberChange('member-b',
          _memberFields(name: 'Bob', pkUuid: 'uuid-BBBB', pkId: 'abcde')),
    ]);

    final rows = await db.select(db.members).get();
    // ignore: avoid_print
    print('[AUDIT] rows after applying two distinct members sharing short id '
        '"abcde": ${rows.map((r) => '(${r.id}, name=${r.name}, '
        'uuid=${r.pluralkitUuid}, pkId=${r.pluralkitId}, del=${r.isDeleted})').toList()}');

    // CORRECT behavior: two distinct people, two live rows, identities intact.
    final liveUuids = rows
        .where((r) => !r.isDeleted && r.pluralkitUuid != null)
        .map((r) => r.pluralkitUuid)
        .toSet();
    expect(liveUuids, containsAll(<String>{'uuid-AAAA', 'uuid-BBBB'}),
        reason: 'Both distinct PK identities should survive; if uuid-AAAA is '
            'missing, member A was silently destroyed by the short-id merge.');
    expect(rows.where((r) => !r.isDeleted).length, 2,
        reason: 'Expected two live member rows for two distinct PK members.');
  });

  test(
      'F3 deleted-row analogue: a recycled short id must NOT strip a '
      'soft-deleted distinct member\'s real uuid', () async {
    // A live PK member, then soft-deleted; PK identity is intentionally retained
    // on the tombstone (user-recoverable, and needed to refuse a re-import dup).
    await _apply(db, [
      _memberChange('member-deleted',
          _memberFields(name: 'Rhea', pkUuid: 'uuid-YYYY', pkId: 'abcde')),
    ]);
    await _apply(db, [
      _memberChange(
          'member-deleted',
          _memberFields(
              name: 'Rhea',
              pkUuid: 'uuid-YYYY',
              pkId: 'abcde',
              isDeleted: true)),
    ]);

    // A DIFFERENT live PK member recycles short id "abcde" (different uuid). The
    // pre-split-before release path would null BOTH pk fields on the deleted
    // row, destroying its real uuid.
    await _apply(db, [
      _memberChange('member-live',
          _memberFields(name: 'Bob', pkUuid: 'uuid-XXXX', pkId: 'abcde')),
    ]);

    final rows = await db.select(db.members).get();
    final deleted = rows.singleWhere((r) => r.id == 'member-deleted');
    final live = rows.singleWhere((r) => r.id == 'member-live');

    expect(deleted.pluralkitUuid, 'uuid-YYYY',
        reason: 'The soft-deleted distinct member must keep its real uuid; a '
            'recycled short id must only clear the stale pluralkit_id.');
    expect(deleted.pluralkitId, isNull,
        reason: 'The stale recycled short id should be cleared off the deleted '
            'row so the live member can take it.');
    expect(live.pluralkitUuid, 'uuid-XXXX');
    expect(live.pluralkitId, 'abcde');
    expect(live.isDeleted, isFalse);
  });
}
