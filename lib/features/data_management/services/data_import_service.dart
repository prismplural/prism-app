import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase, PluralKitSyncStateCompanion;
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/domain/repositories/chat_message_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_repository.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/poll_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/repositories/conversation_categories_repository.dart';
import 'package:prism_plurality/domain/repositories/reminders_repository.dart';
import 'package:prism_plurality/domain/repositories/friends_repository.dart';
import 'package:prism_plurality/features/data_management/models/v3_export_models.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

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
    this.memberGroups = 0,
    this.memberGroupEntries = 0,
    this.customFields = 0,
    this.customFieldValues = 0,
    this.notes = 0,
    this.frontSessionComments = 0,
    this.conversationCategories = 0,
    this.reminders = 0,
    this.friends = 0,
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
  final int memberGroups;
  final int memberGroupEntries;
  final int customFields;
  final int customFieldValues;
  final int notes;
  final int frontSessionComments;
  final int conversationCategories;
  final int reminders;
  final int friends;
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
      habitCompletions +
      memberGroups +
      memberGroupEntries +
      customFields +
      customFieldValues +
      notes +
      frontSessionComments +
      conversationCategories +
      reminders +
      friends;
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
    this.memberGroupsCreated = 0,
    this.memberGroupEntriesCreated = 0,
    this.customFieldsCreated = 0,
    this.customFieldValuesCreated = 0,
    this.notesCreated = 0,
    this.frontSessionCommentsCreated = 0,
    this.conversationCategoriesCreated = 0,
    this.remindersCreated = 0,
    this.friendsCreated = 0,
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
  final int memberGroupsCreated;
  final int memberGroupEntriesCreated;
  final int customFieldsCreated;
  final int customFieldValuesCreated;
  final int notesCreated;
  final int frontSessionCommentsCreated;
  final int conversationCategoriesCreated;
  final int remindersCreated;
  final int friendsCreated;

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
      habitCompletionsCreated +
      memberGroupsCreated +
      memberGroupEntriesCreated +
      customFieldsCreated +
      customFieldValuesCreated +
      notesCreated +
      frontSessionCommentsCreated +
      conversationCategoriesCreated +
      remindersCreated +
      friendsCreated;
}

class DataImportService {
  DataImportService({
    required this.db,
    required this.memberRepository,
    required this.frontingSessionRepository,
    required this.conversationRepository,
    required this.chatMessageRepository,
    required this.pollRepository,
    required this.systemSettingsRepository,
    required this.habitRepository,
    required this.pluralKitSyncDao,
    required this.memberGroupsRepository,
    required this.customFieldsRepository,
    required this.notesRepository,
    required this.frontSessionCommentsRepository,
    required this.conversationCategoriesRepository,
    required this.remindersRepository,
    required this.friendsRepository,
  });

