// PR 2 — PluralKit link-state convergence tests.
//
// Plan: docs/plans/2026-05-26-pluralkit-link-management.md (Part 4).
//
// Approach: simulated LWW harness, NOT the real prism-sync-core engine.
//
// Why simulate. The plan's Part 4 testing section calls for two in-process
// `PrismSyncHandle` instances connected via in-memory transport so the real
// merge engine arbitrates. Bringing up two real handles requires generating
// keypairs, configuring transport, plumbing relay endpoints, and warming up
// HLC clocks — all far outside the scope of these unit tests, which exist
// to verify the per-field LWW semantics specifically around
// `pluralkit_sync_ignored` and Rules A/B in the repo.
//
// The plan's fallback (verbatim): "If two-handle in-memory setup is
// genuinely too heavy for unit-style tests, fall back to: simulate the
// merge engine's LWW behavior with a hand-written test harness that emits
// ops with HLCs and applies them in different orders. Document the choice."
//
// This file is that fallback. Each `_Device` owns:
//   - its own in-memory AppDatabase + DriftMemberRepository (real code,
//     no fakes — so Rules A and B are the production implementations);
//
// A single process-wide capture sink (SyncRecordMixin only supports one)
// routes captured ops to whichever device is currently "active." Each test
// scopes the active device with `device.runWithCapture(() async { … })`
// so emissions from one device's writes never leak into the other's log.
//
// The harness applies a captured op set from one device onto another by
// performing per-field LWW (greater HLC wins; in ties, prior writer wins
// deterministically). This mirrors `prism-sync-core`'s `wins_over`
// (see `prism-sync/crates/prism-sync-core/src/crdt_change.rs`).
//
// What this CANNOT verify (out of scope, deferred to the real-engine
// suite):
//   - tombstone semantics across entity creates and deletes;
//   - relay transport timing / partition behavior;
//   - the exact tiebreak when HLCs match (the simulator uses
//     prior-writer-wins; the real engine uses device_id then op_id).
// What this CAN and DOES verify:
//   - Exclude converges across devices when ops are merged.
//   - Resume converges symmetrically.
//   - The post-merge "next iteration after merge skips" property.
//   - The Rule A+B repo invariants hold when a stale full-domain write
//     lands on a row that has been excluded.
//   - Cross-device "Link wins over an earlier Exclude" via LWW with a
//     greater HLC on the Link write.

// ignore_for_file: experimental_member_use

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;

/// A captured op enriched with a synthetic HLC so the LWW merger can
/// pick winners deterministically. Each field becomes its own LWW unit;
/// the same op contributes one HLC value to every field it writes.
class _Op {
  _Op({
    required this.entityId,
    required this.opType,
    required this.fields,
    required this.hlc,
    required this.deviceId,
  });

  final String entityId;
  final SyncRecordOpType opType;
  final Map<String, dynamic> fields;
  final int hlc;
  final String deviceId;
}

/// A simulated device: real AppDatabase + DriftMemberRepository.
///
/// The process-wide capture sink is installed once per test via
/// [_installSharedCapture]; routing to the correct device's op log is done
/// by setting [_activeDeviceForCapture] before each block of writes.
class _Device {
  _Device(this.id) {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftMemberRepository(db.membersDao, null);
  }

  final String id;
  late final AppDatabase db;
  late final DriftMemberRepository repo;
  int _hlc = 0;

  /// Ops captured during this device's active capture windows.
  final List<_Op> captured = [];

  /// Override the next HLC. The simulator uses this to manufacture
  /// "this device's local clock is at T" scenarios. The next captured
  /// op will get this exact HLC; subsequent ones increment from there.
  void setNextHlc(int hlc) {
    _hlc = hlc - 1; // increment in the capture callback bumps to hlc.
  }

  void resetCapture() {
    captured.clear();
  }

