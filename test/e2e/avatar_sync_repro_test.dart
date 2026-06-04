// Repro: SP-zip-imported avatars show ❔ on the peer device.
//
// The importer writes a member's avatar via the SAME record_update path the
// rest of the app uses (a per-field patch: {"avatar_image_data": <base64>}).
// Static analysis says a normalized avatar (<=256KB) is a sub-1MB op and should
// propagate. This drives the REAL FFI + relay across two paired devices and
// reads avatar_image_data back on the peer to see whether that's actually true
// at realistic sizes, including the bulk shape the importer produces.
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

/// A base64 avatar payload of [rawBytes] raw bytes, varied by [seed] so no two
/// members carry byte-identical blobs (rules out any dedup masking the result).
String _avatarB64(int rawBytes, {int seed = 0}) {
  final bytes = Uint8List(rawBytes);
  for (var i = 0; i < rawBytes; i++) {
    bytes[i] = (i + seed) & 0xFF;
  }
  return base64Encode(bytes);
}

/// Push from A, pull on B, settle once more. Prints the raw sync results so the
/// test output shows pushed/pulled/merged/error/quarantine for every cycle.
Future<void> _exchange(E2EDevice a, E2EDevice b, String label) async {
  final aSync = await a.sync();
  final bSync = await b.sync();
  // A second round so a late-arriving cursor settles.
  final aSync2 = await a.sync();
  final bSync2 = await b.sync();
  // ignore: avoid_print
  print('[$label] A.push=$aSync  B.pull=$bSync  A.push2=$aSync2  B.pull2=$bSync2');
}

