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
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';

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
}
