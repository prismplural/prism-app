import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('getConversationsForMember', () {
    final now = DateTime.utc(2025, 1, 1);

    Future<void> insertConversation({
      required String id,
      String participantIdsJson = '[]',
      bool includesAllMembers = false,
      bool isDeleted = false,
    }) async {
      await db.into(db.conversations).insert(
            ConversationsCompanion.insert(
              id: id,
              createdAt: now,
              lastActivityAt: now,
              participantIds: Value(participantIdsJson),
              includesAllMembers: Value(includesAllMembers),
              isDeleted: Value(isDeleted),
            ),
          );
    }

    test('returns conversations where member is in participant_ids', () async {
      await insertConversation(
        id: 'c1',
        participantIdsJson: '["alice","bob"]',
      );
      await insertConversation(
        id: 'c2',
        participantIdsJson: '["carol"]',
      );

      final result = await db.conversationsDao.getConversationsForMember('alice');

      expect(result.map((c) => c.id), contains('c1'));
      expect(result.map((c) => c.id), isNot(contains('c2')));
    });

    test(
      'includes everyone-group conversations even when member is not in participant_ids',
      () async {
        await insertConversation(
          id: 'everyone',
          participantIdsJson: '[]',
          includesAllMembers: true,
        );
        await insertConversation(
          id: 'private',
          participantIdsJson: '["bob"]',
        );

        // 'alice' is not in any participantIds, but should still see the
        // everyone-group via the includes_all_members flag.
        final result =
            await db.conversationsDao.getConversationsForMember('alice');

        final ids = result.map((c) => c.id).toSet();
        expect(ids, contains('everyone'));
        expect(ids, isNot(contains('private')));
      },
    );

    test('excludes soft-deleted everyone-group conversations', () async {
      await insertConversation(
        id: 'deleted-everyone',
        participantIdsJson: '[]',
        includesAllMembers: true,
        isDeleted: true,
      );

      final result =
          await db.conversationsDao.getConversationsForMember('alice');

      expect(result, isEmpty);
    });

    test(
      'returns both explicit-participant and everyone-group conversations',
      () async {
        await insertConversation(
          id: 'explicit',
          participantIdsJson: '["alice"]',
        );
        await insertConversation(
          id: 'everyone',
          participantIdsJson: '[]',
          includesAllMembers: true,
        );

        final result =
            await db.conversationsDao.getConversationsForMember('alice');

        final ids = result.map((c) => c.id).toSet();
        expect(ids, containsAll(<String>['explicit', 'everyone']));
      },
    );
  });
}
