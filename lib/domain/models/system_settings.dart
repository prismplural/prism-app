import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SleepQuality;

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

/// Corner style preference for the UI (rounded vs angular).
///
/// Kept in the domain layer (Flutter-free) as the canonical DB/sync enum.
/// The shared UI enum [PrismShapes.cornerStyle] in prism_shapes.dart holds
/// the same values; Task 8 (UI) bridges between the two via index mapping.
enum CornerStyle {
  rounded,
  angular;

  String get displayName {
    return switch (this) {
      CornerStyle.rounded => 'Rounded',
      CornerStyle.angular => 'Angular',
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

enum GifConsentState { unknown, enabled, declined }

enum SystemTerminology { members, headmates, alters, parts, facets, custom }

/// Fronting Preferences 1B — default state of the home-screen session list.
///
/// `combinedPeriods` is the post-1A default: derived periods with avatar
/// stacks. `perMemberRows` shows one row per raw session.  `timeline`
/// renders the existing TimelineView in place of the list.
enum FrontingListViewMode { combinedPeriods, perMemberRows, timeline }

/// Fronting Preferences 1B — semantics of "start a front" on the
/// add-front sheet AND the quick-front tile.  `additive` joins the
/// member as a co-fronter; `replace` ends all currently-active fronts
/// before starting the new one (single atomic transaction).
enum FrontStartBehavior { additive, replace }

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
    @Default(CornerStyle.rounded) CornerStyle cornerStyle,
    @Default(true) bool chatEnabled,
    @Default(true) bool pollsEnabled,
    @Default(true) bool habitsEnabled,
    @Default(true) bool sleepTrackingEnabled,
    @Default(true) bool gifSearchEnabled,
    @Default(true) bool voiceNotesEnabled,
    @Default(false) bool sleepSuggestionEnabled,
    @Default(22) int sleepSuggestionHour,
    @Default(0) int sleepSuggestionMinute,
    @Default(false) bool wakeSuggestionEnabled,
    @Default(8.0) double wakeSuggestionAfterHours,
    @Default(30) int quickSwitchThresholdSeconds,
    // Sharing identity generation — incremented on DEK rotation
    @Default(0) int identityGeneration,
    @Default(false) bool chatLogsFront,
    @Default(false) bool terminologyUseEnglish,
    @Default(false) bool hasCompletedOnboarding,
    @Default(false) bool syncThemeEnabled,
    @Default(true) bool habitsBadgeEnabled,
    @Default(FrontingTimingMode.flexible) FrontingTimingMode timingMode,
    @Default(true) bool notesEnabled,
    @Default('') String previousAccentColorHex,
    // Phase 3: Synced settings
    String? systemDescription,
    String? systemColor,
    @Default(false) bool pkGroupSyncV2Enabled,
    /// Synced PluralKit system profile tag.
    String? systemTag,
    @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)
    Uint8List? systemAvatarData,
    @Default(true) bool remindersEnabled,
    String? localeOverride,
    // Phase 3: Device-local settings
    @Default(GifConsentState.unknown) GifConsentState gifConsentState,
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
    // Default sleep quality for new sleep sessions (device-local).
    // Null means no default (user is prompted each time).
    SleepQuality? defaultSleepQuality,
    // Phase 1B: fronting preferences (synced).
    @Default(FrontingListViewMode.combinedPeriods)
    FrontingListViewMode frontingListViewMode,
    @Default(FrontStartBehavior.additive)
    FrontStartBehavior addFrontDefaultBehavior,
    @Default(FrontStartBehavior.additive)
    FrontStartBehavior quickFrontDefaultBehavior,
  }) = _SystemSettings;

  factory SystemSettings.fromJson(Map<String, dynamic> json) =>
      _$SystemSettingsFromJson(json);
}
