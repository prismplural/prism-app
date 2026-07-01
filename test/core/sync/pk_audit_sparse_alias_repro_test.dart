// Regression test for PK merge/write audit finding F2 (2026-06-27).
// A sparse member op (no PluralKit identity fields) for a legacy entity id that
// was previously redirected onto a winner row must land on the winner, not
// create a second orphan row or throw. Before the fix, the non-tombstone member
// apply consulted `pk_identity_sync_aliases` only on the tombstone/delete paths,
// so a sparse incremental edit (rename, display_order, board_last_read_at) for a
// redirected legacy id fell through to a plain insert at the legacy id.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

SyncEvent _eventFromChanges(List<Map<String, dynamic>> changes) {
  return SyncEvent.fromJson({'type': 'RemoteChanges', 'changes': changes});
}

Map<String, dynamic> _memberChange(
  String id,
  Map<String, dynamic> fields, {
  bool isDelete = false,
}) {
  return {
    'table': 'members',
    'entity_id': id,
    'is_delete': isDelete,
    'fields': fields,
  };
}

Map<String, dynamic> _memberFields({
  required String name,
  String? pkUuid,
  String? pkId,
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
    'is_deleted': false,
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
      'F2: a sparse member op for a redirected legacy id lands on the winner, '
      'not a duplicate orphan row', () async {
    const winnerId = 'local-member-A';
    const legacyId = 'legacy-member-B';
    const pkUuid = 'pk-member-uuid-1';

    // Device A holds the PK member under winnerId.
    await _apply(db, [
      _memberChange(
        winnerId,
        _memberFields(name: 'Aria', pkUuid: pkUuid, pkId: 'aaa'),
      ),
    ]);
    // The peer's create op for the SAME PK member arrives under legacyId. The
    // member apply redirects legacyId -> winnerId, recording the alias; legacyId
    // is never materialized.
    await _apply(db, [
      _memberChange(
        legacyId,
        _memberFields(name: 'Aria', pkUuid: pkUuid, pkId: 'aaa'),
      ),
    ]);

    // A later SPARSE incremental op from the peer carries legacyId and ONLY the
    // renamed field — no pluralkit_uuid / pluralkit_id. This is the F2 path.
    await _apply(db, [
      _memberChange(legacyId, <String, dynamic>{'name': 'Renamed'}),
    ]);

    final rows = await db.select(db.members).get();
    final live = rows.where((r) => !r.isDeleted).toList();

    expect(live.length, 1,
        reason: 'The sparse edit must update the winner row, not create a '
            'second orphan row at the redirected legacy id. Rows: '
            '${rows.map((r) => '(${r.id}, ${r.name}, del=${r.isDeleted})').toList()}');
    expect(live.single.id, winnerId,
        reason: 'The surviving row should be the winner the legacy id was '
            'redirected onto.');
    expect(live.single.name, 'Renamed',
        reason: 'The sparse rename should have landed on the winner row.');
    expect(rows.where((r) => r.id == legacyId), isEmpty,
        reason: 'No row should exist under the redirected legacy id.');
  });
}