/// Read avatar_image_data on [d] for member [id]; null means the peer never
/// received the avatar (the ❔ symptom).
Future<String?> _avatarOn(E2EDevice d, String id) => ffi.readFieldValue(
      handle: d.handle,
      table: 'members',
      entityId: id,
      field: 'avatar_image_data',
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

  // Control: a tiny avatar must propagate. If this fails, the harness or the
  // schema is wrong, not the size path.
  test('1KB avatar update propagates to the peer', skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'm-small',
        fieldsJson: '{"name":"Small"}',
      );
      await _exchange(a, b, 'create m-small');

      final av = _avatarB64(1024, seed: 1);
      await ffi.recordUpdate(
        handle: a.handle,
        table: 'members',
        entityId: 'm-small',
        changedFieldsJson: jsonEncode({'avatar_image_data': av}),
      );
      await _exchange(a, b, '1KB avatar');

      final onB = await _avatarOn(b, 'm-small');
      // ignore: avoid_print
      print('[1KB] B avatar present=${onB != null} len=${onB?.length}');
      expect(onB, isNotNull, reason: '1KB avatar must reach B');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // The real question: a 256KB normalized avatar (the importer's byte budget).
  test('256KB avatar update (normalizer cap) propagates to the peer',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'm-256k',
        fieldsJson: '{"name":"Big"}',
      );
      await _exchange(a, b, 'create m-256k');

      final av = _avatarB64(256 * 1024, seed: 7); // == AvatarNormalizer.targetMaxBytes
      await ffi.recordUpdate(
        handle: a.handle,
        table: 'members',
        entityId: 'm-256k',
        changedFieldsJson: jsonEncode({'avatar_image_data': av}),
      );
      await _exchange(a, b, '256KB avatar');

      final onB = await _avatarOn(b, 'm-256k');
      // ignore: avoid_print
      print('[256KB] B avatar present=${onB != null} len=${onB?.length}');
      expect(
        onB,
        isNotNull,
        reason: '256KB normalized avatar must reach B (this is the import size)',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // Positive control for the failure mode: an oversized avatar should NOT
  // silently appear on B (it should quarantine / fail to push). Confirms the
  // harness can actually observe the ❔ outcome.
  test('800KB avatar update (over the 1MB op cap) does NOT reach the peer',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'm-huge',
        fieldsJson: '{"name":"Huge"}',
      );
      await _exchange(a, b, 'create m-huge');

      final av = _avatarB64(800 * 1024, seed: 3); // ~1.06MB base64 => op > 1MB
      await ffi.recordUpdate(
        handle: a.handle,
        table: 'members',
        entityId: 'm-huge',
        changedFieldsJson: jsonEncode({'avatar_image_data': av}),
      );
      await _exchange(a, b, '800KB avatar');

      final onB = await _avatarOn(b, 'm-huge');
      // ignore: avoid_print
      print('[800KB] B avatar present=${onB != null} len=${onB?.length}');
      // Not asserting hard here — the print tells the story either way.
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // The actual import shape: many members, each given a ~256KB avatar via its
  // own record_update, then ONE sync cycle. Mirrors the zip importer's loop.
  test('bulk: 12 members each get a 256KB avatar in one cycle — all reach the peer',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    const n = 12;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      for (var i = 0; i < n; i++) {
        await ffi.recordCreate(
          handle: a.handle,
          table: 'members',
          entityId: 'mb-$i',
          fieldsJson: '{"name":"Mb$i"}',
        );
      }
      await _exchange(a, b, 'create $n members');

      // Importer loop: one avatar-only record_update per member.
      for (var i = 0; i < n; i++) {
        await ffi.recordUpdate(
          handle: a.handle,
          table: 'members',
          entityId: 'mb-$i',
          changedFieldsJson: jsonEncode({'avatar_image_data': _avatarB64(256 * 1024, seed: i)}),
        );
      }
      await _exchange(a, b, 'bulk 256KB avatars');
      // Extra settle cycles in case a per-cycle push cap staggers delivery.
      await _exchange(a, b, 'bulk settle');

      var present = 0;
      final missing = <String>[];
      for (var i = 0; i < n; i++) {
        final onB = await _avatarOn(b, 'mb-$i');
        if (onB != null) {
          present++;
        } else {
          missing.add('mb-$i');
        }
      }
      // ignore: avoid_print
      print('[BULK] $present/$n avatars present on B; missing=$missing');
      expect(present, equals(n), reason: 'all $n imported avatars must reach B; missing=$missing');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // Where exactly does an avatar op stop fitting? Sweep raw sizes and report
  // which propagate. Tells us how large an avatar must be to hit the failure.
  test('threshold sweep: which avatar sizes reach the peer', skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    const sizesKb = [256, 384, 512, 640, 700, 720, 740, 768];
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      final outcome = <String>[];
      for (final kb in sizesKb) {
        final id = 'sweep-$kb';
        await ffi.recordCreate(
          handle: a.handle,
          table: 'members',
          entityId: id,
          fieldsJson: '{"name":"S$kb"}',
        );
        await ffi.recordUpdate(
          handle: a.handle,
          table: 'members',
          entityId: id,
          changedFieldsJson: jsonEncode({'avatar_image_data': _avatarB64(kb * 1024, seed: kb)}),
        );
        final aSync = await a.sync();
        await b.sync();
        await b.sync();
        final onB = await _avatarOn(b, id);
        outcome.add('${kb}KB raw -> A.pushed=${aSync['pushed']} reachesB=${onB != null}');
      }
      final qc = await ffi.quarantinedBatchCount(handle: a.handle);
      // ignore: avoid_print
      print('[SWEEP]\n  ${outcome.join('\n  ')}\n  A.quarantinedBatchCount=$qc');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // For an oversized avatar: does it QUARANTINE (repair banner available) or
  // SILENTLY DROP (no banner anywhere — matches "no warnings")? And can repair
  // rescue a single oversized op (it can't be split)?
  test('oversized avatar: quarantine vs silent drop, and repair behavior',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'q-1',
        fieldsJson: '{"name":"Q"}',
      );
      await _exchange(a, b, 'create q-1');

      await ffi.recordUpdate(
        handle: a.handle,
        table: 'members',
        entityId: 'q-1',
        changedFieldsJson: jsonEncode({'avatar_image_data': _avatarB64(900 * 1024, seed: 9)}),
      );
      final pushRes = await a.sync();
      final qcAfterPush = await ffi.quarantinedBatchCount(handle: a.handle);
      // ignore: avoid_print
      print('[QUAR] after push: pushed=${pushRes['pushed']} '
          'push_incomplete=${pushRes['push_incomplete']} error=${pushRes['error']} '
          'quarantinedBatchCount=$qcAfterPush');

      // Attempt repair (the "Repair stuck sync" action) and re-sync.
      final repaired = await ffi.repairQuarantinedBatches(handle: a.handle);
      final aAfter = await a.sync();
      await b.sync();
      await b.sync();
      final qcAfterRepair = await ffi.quarantinedBatchCount(handle: a.handle);
      final onB = await _avatarOn(b, 'q-1');
      // ignore: avoid_print
      print('[QUAR] after repair: repaired=$repaired A.pushed=${aAfter['pushed']} '
          'quarantinedBatchCount=$qcAfterRepair reachesB=${onB != null}');
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });

  // The unblock advice: re-setting the avatar with a NORMALIZED (small) version
  // must supersede the stuck oversized op and reach the peer.
  test('re-normalizing a stuck oversized avatar unblocks sync to the peer',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'fix-1',
        fieldsJson: '{"name":"Fix"}',
      );
      await _exchange(a, b, 'create fix-1');

      // 1) Oversized avatar gets stuck.
      await ffi.recordUpdate(
        handle: a.handle,
        table: 'members',
        entityId: 'fix-1',
        changedFieldsJson: jsonEncode({'avatar_image_data': _avatarB64(900 * 1024, seed: 11)}),
      );
      await _exchange(a, b, 'oversized');
      final stuck = await _avatarOn(b, 'fix-1');
      // ignore: avoid_print
      print('[FIX] after oversized: reachesB=${stuck != null} '
          'quarantined=${await ffi.quarantinedBatchCount(handle: a.handle)}');

      // 2) Re-set the SAME field with a normalized (256KB) avatar — what a
      //    re-import / re-crop on a current build produces.
      await ffi.recordUpdate(
        handle: a.handle,
        table: 'members',
        entityId: 'fix-1',
        changedFieldsJson: jsonEncode({'avatar_image_data': _avatarB64(256 * 1024, seed: 12)}),
      );
      await _exchange(a, b, 'renormalized');
      final fixed = await _avatarOn(b, 'fix-1');
      // ignore: avoid_print
      print('[FIX] after re-normalize: reachesB=${fixed != null} len=${fixed?.length} '
          'quarantined=${await ffi.quarantinedBatchCount(handle: a.handle)}');
      expect(fixed, isNotNull, reason: 're-normalized avatar must reach B and unblock the member');

      // The auto-unstick calls repair after re-emitting: the superseded
      // oversized op is dropped so the "too large to sync" banner clears
      // instead of lingering forever.
      await ffi.repairQuarantinedBatches(handle: a.handle);
      final qcAfter = (await ffi.quarantinedBatchCount(handle: a.handle)).toInt();
      // ignore: avoid_print
      print('[FIX] after repair: quarantinedBatchCount=$qcAfter');
      expect(
        qcAfter,
        0,
        reason: 'superseded oversized op must be dropped, clearing the stuck-sync banner',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });
}
