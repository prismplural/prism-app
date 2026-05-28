import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_media_attachment_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_board_posts_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExport(
  AppDatabase db,
  Directory cacheDir,
) => DataExportService(
  db: db,
  memberRepository: DriftMemberRepository(db.membersDao, null),
  frontingSessionRepository: DriftFrontingSessionRepository(
    db.frontingSessionsDao,
    null,
  ),
  conversationRepository: DriftConversationRepository(
    db.conversationsDao,
    null,
  ),
  chatMessageRepository: DriftChatMessageRepository(db.chatMessagesDao, null),
  pollRepository: DriftPollRepository(
    db.pollsDao,
    db.pollOptionsDao,
    db.pollVotesDao,
    null,
  ),
  systemSettingsRepository: DriftSystemSettingsRepository(
    db.systemSettingsDao,
    null,
  ),
  habitRepository: DriftHabitRepository(db.habitsDao, null),
  pluralKitSyncDao: db.pluralKitSyncDao,
  memberGroupsRepository: DriftMemberGroupsRepository(db.memberGroupsDao, null),
  customFieldsRepository: DriftCustomFieldsRepository(db.customFieldsDao, null),
  notesRepository: DriftNotesRepository(db.notesDao, null),
  frontSessionCommentsRepository: DriftFrontSessionCommentsRepository(
    db.frontSessionCommentsDao,
    null,
  ),
  conversationCategoriesRepository: DriftConversationCategoriesRepository(
    db.conversationCategoriesDao,
    null,
  ),
  remindersRepository: DriftRemindersRepository(db.remindersDao, null),
  friendsRepository: DriftFriendsRepository(db.friendsDao, null),
  mediaAttachmentsDao: db.mediaAttachmentsDao,
  cacheDirectoryProvider: () async => cacheDir,
  appSupportDirectoryProvider: () async => cacheDir,
);

class _ExportSchemaCoverageCase {
  const _ExportSchemaCoverageCase(
    this.name, {
    required this.domainJson,
    required this.exportJson,
    this.aliases = const {},
    this.ignoredDomainKeys = const {},
  });

  final String name;
  final Map<String, dynamic> domainJson;
  final Map<String, dynamic> exportJson;
  final Map<String, String> aliases;
  final Set<String> ignoredDomainKeys;
}

void _expectExportCoversDomainFields(List<_ExportSchemaCoverageCase> cases) {
  final failures = <String>[];
  for (final c in cases) {
    final exportKeys = c.exportJson.keys.toSet();
    final missing = <String>[];
    for (final domainKey in c.domainJson.keys) {
      if (c.ignoredDomainKeys.contains(domainKey)) continue;
      final exportKey = c.aliases[domainKey] ?? domainKey;
      if (!exportKeys.contains(exportKey)) {
        missing.add('$domainKey -> $exportKey');
      }
    }
    if (missing.isNotEmpty) {
      failures.add('${c.name}: ${missing.join(', ')}');
    }
  }

  expect(
    failures,
    isEmpty,
    reason:
        'Every persisted domain-model JSON key should be represented in the '
        'backup export schema, unless this test names an explicit exception.',
  );
}

Uint8List _tinyPng() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1)));

