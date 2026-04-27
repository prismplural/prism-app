import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
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
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

class DataExportService {
  DataExportService({
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
    required this.mediaAttachmentsDao,
    Future<Directory> Function()? cacheDirectoryProvider,
    Future<Directory> Function()? appSupportDirectoryProvider,
  }) : _cacheDirectoryProvider =
           cacheDirectoryProvider ?? getApplicationCacheDirectory,
       _appSupportDirectoryProvider =
           appSupportDirectoryProvider ?? getApplicationSupportDirectory;

  /// Drift handle. Required so the PRISM1 migration-time export can read
  /// `co_fronter_ids`, `pk_member_ids_json`, and the `session_id` column
  /// directly (the post-Phase-2 freezed models no longer expose those
  /// fields). The provider chain wires this from `databaseProvider` so the
  /// production export path always has it; without it the legacy-fields
  /// flag silently drops the rescue inputs.
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
  final MediaAttachmentsDao mediaAttachmentsDao;
  final Future<Directory> Function() _cacheDirectoryProvider;
  final Future<Directory> Function() _appSupportDirectoryProvider;

  /// Build the [V1Export] model from the current database state.
  ///
  /// This is separated from file I/O so it can be used in tests without
  /// requiring a platform channel (path_provider).
  ///
  /// When [includeLegacyFields] is true, the export emits BOTH new-shape
  /// fields and the v7-era legacy columns (`co_fronter_ids`,
  /// `pk_member_ids_json` on fronting sessions; `session_id` on comments)
  /// so the resulting PRISM1 file is self-sufficient as a rescue input
  /// (see §4.7 of the per-member fronting refactor plan). The legacy
  /// columns are read straight from Drift since they are no longer on the
  /// freezed domain models.
  ///
  /// Default behavior (post-migration exports) emits only the new shape.
  Future<V1Export> buildExport({bool includeLegacyFields = false}) async {
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

    // Batch-fetch all options and votes, then group in memory for O(1) lookup.
    // Only include options belonging to exported (non-deleted) polls.
    final optionsByPoll = await pollRepository.getAllOptionsGroupedByPoll();
    final votesByOption = await pollRepository.getAllVotesGroupedByOption();
    final exportedPollIds = polls.map((p) => p.id).toSet();

    final allOptions = <V1PollOption>[];
    for (final MapEntry(key: pollId, value: options) in optionsByPoll.entries) {
      if (!exportedPollIds.contains(pollId)) continue;
      for (final option in options) {
        final votes = votesByOption[option.id] ?? [];
        allOptions.add(_mapPollOption(option, pollId, votes));
      }
    }

    // Optional legacy-field lookups (only loaded when requested). Reads
    // the v7 Drift columns directly because the new-shape freezed models
    // no longer expose `co_fronter_ids` / `pk_member_ids_json` on
    // FrontingSession or `session_id` on FrontSessionComment.
    final legacySessionFields = includeLegacyFields
        ? await _fetchLegacySessionFields(db)
        : const <String, _LegacySessionFields>{};
    final legacyCommentSessionIds = includeLegacyFields
        ? await _fetchLegacyCommentSessionIds(db)
        : const <String, String>{};

    // Convert to V3 models
    final v1Headmates = members.map(_mapMember).toList();
    final v1Sessions = frontSessions
        .map((s) => _mapFrontSession(s, legacySessionFields[s.id]))
        .toList();
    final v1SleepSessions = sleepSessions.map(_mapSleepSession).toList();
    final v1Conversations = conversations.map(_mapConversation).toList();
    final v1Messages = allMessages.map(_mapMessage).toList();
    final v1Polls = polls.map(_mapPoll).toList();
    final v1Settings = [_mapSettings(settings)];

    // Fetch habits and all completions in single queries
    final habits = await habitRepository.getAllHabits();
    final allCompletions = await habitRepository.getAllCompletions();

    final v1Habits = habits.map(_mapHabit).toList();
    final v1HabitCompletions = allCompletions.map(_mapHabitCompletion).toList();

    // Fetch member groups and entries
    final memberGroups = await memberGroupsRepository.watchAllGroups().first;
    final allGroupEntries = await memberGroupsRepository.getAllGroupEntries();
    final v1MemberGroups = memberGroups.map(_mapMemberGroup).toList();
    final v1MemberGroupEntries = allGroupEntries
        .map(_mapMemberGroupEntry)
        .toList();

    // Fetch custom fields and values
    final customFields = await customFieldsRepository.watchAllFields().first;
    final allFieldValues = await customFieldsRepository.getAllValues();
    final v1CustomFields = customFields.map(_mapCustomField).toList();
    final v1CustomFieldValues = allFieldValues
        .map(_mapCustomFieldValue)
        .toList();

    // Fetch notes
    final allNotes = await notesRepository.watchAllNotes().first;
    final v1Notes = allNotes.map(_mapNote).toList();

    // Fetch front session comments
    final allComments = await frontSessionCommentsRepository.getAllComments();
    final v1FrontSessionComments = allComments
        .map(
          (c) => _mapFrontSessionComment(c, legacyCommentSessionIds[c.id]),
        )
        .toList();

    // Fetch conversation categories
    final categories = await conversationCategoriesRepository.watchAll().first;
    final v1ConversationCategories = categories
        .map(_mapConversationCategory)
        .toList();

    // Fetch reminders
    final reminders = await remindersRepository.watchAll().first;
    final v1Reminders = reminders.map(_mapReminder).toList();

    // Fetch friends
    final friends = await friendsRepository.watchAll().first;
    final v1Friends = friends.map(_mapFriend).toList();

    // Fetch media attachments
    final allMediaAttachments = await mediaAttachmentsDao.getAll();
    final v1MediaAttachments = allMediaAttachments
        .map(
          (a) => V1MediaAttachment(
            id: a.id,
            messageId: a.messageId,
            mediaId: a.mediaId,
            mediaType: a.mediaType,
            encryptionKeyB64: a.encryptionKeyB64,
            contentHash: a.contentHash,
            plaintextHash: a.plaintextHash,
            mimeType: a.mimeType,
            sizeBytes: a.sizeBytes,
            width: a.width,
            height: a.height,
            durationMs: a.durationMs,
            blurhash: a.blurhash,
            waveformB64: a.waveformB64,
            thumbnailMediaId: a.thumbnailMediaId,
            isDeleted: a.isDeleted,
          ),
        )
        .toList();

    // Fetch PluralKit sync state
    final pkState = await pluralKitSyncDao.getSyncState();
    final v1PkSyncState = V1PluralKitSyncState(
      systemId: pkState.systemId,
      isConnected: pkState.isConnected,
      lastSyncDate: pkState.lastSyncDate?.toUtc().toIso8601String(),
      lastManualSyncDate: pkState.lastManualSyncDate?.toUtc().toIso8601String(),
    );

    final totalRecords =
        v1Headmates.length +
        v1Sessions.length +
        v1SleepSessions.length +
        v1Conversations.length +
        v1Messages.length +
        v1Polls.length +
        allOptions.length +
        v1Settings.length +
        v1Habits.length +
        v1HabitCompletions.length +
        v1MemberGroups.length +
        v1MemberGroupEntries.length +
        v1CustomFields.length +
        v1CustomFieldValues.length +
        v1Notes.length +
        v1FrontSessionComments.length +
        v1ConversationCategories.length +
        v1Reminders.length +
        v1Friends.length +
        v1MediaAttachments.length;

    return V1Export(
      formatVersion: '1.0',
      version: '1.0',
      appName: 'Prism Plurality',
      exportDate: DateTime.now().toUtc().toIso8601String(),
      totalRecords: totalRecords,
      headmates: v1Headmates,
      frontSessions: v1Sessions,
      sleepSessions: v1SleepSessions,
      conversations: v1Conversations,
      messages: v1Messages,
      polls: v1Polls,
      pollOptions: allOptions,
      systemSettings: v1Settings,
      habits: v1Habits,
      habitCompletions: v1HabitCompletions,
      pluralKitSyncState: v1PkSyncState,
      memberGroups: v1MemberGroups,
      memberGroupEntries: v1MemberGroupEntries,
      customFields: v1CustomFields,
      customFieldValues: v1CustomFieldValues,
      notes: v1Notes,
      frontSessionComments: v1FrontSessionComments,
      conversationCategories: v1ConversationCategories,
      reminders: v1Reminders,
      friends: v1Friends,
      mediaAttachments: v1MediaAttachments,
    );
  }

