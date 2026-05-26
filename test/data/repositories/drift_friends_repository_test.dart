// test/data/repositories/drift_friends_repository_test.dart
//
// Two test groups:
//
// 1. DateTime UTC normalization (Fix X — UTC tail) — pins that every
//    DateTime emitted by `_friendFields` to the sync engine is Z-suffixed
//    UTC. Mirrors drift_conversation_repository_test.
// 2. Patch-style `updateFriend` (item #3 of the drift-repo migration plan)
//    — asserts that update emits only changed fields, no-ops on unchanged
//    input, refuses tombstoned/missing rows, never emits `is_deleted`
//    through the diff path, and pins `jsonSet` canonicalization on
//    `offered_scopes` / `granted_scopes` so reordering is not an edit.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/friends_dao.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
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

  group('updateFriend (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 1, 12);

    domain.FriendRecord makeFriend({
      String id = 'f1',
      String displayName = 'Original name',
      String? peerSharingId,
      Uint8List? pairwiseSecret,
      Uint8List? pinnedIdentity,
      List<String> offeredScopes = const <String>[],
      String publicKeyHex = 'deadbeef',
      String? sharedSecretHex,
      List<String> grantedScopes = const <String>[],
      bool isVerified = false,
      String? initId,
      DateTime? createdAt,
      DateTime? establishedAt,
      DateTime? lastSyncAt,
    }) {
      return domain.FriendRecord(
        id: id,
        displayName: displayName,
        peerSharingId: peerSharingId,
        pairwiseSecret: pairwiseSecret,
        pinnedIdentity: pinnedIdentity,
        offeredScopes: offeredScopes,
        publicKeyHex: publicKeyHex,
        sharedSecretHex: sharedSecretHex,
        grantedScopes: grantedScopes,
        isVerified: isVerified,
        initId: initId,
        createdAt: createdAt ?? baseTime,
        establishedAt: establishedAt,
        lastSyncAt: lastSyncAt,
      );
    }

    test('emits only the changed fields', () async {
      await repo.createFriend(makeFriend());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateFriend(makeFriend(displayName: 'Updated name'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'friends');
      expect(captured.single.entityId, 'f1');
      expect(captured.single.fields.keys.toSet(), {'display_name'});
      expect(captured.single.fields['display_name'], 'Updated name');
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test('emits nothing when the domain object matches the stored row',
        () async {
      await repo.createFriend(makeFriend());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateFriend(makeFriend());

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.createFriend(
        makeFriend(
          peerSharingId: 'peer-1',
          offeredScopes: const ['a', 'b'],
          grantedScopes: const ['x'],
          sharedSecretHex: 'shared',
          isVerified: true,
          initId: 'init-1',
        ),
      );

      await repo.updateFriend(
        makeFriend(
          displayName: 'Updated name',
          peerSharingId: 'peer-1',
          offeredScopes: const ['a', 'b'],
          grantedScopes: const ['x'],
          sharedSecretHex: 'shared',
          isVerified: true,
          initId: 'init-1',
        ),
      );

      final row = await dao.getById('f1');
      expect(row, isNotNull);
      expect(row!.displayName, 'Updated name');
      expect(row.peerSharingId, 'peer-1');
      expect(row.sharedSecretHex, 'shared');
      expect(row.isVerified, isTrue);
      expect(row.initId, 'init-1');
      // Scopes round-trip through canonical (sorted) jsonSet encoding.
      expect(
        (jsonDecode(row.offeredScopes) as List).cast<String>(),
        ['a', 'b'],
      );
      expect(
        (jsonDecode(row.grantedScopes) as List).cast<String>(),
        ['x'],
      );
    });

    test('null-clearing a blob column emits the null and clears the row',
        () async {
      final pinned = Uint8List.fromList(const [1, 2, 3, 4]);
      await repo.createFriend(makeFriend(pinnedIdentity: pinned));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateFriend(makeFriend(pinnedIdentity: null));

      expect(captured, hasLength(1));
      final patch = captured.single.fields;
      expect(patch.containsKey('pinned_identity'), isTrue);
      expect(patch['pinned_identity'], isNull);
      expect(patch.containsKey('is_deleted'), isFalse);

      final row = await dao.getById('f1');
      expect(row!.pinnedIdentity, isNull);
    });

    test('silently no-ops on a tombstoned row (does not emit, '
        'does not resurrect)', () async {
      await repo.createFriend(makeFriend());
      await repo.deleteFriend('f1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateFriend(makeFriend(displayName: 'Attempted edit'));

      expect(captured, isEmpty);
      final row = await dao.getById('f1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.displayName, 'Original name');
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateFriend(makeFriend(id: 'missing'));

      expect(captured, isEmpty);
      final row = await dao.getById('missing');
      expect(row, isNull);
    });

    test('reordering offered_scopes produces no diff (jsonSet canonicalizes)',
        () async {
      await repo.createFriend(
        makeFriend(offeredScopes: const ['a', 'b', 'c']),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Same scopes, reordered. Everything else identical.
      await repo.updateFriend(
        makeFriend(offeredScopes: const ['c', 'a', 'b']),
      );

      expect(
        captured,
        isEmpty,
        reason: 'set-semantic offered_scopes must canonicalize via jsonSet',
      );
    });

    test('does not emit is_deleted in the patch', () async {
      await repo.createFriend(makeFriend());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateFriend(makeFriend(displayName: 'Changed'));

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });
  });
}