void main() {
  group('DataExportService', () {
    late AppDatabase db;
    late Directory cacheDir;
    late DataExportService exportService;

    setUp(() {
      db = _makeDb();
      cacheDir = Directory.systemTemp.createTempSync('prism-export-test-');
      exportService = _makeExport(db, cacheDir);
    });

    tearDown(() async {
      await db.close();
      await cacheDir.delete(recursive: true);
    });

    test('exportEncryptedData writes an encrypted .prism file', () async {
      final file = await exportService.exportEncryptedData(
        password: 'test-password',
      );

      expect(file.path, endsWith('.prism'));
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      expect(ExportCrypto.isEncrypted(bytes), isTrue);

      final json = ExportCrypto.decrypt(bytes, 'test-password').json;
      final export = jsonDecode(json) as Map<String, dynamic>;
      expect(export['appName'], 'Prism Plurality');
      expect(export['version'], '1.0');
    });

    test(
      'buildExport keeps sleep sessions separate from fronting sessions',
      () async {
        await exportService.frontingSessionRepository.createSession(
          FrontingSession(
            id: 'front-1',
            startTime: DateTime(2026, 3, 18, 10),
            memberId: 'member-1',
          ),
        );
        await exportService.frontingSessionRepository.createSession(
          FrontingSession(
            id: 'sleep-1',
            startTime: DateTime(2026, 3, 18, 22),
            endTime: DateTime(2026, 3, 19, 6),
            memberId: null,
            sessionType: SessionType.sleep,
            quality: SleepQuality.unknown,
            notes: 'nap',
          ),
        );

        final export = await exportService.buildExport();

        expect(export.frontSessions, hasLength(1));
        expect(export.sleepSessions, hasLength(1));
        expect(export.frontSessions.single.id, 'front-1');
        expect(export.sleepSessions.single.id, 'sleep-1');
      },
    );

    test('buildExport normalizes legacy dm-shaped conversations', () async {
      await exportService.conversationRepository.createConversation(
        Conversation(
          id: 'legacy-dm',
          createdAt: DateTime(2026, 3, 18, 10),
          lastActivityAt: DateTime(2026, 3, 18, 11),
          title: '',
          participantIds: const ['alice', 'bob'],
        ),
      );

      final export = await exportService.buildExport();
      final conversation = export.conversations.single;
      final json = conversation.toJson();

      expect(conversation.isDirectMessage, isTrue);
      expect(json['type'], 'directmessage');
      expect(json['isDirectMessage'], isTrue);
    });

    test('buildExport preserves everyone-group conversations', () async {
      await exportService.conversationRepository.createConversation(
        Conversation(
          id: 'everyone-group',
          createdAt: DateTime(2026, 3, 18, 10),
          lastActivityAt: DateTime(2026, 3, 18, 11),
          title: 'Everyone',
          participantIds: const ['creator'],
          includesAllMembers: true,
        ),
      );

      final export = await exportService.buildExport();
      final json = export.conversations.single.toJson();

      expect(json['includesAllMembers'], isTrue);
    });

    test('buildExport covers every exported domain model field', () async {
      // Keep fixture values non-default so conditional V1 JSON keys are covered.
      final avatarBytes = _tinyPng();
      final now = DateTime.utc(2026, 3, 18, 10);
      final later = now.add(const Duration(minutes: 30));

      final member = Member(
        id: 'coverage-member',
        name: 'Coverage Member',
        pronouns: 'they/them',
        emoji: ':)',
        age: 30,
        bio: 'Bio',
        avatarImageData: avatarBytes,
        pkAvatarCachedUrl: 'https://cdn.example/member/avatar.png',
        isActive: true,
        createdAt: now,
        displayOrder: 2,
        isAdmin: true,
        customColorEnabled: true,
        customColorHex: '#123456',
        parentSystemId: 'system-1',
        pluralkitUuid: '11111111-1111-1111-1111-111111111111',
        pluralkitId: 'abcde',
        pluralkitDisplayName: 'PK Display',
        markdownEnabled: false,
        displayName: 'Display',
        birthday: '2000-01-01',
        proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
        pkBannerUrl: 'https://cdn.example/member/banner.png',
        profileHeaderSource: MemberProfileHeaderSource.pluralKit,
        profileHeaderLayout: MemberProfileHeaderLayout.classicOverlap,
        profileHeaderVisible: false,
        nameStyleFont: MemberNameFont.mono,
        nameStyleBold: false,
        nameStyleItalic: true,
        nameStyleColorMode: MemberNameColorMode.custom,
        nameStyleColorHex: '#654321',
        profileHeaderImageData: avatarBytes,
        pkBannerImageData: avatarBytes,
        pkBannerCachedUrl: 'https://cdn.example/member/banner-cached.png',
        pluralkitSyncIgnored: true,
        isAlwaysFronting: true,
      );
      await exportService.memberRepository.createMember(member);

      final session = FrontingSession(
        id: 'coverage-session',
        startTime: now,
        endTime: later,
        memberId: member.id,
        notes: 'Session notes',
        confidence: FrontConfidence.certain,
        pluralkitUuid: '22222222-2222-2222-2222-222222222222',
        pkImportSource: 'api',
        pkFileSwitchId: 'switch-1',
        sessionType: SessionType.normal,
        quality: SleepQuality.good,
        isHealthKitImport: true,
      );
      await exportService.frontingSessionRepository.createSession(session);

      final conversation = Conversation(
        id: 'coverage-group',
        createdAt: now,
        lastActivityAt: later,
        title: 'Coverage',
        emoji: ':sparkles:',
        isDirectMessage: false,
        creatorId: member.id,
        participantIds: [member.id],
        includesAllMembers: true,
        archivedByMemberIds: const ['archived-member'],
        mutedByMemberIds: const ['muted-member'],
        lastReadTimestamps: {member.id: later},
        description: 'Conversation export coverage',
        categoryId: 'category-1',
        displayOrder: 7,
      );
      await exportService.conversationRepository.createConversation(
        conversation,
      );

      final reaction = MessageReaction(
        id: 'coverage-reaction',
        emoji: ':heart:',
        memberId: member.id,
        timestamp: now,
      );
      final message = ChatMessage(
        id: 'coverage-message',
        content: 'Message',
        timestamp: now,
        isSystemMessage: true,
        editedAt: later,
        authorId: member.id,
        conversationId: conversation.id,
        reactions: [reaction],
        replyToId: 'reply-id',
        replyToAuthorId: member.id,
        replyToContent: 'Reply',
      );
      await exportService.chatMessageRepository.createMessage(message);

      final pollVote = PollVote(
        id: 'coverage-vote',
        memberId: member.id,
        votedAt: now,
        responseText: 'Other response',
      );
      final pollOption = PollOption(
        id: 'coverage-option',
        text: 'Option',
        sortOrder: 3,
        isOtherOption: true,
        colorHex: '#abcdef',
        votes: [pollVote],
      );
      final poll = Poll(
        id: 'coverage-poll',
        question: 'Question?',
        description: 'Description',
        isAnonymous: true,
        allowsMultipleVotes: true,
        isClosed: true,
        expiresAt: later,
        createdAt: now,
        options: [pollOption],
      );
      await exportService.pollRepository.createPoll(poll);
      await exportService.pollRepository.castVote(pollVote, pollOption.id);

      final settings = SystemSettings(
        systemName: 'Coverage System',
        sharingId: 'sharing-id',
        showQuickFront: false,
        accentColorHex: '#111111',
        perMemberAccentColors: false,
        terminology: SystemTerminology.parts,
        customTerminology: 'part',
        customPluralTerminology: 'parts',
        frontingRemindersEnabled: true,
        frontingReminderIntervalMinutes: 45,
        themeMode: AppThemeMode.materialYou,
        themeBrightness: ThemeBrightness.dark,
        themeStyle: ThemeStyle.oled,
        cornerStyle: CornerStyle.angular,
        paletteSource: PaletteSource.device,
        paletteSeedColorHex: '#222222',
        paletteMood: PaletteMood.vibrant,
        paletteContrast: PaletteContrast.high,
        chatEnabled: false,
        pollsEnabled: false,
        habitsEnabled: false,
        sleepTrackingEnabled: false,
        gifSearchEnabled: false,
        voiceNotesEnabled: false,
        sleepSuggestionEnabled: true,
        sleepSuggestionHour: 23,
        sleepSuggestionMinute: 15,
        wakeSuggestionEnabled: true,
        wakeSuggestionAfterHours: 7.5,
        quickSwitchThresholdSeconds: 55,
        identityGeneration: 4,
        chatLogsFront: true,
        terminologyUseEnglish: true,
        hasCompletedOnboarding: true,
        syncThemeEnabled: true,
        habitsBadgeEnabled: false,
        timingMode: FrontingTimingMode.strict,
        notesEnabled: false,
        previousAccentColorHex: '#333333',
        systemDescription: 'System description',
        systemColor: '#444444',
        pkGroupSyncV2Enabled: true,
        systemTag: 'tag',
        systemAvatarData: avatarBytes,
        remindersEnabled: false,
        localeOverride: 'en-US',
        gifConsentState: GifConsentState.enabled,
        fontScale: 1.2,
        fontFamily: FontFamily.openDyslexic,
        pinLockEnabled: true,
        biometricLockEnabled: true,
        autoLockDelaySeconds: 120,
        displayFontInAppBar: false,
        navBarItems: const ['fronting', 'members'],
        navBarOverflowItems: const ['settings'],
        syncNavigationEnabled: false,
        chatBadgePreferences: {member.id: 'mentions_only'},
        defaultSleepQuality: SleepQuality.excellent,
        frontingListViewMode: FrontingListViewMode.perMemberRows,
        addFrontDefaultBehavior: FrontStartBehavior.replace,
        quickFrontDefaultBehavior: FrontStartBehavior.replace,
        autoPromoteLongFrontingSessions: false,
        boardsEnabled: true,
        spBoardsBackfilledAt: later,
        membersListViewMode: MembersListViewMode.groupedSections,
        membersGroupedDefaultState: MembersGroupedDefaultState.closed,
        membersFolderMemberVisibility:
            MembersFolderMemberVisibility.ungroupedOnly,
        membersShowPronouns: false,
        membersShowFrontButtons: true,
        membersFrontButtonBehavior: FrontStartBehavior.replace,
        bioMarkdownEnabled: false,
      );
      await exportService.systemSettingsRepository.updateSettings(settings);

      final habit = Habit(
        id: 'coverage-habit',
        name: 'Habit',
        description: 'Habit description',
        icon: 'star',
        colorHex: '#777777',
        isActive: false,
        createdAt: now,
        modifiedAt: later,
        frequency: HabitFrequency.weekly,
        weeklyDays: const [1, 3],
        intervalDays: 2,
        reminderTime: '09:30',
        notificationsEnabled: true,
        notificationMessage: 'Reminder',
        assignedMemberId: member.id,
        onlyNotifyWhenFronting: true,
        isPrivate: true,
        currentStreak: 4,
        bestStreak: 8,
        totalCompletions: 12,
      );
      await exportService.habitRepository.createHabit(habit);
      final completion = HabitCompletion(
        id: 'coverage-completion',
        habitId: habit.id,
        completedAt: now,
        completedByMemberId: member.id,
        notes: 'Completion notes',
        wasFronting: true,
        rating: 5,
        createdAt: now,
        modifiedAt: later,
      );
      await exportService.habitRepository.createCompletion(completion);

      final memberGroup = MemberGroup(
        id: 'coverage-member-group',
        name: 'Group',
        description: 'Group description',
        colorHex: '#888888',
        emoji: '#',
        avatarImageData: avatarBytes,
        displayOrder: 9,
        parentGroupId: 'parent-group',
        groupType: 2,
        filterRules: '{"kind":"all"}',
        createdAt: now,
      );
      await exportService.memberGroupsRepository.createGroup(memberGroup);
      const groupEntry = MemberGroupEntry(
        id: 'coverage-group-entry',
        groupId: 'coverage-member-group',
        memberId: 'coverage-member',
      );
      await exportService.memberGroupsRepository.addMemberToGroup(
        groupEntry.groupId,
        groupEntry.memberId,
        groupEntry.id,
      );

      final customField = CustomField(
        id: 'coverage-field',
        name: 'Field',
        fieldType: CustomFieldType.date,
        datePrecision: DatePrecision.timestamp,
        displayOrder: 5,
        createdAt: now,
      );
      await exportService.customFieldsRepository.createField(customField);
      const customFieldValue = CustomFieldValue(
        id: 'coverage-field-value',
        customFieldId: 'coverage-field',
        memberId: 'coverage-member',
        value: '2026-03-18T10:00:00.000Z',
      );
      await exportService.customFieldsRepository.upsertValue(customFieldValue);

      final note = Note(
        id: 'coverage-note',
        title: 'Note',
        body: 'Body',
        colorHex: '#999999',
        memberId: member.id,
        date: now,
        createdAt: now,
        modifiedAt: later,
      );
      await exportService.notesRepository.createNote(note);

      final comment = FrontSessionComment(
        id: 'coverage-comment',
        sessionId: session.id,
        body: 'Comment',
        timestamp: now,
        createdAt: later,
      );
      await exportService.frontSessionCommentsRepository.createComment(comment);

      final category = ConversationCategory(
        id: 'category-1',
        name: 'Category',
        displayOrder: 6,
        createdAt: now,
        modifiedAt: later,
      );
      await exportService.conversationCategoriesRepository.create(category);

      final reminder = Reminder(
        id: 'coverage-reminder',
        name: 'Reminder',
        message: 'Reminder message',
        trigger: ReminderTrigger.onFrontChange,
        frequency: ReminderFrequency.weekly,
        weeklyDays: const [2, 4],
        intervalDays: 3,
        timeOfDay: '08:15',
        delayHours: 2,
        targetMemberId: member.id,
        isActive: false,
        createdAt: now,
        modifiedAt: later,
      );
      await exportService.remindersRepository.create(reminder);

      final friend = FriendRecord(
        id: 'coverage-friend',
        displayName: 'Friend',
        peerSharingId: 'peer-id',
        pairwiseSecret: avatarBytes,
        pinnedIdentity: avatarBytes,
        offeredScopes: const ['fronting'],
        publicKeyHex: 'public-key',
        sharedSecretHex: 'shared-secret',
        grantedScopes: const ['members'],
        isVerified: true,
        initId: 'init-id',
        createdAt: now,
        establishedAt: later,
        lastSyncAt: later,
      );
      await exportService.friendsRepository.createFriend(friend);

      final boardPost = MemberBoardPost(
        id: 'coverage-board-post',
        targetMemberId: member.id,
        authorId: member.id,
        audience: 'private',
        title: 'Post',
        body: 'Post body',
        createdAt: now,
        writtenAt: later,
        editedAt: later,
      );
      await DriftMemberBoardPostsRepository(
        db.memberBoardPostsDao,
        db.membersDao,
        null,
      ).createPost(boardPost);

      const mediaAttachment = MediaAttachment(
        id: 'coverage-attachment',
        messageId: 'coverage-message',
        mediaId: 'media-id',
        mediaType: 'image',
        encryptionKeyB64: 'key',
        contentHash: 'content-hash',
        plaintextHash: 'plain-hash',
        mimeType: 'image/png',
        sizeBytes: 123,
        width: 10,
        height: 20,
        durationMs: 30,
        blurhash: 'blurhash',
        waveformB64: 'waveform',
        thumbnailMediaId: 'thumb-id',
        sourceUrl: 'https://cdn.example/source.png',
        previewUrl: 'https://cdn.example/preview.png',
      );
      await DriftMediaAttachmentRepository(
        db.mediaAttachmentsDao,
        null,
      ).create(mediaAttachment);

      final export = await exportService.buildExport();

      _expectExportCoversDomainFields([
        _ExportSchemaCoverageCase(
          'Member',
          domainJson: member.toJson(),
          exportJson: export.headmates.single.toJson(),
          aliases: const {
            'bio': 'notes',
            'avatarImageData': 'profilePhotoData',
          },
          ignoredDomainKeys: const {
            'isDeleted',
            'deleteIntentEpoch',
            'deletePushStartedAt',
          },
        ),
        _ExportSchemaCoverageCase(
          'FrontingSession',
          domainJson: session.toJson(),
          exportJson: export.frontSessions.single.toJson(),
          aliases: const {'memberId': 'headmateId'},
          ignoredDomainKeys: const {
            'isDeleted',
            'deleteIntentEpoch',
            'deletePushStartedAt',
          },
        ),
        _ExportSchemaCoverageCase(
          'Conversation',
          domainJson: conversation.toJson(),
          exportJson: export.conversations.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'ChatMessage',
          domainJson: message.toJson(),
          exportJson: export.messages.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'MessageReaction',
          domainJson: reaction.toJson(),
          exportJson: export.messages.single.reactions.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'Poll',
          domainJson: poll.toJson(),
          exportJson: export.polls.single.toJson(),
          ignoredDomainKeys: const {'options'},
        ),
        _ExportSchemaCoverageCase(
          'PollOption',
          domainJson: pollOption.toJson(),
          exportJson: export.pollOptions.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'PollVote',
          domainJson: pollVote.toJson(),
          exportJson: export.pollOptions.single.votes.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'SystemSettings',
          domainJson: settings.toJson(),
          exportJson: export.systemSettings.single.toJson(),
          aliases: const {'cornerStyle': 'themeCornerStyle'},
        ),
        _ExportSchemaCoverageCase(
          'Habit',
          domainJson: habit.toJson(),
          exportJson: export.habits.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'HabitCompletion',
          domainJson: completion.toJson(),
          exportJson: export.habitCompletions.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'MemberGroup',
          domainJson: memberGroup.toJson(),
          exportJson: export.memberGroups.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'MemberGroupEntry',
          domainJson: groupEntry.toJson(),
          exportJson: export.memberGroupEntries.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'CustomField',
          domainJson: customField.toJson(),
          exportJson: export.customFields.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'CustomFieldValue',
          domainJson: customFieldValue.toJson(),
          exportJson: export.customFieldValues.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'Note',
          domainJson: note.toJson(),
          exportJson: export.notes.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'FrontSessionComment',
          domainJson: comment.toJson(),
          exportJson: export.frontSessionComments.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'ConversationCategory',
          domainJson: category.toJson(),
          exportJson: export.conversationCategories.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'Reminder',
          domainJson: reminder.toJson(),
          exportJson: export.reminders.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'FriendRecord',
          domainJson: friend.toJson(),
          exportJson: export.friends.single.toJson(),
          ignoredDomainKeys: const {
            // Pairing secrets are intentionally omitted from plaintext backups.
            'pairwiseSecret',
            'pinnedIdentity',
            'sharedSecretHex',
          },
        ),
        _ExportSchemaCoverageCase(
          'MemberBoardPost',
          domainJson: boardPost.toJson(),
          exportJson: export.memberBoardPosts.single.toJson(),
        ),
        _ExportSchemaCoverageCase(
          'MediaAttachment',
          domainJson: mediaAttachment.toJson(),
          exportJson: export.mediaAttachments.single.toJson(),
        ),
      ]);
    });

    // Issue #40 (review-2026-04-30): legacy raw-SQL queries on dropped
    // columns must degrade gracefully. Today the v7 schema still has
    // `co_fronter_ids`, `pk_member_ids_json`, and comment `session_id`,
    // so the export reads them without complaint. The future v8 cleanup
    // migration will drop those columns; we simulate the post-cleanup
    // shape by physically dropping them via raw SQL after the v7 schema
    // is created, then assert that `buildExport(includeLegacyFields: true)`
    // still completes and merely returns empty legacy maps.
    test(
      'buildExport with includeLegacyFields=true succeeds when legacy columns '
      'still exist on disk',
      () async {
        // Smoke-test the current state.
        final export = await exportService.buildExport(
          includeLegacyFields: true,
        );
        expect(export.frontSessions, isEmpty);
      },
    );

    // -- PR G additions (review finding #39): envelope shape gating ----

    test('V1Export.fromJson rejects unknown formatVersion explicitly '
        '(review finding #39 + remediation plan WS4 step 7)', () async {
      final json = {
        'formatVersion': '99.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': '2026-04-30T00:00:00.000Z',
        'totalRecords': 0,
        'headmates': [],
        'frontSessions': [],
        'sleepSessions': [],
        'conversations': [],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      };
      expect(() => V1Export.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('envelope rescueLegacyFields=true wins over ambiguous row shape: '
        'a row carrying only `headmateId` (which the row-shape sniff would '
        'route to new-shape) routes through legacy when the envelope '
        'flag is set', () async {
      // Row shape: only headmateId, no coFronterIds, no pkMemberIdsJson,
      // no sessionType / memberId. Per the row-shape sniff this would
      // be classified as legacy via the "no headmateId AND no
      // coFronterIds AND no new-shape marker" leg — but it DOES have
      // headmateId, so the row sniff alone routes it to new-shape.
      // The envelope flag overrides.
      V1FrontSession.resetRowShapeLegacyFallbackCount();
      final json = {
        'formatVersion': '1.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': '2026-04-30T00:00:00.000Z',
        'totalRecords': 1,
        'rescueLegacyFields': true,
        'headmates': [],
        'frontSessions': [
          {
            'id': 'ambig-1',
            'startTime': '2026-04-01T09:00:00.000Z',
            'headmateId': 'm1',
          },
        ],
        'sleepSessions': [],
        'conversations': [],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      };
      final export = V1Export.fromJson(json);
      // Envelope flag forces legacy.
      expect(export.frontSessions.single.isLegacyShape, true);
      // Envelope flag drove the decision; the per-row sniff
      // fallback counter did not tick.
      expect(V1FrontSession.rowShapeLegacyFallbackCount, 0);
    });

    test('envelope rescueLegacyFields=false + ambiguous row: per-row sniff '
        'is the fallback and the counter ticks (so its uses can be '
        'observed and eventually removed)', () async {
      V1FrontSession.resetRowShapeLegacyFallbackCount();
      final json = {
        'formatVersion': '1.0',
        'version': '1.0',
        'appName': 'Prism Plurality',
        'exportDate': '2026-04-30T00:00:00.000Z',
        'totalRecords': 1,
        // No rescueLegacyFields: false implicit.
        'headmates': [],
        'frontSessions': [
          {
            'id': 'leg-1',
            'startTime': '2026-04-01T09:00:00.000Z',
            // Pure legacy shape (pkMemberIdsJson present, no
            // sessionType / memberId).
            'pkMemberIdsJson': '["abc"]',
            'pluralkitUuid': 'switch-1',
          },
        ],
        'sleepSessions': [],
        'conversations': [],
        'messages': [],
        'polls': [],
        'pollOptions': [],
        'systemSettings': [],
        'habits': [],
        'habitCompletions': [],
      };
      final export = V1Export.fromJson(json);
      expect(export.frontSessions.single.isLegacyShape, true);
      // Per-row sniff was the trigger — counter ticks once.
      expect(V1FrontSession.rowShapeLegacyFallbackCount, 1);
    });

    test(
      'buildExport with includeLegacyFields=true gracefully skips legacy '
      'queries when columns have been dropped (post-v8 cleanup simulation)',
      () async {
        // Simulate a future v8 cleanup migration by physically dropping the
        // legacy columns. SQLite needs a TableMigration-style rebuild for
        // DROP COLUMN; the simplest reproducible setup is to recreate the
        // tables without the legacy columns using `customStatement`.
        await db.customStatement(
          'CREATE TABLE _new_fronting_sessions ('
          '  id TEXT NOT NULL PRIMARY KEY,'
          '  session_type INTEGER NOT NULL DEFAULT 0,'
          '  start_time INTEGER NOT NULL,'
          '  end_time INTEGER,'
          '  member_id TEXT,'
          '  notes TEXT,'
          '  confidence INTEGER,'
          '  quality INTEGER,'
          '  is_health_kit_import INTEGER NOT NULL DEFAULT 0,'
          '  pluralkit_uuid TEXT,'
          '  pk_import_source TEXT,'
          '  pk_file_switch_id TEXT,'
          '  is_deleted INTEGER NOT NULL DEFAULT 0,'
          '  delete_intent_epoch INTEGER,'
          '  delete_push_started_at INTEGER'
          ')',
        );
        await db.customStatement('DROP TABLE fronting_sessions');
        await db.customStatement(
          'ALTER TABLE _new_fronting_sessions RENAME TO fronting_sessions',
        );

        await db.customStatement(
          'CREATE TABLE _new_front_session_comments ('
          '  id TEXT NOT NULL PRIMARY KEY,'
          '  session_id TEXT NOT NULL,'
          '  body TEXT NOT NULL,'
          '  timestamp INTEGER NOT NULL,'
          '  created_at INTEGER NOT NULL,'
          '  is_deleted INTEGER NOT NULL DEFAULT 0'
          ')',
        );
        await db.customStatement('DROP TABLE front_session_comments');
        await db.customStatement(
          'ALTER TABLE _new_front_session_comments RENAME TO '
          'front_session_comments',
        );

        // Build a fresh export service so the column-existence cache
        // starts clean against the rewritten tables.
        final freshExport = _makeExport(db, cacheDir);
        final export = await freshExport.buildExport(includeLegacyFields: true);
        expect(
          export,
          isNotNull,
          reason:
              'buildExport must not throw a SQL error when legacy columns '
              'have been dropped — the helper should detect the missing '
              'columns via PRAGMA table_info and return empty maps',
        );
      },
    );
  });
}
