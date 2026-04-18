import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prism_plurality/core/database/app_database.dart' show AppDatabase;
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/conversation.dart' as domain;
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/domain/models/poll_vote.dart' as domain;
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

// =============================================================================
// Fake HTTP client
// =============================================================================

class _FakeHttpClient extends http.BaseClient {
  final Map<String, http.Response> _responses = {};
  final calls = <String>[];

  void stubUrl(String url, http.Response response) =>
      _responses[url] = response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request.url.toString());
    final response = _responses[request.url.toString()] ??
        http.Response('not found', 404);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

// =============================================================================
// Fake repositories
// =============================================================================

class _FakeMemberRepository implements MemberRepository {
  final List<domain.Member> _members = [];
  domain.Member? lastUpdatedMember;

  @override
  Future<void> createMember(domain.Member member) async =>
      _members.add(member);

  @override
  Future<void> updateMember(domain.Member member) async {
    lastUpdatedMember = member;
    final i = _members.indexWhere((m) => m.id == member.id);
    if (i >= 0) _members[i] = member;
  }

  @override
  Future<void> deleteMember(String id) async =>
      _members.removeWhere((m) => m.id == id);

  @override
  Future<List<domain.Member>> getAllMembers() async =>
      List.unmodifiable(_members);

  @override
  Future<domain.Member?> getMemberById(String id) async =>
      _members.cast<domain.Member?>().firstWhere(
        (m) => m?.id == id,
        orElse: () => null,
      );

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      _members.where((m) => ids.contains(m.id)).toList();

  @override
  Future<int> getCount() async => _members.length;

  @override
  Stream<List<domain.Member>> watchAllMembers() =>
      Stream.value(List.unmodifiable(_members));

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      Stream.value(_members.where((m) => m.isActive).toList());

  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      Stream.value(_members.cast<domain.Member?>().firstWhere(
        (m) => m?.id == id,
        orElse: () => null,
      ));
}

class _FakeSessionRepository implements FrontingSessionRepository {
  final List<domain.FrontingSession> sessions = [];

  @override
  Future<void> createSession(domain.FrontingSession session) async =>
      sessions.add(session);

  @override
  Future<void> updateSession(domain.FrontingSession session) async {
    final i = sessions.indexWhere((s) => s.id == session.id);
    if (i >= 0) sessions[i] = session;
  }

  @override
  Future<void> deleteSession(String id) async =>
      sessions.removeWhere((s) => s.id == id);

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    final i = sessions.indexWhere((s) => s.id == id);
    if (i >= 0) sessions[i] = sessions[i].copyWith(endTime: endTime);
  }

  @override
  Future<List<domain.FrontingSession>> getAllSessions() async =>
      List.unmodifiable(sessions);

  @override
  Future<List<domain.FrontingSession>> getFrontingSessions() async =>
      sessions.where((s) => !s.isSleep).toList();

  @override
  Future<List<domain.FrontingSession>> getActiveSessions() async =>
      sessions.where((s) => s.isActive && !s.isSleep).toList();

  @override
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered() async =>
      sessions.where((s) => s.isActive).toList();

  @override
  Future<domain.FrontingSession?> getActiveSession() async => null;

  @override
  Future<domain.FrontingSession?> getSessionById(String id) async =>
      sessions.cast<domain.FrontingSession?>().firstWhere(
        (s) => s?.id == id,
        orElse: () => null,
      );

  @override
  Future<List<domain.FrontingSession>> getRecentSessions({int limit = 20}) async =>
      sessions.take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({int limit = 10}) async =>
      sessions.where((s) => s.isSleep).take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async =>
      sessions.where((s) =>
        !s.startTime.isBefore(start) && !s.startTime.isAfter(end)).toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(String memberId) async =>
      sessions.where((s) => s.memberId == memberId).toList();

  @override
  Future<int> getCount() async => sessions.length;

  @override
  Future<int> getFrontingCount() async =>
      sessions.where((s) => !s.isSleep).length;

  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) async => {};

  @override
  Stream<domain.FrontingSession?> watchActiveSession() => Stream.value(null);

  @override
  Stream<domain.FrontingSession?> watchActiveSleepSession() => Stream.value(null);

  @override
  Stream<List<domain.FrontingSession>> watchActiveSessions() =>
      Stream.value(const []);

  @override
  Stream<List<domain.FrontingSession>> watchAllSessions() =>
      Stream.value(List.unmodifiable(sessions));

  @override
  Stream<List<domain.FrontingSession>> watchAllSleepSessions() =>
      Stream.value(sessions.where((s) => s.isSleep).toList());

  @override
  Stream<List<domain.FrontingSession>> watchRecentSessions({int limit = 20}) =>
      Stream.value(sessions.take(limit).toList());

  @override
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({int limit = 30}) =>
      Stream.value(sessions.take(limit).toList());

  @override
  Stream<domain.FrontingSession?> watchSessionById(String id) =>
      Stream.value(null);
}

