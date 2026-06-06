// Board-post delete-resurrection repro (real FFI, real relay, no mocks).
//
// Root-cause repro for "deleted board posts pop back up for some users".
//
// Soft-delete of a board post is a per-field LWW write: `is_deleted = "true"`
// stamped with the delete's HLC (mirrors
// `DriftMemberBoardPostsRepository.softDeletePost` → `syncRecordUpdate(id,
// {is_deleted: true})`). The Rust merge engine protects that tombstone by
// rejecting every NON-`is_deleted` op once an entity is tombstoned
// (`engine/merge.rs` "tombstone protection"), so edit-after-delete cannot
// resurrect a post on a peer that holds the tombstone — Test 2 confirms that.
//
// But `record_create` emits one op PER FIELD, including `is_deleted = "false"`,
// all stamped with a FRESH HLC (`op_emitter.rs::emit_create`). The merge
// engine deliberately lets `is_deleted` ops THROUGH the tombstone gate. So a
// re-create of an already-deleted entity id (what the data-import / SP-boards
// backfill paths do for a post not present locally) emits a fresh-HLC
// `is_deleted = "false"` that beats the older tombstone under per-field LWW —
// and the post resurrects on every peer, including the one that deleted it.
// Test 1 reproduces that.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

const String _table = 'member_board_posts';
const String _postId = 'bp-resurrect-1';

/// The field map the app sends on create (mirrors
/// `DriftMemberBoardPostsRepository.postFields`, minus the DateTime columns —
/// a field subset is accepted by the engine and the dates are irrelevant to the
/// `is_deleted` merge). `is_deleted: false` is included exactly as the real
/// create path includes it.
String _createFieldsJson({required String title}) => jsonEncode({
      'target_member_id': 'member-1',
      'author_id': 'member-1',
      'audience': 'public',
      'title': title,
      'body': 'body text',
      'is_deleted': false,
    });

Future<String?> _isDeleted(E2EDevice d) => ffi.readFieldValue(
      handle: d.handle,
      table: _table,
      entityId: _postId,
      field: 'is_deleted',
    );

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  // ──────────────────────────────────────────────────────────────────────
  // Test 1 — THE BUG. A re-create after a delete resurrects the post on the
  // peer that already applied the delete. Asserts the CORRECT behaviour
  // (tombstone survives) so it FAILS on the current code and PASSES once the
  // resurrection vector is closed.
  // ──────────────────────────────────────────────────────────────────────
  test('re-create after delete must NOT resurrect a board post', skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // 1. A creates the post; B receives it.
      await ffi.recordCreate(
        handle: a.handle,
        table: _table,
        entityId: _postId,
        fieldsJson: _createFieldsJson(title: 'Original'),
      );
      await a.sync();
      await b.sync();
      // B actually received the post (read a content field, not is_deleted —
      // a live post has NO is_deleted field version, only the tombstone does).
      expect(
        await ffi.readFieldValue(
          handle: b.handle,
          table: _table,
          entityId: _postId,
          field: 'title',
        ),
        '"Original"',
        reason: 'B should have received the live post after create',
      );

      // 2. A soft-deletes the post (exactly how softDeletePost emits it:
      //    a field-level is_deleted=true update, NOT a hard delete).
      await ffi.recordUpdate(
        handle: a.handle,
        table: _table,
        entityId: _postId,
        changedFieldsJson: '{"is_deleted":true}',
      );
      await a.sync();
      await b.sync();
      // Settle both directions.
      await a.sync();
      await b.sync();
      expect(await _isDeleted(a), 'true', reason: 'A deleted the post');
      expect(await _isDeleted(b), 'true', reason: 'B converged on the tombstone (post gone)');

      // 3. A device re-creates the SAME post id (what data-import / SP-boards
      //    backfill does for a post that is not present locally). This emits a
      //    fresh-HLC is_deleted=false op.
      await ffi.recordCreate(
        handle: a.handle,
        table: _table,
        entityId: _postId,
        fieldsJson: _createFieldsJson(title: 'Original'),
      );
      await a.sync();
      await b.sync();
      await a.sync();
      await b.sync();

      // 4. The tombstone must survive. On the current code it does NOT: the
      //    re-create's fresh is_deleted=false beats the older tombstone and the
      //    post pops back up on BOTH devices.
      expect(
        await _isDeleted(b),
        'true',
        reason: 'RESURRECTION BUG: re-create emitted a fresh-HLC is_deleted=false '
            'that beat B\'s tombstone under per-field LWW — deleted post reappeared on B',
      );
      expect(
        await _isDeleted(a),
        'true',
        reason: 'RESURRECTION BUG: the re-create also un-deleted the post locally on A',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // ──────────────────────────────────────────────────────────────────────
  // Test 2 — CONTRAST. An edit-after-delete (the app's update path, which
  // strips is_deleted via diffSyncFields) does NOT resurrect, because the
  // merge engine's tombstone protection rejects non-is_deleted ops on a
  // tombstoned entity. This PASSES on the current code and isolates re-create
  // as the unique resurrection vector.
  // ──────────────────────────────────────────────────────────────────────
  test('edit after delete does NOT resurrect (tombstone protection holds)', skip: e2eSkip(),
      () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      await ffi.recordCreate(
        handle: a.handle,
        table: _table,
        entityId: _postId,
        fieldsJson: _createFieldsJson(title: 'Original'),
      );
      await a.sync();
      await b.sync();

      await ffi.recordUpdate(
        handle: a.handle,
        table: _table,
        entityId: _postId,
        changedFieldsJson: '{"is_deleted":true}',
      );
      await a.sync();
      await b.sync();
      await a.sync();
      await b.sync();
      expect(await _isDeleted(a), 'true');
      expect(await _isDeleted(b), 'true');

      // B edits the (deleted) post — a field-level update with NO is_deleted,
      // exactly as the real update path emits (diffSyncFields strips it).
      await ffi.recordUpdate(
        handle: b.handle,
        table: _table,
        entityId: _postId,
        changedFieldsJson: '{"title":"Edited after delete","body":"new"}',
      );
      await b.sync();
      await a.sync();
      await b.sync();
      await a.sync();

      // The tombstone must hold on both devices — the edit cannot resurrect.
      expect(
        await _isDeleted(a),
        'true',
        reason: 'tombstone protection must reject the edit on the deleting device',
      );
      expect(
        await _isDeleted(b),
        'true',
        reason: 'the editing device must not un-delete itself via a field update',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });
}
