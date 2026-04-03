import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

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

class DataExportService {
  DataExportService({
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
    Future<Directory> Function()? cacheDirectoryProvider,
  }) : _cacheDirectoryProvider =
           cacheDirectoryProvider ?? getApplicationCacheDirectory;

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
  final Future<Directory> Function() _cacheDirectoryProvider;

  /// Build the [V3Export] model from the current database state.
  ///
  /// This is separated from file I/O so it can be used in tests without
  /// requiring a platform channel (path_provider).
  Future<V3Export> buildExport() async {
    // Fetch all data
    final members = await memberRepository.getAllMembers();
    final frontSessions = await frontingSessionRepository.getFrontingSessions();
    final sleepSessions = await frontingSessionRepository
        .getRecentSleepSessions(limit: 999999);
    final conversations = await conversationRepository.getAllConversations();
    final polls = await pollRepository.getAllPolls();
    final settings = await systemSettingsRepository.getSettings();

    // Fetch all messages in a single query
    final allMessages = await chatMessageRepository.getAllMessages();

    // Batch-fetch all options and votes, then group in memory for O(1) lookup
    final optionsByPoll = await pollRepository.getAllOptionsGroupedByPoll();
    final votesByOption = await pollRepository.getAllVotesGroupedByOption();

    final allOptions = <V3PollOption>[];
    for (final MapEntry(key: pollId, value: options) in optionsByPoll.entries) {
      for (final option in options) {
        final votes = votesByOption[option.id] ?? [];
        allOptions.add(_mapPollOption(option, pollId, votes));
      }
    }

    // Convert to V3 models
    final v3Headmates = members.map(_mapMember).toList();
    final v3Sessions = frontSessions.map(_mapFrontSession).toList();
    final v3SleepSessions = sleepSessions.map(_mapSleepSession).toList();
    final v3Conversations = conversations.map(_mapConversation).toList();
    final v3Messages = allMessages.map(_mapMessage).toList();
    final v3Polls = polls.map(_mapPoll).toList();
    final v3Settings = [_mapSettings(settings)];

    // Fetch habits and all completions in single queries
    final habits = await habitRepository.getAllHabits();
    final allCompletions = await habitRepository.getAllCompletions();

    final v3Habits = habits.map(_mapHabit).toList();
    final v3HabitCompletions = allCompletions.map(_mapHabitCompletion).toList();

    // Fetch member groups and entries
    final memberGroups = await memberGroupsRepository.watchAllGroups().first;
    final allGroupEntries = <MemberGroupEntry>[];
    for (final group in memberGroups) {
      final entries = await memberGroupsRepository
          .watchGroupEntries(group.id)
          .first;
      allGroupEntries.addAll(entries);
    }
    final v3MemberGroups = memberGroups.map(_mapMemberGroup).toList();
    final v3MemberGroupEntries = allGroupEntries
        .map(_mapMemberGroupEntry)
        .toList();

    // Fetch custom fields and values
    final customFields = await customFieldsRepository.watchAllFields().first;
    final allFieldValues = await customFieldsRepository.getAllValues();
    final v3CustomFields = customFields.map(_mapCustomField).toList();
    final v3CustomFieldValues = allFieldValues
        .map(_mapCustomFieldValue)
        .toList();

    // Fetch notes
    final allNotes = await notesRepository.watchAllNotes().first;
    final v3Notes = allNotes.map(_mapNote).toList();

    // Fetch front session comments
    final allComments = <FrontSessionComment>[];
    for (final session in frontSessions) {
      final comments = await frontSessionCommentsRepository
          .watchCommentsForSession(session.id)
          .first;
      allComments.addAll(comments);
    }
    final v3FrontSessionComments = allComments
        .map(_mapFrontSessionComment)
        .toList();

    // Fetch conversation categories
    final categories = await conversationCategoriesRepository.watchAll().first;
    final v3ConversationCategories = categories
        .map(_mapConversationCategory)
        .toList();

    // Fetch reminders
    final reminders = await remindersRepository.watchAll().first;
    final v3Reminders = reminders.map(_mapReminder).toList();

    // Fetch friends
    final friends = await friendsRepository.watchAll().first;
    final v3Friends = friends.map(_mapFriend).toList();

    // Fetch PluralKit sync state
    final pkState = await pluralKitSyncDao.getSyncState();
    final v3PkSyncState = V3PluralKitSyncState(
      systemId: pkState.systemId,
      isConnected: pkState.isConnected,
      lastSyncDate: pkState.lastSyncDate?.toUtc().toIso8601String(),
      lastManualSyncDate: pkState.lastManualSyncDate?.toUtc().toIso8601String(),
    );

    final totalRecords =
        v3Headmates.length +
        v3Sessions.length +
        v3SleepSessions.length +
        v3Conversations.length +
        v3Messages.length +
        v3Polls.length +
        allOptions.length +
        v3Settings.length +
        v3Habits.length +
        v3HabitCompletions.length +
        v3MemberGroups.length +
        v3MemberGroupEntries.length +
        v3CustomFields.length +
        v3CustomFieldValues.length +
        v3Notes.length +
        v3FrontSessionComments.length +
        v3ConversationCategories.length +
        v3Reminders.length +
        v3Friends.length;

    return V3Export(
      formatVersion: '2025.1',
      version: '3.0',
      appName: 'Prism Plurality',
      exportDate: DateTime.now().toUtc().toIso8601String(),
      totalRecords: totalRecords,
      headmates: v3Headmates,
      frontSessions: v3Sessions,
      sleepSessions: v3SleepSessions,
      conversations: v3Conversations,
      messages: v3Messages,
      polls: v3Polls,
      pollOptions: allOptions,
      systemSettings: v3Settings,
      habits: v3Habits,
      habitCompletions: v3HabitCompletions,
      pluralKitSyncState: v3PkSyncState,
      memberGroups: v3MemberGroups,
      memberGroupEntries: v3MemberGroupEntries,
      customFields: v3CustomFields,
      customFieldValues: v3CustomFieldValues,
      notes: v3Notes,
      frontSessionComments: v3FrontSessionComments,
      conversationCategories: v3ConversationCategories,
      reminders: v3Reminders,
      friends: v3Friends,
    );
  }

