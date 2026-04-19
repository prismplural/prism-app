// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'system_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SystemSettings {

 String? get systemName; String? get sharingId; bool get showQuickFront; String get accentColorHex; bool get perMemberAccentColors; SystemTerminology get terminology; String? get customTerminology; String? get customPluralTerminology; bool get frontingRemindersEnabled; int get frontingReminderIntervalMinutes;// Legacy field — kept for JSON compat, no longer read by app.
 AppThemeMode get themeMode;// New two-axis theme controls.
 ThemeBrightness get themeBrightness; ThemeStyle get themeStyle; CornerStyle get cornerStyle; bool get chatEnabled; bool get pollsEnabled; bool get habitsEnabled; bool get sleepTrackingEnabled; bool get gifSearchEnabled; bool get voiceNotesEnabled; bool get sleepSuggestionEnabled; int get sleepSuggestionHour; int get sleepSuggestionMinute; bool get wakeSuggestionEnabled; double get wakeSuggestionAfterHours; int get quickSwitchThresholdSeconds;// Sharing identity generation — incremented on DEK rotation
 int get identityGeneration; bool get chatLogsFront; bool get terminologyUseEnglish; bool get hasCompletedOnboarding; bool get syncThemeEnabled; bool get habitsBadgeEnabled; FrontingTimingMode get timingMode; bool get notesEnabled; String get previousAccentColorHex;// Phase 3: Synced settings
 String? get systemDescription; String? get systemColor;// Plan 04: synced PluralKit system profile tag.
 String? get systemTag;@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? get systemAvatarData; bool get remindersEnabled; String? get localeOverride;// Phase 3: Device-local settings
 GifConsentState get gifConsentState; double get fontScale; FontFamily get fontFamily; bool get pinLockEnabled; bool get biometricLockEnabled; int get autoLockDelaySeconds;// Display font in home app bar (device-local)
 bool get displayFontInAppBar;// Nav bar configuration (optionally synced)
 List<String> get navBarItems; List<String> get navBarOverflowItems; bool get syncNavigationEnabled;// Chat badge preferences — memberId → 'all' | 'mentions_only'
 Map<String, String> get chatBadgePreferences;
/// Create a copy of SystemSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemSettingsCopyWith<SystemSettings> get copyWith => _$SystemSettingsCopyWithImpl<SystemSettings>(this as SystemSettings, _$identity);

  /// Serializes this SystemSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemSettings&&(identical(other.systemName, systemName) || other.systemName == systemName)&&(identical(other.sharingId, sharingId) || other.sharingId == sharingId)&&(identical(other.showQuickFront, showQuickFront) || other.showQuickFront == showQuickFront)&&(identical(other.accentColorHex, accentColorHex) || other.accentColorHex == accentColorHex)&&(identical(other.perMemberAccentColors, perMemberAccentColors) || other.perMemberAccentColors == perMemberAccentColors)&&(identical(other.terminology, terminology) || other.terminology == terminology)&&(identical(other.customTerminology, customTerminology) || other.customTerminology == customTerminology)&&(identical(other.customPluralTerminology, customPluralTerminology) || other.customPluralTerminology == customPluralTerminology)&&(identical(other.frontingRemindersEnabled, frontingRemindersEnabled) || other.frontingRemindersEnabled == frontingRemindersEnabled)&&(identical(other.frontingReminderIntervalMinutes, frontingReminderIntervalMinutes) || other.frontingReminderIntervalMinutes == frontingReminderIntervalMinutes)&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode)&&(identical(other.themeBrightness, themeBrightness) || other.themeBrightness == themeBrightness)&&(identical(other.themeStyle, themeStyle) || other.themeStyle == themeStyle)&&(identical(other.cornerStyle, cornerStyle) || other.cornerStyle == cornerStyle)&&(identical(other.chatEnabled, chatEnabled) || other.chatEnabled == chatEnabled)&&(identical(other.pollsEnabled, pollsEnabled) || other.pollsEnabled == pollsEnabled)&&(identical(other.habitsEnabled, habitsEnabled) || other.habitsEnabled == habitsEnabled)&&(identical(other.sleepTrackingEnabled, sleepTrackingEnabled) || other.sleepTrackingEnabled == sleepTrackingEnabled)&&(identical(other.gifSearchEnabled, gifSearchEnabled) || other.gifSearchEnabled == gifSearchEnabled)&&(identical(other.voiceNotesEnabled, voiceNotesEnabled) || other.voiceNotesEnabled == voiceNotesEnabled)&&(identical(other.sleepSuggestionEnabled, sleepSuggestionEnabled) || other.sleepSuggestionEnabled == sleepSuggestionEnabled)&&(identical(other.sleepSuggestionHour, sleepSuggestionHour) || other.sleepSuggestionHour == sleepSuggestionHour)&&(identical(other.sleepSuggestionMinute, sleepSuggestionMinute) || other.sleepSuggestionMinute == sleepSuggestionMinute)&&(identical(other.wakeSuggestionEnabled, wakeSuggestionEnabled) || other.wakeSuggestionEnabled == wakeSuggestionEnabled)&&(identical(other.wakeSuggestionAfterHours, wakeSuggestionAfterHours) || other.wakeSuggestionAfterHours == wakeSuggestionAfterHours)&&(identical(other.quickSwitchThresholdSeconds, quickSwitchThresholdSeconds) || other.quickSwitchThresholdSeconds == quickSwitchThresholdSeconds)&&(identical(other.identityGeneration, identityGeneration) || other.identityGeneration == identityGeneration)&&(identical(other.chatLogsFront, chatLogsFront) || other.chatLogsFront == chatLogsFront)&&(identical(other.terminologyUseEnglish, terminologyUseEnglish) || other.terminologyUseEnglish == terminologyUseEnglish)&&(identical(other.hasCompletedOnboarding, hasCompletedOnboarding) || other.hasCompletedOnboarding == hasCompletedOnboarding)&&(identical(other.syncThemeEnabled, syncThemeEnabled) || other.syncThemeEnabled == syncThemeEnabled)&&(identical(other.habitsBadgeEnabled, habitsBadgeEnabled) || other.habitsBadgeEnabled == habitsBadgeEnabled)&&(identical(other.timingMode, timingMode) || other.timingMode == timingMode)&&(identical(other.notesEnabled, notesEnabled) || other.notesEnabled == notesEnabled)&&(identical(other.previousAccentColorHex, previousAccentColorHex) || other.previousAccentColorHex == previousAccentColorHex)&&(identical(other.systemDescription, systemDescription) || other.systemDescription == systemDescription)&&(identical(other.systemColor, systemColor) || other.systemColor == systemColor)&&(identical(other.systemTag, systemTag) || other.systemTag == systemTag)&&const DeepCollectionEquality().equals(other.systemAvatarData, systemAvatarData)&&(identical(other.remindersEnabled, remindersEnabled) || other.remindersEnabled == remindersEnabled)&&(identical(other.localeOverride, localeOverride) || other.localeOverride == localeOverride)&&(identical(other.gifConsentState, gifConsentState) || other.gifConsentState == gifConsentState)&&(identical(other.fontScale, fontScale) || other.fontScale == fontScale)&&(identical(other.fontFamily, fontFamily) || other.fontFamily == fontFamily)&&(identical(other.pinLockEnabled, pinLockEnabled) || other.pinLockEnabled == pinLockEnabled)&&(identical(other.biometricLockEnabled, biometricLockEnabled) || other.biometricLockEnabled == biometricLockEnabled)&&(identical(other.autoLockDelaySeconds, autoLockDelaySeconds) || other.autoLockDelaySeconds == autoLockDelaySeconds)&&(identical(other.displayFontInAppBar, displayFontInAppBar) || other.displayFontInAppBar == displayFontInAppBar)&&const DeepCollectionEquality().equals(other.navBarItems, navBarItems)&&const DeepCollectionEquality().equals(other.navBarOverflowItems, navBarOverflowItems)&&(identical(other.syncNavigationEnabled, syncNavigationEnabled) || other.syncNavigationEnabled == syncNavigationEnabled)&&const DeepCollectionEquality().equals(other.chatBadgePreferences, chatBadgePreferences));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,systemName,sharingId,showQuickFront,accentColorHex,perMemberAccentColors,terminology,customTerminology,customPluralTerminology,frontingRemindersEnabled,frontingReminderIntervalMinutes,themeMode,themeBrightness,themeStyle,cornerStyle,chatEnabled,pollsEnabled,habitsEnabled,sleepTrackingEnabled,gifSearchEnabled,voiceNotesEnabled,sleepSuggestionEnabled,sleepSuggestionHour,sleepSuggestionMinute,wakeSuggestionEnabled,wakeSuggestionAfterHours,quickSwitchThresholdSeconds,identityGeneration,chatLogsFront,terminologyUseEnglish,hasCompletedOnboarding,syncThemeEnabled,habitsBadgeEnabled,timingMode,notesEnabled,previousAccentColorHex,systemDescription,systemColor,systemTag,const DeepCollectionEquality().hash(systemAvatarData),remindersEnabled,localeOverride,gifConsentState,fontScale,fontFamily,pinLockEnabled,biometricLockEnabled,autoLockDelaySeconds,displayFontInAppBar,const DeepCollectionEquality().hash(navBarItems),const DeepCollectionEquality().hash(navBarOverflowItems),syncNavigationEnabled,const DeepCollectionEquality().hash(chatBadgePreferences)]);