class _FakeConversationRepository implements ConversationRepository {
  final List<domain.Conversation> conversations = [];

  @override
  Future<void> createConversation(domain.Conversation conversation) async =>
      conversations.add(conversation);

  @override
  Future<void> updateConversation(domain.Conversation conversation) async {
    final i = conversations.indexWhere((c) => c.id == conversation.id);
    if (i >= 0) conversations[i] = conversation;
  }

  @override
  Future<void> deleteConversation(String id) async =>
      conversations.removeWhere((c) => c.id == id);

  @override
  Future<List<domain.Conversation>> getAllConversations() async =>
      List.unmodifiable(conversations);

  @override
  Future<domain.Conversation?> getConversationById(String id) async =>
      conversations.cast<domain.Conversation?>().firstWhere(
        (c) => c?.id == id,
        orElse: () => null,
      );

  @override
  Future<List<domain.Conversation>> getConversationsForMember(String memberId) async =>
      conversations.where((c) => c.participantIds.contains(memberId)).toList();

  @override
  Future<void> addParticipantId(String conversationId, String memberId) async {}

  @override
  Future<void> addParticipantIds(String conversationId, List<String> memberIds) async {}

  @override
  Future<void> removeParticipantId(String conversationId, String memberId) async {}

  @override
  Future<void> setArchivedByMemberIds(String conversationId, List<String> memberIds) async {}

  @override
  Future<void> setMutedByMemberIds(String conversationId, List<String> memberIds) async {}

  @override
  Future<void> setLastReadTimestamps(
    String conversationId,
    Map<String, DateTime> timestamps,
  ) async {}

  @override
  Future<void> updateLastActivity(String id) async {}

  @override
  Future<int> getCount() async => conversations.length;

  @override
  Stream<List<domain.Conversation>> watchAllConversations() =>
      Stream.value(List.unmodifiable(conversations));

  @override
  Stream<domain.Conversation?> watchConversationById(String id) =>
      Stream.value(null);
}

class _FakeChatMessageRepository implements ChatMessageRepository {
  final List<domain.ChatMessage> messages = [];
  bool throwOnCreate = false;

  @override
  Future<void> createMessage(domain.ChatMessage message) async {
    if (throwOnCreate) throw Exception('simulated message insert failure');
    messages.add(message);
  }

  @override
  Future<void> updateMessage(domain.ChatMessage message) async {
    final i = messages.indexWhere((m) => m.id == message.id);
    if (i >= 0) messages[i] = message;
  }

  @override
  Future<void> deleteMessage(String id) async =>
      messages.removeWhere((m) => m.id == id);

  @override
  Future<List<domain.ChatMessage>> getAllMessages() async =>
      List.unmodifiable(messages);

  @override
  Future<List<domain.ChatMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
    int? offset,
  }) async =>
      messages.where((m) => m.conversationId == conversationId).toList();

  @override
  Future<domain.ChatMessage?> getMessageById(String id) async =>
      messages.cast<domain.ChatMessage?>().firstWhere(
        (m) => m?.id == id,
        orElse: () => null,
      );

  @override
  Future<domain.ChatMessage?> getLatestMessage(String conversationId) async =>
      null;

  @override
  Future<List<({String messageId, String conversationId, String snippet, DateTime timestamp, String? authorId})>>
      searchMessages(String query, {int limit = 20}) async => [];

  @override
  Stream<List<domain.ChatMessage>> watchMessagesForConversation(String conversationId) =>
      Stream.value([]);

  @override
  Stream<List<domain.ChatMessage>> watchRecentMessages(String conversationId, {required int limit}) =>
      Stream.value([]);

  @override
  Stream<domain.ChatMessage?> watchLatestMessage(String conversationId) =>
      Stream.value(null);

  @override
  Stream<int> watchUnreadCount(String conversationId, DateTime since) =>
      Stream.value(0);

  @override
  Stream<int> watchUnreadMentionCount(
    String conversationId,
    DateTime since,
    String memberId,
  ) => Stream.value(0);

  @override
  Stream<Map<String, int>> watchAllUnreadCounts(
    Map<String, DateTime> conversationSince,
  ) => Stream.value({});

  @override
  Stream<Set<String>> watchConversationsWithMentions(
    Map<String, DateTime> conversationSince,
    String memberId,
  ) => Stream.value({});
}