  /// Export all data as an encrypted `.prism` file.
  Future<File> exportEncryptedData({required String password}) async {
    final export = await buildExport();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(export.toJson());
    return _writeExportFile(jsonStr, password: password, extension: 'prism');
  }

  /// Export all data as a plaintext `.json` file.
  ///
  /// This is an explicit insecure path for compatibility and manual sharing.
  Future<File> exportPlaintextData() async {
    final export = await buildExport();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(export.toJson());
    return _writeExportFile(jsonStr, extension: 'json');
  }

  Future<File> _writeExportFile(
    String jsonStr, {
    String? password,
    required String extension,
  }) async {
    final cacheDir = await _cacheDirectoryProvider();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${cacheDir.path}/Prism-Export-$dateStr.$extension');

    if (password != null) {
      final encrypted = ExportCrypto.encrypt(jsonStr, password);
      await file.writeAsBytes(encrypted);
      return file;
    }

    await file.writeAsString(jsonStr);
    return file;
  }

  // -- Mapping helpers -------------------------------------------------------

  V3Headmate _mapMember(Member m) => V3Headmate(
    id: m.id,
    name: m.name,
    pronouns: m.pronouns,
    emoji: m.emoji,
    age: m.age,
    notes: m.bio,
    profilePhotoData: m.avatarImageData != null
        ? base64Encode(m.avatarImageData!)
        : null,
    isActive: m.isActive,
    createdAt: m.createdAt.toUtc().toIso8601String(),
    displayOrder: m.displayOrder,
    isAdmin: m.isAdmin,
    customColorEnabled: m.customColorEnabled,
    customColorHex: m.customColorHex,
    parentSystemId: m.parentSystemId,
    pluralkitUuid: m.pluralkitUuid,
    pluralkitId: m.pluralkitId,
    markdownEnabled: m.markdownEnabled,
  );

  V3FrontSession _mapFrontSession(FrontingSession s) => V3FrontSession(
    id: s.id,
    startTime: s.startTime.toUtc().toIso8601String(),
    endTime: s.endTime?.toUtc().toIso8601String(),
    headmateId: s.memberId,
    coFronterIds: s.coFronterIds,
    notes: s.notes,
    confidence: s.confidence?.index,
    pluralkitUuid: s.pluralkitUuid,
  );

  V3SleepSession _mapSleepSession(FrontingSession s) => V3SleepSession(
    id: s.id,
    startTime: s.startTime.toUtc().toIso8601String(),
    endTime: s.endTime?.toUtc().toIso8601String(),
    quality: s.quality?.index ?? 0,
    notes: s.notes,
    isHealthKitImport: s.isHealthKitImport,
  );

