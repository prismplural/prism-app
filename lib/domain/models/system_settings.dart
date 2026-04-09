import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'system_settings.freezed.dart';
part 'system_settings.g.dart';

Uint8List? _uint8ListFromJson(String? json) =>
    json == null ? null : base64Decode(json);

String? _uint8ListToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);

/// Controls how strictly fronting session timing is validated.
enum FrontingTimingMode {
  flexible,
  strict;

  Duration get gapThreshold => switch (this) {
    FrontingTimingMode.flexible => const Duration(minutes: 5),
    FrontingTimingMode.strict => Duration.zero,
  };

  Duration get adjacentMergeThreshold => const Duration(seconds: 60);
}

/// Brightness preference (orthogonal to theme style).
enum ThemeBrightness {
  system,
  light,
  dark;

  String get displayName {
    return switch (this) {
      ThemeBrightness.system => 'System',
      ThemeBrightness.light => 'Light',
      ThemeBrightness.dark => 'Dark',
    };
  }
}

/// Visual style of the theme (orthogonal to brightness).
enum ThemeStyle {
  standard,
  oled,
  materialYou;

  String get displayName {
    return switch (this) {
      ThemeStyle.standard => 'Default',
      ThemeStyle.oled => 'OLED',
      ThemeStyle.materialYou => 'Material You',
    };
  }
}

/// Legacy enum kept for JSON backwards compatibility.
/// New code should use [ThemeBrightness] + [ThemeStyle] instead.
enum AppThemeMode {
  system,
  light,
  dark,
  oled,
  materialYou;

  String get displayName {
    return switch (this) {
      AppThemeMode.system => 'System',
      AppThemeMode.light => 'Light',
      AppThemeMode.dark => 'Dark',
      AppThemeMode.oled => 'OLED Dark',
      AppThemeMode.materialYou => 'Material You',
    };
  }
}

enum FontFamily {
  system,
  openDyslexic;

  String get displayName {
    return switch (this) {
      FontFamily.system => 'System',
      FontFamily.openDyslexic => 'Open Dyslexic',
    };
  }
}

enum SystemTerminology {
  members,
  headmates,
  alters,
  parts,
  facets,
  custom;

  /// The default singular form for this terminology option.
  String get singularForm {
    return switch (this) {
      SystemTerminology.members => 'Member',
      SystemTerminology.headmates => 'Headmate',
      SystemTerminology.alters => 'Alter',
      SystemTerminology.parts => 'Part',
      SystemTerminology.facets => 'Facet',
      SystemTerminology.custom => 'Member', // fallback; overridden by provider
    };
  }

  /// The default plural form for this terminology option.
  String get pluralForm {
    return switch (this) {
      SystemTerminology.members => 'Members',
      SystemTerminology.headmates => 'Headmates',
      SystemTerminology.alters => 'Alters',
      SystemTerminology.parts => 'Parts',
      SystemTerminology.facets => 'Facets',
      SystemTerminology.custom => 'Members', // fallback; overridden by provider
    };
  }
}

@freezed
abstract class SystemSettings with _$SystemSettings {
  const factory SystemSettings({
    String? systemName,
    String? sharingId,
    @Default(true) bool showQuickFront,
    @Default('#AF8EE9') String accentColorHex,
    @Default(true) bool perMemberAccentColors,
    @Default(SystemTerminology.headmates) SystemTerminology terminology,
    String? customTerminology,
    String? customPluralTerminology,
    @Default(false) bool frontingRemindersEnabled,
    @Default(60) int frontingReminderIntervalMinutes,
    // Legacy field — kept for JSON compat, no longer read by app.
    @Default(AppThemeMode.system) AppThemeMode themeMode,
    // New two-axis theme controls.
    @Default(ThemeBrightness.system) ThemeBrightness themeBrightness,
    @Default(ThemeStyle.standard) ThemeStyle themeStyle,
    @Default(true) bool chatEnabled,
    @Default(true) bool pollsEnabled,
    @Default(true) bool habitsEnabled,
    @Default(true) bool sleepTrackingEnabled,
    @Default(true) bool gifSearchEnabled,
    @Default(30) int quickSwitchThresholdSeconds,
    // Sharing identity generation — incremented on DEK rotation
    @Default(0) int identityGeneration,
    @Default(false) bool chatLogsFront,
    @Default(false) bool hasCompletedOnboarding,
    @Default(false) bool syncThemeEnabled,
    @Default(true) bool habitsBadgeEnabled,
    @Default(FrontingTimingMode.flexible) FrontingTimingMode timingMode,
    @Default(true) bool notesEnabled,
    @Default('') String previousAccentColorHex,
    // Phase 3: Synced settings
    String? systemDescription,
    @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)
    Uint8List? systemAvatarData,
    @Default(true) bool remindersEnabled,
    // Phase 3: Device-local settings
    @Default(1.0) double fontScale,
    @Default(FontFamily.system) FontFamily fontFamily,
    @Default(false) bool pinLockEnabled,
    @Default(false) bool biometricLockEnabled,
    @Default(0) int autoLockDelaySeconds,
    // Display font in home app bar (device-local)
    @Default(true) bool displayFontInAppBar,
    // Nav bar configuration (optionally synced)
    @Default(<String>[]) List<String> navBarItems,
    @Default(<String>[]) List<String> navBarOverflowItems,
    @Default(true) bool syncNavigationEnabled,
    // Chat badge preferences — memberId → 'all' | 'mentions_only'
    @Default(<String, String>{}) Map<String, String> chatBadgePreferences,
  }) = _SystemSettings;

  factory SystemSettings.fromJson(Map<String, dynamic> json) =>
      _$SystemSettingsFromJson(json);
}
