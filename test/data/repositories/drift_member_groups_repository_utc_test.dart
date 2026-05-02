// test/data/repositories/drift_member_groups_repository_utc_test.dart
//
// DateTime UTC normalization (Fix X — UTC tail).
//
// Pins the contract that every DateTime emitted by `_groupFields` to the
// sync engine is Z-suffixed UTC. Mirrors the pattern from
// drift_conversation_repository_test.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';

void main() {
  late AppDatabase db;
  late MemberGroupsDao dao;
  late DriftMemberGroupsRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MemberGroupsDao(db);
    // Null sync handle, no member repo — debugGroupFields is pure on the row.
    repo = DriftMemberGroupsRepository(dao, null);
  });

  tearDown(() => db.close());

  group('debugGroupFields UTC normalization', () {
    test(
      'created_at and last_seen_from_pk_at emit Z-suffixed UTC even when '
      'row stores a local DateTime',
      () async {
        final localCreated = DateTime(2026, 4, 27, 10, 0);
        final localPkSeen = DateTime(2026, 4, 27, 11, 30);

        await db
            .into(db.memberGroups)
            .insert(
              MemberGroupsCompanion.insert(
                id: 'g1',
                name: 'g',
                createdAt: localCreated,
                lastSeenFromPkAt: Value(localPkSeen),
              ),
            );

        final row = await (db.select(db.memberGroups)..limit(1)).getSingle();
        final fields = repo.debugGroupFields(row);

        final createdStr = fields['created_at'] as String;
        final pkSeenStr = fields['last_seen_from_pk_at'] as String;

        expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
        expect(pkSeenStr.endsWith('Z'), isTrue, reason: pkSeenStr);
        expect(
          DateTime.parse(createdStr).isAtSameMomentAs(localCreated.toUtc()),
          isTrue,
        );
        expect(
          DateTime.parse(pkSeenStr).isAtSameMomentAs(localPkSeen.toUtc()),
          isTrue,
        );
      },
    );

    test('null last_seen_from_pk_at remains null in field map', () async {
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'g2',
              name: 'g2',
              createdAt: DateTime(2026, 4, 27),
            ),
          );

      final row = await (db.select(db.memberGroups)..limit(1)).getSingle();
      final fields = repo.debugGroupFields(row);
      expect(fields['last_seen_from_pk_at'], isNull);
    });
  });
}
