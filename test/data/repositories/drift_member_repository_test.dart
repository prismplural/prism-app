// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/chat_message.dart'
    as chat_message_domain;
import 'package:prism_plurality/domain/models/conversation.dart'
    as conversation_domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

/// Wraps a real MembersDao and overrides only the methods the
/// `ensureUnknownSentinelMember` path touches. `insertMember` always
/// throws the configured exception. `getMemberById` returns null on the
/// first call (so the repo decides to insert), then forwards to the
/// underlying DAO (so the post-failure refetch sees whatever the test
/// pre-populated). This lets us drive the race-loser catch path
/// deterministically.
class _RacingDao implements MembersDao {
  _RacingDao(this._delegate, this._toThrow);

  final MembersDao _delegate;
  final Object _toThrow;
  int _getCalls = 0;

  @override
  Future<int> insertMember(MembersCompanion member) async {
    throw _toThrow;
  }

  @override
  Future<Member?> getMemberById(String id) async {
    _getCalls++;
    if (_getCalls == 1) return null;
    return _delegate.getMemberById(id);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      Function.apply(_delegate.noSuchMethod, [invocation]);
}

void main() {
  late AppDatabase db;
  late MembersDao dao;
  late DriftMemberRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.membersDao;
    // Pass null for sync handle so syncRecordCreate is a no-op.
    repo = DriftMemberRepository(dao, null);
  });

  tearDown(() async {
    await db.close();
  });

  group('watchQuickFrontMembersForList', () {
    test(
      'returns current fronters first, then frequent non-fronters',
      () async {
        final now = DateTime(2026, 1, 1, 12);
        Future<void> createMember(String id, String name, int order) {
          return dao.insertMember(
            MembersCompanion.insert(
              id: id,
              name: name,
              createdAt: now,
              displayOrder: Value(order),
              avatarImageData: Value(Uint8List.fromList(const [1, 2, 3])),
              profileHeaderImageData: Value(
                Uint8List.fromList(const [4, 5, 6]),
              ),
            ),
          );
        }

        await createMember('a', 'Alex', 0);
        await createMember('b', 'Bea', 1);
        await createMember('c', 'Cy', 2);
        await createMember('d', 'Dev', 3);
        await createMember('e', 'Eli', 4);
        await createMember(unknownSentinelMemberId, 'Unknown', 99);

        Future<void> insertFront(String id, String memberId, DateTime start) {
          return db
              .into(db.frontingSessions)
              .insert(
                FrontingSessionsCompanion.insert(
                  id: id,
                  startTime: start,
                  memberId: Value(memberId),
                  endTime: Value(start.add(const Duration(minutes: 15))),
                ),
              );
        }

        await db
            .into(db.frontingSessions)
            .insert(
              FrontingSessionsCompanion.insert(
                id: 'active-b',
                startTime: now.subtract(const Duration(minutes: 30)),
                memberId: const Value('b'),
              ),
            );
        await db
            .into(db.frontingSessions)
            .insert(
              FrontingSessionsCompanion.insert(
                id: 'active-c',
                startTime: now.subtract(const Duration(minutes: 10)),
                memberId: const Value('c'),
              ),
            );
        for (var i = 0; i < 3; i++) {
          await insertFront('d-$i', 'd', now.subtract(Duration(hours: i + 1)));
        }
        for (var i = 0; i < 2; i++) {
          await insertFront('e-$i', 'e', now.subtract(Duration(hours: i + 5)));
        }
        await insertFront('a-0', 'a', now.subtract(const Duration(hours: 9)));
        for (var i = 0; i < 4; i++) {
          await insertFront(
            'unknown-$i',
            unknownSentinelMemberId,
            now.subtract(Duration(hours: i + 10)),
          );
        }

        final members = await repo
            .watchQuickFrontMembersForList(
              recentLimit: 20,
              suggestionLimit: 2,
              excludedSuggestionMemberId: unknownSentinelMemberId,
            )
            .first;

        expect([for (final member in members) member.id], ['c', 'b', 'd', 'e']);
        expect(
          members.any((member) => member.avatarImageData != null),
          isFalse,
        );
        expect(
          members.any((member) => member.profileHeaderImageData != null),
          isFalse,
        );
      },
    );
  });

  group('ensureUnknownSentinelMember', () {
    test(
      'first call creates the sentinel and reports wasCreated=true',
      () async {
        final result = await repo.ensureUnknownSentinelMember();
        expect(result.wasCreated, isTrue);
        expect(result.member.id, unknownSentinelMemberId);

        final fetched = await repo.getMemberById(unknownSentinelMemberId);
        expect(fetched, isNotNull);
        expect(fetched!.id, unknownSentinelMemberId);
      },
    );

    test('second call is idempotent and reports wasCreated=false', () async {
      final first = await repo.ensureUnknownSentinelMember();
      expect(first.wasCreated, isTrue);

      final second = await repo.ensureUnknownSentinelMember();
      expect(second.wasCreated, isFalse);
      expect(second.member.id, unknownSentinelMemberId);

      // Exactly one row in the table for the sentinel id.
      final all = await repo.getAllMembers();
      expect(all.where((m) => m.id == unknownSentinelMemberId).length, 1);
    });

    test(
      'returns wasCreated=false when the sentinel was pre-inserted via the DAO',
      () async {
        // Pre-insert directly through the DAO to simulate a row that
        // already existed before this code path runs. The repo should
        // observe it on the initial getMemberById and short-circuit.
        await dao.insertMember(
          MembersCompanion.insert(
            id: unknownSentinelMemberId,
            name: 'Unknown',
            createdAt: DateTime.now().toUtc(),
            emoji: const Value('PRE'),
          ),
        );

        final result = await repo.ensureUnknownSentinelMember();
        expect(result.wasCreated, isFalse);
        // Existing row must be returned untouched (not overwritten).
        expect(result.member.emoji, 'PRE');
      },
    );

    test('two concurrent calls converge — exactly one wasCreated=true, '
        'no thrown exceptions, single row in the table', () async {
      // Drift queues writes on a single connection so the second future
      // typically observes the row from the first; this test guards the
      // defense-in-depth path by also asserting the catch arm is well
      // behaved if the race ever does materialize.
      final results = await Future.wait([
        repo.ensureUnknownSentinelMember(),
        repo.ensureUnknownSentinelMember(),
      ]);

      expect(results, hasLength(2));
      for (final r in results) {
        expect(r.member.id, unknownSentinelMemberId);
      }

      final createdCount = results.where((r) => r.wasCreated).length;
      expect(
        createdCount,
        lessThanOrEqualTo(1),
        reason: 'at most one caller can be the creator',
      );

      final all = await repo.getAllMembers();
      expect(
        all.where((m) => m.id == unknownSentinelMemberId).length,
        1,
        reason: 'exactly one sentinel row regardless of races',
      );
    });

    test('simulated PK constraint violation in insertMember is caught and '
        'the winner is refetched', () async {
      // Pre-insert the "winning" row directly through the DAO so the
      // post-failure refetch in the repo finds something to return.
      await dao.insertMember(
        MembersCompanion.insert(
          id: unknownSentinelMemberId,
          name: 'Winner',
          createdAt: DateTime.now().toUtc(),
          emoji: const Value('WIN'),
        ),
      );

      // _RacingDao returns null on the first getMemberById (so the
      // repo decides to insert), throws PK violation on insertMember
      // (simulating the racing winner already inserted), then forwards
      // the second getMemberById to the real DAO so the refetch sees
      // the winning row.
      final pkException = SqliteException(
        extendedResultCode: 1555, // SQLITE_CONSTRAINT_PRIMARYKEY
        message: 'PRIMARY KEY constraint failed: members.id',
      );
      final racingDao = _RacingDao(dao, pkException);
      final racingRepo = DriftMemberRepository(racingDao, null);

      final result = await racingRepo.ensureUnknownSentinelMember();
      expect(result.wasCreated, isFalse);
      expect(result.member.id, unknownSentinelMemberId);
      expect(result.member.emoji, 'WIN');
    });

    test('a non-constraint exception in insertMember is rethrown', () async {
      // The repo must not swallow arbitrary errors — only SQLite
      // unique/PK constraint violations. A generic StateError must
      // propagate.
      final boom = StateError('disk on fire');
      final racingDao = _RacingDao(dao, boom);
      final boomRepo = DriftMemberRepository(racingDao, null);

      await expectLater(
        boomRepo.ensureUnknownSentinelMember(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('deleteMember sentinel guard', () {
    test('refuses to delete the Unknown sentinel', () async {
      // Pre-create the sentinel so we know there's a row to "delete."
      await repo.ensureUnknownSentinelMember();

      await expectLater(
        repo.deleteMember(unknownSentinelMemberId),
        throwsA(isA<StateError>()),
      );

      // Sentinel must still be present and not soft-deleted.
      final fetched = await repo.getMemberById(unknownSentinelMemberId);
      expect(fetched, isNotNull);
      expect(fetched!.isDeleted, isFalse);
    });

    test('still deletes ordinary members', () async {
      final member = domain.Member(
        id: 'ordinary-1',
        name: 'Ordinary',
        createdAt: DateTime.now().toUtc(),
      );
      await repo.createMember(member);

      await repo.deleteMember('ordinary-1');

      // softDeleteMember filters by is_deleted=false in the watch streams,
      // but getMemberById returns the row regardless — verify it's flagged.
      final fetched = await repo.getMemberById('ordinary-1');
      expect(fetched, isNotNull);
      expect(fetched!.isDeleted, isTrue);
    });

    test('removes deleted members from group membership entries', () async {
      final now = DateTime(2026, 5, 11, 12);
      final repoWithGroups = DriftMemberRepository(
        dao,
        null,
        memberGroupsDao: db.memberGroupsDao,
      );
      await repoWithGroups.createMember(
        domain.Member(id: 'grouped', name: 'Grouped', createdAt: now),
      );
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'group-1',
              name: 'Group',
              createdAt: now,
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: 'entry-1',
              groupId: 'group-1',
              memberId: 'grouped',
            ),
          );

      await repoWithGroups.deleteMember('grouped');

      expect(await db.memberGroupsDao.entriesForGroup('group-1'), isEmpty);
      final tombstone = await (db.select(
        db.memberGroupEntries,
      )..where((entry) => entry.id.equals('entry-1'))).getSingle();
      expect(tombstone.isDeleted, isTrue);
    });

    test('removes deleted members from chat participant metadata', () async {
      final now = DateTime(2026, 5, 9, 12);
      final conversationRepo = DriftConversationRepository(
        db.conversationsDao,
        null,
      );
      final chatMessageRepo = DriftChatMessageRepository(
        db.chatMessagesDao,
        null,
      );
      final repoWithConversations = DriftMemberRepository(
        dao,
        null,
        conversationsDao: db.conversationsDao,
      );

      for (final member in [
        domain.Member(id: 'owner', name: 'Owner', createdAt: now),
        domain.Member(id: 'deleted', name: 'Deleted', createdAt: now),
        domain.Member(id: 'other', name: 'Other', createdAt: now),
      ]) {
        await repoWithConversations.createMember(member);
      }

      await conversationRepo.createConversation(
        conversation_domain.Conversation(
          id: 'conv-1',
          createdAt: now,
          lastActivityAt: now,
          title: 'Group',
          creatorId: 'deleted',
          participantIds: const ['owner', 'deleted', 'other'],
          archivedByMemberIds: const ['deleted', 'owner'],
          mutedByMemberIds: const ['deleted'],
          lastReadTimestamps: {
            for (final id in ['deleted', 'owner']) id: now,
          },
        ),
      );
      await chatMessageRepo.createMessage(
        chat_message_domain.ChatMessage(
          id: 'message-1',
          content: 'historical content stays',
          timestamp: now,
          authorId: 'deleted',
          conversationId: 'conv-1',
        ),
      );

      await repoWithConversations.deleteMember('deleted');

      final conversation = await conversationRepo.getConversationById('conv-1');
      expect(conversation, isNotNull);
      expect(conversation!.participantIds, ['owner', 'other']);
      expect(conversation.archivedByMemberIds, ['owner']);
      expect(conversation.mutedByMemberIds, isEmpty);
      expect(conversation.lastReadTimestamps.keys, ['owner']);
      expect(conversation.creatorId, 'owner');

      final message = await chatMessageRepo.getMessageById('message-1');
      expect(message, isNotNull);
      expect(message!.content, 'historical content stays');
      expect(message.authorId, 'deleted');

      final deleted = await repoWithConversations.getMemberById('deleted');
      expect(deleted, isNotNull);
      expect(deleted!.isDeleted, isTrue);
    });

    test('tombstones member profile preferences for deleted members', () async {
      final now = DateTime(2026, 5, 23, 12);
      final repoWithPreferences = DriftMemberRepository(
        dao,
        null,
        preferenceValuesDao: db.preferenceValuesDao,
      );
      await repoWithPreferences.createMember(
        domain.Member(id: 'member-with-prefs', name: 'Prefs', createdAt: now),
      );
      await db
          .into(db.memberProfilePreferenceValues)
          .insert(
            MemberProfilePreferenceValuesCompanion.insert(
              id: 'bWVtYmVyLXdpdGgtcHJlZnM:profile.example',
              memberId: 'member-with-prefs',
              key: 'profile.example',
              valueType: 'bool',
              valueJson: const Value('true'),
            ),
          );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repoWithPreferences.deleteMember('member-with-prefs');

      final row =
          await (db.select(db.memberProfilePreferenceValues)..where(
                (p) => p.id.equals('bWVtYmVyLXdpdGgtcHJlZnM:profile.example'),
              ))
              .getSingle();
      expect(row.isDeleted, isTrue);
      expect(row.valueJson, null);
      expect(
        captured
            .where((op) => op.table == 'member_profile_preference_values')
            .single
            .opType,
        SyncRecordOpType.delete,
      );
    });
  });

  group('isAlwaysFronting round-trip', () {
    test('persists isAlwaysFronting=true through create + read', () async {
      final member = domain.Member(
        id: 'always-1',
        name: 'Host',
        createdAt: DateTime.now().toUtc(),
        isAlwaysFronting: true,
      );
      await repo.createMember(member);

      final fetched = await repo.getMemberById('always-1');
      expect(fetched, isNotNull);
      expect(fetched!.isAlwaysFronting, isTrue);
    });

    test('defaults to false when not specified', () async {
      final member = domain.Member(
        id: 'default-1',
        name: 'Default',
        createdAt: DateTime.now().toUtc(),
      );
      await repo.createMember(member);

      final fetched = await repo.getMemberById('default-1');
      expect(fetched, isNotNull);
      expect(fetched!.isAlwaysFronting, isFalse);
    });

    test('updateMember can flip the flag from false → true', () async {
      final member = domain.Member(
        id: 'flip-1',
        name: 'Flip',
        createdAt: DateTime.now().toUtc(),
      );
      await repo.createMember(member);

      final initial = await repo.getMemberById('flip-1');
      expect(initial!.isAlwaysFronting, isFalse);

      await repo.updateMember(initial.copyWith(isAlwaysFronting: true));

      final updated = await repo.getMemberById('flip-1');
      expect(updated!.isAlwaysFronting, isTrue);
    });
  });

  group('avatar image round-trip', () {
    test(
      'stores picker-style avatar bytes as decodable normalized image',
      () async {
        final source = img.Image(width: 900, height: 600);
        img.fill(source, color: img.ColorRgb8(20, 30, 40));
        img.fillRect(
          source,
          x1: 200,
          y1: 100,
          x2: 699,
          y2: 499,
          color: img.ColorRgb8(220, 180, 40),
        );
        final avatarBytes = encodeAvatarOutputForStorage(
          Uint8List.fromList(img.encodePng(source)),
        );
        final member = domain.Member(
          id: 'avatar-1',
          name: 'Avatar',
          createdAt: DateTime.now().toUtc(),
          avatarImageData: avatarBytes,
        );

        await repo.createMember(member);

        final fetched = await repo.getMemberById('avatar-1');
        expect(fetched, isNotNull);
        expect(fetched!.avatarImageData, isNotNull);

        final decoded = img.decodeJpg(fetched.avatarImageData!);
        expect(decoded, isNotNull);
        expect(decoded!.width, AvatarNormalizer.maxDimension);
        expect(decoded.height, AvatarNormalizer.maxDimension);
        expect(
          fetched.avatarImageData!.length,
          lessThanOrEqualTo(AvatarNormalizer.targetMaxBytes),
        );
      },
    );

    test(
      'keeps stored avatar bytes decodable after unrelated update',
      () async {
        final source = img.Image(width: 900, height: 600);
        img.fill(source, color: img.ColorRgb8(80, 60, 40));
        final avatarBytes = encodeAvatarOutputForStorage(
          Uint8List.fromList(img.encodePng(source)),
        );
        final member = domain.Member(
          id: 'avatar-2',
          name: 'Avatar 2',
          createdAt: DateTime.now().toUtc(),
          avatarImageData: avatarBytes,
        );

        await repo.createMember(member);
        final initial = await repo.getMemberById('avatar-2');
        expect(initial, isNotNull);

        await repo.updateMember(initial!.copyWith(pronouns: 'they/them'));

        final updated = await repo.getMemberById('avatar-2');
        expect(updated, isNotNull);
        expect(updated!.avatarImageData, isNotNull);

        final decoded = img.decodeJpg(updated.avatarImageData!);
        expect(decoded, isNotNull);
        expect(
          decoded!.width,
          lessThanOrEqualTo(AvatarNormalizer.maxDimension),
        );
        expect(
          decoded.height,
          lessThanOrEqualTo(AvatarNormalizer.maxDimension),
        );
      },
    );
  });

  // ── Patch-style emission ───────────────────────────────────────────────
  //
  // Item #13 of docs/plans/2026-05-25-drift-repo-patch-update-migration.md:
  // updateMember + batchUpdateAvatars must emit per-field patches (not the
  // full member field map). updateMemberFields is the keyed entry point
  // added so the board-posts repo can route cross-table writes through
  // the diff path. All three flows share the same invariants — only
  // changed columns appear in the captured op, tombstoned rows are a
  // no-op, and `is_deleted` never leaks through the diff helper.

  group('updateMember (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    domain.Member makeMember({
      String id = 'm1',
      String name = 'Original',
      String? pronouns,
      String? bio,
      bool isActive = true,
      DateTime? createdAt,
    }) {
      return domain.Member(
        id: id,
        name: name,
        pronouns: pronouns,
        bio: bio,
        isActive: isActive,
        createdAt: createdAt ?? baseTime,
      );
    }

    test('emits only the changed fields', () async {
      await repo.createMember(makeMember());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateMember(makeMember(name: 'Renamed'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'members');
      expect(captured.single.entityId, 'm1');
      expect(captured.single.fields, {'name': 'Renamed'});
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test(
      'emits nothing when the domain object matches the stored row',
      () async {
        await repo.createMember(makeMember());
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateMember(makeMember());

        expect(captured, isEmpty);
      },
    );

    test('preserves untouched columns in the database', () async {
      await repo.createMember(makeMember(pronouns: 'they/them', bio: 'A bio'));

      await repo.updateMember(
        makeMember(name: 'Renamed', pronouns: 'they/them', bio: 'A bio'),
      );

      final row = await dao.getMemberByIdRow('m1');
      expect(row, isNotNull);
      expect(row!.name, 'Renamed');
      expect(row.pronouns, 'they/them');
      expect(row.bio, 'A bio');
      expect(row.isActive, isTrue);
    });

    test(
      'null-clearing emits the null and writes it to the database',
      () async {
        await repo.createMember(makeMember(bio: 'A bio'));
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateMember(makeMember(bio: null));

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.containsKey('bio'), isTrue);
        expect(patch['bio'], isNull);

        final row = await dao.getMemberByIdRow('m1');
        expect(row!.bio, isNull);
      },
    );

    test('silently no-ops on a tombstoned row '
        '(does not emit, does not resurrect)', () async {
      await repo.createMember(makeMember());
      await repo.deleteMember('m1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateMember(makeMember(name: 'Attempted edit'));

      expect(captured, isEmpty);
      final row = await dao.getMemberByIdRow('m1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.name, 'Original');
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateMember(makeMember(id: 'missing'));

      expect(captured, isEmpty);
      final row = await dao.getMemberByIdRow('missing');
      expect(row, isNull);
    });
  });

  group('batchUpdateAvatars (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    Uint8List makeAvatar([int seed = 0]) {
      final src = img.Image(width: 64, height: 64);
      img.fill(src, color: img.ColorRgb8(10 + seed, 20 + seed, 30 + seed));
      return encodeAvatarOutputForStorage(
        Uint8List.fromList(img.encodePng(src)),
      );
    }

    test('per-member patch carries only avatar_image_data', () async {
      // Two active members, neither has an avatar yet.
      await repo.createMember(
        domain.Member(id: 'a', name: 'A', createdAt: baseTime),
      );
      await repo.createMember(
        domain.Member(id: 'b', name: 'B', createdAt: baseTime),
      );

      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.batchUpdateAvatars([
        domain.Member(
          id: 'a',
          name: 'A',
          createdAt: baseTime,
          avatarImageData: makeAvatar(0),
        ),
        domain.Member(
          id: 'b',
          name: 'B',
          createdAt: baseTime,
          avatarImageData: makeAvatar(50),
        ),
      ]);

      expect(captured, hasLength(2));
      for (final op in captured) {
        expect(op.opType, SyncRecordOpType.update);
        expect(op.table, 'members');
        expect(op.fields.keys.toSet(), {'avatar_image_data'});
        // Patch carries the wire (base64) encoding, not the raw bytes.
        expect(op.fields['avatar_image_data'], isA<String>());
        expect(op.fields.containsKey('is_deleted'), isFalse);
      }
    });

    test('skips deleted rows in the batch', () async {
      await repo.createMember(
        domain.Member(id: 'live', name: 'Live', createdAt: baseTime),
      );
      await repo.createMember(
        domain.Member(id: 'gone', name: 'Gone', createdAt: baseTime),
      );
      await repo.deleteMember('gone');

      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.batchUpdateAvatars([
        domain.Member(
          id: 'live',
          name: 'Live',
          createdAt: baseTime,
          avatarImageData: makeAvatar(0),
        ),
        domain.Member(
          id: 'gone',
          name: 'Gone',
          createdAt: baseTime,
          avatarImageData: makeAvatar(50),
        ),
      ]);

      // Only the live member should produce an emission. The tombstoned
      // member's avatar bytes must not be batch-written either (otherwise
      // we'd flip stored bytes on a row whose tombstone says "no avatar").
      expect(captured, hasLength(1));
      expect(captured.single.entityId, 'live');

      final goneRow = await dao.getMemberByIdRow('gone');
      expect(goneRow, isNotNull);
      expect(goneRow!.isDeleted, isTrue);
      expect(goneRow.avatarImageData, isNull);
    });

    test(
      'does not emit stale non-avatar fields from the supplied Member',
      () async {
        // Set the stored row to a known state with several non-avatar
        // columns at non-default values — exactly the kind of state a peer
        // could have produced while this device was holding a stale copy.
        await repo.createMember(
          domain.Member(
            id: 'stale',
            name: 'Server Name',
            pronouns: 'they/them',
            bio: 'updated bio from peer',
            displayOrder: 7,
            createdAt: baseTime,
          ),
        );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        // Caller passes a Member object whose non-avatar fields are STALE
        // (different from what's in the DB). The DAO writes only the avatar
        // bytes — sync emission must do the same. Routing through a full-
        // row diff would surface the stale pronouns/bio/displayOrder as
        // phantom edits and clobber peers.
        await repo.batchUpdateAvatars([
          domain.Member(
            id: 'stale',
            name: 'Old Stale Name',
            pronouns: 'she/her',
            bio: 'stale local bio',
            displayOrder: 2,
            createdAt: baseTime,
            avatarImageData: makeAvatar(99),
          ),
        ]);

        expect(captured, hasLength(1));
        expect(captured.single.fields.keys.toSet(), {'avatar_image_data'});

        // Local DB stays at the server values for the non-avatar columns —
        // the DAO never touched them.
        final row = await dao.getMemberByIdRow('stale');
        expect(row!.name, 'Server Name');
        expect(row.pronouns, 'they/them');
        expect(row.bio, 'updated bio from peer');
        expect(row.displayOrder, 7);
      },
    );
  });

  group('updateMemberFields (keyed patch entry point)', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    test('writes only the specified fields, leaves others intact', () async {
      await repo.createMember(
        domain.Member(
          id: 'k1',
          name: 'Original',
          pronouns: 'they/them',
          createdAt: baseTime,
        ),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final affected = await repo.updateMemberFields('k1', {
        'bio': 'Just added',
      });

      expect(affected, 1);
      final row = await dao.getMemberByIdRow('k1');
      expect(row, isNotNull);
      expect(row!.bio, 'Just added');
      expect(row.name, 'Original');
      expect(row.pronouns, 'they/them');

      // Patch shape is the single supplied field.
      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'members');
      expect(captured.single.entityId, 'k1');
      expect(captured.single.fields, {'bio': 'Just added'});
    });

    test('returns 0 when row is tombstoned', () async {
      await repo.createMember(
        domain.Member(id: 'k2', name: 'Doomed', createdAt: baseTime),
      );
      await repo.deleteMember('k2');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final affected = await repo.updateMemberFields('k2', {
        'name': 'resurface?',
      });

      expect(affected, 0);
      // No emission for a tombstoned row.
      final updateOps = captured.where(
        (op) => op.opType == SyncRecordOpType.update,
      );
      expect(updateOps, isEmpty);
      // And the name must not have flipped.
      final row = await dao.getMemberByIdRow('k2');
      expect(row!.name, 'Doomed');
      expect(row.isDeleted, isTrue);
    });

    test('returns 0 when row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final affected = await repo.updateMemberFields('missing', {
        'name': 'whoever',
      });

      expect(affected, 0);
      expect(captured, isEmpty);
    });

    test('returns 1 with empty patch (no-op success for active row)', () async {
      await repo.createMember(
        domain.Member(id: 'k3', name: 'Same', createdAt: baseTime),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Both an empty map and an unknown-key-only map should be active-row
      // no-ops returning 1 (matches habit's contract).
      expect(await repo.updateMemberFields('k3', {}), 1);
      expect(
        await repo.updateMemberFields('k3', {'totally_unknown_key': 42}),
        1,
      );

      expect(captured, isEmpty);
      final row = await dao.getMemberByIdRow('k3');
      expect(row!.name, 'Same');
    });

    test(
      'filters unknown keys (only _memberPatchKeys reach the diff/companion)',
      () async {
        await repo.createMember(
          domain.Member(
            id: 'k4',
            name: 'Same',
            pronouns: 'she/her',
            createdAt: baseTime,
          ),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        // Mix of known + unknown + is_deleted (stripped by the diff helper).
        // Only `pronouns` actually differs from the stored row.
        final affected = await repo.updateMemberFields('k4', {
          'pronouns': 'they/them',
          'unknown_typo': 'nope',
          'is_deleted': true,
        });

        expect(affected, 1);
        expect(captured, hasLength(1));
        expect(captured.single.fields, {'pronouns': 'they/them'});
        // The stored row must be unchanged on the un-allowed keys; the
        // tombstone field must not have flipped.
        final row = await dao.getMemberByIdRow('k4');
        expect(row!.pronouns, 'they/them');
        expect(row.isDeleted, isFalse);
      },
    );

    test(
      'routes board_last_read_at through the partial companion + sync emit',
      () async {
        await repo.createMember(
          domain.Member(id: 'k5', name: 'Reader', createdAt: baseTime),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        final readAt = baseTime.add(const Duration(hours: 3));
        final affected = await repo.updateMemberFields('k5', {
          'board_last_read_at': readAt,
        });

        expect(affected, 1);
        // DB column populated.
        final row = await dao.getMemberByIdRow('k5');
        expect(row!.boardLastReadAt, isNotNull);
        expect(row.boardLastReadAt!.isAtSameMomentAs(readAt), isTrue);

        // Wire payload carries ISO-8601 UTC, not a Dart DateTime.
        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.keys.toSet(), {'board_last_read_at'});
        expect(patch['board_last_read_at'], isA<String>());
        final emitted = DateTime.parse(patch['board_last_read_at'] as String);
        expect(emitted.isAtSameMomentAs(readAt), isTrue);
      },
    );

    test('CRITICAL: concurrent disjoint update does not clobber', () async {
      // Setup: name='Original', bio='Original bio'.
      await repo.createMember(
        domain.Member(
          id: 'k6',
          name: 'Original',
          bio: 'Original bio',
          createdAt: baseTime,
        ),
      );
      // Simulate a sync-in update: directly DAO-write a new bio bypassing
      // the repo. This is what drift_sync_adapter does for inbound CRDT ops.
      await dao.updateMemberById(
        'k6',
        const MembersCompanion(bio: Value('synced-in')),
      );

      // User's local edit: only the name changed.
      final affected = await repo.updateMemberFields('k6', {'name': 'Renamed'});
      expect(affected, 1);

      // bio='synced-in' must be preserved (NOT clobbered back to 'Original
      // bio'); name='Renamed' must apply. This is the bug the migration
      // exists to fix.
      final row = await dao.getMemberByIdRow('k6');
      expect(row!.bio, 'synced-in');
      expect(row.name, 'Renamed');
    });

    test(
      'accepts a base64 avatar_image_data string for the partial companion',
      () async {
        // Internal Dart callers may also pass a Uint8List directly, but the
        // canonical patch-map encoding is base64 — pin that the partial
        // companion decodes it back into bytes on the way to Drift.
        await repo.createMember(
          domain.Member(id: 'k7', name: 'Avatared', createdAt: baseTime),
        );
        final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
        final encoded = base64Encode(bytes);

        final affected = await repo.updateMemberFields('k7', {
          'avatar_image_data': encoded,
        });
        expect(affected, 1);
        final row = await dao.getMemberByIdRow('k7');
        expect(row!.avatarImageData, bytes);
      },
    );
  });

  // ── PR 2: sync_ignored guards + invariant + new repo methods ────────────
  //
  // Tests for the four new methods in MemberRepository (applyPluralKitLink,
  // recordPluralKitIdentity, excludePluralKitSync, resumePluralKitSync) plus
  // the two-rule write invariant in `_updateMemberFieldsWithIntent`:
  //
  //   Rule A (`_stripPkLinkFields`): on excluded rows, generic updateMember
  //     cannot re-write PK identity / banner / pluralKit header source.
  //     Null writes (the PkStaleLinkException clear path) pass through.
  //   Rule B (`_stripResumeSyncIgnored`): on excluded rows, generic
  //     updateMember cannot transition `sync_ignored: true → false`.
  //
  // Plan reference: docs/plans/2026-05-26-pluralkit-link-management.md
  // Parts 1.5, 1.6, 1.7.

  group('PR 2 invariant: excluded-row write rules', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    Future<void> seedExcludedLinked({
      String id = 'excl-1',
      String? pkUuid = 'pk-uuid-orig',
      String? pkId = 'aaaaa',
      String? pkDisplayName = 'PK Name',
    }) async {
      // Create as non-excluded, link, then exclude — mirrors the real flow
      // (the link arrives first, the user excludes later).
      await repo.createMember(
        domain.Member(id: id, name: 'Linked', createdAt: baseTime),
      );
      await repo.applyPluralKitLink(id, {
        'pluralkit_uuid': ?pkUuid,
        'pluralkit_id': ?pkId,
        'pluralkit_display_name': ?pkDisplayName,
      });
      await repo.excludePluralKitSync(id);
    }

    test('Rule A: updateMemberFields on excluded with PK uuid patch strips '
        'PK fields', () async {
      await seedExcludedLinked();
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final affected = await repo.updateMemberFields('excl-1', {
        'pluralkit_uuid': 'pk-uuid-NEW',
      });

      // The patch becomes empty after stripping, but the row is active so
      // the method returns 1 (no-op success).
      expect(affected, 1);
      final row = await dao.getMemberByIdRow('excl-1');
      expect(
        row!.pluralkitUuid,
        'pk-uuid-orig',
        reason: 'PK uuid must not be re-stamped on an excluded row',
      );
      // No emission — stripped patch is empty.
      expect(
        captured.where((op) => op.opType == SyncRecordOpType.update),
        isEmpty,
      );
    });

    test('Rule B: updateMemberFields on excluded with sync_ignored=false '
        'patch (no PK fields) strips sync_ignored', () async {
      await seedExcludedLinked();
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final affected = await repo.updateMemberFields('excl-1', {
        'pluralkit_sync_ignored': false,
      });

      expect(affected, 1);
      final row = await dao.getMemberByIdRow('excl-1');
      expect(
        row!.pluralkitSyncIgnored,
        isTrue,
        reason: 'Rule B blocks resume via generic updateMember',
      );
      expect(
        captured.where((op) => op.opType == SyncRecordOpType.update),
        isEmpty,
      );
    });

    test('Rules A + B: updateMemberFields on excluded with sync_ignored=false '
        'AND PK fields strips both', () async {
      await seedExcludedLinked();
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final affected = await repo.updateMemberFields('excl-1', {
        'pluralkit_uuid': 'pk-uuid-NEW',
        'pluralkit_id': 'newId',
        'pluralkit_sync_ignored': false,
      });

      expect(affected, 1);
      final row = await dao.getMemberByIdRow('excl-1');
      expect(row!.pluralkitUuid, 'pk-uuid-orig');
      expect(row.pluralkitId, 'aaaaa');
      expect(row.pluralkitSyncIgnored, isTrue);
      expect(
        captured.where((op) => op.opType == SyncRecordOpType.update),
        isEmpty,
      );
    });

    test('Stale-full-domain race: updateMember(stale.copyWith) where stale '
        'has sync_ignored=false, DB has sync_ignored=true, patch sets PK '
        'fields + flips sync_ignored=false → both stripped; non-PK fields '
        'pass through', () async {
      // Setup: row is excluded with PK uuid 'pk-uuid-orig'.
      await seedExcludedLinked();

      // Stale Member object held by an in-flight sync loop: this snapshot
      // pre-dates the user's exclude, so it has sync_ignored=false.
      final stale = domain.Member(
        id: 'excl-1',
        name: 'Linked',
        createdAt: baseTime,
        pluralkitUuid: 'pk-uuid-orig',
        pluralkitId: 'aaaaa',
        pluralkitDisplayName: 'PK Name',
        pluralkitSyncIgnored: false,
      );

      // Sync loop calls updateMember with a stale.copyWith that attempts
      // to re-stamp PK uuid AND set a bio (non-PK field).
      await repo.updateMember(
        stale.copyWith(
          pluralkitUuid: 'pk-uuid-NEW',
          pluralkitId: 'newId',
          bio: 'pulled from PK',
        ),
      );

      final row = await dao.getMemberByIdRow('excl-1');
      // PK identity stripped by Rule A.
      expect(row!.pluralkitUuid, 'pk-uuid-orig');
      expect(row.pluralkitId, 'aaaaa');
      // sync_ignored stays true — Rule B blocked the implicit
      // false-from-stale-diff.
      expect(row.pluralkitSyncIgnored, isTrue);
      // Non-PK fields pass through. Documented limitation per the plan's
      // "one final stale non-PK metadata write" caveat.
      expect(row.bio, 'pulled from PK');
    });

    test(
      'Null-clearing PK fields on excluded member is stripped by Rule A',
      () async {
        // Rule A strips PK keys regardless of value on excluded rows.
        // A stale full-domain updateMember(stale.copyWith(...)) where
        // `stale` predates the link would otherwise diff into a patch
        // with null PK fields and wipe the link the exclude preserves.
        // The PkStaleLinkException null-clear at
        // pk_bidirectional_service.dart:115 is guarded upstream by the
        // per-local sync_ignored skip so this stripping doesn't
        // double-bounce that path.
        await seedExcludedLinked();
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        final affected = await repo.updateMemberFields('excl-1', {
          'pluralkit_uuid': null,
          'pluralkit_id': null,
        });

        // Patch becomes empty after stripping → helper returns 1 (no-op
        // success) and no emission fires.
        expect(affected, 1);
        final row = await dao.getMemberByIdRow('excl-1');
        // PK identity preserved.
        expect(row!.pluralkitUuid, 'pk-uuid-orig');
        expect(row.pluralkitId, 'aaaaa');
        expect(row.pluralkitSyncIgnored, isTrue);
        expect(captured, isEmpty);
      },
    );
  });

  group('PR 2: applyPluralKitLink', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    test(
      'on excluded member writes PK fields AND clears sync_ignored',
      () async {
        // Seed an excluded member with no PK link.
        await repo.createMember(
          domain.Member(id: 'm1', name: 'Excluded', createdAt: baseTime),
        );
        await repo.excludePluralKitSync('m1');
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        final affected = await repo.applyPluralKitLink('m1', {
          'pluralkit_uuid': 'uuid-A',
          'pluralkit_id': 'idA1',
          'pluralkit_display_name': 'PK Display',
        });

        expect(affected, 1);
        final row = await dao.getMemberByIdRow('m1');
        expect(row!.pluralkitUuid, 'uuid-A');
        expect(row.pluralkitId, 'idA1');
        expect(row.pluralkitDisplayName, 'PK Display');
        expect(
          row.pluralkitSyncIgnored,
          isFalse,
          reason: 'applyPluralKitLink force-injects sync_ignored=false',
        );

        // Emission carries the link fields plus the sync_ignored flip.
        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch['pluralkit_uuid'], 'uuid-A');
        expect(patch['pluralkit_id'], 'idA1');
        expect(patch['pluralkit_sync_ignored'], false);
      },
    );

    test('validates patch: rejects missing uuid AND id', () async {
      await repo.createMember(
        domain.Member(id: 'm1', name: 'No Link', createdAt: baseTime),
      );
      expect(
        () => repo.applyPluralKitLink('m1', {
          'pluralkit_display_name': 'just a name',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'validates patch: rejects sync_ignored=true but allows sync_ignored=false',
      () async {
        await repo.createMember(
          domain.Member(id: 'm1', name: 'Sub', createdAt: baseTime),
        );

        // Rejects true — would contradict the method's "link AND resume
        // sync" semantic.
        expect(
          () => repo.applyPluralKitLink('m1', {
            'pluralkit_uuid': 'u',
            'pluralkit_sync_ignored': true,
          }),
          throwsA(isA<ArgumentError>()),
        );

        // Allows false — idempotent with the force-injection. This is the
        // shape that the natural full-domain migration produces (per v8).
        final affected = await repo.applyPluralKitLink('m1', {
          'pluralkit_uuid': 'u',
          'pluralkit_sync_ignored': false,
        });
        expect(affected, 1);
        final row = await dao.getMemberByIdRow('m1');
        expect(row!.pluralkitSyncIgnored, isFalse);
      },
    );

    test(
      'validates patch: rejects unknown keys per _memberPatchKeys',
      () async {
        await repo.createMember(
          domain.Member(id: 'm1', name: 'Sub', createdAt: baseTime),
        );
        expect(
          () => repo.applyPluralKitLink('m1', {
            'pluralkit_uuid': 'u',
            'totally_invalid_key': 42,
          }),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });

  group('PR 2: recordPluralKitIdentity', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    test(
      'on excluded member writes PK fields, leaves sync_ignored=true',
      () async {
        // Excluded member with no link yet — simulates the _linkBackLocally
        // race: user excludes between push send and writeback.
        await repo.createMember(
          domain.Member(id: 'm1', name: 'Pushed', createdAt: baseTime),
        );
        await repo.excludePluralKitSync('m1');

        final affected = await repo.recordPluralKitIdentity('m1', {
          'pluralkit_uuid': 'returned-uuid',
          'pluralkit_id': 'rId01',
        });

        expect(affected, 1);
        final row = await dao.getMemberByIdRow('m1');
        // PK identity recorded (Rule A bypassed).
        expect(row!.pluralkitUuid, 'returned-uuid');
        expect(row.pluralkitId, 'rId01');
        // Sync exclude stays — Rule B is NOT bypassed by
        // recordPluralKitIdentity.
        expect(row.pluralkitSyncIgnored, isTrue);
      },
    );

    test('validates patch: rejects missing uuid AND id', () async {
      await repo.createMember(
        domain.Member(id: 'm1', name: 'Sub', createdAt: baseTime),
      );
      expect(
        () => repo.recordPluralKitIdentity('m1', {
          'pluralkit_display_name': 'oops',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validates patch: rejects sync_ignored regardless of value '
        '(both true AND false)', () async {
      await repo.createMember(
        domain.Member(id: 'm1', name: 'Sub', createdAt: baseTime),
      );

      // Rejects false — unlike applyPluralKitLink, recordPluralKitIdentity
      // refuses ANY sync_ignored payload because its semantic is
      // "do not touch sync state."
      expect(
        () => repo.recordPluralKitIdentity('m1', {
          'pluralkit_uuid': 'u',
          'pluralkit_sync_ignored': false,
        }),
        throwsA(isA<ArgumentError>()),
      );

      // Rejects true too.
      expect(
        () => repo.recordPluralKitIdentity('m1', {
          'pluralkit_uuid': 'u',
          'pluralkit_sync_ignored': true,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validates patch: rejects unknown keys', () async {
      await repo.createMember(
        domain.Member(id: 'm1', name: 'Sub', createdAt: baseTime),
      );
      expect(
        () => repo.recordPluralKitIdentity('m1', {
          'pluralkit_uuid': 'u',
          'totally_invalid_key': 42,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PR 2: excludePluralKitSync / resumePluralKitSync', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    test('excludePluralKitSync on synced member sets sync_ignored=true, '
        'leaves PK fields', () async {
      await repo.createMember(
        domain.Member(
          id: 'm1',
          name: 'Linked',
          pluralkitUuid: 'orig-uuid',
          pluralkitId: 'origId',
          pluralkitDisplayName: 'Name',
          createdAt: baseTime,
        ),
      );

      final affected = await repo.excludePluralKitSync('m1');
      expect(affected, 1);

      final row = await dao.getMemberByIdRow('m1');
      expect(row!.pluralkitSyncIgnored, isTrue);
      // PK fields preserved — historical metadata stays.
      expect(row.pluralkitUuid, 'orig-uuid');
      expect(row.pluralkitId, 'origId');
      expect(row.pluralkitDisplayName, 'Name');
    });

    test('resumePluralKitSync on excluded member sets sync_ignored=false, '
        'leaves PK fields', () async {
      await repo.createMember(
        domain.Member(
          id: 'm1',
          name: 'WasExcluded',
          pluralkitUuid: 'kept-uuid',
          pluralkitId: 'keptId',
          createdAt: baseTime,
          pluralkitSyncIgnored: true,
        ),
      );

      final affected = await repo.resumePluralKitSync('m1');
      expect(affected, 1);

      final row = await dao.getMemberByIdRow('m1');
      expect(row!.pluralkitSyncIgnored, isFalse);
      expect(row.pluralkitUuid, 'kept-uuid');
      expect(row.pluralkitId, 'keptId');
    });
  });

  group('PR 2: pass-through paths on excluded rows', () {
    final baseTime = DateTime.utc(2026, 5, 11, 12);

    Future<void> seedExcludedLinked(String id) async {
      await repo.createMember(
        domain.Member(id: id, name: 'Linked', createdAt: baseTime),
      );
      await repo.applyPluralKitLink(id, {
        'pluralkit_uuid': 'pk-uuid-orig',
        'pluralkit_id': 'aaaaa',
        'pluralkit_display_name': 'Original Name',
      });
      await repo.excludePluralKitSync(id);
    }

    test(
      'updateMember writing non-PK fields on excluded member passes through',
      () async {
        await seedExcludedLinked('m1');
        final current = await repo.getMemberById('m1');

        await repo.updateMember(
          current!.copyWith(name: 'Renamed', bio: 'A new bio'),
        );

        final row = await dao.getMemberByIdRow('m1');
        expect(row!.name, 'Renamed');
        expect(row.bio, 'A new bio');
        // Excluded state preserved.
        expect(row.pluralkitSyncIgnored, isTrue);
      },
    );

    test('updateMember writing pluralkit_display_name on excluded member '
        'passes through (not in strip list)', () async {
      await seedExcludedLinked('m1');
      final current = await repo.getMemberById('m1');

      await repo.updateMember(
        current!.copyWith(pluralkitDisplayName: 'User Edit'),
      );

      final row = await dao.getMemberByIdRow('m1');
      expect(
        row!.pluralkitDisplayName,
        'User Edit',
        reason: 'pluralkit_display_name is user-editable on excluded rows',
      );
      // Exclude marker preserved.
      expect(row.pluralkitSyncIgnored, isTrue);
    });

    test('profile_header_source=prism patch on excluded passes through; '
        '=pluralKit is stripped', () async {
      // Setup: excluded member with header source pluralKit.
      await repo.createMember(
        domain.Member(
          id: 'm1',
          name: 'X',
          createdAt: baseTime,
          profileHeaderSource: domain.MemberProfileHeaderSource.pluralKit,
        ),
      );
      await repo.applyPluralKitLink('m1', {'pluralkit_uuid': 'u'});
      await repo.excludePluralKitSync('m1');

      // Patch sets source to prism — user-driven, allowed.
      final affected1 = await repo.updateMemberFields('m1', {
        'profile_header_source': domain.MemberProfileHeaderSource.prism.index,
      });
      expect(affected1, 1);
      final row1 = await dao.getMemberByIdRow('m1');
      expect(
        row1!.profileHeaderSource,
        domain.MemberProfileHeaderSource.prism.index,
        reason: 'prism source is user-driven; passes through',
      );

      // Reset to pluralKit via the DAO directly (so we exercise the strip
      // path on a fresh attempt).
      await dao.updateMemberById(
        'm1',
        MembersCompanion(
          profileHeaderSource: Value(
            domain.MemberProfileHeaderSource.pluralKit.index,
          ),
        ),
      );

      // Patch sets source back to pluralKit — Rule A strips.
      final affected2 = await repo.updateMemberFields('m1', {
        'profile_header_source':
            domain.MemberProfileHeaderSource.pluralKit.index,
      });
      // Empty patch after strip, but active row → returns 1.
      expect(affected2, 1);
      // The DB write actually flipped via the DAO above, but we want to
      // verify that calling updateMemberFields with pluralKit on an
      // already-pluralKit row produces no emission (it's a no-op diff
      // anyway). The deeper invariant: even if the previous state had
      // been prism and the patch tried to flip to pluralKit, Rule A would
      // strip the patch entry. We test that scenario explicitly:
      await dao.updateMemberById(
        'm1',
        MembersCompanion(
          profileHeaderSource: Value(
            domain.MemberProfileHeaderSource.prism.index,
          ),
        ),
      );
      // Now stored = prism; patch flipping to pluralKit on excluded row
      // must be stripped.
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final affected3 = await repo.updateMemberFields('m1', {
        'profile_header_source':
            domain.MemberProfileHeaderSource.pluralKit.index,
      });
      expect(affected3, 1);
      final row3 = await dao.getMemberByIdRow('m1');
      expect(
        row3!.profileHeaderSource,
        domain.MemberProfileHeaderSource.prism.index,
        reason: 'pluralKit source flip on excluded row is stripped',
      );
      expect(
        captured.where((op) => op.opType == SyncRecordOpType.update),
        isEmpty,
      );
    });
  });
}
