import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide Habit, HabitCompletion;
import 'package:prism_plurality/data/repositories/drift_chat_message_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/drift_poll_repository.dart';
import 'package:prism_plurality/data/repositories/drift_sleep_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_notes_repository.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_conversation_categories_repository.dart';
import 'package:prism_plurality/data/repositories/drift_reminders_repository.dart';
import 'package:prism_plurality/data/repositories/drift_friends_repository.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/data_management/models/v3_export_models.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DataExportService _makeExport(AppDatabase db) => DataExportService(
      memberRepository: DriftMemberRepository(db.membersDao, null),
      frontingSessionRepository:
          DriftFrontingSessionRepository(db.frontingSessionsDao, null),
      conversationRepository:
          DriftConversationRepository(db.conversationsDao, null),
      chatMessageRepository:
          DriftChatMessageRepository(db.chatMessagesDao, null),
      pollRepository: DriftPollRepository(
          db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null),
      sleepSessionRepository:
          DriftSleepSessionRepository(db.sleepSessionsDao, null),
      systemSettingsRepository:
          DriftSystemSettingsRepository(db.systemSettingsDao, null),
      habitRepository: DriftHabitRepository(db.habitsDao, null),
      pluralKitSyncDao: db.pluralKitSyncDao,
      memberGroupsRepository:
          DriftMemberGroupsRepository(db.memberGroupsDao, null),
      customFieldsRepository:
          DriftCustomFieldsRepository(db.customFieldsDao, null),
      notesRepository: DriftNotesRepository(db.notesDao, null),
      frontSessionCommentsRepository:
          DriftFrontSessionCommentsRepository(db.frontSessionCommentsDao, null),
      conversationCategoriesRepository:
          DriftConversationCategoriesRepository(
              db.conversationCategoriesDao, null),
      remindersRepository: DriftRemindersRepository(db.remindersDao, null),
      friendsRepository: DriftFriendsRepository(db.friendsDao, null),
    );

DataImportService _makeImport(AppDatabase db) => DataImportService(
      db: db,
      memberRepository: DriftMemberRepository(db.membersDao, null),
      frontingSessionRepository:
          DriftFrontingSessionRepository(db.frontingSessionsDao, null),
      conversationRepository:
          DriftConversationRepository(db.conversationsDao, null),
      chatMessageRepository:
          DriftChatMessageRepository(db.chatMessagesDao, null),
      pollRepository: DriftPollRepository(
          db.pollsDao, db.pollOptionsDao, db.pollVotesDao, null),
      sleepSessionRepository:
          DriftSleepSessionRepository(db.sleepSessionsDao, null),
      systemSettingsRepository:
          DriftSystemSettingsRepository(db.systemSettingsDao, null),
      habitRepository: DriftHabitRepository(db.habitsDao, null),
      pluralKitSyncDao: db.pluralKitSyncDao,
      memberGroupsRepository:
          DriftMemberGroupsRepository(db.memberGroupsDao, null),
      customFieldsRepository:
          DriftCustomFieldsRepository(db.customFieldsDao, null),
      notesRepository: DriftNotesRepository(db.notesDao, null),
      frontSessionCommentsRepository:
          DriftFrontSessionCommentsRepository(db.frontSessionCommentsDao, null),
      conversationCategoriesRepository:
          DriftConversationCategoriesRepository(
              db.conversationCategoriesDao, null),
      remindersRepository: DriftRemindersRepository(db.remindersDao, null),
      friendsRepository: DriftFriendsRepository(db.friendsDao, null),
    );

/// Serialize a [V3Export] to JSON string and back through [DataImportService].
Future<ImportResult> _roundtrip(
    DataExportService exportSvc, DataImportService importSvc) async {
  final export = await exportSvc.buildExport();
  final jsonStr = const JsonEncoder().convert(export.toJson());
  return importSvc.importData(jsonStr);
}

