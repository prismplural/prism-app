import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/mappers/system_settings_mapper.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // SystemSettingsMapper — cornerStyle / themeCornerStyle round-trip
  // ════════════════════════════════════════════════════════════════════════════

  SystemSettingsData makeDbRow({int themeCornerStyle = 0}) {
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
      themeCornerStyle: themeCornerStyle,
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
      pendingFrontingMigrationMode: 'notStarted',
      pendingFrontingMigrationCleanupSubstate: '',
      frontingListViewMode: 0,
      addFrontDefaultBehavior: 0,
      quickFrontDefaultBehavior: 0,
      boardsEnabled: false,
    );
  }

  group('SystemSettingsMapper cornerStyle', () {
    test('themeCornerStyle=0 maps to CornerStyle.rounded', () {
      final row = makeDbRow(themeCornerStyle: 0);
      final domain = SystemSettingsMapper.toDomain(row);
      expect(domain.cornerStyle, CornerStyle.rounded);
    });

    test('themeCornerStyle=1 maps to CornerStyle.angular', () {
      final row = makeDbRow(themeCornerStyle: 1);
      final domain = SystemSettingsMapper.toDomain(row);
      expect(domain.cornerStyle, CornerStyle.angular);
    });

    test('toCompanion stores CornerStyle.rounded as 0', () {
      final row = makeDbRow(themeCornerStyle: 0);
      final domain = SystemSettingsMapper.toDomain(row);
      final companion = SystemSettingsMapper.toCompanion(domain);
      expect(companion.themeCornerStyle.value, 0);
    });

    test('toCompanion stores CornerStyle.angular as 1', () {
      final row = makeDbRow(themeCornerStyle: 1);
      final domain = SystemSettingsMapper.toDomain(row);
      final companion = SystemSettingsMapper.toCompanion(domain);
      expect(companion.themeCornerStyle.value, 1);
    });

    test('default SystemSettings has CornerStyle.rounded', () {
      const settings = SystemSettings();
      expect(settings.cornerStyle, CornerStyle.rounded);
    });

    test('round-trip: rounded -> companion -> index is 0', () {
      const settings = SystemSettings(cornerStyle: CornerStyle.rounded);
      final companion = SystemSettingsMapper.toCompanion(settings);
      expect(companion.themeCornerStyle.value, 0);
    });

    test('round-trip: angular -> companion -> index is 1', () {
      const settings = SystemSettings(cornerStyle: CornerStyle.angular);
      final companion = SystemSettingsMapper.toCompanion(settings);
      expect(companion.themeCornerStyle.value, 1);
    });
  });
}
