// End-to-end migration harness for SP board messages → Prism MemberBoardPost.
//
// Covers three paths:
//   1. New import  — SpMapper emits MemberBoardPost rows directly (Batch F+).
//   2. Old + backfill — The pre-Batch-F importer created synthetic DM conversations
//      (is_dm=true, emoji=📝, "**title**\nbody" content). SpBoardsBackfillService
//      converts those to the same MemberBoardPost rows with identical deterministic
//      UUID v5 IDs.
//   3. Full import   — SpImporter.executeImport() wired to an in-memory DB,
//      verifying the importer result counts and the boardsEnabled auto-enable.
//
// Test data: /Users/sky/Downloads/export_7b35523d…(2).json
//   5 board messages, all members resolved, all read=false.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_boards_backfill_service.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

import '../../../helpers/fake_repositories.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Path to the real SP export file.
const _exportPath =
    '/Users/sky/Downloads/'
    'export_7b35523dcdf0f69a3aed9e965506e1c0ad9d6a9df79ddba866cbd4bdc352703a(2).json';

SpExportData _loadExport() => SpParser.parse(File(_exportPath).readAsStringSync());

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

SpBoardsBackfillService _makeBackfillService(
  AppDatabase db,
  FakeSystemSettingsRepository settingsRepo,
) {
  final dao = db.memberBoardPostsDao;
  final repo = DriftMemberBoardPostsRepository(dao, db.membersDao, null);
  return SpBoardsBackfillService(
    db: db,
    boardPostsRepo: repo,
    boardPostsDao: dao,
    settingsRepo: settingsRepo,
  );
}

/// Return all non-deleted board posts ordered by body for stable comparisons.
Future<List<Map<String, dynamic>>> _allPosts(AppDatabase db) async {
  final rows = await db.customSelect(
    'SELECT id, target_member_id, author_id, audience, title, body '
    'FROM member_board_posts WHERE is_deleted = 0 ORDER BY body',
  ).get();
  return rows
      .map((r) => {
            'id': r.read<String>('id'),
            'targetMemberId': r.read<String>('target_member_id'),
            'authorId': r.readNullable<String>('author_id'),
            'audience': r.read<String>('audience'),
            'title': r.readNullable<String>('title'),
            'body': r.read<String>('body'),
          })
      .toList();
}

