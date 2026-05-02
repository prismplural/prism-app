import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/mappers/system_settings_mapper.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // SystemSettingsMapper — navBarItems encode / decode
  // ════════════════════════════════════════════════════════════════════════════

  group('SystemSettingsMapper navBarItems', () {
    SystemSettingsData makeDbRow({String navBarItems = ''}) {
      return SystemSettingsData(
        id: 'singleton',
        systemName: null,
        showQuickFront: true,
        accentColorHex: '#7C3AED',
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
        navBarItems: navBarItems,
        navBarOverflowItems: '',
        syncNavigationEnabled: true,
        chatBadgePreferences: '{}',
        sleepSuggestionEnabled: false,
        sleepSuggestionHour: 22,
        sleepSuggestionMinute: 0,
        wakeSuggestionEnabled: false,
        wakeSuggestionAfterHours: 8.0,
        pendingFrontingMigrationMode: 'notStarted',
        pendingFrontingMigrationCleanupSubstate: '',
        frontingListViewMode: 0,
        addFrontDefaultBehavior: 0,
        quickFrontDefaultBehavior: 0,
        boardsEnabled: false,
      );
    }

    test('encodeNavBarItems with empty list returns empty string', () {
      expect(SystemSettingsMapper.encodeNavBarItems([]), '');
    });

    test('encodeNavBarItems with items returns valid JSON', () {
      final encoded = SystemSettingsMapper.encodeNavBarItems([
        'home',
        'chat',
        'settings',
      ]);
      final decoded = jsonDecode(encoded);
      expect(decoded, isA<List>());
      expect(decoded, ['home', 'chat', 'settings']);
    });

    test('round-trip: encode then decode preserves the list', () {
      final original = ['home', 'polls', 'habits', 'chat', 'settings'];
      final encoded = SystemSettingsMapper.encodeNavBarItems(original);
      final row = makeDbRow(navBarItems: encoded);
      final domain = SystemSettingsMapper.toDomain(row);
      expect(domain.navBarItems, original);
    });

    test('decoding empty string returns empty list (via toDomain)', () {
      final row = makeDbRow(navBarItems: '');
      final domain = SystemSettingsMapper.toDomain(row);
      expect(domain.navBarItems, isEmpty);
    });

    test('decoding malformed JSON returns empty list', () {
      final row = makeDbRow(navBarItems: 'not valid json!!!');
      final domain = SystemSettingsMapper.toDomain(row);
      expect(domain.navBarItems, isEmpty);
    });

    test('decoding non-list JSON returns empty list', () {
      final row = makeDbRow(navBarItems: '{}');
      final domain = SystemSettingsMapper.toDomain(row);
      expect(domain.navBarItems, isEmpty);
    });

    test('decoding JSON array of non-strings returns empty list', () {
      // List<String>.from([1,2,3]) throws a TypeError in sound null safety,
      // which the decoder catches and returns an empty list.
      final row = makeDbRow(navBarItems: '[1,2,3]');
      final domain = SystemSettingsMapper.toDomain(row);
      expect(domain.navBarItems, isEmpty);
    });

    test('toCompanion encodes navBarItems via encodeNavBarItems', () {
      final row = makeDbRow(
        navBarItems: jsonEncode(['home', 'chat', 'settings']),
      );
      final domain = SystemSettingsMapper.toDomain(row);
      final companion = SystemSettingsMapper.toCompanion(domain);
      final stored = companion.navBarItems.value;
      expect(jsonDecode(stored), ['home', 'chat', 'settings']);
    });

    test('toCompanion with empty navBarItems stores empty string', () {
      final row = makeDbRow(navBarItems: '');
      final domain = SystemSettingsMapper.toDomain(row);
      final companion = SystemSettingsMapper.toCompanion(domain);
      expect(companion.navBarItems.value, '');
    });
  });
}