@override
String toString() {
  return 'SystemSettings(systemName: $systemName, sharingId: $sharingId, showQuickFront: $showQuickFront, accentColorHex: $accentColorHex, perMemberAccentColors: $perMemberAccentColors, terminology: $terminology, customTerminology: $customTerminology, customPluralTerminology: $customPluralTerminology, frontingRemindersEnabled: $frontingRemindersEnabled, frontingReminderIntervalMinutes: $frontingReminderIntervalMinutes, themeMode: $themeMode, themeBrightness: $themeBrightness, themeStyle: $themeStyle, cornerStyle: $cornerStyle, chatEnabled: $chatEnabled, pollsEnabled: $pollsEnabled, habitsEnabled: $habitsEnabled, sleepTrackingEnabled: $sleepTrackingEnabled, gifSearchEnabled: $gifSearchEnabled, voiceNotesEnabled: $voiceNotesEnabled, sleepSuggestionEnabled: $sleepSuggestionEnabled, sleepSuggestionHour: $sleepSuggestionHour, sleepSuggestionMinute: $sleepSuggestionMinute, wakeSuggestionEnabled: $wakeSuggestionEnabled, wakeSuggestionAfterHours: $wakeSuggestionAfterHours, quickSwitchThresholdSeconds: $quickSwitchThresholdSeconds, identityGeneration: $identityGeneration, chatLogsFront: $chatLogsFront, terminologyUseEnglish: $terminologyUseEnglish, hasCompletedOnboarding: $hasCompletedOnboarding, syncThemeEnabled: $syncThemeEnabled, habitsBadgeEnabled: $habitsBadgeEnabled, timingMode: $timingMode, notesEnabled: $notesEnabled, previousAccentColorHex: $previousAccentColorHex, systemDescription: $systemDescription, systemColor: $systemColor, systemTag: $systemTag, systemAvatarData: $systemAvatarData, remindersEnabled: $remindersEnabled, localeOverride: $localeOverride, gifConsentState: $gifConsentState, fontScale: $fontScale, fontFamily: $fontFamily, pinLockEnabled: $pinLockEnabled, biometricLockEnabled: $biometricLockEnabled, autoLockDelaySeconds: $autoLockDelaySeconds, displayFontInAppBar: $displayFontInAppBar, navBarItems: $navBarItems, navBarOverflowItems: $navBarOverflowItems, syncNavigationEnabled: $syncNavigationEnabled, chatBadgePreferences: $chatBadgePreferences)';
}


}