  V3Conversation _mapConversation(Conversation c) => V3Conversation(
    id: c.id,
    createdAt: c.createdAt.toUtc().toIso8601String(),
    lastActivityAt: c.lastActivityAt.toUtc().toIso8601String(),
    title: c.title,
    emoji: c.emoji,
    isDirectMessage: c.isDirectMessage,
    creatorId: c.creatorId,
    participantIds: c.participantIds,
    lastReadTimestamps: c.lastReadTimestamps.map(
      (k, v) => MapEntry(k, v.toUtc().toIso8601String()),
    ),
    archivedByMemberIds: c.archivedByMemberIds.isNotEmpty
        ? jsonEncode(c.archivedByMemberIds)
        : null,
    mutedByMemberIds: c.mutedByMemberIds.isNotEmpty
        ? jsonEncode(c.mutedByMemberIds)
        : null,
    description: c.description,
    categoryId: c.categoryId,
    displayOrder: c.displayOrder,
  );

  V3Message _mapMessage(ChatMessage m) => V3Message(
    id: m.id,
    content: m.content,
    timestamp: m.timestamp.toUtc().toIso8601String(),
    isSystemMessage: m.isSystemMessage,
    editedAt: m.editedAt?.toUtc().toIso8601String(),
    authorId: m.authorId,
    conversationId: m.conversationId,
    reactions: m.reactions
        .map(
          (r) => V3MessageReaction(
            id: r.id,
            emoji: r.emoji,
            memberId: r.memberId,
            timestamp: r.timestamp.toUtc().toIso8601String(),
          ),
        )
        .toList(),
    replyToId: m.replyToId,
    replyToAuthorId: m.replyToAuthorId,
    replyToContent: m.replyToContent,
  );

  V3Poll _mapPoll(Poll p) => V3Poll(
    id: p.id,
    question: p.question,
    description: p.description,
    isAnonymous: p.isAnonymous,
    allowsMultipleVotes: p.allowsMultipleVotes,
    isClosed: p.isClosed,
    expiresAt: p.expiresAt?.toUtc().toIso8601String(),
    createdAt: p.createdAt.toUtc().toIso8601String(),
  );

  V3PollOption _mapPollOption(
    PollOption o,
    String pollId,
    List<PollVote> votes,
  ) => V3PollOption(
    id: o.id,
    pollId: pollId,
    text: o.text,
    sortOrder: o.sortOrder,
    isOtherOption: o.isOtherOption,
    colorHex: o.colorHex,
    votes: votes
        .map(
          (v) => V3PollVote(
            id: v.id,
            memberId: v.memberId,
            votedAt: v.votedAt.toUtc().toIso8601String(),
            responseText: v.responseText,
          ),
        )
        .toList(),
  );

  V3SystemSettings _mapSettings(SystemSettings s) => V3SystemSettings(
    systemName: s.systemName,
    showQuickFront: s.showQuickFront,
    accentColorHex: s.accentColorHex,
    perMemberAccentColors: s.perMemberAccentColors,
    terminology: s.terminology.index,
    customTerminology: s.customTerminology,
    customPluralTerminology: s.customPluralTerminology,
    frontingRemindersEnabled: s.frontingRemindersEnabled,
    frontingReminderIntervalMinutes: s.frontingReminderIntervalMinutes,
    themeMode: s.themeMode.index,
    themeBrightness: s.themeBrightness.index,
    themeStyle: s.themeStyle.index,
    chatEnabled: s.chatEnabled,
    pollsEnabled: s.pollsEnabled,
    habitsEnabled: s.habitsEnabled,
    sleepTrackingEnabled: s.sleepTrackingEnabled,
    quickSwitchThresholdSeconds: s.quickSwitchThresholdSeconds,
    chatLogsFront: s.chatLogsFront,
    hasCompletedOnboarding: s.hasCompletedOnboarding,
    syncThemeEnabled: s.syncThemeEnabled,
    timingMode: s.timingMode.index,
    habitsBadgeEnabled: s.habitsBadgeEnabled,
    notesEnabled: s.notesEnabled,
    previousAccentColorHex: s.previousAccentColorHex,
    systemDescription: s.systemDescription,
    systemAvatarData: s.systemAvatarData != null
        ? base64Encode(s.systemAvatarData!)
        : null,
    remindersEnabled: s.remindersEnabled,
    fontScale: s.fontScale,
    fontFamily: s.fontFamily.index,
    pinLockEnabled: s.pinLockEnabled,
    biometricLockEnabled: s.biometricLockEnabled,
    autoLockDelaySeconds: s.autoLockDelaySeconds,
    navBarItems: s.navBarItems,
    navBarOverflowItems: s.navBarOverflowItems,
    syncNavigationEnabled: s.syncNavigationEnabled,
    chatBadgePreferences: s.chatBadgePreferences,
  );

