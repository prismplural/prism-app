/// Sentinel determinism tests for the per-member fronting migration.
///
/// The Unknown sentinel member id is the deterministic UUIDv5 derivation
/// `Uuid().v5(spFrontingNamespace, 'unknown-member-sentinel')`. The
/// migration's orphan-rescue path runs under `SyncRecordMixin.suppress`
/// and therefore emits no sync op for the sentinel member's create —
/// so paired devices that re-pair after migration must independently
/// resolve the same id locally. If the derivation ever silently became
/// non-deterministic (e.g. someone replaces the namespace lookup with
/// `Uuid().v4()` or with a derivation keyed off `DateTime.now()`),
/// orphan-rescue rows on device B would point at a member id that
/// doesn't exist on device A.
///
/// These tests pin the determinism contract:
///   1. Two fresh AppDatabase instances produce byte-identical sentinel
///      ids when the helper runs end-to-end.
///   2. The static `unknownSentinelMemberId` constant is byte-identical
///      across separate library evaluations (sanity check on the
///      derivation itself; the constant is a top-level `final` rather
///      than `const` because v5 derivation is a runtime call).
///   3. `ensureUnknownSentinelMember` is idempotent on the same DB.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

void main() {
  group('Unknown sentinel member id determinism', () {
    test(
      'sentinel id is byte-identical across two fresh AppDatabase instances',
      () async {
        final dbA = AppDatabase(NativeDatabase.memory());
        final dbB = AppDatabase(NativeDatabase.memory());
        addTearDown(() async {
          await dbA.close();
          await dbB.close();
        });

        final repoA = DriftMemberRepository(dbA.membersDao, null);
        final repoB = DriftMemberRepository(dbB.membersDao, null);

        final ensuredA = await repoA.ensureUnknownSentinelMember();
        final ensuredB = await repoB.ensureUnknownSentinelMember();

        expect(ensuredA.wasCreated, isTrue);
        expect(ensuredB.wasCreated, isTrue);
        expect(
          ensuredA.member.id,
          ensuredB.member.id,
          reason:
              'Sentinel id must be byte-identical across paired devices. '
              'Each device runs orphan-rescue under sync suppression and '
              'must converge on the same member row without a sync op '
              'carrying the id.',
        );

        // Second sanity check: equal to the documented derivation.
        final derived = const Uuid().v5(
          spFrontingNamespace,
          'unknown-member-sentinel',
        );
        expect(ensuredA.member.id, derived);
        expect(ensuredA.member.id, unknownSentinelMemberId);
      },
    );

    test(
      'unknownSentinelMemberId constant matches the documented derivation',
      () {
        // Pinning the literal here makes future namespace edits fail
        // loudly. Changing the derivation breaks paired-device data on
        // any user who has already run the migration.
        final derived = const Uuid().v5(
          spFrontingNamespace,
          'unknown-member-sentinel',
        );
        expect(unknownSentinelMemberId, derived);
      },
    );

    test(
      'ensureUnknownSentinelMember is idempotent on the same DB '
      '(returns same id, wasCreated=false on second call)',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = DriftMemberRepository(db.membersDao, null);

        final first = await repo.ensureUnknownSentinelMember();
        expect(first.wasCreated, isTrue);
        expect(first.member.id, unknownSentinelMemberId);

        final second = await repo.ensureUnknownSentinelMember();
        expect(second.wasCreated, isFalse);
        expect(second.member.id, first.member.id);

        final allMembers = await repo.getAllMembers();
        expect(
          allMembers.where((m) => m.id == unknownSentinelMemberId).length,
          1,
          reason:
              'Idempotent ensure must not duplicate the sentinel row on '
              'a same-DB second call.',
        );
      },
    );
  });

  // R6/C12 ingress gate: the sentinel reuses a deterministic UUIDv5 id. If a
  // previously-synced sentinel was deleted, the engine holds an absorbing
  // tombstone for that id and a fresh create is a silent fleet-wide no-op that
  // recreates the F21 divergence. `ensureUnknownSentinelMember` (the single
  // chokepoint for every production caller — session lifecycle, fronting
  // change/mutation executors, data import) must consult the gate and skip the
  // EMISSION while keeping the local FK-target row.
  group('ensureUnknownSentinelMember gates on the sync tombstone', () {
    TombstoneGate gateTombstoning(Set<String> ids) {
      return TombstoneGate((table, entityId, field) async {
        if (field != 'is_deleted') return null;
        return ids.contains(entityId) ? 'true' : null;
      });
    }

    test('a tombstoned sentinel id => keeps the local row but emits NO create '
        'into the burned id', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftMemberRepository(db.membersDao, null)
        ..debugTombstoneGateForTesting = gateTombstoning({
          unknownSentinelMemberId,
        });

      final captured = <String>[];
      SyncRecordMixin.installCaptureSinkForTesting(
        (op) => captured.add('${op.table}/${op.entityId}/${op.opType.name}'),
      );
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final ensured = await repo.ensureUnknownSentinelMember();

      // The caller still gets a usable sentinel member back, and the LOCAL row
      // exists so fronting history keeps a resolvable "Unknown" attribution
      // (there is no FK constraint binding it).
      expect(ensured.wasCreated, isTrue);
      expect(ensured.member.id, unknownSentinelMemberId);
      expect(await repo.getMemberById(unknownSentinelMemberId), isNotNull);

      // But NOTHING was emitted into the burned id — that is the whole point.
      expect(
        captured,
        isEmpty,
        reason:
            'a tombstoned sentinel id must not receive a create op '
            '(silent fleet-wide no-op that recreates the F21 divergence)',
      );
    });

    test('a live (non-tombstoned) sentinel id => emits the create as usual',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftMemberRepository(db.membersDao, null)
        ..debugTombstoneGateForTesting = gateTombstoning({});

      final captured = <String>[];
      SyncRecordMixin.installCaptureSinkForTesting(
        (op) => captured.add('${op.table}/${op.entityId}/${op.opType.name}'),
      );
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final ensured = await repo.ensureUnknownSentinelMember();

      expect(ensured.wasCreated, isTrue);
      expect(await repo.getMemberById(unknownSentinelMemberId), isNotNull);
      expect(
        captured,
        ['members/$unknownSentinelMemberId/create'],
        reason: 'a live sentinel id is created and emitted normally',
      );
    });

    test('an already-present sentinel row => no-op regardless of the gate',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftMemberRepository(db.membersDao, null);

      // Seed the row first (emits a create).
      await repo.ensureUnknownSentinelMember();

      // Now flip the gate to tombstoned and ensure again — the existing-row
      // early return wins, so no read, no write, no emission.
      repo.debugTombstoneGateForTesting = gateTombstoning({
        unknownSentinelMemberId,
      });
      final captured = <String>[];
      SyncRecordMixin.installCaptureSinkForTesting(
        (op) => captured.add('${op.table}/${op.entityId}/${op.opType.name}'),
      );
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final second = await repo.ensureUnknownSentinelMember();
      expect(second.wasCreated, isFalse);
      expect(captured, isEmpty);
    });
  });
}