  /// Export all data as an encrypted `.prism` file (PRISM3 format).
  ///
  /// Media blobs are read from the local encrypted cache and carried verbatim
  /// alongside the JSON. If a blob is not cached locally it is silently skipped.
  ///
  /// See [buildExport] for the meaning of [includeLegacyFields].
  Future<File> exportEncryptedData({
    required String password,
    bool includeLegacyFields = false,
  }) async {
    final export = await buildExport(includeLegacyFields: includeLegacyFields);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(export.toJson());

    final mediaBlobs = await _collectMediaBlobs(export.mediaAttachments);

    final cacheDir = await _cacheDirectoryProvider();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${cacheDir.path}/Prism-Export-$dateStr.prism');
    final encrypted = await Isolate.run(
      () => ExportCrypto.encrypt(jsonStr, mediaBlobs, password),
    );
    await file.writeAsBytes(encrypted);
    return file;
  }

  /// Reads encrypted blobs for [attachments] from the local media cache.
  ///
  /// Returns one entry per cached blob. Both main and thumbnail blobs are
  /// included (they share the same encryption key). Missing files are skipped.
  Future<List<({String mediaId, Uint8List blob})>> _collectMediaBlobs(
    List<V1MediaAttachment> attachments,
  ) async {
    final appSupport = await _appSupportDirectoryProvider();
    final mediaDir = Directory('${appSupport.path}/prism_media');
    final blobs = <({String mediaId, Uint8List blob})>[];

    for (final attachment in attachments) {
      for (final mediaId in [attachment.mediaId, attachment.thumbnailMediaId]) {
        if (mediaId.isEmpty) continue;
        final file = File('${mediaDir.path}/$mediaId.enc');
        if (file.existsSync()) {
          blobs.add((mediaId: mediaId, blob: file.readAsBytesSync()));
        }
      }
    }
    return blobs;
  }