void main() {
  group('V3 export/import roundtrip', () {
    late AppDatabase sourceDb;
    late AppDatabase targetDb;
    late DataExportService exportService;
    late DataImportService importService;
    late HabitRepository sourceHabitRepo;
    late SystemSettingsRepository sourceSettingsRepo;

    setUp(() {
      sourceDb = _makeDb();
      targetDb = _makeDb();
      exportService = _makeExport(sourceDb);
      importService = _makeImport(targetDb);
      sourceHabitRepo =
          DriftHabitRepository(sourceDb.habitsDao, null);
      sourceSettingsRepo =
          DriftSystemSettingsRepository(sourceDb.systemSettingsDao, null);
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
      final targetHabitRepo =
          DriftHabitRepository(targetDb.habitsDao, null);
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
          importedHabit.onlyNotifyWhenFronting, habit.onlyNotifyWhenFronting);
      expect(importedHabit.isPrivate, habit.isPrivate);
      expect(importedHabit.currentStreak, habit.currentStreak);
      expect(importedHabit.bestStreak, habit.bestStreak);
      expect(importedHabit.totalCompletions, habit.totalCompletions);

      // Assert: completions restored
      final importedCompletions =
          await targetHabitRepo.getCompletionsForHabit('habit-1');
      expect(importedCompletions, hasLength(2));

      final c1 =
          importedCompletions.firstWhere((c) => c.id == 'completion-1');
      expect(c1.habitId, 'habit-1');
      expect(c1.completedByMemberId, 'member-1');
      expect(c1.notes, 'Felt great!');
      expect(c1.wasFronting, true);
      expect(c1.rating, 5);

      final c2 =
          importedCompletions.firstWhere((c) => c.id == 'completion-2');
      expect(c2.completedByMemberId, isNull);
      expect(c2.notes, isNull);
      expect(c2.wasFronting, false);
      expect(c2.rating, isNull);
    });

    test('all 5 previously-missing SystemSettings fields survive roundtrip',
        () async {
      // Arrange: update settings with non-default values for the 5 new fields
      await sourceSettingsRepo.updateSettings(const SystemSettings(
        systemName: 'Test System',
        themeBrightness: ThemeBrightness.dark,
        themeStyle: ThemeStyle.oled,
        quickSwitchThresholdSeconds: 45,
        chatLogsFront: true,
        syncThemeEnabled: true,
      ));

      // Act
      final result = await _roundtrip(exportService, importService);

      // Assert: import succeeded

      expect(result.settingsUpdated, true);

      // Assert: all 5 fields restored
      final targetSettingsRepo = DriftSystemSettingsRepository(
          targetDb.systemSettingsDao, null);
      final imported = await targetSettingsRepo.getSettings();
      expect(imported.themeBrightness, ThemeBrightness.dark);
      expect(imported.themeStyle, ThemeStyle.oled);
      expect(imported.quickSwitchThresholdSeconds, 45);
      expect(imported.chatLogsFront, true);
      expect(imported.syncThemeEnabled, true);
      expect(imported.systemName, 'Test System');
    });

    test('V3SystemSettings JSON serialization includes all new fields', () {
      // Verify toJson/fromJson symmetry for the 5 new fields
      final original = V3SystemSettings(
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

      final roundtripped = V3SystemSettings.fromJson(json);
      expect(roundtripped.themeBrightness, original.themeBrightness);
      expect(roundtripped.themeStyle, original.themeStyle);
      expect(roundtripped.quickSwitchThresholdSeconds,
          original.quickSwitchThresholdSeconds);
      expect(roundtripped.chatLogsFront, original.chatLogsFront);
      expect(roundtripped.syncThemeEnabled, original.syncThemeEnabled);
    });

    test(
        'V3SystemSettings fromJson defaults new fields to safe values for old exports',
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

      final parsed = V3SystemSettings.fromJson(oldJson);
      expect(parsed.themeBrightness, 0); // system
      expect(parsed.themeStyle, 0); // standard
      expect(parsed.quickSwitchThresholdSeconds, 30);
      expect(parsed.chatLogsFront, false);
      expect(parsed.syncThemeEnabled, false);
    });

    test('idempotent import skips already-imported habits', () async {
      // Arrange: create one habit in source
      final now = DateTime(2026, 2, 1).toUtc();
      await sourceHabitRepo.createHabit(Habit(
        id: 'habit-idempotent',
        name: 'Idempotent Habit',
        createdAt: now,
        modifiedAt: now,
        frequency: HabitFrequency.daily,
      ));

      // First import
      final result1 = await _roundtrip(exportService, importService);
      expect(result1.habitsCreated, 1);

      // Second import of same data using same importService (same target DB)
      final result2 = await _roundtrip(exportService, importService);
      expect(result2.habitsCreated, 0);
    });
  });
}
