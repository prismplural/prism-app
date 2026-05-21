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

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
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

    test('includes_all_members flag is emitted only when true', () {
      final base = domain.Conversation(
        id: 'conv-1',
        createdAt: DateTime.utc(2026, 4, 27),
        lastActivityAt: DateTime.utc(2026, 4, 27, 1),
      );

      // false: omitted so pre-v25 peers don't quarantine every conversation
      // write on an unknown field.
      final off = repo.debugConversationFields(base);
      expect(off.containsKey('includes_all_members'), isFalse);

      // true: emitted explicitly.
      final on = repo.debugConversationFields(
        base.copyWith(includesAllMembers: true),
      );
      expect(on['includes_all_members'], isTrue);
    });
  });

  group('includesAllMembers round-trip', () {
    Future<domain.Conversation> insert({
      required bool includesAllMembers,
    }) async {
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

    test(
      'createConversation persists the flag and read-back preserves it',
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
      },
    );

    test('setIncludesAllMembers flips the flag in storage', () async {
      await insert(includesAllMembers: false);
      expect(
        (await repo.getConversationById('conv-1'))!.includesAllMembers,
        isFalse,
      );

      await repo.setIncludesAllMembers('conv-1', true);
      expect(
        (await repo.getConversationById('conv-1'))!.includesAllMembers,
        isTrue,
      );

      await repo.setIncludesAllMembers('conv-1', false);
      expect(
        (await repo.getConversationById('conv-1'))!.includesAllMembers,
        isFalse,
      );
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

  group('mention reads', () {
    domain.Conversation conversation(String id, String title) =>
        domain.Conversation(
          id: id,
          title: title,
          createdAt: DateTime.utc(2026, 4, 27),
          lastActivityAt: DateTime.utc(2026, 4, 27, 1),
          participantIds: const ['alice'],
        );

    test('point fetch keeps legacy soft-delete semantics', () async {
      await repo.createConversation(conversation('conv-1', 'Deleted chat'));
      await repo.deleteConversation('conv-1');

      expect(await repo.getConversationById('conv-1'), isNotNull);
      expect(await repo.getMentionConversationById('conv-1'), isNull);
    });

    test('searchMentionCandidates treats LIKE wildcards literally', () async {
      await repo.createConversation(conversation('literal-percent', '100%'));
      await repo.createConversation(conversation('plain', 'plain'));

      final percent = await repo.searchMentionCandidates(
        '%',
        activeFronterIds: const ['alice'],
      );

      expect(percent.map((conversation) => conversation.id), [
        'literal-percent',
      ]);
    });
  });
}
