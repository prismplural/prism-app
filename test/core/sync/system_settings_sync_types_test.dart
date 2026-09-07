import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_plurality/data/repositories/drift_system_settings_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

void main() {
  final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
  final fieldTypes =
      ((schema['entities'] as Map<String, dynamic>)['system_settings']
              as Map<String, dynamic>)['fields']
          as Map<String, dynamic>;

  group('SystemSettings emitted sync field types', () {
    late AppDatabase db;
    late DriftSystemSettingsRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftSystemSettingsRepository(SystemSettingsDao(db), null);
    });

    tearDown(() => db.close());

    Future<List<CapturedSyncOp>> capture(Future<void> Function() action) async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);
      await action();
      return captured;
    }

    void expectSchemaTypes(Map<String, dynamic> fields) {
      for (final entry in fields.entries) {
        final declaredType = fieldTypes[entry.key];
        expect(
          declaredType,
          isA<String>(),
          reason:
              'Repository emitted unknown system-settings field ${entry.key}',
        );
        final value = entry.value;
        if (value == null) continue;
        switch (declaredType) {
          case 'Int':
            expect(value, isA<int>(), reason: '${entry.key} must emit Int');
          case 'Real':
            expect(value, isA<double>(), reason: '${entry.key} must emit Real');
          case 'Bool':
            expect(value, isA<bool>(), reason: '${entry.key} must emit Bool');
          case 'String':
          case 'Blob':
          case 'DateTime':
            expect(
              value,
              isA<String>(),
              reason: '${entry.key} must emit String',
            );
          default:
            fail('Unknown schema type $declaredType for ${entry.key}');
        }
      }
    }

    test(
      'captures a real bulk update and validates emitted scalar values',
      () async {
        await repo.updateSyncNavigationEnabled(false);
        final current = await repo.getSettings();
        final settings = current.copyWith(
          systemName: 'Test system',
          sharingId: 'sharing-id',
          showQuickFront: !current.showQuickFront,
          accentColorHex: '#123456',
          perMemberAccentColors: !current.perMemberAccentColors,
          terminology: SystemTerminology.values.last,
          memberNameDisplay: MemberNameDisplay.values.last,
          customTerminology: 'member',
          customPluralTerminology: 'members',
          terminologyUseEnglish: !current.terminologyUseEnglish,
          frontingRemindersEnabled: !current.frontingRemindersEnabled,
          frontingReminderIntervalMinutes:
              current.frontingReminderIntervalMinutes + 1,
          themeMode: AppThemeMode.values.last,
          themeBrightness: ThemeBrightness.values.last,
          themeStyle: ThemeStyle.values.last,
          cornerStyle: CornerStyle.values.last,
          paletteSource: PaletteSource.values.first,
          paletteSeedColorHex: '#654321',
          paletteMood: PaletteMood.values.last,
          paletteContrast: PaletteContrast.values.last,
          chatEnabled: !current.chatEnabled,
          pollsEnabled: !current.pollsEnabled,
          habitsEnabled: !current.habitsEnabled,
          sleepTrackingEnabled: !current.sleepTrackingEnabled,
          gifSearchEnabled: !current.gifSearchEnabled,
          voiceNotesEnabled: !current.voiceNotesEnabled,
          sleepSuggestionEnabled: !current.sleepSuggestionEnabled,
          sleepSuggestionHour: current.sleepSuggestionHour == 23 ? 22 : 23,
          sleepSuggestionMinute: current.sleepSuggestionMinute == 59 ? 58 : 59,
          wakeSuggestionEnabled: !current.wakeSuggestionEnabled,
          wakeSuggestionAfterHours: current.wakeSuggestionAfterHours + 0.5,
          localeOverride: 'en-AU',
          quickSwitchThresholdSeconds: current.quickSwitchThresholdSeconds + 1,
          identityGeneration: current.identityGeneration + 1,
          chatLogsFront: !current.chatLogsFront,
          syncThemeEnabled: true,
          timingMode: FrontingTimingMode.values.last,
          notesEnabled: !current.notesEnabled,
          pkGroupSyncV2Enabled: !current.pkGroupSyncV2Enabled,
          systemDescription: 'Description',
          systemColor: '#FEDCBA',
          systemTag: 'tag',
          systemAvatarData: Uint8List.fromList(<int>[1, 2, 3]),
          remindersEnabled: !current.remindersEnabled,
          habitsBadgeEnabled: !current.habitsBadgeEnabled,
          syncNavigationEnabled: true,
          navBarItems: const <String>['fronting', 'members'],
          navBarOverflowItems: const <String>['settings'],
          navBarLabelDisplayMode: NavBarLabelDisplayMode.values.last,
          navBarRevealLabelsWhenExpanded:
              !current.navBarRevealLabelsWhenExpanded,
          chatBadgePreferences: const <String, String>{'member-1': 'all'},
          frontingListViewMode: FrontingListViewMode.values.last,
          addFrontDefaultBehavior: FrontStartBehavior.values.last,
          quickFrontDefaultBehavior: FrontStartBehavior.values.last,
          autoPromoteLongFrontingSessions:
              !current.autoPromoteLongFrontingSessions,
          bioMarkdownEnabled: !current.bioMarkdownEnabled,
        );

        final captured = await capture(() => repo.updateSettings(settings));

        expect(captured, hasLength(1));
        final op = captured.single;
        expect(op.table, 'system_settings');
        expect(op.entityId, 'singleton');
        expect(op.opType, SyncRecordOpType.update);
        expectSchemaTypes(op.fields);
        const dedicatedPathFields = <String>{
          'boards_enabled',
          'sp_boards_backfilled_at',
          'is_deleted',
        };
        expect(
          op.fields.keys.toSet(),
          equals(fieldTypes.keys.toSet().difference(dedicatedPathFields)),
          reason:
              'Bulk update must emit every schema field except the dedicated '
              'setter and tombstone paths listed above.',
        );
        expect(
          op.fields,
          containsPair('terminology', SystemTerminology.values.last.index),
        );
        expect(
          op.fields,
          containsPair('theme_mode', AppThemeMode.values.last.index),
        );
        expect(
          op.fields,
          containsPair('theme_brightness', ThemeBrightness.values.last.index),
        );
        expect(
          op.fields,
          containsPair('theme_style', ThemeStyle.values.last.index),
        );
        expect(
          op.fields,
          containsPair('timing_mode', FrontingTimingMode.values.last.index),
        );
        expect(fieldTypes['pk_group_sync_v2_enabled'], 'Bool');
        expect(op.fields['pk_group_sync_v2_enabled'], isA<bool>());
        expect(op.fields['wake_suggestion_after_hours'], isA<double>());
        expect(op.fields['system_avatar_data'], base64Encode(<int>[1, 2, 3]));
      },
    );

    test(
      'captures each enum value through its production update method',
      () async {
        await repo.getSettings();
        final captured = await capture(() async {
          for (final value in SystemTerminology.values) {
            await repo.updateTerminology(value);
          }
          for (final value in AppThemeMode.values) {
            await repo.updateThemeMode(value);
          }
          await repo.updateSyncThemeEnabled(true);
          for (final value in ThemeBrightness.values) {
            await repo.updateThemeBrightness(value);
          }
          for (final value in ThemeStyle.values) {
            await repo.updateThemeStyle(value);
          }
          for (final value in FrontingTimingMode.values) {
            await repo.updateTimingMode(value);
          }
        });

        for (final op in captured) {
          expectSchemaTypes(op.fields);
        }
        expect(
          captured
              .where((op) => op.fields.containsKey('terminology'))
              .map((op) => op.fields['terminology']),
          SystemTerminology.values.map((value) => value.index),
        );
        expect(
          captured
              .where((op) => op.fields.containsKey('theme_mode'))
              .map((op) => op.fields['theme_mode']),
          AppThemeMode.values.map((value) => value.index),
        );
        expect(
          captured
              .where((op) => op.fields.containsKey('theme_brightness'))
              .map((op) => op.fields['theme_brightness']),
          ThemeBrightness.values.map((value) => value.index),
        );
        expect(
          captured
              .where((op) => op.fields.containsKey('theme_style'))
              .map((op) => op.fields['theme_style']),
          ThemeStyle.values.map((value) => value.index),
        );
        expect(
          captured
              .where((op) => op.fields.containsKey('timing_mode'))
              .map((op) => op.fields['timing_mode']),
          FrontingTimingMode.values.map((value) => value.index),
        );
      },
    );

    test('emits a nullable schema field as an explicit null update', () async {
      await repo.updateSystemName('present');
      final captured = await capture(() => repo.updateSystemName(null));

      expect(captured, hasLength(1));
      expect(captured.single.fields, containsPair('system_name', isNull));
      expect(fieldTypes['system_name'], 'String');
    });
  });
}
