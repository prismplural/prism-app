// test/data/repositories/drift_conversation_repository_test.dart
//
// DateTime UTC normalization (audit batch O follow-up — pass 8 #2).
//
// `setLastReadTimestamps` was already routed through `.toUtc()` in batch O,
// but `_conversationFields` (used by create/update/full-field writes) still
// emitted local DateTimes via direct `.toIso8601String()`. That reproduced
// the same TZ-drift bug for `created_at`, `last_activity_at`, and the
// `last_read_timestamps` map at create/update time. This test pins the
// contract that every DateTime emitted by the repository to the sync engine
// is Z-suffixed UTC. Mirrors the pattern from drift_sync_adapter_test.
//
// Patch-style emission for `updateConversation` and `updateLastActivity`
// (item #10 of the drift-repo migration plan,
// docs/plans/2026-05-25-drift-repo-patch-update-migration.md). Asserts that:
//
// - `updateConversation` emits only the columns whose values actually
//   changed, no-ops on identical input, refuses tombstoned/missing rows,
//   never emits `is_deleted` through the diff path, and inline-emits
//   `includes_all_members` only when the boolean transitions (matching the
//   sparse-emit contract that keeps pre-v25 peers from quarantining
//   conversation writes).
// - `updateLastActivity` reads the row BEFORE the DAO write so the diff
//   sees the pre-bump state — closes the read-after-write trap from the
//   prior implementation that refetched after writing and re-emitted every
//   column.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/conversation.dart' as domain;