  V3Habit _mapHabit(Habit h) => V3Habit(
    id: h.id,
    name: h.name,
    description: h.description,
    icon: h.icon,
    colorHex: h.colorHex,
    isActive: h.isActive,
    createdAt: h.createdAt.toUtc().toIso8601String(),
    modifiedAt: h.modifiedAt.toUtc().toIso8601String(),
    frequency: h.frequency.name,
    weeklyDays: h.weeklyDays != null ? jsonEncode(h.weeklyDays) : null,
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
  );

  V3HabitCompletion _mapHabitCompletion(HabitCompletion c) => V3HabitCompletion(
    id: c.id,
    habitId: c.habitId,
    completedAt: c.completedAt.toUtc().toIso8601String(),
    completedByMemberId: c.completedByMemberId,
    notes: c.notes,
    wasFronting: c.wasFronting,
    rating: c.rating,
    createdAt: c.createdAt.toUtc().toIso8601String(),
    modifiedAt: c.modifiedAt.toUtc().toIso8601String(),
  );

  V3MemberGroup _mapMemberGroup(MemberGroup g) => V3MemberGroup(
    id: g.id,
    name: g.name,
    description: g.description,
    colorHex: g.colorHex,
    emoji: g.emoji,
    displayOrder: g.displayOrder,
    parentGroupId: g.parentGroupId,
    createdAt: g.createdAt.toUtc().toIso8601String(),
  );

  V3MemberGroupEntry _mapMemberGroupEntry(MemberGroupEntry e) =>
      V3MemberGroupEntry(id: e.id, groupId: e.groupId, memberId: e.memberId);

  V3CustomField _mapCustomField(CustomField f) => V3CustomField(
    id: f.id,
    name: f.name,
    fieldType: f.fieldType.index,
    datePrecision: f.datePrecision?.index,
    displayOrder: f.displayOrder,
    createdAt: f.createdAt.toUtc().toIso8601String(),
  );

  V3CustomFieldValue _mapCustomFieldValue(CustomFieldValue v) =>
      V3CustomFieldValue(
        id: v.id,
        customFieldId: v.customFieldId,
        memberId: v.memberId,
        value: v.value,
      );

  V3Note _mapNote(Note n) => V3Note(
    id: n.id,
    title: n.title,
    body: n.body,
    colorHex: n.colorHex,
    memberId: n.memberId,
    date: n.date.toUtc().toIso8601String(),
    createdAt: n.createdAt.toUtc().toIso8601String(),
    modifiedAt: n.modifiedAt.toUtc().toIso8601String(),
  );

  V3FrontSessionComment _mapFrontSessionComment(FrontSessionComment c) =>
      V3FrontSessionComment(
        id: c.id,
        sessionId: c.sessionId,
        body: c.body,
        timestamp: c.timestamp.toUtc().toIso8601String(),
        createdAt: c.createdAt.toUtc().toIso8601String(),
      );

  V3ConversationCategory _mapConversationCategory(ConversationCategory c) =>
      V3ConversationCategory(
        id: c.id,
        name: c.name,
        displayOrder: c.displayOrder,
        createdAt: c.createdAt.toUtc().toIso8601String(),
        modifiedAt: c.modifiedAt.toUtc().toIso8601String(),
      );

  V3Reminder _mapReminder(Reminder r) => V3Reminder(
    id: r.id,
    name: r.name,
    message: r.message,
    trigger: r.trigger.index,
    intervalDays: r.intervalDays,
    timeOfDay: r.timeOfDay,
    delayHours: r.delayHours,
    isActive: r.isActive,
    createdAt: r.createdAt.toUtc().toIso8601String(),
    modifiedAt: r.modifiedAt.toUtc().toIso8601String(),
  );

  V3Friend _mapFriend(FriendRecord f) => V3Friend(
    id: f.id,
    displayName: f.displayName,
    publicKeyHex: f.publicKeyHex,
    // Exclude sharedSecretHex from export — cryptographic secret should not
    // appear in plaintext backup files. Friends must re-verify after restore.
    sharedSecretHex: null,
    grantedScopes: f.grantedScopes,
    isVerified: f.isVerified,
    createdAt: f.createdAt.toUtc().toIso8601String(),
    lastSyncAt: f.lastSyncAt?.toUtc().toIso8601String(),
  );
}
