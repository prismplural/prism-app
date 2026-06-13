import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase, SpIdMapTableCompanion;
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/conversation.dart' as domain;
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/poll.dart' as domain;
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/models/poll_option.dart' as domain;
import 'package:prism_plurality/domain/models/poll_vote.dart' as domain;
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_member_mapping.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

import '../../../helpers/fake_repositories.dart';

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
    final response =
        _responses[request.url.toString()] ?? http.Response('not found', 404);
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
  Future<void> createMember(domain.Member member) async => _members.add(member);

  @override
  Future<void> updateMember(domain.Member member) async {
    lastUpdatedMember = member;
    final i = _members.indexWhere((m) => m.id == member.id);
    if (i >= 0) _members[i] = member;
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async =>
      throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> excludePluralKitSync(String id) async =>
      throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> resumePluralKitSync(String id) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) async =>
      _members.removeWhere((m) => m.id == id);

  @override
  Future<List<domain.Member>> getAllMembers() async =>
      List.unmodifiable(_members);

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async =>
      List.unmodifiable(_members);

  @override
  Future<domain.Member?> getMemberById(String id) async => _members
      .cast<domain.Member?>()
      .firstWhere((m) => m?.id == id, orElse: () => null);

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      _members.where((m) => ids.contains(m.id)).toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<int> getCount() async => _members.length;

  @override
  Stream<List<domain.Member>> watchAllMembers() =>
      Stream.value(List.unmodifiable(_members));

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      Stream.value(_members.where((m) => m.isActive).toList());

  @override
  Stream<domain.Member?> watchMemberById(String id) => Stream.value(
    _members.cast<domain.Member?>().firstWhere(
      (m) => m?.id == id,
      orElse: () => null,
    ),
  );

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
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
  Future<domain.FrontingSession?> getSessionById(String id) async => sessions
      .cast<domain.FrontingSession?>()
      .firstWhere((s) => s?.id == id, orElse: () => null);

  @override
  Future<List<domain.FrontingSession>> getRecentSessions({
    int limit = 20,
  }) async => sessions.take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) async => sessions.where((s) => s.isSleep).take(limit).toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async => sessions
      .where((s) => !s.startTime.isBefore(start) && !s.startTime.isAfter(end))
      .toList();

  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(
    String memberId,
  ) async => sessions.where((s) => s.memberId == memberId).toList();

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
  Stream<domain.FrontingSession?> watchActiveSleepSession() =>
      Stream.value(null);

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
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({
    int limit = 30,
  }) => Stream.value(sessions.take(limit).toList());

  @override
  Stream<List<domain.FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) {
    final overlapping = sessions.where((s) {
      if (!s.startTime.isBefore(end)) return false;
      final endTime = s.endTime;
      if (endTime == null) return true;
      return endTime.isAfter(start);
    }).toList();
    return Stream.value(overlapping);
  }

  @override
  Stream<domain.FrontingSession?> watchSessionById(String id) =>
      Stream.value(null);

  @override
  Future<List<domain.FrontingSession>> getDeletedSleepSessions() async =>
      const [];

  @override
  Future<List<domain.FrontingSession>> getDeletedLinkedSessions() async =>
      const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) async => (count: 0, avgDuration: null);

  @override
  Stream<List<domain.FrontingSession>> watchRecentSleepSessions({
    required int limit,
  }) => Stream.value(const []);
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
  Future<List<domain.Conversation>> getConversationsByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const <domain.Conversation>[];
    final wanted = ids.toSet();
    return [
      for (final c in conversations)
        if (wanted.contains(c.id)) c,
    ];
  }

  @override
  Future<List<domain.Conversation>> getConversationsForMember(
    String memberId,
  ) async => conversations
      .where(
        (c) =>
            (c.participantIds.contains(memberId) || c.includesAllMembers) &&
            !c.archivedForEveryone &&
            !c.archivedByMemberIds.contains(memberId),
      )
      .toList();

  @override
  Future<List<ConversationActivity>> getConversationActivityForMember(
    String memberId, {
    int? limit,
  }) async {
    final conversations = await getConversationsForMember(memberId);
    final activity = [
      for (final conversation in conversations)
        (conversation: conversation, messageCount: 0),
    ];
    return limit == null ? activity : activity.take(limit).toList();
  }

  @override
  Future<void> addParticipantId(String conversationId, String memberId) async {}

  @override
  Future<void> addParticipantIds(
    String conversationId,
    List<String> memberIds,
  ) async {}

  @override
  Future<void> removeParticipantId(
    String conversationId,
    String memberId,
  ) async {}

  @override
  Future<void> setIncludesAllMembers(String conversationId, bool value) async {}

  @override
  Future<void> setArchivedForEveryone(
    String conversationId,
    bool value,
  ) async {}

  @override
  Future<void> setArchivedByMemberIds(
    String conversationId,
    List<String> memberIds,
  ) async {}

  @override
  Future<void> setMutedByMemberIds(
    String conversationId,
    List<String> memberIds,
  ) async {}

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