/// @nodoc
abstract mixin class $SystemSettingsCopyWith<$Res>  {
  factory $SystemSettingsCopyWith(SystemSettings value, $Res Function(SystemSettings) _then) = _$SystemSettingsCopyWithImpl;
@useResult
$Res call({
 String? systemName, String? sharingId, bool showQuickFront, String accentColorHex, bool perMemberAccentColors, SystemTerminology terminology, String? customTerminology, String? customPluralTerminology, bool frontingRemindersEnabled, int frontingReminderIntervalMinutes, AppThemeMode themeMode, ThemeBrightness themeBrightness, ThemeStyle themeStyle, CornerStyle cornerStyle, bool chatEnabled, bool pollsEnabled, bool habitsEnabled, bool sleepTrackingEnabled, bool gifSearchEnabled, bool voiceNotesEnabled, bool sleepSuggestionEnabled, int sleepSuggestionHour, int sleepSuggestionMinute, bool wakeSuggestionEnabled, double wakeSuggestionAfterHours, int quickSwitchThresholdSeconds, int identityGeneration, bool chatLogsFront, bool terminologyUseEnglish, bool hasCompletedOnboarding, bool syncThemeEnabled, bool habitsBadgeEnabled, FrontingTimingMode timingMode, bool notesEnabled, String previousAccentColorHex, String? systemDescription, String? systemColor, String? systemTag,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? systemAvatarData, bool remindersEnabled, String? localeOverride, GifConsentState gifConsentState, double fontScale, FontFamily fontFamily, bool pinLockEnabled, bool biometricLockEnabled, int autoLockDelaySeconds, bool displayFontInAppBar, List<String> navBarItems, List<String> navBarOverflowItems, bool syncNavigationEnabled, Map<String, String> chatBadgePreferences
});




}
/// @nodoc
class _$SystemSettingsCopyWithImpl<$Res>
    implements $SystemSettingsCopyWith<$Res> {
  _$SystemSettingsCopyWithImpl(this._self, this._then);

  final SystemSettings _self;
  final $Res Function(SystemSettings) _then;

/// Create a copy of SystemSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? systemName = freezed,Object? sharingId = freezed,Object? showQuickFront = null,Object? accentColorHex = null,Object? perMemberAccentColors = null,Object? terminology = null,Object? customTerminology = freezed,Object? customPluralTerminology = freezed,Object? frontingRemindersEnabled = null,Object? frontingReminderIntervalMinutes = null,Object? themeMode = null,Object? themeBrightness = null,Object? themeStyle = null,Object? cornerStyle = null,Object? chatEnabled = null,Object? pollsEnabled = null,Object? habitsEnabled = null,Object? sleepTrackingEnabled = null,Object? gifSearchEnabled = null,Object? voiceNotesEnabled = null,Object? sleepSuggestionEnabled = null,Object? sleepSuggestionHour = null,Object? sleepSuggestionMinute = null,Object? wakeSuggestionEnabled = null,Object? wakeSuggestionAfterHours = null,Object? quickSwitchThresholdSeconds = null,Object? identityGeneration = null,Object? chatLogsFront = null,Object? terminologyUseEnglish = null,Object? hasCompletedOnboarding = null,Object? syncThemeEnabled = null,Object? habitsBadgeEnabled = null,Object? timingMode = null,Object? notesEnabled = null,Object? previousAccentColorHex = null,Object? systemDescription = freezed,Object? systemColor = freezed,Object? systemTag = freezed,Object? systemAvatarData = freezed,Object? remindersEnabled = null,Object? localeOverride = freezed,Object? gifConsentState = null,Object? fontScale = null,Object? fontFamily = null,Object? pinLockEnabled = null,Object? biometricLockEnabled = null,Object? autoLockDelaySeconds = null,Object? displayFontInAppBar = null,Object? navBarItems = null,Object? navBarOverflowItems = null,Object? syncNavigationEnabled = null,Object? chatBadgePreferences = null,}) {
  return _then(_self.copyWith(
systemName: freezed == systemName ? _self.systemName : systemName // ignore: cast_nullable_to_non_nullable
as String?,sharingId: freezed == sharingId ? _self.sharingId : sharingId // ignore: cast_nullable_to_non_nullable
as String?,showQuickFront: null == showQuickFront ? _self.showQuickFront : showQuickFront // ignore: cast_nullable_to_non_nullable
as bool,accentColorHex: null == accentColorHex ? _self.accentColorHex : accentColorHex // ignore: cast_nullable_to_non_nullable
as String,perMemberAccentColors: null == perMemberAccentColors ? _self.perMemberAccentColors : perMemberAccentColors // ignore: cast_nullable_to_non_nullable
as bool,terminology: null == terminology ? _self.terminology : terminology // ignore: cast_nullable_to_non_nullable
as SystemTerminology,customTerminology: freezed == customTerminology ? _self.customTerminology : customTerminology // ignore: cast_nullable_to_non_nullable
as String?,customPluralTerminology: freezed == customPluralTerminology ? _self.customPluralTerminology : customPluralTerminology // ignore: cast_nullable_to_non_nullable
as String?,frontingRemindersEnabled: null == frontingRemindersEnabled ? _self.frontingRemindersEnabled : frontingRemindersEnabled // ignore: cast_nullable_to_non_nullable
as bool,frontingReminderIntervalMinutes: null == frontingReminderIntervalMinutes ? _self.frontingReminderIntervalMinutes : frontingReminderIntervalMinutes // ignore: cast_nullable_to_non_nullable
as int,themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as AppThemeMode,themeBrightness: null == themeBrightness ? _self.themeBrightness : themeBrightness // ignore: cast_nullable_to_non_nullable
as ThemeBrightness,themeStyle: null == themeStyle ? _self.themeStyle : themeStyle // ignore: cast_nullable_to_non_nullable
as ThemeStyle,cornerStyle: null == cornerStyle ? _self.cornerStyle : cornerStyle // ignore: cast_nullable_to_non_nullable
as CornerStyle,chatEnabled: null == chatEnabled ? _self.chatEnabled : chatEnabled // ignore: cast_nullable_to_non_nullable
as bool,pollsEnabled: null == pollsEnabled ? _self.pollsEnabled : pollsEnabled // ignore: cast_nullable_to_non_nullable
as bool,habitsEnabled: null == habitsEnabled ? _self.habitsEnabled : habitsEnabled // ignore: cast_nullable_to_non_nullable
as bool,sleepTrackingEnabled: null == sleepTrackingEnabled ? _self.sleepTrackingEnabled : sleepTrackingEnabled // ignore: cast_nullable_to_non_nullable
as bool,gifSearchEnabled: null == gifSearchEnabled ? _self.gifSearchEnabled : gifSearchEnabled // ignore: cast_nullable_to_non_nullable
as bool,voiceNotesEnabled: null == voiceNotesEnabled ? _self.voiceNotesEnabled : voiceNotesEnabled // ignore: cast_nullable_to_non_nullable
as bool,sleepSuggestionEnabled: null == sleepSuggestionEnabled ? _self.sleepSuggestionEnabled : sleepSuggestionEnabled // ignore: cast_nullable_to_non_nullable
as bool,sleepSuggestionHour: null == sleepSuggestionHour ? _self.sleepSuggestionHour : sleepSuggestionHour // ignore: cast_nullable_to_non_nullable
as int,sleepSuggestionMinute: null == sleepSuggestionMinute ? _self.sleepSuggestionMinute : sleepSuggestionMinute // ignore: cast_nullable_to_non_nullable
as int,wakeSuggestionEnabled: null == wakeSuggestionEnabled ? _self.wakeSuggestionEnabled : wakeSuggestionEnabled // ignore: cast_nullable_to_non_nullable
as bool,wakeSuggestionAfterHours: null == wakeSuggestionAfterHours ? _self.wakeSuggestionAfterHours : wakeSuggestionAfterHours // ignore: cast_nullable_to_non_nullable
as double,quickSwitchThresholdSeconds: null == quickSwitchThresholdSeconds ? _self.quickSwitchThresholdSeconds : quickSwitchThresholdSeconds // ignore: cast_nullable_to_non_nullable
as int,identityGeneration: null == identityGeneration ? _self.identityGeneration : identityGeneration // ignore: cast_nullable_to_non_nullable
as int,chatLogsFront: null == chatLogsFront ? _self.chatLogsFront : chatLogsFront // ignore: cast_nullable_to_non_nullable
as bool,terminologyUseEnglish: null == terminologyUseEnglish ? _self.terminologyUseEnglish : terminologyUseEnglish // ignore: cast_nullable_to_non_nullable
as bool,hasCompletedOnboarding: null == hasCompletedOnboarding ? _self.hasCompletedOnboarding : hasCompletedOnboarding // ignore: cast_nullable_to_non_nullable
as bool,syncThemeEnabled: null == syncThemeEnabled ? _self.syncThemeEnabled : syncThemeEnabled // ignore: cast_nullable_to_non_nullable
as bool,habitsBadgeEnabled: null == habitsBadgeEnabled ? _self.habitsBadgeEnabled : habitsBadgeEnabled // ignore: cast_nullable_to_non_nullable
as bool,timingMode: null == timingMode ? _self.timingMode : timingMode // ignore: cast_nullable_to_non_nullable
as FrontingTimingMode,notesEnabled: null == notesEnabled ? _self.notesEnabled : notesEnabled // ignore: cast_nullable_to_non_nullable
as bool,previousAccentColorHex: null == previousAccentColorHex ? _self.previousAccentColorHex : previousAccentColorHex // ignore: cast_nullable_to_non_nullable
as String,systemDescription: freezed == systemDescription ? _self.systemDescription : systemDescription // ignore: cast_nullable_to_non_nullable
as String?,systemColor: freezed == systemColor ? _self.systemColor : systemColor // ignore: cast_nullable_to_non_nullable
as String?,systemTag: freezed == systemTag ? _self.systemTag : systemTag // ignore: cast_nullable_to_non_nullable
as String?,systemAvatarData: freezed == systemAvatarData ? _self.systemAvatarData : systemAvatarData // ignore: cast_nullable_to_non_nullable
as Uint8List?,remindersEnabled: null == remindersEnabled ? _self.remindersEnabled : remindersEnabled // ignore: cast_nullable_to_non_nullable
as bool,localeOverride: freezed == localeOverride ? _self.localeOverride : localeOverride // ignore: cast_nullable_to_non_nullable
as String?,gifConsentState: null == gifConsentState ? _self.gifConsentState : gifConsentState // ignore: cast_nullable_to_non_nullable
as GifConsentState,fontScale: null == fontScale ? _self.fontScale : fontScale // ignore: cast_nullable_to_non_nullable
as double,fontFamily: null == fontFamily ? _self.fontFamily : fontFamily // ignore: cast_nullable_to_non_nullable
as FontFamily,pinLockEnabled: null == pinLockEnabled ? _self.pinLockEnabled : pinLockEnabled // ignore: cast_nullable_to_non_nullable
as bool,biometricLockEnabled: null == biometricLockEnabled ? _self.biometricLockEnabled : biometricLockEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoLockDelaySeconds: null == autoLockDelaySeconds ? _self.autoLockDelaySeconds : autoLockDelaySeconds // ignore: cast_nullable_to_non_nullable
as int,displayFontInAppBar: null == displayFontInAppBar ? _self.displayFontInAppBar : displayFontInAppBar // ignore: cast_nullable_to_non_nullable
as bool,navBarItems: null == navBarItems ? _self.navBarItems : navBarItems // ignore: cast_nullable_to_non_nullable
as List<String>,navBarOverflowItems: null == navBarOverflowItems ? _self.navBarOverflowItems : navBarOverflowItems // ignore: cast_nullable_to_non_nullable
as List<String>,syncNavigationEnabled: null == syncNavigationEnabled ? _self.syncNavigationEnabled : syncNavigationEnabled // ignore: cast_nullable_to_non_nullable
as bool,chatBadgePreferences: null == chatBadgePreferences ? _self.chatBadgePreferences : chatBadgePreferences // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [SystemSettings].
extension SystemSettingsPatterns on SystemSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SystemSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SystemSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SystemSettings value)  $default,){
final _that = this;
switch (_that) {
case _SystemSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SystemSettings value)?  $default,){
final _that = this;
switch (_that) {
case _SystemSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? systemName,  String? sharingId,  bool showQuickFront,  String accentColorHex,  bool perMemberAccentColors,  SystemTerminology terminology,  String? customTerminology,  String? customPluralTerminology,  bool frontingRemindersEnabled,  int frontingReminderIntervalMinutes,  AppThemeMode themeMode,  ThemeBrightness themeBrightness,  ThemeStyle themeStyle,  CornerStyle cornerStyle,  bool chatEnabled,  bool pollsEnabled,  bool habitsEnabled,  bool sleepTrackingEnabled,  bool gifSearchEnabled,  bool voiceNotesEnabled,  bool sleepSuggestionEnabled,  int sleepSuggestionHour,  int sleepSuggestionMinute,  bool wakeSuggestionEnabled,  double wakeSuggestionAfterHours,  int quickSwitchThresholdSeconds,  int identityGeneration,  bool chatLogsFront,  bool terminologyUseEnglish,  bool hasCompletedOnboarding,  bool syncThemeEnabled,  bool habitsBadgeEnabled,  FrontingTimingMode timingMode,  bool notesEnabled,  String previousAccentColorHex,  String? systemDescription,  String? systemColor,  String? systemTag, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? systemAvatarData,  bool remindersEnabled,  String? localeOverride,  GifConsentState gifConsentState,  double fontScale,  FontFamily fontFamily,  bool pinLockEnabled,  bool biometricLockEnabled,  int autoLockDelaySeconds,  bool displayFontInAppBar,  List<String> navBarItems,  List<String> navBarOverflowItems,  bool syncNavigationEnabled,  Map<String, String> chatBadgePreferences)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SystemSettings() when $default != null:
return $default(_that.systemName,_that.sharingId,_that.showQuickFront,_that.accentColorHex,_that.perMemberAccentColors,_that.terminology,_that.customTerminology,_that.customPluralTerminology,_that.frontingRemindersEnabled,_that.frontingReminderIntervalMinutes,_that.themeMode,_that.themeBrightness,_that.themeStyle,_that.cornerStyle,_that.chatEnabled,_that.pollsEnabled,_that.habitsEnabled,_that.sleepTrackingEnabled,_that.gifSearchEnabled,_that.voiceNotesEnabled,_that.sleepSuggestionEnabled,_that.sleepSuggestionHour,_that.sleepSuggestionMinute,_that.wakeSuggestionEnabled,_that.wakeSuggestionAfterHours,_that.quickSwitchThresholdSeconds,_that.identityGeneration,_that.chatLogsFront,_that.terminologyUseEnglish,_that.hasCompletedOnboarding,_that.syncThemeEnabled,_that.habitsBadgeEnabled,_that.timingMode,_that.notesEnabled,_that.previousAccentColorHex,_that.systemDescription,_that.systemColor,_that.systemTag,_that.systemAvatarData,_that.remindersEnabled,_that.localeOverride,_that.gifConsentState,_that.fontScale,_that.fontFamily,_that.pinLockEnabled,_that.biometricLockEnabled,_that.autoLockDelaySeconds,_that.displayFontInAppBar,_that.navBarItems,_that.navBarOverflowItems,_that.syncNavigationEnabled,_that.chatBadgePreferences);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? systemName,  String? sharingId,  bool showQuickFront,  String accentColorHex,  bool perMemberAccentColors,  SystemTerminology terminology,  String? customTerminology,  String? customPluralTerminology,  bool frontingRemindersEnabled,  int frontingReminderIntervalMinutes,  AppThemeMode themeMode,  ThemeBrightness themeBrightness,  ThemeStyle themeStyle,  CornerStyle cornerStyle,  bool chatEnabled,  bool pollsEnabled,  bool habitsEnabled,  bool sleepTrackingEnabled,  bool gifSearchEnabled,  bool voiceNotesEnabled,  bool sleepSuggestionEnabled,  int sleepSuggestionHour,  int sleepSuggestionMinute,  bool wakeSuggestionEnabled,  double wakeSuggestionAfterHours,  int quickSwitchThresholdSeconds,  int identityGeneration,  bool chatLogsFront,  bool terminologyUseEnglish,  bool hasCompletedOnboarding,  bool syncThemeEnabled,  bool habitsBadgeEnabled,  FrontingTimingMode timingMode,  bool notesEnabled,  String previousAccentColorHex,  String? systemDescription,  String? systemColor,  String? systemTag, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? systemAvatarData,  bool remindersEnabled,  String? localeOverride,  GifConsentState gifConsentState,  double fontScale,  FontFamily fontFamily,  bool pinLockEnabled,  bool biometricLockEnabled,  int autoLockDelaySeconds,  bool displayFontInAppBar,  List<String> navBarItems,  List<String> navBarOverflowItems,  bool syncNavigationEnabled,  Map<String, String> chatBadgePreferences)  $default,) {final _that = this;
switch (_that) {
case _SystemSettings():
return $default(_that.systemName,_that.sharingId,_that.showQuickFront,_that.accentColorHex,_that.perMemberAccentColors,_that.terminology,_that.customTerminology,_that.customPluralTerminology,_that.frontingRemindersEnabled,_that.frontingReminderIntervalMinutes,_that.themeMode,_that.themeBrightness,_that.themeStyle,_that.cornerStyle,_that.chatEnabled,_that.pollsEnabled,_that.habitsEnabled,_that.sleepTrackingEnabled,_that.gifSearchEnabled,_that.voiceNotesEnabled,_that.sleepSuggestionEnabled,_that.sleepSuggestionHour,_that.sleepSuggestionMinute,_that.wakeSuggestionEnabled,_that.wakeSuggestionAfterHours,_that.quickSwitchThresholdSeconds,_that.identityGeneration,_that.chatLogsFront,_that.terminologyUseEnglish,_that.hasCompletedOnboarding,_that.syncThemeEnabled,_that.habitsBadgeEnabled,_that.timingMode,_that.notesEnabled,_that.previousAccentColorHex,_that.systemDescription,_that.systemColor,_that.systemTag,_that.systemAvatarData,_that.remindersEnabled,_that.localeOverride,_that.gifConsentState,_that.fontScale,_that.fontFamily,_that.pinLockEnabled,_that.biometricLockEnabled,_that.autoLockDelaySeconds,_that.displayFontInAppBar,_that.navBarItems,_that.navBarOverflowItems,_that.syncNavigationEnabled,_that.chatBadgePreferences);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? systemName,  String? sharingId,  bool showQuickFront,  String accentColorHex,  bool perMemberAccentColors,  SystemTerminology terminology,  String? customTerminology,  String? customPluralTerminology,  bool frontingRemindersEnabled,  int frontingReminderIntervalMinutes,  AppThemeMode themeMode,  ThemeBrightness themeBrightness,  ThemeStyle themeStyle,  CornerStyle cornerStyle,  bool chatEnabled,  bool pollsEnabled,  bool habitsEnabled,  bool sleepTrackingEnabled,  bool gifSearchEnabled,  bool voiceNotesEnabled,  bool sleepSuggestionEnabled,  int sleepSuggestionHour,  int sleepSuggestionMinute,  bool wakeSuggestionEnabled,  double wakeSuggestionAfterHours,  int quickSwitchThresholdSeconds,  int identityGeneration,  bool chatLogsFront,  bool terminologyUseEnglish,  bool hasCompletedOnboarding,  bool syncThemeEnabled,  bool habitsBadgeEnabled,  FrontingTimingMode timingMode,  bool notesEnabled,  String previousAccentColorHex,  String? systemDescription,  String? systemColor,  String? systemTag, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson)  Uint8List? systemAvatarData,  bool remindersEnabled,  String? localeOverride,  GifConsentState gifConsentState,  double fontScale,  FontFamily fontFamily,  bool pinLockEnabled,  bool biometricLockEnabled,  int autoLockDelaySeconds,  bool displayFontInAppBar,  List<String> navBarItems,  List<String> navBarOverflowItems,  bool syncNavigationEnabled,  Map<String, String> chatBadgePreferences)?  $default,) {final _that = this;
switch (_that) {
case _SystemSettings() when $default != null:
return $default(_that.systemName,_that.sharingId,_that.showQuickFront,_that.accentColorHex,_that.perMemberAccentColors,_that.terminology,_that.customTerminology,_that.customPluralTerminology,_that.frontingRemindersEnabled,_that.frontingReminderIntervalMinutes,_that.themeMode,_that.themeBrightness,_that.themeStyle,_that.cornerStyle,_that.chatEnabled,_that.pollsEnabled,_that.habitsEnabled,_that.sleepTrackingEnabled,_that.gifSearchEnabled,_that.voiceNotesEnabled,_that.sleepSuggestionEnabled,_that.sleepSuggestionHour,_that.sleepSuggestionMinute,_that.wakeSuggestionEnabled,_that.wakeSuggestionAfterHours,_that.quickSwitchThresholdSeconds,_that.identityGeneration,_that.chatLogsFront,_that.terminologyUseEnglish,_that.hasCompletedOnboarding,_that.syncThemeEnabled,_that.habitsBadgeEnabled,_that.timingMode,_that.notesEnabled,_that.previousAccentColorHex,_that.systemDescription,_that.systemColor,_that.systemTag,_that.systemAvatarData,_that.remindersEnabled,_that.localeOverride,_that.gifConsentState,_that.fontScale,_that.fontFamily,_that.pinLockEnabled,_that.biometricLockEnabled,_that.autoLockDelaySeconds,_that.displayFontInAppBar,_that.navBarItems,_that.navBarOverflowItems,_that.syncNavigationEnabled,_that.chatBadgePreferences);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SystemSettings implements SystemSettings {
  const _SystemSettings({this.systemName, this.sharingId, this.showQuickFront = true, this.accentColorHex = '#AF8EE9', this.perMemberAccentColors = true, this.terminology = SystemTerminology.headmates, this.customTerminology, this.customPluralTerminology, this.frontingRemindersEnabled = false, this.frontingReminderIntervalMinutes = 60, this.themeMode = AppThemeMode.system, this.themeBrightness = ThemeBrightness.system, this.themeStyle = ThemeStyle.standard, this.cornerStyle = CornerStyle.rounded, this.chatEnabled = true, this.pollsEnabled = true, this.habitsEnabled = true, this.sleepTrackingEnabled = true, this.gifSearchEnabled = true, this.voiceNotesEnabled = true, this.sleepSuggestionEnabled = false, this.sleepSuggestionHour = 22, this.sleepSuggestionMinute = 0, this.wakeSuggestionEnabled = false, this.wakeSuggestionAfterHours = 8.0, this.quickSwitchThresholdSeconds = 30, this.identityGeneration = 0, this.chatLogsFront = false, this.terminologyUseEnglish = false, this.hasCompletedOnboarding = false, this.syncThemeEnabled = false, this.habitsBadgeEnabled = true, this.timingMode = FrontingTimingMode.flexible, this.notesEnabled = true, this.previousAccentColorHex = '', this.systemDescription, this.systemColor, this.systemTag, @JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) this.systemAvatarData, this.remindersEnabled = true, this.localeOverride, this.gifConsentState = GifConsentState.unknown, this.fontScale = 1.0, this.fontFamily = FontFamily.system, this.pinLockEnabled = false, this.biometricLockEnabled = false, this.autoLockDelaySeconds = 0, this.displayFontInAppBar = true, final  List<String> navBarItems = const <String>[], final  List<String> navBarOverflowItems = const <String>[], this.syncNavigationEnabled = true, final  Map<String, String> chatBadgePreferences = const <String, String>{}}): _navBarItems = navBarItems,_navBarOverflowItems = navBarOverflowItems,_chatBadgePreferences = chatBadgePreferences;
  factory _SystemSettings.fromJson(Map<String, dynamic> json) => _$SystemSettingsFromJson(json);

@override final  String? systemName;
@override final  String? sharingId;
@override@JsonKey() final  bool showQuickFront;
@override@JsonKey() final  String accentColorHex;
@override@JsonKey() final  bool perMemberAccentColors;
@override@JsonKey() final  SystemTerminology terminology;
@override final  String? customTerminology;
@override final  String? customPluralTerminology;
@override@JsonKey() final  bool frontingRemindersEnabled;
@override@JsonKey() final  int frontingReminderIntervalMinutes;
// Legacy field — kept for JSON compat, no longer read by app.
@override@JsonKey() final  AppThemeMode themeMode;
// New two-axis theme controls.
@override@JsonKey() final  ThemeBrightness themeBrightness;
@override@JsonKey() final  ThemeStyle themeStyle;
@override@JsonKey() final  CornerStyle cornerStyle;
@override@JsonKey() final  bool chatEnabled;
@override@JsonKey() final  bool pollsEnabled;
@override@JsonKey() final  bool habitsEnabled;
@override@JsonKey() final  bool sleepTrackingEnabled;
@override@JsonKey() final  bool gifSearchEnabled;
@override@JsonKey() final  bool voiceNotesEnabled;
@override@JsonKey() final  bool sleepSuggestionEnabled;
@override@JsonKey() final  int sleepSuggestionHour;
@override@JsonKey() final  int sleepSuggestionMinute;
@override@JsonKey() final  bool wakeSuggestionEnabled;
@override@JsonKey() final  double wakeSuggestionAfterHours;
@override@JsonKey() final  int quickSwitchThresholdSeconds;
// Sharing identity generation — incremented on DEK rotation
@override@JsonKey() final  int identityGeneration;
@override@JsonKey() final  bool chatLogsFront;
@override@JsonKey() final  bool terminologyUseEnglish;
@override@JsonKey() final  bool hasCompletedOnboarding;
@override@JsonKey() final  bool syncThemeEnabled;
@override@JsonKey() final  bool habitsBadgeEnabled;
@override@JsonKey() final  FrontingTimingMode timingMode;
@override@JsonKey() final  bool notesEnabled;
@override@JsonKey() final  String previousAccentColorHex;
// Phase 3: Synced settings
@override final  String? systemDescription;
@override final  String? systemColor;
// Plan 04: synced PluralKit system profile tag.
@override final  String? systemTag;
@override@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) final  Uint8List? systemAvatarData;
@override@JsonKey() final  bool remindersEnabled;
@override final  String? localeOverride;
// Phase 3: Device-local settings
@override@JsonKey() final  GifConsentState gifConsentState;
@override@JsonKey() final  double fontScale;
@override@JsonKey() final  FontFamily fontFamily;
@override@JsonKey() final  bool pinLockEnabled;
@override@JsonKey() final  bool biometricLockEnabled;
@override@JsonKey() final  int autoLockDelaySeconds;
// Display font in home app bar (device-local)
@override@JsonKey() final  bool displayFontInAppBar;
// Nav bar configuration (optionally synced)
 final  List<String> _navBarItems;
// Nav bar configuration (optionally synced)
@override@JsonKey() List<String> get navBarItems {
  if (_navBarItems is EqualUnmodifiableListView) return _navBarItems;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_navBarItems);
}

 final  List<String> _navBarOverflowItems;
