// Regression tests for the F2 retarget guards (2026-06-27 audit, hardened after
// adversarial review). The non-tombstone member apply retargets an
// identity-unmatched op onto a recorded redirect-alias holder so a SPARSE edit
// for a redirected legacy id lands on the winner. That retarget must NOT fire
// when it would clobber an unrelated member:
//   - an op carrying its OWN distinct PK identity is a different member (or a
//     relink), not a sparse edit — it must not be folded onto the holder;
//   - a holder since relinked to a DIFFERENT PK member no longer holds the
//     alias's recorded identity — it must not be overwritten.
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
      'F2 guard: a full-identity create under a redirected legacy id is NOT '
      'folded onto the alias holder', () async {
    // Winner holds the PK member uuid-X; a peer op for the same member arrives
    // under "legacy" and is redirected onto the winner (alias legacy -> winner).
    await _apply(db, [
      _memberChange('winner',
          _memberFields(name: 'Xavier', pkUuid: 'uuid-X', pkId: 'sx')),
    ]);
    await _apply(db, [
      _memberChange('legacy',
          _memberFields(name: 'Xavier', pkUuid: 'uuid-X', pkId: 'sx')),
    ]);

    // A FULL create for a DISTINCT member uuid-Y arrives under the still-aliased
    // "legacy" id. It carries its own identity, so it must NOT be retargeted onto
    // the winner (which would overwrite uuid-X with uuid-Y).
    await _apply(db, [
      _memberChange('legacy',
          _memberFields(name: 'Yara', pkUuid: 'uuid-Y', pkId: 'sy')),
    ]);

    final rows = await db.select(db.members).get();
    final byUuid = {
      for (final r in rows.where((r) => !r.isDeleted)) r.pluralkitUuid: r,
    };
    expect(byUuid.containsKey('uuid-X'), isTrue,
        reason: 'The winner (uuid-X) must survive intact, not be overwritten.');
    expect(byUuid['uuid-X']!.name, 'Xavier');
    expect(byUuid.containsKey('uuid-Y'), isTrue,
        reason: 'The distinct member uuid-Y must exist as its own row.');
  });

  test(
      'F2 guard: a sparse edit does NOT clobber a holder that was relinked to a '
      'different PK member', () async {
    await _apply(db, [
      _memberChange('winner',
          _memberFields(name: 'Xavier', pkUuid: 'uuid-X', pkId: 'sx')),
    ]);
    await _apply(db, [
      _memberChange('legacy',
          _memberFields(name: 'Xavier', pkUuid: 'uuid-X', pkId: 'sx')),
    ]);
    // The winner row is relinked in place to a DIFFERENT PK member uuid-Y. The
    // alias legacy -> winner (recorded for uuid-X) is now stale.
    await _apply(db, [
      _memberChange('winner',
          _memberFields(name: 'Yara', pkUuid: 'uuid-Y', pkId: 'sy')),
    ]);

    // A late SPARSE edit still addressed to the old legacy id must NOT be
    // retargeted onto the relinked winner (which now holds a different member).
    await _apply(db, [
      _memberChange('legacy', <String, dynamic>{'name': 'StaleLateEdit'}),
    ]);

    final winner = (await db.select(db.members).get())
        .singleWhere((r) => r.id == 'winner');
    expect(winner.name, 'Yara',
        reason: 'The relinked member (uuid-Y) must not be clobbered by a stale '
            'sparse edit addressed to the old legacy id.');
    expect(winner.pluralkitUuid, 'uuid-Y');
  });
}