  // -- Mapping helpers -------------------------------------------------------

  V1Headmate _mapMember(Member m) => V1Headmate(
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
    displayName: m.displayName,
    birthday: m.birthday,
    proxyTagsJson: m.proxyTagsJson,
    pluralkitSyncIgnored: m.pluralkitSyncIgnored,
  );

  V1FrontSession _mapFrontSession(
    FrontingSession s, [
    _LegacySessionFields? legacy,
  ]) => V1FrontSession(
    id: s.id,
    startTime: s.startTime.toUtc().toIso8601String(),
    endTime: s.endTime?.toUtc().toIso8601String(),
    headmateId: s.memberId,
    // Legacy column reads — only populated when `includeLegacyFields = true`
    // was passed and Drift was queried directly. New-shape exports leave
    // these empty so the v8-era importer doesn't see legacy markers and
    // mistakenly route through the rescue branch (DataImportService treats
    // any populated `coFronterIds` / `pkMemberIdsJson` as a legacy marker).
    coFronterIds: legacy?.coFronterIds ?? const [],
    pkMemberIdsJson: legacy?.pkMemberIdsJson,
    notes: s.notes,
    confidence: s.confidence?.index,
    pluralkitUuid: s.pluralkitUuid,
    sessionType: s.sessionType.index,
    quality: s.quality?.index,
    isHealthKitImport: s.isHealthKitImport,
  );

  V1SleepSession _mapSleepSession(FrontingSession s) => V1SleepSession(
    id: s.id,
    startTime: s.startTime.toUtc().toIso8601String(),
    endTime: s.endTime?.toUtc().toIso8601String(),
    quality: s.quality?.index ?? 0,
    notes: s.notes,
    isHealthKitImport: s.isHealthKitImport,
  );