  final AppDatabase db;
  final MemberRepository memberRepository;
  final FrontingSessionRepository frontingSessionRepository;
  final ConversationRepository conversationRepository;
  final ChatMessageRepository chatMessageRepository;
  final PollRepository pollRepository;
  final SystemSettingsRepository systemSettingsRepository;
  final HabitRepository habitRepository;
  final PluralKitSyncDao pluralKitSyncDao;
  final MemberGroupsRepository memberGroupsRepository;
  final CustomFieldsRepository customFieldsRepository;
  final NotesRepository notesRepository;
  final FrontSessionCommentsRepository frontSessionCommentsRepository;
  final ConversationCategoriesRepository conversationCategoriesRepository;
  final RemindersRepository remindersRepository;
  final FriendsRepository friendsRepository;

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
      memberGroups: export.memberGroups.length,
      memberGroupEntries: export.memberGroupEntries.length,
      customFields: export.customFields.length,
      customFieldValues: export.customFieldValues.length,
      notes: export.notes.length,
      frontSessionComments: export.frontSessionComments.length,
      conversationCategories: export.conversationCategories.length,
      reminders: export.reminders.length,
      friends: export.friends.length,
      formatVersion: export.formatVersion,
      exportDate: export.exportDate,
    );
  }

  /// Import data from a JSON string.
  ///
  /// The entire import runs inside a single database transaction. If any
  /// entity fails to insert the transaction is rolled back automatically and
  /// the exception propagates to the caller — the database is left unchanged.
  Future<ImportResult> importData(
    String json, {
    bool preserveImportedOnboardingState = true,
  }) async {
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
            markdownEnabled: h.markdownEnabled,
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
            sessionType: SessionType.normal,
            confidence:
                s.confidence != null &&
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
      final existingSleep = existingSessions.where((s) => s.isSleep).toList();
      final existingSleepIds = existingSleep.map((s) => s.id).toSet();

      for (final s in export.sleepSessions) {
        if (existingSleepIds.contains(s.id)) continue;
        await frontingSessionRepository.createSession(
          FrontingSession(
            id: s.id,
            startTime: DateTime.parse(s.startTime),
            endTime: s.endTime != null ? DateTime.parse(s.endTime!) : null,
            sessionType: SessionType.sleep,
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
            description: c.description,
            categoryId: c.categoryId,
            displayOrder: c.displayOrder,
          ),
        );
        conversationsCreated++;
      }

      // 5. Import messages
      var messagesCreated = 0;
      // Preload existing message IDs to avoid per-record queries
      final allExistingMsgs = await chatMessageRepository.getAllMessages();
      final existingMessageIds = allExistingMsgs.map((m) => m.id).toSet();
      for (final m in export.messages) {
        if (existingMessageIds.contains(m.id)) continue;

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
            replyToId: m.replyToId,
            replyToAuthorId: m.replyToAuthorId,
            replyToContent: m.replyToContent,
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
            description: p.description,
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

      // Batch-load all existing poll option IDs in one query.
      final allOptions = await pollRepository.getAllOptions();
      final existingOptionIds = <String>{
        for (final opt in allOptions) opt.id,
      };
      for (final o in export.pollOptions) {
        if (existingOptionIds.contains(o.id)) continue;

        await pollRepository.createOption(
          PollOption(
            id: o.id,
            text: o.text,
            sortOrder: o.sortOrder,
            isOtherOption: o.isOtherOption,
            colorHex: o.colorHex,
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
            sharingId: s.sharingId,
            showQuickFront: s.showQuickFront,
            accentColorHex: s.accentColorHex,
            perMemberAccentColors: s.perMemberAccentColors,
            terminology:
                s.terminology >= 0 &&
                    s.terminology < SystemTerminology.values.length
                ? SystemTerminology.values[s.terminology]
                : SystemTerminology.headmates,
            customTerminology: s.customTerminology,
            customPluralTerminology: s.customPluralTerminology,
            terminologyUseEnglish: s.terminologyUseEnglish,
            frontingRemindersEnabled: s.frontingRemindersEnabled,
            frontingReminderIntervalMinutes: s.frontingReminderIntervalMinutes,
            themeMode:
                s.themeMode >= 0 && s.themeMode < AppThemeMode.values.length
                ? AppThemeMode.values[s.themeMode]
                : AppThemeMode.system,
            themeBrightness:
                s.themeBrightness >= 0 &&
                    s.themeBrightness < ThemeBrightness.values.length
                ? ThemeBrightness.values[s.themeBrightness]
                : ThemeBrightness.system,
            themeStyle:
                s.themeStyle >= 0 && s.themeStyle < ThemeStyle.values.length
                ? ThemeStyle.values[s.themeStyle]
                : ThemeStyle.standard,
            chatEnabled: s.chatEnabled,
            pollsEnabled: s.pollsEnabled,
            habitsEnabled: s.habitsEnabled,
            sleepTrackingEnabled: s.sleepTrackingEnabled,
            quickSwitchThresholdSeconds: s.quickSwitchThresholdSeconds,
            identityGeneration: s.identityGeneration,
            chatLogsFront: s.chatLogsFront,
            hasCompletedOnboarding: preserveImportedOnboardingState
                ? s.hasCompletedOnboarding
                : false,
            syncThemeEnabled: s.syncThemeEnabled,
            timingMode:
                (s.timingMode ?? 0) >= 0 &&
                    (s.timingMode ?? 0) < FrontingTimingMode.values.length
                ? FrontingTimingMode.values[s.timingMode ?? 0]
                : FrontingTimingMode.flexible,
            habitsBadgeEnabled: s.habitsBadgeEnabled,
            notesEnabled: s.notesEnabled,
            previousAccentColorHex: s.previousAccentColorHex,
            systemDescription: s.systemDescription,
            systemAvatarData: s.systemAvatarData != null
                ? base64Decode(s.systemAvatarData!)
                : null,
            remindersEnabled: s.remindersEnabled,
            fontScale: s.fontScale,
            fontFamily:
                s.fontFamily >= 0 && s.fontFamily < FontFamily.values.length
                ? FontFamily.values[s.fontFamily]
                : FontFamily.system,
            // Force device-local security settings to false on import —
            // PIN/biometric lock must be configured through the settings UI
            // where the user actually sets a PIN on this device.
            pinLockEnabled: false,
            biometricLockEnabled: false,
            autoLockDelaySeconds: s.autoLockDelaySeconds,
            navBarItems: s.navBarItems,
            navBarOverflowItems: s.navBarOverflowItems,
            syncNavigationEnabled: s.syncNavigationEnabled,
            chatBadgePreferences: s.chatBadgePreferences,
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
      // Batch-load all existing completion IDs in one query.
      final allCompletions = await habitRepository.getAllCompletions();
      final existingCompletionIds = <String>{
        for (final c in allCompletions) c.id,
      };
      for (final c in export.habitCompletions) {
        if (existingCompletionIds.contains(c.id)) continue;

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
        final current = await pluralKitSyncDao.getSyncState();
        final existingId = current.systemId;
        if (existingId != null && pk.systemId != null && existingId != pk.systemId) {
          // Backup is from a different PluralKit system — skip to avoid overwriting
          // the current system's connection state with a foreign system ID.
          debugPrint(
            '[Import] Skipped PluralKit sync state: '
            'backup systemId (${pk.systemId}) != current ($existingId)',
          );
        } else {
          await pluralKitSyncDao.upsertSyncState(
            PluralKitSyncStateCompanion(
              id: const Value('pk_config'),
              systemId: Value(pk.systemId),
              isConnected: Value(pk.isConnected),
              lastSyncDate: Value(
                pk.lastSyncDate != null ? DateTime.parse(pk.lastSyncDate!) : null,
              ),
              lastManualSyncDate: Value(
                pk.lastManualSyncDate != null
                    ? DateTime.parse(pk.lastManualSyncDate!)
                    : null,
              ),
            ),
          );
        }
      }

      // 11. Import member groups
      var memberGroupsCreated = 0;
      final existingGroups = await memberGroupsRepository
          .watchAllGroups()
          .first;
      final existingGroupIds = existingGroups.map((g) => g.id).toSet();

      for (final g in export.memberGroups) {
        if (existingGroupIds.contains(g.id)) continue;
        await memberGroupsRepository.createGroup(
          MemberGroup(
            id: g.id,
            name: g.name,
            description: g.description,
            colorHex: g.colorHex,
            emoji: g.emoji,
            displayOrder: g.displayOrder,
            parentGroupId: g.parentGroupId,
            createdAt: DateTime.parse(g.createdAt),
          ),
        );
        memberGroupsCreated++;
      }

      // 12. Import member group entries
      var memberGroupEntriesCreated = 0;
      final existingEntries = await memberGroupsRepository.getAllGroupEntries();
      final existingEntryIds = existingEntries.map((e) => e.id).toSet();
      for (final e in export.memberGroupEntries) {
        if (existingEntryIds.contains(e.id)) continue;
        await memberGroupsRepository.addMemberToGroup(
          e.groupId,
          e.memberId,
          e.id,
        );
        memberGroupEntriesCreated++;
      }

      // 13. Import custom fields
      var customFieldsCreated = 0;
      final existingFields = await customFieldsRepository
          .watchAllFields()
          .first;
      final existingFieldIds = existingFields.map((f) => f.id).toSet();

      for (final f in export.customFields) {
        if (existingFieldIds.contains(f.id)) continue;
        await customFieldsRepository.createField(
          CustomField(
            id: f.id,
            name: f.name,
            fieldType:
                f.fieldType >= 0 && f.fieldType < CustomFieldType.values.length
                ? CustomFieldType.values[f.fieldType]
                : CustomFieldType.text,
            datePrecision:
                f.datePrecision != null &&
                    f.datePrecision! >= 0 &&
                    f.datePrecision! < DatePrecision.values.length
                ? DatePrecision.values[f.datePrecision!]
                : null,
            displayOrder: f.displayOrder,
            createdAt: DateTime.parse(f.createdAt),
          ),
        );
        customFieldsCreated++;
      }

      // 14. Import custom field values
      var customFieldValuesCreated = 0;
      final existingValues = await customFieldsRepository.getAllValues();
      final existingValueKeys =
          existingValues.map((v) => '${v.customFieldId}:${v.memberId}').toSet();
      for (final v in export.customFieldValues) {
        if (existingValueKeys.contains('${v.customFieldId}:${v.memberId}')) {
          continue;
        }
        await customFieldsRepository.upsertValue(
          CustomFieldValue(
            id: v.id,
            customFieldId: v.customFieldId,
            memberId: v.memberId,
            value: v.value,
          ),
        );
        customFieldValuesCreated++;
      }

      // 15. Import notes
      var notesCreated = 0;
      final existingNotes = await notesRepository.watchAllNotes().first;
      final existingNoteIds = existingNotes.map((n) => n.id).toSet();

      for (final n in export.notes) {
        if (existingNoteIds.contains(n.id)) continue;
        await notesRepository.createNote(
          Note(
            id: n.id,
            title: n.title,
            body: n.body,
            colorHex: n.colorHex,
            memberId: n.memberId,
            date: DateTime.parse(n.date),
            createdAt: DateTime.parse(n.createdAt),
            modifiedAt: DateTime.parse(n.modifiedAt),
          ),
        );
        notesCreated++;
      }

      // 16. Import front session comments
      var frontSessionCommentsCreated = 0;
      final existingComments =
          await frontSessionCommentsRepository.getAllComments();
      final existingCommentIds =
          existingComments.map((c) => c.id).toSet();
      for (final c in export.frontSessionComments) {
        if (existingCommentIds.contains(c.id)) continue;
        await frontSessionCommentsRepository.createComment(
          FrontSessionComment(
            id: c.id,
            sessionId: c.sessionId,
            body: c.body,
            timestamp: DateTime.parse(c.timestamp),
            createdAt: DateTime.parse(c.createdAt),
          ),
        );
        frontSessionCommentsCreated++;
      }

      // 17. Import conversation categories
      var conversationCategoriesCreated = 0;
      final existingCategories = await conversationCategoriesRepository
          .watchAll()
          .first;
      final existingCategoryIds = existingCategories.map((c) => c.id).toSet();

      for (final c in export.conversationCategories) {
        if (existingCategoryIds.contains(c.id)) continue;
        await conversationCategoriesRepository.create(
          ConversationCategory(
            id: c.id,
            name: c.name,
            displayOrder: c.displayOrder,
            createdAt: DateTime.parse(c.createdAt),
            modifiedAt: DateTime.parse(c.modifiedAt),
          ),
        );
        conversationCategoriesCreated++;
      }

      // 18. Import reminders
      var remindersCreated = 0;
      final existingReminders = await remindersRepository.watchAll().first;
      final existingReminderIds = existingReminders.map((r) => r.id).toSet();

      for (final r in export.reminders) {
        if (existingReminderIds.contains(r.id)) continue;
        await remindersRepository.create(
          Reminder(
            id: r.id,
            name: r.name,
            message: r.message,
            trigger: r.trigger >= 0 && r.trigger < ReminderTrigger.values.length
                ? ReminderTrigger.values[r.trigger]
                : ReminderTrigger.scheduled,
            intervalDays: r.intervalDays,
            timeOfDay: r.timeOfDay,
            delayHours: r.delayHours,
            isActive: r.isActive,
            createdAt: DateTime.parse(r.createdAt),
            modifiedAt: DateTime.parse(r.modifiedAt),
          ),
        );
        remindersCreated++;
      }

      // 19. Import friends
      var friendsCreated = 0;
      final existingFriends = await friendsRepository.watchAll().first;
      final existingFriendIds = existingFriends.map((f) => f.id).toSet();

      for (final f in export.friends) {
        if (existingFriendIds.contains(f.id)) continue;
        await friendsRepository.createFriend(
          FriendRecord(
            id: f.id,
            displayName: f.displayName,
            peerSharingId: f.peerSharingId,
            offeredScopes: f.offeredScopes,
            publicKeyHex: f.publicKeyHex,
            // Export intentionally omits sharedSecretHex to avoid plaintext
            // secrets in backups. Re-pairing is required after restore.
            sharedSecretHex: null,
            grantedScopes: f.grantedScopes,
            isVerified: f.isVerified,
            initId: f.initId,
            createdAt: DateTime.parse(f.createdAt),
            establishedAt: f.establishedAt != null
                ? DateTime.parse(f.establishedAt!)
                : null,
            lastSyncAt: f.lastSyncAt != null
                ? DateTime.parse(f.lastSyncAt!)
                : null,
          ),
        );
        friendsCreated++;
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
        memberGroupsCreated: memberGroupsCreated,
        memberGroupEntriesCreated: memberGroupEntriesCreated,
        customFieldsCreated: customFieldsCreated,
        customFieldValuesCreated: customFieldValuesCreated,
        notesCreated: notesCreated,
        frontSessionCommentsCreated: frontSessionCommentsCreated,
        conversationCategoriesCreated: conversationCategoriesCreated,
        remindersCreated: remindersCreated,
        friendsCreated: friendsCreated,
      );
    });
  }
}
