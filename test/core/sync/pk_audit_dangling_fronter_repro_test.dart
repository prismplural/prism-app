// Regression test for PK merge/write audit finding F1 (2026-06-27).
// The fronting-session apply path must not write member_id VERBATIM from the
// incoming op without remapping it through pk_identity_sync_aliases. In a
// cross-device setup, two devices mint different local member ids (LA/LB) for
// the same PK member; the member apply redirects LB->LA (LB never materialized,
// alias LB->LA recorded). A switch op carrying member_id=LB then landed as a
// fronting row pointing at LB — a member id that does not exist locally — so the
// fronter silently vanished from the UI. The apply now remaps a dangling
// member_id to the live local winner before writing the row.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

Map<String, dynamic> _memberFields({
  required String name,
  String? pkUuid,
  String? pkId,
}) => <String, dynamic>{
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

void main() {
  test(
      'AUDIT: cross-device fronting apply leaves a dangling member_id '
      '(fronter vanishes)', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get(); // force migrations

    final wrapped = buildSyncAdapterWithCompletion(db);
    final members =
        wrapped.adapter.entities.singleWhere((e) => e.tableName == 'members');
    final fronting = wrapped.adapter.entities
        .singleWhere((e) => e.tableName == 'fronting_sessions');

    const pkMemberUuid = 'pk-member-uuid-1';
    const switchUuid = 'pk-switch-uuid-1';
    const localA = 'local-member-A'; // this device's id for the PK member
    const localB = 'local-member-B'; // the OTHER device's id for the same member

    wrapped.beginSyncBatch();
    // This device already holds the PK member under id LA.
    await members.applyFields(
        localA, _memberFields(name: 'Aria', pkUuid: pkMemberUuid, pkId: 'aaa'));
    // The peer's create op for the SAME PK member arrives under id LB. The
    // member apply redirects LB -> LA (LB is never materialized; alias recorded).
    await members.applyFields(
        localB, _memberFields(name: 'Aria', pkUuid: pkMemberUuid, pkId: 'aaa'));
    // The peer's switch op references the fronter by ITS local id, LB.
    await fronting.applyFields('session-1', <String, dynamic>{
      'start_time': DateTime.utc(2026, 6, 1).toIso8601String(),
      'end_time': null,
      'session_type': 0,
      'is_health_kit_import': false,
      'is_deleted': false,
      'member_id': localB,
      'pluralkit_uuid': switchUuid,
    });
    await wrapped.completeSyncBatch();

    final memberRows = await db.select(db.members).get();
    final liveMemberIds = memberRows
        .where((m) => !m.isDeleted)
        .map((m) => m.id)
        .toSet();
    final sessionRows = await db.select(db.frontingSessions).get();
    final session = sessionRows.single;

    // ignore: avoid_print
    print('[AUDIT] live member ids = $liveMemberIds; '
        'fronting session member_id = ${session.memberId}  '
        '(points at a live member? ${liveMemberIds.contains(session.memberId)})');

    // CORRECT behavior: the session must point at the live, materialized member.
    expect(liveMemberIds.contains(session.memberId), isTrue,
        reason: 'Fronting session.member_id=${session.memberId} does not match '
            'any live member ($liveMemberIds). The fronter is dangling and '
            'will silently vanish from the UI. Expected it remapped to $localA '
            'via pk_identity_sync_aliases.');
  });

  test(
      'F1 order-independence: fronting op applied BEFORE the redirected member '
      'op is back-filled onto the winner', () async {
    // The engine does not order changes across tables causally, so a switch op
    // can apply before the member-create that records the LB->LA redirect (and
    // can even arrive in an earlier batch). The forward remap cannot help here —
    // no alias exists yet — so the member apply must back-fill the dangling
    // session when it records the redirect.
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get(); // force migrations

    final wrapped = buildSyncAdapterWithCompletion(db);
    final members =
        wrapped.adapter.entities.singleWhere((e) => e.tableName == 'members');
    final fronting = wrapped.adapter.entities
        .singleWhere((e) => e.tableName == 'fronting_sessions');

    const pkMemberUuid = 'pk-member-uuid-1';
    const switchUuid = 'pk-switch-uuid-1';
    const localA = 'local-member-A';
    const localB = 'local-member-B';

    wrapped.beginSyncBatch();
    await members.applyFields(
        localA, _memberFields(name: 'Aria', pkUuid: pkMemberUuid, pkId: 'aaa'));
    // The switch op arrives FIRST, before the member-create for LB — no LB->LA
    // alias exists yet, so the remap writes LB verbatim (dangling for now).
    await fronting.applyFields('session-1', <String, dynamic>{
      'start_time': DateTime.utc(2026, 6, 1).toIso8601String(),
      'end_time': null,
      'session_type': 0,
      'is_health_kit_import': false,
      'is_deleted': false,
      'member_id': localB,
      'pluralkit_uuid': switchUuid,
    });
    // The peer's create op for the SAME PK member arrives under id LB and
    // redirects LB -> LA — this must back-fill the dangling session.
    await members.applyFields(
        localB, _memberFields(name: 'Aria', pkUuid: pkMemberUuid, pkId: 'aaa'));
    await wrapped.completeSyncBatch();

    final liveMemberIds = (await db.select(db.members).get())
        .where((m) => !m.isDeleted)
        .map((m) => m.id)
        .toSet();
    final session = (await db.select(db.frontingSessions).get()).single;

    expect(session.memberId, localA,
        reason: 'The session applied before the redirect must be back-filled '
            'onto the live winner $localA; got ${session.memberId}.');
    expect(liveMemberIds.contains(session.memberId), isTrue,
        reason: 'Back-filled session must point at a live member.');
  });
}