void main() {
  late AppDatabase db;
  late ConversationsDao dao;
  late DriftConversationRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = ConversationsDao(db);
    // Null sync handle — debugConversationFields is pure on the domain
    // object and doesn't call into the FFI.
    repo = DriftConversationRepository(dao, null);
  });

  tearDown(() => db.close());

  group('debugConversationFields UTC normalization', () {
    test('created_at, last_activity_at, and last_read_timestamps emit '
        'Z-suffixed UTC even when input is a local DateTime', () {
      final localCreated = DateTime(2026, 4, 27, 10, 0);
      final localActivity = DateTime(2026, 4, 27, 11, 30);
      final localLastRead = DateTime(2026, 4, 27, 12, 15);

      final conversation = domain.Conversation(
        id: 'conv-1',
        createdAt: localCreated,
        lastActivityAt: localActivity,
        lastReadTimestamps: {'alice': localLastRead},
      );

      final fields = repo.debugConversationFields(conversation);

      final createdStr = fields['created_at'] as String;
      final activityStr = fields['last_activity_at'] as String;
      expect(
        createdStr.endsWith('Z'),
        isTrue,
        reason: 'created_at must be UTC (Z-suffixed): got $createdStr',
      );
      expect(
        activityStr.endsWith('Z'),
        isTrue,
        reason: 'last_activity_at must be UTC (Z-suffixed): got $activityStr',
      );
      expect(
        DateTime.parse(createdStr).isAtSameMomentAs(localCreated.toUtc()),
        isTrue,
      );
      expect(
        DateTime.parse(activityStr).isAtSameMomentAs(localActivity.toUtc()),
        isTrue,
      );

      final lastReadJson = fields['last_read_timestamps'] as String;
      final decoded = jsonDecode(lastReadJson) as Map<String, dynamic>;
      final aliceStr = decoded['alice'] as String;
      expect(
        aliceStr.endsWith('Z'),
        isTrue,
        reason:
            'last_read_timestamps values must be UTC (Z-suffixed): '
            'got $aliceStr',
      );
      expect(
        DateTime.parse(aliceStr).isAtSameMomentAs(localLastRead.toUtc()),
        isTrue,
      );
    });

    test('muted_by_member_ids is included in the sync field map', () {
      final conversation = domain.Conversation(
        id: 'conv-1',
        createdAt: DateTime.utc(2026, 4, 27),
        lastActivityAt: DateTime.utc(2026, 4, 27, 1),
        mutedByMemberIds: ['alice', 'bob'],
      );

      final fields = repo.debugConversationFields(conversation);

      expect(fields['muted_by_member_ids'], '["alice","bob"]');
    });

    test(
      'includes_all_members is NEVER in the helper field map '
      '(sparse-field carve-out)',
      () {
        // Patch-style migration moved `includes_all_members` out of
        // `_conversationFields` entirely. The sparse-emit contract
        // (only include when true, for pre-v25 peers) is preserved by
        // inline-emit logic in createConversation / setIncludesAllMembers
        // / updateConversation transitions — see the carve-out section of
        // docs/plans/2026-05-25-drift-repo-patch-update-migration.md.
        // `diffSyncFields` iterates `next.entries`, so a field absent from
        // `next` is never emitted even if it differs — the helper MUST
        // omit it for both `true` and `false` values, and the inline-emit
        // sites must restore the sparse contract.
        final base = domain.Conversation(
          id: 'conv-1',
          createdAt: DateTime.utc(2026, 4, 27),
          lastActivityAt: DateTime.utc(2026, 4, 27, 1),
        );

        expect(
          repo.debugConversationFields(base).containsKey(
            'includes_all_members',
          ),
          isFalse,
          reason: 'helper must omit includes_all_members when false',
        );
        expect(
          repo
              .debugConversationFields(
                base.copyWith(includesAllMembers: true),
              )
              .containsKey('includes_all_members'),
          isFalse,
          reason: 'helper must omit includes_all_members even when true; '
              'the sparse emit moved to createConversation / '
              'setIncludesAllMembers / updateConversation',
        );
      },
    );
  });

  group('includesAllMembers round-trip', () {
    Future<domain.Conversation> insert({required bool includesAllMembers}) async {
      final conversation = domain.Conversation(
        id: 'conv-1',
        createdAt: DateTime.utc(2026, 4, 27),
        lastActivityAt: DateTime.utc(2026, 4, 27, 1),
        title: 'Everyone',
        creatorId: 'creator',
        participantIds: const ['creator'],
        includesAllMembers: includesAllMembers,
      );
      await repo.createConversation(conversation);
      return conversation;
    }

    test('createConversation persists the flag and read-back preserves it',
        () async {
      await insert(includesAllMembers: true);

      final round = await repo.getConversationById('conv-1');
      expect(round, isNotNull);
      expect(round!.includesAllMembers, isTrue);
      expect(
        round.participantIds,
        ['creator'],
        reason: 'Everyone-groups still store the creator explicitly',
      );
    });

    test('setIncludesAllMembers flips the flag in storage', () async {
      await insert(includesAllMembers: false);
      expect((await repo.getConversationById('conv-1'))!.includesAllMembers,
          isFalse);

      await repo.setIncludesAllMembers('conv-1', true);
      expect((await repo.getConversationById('conv-1'))!.includesAllMembers,
          isTrue);

      await repo.setIncludesAllMembers('conv-1', false);
      expect((await repo.getConversationById('conv-1'))!.includesAllMembers,
          isFalse);
    });

    test('setIncludesAllMembers leaves other fields untouched', () async {
      await insert(includesAllMembers: false);

      await repo.setIncludesAllMembers('conv-1', true);

      final after = await repo.getConversationById('conv-1');
      expect(after!.title, 'Everyone');
      expect(after.creatorId, 'creator');
      expect(after.participantIds, ['creator']);
    });
  });

  group('updateConversation (patch-style emission)', () {
    domain.Conversation seed({
      String id = 'conv-1',
      String? title = 'Original title',
      String? emoji,
      String? description,
      String? categoryId,
      int displayOrder = 0,
      bool isDirectMessage = false,
      String? creatorId = 'creator',
      List<String> participantIds = const ['creator'],
      bool includesAllMembers = false,
      List<String> archivedByMemberIds = const [],
      List<String> mutedByMemberIds = const [],
      Map<String, DateTime> lastReadTimestamps = const {},
    }) {
      return domain.Conversation(
        id: id,
        createdAt: DateTime.utc(2026, 4, 27),
        lastActivityAt: DateTime.utc(2026, 4, 27, 1),
        title: title,
        emoji: emoji,
        isDirectMessage: isDirectMessage,
        creatorId: creatorId,
        participantIds: participantIds,
        includesAllMembers: includesAllMembers,
        archivedByMemberIds: archivedByMemberIds,
        mutedByMemberIds: mutedByMemberIds,
        lastReadTimestamps: lastReadTimestamps,
        description: description,
        categoryId: categoryId,
        displayOrder: displayOrder,
      );
    }

    test('emits only the changed fields', () async {
      await repo.createConversation(seed(title: 'Old'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateConversation(seed(title: 'New'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'conversations');
      expect(captured.single.entityId, 'conv-1');
      expect(captured.single.fields.keys.toSet(), {'title'});
      expect(captured.single.fields['title'], 'New');
    });

    test('emits nothing when the domain matches the stored row', () async {
      await repo.createConversation(seed(title: 'Same'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateConversation(seed(title: 'Same'));

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.createConversation(
        seed(
          title: 'before',
          emoji: 'smile',
          description: 'desc',
          categoryId: 'cat-1',
          displayOrder: 7,
          participantIds: const ['creator', 'alice'],
          archivedByMemberIds: const ['alice'],
          mutedByMemberIds: const ['bob'],
        ),
      );

      await repo.updateConversation(
        seed(
          title: 'after',
          emoji: 'smile',
          description: 'desc',
          categoryId: 'cat-1',
          displayOrder: 7,
          participantIds: const ['creator', 'alice'],
          archivedByMemberIds: const ['alice'],
          mutedByMemberIds: const ['bob'],
        ),
      );

      final row = await dao.getConversationById('conv-1');
      expect(row, isNotNull);
      expect(row!.title, 'after');
      expect(row.emoji, 'smile');
      expect(row.description, 'desc');
      expect(row.categoryId, 'cat-1');
      expect(row.displayOrder, 7);
      expect(jsonDecode(row.participantIds), ['creator', 'alice']);
      expect(jsonDecode(row.archivedByMemberIds), ['alice']);
      expect(jsonDecode(row.mutedByMemberIds), ['bob']);
    });

    test('null-clearing emits the null and writes it to the database',
        () async {
      await repo.createConversation(seed(title: 'had a title'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateConversation(seed(title: null));

      expect(captured, hasLength(1));
      final patch = captured.single.fields;
      expect(patch.containsKey('title'), isTrue);
      expect(patch['title'], isNull);

      final row = await dao.getConversationById('conv-1');
      expect(row!.title, isNull);
    });

    test(
      'silently no-ops on a tombstoned conversation (does not emit, '
      'does not resurrect)',
      () async {
        await repo.createConversation(seed(title: 'before delete'));
        await repo.deleteConversation('conv-1');
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateConversation(seed(title: 'attempted resurrect'));

        expect(captured, isEmpty);
        final row = await dao.getConversationById('conv-1');
        expect(row, isNotNull);
        expect(row!.isDeleted, isTrue);
        expect(row.title, 'before delete');
      },
    );

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateConversation(seed(id: 'missing', title: 'nope'));

      expect(captured, isEmpty);
      final row = await dao.getConversationById('missing');
      expect(row, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      // diffSyncFields strips `is_deleted` unconditionally. The early-return
      // on `existingRow.isDeleted` covers the resurrection edge separately.
      // Pin the strip behaviour.
      await repo.createConversation(seed(title: 'a'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateConversation(seed(title: 'b'));

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test(
      'includes_all_members false→true transition emits the field inline',
      () async {
        await repo.createConversation(
          seed(title: 'team', includesAllMembers: false),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateConversation(
          seed(title: 'team', includesAllMembers: true),
        );

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.containsKey('includes_all_members'), isTrue);
        expect(patch['includes_all_members'], isTrue);

        // DB write applied through the partial companion.
        final row = await dao.getConversationById('conv-1');
        expect(row!.includesAllMembers, isTrue);
      },
    );

    test(
      'includes_all_members true→false transition emits the field inline',
      () async {
        await repo.createConversation(
          seed(title: 'team', includesAllMembers: true),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateConversation(
          seed(title: 'team', includesAllMembers: false),
        );

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.containsKey('includes_all_members'), isTrue);
        expect(
          patch['includes_all_members'],
          isFalse,
          reason: 'transition emit mirrors setIncludesAllMembers, which '
              'emits false unconditionally',
        );

        final row = await dao.getConversationById('conv-1');
        expect(row!.includesAllMembers, isFalse);
      },
    );

    test(
      'includes_all_members unchanged emits nothing for that field',
      () async {
        await repo.createConversation(
          seed(title: 'team', includesAllMembers: true),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        // Same flag, different title — diff should narrow to title only.
        await repo.updateConversation(
          seed(title: 'team renamed', includesAllMembers: true),
        );

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.containsKey('includes_all_members'), isFalse);
        expect(patch.keys.toSet(), {'title'});
      },
    );
  });

  group('updateLastActivity (patch-style emission)', () {
    test(
      'emits only the bumped timestamp, even with rich non-default columns',
      () async {
        // Seed with a wide variety of non-default values that
        // updateLastActivity does not touch. If the implementation refetched
        // after the DAO write (the read-after-write trap), every column
        // would diff because the round-trip touches storage encoding
        // (DateTime UTC normalization, JSON list shape).
        await repo.createConversation(
          domain.Conversation(
            id: 'conv-1',
            createdAt: DateTime.utc(2026, 4, 27),
            lastActivityAt: DateTime.utc(2026, 4, 27, 1),
            title: 'has title',
            emoji: 'smile',
            isDirectMessage: true,
            creatorId: 'creator',
            participantIds: const ['creator', 'alice'],
            includesAllMembers: true,
            archivedByMemberIds: const ['alice'],
            mutedByMemberIds: const ['bob'],
            description: 'descr',
            categoryId: 'cat-1',
            displayOrder: 5,
          ),
        );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateLastActivity('conv-1');

        expect(captured, hasLength(1));
        final op = captured.single;
        expect(op.opType, SyncRecordOpType.update);
        expect(op.table, 'conversations');
        expect(op.entityId, 'conv-1');
        // The patch must be the single field updateLastActivity actually
        // changes — and explicitly NOT include anything from the rich set
        // of unchanged columns. The old code re-emitted the whole row.
        expect(op.fields.keys.toSet(), {'last_activity_at'});
        expect(op.fields.containsKey('title'), isFalse);
        expect(op.fields.containsKey('emoji'), isFalse);
        expect(op.fields.containsKey('is_direct_message'), isFalse);
        expect(op.fields.containsKey('creator_id'), isFalse);
        expect(op.fields.containsKey('participant_ids'), isFalse);
        expect(op.fields.containsKey('archived_by_member_ids'), isFalse);
        expect(op.fields.containsKey('muted_by_member_ids'), isFalse);
        expect(op.fields.containsKey('last_read_timestamps'), isFalse);
        expect(op.fields.containsKey('description'), isFalse);
        expect(op.fields.containsKey('category_id'), isFalse);
        expect(op.fields.containsKey('display_order'), isFalse);
        expect(op.fields.containsKey('is_deleted'), isFalse);
        expect(op.fields.containsKey('includes_all_members'), isFalse);

        // Sanity: the new timestamp must be a Z-suffixed UTC ISO string.
        final emittedTs = op.fields['last_activity_at'] as String;
        expect(emittedTs.endsWith('Z'), isTrue);

        // And the row is updated.
        final row = await dao.getConversationById('conv-1');
        expect(row, isNotNull);
        expect(row!.title, 'has title');
        expect(row.includesAllMembers, isTrue);
      },
    );

    test('silently no-ops on a tombstoned conversation', () async {
      await repo.createConversation(
        domain.Conversation(
          id: 'conv-1',
          createdAt: DateTime.utc(2026, 4, 27),
          lastActivityAt: DateTime.utc(2026, 4, 27, 1),
          title: 'before delete',
        ),
      );
      await repo.deleteConversation('conv-1');

      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateLastActivity('conv-1');

      expect(captured, isEmpty);
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateLastActivity('missing');

      expect(captured, isEmpty);
    });
  });
}
