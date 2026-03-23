import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart' show AppDatabase, PluralKitSyncStateCompanion;
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/domain/repositories/sleep_session_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/data_management/models/v3_export_models.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';

/// Preview of what an import file contains, without actually importing.
class ImportPreview {
  const ImportPreview({
    this.headmates = 0,
    this.frontSessions = 0,
    this.sleepSessions = 0,
    this.conversations = 0,
    this.messages = 0,
    this.polls = 0,
    this.pollOptions = 0,
    this.systemSettings = 0,
    this.habits = 0,
    this.habitCompletions = 0,
    this.formatVersion = '',
    this.exportDate = '',
  });

  final int headmates;
  final int frontSessions;
  final int sleepSessions;
  final int conversations;
  final int messages;
  final int polls;
  final int pollOptions;
  final int systemSettings;
  final int habits;
  final int habitCompletions;
  final String formatVersion;
  final String exportDate;

  int get totalRecords =>
      headmates +
      frontSessions +
      sleepSessions +
      conversations +
      messages +
      polls +
      pollOptions +
      systemSettings +
      habits +
      habitCompletions;
}

/// Result of a completed import operation.
class ImportResult {
  ImportResult({
    this.membersCreated = 0,
    this.frontSessionsCreated = 0,
    this.sleepSessionsCreated = 0,
    this.conversationsCreated = 0,
    this.messagesCreated = 0,
    this.pollsCreated = 0,
    this.pollOptionsCreated = 0,
    this.settingsUpdated = false,
    this.habitsCreated = 0,
    this.habitCompletionsCreated = 0,
  });

  final int membersCreated;
  final int frontSessionsCreated;
  final int sleepSessionsCreated;
  final int conversationsCreated;
  final int messagesCreated;
  final int pollsCreated;
  final int pollOptionsCreated;
  final bool settingsUpdated;
  final int habitsCreated;
  final int habitCompletionsCreated;

  int get totalRecordsCreated =>
      membersCreated +
      frontSessionsCreated +
      sleepSessionsCreated +
      conversationsCreated +
      messagesCreated +
      pollsCreated +
      pollOptionsCreated +
      (settingsUpdated ? 1 : 0) +
      habitsCreated +
      habitCompletionsCreated;
}

class DataImportService {
  DataImportService({
    required this.db,
    required this.memberRepository,
    required this.frontingSessionRepository,
    required this.conversationRepository,
    required this.chatMessageRepository,
    required this.pollRepository,
    required this.sleepSessionRepository,
    required this.systemSettingsRepository,
    required this.habitRepository,
    required this.pluralKitSyncDao,
  });

  final AppDatabase db;
  final MemberRepository memberRepository;
  final FrontingSessionRepository frontingSessionRepository;
  final ConversationRepository conversationRepository;
  final ChatMessageRepository chatMessageRepository;
  final PollRepository pollRepository;
  final SleepSessionRepository sleepSessionRepository;
  final SystemSettingsRepository systemSettingsRepository;
  final HabitRepository habitRepository;
  final PluralKitSyncDao pluralKitSyncDao;

  /// Resolve raw file bytes to a JSON string.
  ///
  /// If the bytes start with the `PRISM1` magic header, [password] is used to
  /// decrypt. Otherwise the bytes are treated as plain-text UTF-8 JSON.
  static String resolveBytes(Uint8List bytes, {String? password}) {
    if (ExportCrypto.isEncrypted(bytes)) {
      if (password == null || password.isEmpty) {
        throw const FormatException(
          'This file is encrypted. Please provide a password.',
        );
      }
      return ExportCrypto.decrypt(bytes, password);
    }
    return utf8.decode(bytes);
  }

  /// Recognized format versions that this service can import.
  static const supportedVersions = ['2025.1'];

  /// Parse a JSON string and return a preview without importing.
  ///
  /// Throws [FormatException] if the format version is unrecognized.
  ImportPreview parsePreview(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final export = V3Export.fromJson(map);

    if (!supportedVersions.contains(export.formatVersion)) {
      throw FormatException(
        'Unsupported export format version: ${export.formatVersion}. '
        'Supported versions: ${supportedVersions.join(', ')}',
      );
    }

    return ImportPreview(
      headmates: export.headmates.length,
      frontSessions: export.frontSessions.length,
      sleepSessions: export.sleepSessions.length,
      conversations: export.conversations.length,
      messages: export.messages.length,
      polls: export.polls.length,
      pollOptions: export.pollOptions.length,
      systemSettings: export.systemSettings.length,
      habits: export.habits.length,
      habitCompletions: export.habitCompletions.length,
      formatVersion: export.formatVersion,
      exportDate: export.exportDate,
    );
  }

