// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SystemSettings _$SystemSettingsFromJson(
  Map<String, dynamic> json,
) => _SystemSettings(
  systemName: json['systemName'] as String?,
  sharingId: json['sharingId'] as String?,
  showQuickFront: json['showQuickFront'] as bool? ?? true,
  accentColorHex: json['accentColorHex'] as String? ?? '#AF8EE9',
  perMemberAccentColors: json['perMemberAccentColors'] as bool? ?? true,
  terminology:
      $enumDecodeNullable(_$SystemTerminologyEnumMap, json['terminology']) ??
      SystemTerminology.headmates,
  customTerminology: json['customTerminology'] as String?,
  customPluralTerminology: json['customPluralTerminology'] as String?,
  frontingRemindersEnabled: json['frontingRemindersEnabled'] as bool? ?? false,
  frontingReminderIntervalMinutes:
      (json['frontingReminderIntervalMinutes'] as num?)?.toInt() ?? 60,
  themeMode:
      $enumDecodeNullable(_$AppThemeModeEnumMap, json['themeMode']) ??
      AppThemeMode.system,
  themeBrightness:
      $enumDecodeNullable(_$ThemeBrightnessEnumMap, json['themeBrightness']) ??
      ThemeBrightness.system,
  themeStyle:
      $enumDecodeNullable(_$ThemeStyleEnumMap, json['themeStyle']) ??
      ThemeStyle.standard,
  cornerStyle:
      $enumDecodeNullable(_$CornerStyleEnumMap, json['cornerStyle']) ??
      CornerStyle.rounded,
  chatEnabled: json['chatEnabled'] as bool? ?? true,
  pollsEnabled: json['pollsEnabled'] as bool? ?? true,
  habitsEnabled: json['habitsEnabled'] as bool? ?? true,
  sleepTrackingEnabled: json['sleepTrackingEnabled'] as bool? ?? true,
  gifSearchEnabled: json['gifSearchEnabled'] as bool? ?? true,
  voiceNotesEnabled: json['voiceNotesEnabled'] as bool? ?? true,
  sleepSuggestionEnabled: json['sleepSuggestionEnabled'] as bool? ?? false,
  sleepSuggestionHour: (json['sleepSuggestionHour'] as num?)?.toInt() ?? 22,
  sleepSuggestionMinute: (json['sleepSuggestionMinute'] as num?)?.toInt() ?? 0,
  wakeSuggestionEnabled: json['wakeSuggestionEnabled'] as bool? ?? false,
  wakeSuggestionAfterHours:
      (json['wakeSuggestionAfterHours'] as num?)?.toDouble() ?? 8.0,
  quickSwitchThresholdSeconds:
      (json['quickSwitchThresholdSeconds'] as num?)?.toInt() ?? 30,
  identityGeneration: (json['identityGeneration'] as num?)?.toInt() ?? 0,
  chatLogsFront: json['chatLogsFront'] as bool? ?? false,
  terminologyUseEnglish: json['terminologyUseEnglish'] as bool? ?? false,
  hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
  syncThemeEnabled: json['syncThemeEnabled'] as bool? ?? false,
  habitsBadgeEnabled: json['habitsBadgeEnabled'] as bool? ?? true,
  timingMode:
      $enumDecodeNullable(_$FrontingTimingModeEnumMap, json['timingMode']) ??
      FrontingTimingMode.flexible,
  notesEnabled: json['notesEnabled'] as bool? ?? true,
  previousAccentColorHex: json['previousAccentColorHex'] as String? ?? '',
  systemDescription: json['systemDescription'] as String?,
  systemColor: json['systemColor'] as String?,
  systemTag: json['systemTag'] as String?,
  systemAvatarData: _uint8ListFromJson(json['systemAvatarData'] as String?),
  remindersEnabled: json['remindersEnabled'] as bool? ?? true,
  localeOverride: json['localeOverride'] as String?,
  gifConsentState:
      $enumDecodeNullable(_$GifConsentStateEnumMap, json['gifConsentState']) ??
      GifConsentState.unknown,
  fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
  fontFamily:
      $enumDecodeNullable(_$FontFamilyEnumMap, json['fontFamily']) ??
      FontFamily.system,
  pinLockEnabled: json['pinLockEnabled'] as bool? ?? false,
  biometricLockEnabled: json['biometricLockEnabled'] as bool? ?? false,
  autoLockDelaySeconds: (json['autoLockDelaySeconds'] as num?)?.toInt() ?? 0,
  displayFontInAppBar: json['displayFontInAppBar'] as bool? ?? true,
  navBarItems:
      (json['navBarItems'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  navBarOverflowItems:
      (json['navBarOverflowItems'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  syncNavigationEnabled: json['syncNavigationEnabled'] as bool? ?? true,
  chatBadgePreferences:
      (json['chatBadgePreferences'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const <String, String>{},
  defaultSleepQuality: $enumDecodeNullable(
    _$SleepQualityEnumMap,
    json['defaultSleepQuality'],
  ),
);

Map<String, dynamic> _$SystemSettingsToJson(
  _SystemSettings instance,
) => <String, dynamic>{
  'systemName': instance.systemName,
  'sharingId': instance.sharingId,
  'showQuickFront': instance.showQuickFront,
  'accentColorHex': instance.accentColorHex,
  'perMemberAccentColors': instance.perMemberAccentColors,
  'terminology': _$SystemTerminologyEnumMap[instance.terminology]!,
  'customTerminology': instance.customTerminology,
  'customPluralTerminology': instance.customPluralTerminology,
  'frontingRemindersEnabled': instance.frontingRemindersEnabled,
  'frontingReminderIntervalMinutes': instance.frontingReminderIntervalMinutes,
  'themeMode': _$AppThemeModeEnumMap[instance.themeMode]!,
  'themeBrightness': _$ThemeBrightnessEnumMap[instance.themeBrightness]!,
  'themeStyle': _$ThemeStyleEnumMap[instance.themeStyle]!,
  'cornerStyle': _$CornerStyleEnumMap[instance.cornerStyle]!,
  'chatEnabled': instance.chatEnabled,
  'pollsEnabled': instance.pollsEnabled,
  'habitsEnabled': instance.habitsEnabled,
  'sleepTrackingEnabled': instance.sleepTrackingEnabled,
  'gifSearchEnabled': instance.gifSearchEnabled,
  'voiceNotesEnabled': instance.voiceNotesEnabled,
  'sleepSuggestionEnabled': instance.sleepSuggestionEnabled,
  'sleepSuggestionHour': instance.sleepSuggestionHour,
  'sleepSuggestionMinute': instance.sleepSuggestionMinute,
  'wakeSuggestionEnabled': instance.wakeSuggestionEnabled,
  'wakeSuggestionAfterHours': instance.wakeSuggestionAfterHours,
  'quickSwitchThresholdSeconds': instance.quickSwitchThresholdSeconds,
  'identityGeneration': instance.identityGeneration,
  'chatLogsFront': instance.chatLogsFront,
  'terminologyUseEnglish': instance.terminologyUseEnglish,
  'hasCompletedOnboarding': instance.hasCompletedOnboarding,
  'syncThemeEnabled': instance.syncThemeEnabled,
  'habitsBadgeEnabled': instance.habitsBadgeEnabled,
  'timingMode': _$FrontingTimingModeEnumMap[instance.timingMode]!,
  'notesEnabled': instance.notesEnabled,
  'previousAccentColorHex': instance.previousAccentColorHex,
  'systemDescription': instance.systemDescription,
  'systemColor': instance.systemColor,
  'systemTag': instance.systemTag,
  'systemAvatarData': _uint8ListToJson(instance.systemAvatarData),
  'remindersEnabled': instance.remindersEnabled,
  'localeOverride': instance.localeOverride,
  'gifConsentState': _$GifConsentStateEnumMap[instance.gifConsentState]!,
  'fontScale': instance.fontScale,
  'fontFamily': _$FontFamilyEnumMap[instance.fontFamily]!,
  'pinLockEnabled': instance.pinLockEnabled,
  'biometricLockEnabled': instance.biometricLockEnabled,
  'autoLockDelaySeconds': instance.autoLockDelaySeconds,
  'displayFontInAppBar': instance.displayFontInAppBar,
  'navBarItems': instance.navBarItems,
  'navBarOverflowItems': instance.navBarOverflowItems,
  'syncNavigationEnabled': instance.syncNavigationEnabled,
  'chatBadgePreferences': instance.chatBadgePreferences,
  'defaultSleepQuality': _$SleepQualityEnumMap[instance.defaultSleepQuality],
};

const _$SystemTerminologyEnumMap = {
  SystemTerminology.members: 'members',
  SystemTerminology.headmates: 'headmates',
  SystemTerminology.alters: 'alters',
  SystemTerminology.parts: 'parts',
  SystemTerminology.facets: 'facets',
  SystemTerminology.custom: 'custom',
};

const _$AppThemeModeEnumMap = {
  AppThemeMode.system: 'system',
  AppThemeMode.light: 'light',
  AppThemeMode.dark: 'dark',
  AppThemeMode.oled: 'oled',
  AppThemeMode.materialYou: 'materialYou',
};

const _$ThemeBrightnessEnumMap = {
  ThemeBrightness.system: 'system',
  ThemeBrightness.light: 'light',
  ThemeBrightness.dark: 'dark',
};

const _$ThemeStyleEnumMap = {
  ThemeStyle.standard: 'standard',
  ThemeStyle.oled: 'oled',
  ThemeStyle.materialYou: 'materialYou',
};

const _$CornerStyleEnumMap = {
  CornerStyle.rounded: 'rounded',
  CornerStyle.angular: 'angular',
};

const _$FrontingTimingModeEnumMap = {
  FrontingTimingMode.flexible: 'flexible',
  FrontingTimingMode.strict: 'strict',
};

const _$GifConsentStateEnumMap = {
  GifConsentState.unknown: 'unknown',
  GifConsentState.enabled: 'enabled',
  GifConsentState.declined: 'declined',
};

const _$FontFamilyEnumMap = {
  FontFamily.system: 'system',
  FontFamily.openDyslexic: 'openDyslexic',
};

const _$SleepQualityEnumMap = {
  SleepQuality.unknown: 'unknown',
  SleepQuality.veryPoor: 'veryPoor',
  SleepQuality.poor: 'poor',
  SleepQuality.fair: 'fair',
  SleepQuality.good: 'good',
  SleepQuality.excellent: 'excellent',
};
