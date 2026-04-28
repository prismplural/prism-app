// test/data/repositories/drift_friends_repository_test.dart
//
// DateTime UTC normalization (Fix X — UTC tail).
//
// Pins the contract that every DateTime emitted by `_friendFields` to the
// sync engine is Z-suffixed UTC. Mirrors the pattern from
// drift_conversation_repository_test.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/friends_dao.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/domain/models/friend_record.dart' as domain;

void main() {
  late AppDatabase db;
  late FriendsDao dao;
  late DriftFriendsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = FriendsDao(db);
    repo = DriftFriendsRepository(dao, null);
  });

  tearDown(() => db.close());

  group('debugFriendFields UTC normalization', () {
    test(
      'created_at, established_at, and last_sync_at emit Z-suffixed UTC '
      'even when input is a local DateTime',
      () {
        final localCreated = DateTime(2026, 4, 27, 10, 0);
        final localEstablished = DateTime(2026, 4, 27, 11, 0);
        final localLastSync = DateTime(2026, 4, 27, 12, 0);

        final friend = domain.FriendRecord(
          id: 'f1',
          displayName: 'friend',
          publicKeyHex: 'deadbeef',
          createdAt: localCreated,
          establishedAt: localEstablished,
          lastSyncAt: localLastSync,
        );

        final fields = repo.debugFriendFields(friend);
        final createdStr = fields['created_at'] as String;
        final establishedStr = fields['established_at'] as String;
        final lastSyncStr = fields['last_sync_at'] as String;

        expect(createdStr.endsWith('Z'), isTrue, reason: createdStr);
        expect(establishedStr.endsWith('Z'), isTrue, reason: establishedStr);
        expect(lastSyncStr.endsWith('Z'), isTrue, reason: lastSyncStr);
        expect(
          DateTime.parse(createdStr).isAtSameMomentAs(localCreated.toUtc()),
          isTrue,
        );
        expect(
          DateTime.parse(establishedStr)
              .isAtSameMomentAs(localEstablished.toUtc()),
          isTrue,
        );
        expect(
          DateTime.parse(lastSyncStr).isAtSameMomentAs(localLastSync.toUtc()),
          isTrue,
        );
      },
    );

    test(
      'null established_at and last_sync_at remain null in field map',
      () {
        final friend = domain.FriendRecord(
          id: 'f2',
          displayName: 'friend',
          publicKeyHex: 'cafebabe',
          createdAt: DateTime(2026, 4, 27),
          // establishedAt and lastSyncAt left null.
        );

        final fields = repo.debugFriendFields(friend);
        expect(fields['established_at'], isNull);
        expect(fields['last_sync_at'], isNull);
      },
    );
  });
}