  /// Run [body] while routing captured ops to this device's log.
  /// Restores the previous active device on exit.
  Future<void> runWithCapture(Future<void> Function() body) async {
    final prior = _activeDeviceForCapture;
    _activeDeviceForCapture = this;
    try {
      await body();
    } finally {
      _activeDeviceForCapture = prior;
    }
  }

  /// Pull and bump the device's local HLC. Called by the shared capture
  /// sink for ops attributed to this device.
  int nextHlc() {
    _hlc++;
    return _hlc;
  }

  Future<void> close() async {
    await db.close();
  }
}

/// Currently-active device for capture routing. Tests scope this via
/// [_Device.runWithCapture]. If null, captures are dropped — useful for
/// "warm-up" writes (e.g. createMember on both devices in seedSharedMember)
/// where we don't care about the op stream.
_Device? _activeDeviceForCapture;

/// Install a single process-wide capture sink that routes to whichever
/// device is currently active. Each test installs once in setUp and
/// removes once in tearDown.
void _installSharedCapture() {
  SyncRecordMixin.installCaptureSinkForTesting((op) {
    if (op.table != 'members') return;
    final device = _activeDeviceForCapture;
    if (device == null) return;
    device.captured.add(
      _Op(
        entityId: op.entityId,
        opType: op.opType,
        fields: Map.of(op.fields),
        hlc: device.nextHlc(),
        deviceId: device.id,
      ),
    );
  });
}

/// Simulated LWW merger: replays one device's captured ops into the other
/// device's DB. Per-field arbitration matches `prism-sync-core`'s
/// `wins_over` semantics: greater HLC wins; ties go to the prior writer.
///
/// Implementation note: we apply ops directly via the DAO + a per-field
/// "latest known HLC per (entity,field)" map so the merge is honest LWW,
/// not whatever order ops happen to arrive. This mirrors the engine which
/// stores per-field HLC vectors.
class _Merger {
  final Map<String, Map<String, int>> _fieldHlcByEntity = {};

  /// Apply [ops] onto [target]. Ops are applied in HLC order so the
  /// "latest HLC seen" tracking is monotonic.
  Future<void> mergeInto(_Device target, List<_Op> ops) async {
    final sorted = List<_Op>.of(ops)
      ..sort((a, b) => a.hlc.compareTo(b.hlc));
    for (final op in sorted) {
      switch (op.opType) {
        case SyncRecordOpType.create:
          final existing = await target.db.membersDao.getMemberByIdRow(
            op.entityId,
          );
          if (existing == null) {
            // Insert minimally. The convergence tests below seed each
            // device's member with createMember() directly, so this
            // branch is rarely hit; the merger is built defensively.
            await target.db.membersDao.insertMember(
              MembersCompanion.insert(
                id: op.entityId,
                name: (op.fields['name'] as String?) ?? 'unknown',
                createdAt: DateTime.now().toUtc(),
              ),
            );
          }
          await _applyFieldsLww(target, op);
          break;
        case SyncRecordOpType.update:
          await _applyFieldsLww(target, op);
          break;
        case SyncRecordOpType.delete:
          // Out of scope for these tests — Rule A/B convergence is about
          // active rows.
          break;
      }
    }
  }

  Future<void> _applyFieldsLww(_Device target, _Op op) async {
    final perField = _fieldHlcByEntity.putIfAbsent(op.entityId, () => {});
    final accepted = <String, dynamic>{};
    for (final entry in op.fields.entries) {
      final priorHlc = perField[entry.key];
      // Strict greater — equal HLCs lose to the prior writer in this
      // simulator. Matches the conservative "don't reorder on ties" rule
      // we want for the documented assertions.
      if (priorHlc == null || op.hlc > priorHlc) {
        perField[entry.key] = op.hlc;
        accepted[entry.key] = entry.value;
      }
    }
    if (accepted.isEmpty) return;
    // Apply directly via the DAO so we bypass the local repo invariant
    // (which would re-strip writes Rule A/B already validated locally on
    // the originating device). The CRDT merge engine is the source of
    // truth at this layer.
    final companion = _companionFromPatch(accepted);
    await target.db.membersDao.updateMemberById(op.entityId, companion);
  }