/// Wraps a real [MemberRepository] and throws on the first existing-members
/// read. Used by the rollback tests below to force a transaction failure.
///
/// Phase 6's batch path bypasses every per-row `messageRepo.createMessage`
/// call, so the pre-Phase-6 fault injection via `_FakeChatMessageRepository
/// .throwOnCreate` no longer fires. The SP importer still calls
/// `memberRepo.getAllMembersIncludingDeleted()` once at the top of its
/// members loop (pre-resolve existing-member/tombstone detection), so that's
/// the durable failure-injection point that survives later batching changes.
class _ThrowingMemberRepository implements MemberRepository {
  _ThrowingMemberRepository(this._inner);
  final MemberRepository _inner;
  bool _thrown = false;

  @override
  Future<List<domain.Member>> getAllMembers() =>
      _throwOnceOr(_inner.getAllMembers);

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() =>
      _throwOnceOr(_inner.getAllMembersIncludingDeleted);

  Future<List<domain.Member>> _throwOnceOr(
    Future<List<domain.Member>> Function() read,
  ) async {
    if (!_thrown) {
      _thrown = true;
      throw Exception('simulated members read failure');
    }
    return read();
  }

  @override
  Future<void> clearPluralKitLink(String id) => _inner.clearPluralKitLink(id);
  @override
  Future<void> createMember(domain.Member member) =>
      _inner.createMember(member);
  @override
  Future<void> deleteMember(String id) => _inner.deleteMember(id);
  @override
  Future<int> getCount() => _inner.getCount();
  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() =>
      _inner.getDeletedLinkedMembers();
  @override
  Future<domain.Member?> getMemberById(String id) => _inner.getMemberById(id);
  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) =>
      _inner.getMembersByIds(ids);
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      _inner.stampDeletePushStartedAt(id, timestampMs);
  @override
  Future<void> updateMember(domain.Member member) =>
      _inner.updateMember(member);
  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) => _inner.updateMemberFields(id, changedFields);
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) =>
      _inner.applyPluralKitLink(id, patch);
  @override
  Future<int> recordPluralKitIdentity(String id, Map<String, dynamic> patch) =>
      _inner.recordPluralKitIdentity(id, patch);
  @override
  Future<int> excludePluralKitSync(String id) =>
      _inner.excludePluralKitSync(id);
  @override
  Future<int> resumePluralKitSync(String id) => _inner.resumePluralKitSync(id);
  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      _inner.watchActiveMembers();
  @override
  Stream<List<domain.Member>> watchAllMembers() => _inner.watchAllMembers();
  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      _inner.watchMemberById(id);
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      _inner.watchMembersByIds(ids);
  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => _inner.ensureUnknownSentinelMember();
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
  Future<domain.ChatMessage?> getMessageById(String id) async => messages
      .cast<domain.ChatMessage?>()
      .firstWhere((m) => m?.id == id, orElse: () => null);

  @override
  Future<bool> isMessageDeleted(String messageId) async => false;

  @override
  Future<domain.ChatMessage?> getLatestMessage(String conversationId) async =>
      null;

  @override
  Future<
    List<
      ({
        String messageId,
        String conversationId,
        String snippet,
        DateTime timestamp,
        String? authorId,
      })
    >
  >
  searchMessages(String query, {int limit = 20}) async => [];

  @override
  Stream<List<domain.ChatMessage>> watchMessagesForConversation(
    String conversationId,
  ) => Stream.value([]);

  @override
  Stream<List<domain.ChatMessage>> watchRecentMessages(
    String conversationId, {
    required int limit,
  }) => Stream.value([]);

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
  Future<domain.Poll?> getPollById(String id) async => polls
      .cast<domain.Poll?>()
      .firstWhere((p) => p?.id == id, orElse: () => null);

  @override
  Future<List<domain.PollOption>> getAllOptions() async =>
      List.unmodifiable(options);

  @override
  Future<Map<String, List<domain.PollOption>>>
  getAllOptionsGroupedByPoll() async => {};

  @override
  Future<List<domain.PollOption>> getOptionsForPoll(String pollId) async =>
      options.where((o) => true).toList(); // simplified

  @override
  Future<List<domain.PollVote>> getAllVotes() async => List.unmodifiable(votes);

  @override
  Future<Map<String, List<domain.PollVote>>>
  getAllVotesGroupedByOption() async => {};

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
})
_makeFakeRepos() {
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

Uint8List _jpegBytes(int r, int g, int b) {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<String> _writeAvatarZip(Map<String, Uint8List> files) async {
  final dir = await Directory.systemTemp.createTemp('sp-importer-avatar-zip-');
  addTearDown(() => dir.delete(recursive: true));

  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  final file = File('${dir.path}/avatars.zip');
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file.path;
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // Happy path
  // ---------------------------------------------------------------------------

  group('happy path', () {
    test(
      'members + sessions + conversations imported with correct counts',
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
      },
    );

    test(
      'non-sync member repository no longer surfaces a replay-skip warning '
      '(F08: emissions persist to the outbox, not via the member repo)',
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

        // The importer removed the in-memory post-commit replay (and its no-emitter /
        // replay-failure warnings): captured emissions are persisted into the
        // durable outbox inside the import transaction and dispatched by the
        // drainer, independent of whether the member repo mixes in
        // SyncRecordMixin. No replay-skip warning should remain.
        expect(
          result.warnings.where(
            (w) => w.contains('sync emissions could not be replayed'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'legacy encrypted SP chat rows are skipped while decrypted rows with iv import',
      () async {
        final repos = _makeFakeRepos();
        final importer = SpImporter(httpClient: _FakeHttpClient());

        final data = SpExportData(
          members: const [SpMember(id: 'sp-a', name: 'Alice')],
          customFronts: const [],
          frontHistory: const [],
          groups: const [],
          channels: const [SpChannel(id: 'ch-1', name: 'General')],
          messages: [
            SpMessage.fromJson(const {
              '_id': 'msg-plaintext',
              'channel': 'ch-1',
              'writer': 'sp-a',
              'message': 'Plaintext from a current Simply Plural export',
              'iv': 'YWJjZGVmZ2hpamtsbW5vcA==',
              'writtenAt': 1735689600000,
            }, 'ch-1'),
            SpMessage.fromJson(const {
              '_id': 'msg-encrypted',
              'channel': 'ch-1',
              'writer': 'sp-a',
              'message': 'rR9y0tk=',
              'iv': 'YWJjZGVmZ2hpamtsbW5vcA==',
              'writtenAt': 1735689660000,
            }, 'ch-1'),
          ],
          polls: const [],
        );

        expect(data.messages.first.looksEncrypted, isFalse);
        expect(data.messages.last.looksEncrypted, isTrue);

        final db = _makeDb();
        addTearDown(db.close);
        final result = await importer.executeImport(
          db: db,
          data: data,
          memberRepo: repos.memberRepo,
          sessionRepo: repos.sessionRepo,
          conversationRepo: repos.conversationRepo,
          messageRepo: repos.messageRepo,
          pollRepo: repos.pollRepo,
          downloadAvatars: false,
        );

        final messages = await db.chatMessagesDao.getAllMessages();
        expect(result.messagesImported, 1);
        expect(messages, hasLength(1));
        expect(
          messages.single.content,
          'Plaintext from a current Simply Plural export',
        );
        expect(
          result.warnings.any(
            (w) => w.toLowerCase().contains('encrypted') && w.contains('1'),
          ),
          isTrue,
        );
      },
    );

    test(
      'SP member with matching PluralKit short ID reuses existing local member',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        await memberRepo.createMember(
          domain.Member(
            id: 'pk-local-alice',
            name: 'Alice from PK',
            createdAt: DateTime(2025, 1, 1),
            pluralkitId: 'abcde',
          ),
        );

        final result = await SpImporter(httpClient: _FakeHttpClient())
            .executeImport(
              db: db,
              data: SpExportData(
                members: const [
                  SpMember(id: 'sp-alice', name: 'Alice', pkId: 'abcde'),
                ],
                customFronts: const [],
                frontHistory: [
                  SpFrontHistory(
                    id: 'front-1',
                    memberId: 'sp-alice',
                    startTime: DateTime(2025, 1, 2),
                    endTime: DateTime(2025, 1, 3),
                  ),
                ],
                groups: const [],
                channels: const [],
                messages: const [],
                polls: const [],
              ),
              memberRepo: memberRepo,
              sessionRepo: sessionRepo,
              conversationRepo: _FakeConversationRepository(),
              messageRepo: _FakeChatMessageRepository(),
              pollRepo: _FakePollRepository(),
              spImportDao: db.spImportDao,
              downloadAvatars: false,
            );

        final members = await memberRepo.getAllMembers();
        final sessions = await sessionRepo.getAllSessions();
        final mappings = await db.spImportDao.getAllMappings();

        expect(result.membersImported, 0);
        expect(result.sessionsImported, 1);
        expect(members, hasLength(1));
        expect(members.single.id, 'pk-local-alice');
        expect(sessions.single.memberId, 'pk-local-alice');
        expect(
          mappings.any(
            (row) =>
                row.entityType == 'member' &&
                row.spId == 'sp-alice' &&
                row.prismId == 'pk-local-alice',
          ),
          isTrue,
        );
      },
    );

    test(
      'persisted mapping to soft-deleted PK member imports as new without PK collision',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        await memberRepo.createMember(
          domain.Member(
            id: 'pk-local-alice',
            name: 'Deleted Alice from PK',
            createdAt: DateTime(2025, 1, 1),
            pluralkitId: 'abcde',
          ),
        );
        await memberRepo.deleteMember('pk-local-alice');
        await db.spImportDao.upsertMappings([
          const SpIdMapTableCompanion(
            spId: Value('sp-alice'),
            entityType: Value('member'),
            prismId: Value('pk-local-alice'),
          ),
        ]);

        final result = await SpImporter(httpClient: _FakeHttpClient())
            .executeImport(
              db: db,
              data: const SpExportData(
                members: [
                  SpMember(id: 'sp-alice', name: 'Alice', pkId: 'abcde'),
                ],
                customFronts: [],
                frontHistory: [],
                groups: [],
                channels: [],
                messages: [],
                polls: [],
              ),
              memberRepo: memberRepo,
              sessionRepo: _FakeSessionRepository(),
              conversationRepo: _FakeConversationRepository(),
              messageRepo: _FakeChatMessageRepository(),
              pollRepo: _FakePollRepository(),
              spImportDao: db.spImportDao,
              downloadAvatars: false,
            );

        final activeMembers = await memberRepo.getAllMembers();
        final allMembers = await memberRepo.getAllMembersIncludingDeleted();
        final mappings = await db.spImportDao.getAllMappings();

        expect(result.membersImported, 1);
        expect(result.membersLinked, 0);
        expect(activeMembers, hasLength(1));
        expect(activeMembers.single.id, isNot('pk-local-alice'));
        expect(activeMembers.single.pluralkitId, isNull);
        expect(allMembers, hasLength(2));
        expect(
          allMembers.singleWhere((m) => m.id == 'pk-local-alice').isDeleted,
          isTrue,
        );
        expect(
          mappings
              .singleWhere(
                (row) => row.entityType == 'member' && row.spId == 'sp-alice',
              )
              .prismId,
          activeMembers.single.id,
        );
      },
    );

    test(
      'SP member with unique exact name reuses existing local member',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        await memberRepo.createMember(
          domain.Member(
            id: 'existing-alice',
            name: 'Alice',
            createdAt: DateTime(2025, 1, 1),
          ),
        );

        final result = await SpImporter(httpClient: _FakeHttpClient())
            .executeImport(
              db: db,
              data: SpExportData(
                members: const [SpMember(id: 'sp-alice', name: ' Alice ')],
                customFronts: const [],
                frontHistory: [
                  SpFrontHistory(
                    id: 'front-1',
                    memberId: 'sp-alice',
                    startTime: DateTime(2025, 1, 2),
                    endTime: DateTime(2025, 1, 3),
                  ),
                ],
                groups: const [],
                channels: const [],
                messages: const [],
                polls: const [],
              ),
              memberRepo: memberRepo,
              sessionRepo: sessionRepo,
              conversationRepo: _FakeConversationRepository(),
              messageRepo: _FakeChatMessageRepository(),
              pollRepo: _FakePollRepository(),
              spImportDao: db.spImportDao,
              downloadAvatars: false,
            );

        final members = await memberRepo.getAllMembers();
        final sessions = await sessionRepo.getAllSessions();

        expect(result.membersImported, 0);
        expect(members, hasLength(1));
        expect(sessions.single.memberId, 'existing-alice');
      },
    );

    test(
      'SP member named Unknown does not collapse into the system sentinel',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        await memberRepo.ensureUnknownSentinelMember();
        await db.spImportDao.upsertMappings([
          SpIdMapTableCompanion(
            spId: const Value('sp-real-unknown'),
            entityType: const Value('member'),
            prismId: Value(unknownSentinelMemberId),
          ),
        ]);

        final result = await SpImporter(httpClient: _FakeHttpClient())
            .executeImport(
              db: db,
              data: SpExportData(
                members: const [
                  SpMember(id: 'sp-real-unknown', name: 'Unknown'),
                ],
                customFronts: const [],
                frontHistory: [
                  SpFrontHistory(
                    id: 'front-real',
                    memberId: 'sp-real-unknown',
                    startTime: DateTime(2025, 1, 2),
                    endTime: DateTime(2025, 1, 3),
                  ),
                  SpFrontHistory(
                    id: 'front-literal-unknown',
                    memberId: 'unknown',
                    startTime: DateTime(2025, 1, 4),
                    endTime: DateTime(2025, 1, 5),
                  ),
                ],
                groups: const [],
                channels: const [],
                messages: const [],
                polls: const [],
              ),
              memberRepo: memberRepo,
              sessionRepo: sessionRepo,
              conversationRepo: _FakeConversationRepository(),
              messageRepo: _FakeChatMessageRepository(),
              pollRepo: _FakePollRepository(),
              spImportDao: db.spImportDao,
              downloadAvatars: false,
            );

        final members = await memberRepo.getAllMembers();
        final sessions = await sessionRepo.getAllSessions();
        final mappings = await db.spImportDao.getAllMappings();
        final realUnknownSession = sessions.singleWhere(
          (s) => s.startTime == DateTime(2025, 1, 2),
          orElse: () => throw StateError('front-real was not imported'),
        );
        final literalUnknownSession = sessions.singleWhere(
          (s) => s.startTime == DateTime(2025, 1, 4),
          orElse: () =>
              throw StateError('front-literal-unknown was not imported'),
        );

        expect(result.membersImported, 1);
        expect(members, hasLength(2));
        expect(realUnknownSession.memberId, isNot(unknownSentinelMemberId));
        expect(literalUnknownSession.memberId, unknownSentinelMemberId);
        expect(
          members.where((m) => m.id == unknownSentinelMemberId),
          hasLength(1),
        );
        expect(
          mappings
              .singleWhere(
                (row) =>
                    row.entityType == 'member' && row.spId == 'sp-real-unknown',
              )
              .prismId,
          realUnknownSession.memberId,
        );
      },
    );

    test(
      'SP exact-name fallback does not match ambiguous local names',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepo = DriftMemberRepository(db.membersDao, null);

        await memberRepo.createMember(
          domain.Member(
            id: 'existing-alice-1',
            name: 'Alice',
            createdAt: DateTime(2025, 1, 1),
          ),
        );
        await memberRepo.createMember(
          domain.Member(
            id: 'existing-alice-2',
            name: 'alice',
            createdAt: DateTime(2025, 1, 1),
          ),
        );

        final result = await SpImporter(httpClient: _FakeHttpClient())
            .executeImport(
              db: db,
              data: const SpExportData(
                members: [SpMember(id: 'sp-alice', name: 'Alice')],
                customFronts: [],
                frontHistory: [],
                groups: [],
                channels: [],
                messages: [],
                polls: [],
              ),
              memberRepo: memberRepo,
              sessionRepo: _FakeSessionRepository(),
              conversationRepo: _FakeConversationRepository(),
              messageRepo: _FakeChatMessageRepository(),
              pollRepo: _FakePollRepository(),
              spImportDao: db.spImportDao,
              downloadAvatars: false,
            );

        final members = await memberRepo.getAllMembers();

        expect(result.membersImported, 1);
        expect(members, hasLength(3));
      },
    );

    test('SP exact-name fallback does not match ambiguous SP names', () async {
      final db = _makeDb();
      addTearDown(db.close);

      final memberRepo = DriftMemberRepository(db.membersDao, null);

      await memberRepo.createMember(
        domain.Member(
          id: 'existing-alice',
          name: 'Alice',
          createdAt: DateTime(2025, 1, 1),
        ),
      );

      final result = await SpImporter(httpClient: _FakeHttpClient())
          .executeImport(
            db: db,
            data: const SpExportData(
              members: [
                SpMember(id: 'sp-alice-1', name: 'Alice'),
                SpMember(id: 'sp-alice-2', name: 'alice'),
              ],
              customFronts: [],
              frontHistory: [],
              groups: [],
              channels: [],
              messages: [],
              polls: [],
            ),
            memberRepo: memberRepo,
            sessionRepo: _FakeSessionRepository(),
            conversationRepo: _FakeConversationRepository(),
            messageRepo: _FakeChatMessageRepository(),
            pollRepo: _FakePollRepository(),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
          );

      final members = await memberRepo.getAllMembers();

      expect(result.membersImported, 2);
      expect(members, hasLength(3));
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

    test(
      'board imports auto-enable boards without leaking disclosure key',
      () async {
        final db = _makeDb();
        final settingsRepo = FakeSystemSettingsRepository();
        final importer = SpImporter(httpClient: _FakeHttpClient());
        final data = SpExportData(
          members: const [
            SpMember(id: 'sp-a', name: 'Alice'),
            SpMember(id: 'sp-b', name: 'Bob'),
          ],
          customFronts: const [],
          frontHistory: const [],
          groups: const [],
          channels: const [],
          messages: const [],
          polls: const [],
          boardMessages: [
            SpBoardMessage(
              id: 'board-1',
              writtenBy: 'sp-a',
              writtenFor: 'sp-b',
              message: 'Imported board post',
              writtenAt: DateTime(2025, 1, 1),
            ),
          ],
        );

        final repos = _makeFakeRepos();

        final result = await importer.executeImport(
          db: db,
          data: data,
          memberRepo: DriftMemberRepository(db.membersDao, null),
          sessionRepo: repos.sessionRepo,
          conversationRepo: repos.conversationRepo,
          messageRepo: repos.messageRepo,
          pollRepo: repos.pollRepo,
          settingsRepo: settingsRepo,
          boardPostsRepo: DriftMemberBoardPostsRepository(
            db.memberBoardPostsDao,
            db.membersDao,
            null,
          ),
          downloadAvatars: false,
        );

        expect(result.boardPostsImported, 1);
        expect(settingsRepo.settings.boardsEnabled, isTrue);
        expect(
          settingsRepo.settings.navBarOverflowItems.contains('boards'),
          isTrue,
        );
        expect(
          result.warnings.any(
            (w) => w.contains('importDisclosureBoardsEnabled'),
          ),
          isFalse,
        );
      },
    );

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
        result.warnings.any(
          (w) => w.contains('no-such-member') || w.contains('not found'),
        ),
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

    test(
      'avatar ZIP overwrites remote avatar bytes when both are present',
      () async {
        const avatarUrl = 'https://example.com/avatar.png';
        // Phase 6 switched these tests to the real `DriftMemberRepository`
        // (see comment below). Drift's avatar normalize step decodes the
        // input bytes, so the fake byte buffer used pre-Phase-6 no longer
        // round-trips. Use a real JPEG so normalize is a no-op and the
        // bytes survive the round trip.
        final remoteBytes = _jpegBytes(10, 20, 30);
        final zipBytes = _jpegBytes(220, 20, 20);
        final zipPath = await _writeAvatarZip({'sp-a.jpg': zipBytes});

        final client = _FakeHttpClient();
        client.stubUrl(
          avatarUrl,
          http.Response.bytes(
            remoteBytes,
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

        final db = _makeDb();
        addTearDown(db.close);
        // Phase 6 batches member inserts through `db.membersDao` directly,
        // so the fake-repo `_members` list is no longer populated by the
        // importer. Use the real Drift-backed repo so `getAllMembers()`
        // reads from the same DB the batch wrote to.
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final importer = SpImporter(httpClient: client);

        final result = await importer.executeImport(
          db: db,
          data: data,
          memberRepo: memberRepo,
          sessionRepo: _FakeSessionRepository(),
          conversationRepo: _FakeConversationRepository(),
          messageRepo: _FakeChatMessageRepository(),
          pollRepo: _FakePollRepository(),
          spImportDao: db.spImportDao,
          downloadAvatars: true,
          avatarZipPath: zipPath,
        );

        final imported = (await memberRepo.getAllMembers()).single;
        expect(result.avatarsDownloaded, 1);
        expect(result.avatarsImportedFromZip, 1);
        expect(imported.avatarImageData, zipBytes);
      },
    );

    test(
      'explicit linked member keeps local avatar and imports dependent data',
      () async {
        const avatarUrl = 'https://example.com/avatar.png';
        final remoteBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final zipBytes = _jpegBytes(220, 20, 20);
        final originalAvatar = _jpegBytes(9, 9, 9);
        final zipPath = await _writeAvatarZip({'sp-a.jpg': zipBytes});

        final client = _FakeHttpClient();
        client.stubUrl(
          avatarUrl,
          http.Response.bytes(
            remoteBytes,
            200,
            headers: {'content-type': 'image/png'},
          ),
        );

        final data = SpExportData(
          members: const [
            SpMember(id: 'sp-a', name: 'Alice', avatarUrl: avatarUrl),
          ],
          customFronts: const [],
          frontHistory: [
            SpFrontHistory(
              id: 'front-a',
              memberId: 'sp-a',
              startTime: DateTime.utc(2024),
              endTime: DateTime.utc(2024, 1, 1, 1),
            ),
          ],
          groups: const [],
          channels: const [],
          messages: const [],
          polls: const [],
        );

        final db = _makeDb();
        addTearDown(db.close);
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final conversationRepo = DriftConversationRepository(
          db.conversationsDao,
          null,
        );
        final messageRepo = DriftChatMessageRepository(
          db.chatMessagesDao,
          null,
        );
        final pollRepo = DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        );

        await memberRepo.createMember(
          domain.Member(
            id: 'local-a',
            name: 'Local Alice',
            createdAt: DateTime.utc(2023),
            avatarImageData: originalAvatar,
          ),
        );

        final result = await SpImporter(httpClient: client).executeImport(
          db: db,
          data: data,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
          conversationRepo: conversationRepo,
          messageRepo: messageRepo,
          pollRepo: pollRepo,
          spImportDao: db.spImportDao,
          memberMappingDecisions: const {
            'sp-a': SpLinkMemberDecision(
              spMemberId: 'sp-a',
              localMemberId: 'local-a',
            ),
          },
          downloadAvatars: true,
          avatarZipPath: zipPath,
        );

        final members = await memberRepo.getAllMembers();
        expect(result.membersImported, 0);
        expect(result.membersLinked, 1);
        expect(result.sessionsImported, 1);
        expect(result.avatarsDownloaded, 0);
        expect(result.avatarsImportedFromZip, 0);
        expect(client.calls, isEmpty);
        expect(members, hasLength(1));
        expect(members.single.name, 'Local Alice');
        expect(members.single.avatarImageData, originalAvatar);
        expect((await sessionRepo.getAllSessions()).single.memberId, 'local-a');
      },
    );

    test(
      'explicit import-new decision is not re-linked by fallback matching',
      () async {
        const data = SpExportData(
          members: [SpMember(id: 'sp-a', name: 'Alice', pkId: 'abcde')],
          customFronts: [],
          frontHistory: [],
          groups: [],
          channels: [],
          messages: [],
          polls: [],
        );

        final db = _makeDb();
        addTearDown(db.close);
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final conversationRepo = DriftConversationRepository(
          db.conversationsDao,
          null,
        );
        final messageRepo = DriftChatMessageRepository(
          db.chatMessagesDao,
          null,
        );
        final pollRepo = DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        );

        await memberRepo.createMember(
          domain.Member(
            id: 'local-a',
            name: 'Alice',
            pluralkitId: 'abcde',
            createdAt: DateTime.utc(2023),
          ),
        );

        final result = await SpImporter(httpClient: _FakeHttpClient())
            .executeImport(
              db: db,
              data: data,
              memberRepo: memberRepo,
              sessionRepo: sessionRepo,
              conversationRepo: conversationRepo,
              messageRepo: messageRepo,
              pollRepo: pollRepo,
              spImportDao: db.spImportDao,
              memberMappingDecisions: const {
                'sp-a': SpImportMemberDecision(spMemberId: 'sp-a'),
              },
              downloadAvatars: false,
            );

        final members = await memberRepo.getAllMembers();
        expect(result.membersImported, 1);
        expect(result.membersLinked, 0);
        expect(members, hasLength(2));
        expect(members.where((member) => member.name == 'Alice'), hasLength(2));
        expect(
          members.any(
            (member) => member.id != 'local-a' && member.pluralkitId == null,
          ),
          isTrue,
        );
      },
    );

    test('malformed avatar ZIP becomes a warning after JSON import', () async {
      final zipFile = File('${Directory.systemTemp.path}/bad-sp-avatar.zip');
      await zipFile.writeAsBytes([1, 2, 3, 4]);
      addTearDown(() {
        if (zipFile.existsSync()) zipFile.deleteSync();
      });

      const data = SpExportData(
        members: [SpMember(id: 'sp-a', name: 'Alice')],
        customFronts: [],
        frontHistory: [],
        groups: [],
        channels: [],
        messages: [],
        polls: [],
      );
      final db = _makeDb();
      addTearDown(db.close);
      // Phase 6 batches member inserts through `db.membersDao` directly;
      // use the real Drift repo so `getAllMembers()` reads the same DB.
      final memberRepo = DriftMemberRepository(db.membersDao, null);

      final result = await SpImporter(httpClient: _FakeHttpClient())
          .executeImport(
            db: db,
            data: data,
            memberRepo: memberRepo,
            sessionRepo: _FakeSessionRepository(),
            conversationRepo: _FakeConversationRepository(),
            messageRepo: _FakeChatMessageRepository(),
            pollRepo: _FakePollRepository(),
            spImportDao: db.spImportDao,
            downloadAvatars: false,
            avatarZipPath: zipFile.path,
          );

      expect(result.membersImported, 1);
      expect(result.avatarsImportedFromZip, 0);
      expect(
        result.warnings.any((w) => w.contains('Could not import avatar ZIP')),
        isTrue,
      );
      expect((await memberRepo.getAllMembers()).single.name, 'Alice');
    });

    test(
      '404 → member saved without avatar and avatarsDownloaded == 0',
      () async {
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
      },
    );

    test(
      '200 + text/html → content-type guard rejects and emits warning',
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
      },
    );

    test('avatar retry warning classifier leaves ZIP warnings intact', () {
      expect(
        ImportResult.isAvatarDownloadWarning('1 avatar(s) failed to download'),
        isTrue,
      );
      expect(
        ImportResult.isAvatarDownloadWarning(
          'System avatar failed to download',
        ),
        isTrue,
      );
      expect(
        ImportResult.isAvatarDownloadWarning(
          'Could not import avatar ZIP: invalid archive',
        ),
        isFalse,
      );
      expect(
        ImportResult.isAvatarDownloadWarning(
          'No supported images were found in the avatar ZIP.',
        ),
        isFalse,
      );
    });

    test(
      'retryAvatarDownloads uses SP id map and preserves member edits',
      () async {
        const avatarUrl = 'https://example.com/flaky.png';
        // Phase 6 routes member writes through the real DriftMemberRepository
        // (avatar normalize decodes the bytes). Use a real JPEG so the round
        // trip preserves the buffer.
        final fakeBytes = _jpegBytes(9, 8, 7);

        final db = _makeDb();
        addTearDown(db.close);

        final client = _FakeHttpClient()
          ..stubUrl(avatarUrl, http.Response('temporary miss', 404));
        const data = SpExportData(
          members: [SpMember(id: 'sp-a', name: 'Alice', avatarUrl: avatarUrl)],
          customFronts: [],
          frontHistory: [],
          groups: [],
          channels: [],
          messages: [],
          polls: [],
        );

        // Phase 6 batches member inserts through `db.membersDao` directly;
        // use the real Drift repo so the retry path observes the inserted
        // member via the shared DB.
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final importer = SpImporter(httpClient: client);

        final initial = await importer.executeImport(
          db: db,
          data: data,
          memberRepo: memberRepo,
          sessionRepo: _FakeSessionRepository(),
          conversationRepo: _FakeConversationRepository(),
          messageRepo: _FakeChatMessageRepository(),
          pollRepo: _FakePollRepository(),
          spImportDao: db.spImportDao,
          downloadAvatars: true,
        );
        expect(initial.avatarsDownloaded, 0);
        expect(initial.hasAvatarDownloadFailures, isTrue);

        final imported = (await memberRepo.getAllMembers()).single;
        await memberRepo.updateMember(imported.copyWith(name: 'Edited Alice'));

        client.stubUrl(
          avatarUrl,
          http.Response.bytes(
            fakeBytes,
            200,
            headers: {'content-type': 'image/png'},
          ),
        );

        final retry = await importer.retryAvatarDownloads(
          data: data,
          memberRepo: memberRepo,
          spImportDao: db.spImportDao,
        );

        final updated = (await memberRepo.getAllMembers()).single;
        expect(retry.avatarsDownloaded, 1);
        expect(retry.warnings, isEmpty);
        expect(updated.name, 'Edited Alice');
        expect(updated.avatarImageData, fakeBytes);
      },
    );

    test(
      'retryAvatarDownloads reports total mapped members with avatars',
      () async {
        const avatarUrlA = 'https://example.com/a.png';
        const avatarUrlB = 'https://example.com/b.png';
        // Phase 6 — see comment in earlier avatar test. Use real JPEGs so
        // normalize doesn't truncate the round-trip.
        final bytesA = _jpegBytes(1, 1, 1);
        final bytesB = _jpegBytes(2, 2, 2);

        final db = _makeDb();
        addTearDown(db.close);

        final client = _FakeHttpClient()
          ..stubUrl(
            avatarUrlA,
            http.Response.bytes(
              bytesA,
              200,
              headers: {'content-type': 'image/png'},
            ),
          )
          ..stubUrl(avatarUrlB, http.Response('temporary miss', 404));
        const data = SpExportData(
          members: [
            SpMember(id: 'sp-a', name: 'Alice', avatarUrl: avatarUrlA),
            SpMember(id: 'sp-b', name: 'Bob', avatarUrl: avatarUrlB),
          ],
          customFronts: [],
          frontHistory: [],
          groups: [],
          channels: [],
          messages: [],
          polls: [],
        );

        // Phase 6 batches member inserts through `db.membersDao` directly;
        // use the real Drift repo so the retry path observes inserted members.
        final memberRepo = DriftMemberRepository(db.membersDao, null);
        final importer = SpImporter(httpClient: client);

        final initial = await importer.executeImport(
          db: db,
          data: data,
          memberRepo: memberRepo,
          sessionRepo: _FakeSessionRepository(),
          conversationRepo: _FakeConversationRepository(),
          messageRepo: _FakeChatMessageRepository(),
          pollRepo: _FakePollRepository(),
          spImportDao: db.spImportDao,
          downloadAvatars: true,
        );
        expect(initial.avatarsDownloaded, 1);

        client
          ..stubUrl(avatarUrlA, http.Response('temporary miss', 404))
          ..stubUrl(
            avatarUrlB,
            http.Response.bytes(
              bytesB,
              200,
              headers: {'content-type': 'image/png'},
            ),
          );

        final retry = await importer.retryAvatarDownloads(
          data: data,
          memberRepo: memberRepo,
          spImportDao: db.spImportDao,
        );

        final members = await memberRepo.getAllMembers();
        expect(retry.avatarsDownloaded, 2);
        expect(
          members.where((member) => member.avatarImageData != null),
          hasLength(2),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Progress callback
  // ---------------------------------------------------------------------------

  group('progress callback', () {
    test(
      'fires labels in sequence and progress is monotonically non-decreasing',
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
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Transaction rollback
  // ---------------------------------------------------------------------------

  group('transaction rollback', () {
    test('exception mid-import rolls back all inserts', () async {
      final db = _makeDb();
      addTearDown(db.close);

      // Phase 6 batches every per-row write away from the repositories, so
      // the old `_FakeChatMessageRepository.throwOnCreate` fault never
      // fires. Inject the failure on `memberRepo.getAllMembers()` instead —
      // it's the first transactional call the importer makes (pre-resolve
      // existing-member detection) and survives every later batching pass.
      final memberRepoBase = DriftMemberRepository(db.membersDao, null);
      final memberRepo = _ThrowingMemberRepository(memberRepoBase);
      final sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final conversationRepo = DriftConversationRepository(
        db.conversationsDao,
        null,
      );
      final pollRepo = DriftPollRepository(
        db.pollsDao,
        db.pollOptionsDao,
        db.pollVotesDao,
        null,
      );

      final messageRepo = _FakeChatMessageRepository();

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

      Object? caught;
      try {
        await SpImporter(httpClient: _FakeHttpClient()).executeImport(
          db: db,
          data: data,
          memberRepo: memberRepo,
          sessionRepo: sessionRepo,
          conversationRepo: conversationRepo,
          messageRepo: messageRepo,
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

    test(
      'clearExistingData + failure → pre-existing data is preserved (rollback includes wipe)',
      () async {
        final db = _makeDb();
        addTearDown(db.close);

        final memberRepoBase = DriftMemberRepository(db.membersDao, null);
        final sessionRepo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final conversationRepo = DriftConversationRepository(
          db.conversationsDao,
          null,
        );
        final pollRepo = DriftPollRepository(
          db.pollsDao,
          db.pollOptionsDao,
          db.pollVotesDao,
          null,
        );

        // Seed one existing member via the real repo.
        await memberRepoBase.createMember(
          domain.Member(
            id: 'existing-1',
            name: 'Existing',
            createdAt: DateTime(2025, 1, 1),
          ),
        );

        // Verify it's there before import.
        final beforeImport = await db.membersDao.getAllMembers();
        expect(beforeImport.length, 1);

        // Wrap the member repo so its first `getAllMembers()` call inside
        // the import transaction throws — Phase 6 makes this the durable
        // failure-injection point. See the comment on the test above.
        final memberRepo = _ThrowingMemberRepository(memberRepoBase);
        final messageRepo = _FakeChatMessageRepository();

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
            messageRepo: messageRepo,
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
      },
    );
  });

  // ---------------------------------------------------------------------------
  // System color routing (regression)
  // ---------------------------------------------------------------------------
  //
  // Regression: SP's `color` field on the user/system record must route to
  // `updateSystemColor(...)` — it must NOT overwrite `accentColorHex`, which
  // is Prism's separately-configured app accent color.
  group('system color routing', () {
    test(
      'SP color field routes to updateSystemColor without touching accentColorHex',
      () async {
        const seededAccent = '#123456';
        final settingsRepo = FakeSystemSettingsRepository()
          ..settings = const SystemSettings(accentColorHex: seededAccent);

        const data = SpExportData(
          members: [],
          customFronts: [],
          frontHistory: [],
          groups: [],
          channels: [],
          messages: [],
          polls: [],
          systemColor: 'ff0000',
          systemName: 'Test System',
        );

        final repos = _makeFakeRepos();
        final importer = SpImporter(httpClient: _FakeHttpClient());

        await importer.executeImport(
          db: _makeDb(),
          data: data,
          memberRepo: repos.memberRepo,
          sessionRepo: repos.sessionRepo,
          conversationRepo: repos.conversationRepo,
          messageRepo: repos.messageRepo,
          pollRepo: repos.pollRepo,
          settingsRepo: settingsRepo,
          downloadAvatars: false,
        );

        expect(settingsRepo.settings.systemColor, 'ff0000');
        expect(
          settingsRepo.settings.accentColorHex,
          seededAccent,
          reason: 'SP system color must not overwrite the app accent color',
        );
      },
    );
  });
}
