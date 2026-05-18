import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/migration/services/group_chat_visibility_sync_reemit_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _insertConversation(
  AppDatabase db, {
  required String id,
  String? creatorId,
  List<String> participantIds = const [],
  String? participantIdsJson,
  bool includesAllMembers = false,
  bool isDirectMessage = false,
  bool isDeleted = false,
}) async {
  final now = DateTime.utc(2026, 5, 18, 12);
  await db.conversationsDao.insertConversation(
    ConversationsCompanion.insert(
      id: id,
      createdAt: now,
      lastActivityAt: now,
      title: Value('Conversation $id'),
      creatorId: Value(creatorId),
      participantIds: Value(participantIdsJson ?? jsonEncode(participantIds)),
      isDirectMessage: Value(isDirectMessage),
      isDeleted: Value(isDeleted),
      includesAllMembers: Value(includesAllMembers),
    ),
  );
}

void main() {
  late AppDatabase db;
  late List<_CapturedUpdate> updates;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = _makeDb();
    updates = [];
  });

  tearDown(() async {
    await db.close();
  });

  GroupChatVisibilitySyncReemitService service() {
    return GroupChatVisibilitySyncReemitService(
      db: db,
      recordUpdate:
          ({required table, required entityId, required fields}) async {
            updates.add(_CapturedUpdate(table, entityId, fields));
          },
    );
  }

  test('re-emits only everyone-visible group chat flags once', () async {
    await _insertConversation(
      db,
      id: 'everyone-explicit',
      participantIds: const ['alice', 'bob'],
      includesAllMembers: true,
    );
    await _insertConversation(
      db,
      id: 'everyone-repaired-owner',
      creatorId: 'admin',
      participantIds: const ['admin'],
      includesAllMembers: true,
    );
    await _insertConversation(db, id: 'scoped');
    await _insertConversation(
      db,
      id: 'dm',
      includesAllMembers: true,
      isDirectMessage: true,
    );
    await _insertConversation(
      db,
      id: 'deleted',
      includesAllMembers: true,
      isDeleted: true,
    );

    expect(
      await GroupChatVisibilitySyncReemitService.hasCandidates(db),
      isTrue,
    );

    final result = await service().runOnce();

    expect(result.error, isNull);
    expect(result.conversationsReemitted, 2);
    expect(updates, [
      const _CapturedUpdate('conversations', 'everyone-explicit', {
        'includes_all_members': true,
      }),
      const _CapturedUpdate('conversations', 'everyone-repaired-owner', {
        'includes_all_members': true,
        'creator_id': 'admin',
        'participant_ids': '["admin"]',
      }),
    ]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(GroupChatVisibilitySyncReemitService.flagKey), isTrue);

    final secondResult = await service().runOnce();

    expect(secondResult.alreadyCompleted, isTrue);
    expect(updates, hasLength(2));
  });

  test('marks complete when there are no candidates', () async {
    expect(
      await GroupChatVisibilitySyncReemitService.hasCandidates(db),
      isFalse,
    );

    final result = await service().runOnce();

    expect(result.error, isNull);
    expect(result.conversationsReemitted, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(GroupChatVisibilitySyncReemitService.flagKey), isTrue);
  });

  test(
    'owner repair fields require a single participant matching creator',
    () async {
      await _insertConversation(
        db,
        id: 'malformed',
        creatorId: 'admin',
        participantIdsJson: 'not json',
        includesAllMembers: true,
      );
      await _insertConversation(
        db,
        id: 'mismatch',
        creatorId: 'admin',
        participantIds: const ['bob'],
        includesAllMembers: true,
      );

      final result = await service().runOnce();

      expect(result.error, isNull);
      expect(result.conversationsReemitted, 2);
      expect(updates, [
        const _CapturedUpdate('conversations', 'malformed', {
          'includes_all_members': true,
        }),
        const _CapturedUpdate('conversations', 'mismatch', {
          'includes_all_members': true,
        }),
      ]);
    },
  );

  test('does not mark complete when sync emission fails', () async {
    await _insertConversation(db, id: 'everyone', includesAllMembers: true);
    final failingService = GroupChatVisibilitySyncReemitService(
      db: db,
      recordUpdate:
          ({required table, required entityId, required fields}) async {
            throw StateError('sync unavailable');
          },
    );

    final result = await failingService.runOnce();

    expect(result.hasError, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(GroupChatVisibilitySyncReemitService.flagKey),
      isNot(isTrue),
    );
  });
}

class _CapturedUpdate {
  const _CapturedUpdate(this.table, this.entityId, this.fields);

  final String table;
  final String entityId;
  final Map<String, dynamic> fields;

  @override
  bool operator ==(Object other) {
    return other is _CapturedUpdate &&
        other.table == table &&
        other.entityId == entityId &&
        const DeepCollectionEquality().equals(other.fields, fields);
  }

  @override
  int get hashCode =>
      Object.hash(table, entityId, const DeepCollectionEquality().hash(fields));

  @override
  String toString() => '_CapturedUpdate($table, $entityId, $fields)';
}