class _FakePollRepository implements PollRepository {
  final List<domain.Poll> polls = [];
  final List<domain.PollOption> options = [];
  final List<domain.PollVote> votes = [];

  @override
  Future<void> createPoll(domain.Poll poll) async => polls.add(poll);

  @override
  Future<void> updatePoll(domain.Poll poll) async {
    final i = polls.indexWhere((p) => p.id == poll.id);
    if (i >= 0) polls[i] = poll;
  }

  @override
  Future<void> deletePoll(String id) async =>
      polls.removeWhere((p) => p.id == id);

  @override
  Future<void> closePoll(String id) async {}

  @override
  Future<void> createOption(domain.PollOption option, String pollId) async =>
      options.add(option);

  @override
  Future<void> deleteOption(String id) async =>
      options.removeWhere((o) => o.id == id);

  @override
  Future<void> castVote(domain.PollVote vote, String optionId) async =>
      votes.add(vote);

  @override
  Future<void> removeVote(String id) async =>
      votes.removeWhere((v) => v.id == id);

  @override
  Future<List<domain.Poll>> getAllPolls() async => List.unmodifiable(polls);

  @override
  Future<List<domain.Poll>> getActivePolls() async =>
      polls.where((p) => !p.isClosed).toList();

  @override
  Future<List<domain.Poll>> getClosedPolls() async =>
      polls.where((p) => p.isClosed).toList();

  @override
  Future<domain.Poll?> getPollById(String id) async =>
      polls.cast<domain.Poll?>().firstWhere(
        (p) => p?.id == id,
        orElse: () => null,
      );

  @override
  Future<List<domain.PollOption>> getAllOptions() async =>
      List.unmodifiable(options);

  @override
  Future<Map<String, List<domain.PollOption>>> getAllOptionsGroupedByPoll() async => {};

  @override
  Future<List<domain.PollOption>> getOptionsForPoll(String pollId) async =>
      options.where((o) => true).toList(); // simplified

  @override
  Future<List<domain.PollVote>> getAllVotes() async =>
      List.unmodifiable(votes);

  @override
  Future<Map<String, List<domain.PollVote>>> getAllVotesGroupedByOption() async => {};

  @override
  Future<List<domain.PollVote>> getVotesForOption(String optionId) async =>
      votes;

  @override
  Future<int> getCount() async => polls.length;

  @override
  Stream<List<domain.Poll>> watchAllPolls() => Stream.value(polls);

  @override
  Stream<List<domain.Poll>> watchActivePolls() =>
      Stream.value(polls.where((p) => !p.isClosed).toList());

  @override
  Stream<domain.Poll?> watchPollById(String id) => Stream.value(null);

  @override
  Stream<List<domain.PollOption>> watchOptionsForPoll(String pollId) =>
      Stream.value([]);

  @override
  Stream<List<domain.PollVote>> watchVotesForOption(String optionId) =>
      Stream.value([]);
}


// =============================================================================
// Helpers
// =============================================================================

/// Minimal valid SpExportData: 2 members, 1 front history, 1 channel, 1 message.
SpExportData _makeFullExportData() {
  const memberA = SpMember(id: 'sp-a', name: 'Alice');
  const memberB = SpMember(id: 'sp-b', name: 'Bob');
  const channel = SpChannel(id: 'ch-1', name: 'General');
  final message = SpMessage(
    id: 'msg-1',
    channelId: 'ch-1',
    content: 'Hello!',
    timestamp: DateTime(2025, 1, 1),
  );
  final session = SpFrontHistory(
    id: 'fh-1',
    memberId: 'sp-a',
    startTime: DateTime(2025, 1, 1),
    endTime: DateTime(2025, 1, 2),
  );

  return SpExportData(
    members: [memberA, memberB],
    customFronts: [],
    frontHistory: [session],
    groups: [],
    channels: [channel],
    messages: [message],
    polls: [],
  );
}