@override@JsonKey() List<String> get navBarOverflowItems {
  if (_navBarOverflowItems is EqualUnmodifiableListView) return _navBarOverflowItems;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_navBarOverflowItems);
}

@override@JsonKey() final  bool syncNavigationEnabled;
// Chat badge preferences — memberId → 'all' | 'mentions_only'
 final  Map<String, String> _chatBadgePreferences;
// Chat badge preferences — memberId → 'all' | 'mentions_only'
@override@JsonKey() Map<String, String> get chatBadgePreferences {
  if (_chatBadgePreferences is EqualUnmodifiableMapView) return _chatBadgePreferences;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_chatBadgePreferences);
}


/// Create a copy of SystemSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SystemSettingsCopyWith<_SystemSettings> get copyWith => __$SystemSettingsCopyWithImpl<_SystemSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SystemSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SystemSettings&&(identical(other.systemName, systemName) || other.systemName == systemName)&&(identical(other.sharingId, sharingId) || other.sharingId == sharingId)&&(identical(other.showQuickFront, showQuickFront) || other.showQuickFront == showQuickFront)&&(identical(other.accentColorHex, accentColorHex) || other.accentColorHex == accentColorHex)&&(identical(other.perMemberAccentColors, perMemberAccentColors) || other.perMemberAccentColors == perMemberAccentColors)&&(identical(other.terminology, terminology) || other.terminology == terminology)&&(identical(other.customTerminology, customTerminology) || other.customTerminology == customTerminology)&&(identical(other.customPluralTerminology, customPluralTerminology) || other.customPluralTerminology == customPluralTerminology)&&(identical(other.frontingRemindersEnabled, frontingRemindersEnabled) || other.frontingRemindersEnabled == frontingRemindersEnabled)&&(identical(other.frontingReminderIntervalMinutes, frontingReminderIntervalMinutes) || other.frontingReminderIntervalMinutes == frontingReminderIntervalMinutes)&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode)&&(identical(other.themeBrightness, themeBrightness) || other.themeBrightness == themeBrightness)&&(identical(other.themeStyle, themeStyle) || other.themeStyle == themeStyle)&&(identical(other.cornerStyle, cornerStyle) || other.cornerStyle == cornerStyle)&&(identical(other.chatEnabled, chatEnabled) || other.chatEnabled == chatEnabled)&&(identical(other.pollsEnabled, pollsEnabled) || other.pollsEnabled == pollsEnabled)&&(identical(other.habitsEnabled, habitsEnabled) || other.habitsEnabled == habitsEnabled)&&(identical(other.sleepTrackingEnabled, sleepTrackingEnabled) || other.sleepTrackingEnabled == sleepTrackingEnabled)&&(identical(other.gifSearchEnabled, gifSearchEnabled) || other.gifSearchEnabled == gifSearchEnabled)&&(identical(other.voiceNotesEnabled, voiceNotesEnabled) || other.voiceNotesEnabled == voiceNotesEnabled)&&(identical(other.sleepSuggestionEnabled, sleepSuggestionEnabled) || other.sleepSuggestionEnabled == sleepSuggestionEnabled)&&(identical(other.sleepSuggestionHour, sleepSuggestionHour) || other.sleepSuggestionHour == sleepSuggestionHour)&&(identical(other.sleepSuggestionMinute, sleepSuggestionMinute) || other.sleepSuggestionMinute == sleepSuggestionMinute)&&(identical(other.wakeSuggestionEnabled, wakeSuggestionEnabled) || other.wakeSuggestionEnabled == wakeSuggestionEnabled)&&(identical(other.wakeSuggestionAfterHours, wakeSuggestionAfterHours) || other.wakeSuggestionAfterHours == wakeSuggestionAfterHours)&&(identical(other.quickSwitchThresholdSeconds, quickSwitchThresholdSeconds) || other.quickSwitchThresholdSeconds == quickSwitchThresholdSeconds)&&(identical(other.identityGeneration, identityGeneration) || other.identityGeneration == identityGeneration)&&(identical(other.chatLogsFront, chatLogsFront) || other.chatLogsFront == chatLogsFront)&&(identical(other.terminologyUseEnglish, terminologyUseEnglish) || other.terminologyUseEnglish == terminologyUseEnglish)&&(identical(other.hasCompletedOnboarding, hasCompletedOnboarding) || other.hasCompletedOnboarding == hasCompletedOnboarding)&&(identical(other.syncThemeEnabled, syncThemeEnabled) || other.syncThemeEnabled == syncThemeEnabled)&&(identical(other.habitsBadgeEnabled, habitsBadgeEnabled) || other.habitsBadgeEnabled == habitsBadgeEnabled)&&(identical(other.timingMode, timingMode) || other.timingMode == timingMode)&&(identical(other.notesEnabled, notesEnabled) || other.notesEnabled == notesEnabled)&&(identical(other.previousAccentColorHex, previousAccentColorHex) || other.previousAccentColorHex == previousAccentColorHex)&&(identical(other.systemDescription, systemDescription) || other.systemDescription == systemDescription)&&(identical(other.systemColor, systemColor) || other.systemColor == systemColor)&&(identical(other.systemTag, systemTag) || other.systemTag == systemTag)&&const DeepCollectionEquality().equals(other.systemAvatarData, systemAvatarData)&&(identical(other.remindersEnabled, remindersEnabled) || other.remindersEnabled == remindersEnabled)&&(identical(other.localeOverride, localeOverride) || other.localeOverride == localeOverride)&&(identical(other.gifConsentState, gifConsentState) || other.gifConsentState == gifConsentState)&&(identical(other.fontScale, fontScale) || other.fontScale == fontScale)&&(identical(other.fontFamily, fontFamily) || other.fontFamily == fontFamily)&&(identical(other.pinLockEnabled, pinLockEnabled) || other.pinLockEnabled == pinLockEnabled)&&(identical(other.biometricLockEnabled, biometricLockEnabled) || other.biometricLockEnabled == biometricLockEnabled)&&(identical(other.autoLockDelaySeconds, autoLockDelaySeconds) || other.autoLockDelaySeconds == autoLockDelaySeconds)&&(identical(other.displayFontInAppBar, displayFontInAppBar) || other.displayFontInAppBar == displayFontInAppBar)&&const DeepCollectionEquality().equals(other._navBarItems, _navBarItems)&&const DeepCollectionEquality().equals(other._navBarOverflowItems, _navBarOverflowItems)&&(identical(other.syncNavigationEnabled, syncNavigationEnabled) || other.syncNavigationEnabled == syncNavigationEnabled)&&const DeepCollectionEquality().equals(other._chatBadgePreferences, _chatBadgePreferences));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,systemName,sharingId,showQuickFront,accentColorHex,perMemberAccentColors,terminology,customTerminology,customPluralTerminology,frontingRemindersEnabled,frontingReminderIntervalMinutes,themeMode,themeBrightness,themeStyle,cornerStyle,chatEnabled,pollsEnabled,habitsEnabled,sleepTrackingEnabled,gifSearchEnabled,voiceNotesEnabled,sleepSuggestionEnabled,sleepSuggestionHour,sleepSuggestionMinute,wakeSuggestionEnabled,wakeSuggestionAfterHours,quickSwitchThresholdSeconds,identityGeneration,chatLogsFront,terminologyUseEnglish,hasCompletedOnboarding,syncThemeEnabled,habitsBadgeEnabled,timingMode,notesEnabled,previousAccentColorHex,systemDescription,systemColor,systemTag,const DeepCollectionEquality().hash(systemAvatarData),remindersEnabled,localeOverride,gifConsentState,fontScale,fontFamily,pinLockEnabled,biometricLockEnabled,autoLockDelaySeconds,displayFontInAppBar,const DeepCollectionEquality().hash(_navBarItems),const DeepCollectionEquality().hash(_navBarOverflowItems),syncNavigationEnabled,const DeepCollectionEquality().hash(_chatBadgePreferences)]);