  V1Conversation _mapConversation(Conversation c) => V1Conversation(
    id: c.id,
    createdAt: c.createdAt.toUtc().toIso8601String(),
    lastActivityAt: c.lastActivityAt.toUtc().toIso8601String(),
    title: c.title,
    emoji: c.emoji,
    isDirectMessage: isV1ConversationDirectMessage(
      isDirectMessage: c.isDirectMessage,
      title: c.title,
      emoji: c.emoji,
      categoryId: c.categoryId,
      participantIds: c.participantIds,
    ),
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

  V1Message _mapMessage(ChatMessage m) => V1Message(
    id: m.id,
    content: m.content,
    timestamp: m.timestamp.toUtc().toIso8601String(),
    isSystemMessage: m.isSystemMessage,
    editedAt: m.editedAt?.toUtc().toIso8601String(),
    authorId: m.authorId,
    conversationId: m.conversationId,
    reactions: m.reactions
        .map(
          (r) => V1MessageReaction(
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

  V1Poll _mapPoll(Poll p) => V1Poll(
    id: p.id,
    question: p.question,
    description: p.description,
    isAnonymous: p.isAnonymous,
    allowsMultipleVotes: p.allowsMultipleVotes,
    isClosed: p.isClosed,
    expiresAt: p.expiresAt?.toUtc().toIso8601String(),
    createdAt: p.createdAt.toUtc().toIso8601String(),
  );

  V1PollOption _mapPollOption(
    PollOption o,
    String pollId,
    List<PollVote> votes,
  ) => V1PollOption(
    id: o.id,
    pollId: pollId,
    text: o.text,
    sortOrder: o.sortOrder,
    isOtherOption: o.isOtherOption,
    colorHex: o.colorHex,
    votes: votes
        .map(
          (v) => V1PollVote(
            id: v.id,
            memberId: v.memberId,
            votedAt: v.votedAt.toUtc().toIso8601String(),
            responseText: v.responseText,
          ),
        )
        .toList(),
  );

  V1SystemSettings _mapSettings(SystemSettings s) => V1SystemSettings(
    systemName: s.systemName,
    sharingId: s.sharingId,
    showQuickFront: s.showQuickFront,
    accentColorHex: s.accentColorHex,
    perMemberAccentColors: s.perMemberAccentColors,
    terminology: s.terminology.index,
    customTerminology: s.customTerminology,
    customPluralTerminology: s.customPluralTerminology,
    terminologyUseEnglish: s.terminologyUseEnglish,
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
    identityGeneration: s.identityGeneration,
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

  V1Habit _mapHabit(Habit h) => V1Habit(
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

  V1HabitCompletion _mapHabitCompletion(HabitCompletion c) => V1HabitCompletion(
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

  V1MemberGroup _mapMemberGroup(MemberGroup g) => V1MemberGroup(
    id: g.id,
    name: g.name,
    description: g.description,
    colorHex: g.colorHex,
    emoji: g.emoji,
    displayOrder: g.displayOrder,
    parentGroupId: g.parentGroupId,
    createdAt: g.createdAt.toUtc().toIso8601String(),
  );

  V1MemberGroupEntry _mapMemberGroupEntry(MemberGroupEntry e) =>
      V1MemberGroupEntry(id: e.id, groupId: e.groupId, memberId: e.memberId);

  V1CustomField _mapCustomField(CustomField f) => V1CustomField(
    id: f.id,
    name: f.name,
    fieldType: f.fieldType.index,
    datePrecision: f.datePrecision?.index,
    displayOrder: f.displayOrder,
    createdAt: f.createdAt.toUtc().toIso8601String(),
  );

  V1CustomFieldValue _mapCustomFieldValue(CustomFieldValue v) =>
      V1CustomFieldValue(
        id: v.id,
        customFieldId: v.customFieldId,
        memberId: v.memberId,
        value: v.value,
      );

  V1Note _mapNote(Note n) => V1Note(
    id: n.id,
    title: n.title,
    body: n.body,
    colorHex: n.colorHex,
    memberId: n.memberId,
    date: n.date.toUtc().toIso8601String(),
    createdAt: n.createdAt.toUtc().toIso8601String(),
    modifiedAt: n.modifiedAt.toUtc().toIso8601String(),
  );

  V1FrontSessionComment _mapFrontSessionComment(
    FrontSessionComment c, [
    String? legacySessionId,
  ]) =>
      V1FrontSessionComment(
        id: c.id,
        // Only emitted in legacy-fields mode — new-shape exports anchor
        // comments via `targetTime`, not a session FK. The v7 column is
        // still present in Drift but unread by the new code paths.
        sessionId: legacySessionId,
        body: c.body,
        timestamp: c.timestamp.toUtc().toIso8601String(),
        createdAt: c.createdAt.toUtc().toIso8601String(),
        targetTime: c.targetTime?.toUtc().toIso8601String(),
        authorMemberId: c.authorMemberId,
      );

  V1ConversationCategory _mapConversationCategory(ConversationCategory c) =>
      V1ConversationCategory(
        id: c.id,
        name: c.name,
        displayOrder: c.displayOrder,
        createdAt: c.createdAt.toUtc().toIso8601String(),
        modifiedAt: c.modifiedAt.toUtc().toIso8601String(),
      );

  V1Reminder _mapReminder(Reminder r) => V1Reminder(
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

  V1Friend _mapFriend(FriendRecord f) => V1Friend(
    id: f.id,
    displayName: f.displayName,
    publicKeyHex: f.publicKeyHex,
    peerSharingId: f.peerSharingId,
    // Exclude sharedSecretHex from export — cryptographic secret should not
    // appear in plaintext backup files. Friends must re-verify after restore.
    sharedSecretHex: null,
    offeredScopes: f.offeredScopes,
    grantedScopes: f.grantedScopes,
    isVerified: f.isVerified,
    initId: f.initId,
    createdAt: f.createdAt.toUtc().toIso8601String(),
    establishedAt: f.establishedAt?.toUtc().toIso8601String(),
    lastSyncAt: f.lastSyncAt?.toUtc().toIso8601String(),
  );

  /// Reads `co_fronter_ids` (JSON list) and `pk_member_ids_json` directly
  /// off the v7 Drift columns for every non-deleted fronting session.
  /// Used only when `includeLegacyFields = true` is passed to
  /// [buildExport]; otherwise the export skips this query entirely.
  Future<Map<String, _LegacySessionFields>> _fetchLegacySessionFields(
    AppDatabase db,
  ) async {
    final rows = await db.customSelect(
      'SELECT id, co_fronter_ids, pk_member_ids_json '
      'FROM fronting_sessions WHERE is_deleted = 0',
    ).get();
    final out = <String, _LegacySessionFields>{};
    for (final row in rows) {
      final id = row.read<String>('id');
      final raw = row.read<String?>('co_fronter_ids') ?? '[]';
      List<String> parsed;
      try {
        final decoded = jsonDecode(raw);
        parsed = decoded is List
            ? decoded.whereType<String>().toList()
            : const <String>[];
      } catch (_) {
        // Defensive: a malformed JSON value shouldn't kill the whole export.
        // The corrupt-co-fronter-ids edge case (§6) is already handled by
        // the migration service; export just round-trips whatever's there.
        parsed = const <String>[];
      }
      out[id] = _LegacySessionFields(
        coFronterIds: parsed,
        pkMemberIdsJson: row.read<String?>('pk_member_ids_json'),
      );
    }
    return out;
  }

  /// Reads the v7 `session_id` column off `front_session_comments` for
  /// every non-deleted comment row. Returns the empty map if no rows have
  /// a non-empty `session_id` (post-migration the comments mapper writes
  /// an empty string sentinel into the column).
  Future<Map<String, String>> _fetchLegacyCommentSessionIds(
    AppDatabase db,
  ) async {
    final rows = await db.customSelect(
      'SELECT id, session_id FROM front_session_comments '
      "WHERE is_deleted = 0 AND session_id IS NOT NULL AND session_id != ''",
    ).get();
    return {
      for (final row in rows)
        row.read<String>('id'): row.read<String>('session_id'),
    };
  }
}

/// v7-era legacy column values for a single fronting session row, read
/// directly from Drift since the new-shape freezed model no longer
/// exposes them.
class _LegacySessionFields {
  const _LegacySessionFields({
    required this.coFronterIds,
    required this.pkMemberIdsJson,
  });

  final List<String> coFronterIds;
  final String? pkMemberIdsJson;
}
