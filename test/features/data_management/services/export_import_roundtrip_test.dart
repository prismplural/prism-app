import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Habit, HabitCompletion, Member;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
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
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExport(AppDatabase db) => DataExportService(
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
);

DataImportService _makeImport(AppDatabase db) => DataImportService(
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
);

/// Serialize a [V1Export] to JSON string and back through [DataImportService].
Future<ImportResult> _roundtrip(
  DataExportService exportSvc,
  DataImportService importSvc,
) async {
  final export = await exportSvc.buildExport();
  final jsonStr = const JsonEncoder().convert(export.toJson());
  return importSvc.importData(jsonStr);
}

void main() {
  group('V3 export/import roundtrip', () {
    late bool previousMultipleDbWarningSetting;
    late AppDatabase sourceDb;
    late AppDatabase targetDb;
    late DataExportService exportService;
    late DataImportService importService;
    late HabitRepository sourceHabitRepo;
    late SystemSettingsRepository sourceSettingsRepo;

    setUpAll(() {
      previousMultipleDbWarningSetting =
          drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      // These tests intentionally keep isolated source and target in-memory
      // databases open at the same time to verify export/import roundtrips.
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDownAll(() {
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousMultipleDbWarningSetting;
    });

    setUp(() {
      sourceDb = _makeDb();
      targetDb = _makeDb();
      exportService = _makeExport(sourceDb);
      importService = _makeImport(targetDb);
      sourceHabitRepo = DriftHabitRepository(sourceDb.habitsDao, null);
      sourceSettingsRepo = DriftSystemSettingsRepository(
        sourceDb.systemSettingsDao,
        null,
      );
    });

    tearDown(() async {
      await sourceDb.close();
      await targetDb.close();
    });

    test('habits and completions survive export → import', () async {
      // Arrange: create a habit and two completions in the source DB
      final now = DateTime(2026, 1, 15, 10, 0, 0).toUtc();
      final habit = Habit(
        id: 'habit-1',
        name: 'Morning Walk',
        description: 'Walk for 30 minutes',
        icon: '🚶',
        colorHex: '#FF5733',
        isActive: true,
        createdAt: now,
        modifiedAt: now,
        frequency: HabitFrequency.daily,
        weeklyDays: [1, 3, 5],
        reminderTime: '08:00',
        notificationsEnabled: true,
        notificationMessage: 'Time to walk!',
        assignedMemberId: 'member-1',
        onlyNotifyWhenFronting: true,
        isPrivate: false,
        currentStreak: 5,
        bestStreak: 10,
        totalCompletions: 42,
      );
      await sourceHabitRepo.createHabit(habit);

      final completion1 = HabitCompletion(
        id: 'completion-1',
        habitId: 'habit-1',
        completedAt: now,
        completedByMemberId: 'member-1',
        notes: 'Felt great!',
        wasFronting: true,
        rating: 5,
        createdAt: now,
        modifiedAt: now,
      );
      final completion2 = HabitCompletion(
        id: 'completion-2',
        habitId: 'habit-1',
        completedAt: now.subtract(const Duration(days: 1)),
        completedByMemberId: null,
        notes: null,
        wasFronting: false,
        rating: null,
        createdAt: now.subtract(const Duration(days: 1)),
        modifiedAt: now.subtract(const Duration(days: 1)),
      );
      await sourceHabitRepo.createCompletion(completion1);
      await sourceHabitRepo.createCompletion(completion2);

      // Act
      final result = await _roundtrip(exportService, importService);

      // Assert: import succeeded

      expect(result.habitsCreated, 1);
      expect(result.habitCompletionsCreated, 2);

      // Assert: habit fields restored correctly
      final targetHabitRepo = DriftHabitRepository(targetDb.habitsDao, null);
      final importedHabits = await targetHabitRepo.getAllHabits();
      expect(importedHabits, hasLength(1));
      final importedHabit = importedHabits.single;
      expect(importedHabit.id, habit.id);
      expect(importedHabit.name, habit.name);
      expect(importedHabit.description, habit.description);
      expect(importedHabit.icon, habit.icon);
      expect(importedHabit.colorHex, habit.colorHex);
      expect(importedHabit.isActive, habit.isActive);
      expect(importedHabit.frequency, habit.frequency);
      expect(importedHabit.weeklyDays, habit.weeklyDays);
      expect(importedHabit.reminderTime, habit.reminderTime);
      expect(importedHabit.notificationsEnabled, habit.notificationsEnabled);
      expect(importedHabit.notificationMessage, habit.notificationMessage);
      expect(importedHabit.assignedMemberId, habit.assignedMemberId);
      expect(
        importedHabit.onlyNotifyWhenFronting,
        habit.onlyNotifyWhenFronting,
      );
      expect(importedHabit.isPrivate, habit.isPrivate);
      expect(importedHabit.currentStreak, habit.currentStreak);
      expect(importedHabit.bestStreak, habit.bestStreak);
      expect(importedHabit.totalCompletions, habit.totalCompletions);

      // Assert: completions restored
      final importedCompletions = await targetHabitRepo.getCompletionsForHabit(
        'habit-1',
      );
      expect(importedCompletions, hasLength(2));

      final c1 = importedCompletions.firstWhere((c) => c.id == 'completion-1');
      expect(c1.habitId, 'habit-1');
      expect(c1.completedByMemberId, 'member-1');
      expect(c1.notes, 'Felt great!');
      expect(c1.wasFronting, true);
      expect(c1.rating, 5);

      final c2 = importedCompletions.firstWhere((c) => c.id == 'completion-2');
      expect(c2.completedByMemberId, isNull);
      expect(c2.notes, isNull);
      expect(c2.wasFronting, false);
      expect(c2.rating, isNull);
    });

    test(
      'all 5 previously-missing SystemSettings fields survive roundtrip',
      () async {
        // Arrange: update settings with non-default values for the 5 new fields
        await sourceSettingsRepo.updateSettings(
          const SystemSettings(
            systemName: 'Test System',
            themeBrightness: ThemeBrightness.dark,
            themeStyle: ThemeStyle.oled,
            quickSwitchThresholdSeconds: 45,
            chatLogsFront: true,
            syncThemeEnabled: true,
          ),
        );

        // Act
        final result = await _roundtrip(exportService, importService);

        // Assert: import succeeded

        expect(result.settingsUpdated, true);

        // Assert: all 5 fields restored
        final targetSettingsRepo = DriftSystemSettingsRepository(
          targetDb.systemSettingsDao,
          null,
        );
        final imported = await targetSettingsRepo.getSettings();
        expect(imported.themeBrightness, ThemeBrightness.dark);
        expect(imported.themeStyle, ThemeStyle.oled);
        expect(imported.quickSwitchThresholdSeconds, 45);
        expect(imported.chatLogsFront, true);
        expect(imported.syncThemeEnabled, true);
        expect(imported.systemName, 'Test System');
      },
    );

    test('V1SystemSettings JSON serialization includes all new fields', () {
      // Verify toJson/fromJson symmetry for the 5 new fields
      final original = V1SystemSettings(
        themeBrightness: 2, // materialYou
        themeStyle: 1, // oled
        quickSwitchThresholdSeconds: 60,
        chatLogsFront: true,
        syncThemeEnabled: true,
      );

      final json = original.toJson();
      expect(json['themeBrightness'], 2);
      expect(json['themeStyle'], 1);
      expect(json['quickSwitchThresholdSeconds'], 60);
      expect(json['chatLogsFront'], true);
      expect(json['syncThemeEnabled'], true);

      final roundtripped = V1SystemSettings.fromJson(json);
      expect(roundtripped.themeBrightness, original.themeBrightness);
      expect(roundtripped.themeStyle, original.themeStyle);
      expect(
        roundtripped.quickSwitchThresholdSeconds,
        original.quickSwitchThresholdSeconds,
      );
      expect(roundtripped.chatLogsFront, original.chatLogsFront);
      expect(roundtripped.syncThemeEnabled, original.syncThemeEnabled);
    });

    test(
      'V1SystemSettings fromJson defaults new fields to safe values for old exports',
      () {
        // Simulate an old export that lacks the 5 new fields
        final oldJson = <String, dynamic>{
          'showQuickFront': true,
          'accentColorHex': '#7C3AED',
          'perMemberAccentColors': true,
          'terminology': 0,
          'frontingRemindersEnabled': false,
          'frontingReminderIntervalMinutes': 60,
          'themeMode': 0,
          'chatEnabled': true,
          'pollsEnabled': true,
          'habitsEnabled': true,
          'sleepTrackingEnabled': true,
          'hasCompletedOnboarding': false,
        };

        final parsed = V1SystemSettings.fromJson(oldJson);
        expect(parsed.themeBrightness, 0); // system
        expect(parsed.themeStyle, 0); // standard
        expect(parsed.quickSwitchThresholdSeconds, 30);
        expect(parsed.chatLogsFront, false);
        expect(parsed.syncThemeEnabled, false);
      },
    );

    test(
      'sleep sessions survive export → import as unified fronting rows',
      () async {
        final sleepRepo = DriftFrontingSessionRepository(
          sourceDb.frontingSessionsDao,
          null,
        );
        await sleepRepo.createSession(
          FrontingSession(
            id: 'sleep-1',
            startTime: DateTime(2026, 1, 20, 22, 0, 0).toUtc(),
            endTime: DateTime(2026, 1, 21, 6, 0, 0).toUtc(),
            memberId: null,
            sessionType: SessionType.sleep,
            quality: SleepQuality.good,
            notes: 'Slept well',
            isHealthKitImport: true,
          ),
        );

        final result = await _roundtrip(exportService, importService);
        expect(result.sleepSessionsCreated, 1);

        final targetSleepRepo = DriftFrontingSessionRepository(
          targetDb.frontingSessionsDao,
          null,
        );
        final imported = await targetSleepRepo.getAllSessions();
        expect(imported, hasLength(1));
        expect(imported.single.id, 'sleep-1');
        expect(imported.single.sessionType, SessionType.sleep);
        expect(imported.single.quality, SleepQuality.good);
        expect(imported.single.isHealthKitImport, isTrue);
      },
    );

    test(
      'member groups, entries, custom fields, values, and front session comments survive roundtrip',
      () async {
        final now = DateTime(2026, 3, 10, 12, 0, 0).toUtc();

        // --- Seed a member (needed as FK target for group entries and field values)
        await DriftMemberRepository(sourceDb.membersDao, null).createMember(
          Member(
            id: 'member-rnd',
            name: 'Roundtrip Member',
            pronouns: 'they/them',
            emoji: '\u2728',
            createdAt: now,
          ),
        );

        // --- Seed member groups + entries
        final sourceGroupsRepo = DriftMemberGroupsRepository(
          sourceDb.memberGroupsDao,
          null,
        );
        await sourceGroupsRepo.createGroup(
          MemberGroup(
            id: 'group-1',
            name: 'Test Group',
            description: 'A test group',
            colorHex: '#FF0000',
            emoji: '\uD83C\uDF1F',
            displayOrder: 1,
            createdAt: now,
          ),
        );
        await sourceGroupsRepo.addMemberToGroup(
          'group-1',
          'member-rnd',
          'entry-1',
        );

        // --- Seed custom fields + values
        final sourceFieldsRepo = DriftCustomFieldsRepository(
          sourceDb.customFieldsDao,
          null,
        );
        await sourceFieldsRepo.createField(
          CustomField(
            id: 'field-1',
            name: 'Favorite Color',
            fieldType: CustomFieldType.text,
            displayOrder: 0,
            createdAt: now,
          ),
        );
        await sourceFieldsRepo.upsertValue(
          const CustomFieldValue(
            id: 'fv-1',
            customFieldId: 'field-1',
            memberId: 'member-rnd',
            value: 'Purple',
          ),
        );

        // --- Seed a fronting session (needed as FK target for comments)
        await DriftFrontingSessionRepository(
          sourceDb.frontingSessionsDao,
          null,
        ).createSession(
          FrontingSession(
            id: 'session-rnd',
            startTime: now.subtract(const Duration(hours: 2)),
            endTime: now,
            memberId: 'member-rnd',
          ),
        );

        // --- Seed front session comments
        final sourceCommentsRepo = DriftFrontSessionCommentsRepository(
          sourceDb.frontSessionCommentsDao,
          null,
        );
        await sourceCommentsRepo.createComment(
          FrontSessionComment(
            id: 'comment-1',
            // Post-Phase-5 comments anchor to targetTime, not session id.
            targetTime: now,
            body: 'Felt good today',
            timestamp: now,
            createdAt: now,
          ),
        );
        await sourceCommentsRepo.createComment(
          FrontSessionComment(
            id: 'comment-2',
            targetTime: now.add(const Duration(minutes: 5)),
            body: 'Second comment',
            timestamp: now.add(const Duration(minutes: 5)),
            createdAt: now.add(const Duration(minutes: 5)),
          ),
        );

        // Act: export from source, import into target
        final result = await _roundtrip(exportService, importService);

        // Assert counts
        expect(result.memberGroupsCreated, 1);
        expect(result.memberGroupEntriesCreated, 1);
        expect(result.customFieldsCreated, 1);
        expect(result.customFieldValuesCreated, 1);
        expect(result.frontSessionCommentsCreated, 2);

        // Assert member group fields restored
        final targetGroupsRepo = DriftMemberGroupsRepository(
          targetDb.memberGroupsDao,
          null,
        );
        final importedGroups = await targetGroupsRepo.watchAllGroups().first;
        expect(importedGroups, hasLength(1));
        expect(importedGroups.single.id, 'group-1');
        expect(importedGroups.single.name, 'Test Group');
        expect(importedGroups.single.description, 'A test group');

        // Assert member group entry restored
        final importedEntries = await targetGroupsRepo.getAllGroupEntries();
        expect(importedEntries, hasLength(1));
        expect(importedEntries.single.groupId, 'group-1');
        expect(importedEntries.single.memberId, 'member-rnd');

        // Assert custom field restored
        final targetFieldsRepo = DriftCustomFieldsRepository(
          targetDb.customFieldsDao,
          null,
        );
        final importedFields = await targetFieldsRepo.watchAllFields().first;
        expect(importedFields, hasLength(1));
        expect(importedFields.single.name, 'Favorite Color');
        expect(importedFields.single.fieldType, CustomFieldType.text);

        // Assert custom field value restored
        final importedValues = await targetFieldsRepo.getAllValues();
        expect(importedValues, hasLength(1));
        expect(importedValues.single.value, 'Purple');
        expect(importedValues.single.memberId, 'member-rnd');

        // Assert front session comments restored
        final targetCommentsRepo = DriftFrontSessionCommentsRepository(
          targetDb.frontSessionCommentsDao,
          null,
        );
        final importedComments = await targetCommentsRepo.getAllComments();
        expect(importedComments, hasLength(2));
        final c1 = importedComments.firstWhere((c) => c.id == 'comment-1');
        expect(c1.body, 'Felt good today');
        expect(c1.targetTime?.toUtc(), now);
        final c2 = importedComments.firstWhere((c) => c.id == 'comment-2');
        expect(c2.body, 'Second comment');
      },
    );

    test(
      'idempotent import of groups, fields, and comments creates zero duplicates',
      () async {
        final now = DateTime(2026, 3, 11, 8, 0, 0).toUtc();

        // Seed member
        await DriftMemberRepository(sourceDb.membersDao, null).createMember(
          Member(
            id: 'member-idem',
            name: 'Idempotent Member',
            pronouns: 'she/her',
            emoji: '\uD83D\uDC9C',
            createdAt: now,
          ),
        );

        // Seed group + entry
        final sourceGroupsRepo = DriftMemberGroupsRepository(
          sourceDb.memberGroupsDao,
          null,
        );
        await sourceGroupsRepo.createGroup(
          MemberGroup(
            id: 'group-idem',
            name: 'Idem Group',
            createdAt: now,
          ),
        );
        await sourceGroupsRepo.addMemberToGroup(
          'group-idem',
          'member-idem',
          'entry-idem',
        );

        // Seed custom field + value
        final sourceFieldsRepo = DriftCustomFieldsRepository(
          sourceDb.customFieldsDao,
          null,
        );
        await sourceFieldsRepo.createField(
          CustomField(
            id: 'field-idem',
            name: 'Role',
            fieldType: CustomFieldType.text,
            createdAt: now,
          ),
        );
        await sourceFieldsRepo.upsertValue(
          const CustomFieldValue(
            id: 'fv-idem',
            customFieldId: 'field-idem',
            memberId: 'member-idem',
            value: 'Host',
          ),
        );

        // Seed fronting session + comment
        await DriftFrontingSessionRepository(
          sourceDb.frontingSessionsDao,
          null,
        ).createSession(
          FrontingSession(
            id: 'session-idem',
            startTime: now.subtract(const Duration(hours: 1)),
            endTime: now,
            memberId: 'member-idem',
          ),
        );

        final sourceCommentsRepo = DriftFrontSessionCommentsRepository(
          sourceDb.frontSessionCommentsDao,
          null,
        );
        await sourceCommentsRepo.createComment(
          FrontSessionComment(
            id: 'comment-idem',
            targetTime: now,
            body: 'Test comment',
            timestamp: now,
            createdAt: now,
          ),
        );

        // First import
        final result1 = await _roundtrip(exportService, importService);
        expect(result1.memberGroupsCreated, 1);
        expect(result1.memberGroupEntriesCreated, 1);
        expect(result1.customFieldsCreated, 1);
        expect(result1.customFieldValuesCreated, 1);
        expect(result1.frontSessionCommentsCreated, 1);

        // Second import — same data, same target DB
        final result2 = await _roundtrip(exportService, importService);
        expect(result2.memberGroupsCreated, 0);
        expect(result2.memberGroupEntriesCreated, 0);
        expect(result2.customFieldsCreated, 0);
        expect(result2.customFieldValuesCreated, 0);
        expect(result2.frontSessionCommentsCreated, 0);
      },
    );

    test(
      'PluralKit Phase 2 member fields survive export → import',
      () async {
        // Arrange: create a member with all PK Phase 2 fields populated
        final now = DateTime(2026, 4, 17, 12, 0, 0).toUtc();
        await DriftMemberRepository(sourceDb.membersDao, null).createMember(
          Member(
            id: 'pk-member-1',
            name: 'Alex',
            pronouns: 'they/them',
            emoji: '\u2728',
            createdAt: now,
            pluralkitUuid: '11111111-1111-1111-1111-111111111111',
            pluralkitId: 'abcde',
            displayName: 'Alex (fronting)',
            birthday: '1995-06-15',
            proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
            pluralkitSyncIgnored: true,
          ),
        );

        // Act
        final result = await _roundtrip(exportService, importService);
        expect(result.membersCreated, 1);

        // Assert: all PK fields round-tripped
        final targetMemberRepo = DriftMemberRepository(
          targetDb.membersDao,
          null,
        );
        final imported = await targetMemberRepo.getAllMembers();
        expect(imported, hasLength(1));
        final m = imported.single;
        expect(m.id, 'pk-member-1');
        expect(m.pluralkitUuid, '11111111-1111-1111-1111-111111111111');
        expect(m.pluralkitId, 'abcde');
        expect(m.displayName, 'Alex (fronting)');
        expect(m.birthday, '1995-06-15');
        expect(m.proxyTagsJson, '[{"prefix":"A:","suffix":null}]');
        expect(m.pluralkitSyncIgnored, true);
      },
    );

    test(
      'PluralKit fronting session pluralkitUuid survives new-shape roundtrip',
      () async {
        final now = DateTime(2026, 4, 17, 14, 0, 0).toUtc();

        // Seed a member (FK target) and a session with pkMemberIdsJson
        await DriftMemberRepository(sourceDb.membersDao, null).createMember(
          Member(
            id: 'pk-session-member',
            name: 'Co-fronter',
            emoji: '\u2728',
            createdAt: now,
          ),
        );
        await DriftFrontingSessionRepository(
          sourceDb.frontingSessionsDao,
          null,
        ).createSession(
          FrontingSession(
            id: 'pk-session-1',
            startTime: now.subtract(const Duration(hours: 1)),
            endTime: now,
            memberId: 'pk-session-member',
            pluralkitUuid: '22222222-2222-2222-2222-222222222222',
          ),
        );

        final result = await _roundtrip(exportService, importService);
        expect(result.frontSessionsCreated, 1);

        final targetSessionsRepo = DriftFrontingSessionRepository(
          targetDb.frontingSessionsDao,
          null,
        );
        final imported = await targetSessionsRepo.getAllSessions();
        expect(imported, hasLength(1));
        final s = imported.single;
        expect(s.id, 'pk-session-1');
        expect(s.pluralkitUuid, '22222222-2222-2222-2222-222222222222');
        // Post-Phase-5 the FrontingSession model no longer carries
        // `pkMemberIdsJson` — the field is read off the v7 Drift column
        // only when the legacy-fields export branch runs (migration-time).
        // The new-shape exporter omits it; per-member rows are derived via
        // §2.6 deterministic v5 ids on import.
      },
    );

    test(
      'V1Headmate/V1FrontSession fromJson defaults PK Phase 2 fields for old exports',
      () {
        // Old export without PK Phase 2 fields — must parse cleanly.
        final oldHeadmateJson = <String, dynamic>{
          'id': 'm1',
          'name': 'Legacy',
          'isActive': true,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'displayOrder': 0,
          'isAdmin': false,
          'customColorEnabled': false,
          'markdownEnabled': false,
        };
        final h = V1Headmate.fromJson(oldHeadmateJson);
        expect(h.displayName, isNull);
        expect(h.birthday, isNull);
        expect(h.proxyTagsJson, isNull);
        expect(h.pluralkitSyncIgnored, false);

        final oldSessionJson = <String, dynamic>{
          'id': 's1',
          'startTime': '2026-01-01T00:00:00.000Z',
        };
        final s = V1FrontSession.fromJson(oldSessionJson);
        expect(s.pkMemberIdsJson, isNull);
      },
    );

    test('idempotent import skips already-imported habits', () async {
      // Arrange: create one habit in source
      final now = DateTime(2026, 2, 1).toUtc();
      await sourceHabitRepo.createHabit(
        Habit(
          id: 'habit-idempotent',
          name: 'Idempotent Habit',
          createdAt: now,
          modifiedAt: now,
          frequency: HabitFrequency.daily,
        ),
      );

      // First import
      final result1 = await _roundtrip(exportService, importService);
      expect(result1.habitsCreated, 1);

      // Second import of same data using same importService (same target DB)
      final result2 = await _roundtrip(exportService, importService);
      expect(result2.habitsCreated, 0);
    });
  });
}