@override
String toString() {
  return 'SystemSettings(systemName: $systemName, sharingId: $sharingId, showQuickFront: $showQuickFront, accentColorHex: $accentColorHex, perMemberAccentColors: $perMemberAccentColors, terminology: $terminology, customTerminology: $customTerminology, customPluralTerminology: $customPluralTerminology, frontingRemindersEnabled: $frontingRemindersEnabled, frontingReminderIntervalMinutes: $frontingReminderIntervalMinutes, themeMode: $themeMode, themeBrightness: $themeBrightness, themeStyle: $themeStyle, cornerStyle: $cornerStyle, chatEnabled: $chatEnabled, pollsEnabled: $pollsEnabled, habitsEnabled: $habitsEnabled, sleepTrackingEnabled: $sleepTrackingEnabled, gifSearchEnabled: $gifSearchEnabled, voiceNotesEnabled: $voiceNotesEnabled, sleepSuggestionEnabled: $sleepSuggestionEnabled, sleepSuggestionHour: $sleepSuggestionHour, sleepSuggestionMinute: $sleepSuggestionMinute, wakeSuggestionEnabled: $wakeSuggestionEnabled, wakeSuggestionAfterHours: $wakeSuggestionAfterHours, quickSwitchThresholdSeconds: $quickSwitchThresholdSeconds, identityGeneration: $identityGeneration, chatLogsFront: $chatLogsFront, terminologyUseEnglish: $terminologyUseEnglish, hasCompletedOnboarding: $hasCompletedOnboarding, syncThemeEnabled: $syncThemeEnabled, habitsBadgeEnabled: $habitsBadgeEnabled, timingMode: $timingMode, notesEnabled: $notesEnabled, previousAccentColorHex: $previousAccentColorHex, systemDescription: $systemDescription, systemColor: $systemColor, systemTag: $systemTag, systemAvatarData: $systemAvatarData, remindersEnabled: $remindersEnabled, localeOverride: $localeOverride, gifConsentState: $gifConsentState, fontScale: $fontScale, fontFamily: $fontFamily, pinLockEnabled: $pinLockEnabled, biometricLockEnabled: $biometricLockEnabled, autoLockDelaySeconds: $autoLockDelaySeconds, displayFontInAppBar: $displayFontInAppBar, navBarItems: $navBarItems, navBarOverflowItems: $navBarOverflowItems, syncNavigationEnabled: $syncNavigationEnabled, chatBadgePreferences: $chatBadgePreferences)';
}


}