/// Replicates the old pre-Batch-F message formatting: "**title**\nbody".
String _oldContent(String? title, String body) {
  if (title != null && title.isNotEmpty) return '**$title**\n$body';
  return body;
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  final exportExists = File(_exportPath).existsSync();
  final skipMsg = exportExists ? null : 'Export file not found at $_exportPath';

  // ---------------------------------------------------------------------------
  // Group 1 — New import path via SpMapper
  // ---------------------------------------------------------------------------

  group('New import path (SpMapper)', skip: skipMsg, () {
    late SpExportData data;
    late SpMapper mapper;
    late MappedData mapped;

    setUpAll(() {
      data = _loadExport();
      mapper = SpMapper();
      mapped = mapper.mapAll(data);
    });

    test('parses 5 board messages from export', () {
      expect(data.boardMessages, hasLength(5));
    });

    test('produces 5 MemberBoardPost rows', () {
      expect(mapped.boardPosts, hasLength(5));
    });

    test('all board posts have audience=private', () {
      for (final post in mapped.boardPosts) {
        expect(post.audience, equals('private'),
            reason: 'post ${post.id}');
      }
    });

    test('all board posts have non-null targetMemberId', () {
      for (final post in mapped.boardPosts) {
        expect(post.targetMemberId, isNotNull,
            reason: 'post ${post.id}');
      }
    });

    test('all board posts have non-null authorId (all writtenBy resolve)', () {
      for (final post in mapped.boardPosts) {
        expect(post.authorId, isNotNull,
            reason: 'post ${post.id}');
      }
    });

    test('no member-resolution warnings', () {
      final warn = mapped.warnings.where((w) => w.contains('not found in member map')).toList();
      expect(warn, isEmpty);
    });

    test('boardLastReadAtUpdates is empty (all messages read=false)', () {
      expect(mapped.boardLastReadAtUpdates, isEmpty);
    });

    test('titles stored as separate field, body does not contain ** prefix', () {
      for (final post in mapped.boardPosts) {
        expect(post.title, isNotNull, reason: 'every message in this export has a title');
        expect(post.body, isNot(startsWith('**')),
            reason: 'new path must not prepend the title to body');
      }
    });

    test('deterministic IDs are stable across two mapper runs with same member map', () {
      final mapper2 = SpMapper(existingMappings: {'member': mapper.memberIdMap});
      final mapped2 = mapper2.mapAll(data);
      expect(
        mapped2.boardPosts.map((p) => p.id).toSet(),
        equals(mapped.boardPosts.map((p) => p.id).toSet()),
      );
    });

    test('all post IDs are distinct', () {
      final ids = mapped.boardPosts.map((p) => p.id).toSet();
      expect(ids.length, equals(mapped.boardPosts.length));
    });

    test('no synthetic DM 📝 conversations produced', () {
      final boardDmConvs = mapped.conversations
          .where((c) => c.isDirectMessage && c.emoji == '\u{1F4DD}')
          .toList();
      expect(boardDmConvs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 2 — Old DM path + backfill, ID convergence
  // ---------------------------------------------------------------------------

  group('Old DM path + backfill convergence', skip: skipMsg, () {
    late SpExportData data;
    late SpMapper mapper;
    late MappedData mapped;
    late AppDatabase db;
    late FakeSystemSettingsRepository settingsRepo;

    setUp(() async {
      data = _loadExport();
      mapper = SpMapper();
      mapped = mapper.mapAll(data);

      db = _makeDb();
      settingsRepo = FakeSystemSettingsRepository();

      // Insert minimal member rows.
      final now = DateTime.now().toUtc();
      for (final member in mapped.members) {
        await db.membersDao.insertMember(MembersCompanion(
          id: Value(member.id),
          name: Value(member.name),
          createdAt: Value(now),
        ));
      }

      // Simulate what pre-Batch-F _mapBoardMessages created:
      //   • one DM conversation (emoji=📝, is_dm=true) per (writtenBy, writtenFor) pair
      //   • one chat_message per board message with content = "**title**\nbody"
      //   • participantIds = [byId, forId] (byId first, as old mapper did)
      //
      // The lastActivityAt is set to bm.writtenAt so it predates the backfill
      // sentinel (which is set to now() at run time).
      const uuid = Uuid();
      final pairToConvId = <String, String>{};

      for (final bm in data.boardMessages) {
        if (bm.message.isEmpty) continue;
        if (bm.writtenFor == null) continue;

        final byId = mapper.resolveMemberId(bm.writtenBy ?? '');
        final forId = mapper.resolveMemberId(bm.writtenFor!);
        if (forId == null) continue;

        // Order-independent pair key — mirrors old mapper sort.
        final sortedIds = [byId ?? '', forId]..sort();
        final pairKey = '${sortedIds[0]}_${sortedIds[1]}';

        if (!pairToConvId.containsKey(pairKey)) {
          final convId = uuid.v4();
          pairToConvId[pairKey] = convId;

          final participants = <String>[
            if (byId != null) byId,
            if (forId != byId) forId,
          ];

          await db.conversationsDao.insertConversation(
            ConversationsCompanion(
              id: Value(convId),
              createdAt: Value(bm.writtenAt.toUtc()),
              lastActivityAt: Value(bm.writtenAt.toUtc()),
              emoji: const Value('\u{1F4DD}'),
              isDirectMessage: const Value(true),
              participantIds: Value(jsonEncode(participants)),
            ),
          );
        }

        await db.chatMessagesDao.insertMessage(
          ChatMessagesCompanion(
            id: Value(uuid.v4()),
            conversationId: Value(pairToConvId[pairKey]!),
            content: Value(_oldContent(bm.title, bm.message)),
            timestamp: Value(bm.writtenAt.toUtc()),
            authorId: Value(byId),
          ),
        );
      }
    });

    tearDown(() async => db.close());

    test('backfill converts all 5 messages and reports correct count', () async {
      final result = await _makeBackfillService(db, settingsRepo).run();
      expect(result.abortedByPeer, isFalse);
      expect(result.postsConverted, equals(5));
      expect(await _allPosts(db), hasLength(5));
    });

    test('backfilled post IDs match new-path IDs exactly', () async {
      await _makeBackfillService(db, settingsRepo).run();

      final backfilledIds = (await _allPosts(db)).map((p) => p['id'] as String).toSet();
      final newPathIds = mapped.boardPosts.map((p) => p.id).toSet();

      expect(backfilledIds, equals(newPathIds),
          reason: 'Both paths must produce identical deterministic UUID v5 IDs');
    });

    test('backfilled targetMemberId and authorId match new-path values', () async {
      await _makeBackfillService(db, settingsRepo).run();

      final posts = await _allPosts(db);
      final newPathById = {for (final p in mapped.boardPosts) p.id: p};

      for (final post in posts) {
        final newPost = newPathById[post['id'] as String]!;
        expect(post['targetMemberId'], equals(newPost.targetMemberId),
            reason: 'targetMemberId mismatch for ${post["id"]}');
        expect(post['authorId'], equals(newPost.authorId),
            reason: 'authorId mismatch for ${post["id"]}');
      }
    });

    test('backfilled title and body match new-path values', () async {
      await _makeBackfillService(db, settingsRepo).run();

      final posts = await _allPosts(db);
      final newPathById = {for (final p in mapped.boardPosts) p.id: p};

      for (final post in posts) {
        final newPost = newPathById[post['id'] as String]!;
        expect(post['title'], equals(newPost.title),
            reason: 'title mismatch for ${post["id"]}');
        expect(post['body'], equals(newPost.body),
            reason: 'body mismatch for ${post["id"]}');
      }
    });

    test('backfill is idempotent — second run inserts 0 new posts', () async {
      final service = _makeBackfillService(db, settingsRepo);
      await service.run();

      // Reset sentinel so the service can run again.
      settingsRepo.updateSettings(
          settingsRepo.settings.copyWith(spBoardsBackfilledAt: null));

      final result2 = await service.run();
      expect(result2.postsConverted, equals(0));
      expect(await _allPosts(db), hasLength(5));
    });

    test('backfill enables boardsEnabled when posts are converted', () async {
      expect(settingsRepo.settings.boardsEnabled, isFalse);
      await _makeBackfillService(db, settingsRepo).run();
      expect(settingsRepo.settings.boardsEnabled, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3 — Full SpImporter.executeImport() integration test
  // ---------------------------------------------------------------------------

  group('Full SpImporter integration', skip: skipMsg, () {
    late AppDatabase db;
    late FakeSystemSettingsRepository settingsRepo;

    setUp(() {
      db = _makeDb();
      settingsRepo = FakeSystemSettingsRepository();
    });

    tearDown(() async => db.close());

    test('imports 5 board posts and auto-enables boardsEnabled', () async {
      final result = await _runFullImport(db, settingsRepo);
      expect(result.boardPostsImported, equals(5));
      expect(settingsRepo.settings.boardsEnabled, isTrue);
      expect(await _allPosts(db), hasLength(5));
    });

    test('all imported board posts have audience=private and non-null targetMemberId', () async {
      await _runFullImport(db, settingsRepo);
      final posts = await _allPosts(db);
      for (final post in posts) {
        expect(post['audience'], equals('private'));
        expect(post['targetMemberId'], isNotNull);
      }
    });

    test('re-import with clearExistingData produces same 5 posts', () async {
      // First import.
      final result1 = await _runFullImport(db, settingsRepo, persistMappings: true);
      final ids1 = (await _allPosts(db)).map((p) => p['id'] as String).toSet();
      expect(result1.boardPostsImported, equals(5));

      // Second import with clearExistingData wipes then re-inserts.
      // The deterministic UUIDs from sp_id_map mean the same IDs are produced.
      final result2 = await _runFullImport(
        db,
        settingsRepo,
        persistMappings: true,
        clearExistingData: true,
      );
      final ids2 = (await _allPosts(db)).map((p) => p['id'] as String).toSet();

      expect(result2.boardPostsImported, equals(5));
      expect(ids2, equals(ids1),
          reason: 'Re-import must produce identical deterministic IDs');
    });
  });
}

// =============================================================================
// Full-import helper
// =============================================================================

Future<ImportResult> _runFullImport(
  AppDatabase db,
  FakeSystemSettingsRepository settingsRepo, {
  bool persistMappings = false,
  bool clearExistingData = false,
}) async {
  final data = _loadExport();
  final importer = SpImporter();

  final memberRepo = DriftMemberRepository(db.membersDao, null);
  final sessionRepo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
  final convRepo = DriftConversationRepository(db.conversationsDao, null);
  final pollRepo = DriftPollRepository(
      db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null);
  final boardPostsRepo =
      DriftMemberBoardPostsRepository(db.memberBoardPostsDao, db.membersDao, null);

  return importer.executeImport(
    db: db,
    data: data,
    memberRepo: memberRepo,
    sessionRepo: sessionRepo,
    conversationRepo: convRepo,
    messageRepo: _NullChatMessageRepo(),
    pollRepo: pollRepo,
    settingsRepo: settingsRepo,
    boardPostsRepo: boardPostsRepo,
    spImportDao: persistMappings ? db.spImportDao : null,
    clearExistingData: clearExistingData,
    downloadAvatars: false,
  );
}

// =============================================================================
// Minimal ChatMessageRepository for integration tests
// =============================================================================

/// Swallows createMessage calls — the integration tests only assert board posts
/// and member counts, not channel message counts.
class _NullChatMessageRepo implements ChatMessageRepository {
  @override
  Future<void> createMessage(domain.ChatMessage message) async {}

  @override
  Future<void> updateMessage(domain.ChatMessage message) async {}

  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<List<domain.ChatMessage>> getAllMessages() async => [];

  @override
  Future<List<domain.ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async =>
      [];

  @override
  Future<domain.ChatMessage?> getLatestMessage(String conversationId) async => null;

  @override
  Future<domain.ChatMessage?> getMessageById(String id) async => null;

  @override
  Stream<List<domain.ChatMessage>> watchMessagesForConversation(
          String conversationId) =>
      const Stream.empty();

  @override
  Stream<List<domain.ChatMessage>> watchRecentMessages(
          String conversationId, {required int limit}) =>
      const Stream.empty();

  @override
  Stream<domain.ChatMessage?> watchLatestMessage(String conversationId) =>
      const Stream.empty();

  @override
  Future<
      List<({
        String messageId,
        String conversationId,
        String snippet,
        DateTime timestamp,
        String? authorId
      })>> searchMessages(String query, {int limit = 20}) async =>
      [];

  @override
  Stream<int> watchUnreadCount(String conversationId, DateTime since) =>
      const Stream.empty();

  @override
  Stream<int> watchUnreadMentionCount(
          String conversationId, DateTime since, String memberId) =>
      const Stream.empty();

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
          Map<String, DateTime> conversationSince) =>
      const Stream.empty();

  @override
  Stream<Set<String>> watchConversationsWithMentions(
          Map<String, DateTime> conversationSince, String memberId) =>
      const Stream.empty();
}
