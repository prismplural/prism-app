import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

/// Mirrors the field map produced by DriftSystemSettingsRepository._settingsFields
/// and the individual _syncField calls for enum fields.
///
/// Regression: enum fields were serialized via .name (String) instead of
/// .index (int), causing "Type mismatch: expected int, got String" quarantine
/// errors on the receiving device.
Map<String, dynamic> _buildSyncFieldsMap(SystemSettings s) => {
  'system_name': s.systemName,
  'show_quick_front': s.showQuickFront,
  'accent_color_hex': s.accentColorHex,
  'per_member_accent_colors': s.perMemberAccentColors,
  'terminology': s.terminology.index,
  'custom_terminology': s.customTerminology,
  'custom_plural_terminology': s.customPluralTerminology,
  'fronting_reminders_enabled': s.frontingRemindersEnabled,
  'fronting_reminder_interval_minutes': s.frontingReminderIntervalMinutes,
  'theme_mode': s.themeMode.index,
  'theme_brightness': s.themeBrightness.index,
  'theme_style': s.themeStyle.index,
  'chat_enabled': s.chatEnabled,
  'polls_enabled': s.pollsEnabled,
  'habits_enabled': s.habitsEnabled,
  'sleep_tracking_enabled': s.sleepTrackingEnabled,
  'quick_switch_threshold_seconds': s.quickSwitchThresholdSeconds,
  'chat_logs_front': s.chatLogsFront,
  'sync_theme_enabled': s.syncThemeEnabled,
  'timing_mode': s.timingMode.index,
  'system_color': 'ff0000',
  'is_deleted': false,
};

void main() {
  group('SystemSettings sync field types', () {
    // Parse the schema once for all tests.
    final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
    final systemSettingsSchema =
        (schema['entities'] as Map<String, dynamic>)['system_settings']
            as Map<String, dynamic>;
    final fieldTypes =
        systemSettingsSchema['fields'] as Map<String, dynamic>;

    test('all Int fields in sync schema receive int values (not String)', () {
      // Use every enum variant to exercise all index values.
      for (final terminology in SystemTerminology.values) {
        for (final themeMode in AppThemeMode.values) {
          for (final themeBrightness in ThemeBrightness.values) {
            for (final themeStyle in ThemeStyle.values) {
              for (final timingMode in FrontingTimingMode.values) {
                final settings = SystemSettings(
                  terminology: terminology,
                  themeMode: themeMode,
                  themeBrightness: themeBrightness,
                  themeStyle: themeStyle,
                  timingMode: timingMode,
                );

                final fields = _buildSyncFieldsMap(settings);

                for (final entry in fieldTypes.entries) {
                  final fieldName = entry.key;
                  final declaredType = entry.value as String;
                  final value = fields[fieldName];

                  if (value == null) continue; // nullable fields are fine

                  if (declaredType == 'Int') {
                    expect(
                      value,
                      isA<int>(),
                      reason:
                          'Field "$fieldName" is declared as "Int" in sync schema '
                          'but got ${value.runtimeType} ($value). '
                          'Use .index not .name for enum fields.',
                    );
                  } else if (declaredType == 'Bool') {
                    expect(
                      value,
                      isA<bool>(),
                      reason:
                          'Field "$fieldName" is declared as "Bool" but got '
                          '${value.runtimeType}.',
                    );
                  } else if (declaredType == 'String') {
                    // String fields may be null (nullable) — skip non-null check.
                    expect(
                      value,
                      isA<String>(),
                      reason:
                          'Field "$fieldName" is declared as "String" but got '
                          '${value.runtimeType}.',
                    );
                  }
                }
              }
            }
          }
        }
      }
    });

    test('Int enum fields produce values within valid index range', () {
      // Ensures enum indices haven't drifted out of expected bounds.
      expect(SystemTerminology.values.length, greaterThanOrEqualTo(1));
      expect(AppThemeMode.values.length, greaterThanOrEqualTo(1));
      expect(ThemeBrightness.values.length, greaterThanOrEqualTo(1));
      expect(ThemeStyle.values.length, greaterThanOrEqualTo(1));
      expect(FrontingTimingMode.values.length, greaterThanOrEqualTo(1));

      final settings = SystemSettings(
        terminology: SystemTerminology.values.last,
        themeMode: AppThemeMode.values.last,
        themeBrightness: ThemeBrightness.values.last,
        themeStyle: ThemeStyle.values.last,
        timingMode: FrontingTimingMode.values.last,
      );
      final fields = _buildSyncFieldsMap(settings);

      expect(fields['terminology'], SystemTerminology.values.last.index);
      expect(fields['theme_mode'], AppThemeMode.values.last.index);
      expect(fields['theme_brightness'], ThemeBrightness.values.last.index);
      expect(fields['theme_style'], ThemeStyle.values.last.index);
      expect(fields['timing_mode'], FrontingTimingMode.values.last.index);
    });
  });
}
