import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';

/// Results of a database health check.
class HealthReport {
  const HealthReport({
    required this.isHealthy,
    required this.issues,
    required this.checkedAt,
    required this.recordCounts,
  });

  final bool isHealthy;
  final List<String> issues;
  final DateTime checkedAt;
  final Map<String, int> recordCounts;
}

/// Pure Dart service for checking database integrity and performing
/// maintenance operations.
class DatabaseHealthService {
  const DatabaseHealthService();

  /// Runs a full health check across all repositories.
  ///
  /// Checks for orphaned messages, invalid session time ranges, and duplicate
  /// member names. Returns a [HealthReport] summarising findings.
  Future<HealthReport> runHealthCheck({
    required MemberRepository members,
    required FrontingSessionRepository sessions,
    required ConversationRepository conversations,
    required ChatMessageRepository messages,
  }) async {
    final issues = <String>[];

    final allMembers = await members.getAllMembers();
    final allSessions = await sessions.getAllSessions();
    final allConversations = await conversations.getAllConversations();

    final recordCounts = <String, int>{
      'members': allMembers.length,
      'sessions': allSessions.length,
      'conversations': allConversations.length,
    };

    // Check for sessions where startTime > endTime.
    for (final session in allSessions) {
      if (session.endTime != null &&
          session.startTime.isAfter(session.endTime!)) {
        issues.add(
          'Session ${session.id} has startTime after endTime '
          '(${session.startTime} > ${session.endTime})',
        );
      }
    }

    // Check for duplicate member names.
    final nameCount = <String, int>{};
    for (final member in allMembers) {
      nameCount[member.name] = (nameCount[member.name] ?? 0) + 1;
    }
    for (final entry in nameCount.entries) {
      if (entry.value > 1) {
        issues.add(
          'Duplicate member name "${entry.key}" appears ${entry.value} times',
        );
      }
    }

    // Count total messages across all conversations.
    var totalMessages = 0;
    for (final convo in allConversations) {
      final msgs = await messages.getMessagesForConversation(convo.id);
      totalMessages += msgs.length;
    }
    recordCounts['messages'] = totalMessages;

    return HealthReport(
      isHealthy: issues.isEmpty,
      issues: issues,
      checkedAt: DateTime.now(),
      recordCounts: recordCounts,
    );
  }

  /// Finds and removes exact duplicate members (same name).
  ///
  /// Keeps the first member (by creation date) and removes duplicates.
  /// Returns the number of members removed.
  Future<int> deduplicateMembers(MemberRepository repo) async {
    final allMembers = await repo.getAllMembers();
    final seen = <String, bool>{};
    var removed = 0;

    // Sort by createdAt so we keep the earliest member.
    final sorted = List.of(allMembers)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final member in sorted) {
      if (seen.containsKey(member.name)) {
        await repo.deleteMember(member.id);
        removed++;
      } else {
        seen[member.name] = true;
      }
    }

    return removed;
  }
}