/// @nodoc
abstract mixin class _$SystemSettingsCopyWith<$Res> implements $SystemSettingsCopyWith<$Res> {
  factory _$SystemSettingsCopyWith(_SystemSettings value, $Res Function(_SystemSettings) _then) = __$SystemSettingsCopyWithImpl;
@override @useResult
$Res call({
 String? systemName, String? sharingId, bool showQuickFront, String accentColorHex, bool perMemberAccentColors, SystemTerminology terminology, String? customTerminology, String? customPluralTerminology, bool frontingRemindersEnabled, int frontingReminderIntervalMinutes, AppThemeMode themeMode, ThemeBrightness themeBrightness, ThemeStyle themeStyle, CornerStyle cornerStyle, bool chatEnabled, bool pollsEnabled, bool habitsEnabled, bool sleepTrackingEnabled, bool gifSearchEnabled, bool voiceNotesEnabled, bool sleepSuggestionEnabled, int sleepSuggestionHour, int sleepSuggestionMinute, bool wakeSuggestionEnabled, double wakeSuggestionAfterHours, int quickSwitchThresholdSeconds, int identityGeneration, bool chatLogsFront, bool terminologyUseEnglish, bool hasCompletedOnboarding, bool syncThemeEnabled, bool habitsBadgeEnabled, FrontingTimingMode timingMode, bool notesEnabled, String previousAccentColorHex, String? systemDescription, String? systemColor, String? systemTag,@JsonKey(fromJson: _uint8ListFromJson, toJson: _uint8ListToJson) Uint8List? systemAvatarData, bool remindersEnabled, String? localeOverride, GifConsentState gifConsentState, double fontScale, FontFamily fontFamily, bool pinLockEnabled, bool biometricLockEnabled, int autoLockDelaySeconds, bool displayFontInAppBar, List<String> navBarItems, List<String> navBarOverflowItems, bool syncNavigationEnabled, Map<String, String> chatBadgePreferences
});




}
/// @nodoc
class __$SystemSettingsCopyWithImpl<$Res>
    implements _$SystemSettingsCopyWith<$Res> {
  __$SystemSettingsCopyWithImpl(this._self, this._then);

  final _SystemSettings _self;
  final $Res Function(_SystemSettings) _then;

/// Create a copy of SystemSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? systemName = freezed,Object? sharingId = freezed,Object? showQuickFront = null,Object? accentColorHex = null,Object? perMemberAccentColors = null,Object? terminology = null,Object? customTerminology = freezed,Object? customPluralTerminology = freezed,Object? frontingRemindersEnabled = null,Object? frontingReminderIntervalMinutes = null,Object? themeMode = null,Object? themeBrightness = null,Object? themeStyle = null,Object? cornerStyle = null,Object? chatEnabled = null,Object? pollsEnabled = null,Object? habitsEnabled = null,Object? sleepTrackingEnabled = null,Object? gifSearchEnabled = null,Object? voiceNotesEnabled = null,Object? sleepSuggestionEnabled = null,Object? sleepSuggestionHour = null,Object? sleepSuggestionMinute = null,Object? wakeSuggestionEnabled = null,Object? wakeSuggestionAfterHours = null,Object? quickSwitchThresholdSeconds = null,Object? identityGeneration = null,Object? chatLogsFront = null,Object? terminologyUseEnglish = null,Object? hasCompletedOnboarding = null,Object? syncThemeEnabled = null,Object? habitsBadgeEnabled = null,Object? timingMode = null,Object? notesEnabled = null,Object? previousAccentColorHex = null,Object? systemDescription = freezed,Object? systemColor = freezed,Object? systemTag = freezed,Object? systemAvatarData = freezed,Object? remindersEnabled = null,Object? localeOverride = freezed,Object? gifConsentState = null,Object? fontScale = null,Object? fontFamily = null,Object? pinLockEnabled = null,Object? biometricLockEnabled = null,Object? autoLockDelaySeconds = null,Object? displayFontInAppBar = null,Object? navBarItems = null,Object? navBarOverflowItems = null,Object? syncNavigationEnabled = null,Object? chatBadgePreferences = null,}) {
  return _then(_SystemSettings(
systemName: freezed == systemName ? _self.systemName : systemName // ignore: cast_nullable_to_non_nullable
as String?,sharingId: freezed == sharingId ? _self.sharingId : sharingId // ignore: cast_nullable_to_non_nullable
as String?,showQuickFront: null == showQuickFront ? _self.showQuickFront : showQuickFront // ignore: cast_nullable_to_non_nullable
as bool,accentColorHex: null == accentColorHex ? _self.accentColorHex : accentColorHex // ignore: cast_nullable_to_non_nullable
as String,perMemberAccentColors: null == perMemberAccentColors ? _self.perMemberAccentColors : perMemberAccentColors // ignore: cast_nullable_to_non_nullable
as bool,terminology: null == terminology ? _self.terminology : terminology // ignore: cast_nullable_to_non_nullable
as SystemTerminology,customTerminology: freezed == customTerminology ? _self.customTerminology : customTerminology // ignore: cast_nullable_to_non_nullable
as String?,customPluralTerminology: freezed == customPluralTerminology ? _self.customPluralTerminology : customPluralTerminology // ignore: cast_nullable_to_non_nullable
as String?,frontingRemindersEnabled: null == frontingRemindersEnabled ? _self.frontingRemindersEnabled : frontingRemindersEnabled // ignore: cast_nullable_to_non_nullable
as bool,frontingReminderIntervalMinutes: null == frontingReminderIntervalMinutes ? _self.frontingReminderIntervalMinutes : frontingReminderIntervalMinutes // ignore: cast_nullable_to_non_nullable
as int,themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as AppThemeMode,themeBrightness: null == themeBrightness ? _self.themeBrightness : themeBrightness // ignore: cast_nullable_to_non_nullable
as ThemeBrightness,themeStyle: null == themeStyle ? _self.themeStyle : themeStyle // ignore: cast_nullable_to_non_nullable
as ThemeStyle,cornerStyle: null == cornerStyle ? _self.cornerStyle : cornerStyle // ignore: cast_nullable_to_non_nullable
as CornerStyle,chatEnabled: null == chatEnabled ? _self.chatEnabled : chatEnabled // ignore: cast_nullable_to_non_nullable
as bool,pollsEnabled: null == pollsEnabled ? _self.pollsEnabled : pollsEnabled // ignore: cast_nullable_to_non_nullable
as bool,habitsEnabled: null == habitsEnabled ? _self.habitsEnabled : habitsEnabled // ignore: cast_nullable_to_non_nullable
as bool,sleepTrackingEnabled: null == sleepTrackingEnabled ? _self.sleepTrackingEnabled : sleepTrackingEnabled // ignore: cast_nullable_to_non_nullable
as bool,gifSearchEnabled: null == gifSearchEnabled ? _self.gifSearchEnabled : gifSearchEnabled // ignore: cast_nullable_to_non_nullable
as bool,voiceNotesEnabled: null == voiceNotesEnabled ? _self.voiceNotesEnabled : voiceNotesEnabled // ignore: cast_nullable_to_non_nullable
as bool,sleepSuggestionEnabled: null == sleepSuggestionEnabled ? _self.sleepSuggestionEnabled : sleepSuggestionEnabled // ignore: cast_nullable_to_non_nullable
as bool,sleepSuggestionHour: null == sleepSuggestionHour ? _self.sleepSuggestionHour : sleepSuggestionHour // ignore: cast_nullable_to_non_nullable
as int,sleepSuggestionMinute: null == sleepSuggestionMinute ? _self.sleepSuggestionMinute : sleepSuggestionMinute // ignore: cast_nullable_to_non_nullable
as int,wakeSuggestionEnabled: null == wakeSuggestionEnabled ? _self.wakeSuggestionEnabled : wakeSuggestionEnabled // ignore: cast_nullable_to_non_nullable
as bool,wakeSuggestionAfterHours: null == wakeSuggestionAfterHours ? _self.wakeSuggestionAfterHours : wakeSuggestionAfterHours // ignore: cast_nullable_to_non_nullable
as double,quickSwitchThresholdSeconds: null == quickSwitchThresholdSeconds ? _self.quickSwitchThresholdSeconds : quickSwitchThresholdSeconds // ignore: cast_nullable_to_non_nullable
as int,identityGeneration: null == identityGeneration ? _self.identityGeneration : identityGeneration // ignore: cast_nullable_to_non_nullable
as int,chatLogsFront: null == chatLogsFront ? _self.chatLogsFront : chatLogsFront // ignore: cast_nullable_to_non_nullable
as bool,terminologyUseEnglish: null == terminologyUseEnglish ? _self.terminologyUseEnglish : terminologyUseEnglish // ignore: cast_nullable_to_non_nullable
as bool,hasCompletedOnboarding: null == hasCompletedOnboarding ? _self.hasCompletedOnboarding : hasCompletedOnboarding // ignore: cast_nullable_to_non_nullable
as bool,syncThemeEnabled: null == syncThemeEnabled ? _self.syncThemeEnabled : syncThemeEnabled // ignore: cast_nullable_to_non_nullable
as bool,habitsBadgeEnabled: null == habitsBadgeEnabled ? _self.habitsBadgeEnabled : habitsBadgeEnabled // ignore: cast_nullable_to_non_nullable
as bool,timingMode: null == timingMode ? _self.timingMode : timingMode // ignore: cast_nullable_to_non_nullable
as FrontingTimingMode,notesEnabled: null == notesEnabled ? _self.notesEnabled : notesEnabled // ignore: cast_nullable_to_non_nullable
as bool,previousAccentColorHex: null == previousAccentColorHex ? _self.previousAccentColorHex : previousAccentColorHex // ignore: cast_nullable_to_non_nullable
as String,systemDescription: freezed == systemDescription ? _self.systemDescription : systemDescription // ignore: cast_nullable_to_non_nullable
as String?,systemColor: freezed == systemColor ? _self.systemColor : systemColor // ignore: cast_nullable_to_non_nullable
as String?,systemTag: freezed == systemTag ? _self.systemTag : systemTag // ignore: cast_nullable_to_non_nullable
as String?,systemAvatarData: freezed == systemAvatarData ? _self.systemAvatarData : systemAvatarData // ignore: cast_nullable_to_non_nullable
as Uint8List?,remindersEnabled: null == remindersEnabled ? _self.remindersEnabled : remindersEnabled // ignore: cast_nullable_to_non_nullable
as bool,localeOverride: freezed == localeOverride ? _self.localeOverride : localeOverride // ignore: cast_nullable_to_non_nullable
as String?,gifConsentState: null == gifConsentState ? _self.gifConsentState : gifConsentState // ignore: cast_nullable_to_non_nullable
as GifConsentState,fontScale: null == fontScale ? _self.fontScale : fontScale // ignore: cast_nullable_to_non_nullable
as double,fontFamily: null == fontFamily ? _self.fontFamily : fontFamily // ignore: cast_nullable_to_non_nullable
as FontFamily,pinLockEnabled: null == pinLockEnabled ? _self.pinLockEnabled : pinLockEnabled // ignore: cast_nullable_to_non_nullable
as bool,biometricLockEnabled: null == biometricLockEnabled ? _self.biometricLockEnabled : biometricLockEnabled // ignore: cast_nullable_to_non_nullable
as bool,autoLockDelaySeconds: null == autoLockDelaySeconds ? _self.autoLockDelaySeconds : autoLockDelaySeconds // ignore: cast_nullable_to_non_nullable
as int,displayFontInAppBar: null == displayFontInAppBar ? _self.displayFontInAppBar : displayFontInAppBar // ignore: cast_nullable_to_non_nullable
as bool,navBarItems: null == navBarItems ? _self._navBarItems : navBarItems // ignore: cast_nullable_to_non_nullable
as List<String>,navBarOverflowItems: null == navBarOverflowItems ? _self._navBarOverflowItems : navBarOverflowItems // ignore: cast_nullable_to_non_nullable
as List<String>,syncNavigationEnabled: null == syncNavigationEnabled ? _self.syncNavigationEnabled : syncNavigationEnabled // ignore: cast_nullable_to_non_nullable
as bool,chatBadgePreferences: null == chatBadgePreferences ? _self._chatBadgePreferences : chatBadgePreferences // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

// dart format on