/// Minimal SpExportData (all empty lists).
SpExportData _emptyExportData() => const SpExportData(
  members: [],
  customFronts: [],
  frontHistory: [],
  groups: [],
  channels: [],
  messages: [],
  polls: [],
);

/// Build a standard set of fakes for use in most tests.
({
  _FakeMemberRepository memberRepo,
  _FakeSessionRepository sessionRepo,
  _FakeConversationRepository conversationRepo,
  _FakeChatMessageRepository messageRepo,
  _FakePollRepository pollRepo,
}) _makeFakeRepos() {
  return (
    memberRepo: _FakeMemberRepository(),
    sessionRepo: _FakeSessionRepository(),
    conversationRepo: _FakeConversationRepository(),
    messageRepo: _FakeChatMessageRepository(),
    pollRepo: _FakePollRepository(),
  );
}

/// Build an in-memory AppDatabase with real Drift repositories.
AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // Happy path
  // ---------------------------------------------------------------------------

  group('happy path', () {
    test('members + sessions + conversations imported with correct counts',
        () async {
      final repos = _makeFakeRepos();
      final importer = SpImporter(httpClient: _FakeHttpClient());

      final result = await importer.executeImport(
        db: _makeDb(),
        data: _makeFullExportData(),
        memberRepo: repos.memberRepo,
        sessionRepo: repos.sessionRepo,
        conversationRepo: repos.conversationRepo,
        messageRepo: repos.messageRepo,
        pollRepo: repos.pollRepo,
        downloadAvatars: false,
      );

      expect(result.membersImported, 2);
      expect(result.sessionsImported, 1);
      expect(result.conversationsImported, 1);
      expect(result.messagesImported, 1);
      expect(result.pollsImported, 0);
      expect(result.avatarsDownloaded, 0);
    });

    test('empty export produces zero counts and no errors', () async {
      final repos = _makeFakeRepos();
      final importer = SpImporter(httpClient: _FakeHttpClient());

      final result = await importer.executeImport(
        db: _makeDb(),
        data: _emptyExportData(),
        memberRepo: repos.memberRepo,
        sessionRepo: repos.sessionRepo,
        conversationRepo: repos.conversationRepo,
        messageRepo: repos.messageRepo,
        pollRepo: repos.pollRepo,
        downloadAvatars: false,
      );

      expect(result.membersImported, 0);
      expect(result.sessionsImported, 0);
      expect(result.conversationsImported, 0);
      expect(result.messagesImported, 0);
      expect(result.pollsImported, 0);
      expect(result.warnings, isEmpty);
    });

    test('unknown member in front history produces a warning', () async {
      // SpFrontHistory referencing 'unknown-member-id' which has no matching
      // SpMember — the mapper should emit a warning.
      final data = SpExportData(
        members: const [SpMember(id: 'sp-a', name: 'Alice')],
        customFronts: const [],
        frontHistory: [
          SpFrontHistory(
            id: 'fh-1',
            memberId: 'no-such-member',
            startTime: DateTime(2025, 1, 1),
          ),
        ],
        groups: const [],
        channels: const [],
        messages: const [],
        polls: const [],
      );

      final repos = _makeFakeRepos();
      final importer = SpImporter(httpClient: _FakeHttpClient());

      final result = await importer.executeImport(
        db: _makeDb(),
        data: data,
        memberRepo: repos.memberRepo,
        sessionRepo: repos.sessionRepo,
        conversationRepo: repos.conversationRepo,
        messageRepo: repos.messageRepo,
        pollRepo: repos.pollRepo,
        downloadAvatars: false,
      );

      expect(result.warnings, isNotEmpty);
      expect(
        result.warnings.any((w) => w.contains('no-such-member') || w.contains('not found')),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Avatar downloads
  // ---------------------------------------------------------------------------

  group('avatar downloads', () {
    test('200 + image/png stores bytes on member', () async {
      const avatarUrl = 'https://example.com/avatar.png';
      final fakeBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      final client = _FakeHttpClient();
      client.stubUrl(
        avatarUrl,
        http.Response.bytes(
          fakeBytes,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );

      const data = SpExportData(
        members: [SpMember(id: 'sp-a', name: 'Alice', avatarUrl: avatarUrl)],
        customFronts: [],
        frontHistory: [],
        groups: [],
        channels: [],
        messages: [],
        polls: [],
      );

      final memberRepo = _FakeMemberRepository();
      final importer = SpImporter(httpClient: client);

      final result = await importer.executeImport(
        db: _makeDb(),
        data: data,
        memberRepo: memberRepo,
        sessionRepo: _FakeSessionRepository(),
        conversationRepo: _FakeConversationRepository(),
        messageRepo: _FakeChatMessageRepository(),
        pollRepo: _FakePollRepository(),
        downloadAvatars: true,
      );

      expect(result.avatarsDownloaded, 1);
      expect(client.calls, contains(avatarUrl));
      expect(memberRepo.lastUpdatedMember, isNotNull);
      expect(memberRepo.lastUpdatedMember!.avatarImageData, isNotNull);
      expect(memberRepo.lastUpdatedMember!.avatarImageData, equals(fakeBytes));
    });

    test('404 → member saved without avatar and avatarsDownloaded == 0', () async {
      const avatarUrl = 'https://example.com/missing.png';

      final client = _FakeHttpClient();
      client.stubUrl(avatarUrl, http.Response('not found', 404));

      const data = SpExportData(
        members: [SpMember(id: 'sp-a', name: 'Alice', avatarUrl: avatarUrl)],
        customFronts: [],
        frontHistory: [],
        groups: [],
        channels: [],
        messages: [],
        polls: [],
      );

      final memberRepo = _FakeMemberRepository();
      final importer = SpImporter(httpClient: client);

      final result = await importer.executeImport(
        db: _makeDb(),
        data: data,
        memberRepo: memberRepo,
        sessionRepo: _FakeSessionRepository(),
        conversationRepo: _FakeConversationRepository(),
        messageRepo: _FakeChatMessageRepository(),
        pollRepo: _FakePollRepository(),
        downloadAvatars: true,
      );

      expect(result.avatarsDownloaded, 0);
      // Member was still imported.
      expect(result.membersImported, 1);
      // No update was called (no avatar data to store).
      expect(memberRepo.lastUpdatedMember, isNull);
    });

    test('200 + text/html → content-type guard rejects and emits warning',
        () async {
      const avatarUrl = 'https://example.com/redirect.html';

      final client = _FakeHttpClient();
      client.stubUrl(
        avatarUrl,
        http.Response.bytes(
          Uint8List.fromList([60, 104, 116, 109, 108, 62]), // <html>
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );

      const data = SpExportData(
        members: [SpMember(id: 'sp-a', name: 'Alice', avatarUrl: avatarUrl)],
        customFronts: [],
        frontHistory: [],
        groups: [],
        channels: [],
        messages: [],
        polls: [],
      );

      final importer = SpImporter(httpClient: client);

      final result = await importer.executeImport(
        db: _makeDb(),
        data: data,
        memberRepo: _FakeMemberRepository(),
        sessionRepo: _FakeSessionRepository(),
        conversationRepo: _FakeConversationRepository(),
        messageRepo: _FakeChatMessageRepository(),
        pollRepo: _FakePollRepository(),
        downloadAvatars: true,
      );

      expect(result.avatarsDownloaded, 0);
      // After refactoring the per-URL HTTP guard into the shared
      // fetchAvatarBytes helper, callers get a generic per-member "avatar
      // download failed" warning. The content-type check is now covered
      // end-to-end by avatar_fetcher_test.dart.
      expect(
        result.warnings.any((w) => w.toLowerCase().contains('avatar')),
        isTrue,
        reason: 'Expected a per-member avatar-download warning',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Progress callback
  // ---------------------------------------------------------------------------

  group('progress callback', () {
    test('fires labels in sequence and progress is monotonically non-decreasing',
        () async {
      final progressLog = <(int, int, String)>[];

      final repos = _makeFakeRepos();
      final importer = SpImporter(httpClient: _FakeHttpClient());

      await importer.executeImport(
        db: _makeDb(),
        data: _makeFullExportData(),
        memberRepo: repos.memberRepo,
        sessionRepo: repos.sessionRepo,
        conversationRepo: repos.conversationRepo,
        messageRepo: repos.messageRepo,
        pollRepo: repos.pollRepo,
        downloadAvatars: false,
        onProgress: (current, total, label) {
          progressLog.add((current, total, label));
        },
      );

      expect(progressLog, isNotEmpty);

      // Should see at least a 'members' label.
      expect(
        progressLog.any((e) => e.$3.toLowerCase().contains('member')),
        isTrue,
        reason: 'Expected a progress label mentioning members',
      );

      // Current should never exceed total.
      for (final (current, total, _) in progressLog) {
        expect(current, lessThanOrEqualTo(total));
      }

      // Current values should be non-decreasing over the sequence.
      for (var i = 1; i < progressLog.length; i++) {
        expect(
          progressLog[i].$1,
          greaterThanOrEqualTo(progressLog[i - 1].$1),
          reason: 'Progress current should not go backwards',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Transaction rollback
  // ---------------------------------------------------------------------------

  group('transaction rollback', () {
    test('exception mid-import rolls back all inserts', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      final sessionRepo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
      final conversationRepo = DriftConversationRepository(db.conversationsDao, null);
      final pollRepo = DriftPollRepository(db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null);

      // The message repo will throw, which should roll back members too.
      final throwingMessageRepo = _FakeChatMessageRepository()..throwOnCreate = true;

      final data = SpExportData(
        members: const [SpMember(id: 'sp-a', name: 'Alice')],
        customFronts: const [],
        frontHistory: const [],
        groups: const [],
        channels: const [SpChannel(id: 'ch-1', name: 'General')],
        messages: [
          SpMessage(
            id: 'msg-1',
            channelId: 'ch-1',
            content: 'Hello!',
            timestamp: DateTime(2025, 1, 1),
          ),
        ],
        polls: const [],
      );

      // The real DB transaction should roll back; the fake messageRepo throws
      // inside the transaction body.
      Object? caught;
      try {
        await SpImporter(httpClient: _FakeHttpClient()).executeImport(
          db: db,
          data: data,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
          conversationRepo: conversationRepo,
          messageRepo: throwingMessageRepo,
          pollRepo: pollRepo,
          downloadAvatars: false,
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isNotNull, reason: 'Should have propagated the exception');

      // Members should be rolled back — none present in the DB.
      final members = await db.membersDao.getAllMembers();
      expect(
        members,
        isEmpty,
        reason: 'Transaction rollback should have removed the inserted member',
      );
    });

    test('clearExistingData + failure → pre-existing data is preserved (rollback includes wipe)',
        () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);
      final sessionRepo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
      final conversationRepo = DriftConversationRepository(db.conversationsDao, null);
      final pollRepo = DriftPollRepository(db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null);

      // Seed one existing member via the real repo.
      await memberRepo.createMember(domain.Member(
        id: 'existing-1',
        name: 'Existing',
        createdAt: DateTime(2025, 1, 1),
      ));

      // Verify it's there before import.
      final beforeImport = await db.membersDao.getAllMembers();
      expect(beforeImport.length, 1);

      // Message repo throws mid-import to trigger rollback.
      final throwingMessageRepo = _FakeChatMessageRepository()..throwOnCreate = true;

      final data = SpExportData(
        members: const [SpMember(id: 'sp-new', name: 'New Member')],
        customFronts: const [],
        frontHistory: const [],
        groups: const [],
        channels: const [SpChannel(id: 'ch-1', name: 'General')],
        messages: [
          SpMessage(
            id: 'msg-1',
            channelId: 'ch-1',
            content: 'Hi!',
            timestamp: DateTime(2025, 1, 1),
          ),
        ],
        polls: const [],
      );

      Object? caught;
      try {
        await SpImporter(httpClient: _FakeHttpClient()).executeImport(
          db: db,
          data: data,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
          conversationRepo: conversationRepo,
          messageRepo: throwingMessageRepo,
          pollRepo: pollRepo,
          clearExistingData: true,
          downloadAvatars: false,
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);

      // Because clearExistingData and the inserts are inside the SAME
      // transaction, a rollback undoes the wipe too — the pre-existing member
      // should still be present.
      final afterImport = await db.membersDao.getAllMembers();
      expect(
        afterImport.length,
        1,
        reason:
            'The wipe was inside the rolled-back transaction, so pre-existing '
            'data should be restored',
      );
      expect(afterImport.first.id, 'existing-1');
    });
  });
}
