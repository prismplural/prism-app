import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/mappers/system_settings_mapper.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

/// Round-trip coverage for the three Phase 1B fronting preference fields:
///   - fronting_list_view_mode  (FrontingListViewMode)
///   - add_front_default_behavior  (FrontStartBehavior)
///   - quick_front_default_behavior  (FrontStartBehavior)
///
/// Mirrors the corner-style / nav-bar mapper tests already in this folder.
void main() {
  SystemSettingsData makeDbRow({
    int frontingListViewMode = 0,
    int addFrontDefaultBehavior = 0,
    int quickFrontDefaultBehavior = 0,
  }) {
    return SystemSettingsData(
      id: 'singleton',
      systemName: null,
      showQuickFront: true,
      accentColorHex: '#AF8EE9',
      perMemberAccentColors: false,
      terminology: 0,
      customTerminology: null,
      customPluralTerminology: null,
      terminologyUseEnglish: false,
      frontingRemindersEnabled: false,
      frontingReminderIntervalMinutes: 60,
      themeMode: 0,
      themeBrightness: 0,
      themeStyle: 0,
      themeCornerStyle: 0,
      chatEnabled: true,
      pollsEnabled: true,
      habitsEnabled: true,
      sleepTrackingEnabled: true,
      gifSearchEnabled: true,
      voiceNotesEnabled: true,
      localeOverride: null,
      quickSwitchThresholdSeconds: 30,
      identityGeneration: 0,
      chatLogsFront: false,
      hasCompletedOnboarding: false,
      syncThemeEnabled: false,
      habitsBadgeEnabled: true,
      timingMode: 0,
      notesEnabled: true,
      pkGroupSyncV2Enabled: false,
      previousAccentColorHex: '',
      systemDescription: null,
      systemColor: null,
      systemTag: null,
      systemAvatarData: null,
      remindersEnabled: true,
      gifConsentState: 0,
      fontScale: 1.0,
      fontFamily: 0,
      pinLockEnabled: false,
      biometricLockEnabled: false,
      autoLockDelaySeconds: 0,
      displayFontInAppBar: true,
      isDeleted: false,
      navBarItems: '',
      navBarOverflowItems: '',
      syncNavigationEnabled: true,
      chatBadgePreferences: '{}',
      sleepSuggestionEnabled: false,
      sleepSuggestionHour: 22,
      sleepSuggestionMinute: 0,
      wakeSuggestionEnabled: false,
      wakeSuggestionAfterHours: 8.0,
      sharingId: null,
      pendingFrontingMigrationMode: 'complete',
      pendingFrontingMigrationCleanupSubstate: '',
      frontingListViewMode: frontingListViewMode,
      addFrontDefaultBehavior: addFrontDefaultBehavior,
      quickFrontDefaultBehavior: quickFrontDefaultBehavior,
      boardsEnabled: false,
    );
  }

  group('SystemSettingsMapper — frontingListViewMode', () {
    test('default SystemSettings has FrontingListViewMode.combinedPeriods', () {
      const settings = SystemSettings();
      expect(
        settings.frontingListViewMode,
        FrontingListViewMode.combinedPeriods,
      );
    });

    test('row index 0 maps to combinedPeriods', () {
      final row = makeDbRow(frontingListViewMode: 0);
      expect(
        SystemSettingsMapper.toDomain(row).frontingListViewMode,
        FrontingListViewMode.combinedPeriods,
      );
    });

    test('row index 1 maps to perMemberRows', () {
      final row = makeDbRow(frontingListViewMode: 1);
      expect(
        SystemSettingsMapper.toDomain(row).frontingListViewMode,
        FrontingListViewMode.perMemberRows,
      );
    });

    test('row index 2 maps to timeline', () {
      final row = makeDbRow(frontingListViewMode: 2);
      expect(
        SystemSettingsMapper.toDomain(row).frontingListViewMode,
        FrontingListViewMode.timeline,
      );
    });

    test('invalid stored index falls back to combinedPeriods', () {
      expect(
        SystemSettingsMapper.toDomain(
          makeDbRow(frontingListViewMode: -1),
        ).frontingListViewMode,
        FrontingListViewMode.combinedPeriods,
      );
      expect(
        SystemSettingsMapper.toDomain(
          makeDbRow(frontingListViewMode: 999),
        ).frontingListViewMode,
        FrontingListViewMode.combinedPeriods,
      );
    });

    test('toCompanion stores enum index for each variant', () {
      for (final mode in FrontingListViewMode.values) {
        final settings = const SystemSettings().copyWith(
          frontingListViewMode: mode,
        );
        final companion = SystemSettingsMapper.toCompanion(settings);
        expect(companion.frontingListViewMode.value, mode.index);
      }
    });

    test('round-trip: every variant survives toCompanion → toDomain', () {
      for (final mode in FrontingListViewMode.values) {
        final row = makeDbRow(frontingListViewMode: mode.index);
        final domain = SystemSettingsMapper.toDomain(row);
        expect(domain.frontingListViewMode, mode);
      }
    });
  });

  group('SystemSettingsMapper — addFrontDefaultBehavior', () {
    test('default SystemSettings has FrontStartBehavior.additive', () {
      const settings = SystemSettings();
      expect(settings.addFrontDefaultBehavior, FrontStartBehavior.additive);
    });

    test('row index 0 maps to additive', () {
      final row = makeDbRow(addFrontDefaultBehavior: 0);
      expect(
        SystemSettingsMapper.toDomain(row).addFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
    });

    test('row index 1 maps to replace', () {
      final row = makeDbRow(addFrontDefaultBehavior: 1);
      expect(
        SystemSettingsMapper.toDomain(row).addFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
    });

    test('invalid stored index falls back to additive', () {
      expect(
        SystemSettingsMapper.toDomain(
          makeDbRow(addFrontDefaultBehavior: -1),
        ).addFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
      expect(
        SystemSettingsMapper.toDomain(
          makeDbRow(addFrontDefaultBehavior: 999),
        ).addFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
    });

    test('round-trip: every variant survives toCompanion → toDomain', () {
      for (final behavior in FrontStartBehavior.values) {
        final settings = const SystemSettings().copyWith(
          addFrontDefaultBehavior: behavior,
        );
        final companion = SystemSettingsMapper.toCompanion(settings);
        expect(companion.addFrontDefaultBehavior.value, behavior.index);
        final row = makeDbRow(addFrontDefaultBehavior: behavior.index);
        expect(
          SystemSettingsMapper.toDomain(row).addFrontDefaultBehavior,
          behavior,
        );
      }
    });
  });

  group('SystemSettingsMapper — quickFrontDefaultBehavior', () {
    test('default SystemSettings has FrontStartBehavior.additive', () {
      const settings = SystemSettings();
      expect(settings.quickFrontDefaultBehavior, FrontStartBehavior.additive);
    });

    test('row index 0 maps to additive', () {
      final row = makeDbRow(quickFrontDefaultBehavior: 0);
      expect(
        SystemSettingsMapper.toDomain(row).quickFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
    });

    test('row index 1 maps to replace', () {
      final row = makeDbRow(quickFrontDefaultBehavior: 1);
      expect(
        SystemSettingsMapper.toDomain(row).quickFrontDefaultBehavior,
        FrontStartBehavior.replace,
      );
    });

    test('invalid stored index falls back to additive', () {
      expect(
        SystemSettingsMapper.toDomain(
          makeDbRow(quickFrontDefaultBehavior: -1),
        ).quickFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
      expect(
        SystemSettingsMapper.toDomain(
          makeDbRow(quickFrontDefaultBehavior: 999),
        ).quickFrontDefaultBehavior,
        FrontStartBehavior.additive,
      );
    });

    test('round-trip: every variant survives toCompanion → toDomain', () {
      for (final behavior in FrontStartBehavior.values) {
        final settings = const SystemSettings().copyWith(
          quickFrontDefaultBehavior: behavior,
        );
        final companion = SystemSettingsMapper.toCompanion(settings);
        expect(companion.quickFrontDefaultBehavior.value, behavior.index);
        final row = makeDbRow(quickFrontDefaultBehavior: behavior.index);
        expect(
          SystemSettingsMapper.toDomain(row).quickFrontDefaultBehavior,
          behavior,
        );
      }
    });
  });

  group(
    'SystemSettingsMapper — independence of the two FrontStartBehavior fields',
    () {
      test(
        'add-front and quick-front behaviors are independent on round-trip',
        () {
          // add=replace, quick=additive
          final row = makeDbRow(
            addFrontDefaultBehavior: 1,
            quickFrontDefaultBehavior: 0,
          );
          final domain = SystemSettingsMapper.toDomain(row);
          expect(domain.addFrontDefaultBehavior, FrontStartBehavior.replace);
          expect(domain.quickFrontDefaultBehavior, FrontStartBehavior.additive);
        },
      );
    },
  );
}