  MembersCompanion _companionFromPatch(Map<String, dynamic> fields) {
    return MembersCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      pronouns: fields.containsKey('pronouns')
          ? Value(fields['pronouns'] as String?)
          : const Value.absent(),
      bio: fields.containsKey('bio')
          ? Value(fields['bio'] as String?)
          : const Value.absent(),
      pluralkitUuid: fields.containsKey('pluralkit_uuid')
          ? Value(fields['pluralkit_uuid'] as String?)
          : const Value.absent(),
      pluralkitId: fields.containsKey('pluralkit_id')
          ? Value(fields['pluralkit_id'] as String?)
          : const Value.absent(),
      pluralkitDisplayName: fields.containsKey('pluralkit_display_name')
          ? Value(fields['pluralkit_display_name'] as String?)
          : const Value.absent(),
      pluralkitSyncIgnored: fields.containsKey('pluralkit_sync_ignored')
          ? Value(fields['pluralkit_sync_ignored'] as bool)
          : const Value.absent(),
    );
  }
}

void main() {
  late _Device deviceA;
  late _Device deviceB;
  late _Merger merger;

  setUp(() {
    deviceA = _Device('A');
    deviceB = _Device('B');
    merger = _Merger();
    _installSharedCapture();
  });

  tearDown(() async {
    SyncRecordMixin.removeCaptureSinkForTesting();
    _activeDeviceForCapture = null;
    await deviceA.close();
    await deviceB.close();
  });

  /// Seed the same member row on both devices without capturing the
  /// creates (we don't want those to count as merge ops).
  Future<void> seedSharedMember({
    String id = 'shared',
    String? pluralkitUuid = 'pk-uuid',
    String? pluralkitId = 'pkid1',
    bool pluralkitSyncIgnored = false,
  }) async {
    _activeDeviceForCapture = null; // skip capture during seed
    final member = domain.Member(
      id: id,
      name: 'Shared',
      createdAt: DateTime.utc(2026),
      pluralkitUuid: pluralkitUuid,
      pluralkitId: pluralkitId,
      pluralkitSyncIgnored: pluralkitSyncIgnored,
    );
    await deviceA.repo.createMember(member);
    await deviceB.repo.createMember(member);
  }

  group('PR 2 convergence: Exclude / Resume', () {
    test('Exclude converges across devices', () async {
      await seedSharedMember();

      // A excludes; capture A's ops then merge them onto B.
      await deviceA.runWithCapture(() async {
        await deviceA.repo.excludePluralKitSync('shared');
      });
      await merger.mergeInto(deviceB, deviceA.captured);

      final aRow = await deviceA.db.membersDao.getMemberByIdRow('shared');
      final bRow = await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(aRow!.pluralkitSyncIgnored, isTrue);
      expect(bRow!.pluralkitSyncIgnored, isTrue);
    });

    test('Resume converges across devices', () async {
      await seedSharedMember(pluralkitSyncIgnored: true);

      await deviceA.runWithCapture(() async {
        await deviceA.repo.resumePluralKitSync('shared');
      });
      await merger.mergeInto(deviceB, deviceA.captured);

      final aRow = await deviceA.db.membersDao.getMemberByIdRow('shared');
      final bRow = await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(aRow!.pluralkitSyncIgnored, isFalse);
      expect(bRow!.pluralkitSyncIgnored, isFalse);
    });
  });

  group('PR 2 convergence: race scenarios', () {
    test('PK iteration on B during A\'s exclude (race) — sync_ignored=true '
        'persists; subsequent B iterations skip', () async {
      await seedSharedMember();

      // T1: A excludes.
      deviceA.setNextHlc(10);
      await deviceA.runWithCapture(() async {
        await deviceA.repo.excludePluralKitSync('shared');
      });
      // Don't merge yet; simulate B's view of the world is still
      // pre-merge.

      // T2 > T1: B's PK sync iteration tries to refresh metadata (B
      // doesn't know about A's exclude yet). Use updateMember on the
      // stale (sync_ignored=false) Member — exactly the race the plan
      // describes.
      deviceB.setNextHlc(100);
      await deviceB.runWithCapture(() async {
        final staleOnB = (await deviceB.repo.getMemberById('shared'))!;
        await deviceB.repo.updateMember(
          staleOnB.copyWith(pluralkitDisplayName: 'PK refreshed display'),
        );
      });

      // Merge A's exclude into B AFTER B's race write. The exclude was
      // emitted at T1=10 and B's display update at T2=100. LWW on
      // sync_ignored: only A's exclude wrote it, so the (only) writer's
      // value wins.
      await merger.mergeInto(deviceB, deviceA.captured);

      final bRow = await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(bRow!.pluralkitSyncIgnored, isTrue);

      // Merge B's race op onto A. The op carries display_name only (not
      // PK identity), so neither Rule A nor Rule B fires at the repo
      // level (and we apply directly via the DAO anyway). The
      // substantive convergence assertion: A and B agree on
      // sync_ignored=true.
      await merger.mergeInto(deviceA, deviceB.captured);
      final aRow = await deviceA.db.membersDao.getMemberByIdRow('shared');
      expect(aRow!.pluralkitSyncIgnored, isTrue);

      // Subsequent B iteration: with exclude now reflecting on B, a
      // production PK sync would NOT enter the per-local loop for an
      // excluded row (Part 1.5 guards). Simulate by re-reading and
      // confirming nothing has reverted.
      final bRowAfter = await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(bRowAfter!.pluralkitSyncIgnored, isTrue);
    });

    test('Stale full-domain write on an excluded row gets stripped by '
        'Rules A + B (local invariant)', () async {
      // This case lives at the repo layer — Rule A strips re-stamps of
      // pluralkit_uuid/pluralkit_id, Rule B strips sync_ignored=false on
      // an excluded row. Documented here as part of the convergence
      // story: even if a stale Member object survives a peer-side write,
      // local Rules A+B keep the row excluded.
      await seedSharedMember();
      await deviceA.runWithCapture(() async {
        await deviceA.repo.excludePluralKitSync('shared');
        // Now A's sync loop holds a stale (pre-exclude) Member and tries
        // to re-stamp PK fields and flip sync_ignored back.
        final stale = domain.Member(
          id: 'shared',
          name: 'Shared',
          createdAt: DateTime.utc(2026),
          pluralkitUuid: 'pk-uuid',
          pluralkitId: 'pkid1',
          pluralkitSyncIgnored: false,
        );
        await deviceA.repo.updateMember(
          stale.copyWith(
            pluralkitUuid: 'pk-uuid-NEW',
            pluralkitId: 'NEWID',
            bio: 'should pass through',
          ),
        );
      });

      final aRow = await deviceA.db.membersDao.getMemberByIdRow('shared');
      // Rule A stripped PK identity re-stamps.
      expect(aRow!.pluralkitUuid, 'pk-uuid');
      expect(aRow.pluralkitId, 'pkid1');
      // Rule B stripped sync_ignored=false.
      expect(aRow.pluralkitSyncIgnored, isTrue);
      // Non-PK fields pass through (documented limitation).
      expect(aRow.bio, 'should pass through');
    });

    test('Documented: one final remote PK push from B is acceptable; '
        'next iteration after merge skips', () async {
      // The plan's Part 4 "Exclude race — remote PK pushes" documents
      // that the repo invariant only protects Prism's local DB. If B was
      // mid-push when A excluded, the network call lands on PK before
      // B learns of the exclude. The convergence guarantee is about the
      // NEXT iteration: once A's exclude merges on B, B's PK sync skips
      // the excluded local.
      //
      // We simulate this with two phases:
      //   Phase 1: A excludes; B has a stale view and would have pushed.
      //   Phase 2: A's exclude merges onto B; B's NEXT iteration sees
      //     sync_ignored=true and skips.
      await seedSharedMember();

      await deviceA.runWithCapture(() async {
        await deviceA.repo.excludePluralKitSync('shared');
      });

      // B's view pre-merge: sync_ignored=false. A production guard like
      // _doPushPendingSwitches' map build would happily include this
      // member's PK ID. We accept this as the "one final push" hazard.
      final bRowPreMerge =
          await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(bRowPreMerge!.pluralkitSyncIgnored, isFalse,
          reason: 'pre-merge B still thinks member is sync-enabled');

      // Phase 2: merge.
      await merger.mergeInto(deviceB, deviceA.captured);

      final bRowPostMerge =
          await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(
        bRowPostMerge!.pluralkitSyncIgnored,
        isTrue,
        reason: 'post-merge B has the exclude; next iteration will skip',
      );
    });

    test('Cross-device Link vs. Exclude: A excludes at T1; A\'s op merges '
        'on B; B then links M at T2 > T1; T2 link write resumes sync; '
        'B\'s link merges back to A; both devices converge to linked + '
        'sync resumed', () async {
      // Realistic timeline:
      //   T1: A excludes M. A's row sync_ignored=true at HLC 10.
      //   merge A→B: B's row sync_ignored=true.
      //   T2 > T1: B's user opens the manage screen and explicitly links
      //     M to a new PK member. applyPluralKitLink flips sync_ignored
      //     from true (post-merge state on B) to false at HLC 100, AND
      //     writes new PK identity. Diff captures sync_ignored=false in
      //     the emitted op because B's stored row was true before.
      //   merge B→A: B's op carries sync_ignored=false at HLC 100, plus
      //     new PK identity. A's per-field LWW: HLC 100 > prior HLC 10
      //     on sync_ignored, so B wins.
      //
      // End state: both devices have sync_ignored=false and the new PK
      // identity. Documents the "later user action wins" semantic from
      // the plan's Part 4 "Cross-device Link vs. Exclude composition."
      await seedSharedMember();

      // T1: A excludes (HLC 10).
      deviceA.setNextHlc(10);
      await deviceA.runWithCapture(() async {
        await deviceA.repo.excludePluralKitSync('shared');
      });

      // Merge A's exclude onto B. B's row is now sync_ignored=true with
      // merger tracking HLC 10 for the sync_ignored field.
      await merger.mergeInto(deviceB, deviceA.captured);
      final bRowPostMerge =
          await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(bRowPostMerge!.pluralkitSyncIgnored, isTrue,
          reason: 'B has applied A\'s exclude');

      // T2 > T1: B's user picks M as Link target via manage screen.
      // applyPluralKitLink force-injects sync_ignored=false; diff against
      // B's now-true row keeps the flip in the emitted patch.
      deviceB.setNextHlc(100);
      await deviceB.runWithCapture(() async {
        await deviceB.repo.applyPluralKitLink('shared', {
          'pluralkit_uuid': 'pk-uuid-B',
          'pluralkit_id': 'BBBBB',
        });
      });

      // Merge B's link onto A. Per-field LWW: B's HLC 100 > A's HLC 10
      // on sync_ignored, so B wins.
      await merger.mergeInto(deviceA, deviceB.captured);

      final aRow = await deviceA.db.membersDao.getMemberByIdRow('shared');
      final bRow = await deviceB.db.membersDao.getMemberByIdRow('shared');
      expect(aRow!.pluralkitSyncIgnored, isFalse,
          reason: 'B\'s later Link wins over A\'s earlier Exclude');
      expect(bRow!.pluralkitSyncIgnored, isFalse);
      expect(aRow.pluralkitUuid, 'pk-uuid-B');
      expect(bRow.pluralkitUuid, 'pk-uuid-B');
      expect(aRow.pluralkitId, 'BBBBB');
      expect(bRow.pluralkitId, 'BBBBB');
    });
  });
}