  /// Import data from a JSON string.
  ///
  /// The entire import runs inside a single database transaction. If any
  /// entity fails to insert the transaction is rolled back automatically and
  /// the exception propagates to the caller — the database is left unchanged.
  Future<ImportResult> importData(String json) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final export = V3Export.fromJson(map);

    if (!supportedVersions.contains(export.formatVersion)) {
      throw FormatException(
        'Unsupported export format version: ${export.formatVersion}. '
        'Supported versions: ${supportedVersions.join(', ')}',
      );
    }

    return db.transaction(() async {
      // 1. Import members (first pass: create)
      var membersCreated = 0;
      final existingMembers = await memberRepository.getAllMembers();
      final existingMemberIds = existingMembers.map((m) => m.id).toSet();

      for (final h in export.headmates) {
        if (existingMemberIds.contains(h.id)) continue;
        await memberRepository.createMember(
          Member(
            id: h.id,
            name: h.name,
            pronouns: h.pronouns,
            emoji: h.emoji ?? '\u2754',
            age: h.age,
            bio: h.notes,
            avatarImageData: h.avatarImageData,
            isActive: h.isActive,
            createdAt: DateTime.parse(h.createdAt),
            displayOrder: h.displayOrder,
            isAdmin: h.isAdmin,
            customColorEnabled: h.customColorEnabled,
            customColorHex: h.customColorHex,
            pluralkitUuid: h.pluralkitUuid,
            pluralkitId: h.pluralkitId,
          ),
        );
        membersCreated++;
      }

      // Second pass: set parentSystemId for members
      for (final h in export.headmates) {
        if (h.parentSystemId == null) continue;
        final member = await memberRepository.getMemberById(h.id);
        if (member != null && member.parentSystemId != h.parentSystemId) {
          await memberRepository.updateMember(
            member.copyWith(parentSystemId: h.parentSystemId),
          );
        }
      }

      // 2. Import fronting sessions
      var frontSessionsCreated = 0;
      final existingSessions = await frontingSessionRepository.getAllSessions();
      final existingSessionIds = existingSessions.map((s) => s.id).toSet();

      for (final s in export.frontSessions) {
        if (existingSessionIds.contains(s.id)) continue;
        await frontingSessionRepository.createSession(
          FrontingSession(
            id: s.id,
            startTime: DateTime.parse(s.startTime),
            endTime: s.endTime != null ? DateTime.parse(s.endTime!) : null,
            memberId: s.headmateId,
            coFronterIds: s.coFronterIds,
            notes: s.notes,
            confidence: s.confidence != null &&
                    s.confidence! >= 0 &&
                    s.confidence! < FrontConfidence.values.length
                ? FrontConfidence.values[s.confidence!]
                : null,
            pluralkitUuid: s.pluralkitUuid,
          ),
        );
        frontSessionsCreated++;
      }

      // 3. Import sleep sessions
      var sleepSessionsCreated = 0;
      final existingSleep = await sleepSessionRepository.getRecentSleepSessions(
        limit: 999999,
      );
      final existingSleepIds = existingSleep.map((s) => s.id).toSet();

      for (final s in export.sleepSessions) {
        if (existingSleepIds.contains(s.id)) continue;
        await sleepSessionRepository.createSleepSession(
          SleepSession(
            id: s.id,
            startTime: DateTime.parse(s.startTime),
            endTime: s.endTime != null ? DateTime.parse(s.endTime!) : null,
            quality: s.quality >= 0 && s.quality < SleepQuality.values.length
                ? SleepQuality.values[s.quality]
                : SleepQuality.unknown,
            notes: s.notes,
            isHealthKitImport: s.isHealthKitImport,
          ),
        );
        sleepSessionsCreated++;
      }

      // 4. Import conversations
      var conversationsCreated = 0;
      final existingConvs = await conversationRepository.getAllConversations();
      final existingConvIds = existingConvs.map((c) => c.id).toSet();

      for (final c in export.conversations) {
        if (existingConvIds.contains(c.id)) continue;
        // Rebuild lastReadTimestamps from String:String map
        final timestamps = c.lastReadTimestamps.map(
          (k, v) => MapEntry(k, DateTime.parse(v)),
        );

        await conversationRepository.createConversation(
          Conversation(
            id: c.id,
            createdAt: DateTime.parse(c.createdAt),
            lastActivityAt: DateTime.parse(c.lastActivityAt),
            title: c.title,
            emoji: c.emoji,
            isDirectMessage: c.isDirectMessage,
            creatorId: c.creatorId,
            participantIds: c.participantIds,
            archivedByMemberIds: c.archivedByMemberIds != null
                ? (jsonDecode(c.archivedByMemberIds!) as List).cast<String>()
                : [],
            mutedByMemberIds: c.mutedByMemberIds != null
                ? (jsonDecode(c.mutedByMemberIds!) as List).cast<String>()
                : [],
            lastReadTimestamps: timestamps,
          ),
        );
        conversationsCreated++;
      }

      // 5. Import messages
      var messagesCreated = 0;
      for (final m in export.messages) {
        final existing = await chatMessageRepository.getMessageById(m.id);
        if (existing != null) continue;

        await chatMessageRepository.createMessage(
          ChatMessage(
            id: m.id,
            content: m.content,
            timestamp: DateTime.parse(m.timestamp),
            isSystemMessage: m.isSystemMessage,
            editedAt: m.editedAt != null ? DateTime.parse(m.editedAt!) : null,
            authorId: m.authorId,
            conversationId: m.conversationId,
            reactions: m.reactions
                .map(
                  (r) => MessageReaction(
                    id: r.id,
                    emoji: r.emoji,
                    memberId: r.memberId,
                    timestamp: DateTime.parse(r.timestamp),
                  ),
                )
                .toList(),
          ),
        );
        messagesCreated++;
      }

      // 6. Import polls + options + votes
      var pollsCreated = 0;
      var pollOptionsCreated = 0;
      final existingPolls = await pollRepository.getAllPolls();
      final existingPollIds = existingPolls.map((p) => p.id).toSet();

      for (final p in export.polls) {
        if (existingPollIds.contains(p.id)) continue;
        await pollRepository.createPoll(
          Poll(
            id: p.id,
            question: p.question,
            isAnonymous: p.isAnonymous,
            allowsMultipleVotes: p.allowsMultipleVotes,
            isClosed: p.isClosed,
            expiresAt: p.expiresAt != null
                ? DateTime.parse(p.expiresAt!)
                : null,
            createdAt: DateTime.parse(p.createdAt),
          ),
        );
        pollsCreated++;
      }

      for (final o in export.pollOptions) {
        final existingOptions = await pollRepository.getOptionsForPoll(
          o.pollId,
        );
        if (existingOptions.any((existing) => existing.id == o.id)) continue;

        await pollRepository.createOption(
          PollOption(
            id: o.id,
            text: o.text,
            sortOrder: o.sortOrder,
            isOtherOption: o.isOtherOption,
          ),
          o.pollId,
        );
        pollOptionsCreated++;

        // Import votes for this option
        for (final v in o.votes) {
          await pollRepository.castVote(
            PollVote(
              id: v.id,
              memberId: v.memberId,
              votedAt: DateTime.parse(v.votedAt),
              responseText: v.responseText,
            ),
            o.id,
          );
        }
      }

      // 7. Import system settings
      var settingsUpdated = false;
      if (export.systemSettings.isNotEmpty) {
        final s = export.systemSettings.first;
        await systemSettingsRepository.updateSettings(
          SystemSettings(
            systemName: s.systemName,
            showQuickFront: s.showQuickFront,
            accentColorHex: s.accentColorHex,
            perMemberAccentColors: s.perMemberAccentColors,
            terminology: SystemTerminology.values[s.terminology],
            customTerminology: s.customTerminology,
            customPluralTerminology: s.customPluralTerminology,
            frontingRemindersEnabled: s.frontingRemindersEnabled,
            frontingReminderIntervalMinutes: s.frontingReminderIntervalMinutes,
            themeMode: AppThemeMode.values[s.themeMode],
            themeBrightness: ThemeBrightness.values[s.themeBrightness],
            themeStyle: ThemeStyle.values[s.themeStyle],
            chatEnabled: s.chatEnabled,
            pollsEnabled: s.pollsEnabled,
            habitsEnabled: s.habitsEnabled,
            sleepTrackingEnabled: s.sleepTrackingEnabled,
            quickSwitchThresholdSeconds: s.quickSwitchThresholdSeconds,
            chatLogsFront: s.chatLogsFront,
            hasCompletedOnboarding: s.hasCompletedOnboarding,
            syncThemeEnabled: s.syncThemeEnabled,
            timingMode:
                FrontingTimingMode.values[s.timingMode ?? 0],
          ),
        );
        settingsUpdated = true;
      }

      // 8. Import habits
      var habitsCreated = 0;
      final existingHabits = await habitRepository.getAllHabits();
      final existingHabitIds = existingHabits.map((h) => h.id).toSet();

      for (final h in export.habits) {
        if (existingHabitIds.contains(h.id)) continue;
        await habitRepository.createHabit(
          Habit(
            id: h.id,
            name: h.name,
            description: h.description,
            icon: h.icon,
            colorHex: h.colorHex,
            isActive: h.isActive,
            createdAt: DateTime.parse(h.createdAt),
            modifiedAt: DateTime.parse(h.modifiedAt),
            frequency: HabitFrequency.values.firstWhere(
              (f) => f.name == h.frequency,
              orElse: () => HabitFrequency.daily,
            ),
            weeklyDays: h.weeklyDays != null
                ? (jsonDecode(h.weeklyDays!) as List).cast<int>()
                : null,
            intervalDays: h.intervalDays,
            reminderTime: h.reminderTime,
            notificationsEnabled: h.notificationsEnabled,
            notificationMessage: h.notificationMessage,
            assignedMemberId: h.assignedMemberId,
            onlyNotifyWhenFronting: h.onlyNotifyWhenFronting,
            isPrivate: h.isPrivate,
            currentStreak: h.currentStreak,
            bestStreak: h.bestStreak,
            totalCompletions: h.totalCompletions,
          ),
        );
        habitsCreated++;
      }

      // 9. Import habit completions
      var habitCompletionsCreated = 0;
      for (final c in export.habitCompletions) {
        final existingCompletions = await habitRepository.getCompletionsForHabit(
          c.habitId,
        );
        if (existingCompletions.any((existing) => existing.id == c.id)) {
          continue;
        }

        await habitRepository.createCompletion(
          HabitCompletion(
            id: c.id,
            habitId: c.habitId,
            completedAt: DateTime.parse(c.completedAt),
            completedByMemberId: c.completedByMemberId,
            notes: c.notes,
            wasFronting: c.wasFronting,
            rating: c.rating,
            createdAt: DateTime.parse(c.createdAt),
            modifiedAt: DateTime.parse(c.modifiedAt),
          ),
        );
        habitCompletionsCreated++;
      }

      // 10. Import PluralKit sync state
      if (export.pluralKitSyncState != null) {
        final pk = export.pluralKitSyncState!;
        await pluralKitSyncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            systemId: Value(pk.systemId),
            isConnected: Value(pk.isConnected),
            lastSyncDate: Value(
              pk.lastSyncDate != null
                  ? DateTime.parse(pk.lastSyncDate!)
                  : null,
            ),
            lastManualSyncDate: Value(
              pk.lastManualSyncDate != null
                  ? DateTime.parse(pk.lastManualSyncDate!)
                  : null,
            ),
          ),
        );
      }

      return ImportResult(
        membersCreated: membersCreated,
        frontSessionsCreated: frontSessionsCreated,
        sleepSessionsCreated: sleepSessionsCreated,
        conversationsCreated: conversationsCreated,
        messagesCreated: messagesCreated,
        pollsCreated: pollsCreated,
        pollOptionsCreated: pollOptionsCreated,
        settingsUpdated: settingsUpdated,
        habitsCreated: habitsCreated,
        habitCompletionsCreated: habitCompletionsCreated,
      );
    });
  }
}
