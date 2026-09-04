import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart' hide CornerStyle;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart' as domain;
import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/member_name_presentation.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

const _kThemeBrightnessCache = 'prism.cache.theme_brightness';
const _kThemeStyleCache = 'prism.cache.theme_style';
const _kThemeCornerStyleCache = 'prism.cache.theme_corner_style';
const _kAccentColorHexCache = 'prism.cache.accent_color_hex';
const _kPaletteSourceCache = 'prism.cache.palette_source';
const _kPaletteSeedColorHexCache = 'prism.cache.palette_seed_color_hex';
const _kPaletteMoodCache = 'prism.cache.palette_mood';
const _kPaletteContrastCache = 'prism.cache.palette_contrast';
const _kIgnoreSyncedAppearance = 'prism.pref.ignore_synced_appearance';
const _kUseProxyTagsForAuthoring = 'prism.pref.use_proxy_tags_for_authoring';
const _kHardLockSyncOnAppLock = 'prism.pref.hard_lock_sync_on_app_lock';
const _kScreenPrivacyEnabled = 'prism.pref.screen_privacy_enabled';
const _kLastUsedSpeakingAsMember = 'prism.pref.last_used_speaking_as_member';

ThemeStyle effectiveThemeStyleForPlatform(
  ThemeStyle style,
  TargetPlatform platform,
) => style;

bool paletteDeviceSourceAvailableForPlatform(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.fuchsia || TargetPlatform.iOS => false,
  };
}

PaletteSource effectivePaletteSourceForPlatform(
  PaletteSource source,
  TargetPlatform platform,
) {
  if (source == PaletteSource.device &&
      !paletteDeviceSourceAvailableForPlatform(platform)) {
    return PaletteSource.custom;
  }
  return source;
}

/// Transient storage for a generated mnemonic during secret key setup.
/// Auto-disposed when no longer watched (Riverpod 3 auto-disposes by default).
final pendingMnemonicProvider =
    NotifierProvider<PendingMnemonicNotifier, String?>(
      PendingMnemonicNotifier.new,
    );

class PendingMnemonicNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

/// System settings (singleton, streamed for reactivity).
final systemSettingsProvider = StreamProvider<SystemSettings>((ref) {
  final repo = ref.watch(systemSettingsRepositoryProvider);
  return repo.watchSettings();
});

/// Settings notifier for updates.
class SettingsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updateSystemName(String? name) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSystemName(name);
    });
  }

  Future<void> updateTerminology(
    SystemTerminology terminology, {
    String? customTerminology,
    String? customPluralTerminology,
    bool useEnglish = false,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateTerminologyFields(
        terminology: terminology,
        customTerminology: customTerminology,
        customPluralTerminology: customPluralTerminology,
        useEnglish: useEnglish,
      );
    });
  }

  Future<void> updateSystemTerminology({
    required String singular,
    required String plural,
  }) async {
    state = await AsyncValue.guard(() async {
      final normalized = SystemTerms.custom(
        singular: singular,
        plural: plural,
      ).normalized();
      await ref
          .read(appPreferenceRepositoryProvider)
          .set(systemTermsPreference, normalized);
    });
  }

  Future<void> updateSystemTerminologyPreset(SystemTermPreset preset) async {
    state = await AsyncValue.guard(() async {
      await ref
          .read(appPreferenceRepositoryProvider)
          .set(systemTermsPreference, SystemTerms.preset(preset));
    });
  }

  Future<void> resetSystemTerminology() async {
    state = await AsyncValue.guard(() async {
      await ref
          .read(appPreferenceRepositoryProvider)
          .reset(systemTermsPreference);
    });
  }

  Future<void> updateFrontingTerminologyPreset(
    FrontingTermPreset preset, {
    FrontingTermBundle? custom,
    SimpleFrontingTermAuthoring? authoring,
  }) async {
    state = await AsyncValue.guard(() async {
      await ref
          .read(appPreferenceRepositoryProvider)
          .set(
            frontingTermsPreference,
            FrontingTerms.preset(preset, custom: custom, authoring: authoring),
          );
    });
  }

  Future<void> updateFrontingTerminologyCustom(
    FrontingTermBundle bundle, {
    SimpleFrontingTermAuthoring? authoring,
  }) async {
    state = await AsyncValue.guard(() async {
      await ref
          .read(appPreferenceRepositoryProvider)
          .set(
            frontingTermsPreference,
            FrontingTerms.custom(bundle, authoring: authoring),
          );
    });
  }

  Future<void> resetFrontingTerminology() async {
    state = await AsyncValue.guard(() async {
      await ref
          .read(appPreferenceRepositoryProvider)
          .reset(frontingTermsPreference);
    });
  }

  Future<void> updateAccentColor(String hex) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateAccentColorHex(hex);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAccentColorHexCache, hex);
      ref.read(cachedAccentColorHexProvider.notifier).set(hex);
    });
  }

  Future<void> updatePerMemberAccentColors(bool enabled) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updatePerMemberAccentColors(enabled);
    });
  }

  Future<void> updateQuickSwitchThreshold(int seconds) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateQuickSwitchThresholdSeconds(seconds);
    });
  }

  Future<void> toggleQuickFront(bool enabled) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateShowQuickFront(enabled);
    });
  }

  Future<void> updateAutoPromoteLongFrontingSessions(bool enabled) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateAutoPromoteLongFrontingSessions(enabled);
    });
  }

  Future<void> updateFrontingReminders({
    required bool enabled,
    int? intervalMinutes,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      if (intervalMinutes != null) {
        await repo.updateFrontingReminders(
          enabled: enabled,
          intervalMinutes: intervalMinutes,
        );
      } else {
        await repo.updateFrontingRemindersEnabled(enabled);
      }
    });
  }

  Future<void> updateThemeMode(AppThemeMode mode) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateThemeMode(mode);
    });
  }

  Future<void> updateThemeBrightness(ThemeBrightness brightness) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateThemeBrightness(brightness);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeBrightnessCache, brightness.name);
      ref.read(cachedThemeBrightnessProvider.notifier).set(brightness);
    });
  }

  Future<void> updateThemeStyle(ThemeStyle style) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateThemeStyle(style);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeStyleCache, style.name);
      ref.read(cachedThemeStyleProvider.notifier).set(style);
    });
  }

  Future<void> updateCornerStyle(CornerStyle style) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      // Bridge: UI enum → domain enum
      await repo.updateCornerStyle(domain.CornerStyle.values[style.index]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kThemeCornerStyleCache, style.index);
      ref.read(cachedCornerStyleProvider.notifier).set(style);
    });
  }

  Future<void> updateMemberNameDisplay(MemberNameDisplay value) async {
    state = await AsyncValue.guard(() async {
      final primary = value == MemberNameDisplay.legacyName
          ? MemberNamePrimary.canonicalName
          : MemberNamePrimary.fullName;
      await _updateMemberNamePresentation(primary: primary);
    });
  }

  Future<void> updateMemberNamePresentationPrimary(
    MemberNamePrimary primary,
  ) async {
    state = await AsyncValue.guard(() async {
      await _updateMemberNamePresentation(primary: primary);
    });
  }

  Future<void> updateMemberNamePresentationShowAlternate(
    bool showAlternate,
  ) async {
    state = await AsyncValue.guard(() async {
      await _updateMemberNamePresentation(showAlternate: showAlternate);
    });
  }

  Future<void> _updateMemberNamePresentation({
    MemberNamePrimary? primary,
    bool? showAlternate,
  }) async {
    var next = await _currentMemberNamePresentation();
    if (primary != null) next = next.withPrimary(primary);
    if (showAlternate != null) {
      next = next.withShowAlternateName(showAlternate);
    }

    await ref
        .read(appPreferenceRepositoryProvider)
        .set(memberNamePresentationPreference, next.storageValue);

    if (primary != null) {
      final legacyValue = next.preferDisplayName
          ? MemberNameDisplay.display
          : MemberNameDisplay.legacyName;
      await ref
          .read(systemSettingsRepositoryProvider)
          .updateMemberNameDisplay(legacyValue);
    }
  }

  Future<MemberNamePresentation> _currentMemberNamePresentation() async {
    final prefs = ref.read(appPreferenceRepositoryProvider);
    final stored = await prefs.getStored(memberNamePresentationPreference);
    final storedPresentation = stored == null
        ? null
        : MemberNamePresentation.tryParse(stored);
    if (storedPresentation != null) return storedPresentation;

    final loadedSettings = ref
        .read(systemSettingsProvider)
        .whenOrNull(data: (settings) => settings);
    final settings =
        loadedSettings ??
        await ref.read(systemSettingsRepositoryProvider).getSettings();
    return _legacyMemberNamePresentation(settings);
  }

  Future<void> updatePaletteSource(PaletteSource source) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updatePaletteSource(source);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPaletteSourceCache, source.name);
      ref.read(cachedPaletteSourceProvider.notifier).set(source);
    });
  }

  Future<void> updatePaletteSeedColorHex(String hex) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updatePaletteSeedColorHex(hex);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPaletteSeedColorHexCache, hex);
      ref.read(cachedPaletteSeedColorHexProvider.notifier).set(hex);
    });
  }

  Future<void> updatePaletteMood(PaletteMood mood) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updatePaletteMood(mood);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPaletteMoodCache, mood.name);
      ref.read(cachedPaletteMoodProvider.notifier).set(mood);
    });
  }

  Future<void> updatePaletteContrast(PaletteContrast contrast) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updatePaletteContrast(contrast);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPaletteContrastCache, contrast.name);
      ref.read(cachedPaletteContrastProvider.notifier).set(contrast);
    });
  }

  /// Save the current accent color before switching to dynamic system colors,
  /// and restore it when switching away.
  Future<void> handleThemeStyleChange(ThemeStyle style) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      final current = await repo.getSettings();
      String? restoredAccentHex;

      if (style == ThemeStyle.materialYou &&
          current.themeStyle != ThemeStyle.materialYou) {
        // Save the current accent color before enabling dynamic system colors.
        await repo.updatePreviousAccentColorHex(current.accentColorHex);
      } else if (style != ThemeStyle.materialYou &&
          current.themeStyle == ThemeStyle.materialYou) {
        // Restore the saved accent color when leaving dynamic system colors.
        final saved = current.previousAccentColorHex;
        if (saved.isNotEmpty) {
          await repo.updateAccentColorHex(saved);
          restoredAccentHex = saved;
        }
      }

      await repo.updateThemeStyle(style);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeStyleCache, style.name);
      ref.read(cachedThemeStyleProvider.notifier).set(style);
      if (restoredAccentHex != null) {
        await prefs.setString(_kAccentColorHexCache, restoredAccentHex);
        ref.read(cachedAccentColorHexProvider.notifier).set(restoredAccentHex);
      }
    });
  }

  Future<void> updateSyncThemeEnabled(bool enabled) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSyncThemeEnabled(enabled);
    });
  }

  Future<void> updateChatLogsFront(bool enabled) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateChatLogsFront(enabled);
    });
  }

  Future<void> updateTimingMode(FrontingTimingMode mode) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateTimingMode(mode);
    });
  }

  Future<void> updateFrontingListViewMode(FrontingListViewMode mode) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateFrontingListViewMode(mode);
    });
  }

  Future<void> updateAddFrontDefaultBehavior(FrontStartBehavior mode) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateAddFrontDefaultBehavior(mode);
    });
  }

  Future<void> updateQuickFrontDefaultBehavior(FrontStartBehavior mode) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateQuickFrontDefaultBehavior(mode);
    });
  }

  Future<void> updateMembersListViewMode(MembersListViewMode mode) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateMembersListViewMode(mode);
    });
  }

  Future<void> updateMembersGroupedDefaultState(
    MembersGroupedDefaultState defaultState,
  ) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateMembersGroupedDefaultState(defaultState);
    });
  }

  Future<void> updateMembersFolderMemberVisibility(
    MembersFolderMemberVisibility visibility,
  ) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateMembersFolderMemberVisibility(visibility);
    });
  }

  Future<void> updateMembersShowPronouns(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateMembersShowPronouns(value);
    });
  }

  Future<void> updateMembersShowFrontButtons(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateMembersShowFrontButtons(value);
    });
  }

  Future<void> updateMembersShowGroups(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateMembersShowGroups(value);
    });
  }

  Future<void> updateMembersFrontButtonBehavior(
    FrontStartBehavior behavior,
  ) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateMembersFrontButtonBehavior(behavior);
    });
  }

  Future<void> updateHabitsBadgeEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateHabitsBadgeEnabled(value);
    });
  }

  Future<void> updateNotesEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateNotesEnabled(value);
    });
  }

  Future<void> updateBioMarkdownEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateBioMarkdownEnabled(value);
    });
  }

  Future<void> updateRemindersEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateRemindersEnabled(value);
    });
  }

  Future<void> updateGifSearchEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateGifSearchEnabled(value);
    });
  }

  Future<void> updateVoiceNotesEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateVoiceNotesEnabled(value);
    });
  }

  Future<void> updateSleepSuggestionEnabled(bool enabled) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSleepSuggestionEnabled(enabled);
    });
  }

  Future<void> updateSleepSuggestionTime(int hour, int minute) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSleepSuggestionTime(hour, minute);
    });
  }

  Future<void> updateWakeSuggestionEnabled(bool enabled) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateWakeSuggestionEnabled(enabled);
    });
  }

  Future<void> updateWakeSuggestionAfterHours(double hours) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateWakeSuggestionAfterHours(hours);
    });
  }

  Future<void> updateLocaleOverride(String? value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateLocaleOverride(value);
    });
  }

  Future<void> updateDefaultSleepQuality(SleepQuality? value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateDefaultSleepQuality(value);
    });
  }

  Future<void> updateSystemDescription(String? value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSystemDescription(value);
    });
  }

  Future<void> updateSystemTag(String? value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSystemTag(value);
    });
  }

  Future<void> updateSystemColor(String? colorHex) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSystemColor(colorHex);
    });
  }

  Future<void> updateSystemAvatarData(Uint8List? value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSystemAvatarData(value);
    });
  }

  Future<void> updateGifConsentState(GifConsentState value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateGifConsentState(value);
    });
  }

  Future<void> updateFontScale(double value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateFontScale(value);
    });
  }

  Future<void> updateFontFamily(FontFamily value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateFontFamily(value);
    });
  }

  Future<void> updateDisplayFontInAppBar(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateDisplayFontInAppBar(value);
    });
  }

  Future<void> updatePinLockEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updatePinLockEnabled(value);
    });
  }

  Future<void> updateBiometricLockEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateBiometricLockEnabled(value);
    });
  }

  Future<void> updateAutoLockDelaySeconds(int value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateAutoLockDelaySeconds(value);
    });
  }

  Future<void> updateNavBarItems(List<String> items) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateNavBarItems(items);
    });
  }

  Future<void> updateNavBarOverflowItems(List<String> items) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateNavBarOverflowItems(items);
    });
  }

  Future<void> updateNavigationLayout({
    required List<String> navBarItems,
    required List<String> navBarOverflowItems,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      final settings = await repo.getSettings();
      await repo.updateSettings(
        settings.copyWith(
          navBarItems: navBarItems,
          navBarOverflowItems: navBarOverflowItems,
        ),
      );
    });
  }

  Future<void> updateSyncNavigationEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSyncNavigationEnabled(value);
    });
  }

  // Visibility + the always-visible style ride the system_settings columns; the
  // when-expanded style is a synced app preference. These writers keep both in
  // step and carry the current style across a visibility change.
  Future<void> updateNavBarLabelVisibility(NavBarLabelVisibility value) async {
    final style = ref.read(navBarLabelStyleProvider);
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      switch (value) {
        case NavBarLabelVisibility.always:
          await repo.updateNavBarLabelDisplayMode(
            navBarAlwaysModeForStyle(style),
          );
          await repo.updateNavBarRevealLabelsWhenExpanded(false);
        case NavBarLabelVisibility.whenExpanded:
          await repo.updateNavBarLabelDisplayMode(
            NavBarLabelDisplayMode.iconsOnly,
          );
          await repo.updateNavBarRevealLabelsWhenExpanded(true);
          await ref
              .read(navBarExpandedLabelsFullProvider.notifier)
              .set(style == NavBarLabelStyle.full);
        case NavBarLabelVisibility.never:
          await repo.updateNavBarLabelDisplayMode(
            NavBarLabelDisplayMode.iconsOnly,
          );
          await repo.updateNavBarRevealLabelsWhenExpanded(false);
      }
    });
  }

  Future<void> updateNavBarLabelStyle(NavBarLabelStyle value) async {
    final visibility = ref.read(navBarLabelVisibilityProvider);
    state = await AsyncValue.guard(() async {
      switch (visibility) {
        case NavBarLabelVisibility.always:
          await ref
              .read(systemSettingsRepositoryProvider)
              .updateNavBarLabelDisplayMode(navBarAlwaysModeForStyle(value));
        case NavBarLabelVisibility.whenExpanded:
          await ref
              .read(navBarExpandedLabelsFullProvider.notifier)
              .set(value == NavBarLabelStyle.full);
        case NavBarLabelVisibility.never:
          break; // No labels render; the style control is hidden.
      }
    });
  }

  Future<void> updateChatBadgePreferences(Map<String, String> prefs) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateChatBadgePreferences(prefs);
    });
  }

  /// Update one or more feature toggles.
  Future<void> updateFeatureToggle({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
    bool? boardsEnabled,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateFeatureToggles(
        chatEnabled: chatEnabled,
        pollsEnabled: pollsEnabled,
        habitsEnabled: habitsEnabled,
        sleepTrackingEnabled: sleepTrackingEnabled,
      );
      if (boardsEnabled != null) {
        // Check if we're flipping boards on for the first time, so we can
        // append 'boards' to the nav overflow if it isn't already present.
        final current = await repo.getSettings();
        final wasEnabled = current.boardsEnabled;
        await repo.updateBoardsEnabled(boardsEnabled);
        if (!wasEnabled && boardsEnabled) {
          // First-enable nav-append: add 'boards' to the overflow list if it
          // is absent from both the primary nav and the overflow.
          final re = await repo.getSettings();
          final primaryIds = re.navBarItems;
          final overflowIds = re.navBarOverflowItems;
          final alreadyPresent =
              primaryIds.contains('boards') || overflowIds.contains('boards');
          if (!alreadyPresent) {
            await repo.updateNavBarOverflowItems([...overflowIds, 'boards']);
          }
        }
      }
    });
  }
}

final settingsNotifierProvider = AsyncNotifierProvider<SettingsNotifier, void>(
  SettingsNotifier.new,
);

/// Provides the current theme mode preference, reactive to settings changes.
/// Legacy — use [themeBrightnessProvider] + [themeStyleProvider] instead.
final appThemeModeProvider = Provider<AppThemeMode>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.themeMode) ??
      AppThemeMode.system;
});

/// Seeded from SharedPreferences in main() before runApp().
/// Falls back to system/standard defaults if no cache exists.
/// Override in ProviderScope to supply the cached value.
final cachedThemeBrightnessProvider =
    NotifierProvider<CachedThemeBrightnessNotifier, ThemeBrightness>(
      CachedThemeBrightnessNotifier.new,
    );

class CachedThemeBrightnessNotifier
    extends _CachedAppearanceValueNotifier<ThemeBrightness> {
  CachedThemeBrightnessNotifier([super.initial = ThemeBrightness.system]);
}

final cachedThemeStyleProvider =
    NotifierProvider<CachedThemeStyleNotifier, ThemeStyle>(
      CachedThemeStyleNotifier.new,
    );

class CachedThemeStyleNotifier
    extends _CachedAppearanceValueNotifier<ThemeStyle> {
  CachedThemeStyleNotifier([super.initial = ThemeStyle.standard]);
}

final cachedPaletteSourceProvider =
    NotifierProvider<CachedPaletteSourceNotifier, PaletteSource>(
      CachedPaletteSourceNotifier.new,
    );

class CachedPaletteSourceNotifier
    extends _CachedAppearanceValueNotifier<PaletteSource> {
  CachedPaletteSourceNotifier([super.initial = PaletteSource.custom]);
}

final cachedAccentColorHexProvider =
    NotifierProvider<CachedAccentColorHexNotifier, String?>(
      CachedAccentColorHexNotifier.new,
    );

class CachedAccentColorHexNotifier
    extends _CachedAppearanceValueNotifier<String?> {
  CachedAccentColorHexNotifier([super.initial]);
}

final cachedPaletteSeedColorHexProvider =
    NotifierProvider<CachedPaletteSeedColorHexNotifier, String>(
      CachedPaletteSeedColorHexNotifier.new,
    );

class CachedPaletteSeedColorHexNotifier
    extends _CachedAppearanceValueNotifier<String> {
  CachedPaletteSeedColorHexNotifier([super.initial = '#9070A0']);
}

final cachedPaletteMoodProvider =
    NotifierProvider<CachedPaletteMoodNotifier, PaletteMood>(
      CachedPaletteMoodNotifier.new,
    );

class CachedPaletteMoodNotifier
    extends _CachedAppearanceValueNotifier<PaletteMood> {
  CachedPaletteMoodNotifier([super.initial = PaletteMood.tonal]);
}

final cachedPaletteContrastProvider =
    NotifierProvider<CachedPaletteContrastNotifier, PaletteContrast>(
      CachedPaletteContrastNotifier.new,
    );

class CachedPaletteContrastNotifier
    extends _CachedAppearanceValueNotifier<PaletteContrast> {
  CachedPaletteContrastNotifier([super.initial = PaletteContrast.standard]);
}

final targetPlatformProvider = Provider<TargetPlatform>(
  (_) => defaultTargetPlatform,
);

/// Seeded from SharedPreferences in main() before runApp().
/// Falls back to rounded if no cache exists.
/// Override in ProviderScope to supply the cached value.
final cachedCornerStyleProvider =
    NotifierProvider<CachedCornerStyleNotifier, CornerStyle>(
      CachedCornerStyleNotifier.new,
    );

class CachedCornerStyleNotifier
    extends _CachedAppearanceValueNotifier<CornerStyle> {
  CachedCornerStyleNotifier([super.initial = CornerStyle.rounded]);
}

abstract class _CachedAppearanceValueNotifier<T> extends Notifier<T> {
  _CachedAppearanceValueNotifier(T initial) : _initial = initial;

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

/// Per-device local override: when true, the user prefers not to follow
/// synced appearance settings (brightness, style, accent, corner style).
/// Stored ONLY in SharedPreferences — never synced.
final ignoreSyncedAppearanceProvider =
    AsyncNotifierProvider<IgnoreSyncedAppearanceNotifier, bool>(
      IgnoreSyncedAppearanceNotifier.new,
    );

class IgnoreSyncedAppearanceNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIgnoreSyncedAppearance) ?? false;
  }

  Future<void> set(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIgnoreSyncedAppearance, value);
  }
}

/// Current brightness preference.
/// When ignoreSyncedAppearance is ON, reads the cached (local) value.
final themeBrightnessProvider = Provider<ThemeBrightness>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedThemeBrightnessProvider);
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.themeBrightness) ??
      ref.watch(cachedThemeBrightnessProvider);
});

/// Current theme style preference.
/// When ignoreSyncedAppearance is ON, reads the cached (local) value.
final themeStyleProvider = Provider<ThemeStyle>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedThemeStyleProvider);
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.themeStyle) ??
      ref.watch(cachedThemeStyleProvider);
});

/// Current theme style after applying platform capabilities.
///
/// Dynamic system colors are only available on Android, so any synced or
/// cached `materialYou` style downgrades to `standard` elsewhere.
final effectiveThemeStyleProvider = Provider<ThemeStyle>((ref) {
  final style = ref.watch(themeStyleProvider);
  final platform = ref.watch(targetPlatformProvider);
  return effectiveThemeStyleForPlatform(style, platform);
});

/// Palette source preference, respecting the local appearance override.
final paletteSourcePreferenceProvider = Provider<PaletteSource>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedPaletteSourceProvider);
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.paletteSource) ??
      ref.watch(cachedPaletteSourceProvider);
});

/// Palette source after platform capability checks.
final paletteSourceProvider = Provider<PaletteSource>((ref) {
  final source = ref.watch(paletteSourcePreferenceProvider);
  final platform = ref.watch(targetPlatformProvider);
  return effectivePaletteSourceForPlatform(source, platform);
});

/// Custom palette seed, respecting the local appearance override.
final paletteSeedColorHexProvider = Provider<String>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedPaletteSeedColorHexProvider);
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.paletteSeedColorHex) ??
      ref.watch(cachedPaletteSeedColorHexProvider);
});

/// Palette mood, respecting the local appearance override.
final paletteMoodProvider = Provider<PaletteMood>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedPaletteMoodProvider);
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.paletteMood) ??
      ref.watch(cachedPaletteMoodProvider);
});

/// Palette contrast, respecting the local appearance override.
final paletteContrastProvider = Provider<PaletteContrast>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedPaletteContrastProvider);
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.paletteContrast) ??
      ref.watch(cachedPaletteContrastProvider);
});

/// Reactive corner style, gated by ignoreSyncedAppearance.
/// When ignoreSyncedAppearance is ON, reads the cached (local) value.
/// Exposes the UI-layer CornerStyle for consumption by app_theme.dart.
final cornerStyleProvider = Provider<CornerStyle>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedCornerStyleProvider);
  final settings = ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s);
  if (settings == null) return ref.watch(cachedCornerStyleProvider);
  // Bridge: domain enum index → UI enum
  return CornerStyle.values[settings.cornerStyle.index];
});

MemberNamePresentation _legacyMemberNamePresentation(SystemSettings? settings) {
  return MemberNamePresentation.fromLegacy(
    settings?.memberNameDisplay ?? MemberNameDisplay.display,
  );
}

/// Raw synced app preference row for member name presentation.
///
/// A missing, deleted, or invalid row stays nullable so the app can preserve the
/// legacy system setting as the fallback instead of collapsing to a static
/// preference default.
final storedMemberNamePresentationProvider =
    StreamProvider<MemberNamePresentation?>((ref) {
      final repo = ref.watch(appPreferenceRepositoryProvider);
      return repo
          .watchStored(memberNamePresentationPreference)
          .map(
            (value) =>
                value == null ? null : MemberNamePresentation.tryParse(value),
          );
    });

/// Synced system-wide rule for how member names are presented.
///
/// Existing installs without an app-preference row derive their value from the
/// legacy system setting so the UI does not change until the user edits it.
final memberNamePresentationProvider = Provider<MemberNamePresentation>((ref) {
  final legacy = _legacyMemberNamePresentation(
    ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s),
  );
  return ref
      .watch(storedMemberNamePresentationProvider)
      .maybeWhen(data: (stored) => stored ?? legacy, orElse: () => legacy);
});

/// Legacy two-state projection kept for older call sites and tests.
final memberNameDisplayProvider = Provider<MemberNameDisplay>((ref) {
  return ref.watch(memberNamePresentationProvider).preferDisplayName
      ? MemberNameDisplay.display
      : MemberNameDisplay.legacyName;
});

/// Whether appearance settings are synced across devices.
/// NOT gated by ignoreSyncedAppearance — this is the global "do we share" toggle.
final syncAppearanceEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s);
  return settings?.syncThemeEnabled ?? false;
});

/// Resolves a list of tab ID strings to AppShellTab objects, filtering by
/// enabled state and deduplicating against [seen].
List<AppShellTab> _resolveTabIds(
  List<String> ids,
  ({
    bool chat,
    bool polls,
    bool habits,
    bool sleep,
    bool notes,
    bool reminders,
    bool boards,
  })
  flags,
  Map<String, AppShellTab> tabById,
  Set<String> seen,
) {
  final result = <AppShellTab>[];
  for (final id in ids) {
    if (!seen.add(id)) continue;
    final tab = tabById[id];
    if (tab != null && tab.isEnabled(flags)) {
      result.add(tab);
    }
  }
  return result;
}

/// Resolved nav layout: primary tabs rendered directly in the bar, plus
/// overflow tabs reached through the More trigger.
typedef NavLayout = ({List<AppShellTab> primary, List<AppShellTab> overflow});

/// Single source of truth for computing the resolved primary + overflow tab
/// split. Used by both the rendered nav bar and the navigation settings UI
/// so they never disagree.
///
/// Invariants:
/// - Home is always present in either primary or overflow.
/// - Settings is always present in either primary or overflow.
/// - Primary is never empty after overflow is populated, so More remains
///   reachable.
/// - Primary never exceeds [kMaxPrimaryNavTabs]; excess spills to the front
///   of overflow preserving order.
/// - A tab never appears in both primary and overflow.
/// - Feature-disabled tabs are filtered out.
NavLayout normalizeNavLayout({
  required List<String> primaryIds,
  required List<String> overflowIds,
  required ({
    bool chat,
    bool polls,
    bool habits,
    bool sleep,
    bool notes,
    bool reminders,
    bool boards,
  })
  flags,
}) {
  final tabById = {for (final t in appShellTabs) t.id.name: t};
  final seen = <String>{};

  var primary = _resolveTabIds(primaryIds, flags, tabById, seen);
  final overflow = _resolveTabIds(overflowIds, flags, tabById, seen);

  // Home must stay reachable, but it is user-movable like Settings.
  final homeTab = tabById[AppShellTabId.home.name]!;
  if (!seen.contains(AppShellTabId.home.name)) {
    if (primary.length < kMaxPrimaryNavTabs) {
      primary.insert(0, homeTab);
    } else {
      overflow.add(homeTab);
    }
    seen.add(AppShellTabId.home.name);
  }

  // Settings must stay reachable so users can always return to configuration.
  if (!primary.any((t) => t.id == AppShellTabId.settings) &&
      !overflow.any((t) => t.id == AppShellTabId.settings)) {
    overflow.add(tabById[AppShellTabId.settings.name]!);
  }

  if (primary.isEmpty && overflow.isNotEmpty) {
    primary.add(overflow.removeAt(0));
  }

  // Enforce the primary cap: excess spills to the front of overflow in order.
  if (primary.length > kMaxPrimaryNavTabs) {
    final excess = primary.sublist(kMaxPrimaryNavTabs);
    primary = primary.sublist(0, kMaxPrimaryNavTabs);
    overflow.insertAll(0, excess);
  }

  return (primary: primary, overflow: overflow);
}

NavLayout _watchNavLayout(Ref ref) {
  final configured = ref.watch(navBarItemsProvider);
  final overflowIds = ref.watch(navBarOverflowItemsProvider);
  final flags = ref.watch(featureFlagsProvider);
  final usesDefaultLayout = configured.isEmpty && overflowIds.isEmpty;
  final primaryIds = usesDefaultLayout ? defaultNavBarTabIds : configured;
  final resolvedOverflowIds = usesDefaultLayout
      ? defaultNavBarOverflowTabIds
      : overflowIds;
  return normalizeNavLayout(
    primaryIds: primaryIds,
    overflowIds: resolvedOverflowIds,
    flags: flags,
  );
}

/// Computes the primary nav bar tabs (shown directly in the bar).
final activeNavBarTabsProvider = Provider<List<AppShellTab>>((ref) {
  return _watchNavLayout(ref).primary;
});

/// Computes the overflow menu tabs (shown when the More trigger is expanded).
final navBarOverflowTabsProvider = Provider<List<AppShellTab>>((ref) {
  return _watchNavLayout(ref).overflow;
});

/// Narrow provider for accent color — only rebuilds dependents when accent color changes.
/// When ignoreSyncedAppearance is ON, reads the cached (local) value.
final accentColorHexProvider = Provider<String?>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return ref.watch(cachedAccentColorHexProvider);
  return ref
      .watch(systemSettingsProvider)
      .whenOrNull(data: (s) => s.accentColorHex);
});

/// Narrow provider for font family selection.
final fontFamilySettingProvider = Provider<FontFamily>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.fontFamily) ??
      FontFamily.system;
});

/// Narrow provider for font scale.
final fontScaleSettingProvider = Provider<double>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.fontScale) ??
      1.0;
});

/// Chat badge preferences map (memberId → 'all' | 'mentions_only').
final chatBadgePreferencesProvider = Provider<Map<String, String>>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.chatBadgePreferences) ??
      {};
});

/// Narrow provider for habits badge enabled flag.
final habitsBadgeEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.habitsBadgeEnabled) ??
      false;
});

/// Current fronting timing mode preference (local-only, not synced).
final timingModeProvider = Provider<FrontingTimingMode>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.timingMode) ??
      FrontingTimingMode.flexible;
});

/// Current fronting list view-mode preference (synced).
/// Default state of the home-screen session list — combined periods,
/// per-member rows, or timeline.
final frontingListViewModeProvider = Provider<FrontingListViewMode>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.frontingListViewMode) ??
      FrontingListViewMode.combinedPeriods;
});

/// Default behavior when adding a new front via the add-front sheet (synced).
final addFrontDefaultBehaviorProvider = Provider<FrontStartBehavior>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.addFrontDefaultBehavior) ??
      FrontStartBehavior.additive;
});

/// Default behavior when using quick front (synced).
final quickFrontDefaultBehaviorProvider = Provider<FrontStartBehavior>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.quickFrontDefaultBehavior) ??
      FrontStartBehavior.additive;
});

/// Whether long-running active sessions auto-promote into the pinned header.
final autoPromoteLongFrontingSessionsProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.autoPromoteLongFrontingSessions) ??
      true;
});

/// Device-local members tab display mode.
final membersListViewModeProvider = Provider<MembersListViewMode>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.membersListViewMode) ??
      MembersListViewMode.folders;
});

/// Device-local default expansion state for grouped member sections.
final membersGroupedDefaultStateProvider = Provider<MembersGroupedDefaultState>(
  (ref) {
    return ref
            .watch(systemSettingsProvider)
            .whenOrNull(data: (s) => s.membersGroupedDefaultState) ??
        MembersGroupedDefaultState.open;
  },
);

/// Device-local member visibility below folders in folder view.
final membersFolderMemberVisibilityProvider =
    Provider<MembersFolderMemberVisibility>((ref) {
      return ref
              .watch(systemSettingsProvider)
              .whenOrNull(data: (s) => s.membersFolderMemberVisibility) ??
          MembersFolderMemberVisibility.allMembers;
    });

/// Device-local visibility of member pronouns in member rows.
final membersShowPronounsProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.membersShowPronouns) ??
      true;
});

/// Device-local visibility of direct front buttons in member rows.
final membersShowFrontButtonsProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.membersShowFrontButtons) ??
      false;
});

/// Device-local toggle for showing group structure in the members list.
final membersShowGroupsProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.membersShowGroups) ??
      true;
});

/// Device-local behavior used by member-row front buttons and row actions.
final membersFrontButtonBehaviorProvider = Provider<FrontStartBehavior>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.membersFrontButtonBehavior) ??
      FrontStartBehavior.additive;
});

/// Narrow provider for `hasCompletedOnboarding` flag.
final hasCompletedOnboardingProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.hasCompletedOnboarding) ??
      false;
});

/// Narrow provider for `notesEnabled` flag.
final notesEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.notesEnabled) ??
      true;
});

/// Narrow provider for the global "render bio markdown" switch.
///
/// When false, every member bio renders as plain text regardless of the
/// per-member [Member.markdownEnabled] flag. When true (the default), the
/// per-member flag decides.
final bioMarkdownEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.bioMarkdownEnabled) ??
      true;
});

/// Narrow provider for `boardsEnabled` flag.
final boardsEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.boardsEnabled) ??
      false;
});

/// Narrow provider for system name.
final systemNameProvider = Provider<String?>((ref) {
  return ref
      .watch(systemSettingsProvider)
      .whenOrNull(data: (s) => s.systemName);
});

/// Narrow provider for display font in home app bar.
final displayFontInAppBarProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.displayFontInAppBar) ??
      true;
});

/// Narrow provider for `syncThemeEnabled` flag.
final syncThemeEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.syncThemeEnabled) ??
      false;
});

/// Narrow provider for `syncNavigationEnabled` flag.
final syncNavigationEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.syncNavigationEnabled) ??
      true;
});

/// Synced app preference: full vs. truncated text for labels revealed when the
/// mobile nav bar's More menu expands. Only meaningful in "labels when opened"
/// mode; see [navBarLabelStyleProvider].
final navBarExpandedLabelsFullProvider =
    AsyncNotifierProvider<NavBarExpandedLabelsFullNotifier, bool>(
      NavBarExpandedLabelsFullNotifier.new,
    );

class NavBarExpandedLabelsFullNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final initial = await repo.get(navBarExpandedLabelsFullPreference);
    final subscription = repo
        .watch(navBarExpandedLabelsFullPreference)
        .listen(
          (value) => state = AsyncValue.data(value),
          onError: (Object error, StackTrace stackTrace) =>
              state = AsyncValue.error(error, stackTrace),
        );
    ref.onDispose(subscription.cancel);
    return initial;
  }

  Future<void> set(bool value) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(navBarExpandedLabelsFullPreference, value);
    state = AsyncValue.data(value);
  }
}

/// When labels appear in the mobile nav bar. Derived from the stored display
/// mode + reveal flag (see [NavBarLabelDisplayMode]).
final navBarLabelVisibilityProvider = Provider<NavBarLabelVisibility>((ref) {
  final settings = ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s);
  if (settings == null) return NavBarLabelVisibility.always;
  return navBarLabelVisibilityFor(
    settings.navBarLabelDisplayMode,
    settings.navBarRevealLabelsWhenExpanded,
  );
});

/// Whether shown labels render in full or truncated. For always-visible labels
/// the treatment is encoded in the display mode; for labels revealed on expand
/// it comes from the [navBarExpandedLabelsFullProvider] app preference.
final navBarLabelStyleProvider = Provider<NavBarLabelStyle>((ref) {
  final settings = ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s);
  final mode =
      settings?.navBarLabelDisplayMode ?? NavBarLabelDisplayMode.fullLabels;
  // Any icons-only mode (whenExpanded or never) carries its text treatment in
  // the app preference, not the display mode. Reading it even in `never` keeps
  // the choice intact across a never round-trip so it isn't silently reset to
  // full when the user toggles labels back on.
  if (mode == NavBarLabelDisplayMode.iconsOnly) {
    final expandedFull =
        ref
            .watch(navBarExpandedLabelsFullProvider)
            .whenOrNull(data: (v) => v) ??
        false;
    return expandedFull ? NavBarLabelStyle.full : NavBarLabelStyle.truncated;
  }
  return navBarLabelStyleFromMode(mode);
});

/// Narrow provider for `chatEnabled` flag.
final chatEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.chatEnabled) ??
      true;
});

/// Narrow provider for `gifSearchEnabled` flag.
final gifSearchEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.gifSearchEnabled) ??
      true;
});

final gifConsentStateProvider = Provider<GifConsentState>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.gifConsentState) ??
      GifConsentState.unknown;
});

/// Narrow provider for `voiceNotesEnabled` flag.
final voiceNotesEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.voiceNotesEnabled) ??
      true;
});

/// Narrow provider for locale override. Returns null for system default.
final localeOverrideProvider = Provider<Locale?>((ref) {
  final code = ref
      .watch(systemSettingsProvider)
      .whenOrNull(data: (s) => s.localeOverride);
  if (code == null || code.isEmpty) return null;
  const supported = [Locale('en'), Locale('es')];
  final locale = Locale(code);
  if (supported.any((l) => l.languageCode == locale.languageCode)) {
    return locale;
  }
  return null;
});

/// Narrow provider for `pollsEnabled` flag.
final pollsEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.pollsEnabled) ??
      true;
});

/// Narrow provider for `habitsEnabled` flag.
final habitsEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.habitsEnabled) ??
      true;
});

/// Narrow provider for `sleepTrackingEnabled` flag.
final sleepTrackingEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.sleepTrackingEnabled) ??
      true;
});

/// Narrow provider for `remindersEnabled` flag.
final remindersEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.remindersEnabled) ??
      true;
});

/// Narrow provider for `frontingRemindersEnabled` flag.
final frontingRemindersEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.frontingRemindersEnabled) ??
      false;
});

/// Narrow provider for `frontingReminderIntervalMinutes`.
final frontingReminderIntervalProvider = Provider<int>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.frontingReminderIntervalMinutes) ??
      60;
});

/// Narrow provider for `chatLogsFront` flag.
final chatLogsFrontProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.chatLogsFront) ??
      false;
});

/// Per-device local override: when true, the chat composer will author a
/// message as the member whose PluralKit proxy tag matches the draft text.
/// Stored ONLY in SharedPreferences — never synced. Proxy-tag authoring is a
/// typing habit, not a persistent state change, and should not propagate
/// across devices.
final useProxyTagsForAuthoringProvider =
    AsyncNotifierProvider<UseProxyTagsForAuthoringNotifier, bool>(
      UseProxyTagsForAuthoringNotifier.new,
    );

class UseProxyTagsForAuthoringNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kUseProxyTagsForAuthoring) ?? true;
  }

  Future<void> set(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseProxyTagsForAuthoring, value);
  }
}

/// Per-device local privacy override: when true, app lock also forgets the
/// wrapped runtime sync DEK so sync requires recovery before resuming.
/// Stored ONLY in SharedPreferences because this controls device behavior.
final hardLockSyncOnAppLockProvider =
    AsyncNotifierProvider<HardLockSyncOnAppLockNotifier, bool>(
      HardLockSyncOnAppLockNotifier.new,
    );

class HardLockSyncOnAppLockNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHardLockSyncOnAppLock) ?? false;
  }

  Future<void> set(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHardLockSyncOnAppLock, value);
  }
}

/// Per-device local privacy preference: when true, the platform secure-
/// display flag is applied for the whole app (FLAG_SECURE on Android,
/// secure-text-field overlay on iOS) so screenshots are blocked and the
/// app's content is hidden from the app switcher snapshot. Stored ONLY
/// in SharedPreferences — never synced. The threat model is local to
/// the device (someone glancing at the recent-apps tray).
final screenPrivacyEnabledProvider =
    AsyncNotifierProvider<ScreenPrivacyEnabledNotifier, bool>(
      ScreenPrivacyEnabledNotifier.new,
    );

class ScreenPrivacyEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kScreenPrivacyEnabled) ?? false;
  }

  Future<void> set(bool value) async {
    // Persist BEFORE flipping in-memory state. If SharedPreferences
    // reports a failed write (full disk, plugin error), we leave the
    // notifier's state and the UI switch at the previous value so the
    // user notices the toggle didn't take — silently keeping a privacy
    // setting "on" in memory while disk says "off" would be a footgun.
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setBool(_kScreenPrivacyEnabled, value);
    if (!ok) {
      throw StateError(
        'Failed to persist screen privacy preference to SharedPreferences',
      );
    }
    state = AsyncValue.data(value);
  }
}

/// Synced app preference for hiding member counts across management surfaces.
final hideMemberCountsProvider =
    AsyncNotifierProvider<HideMemberCountsNotifier, bool>(
      HideMemberCountsNotifier.new,
    );

class HideMemberCountsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final subscription = repo
        .watch(hideMemberCountsPreference)
        .listen(
          (value) {
            state = AsyncValue.data(value);
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
          },
        );
    ref.onDispose(subscription.cancel);
    return repo.get(hideMemberCountsPreference);
  }

  Future<void> set(bool value) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(hideMemberCountsPreference, value);
    state = AsyncValue.data(value);
  }
}

/// Synced preference for how composer surfaces pick the default "acting as"
/// member.
final composerDefaultMemberProvider =
    AsyncNotifierProvider<ComposerDefaultMemberNotifier, ComposerDefaultMember>(
      ComposerDefaultMemberNotifier.new,
    );

class ComposerDefaultMemberNotifier
    extends AsyncNotifier<ComposerDefaultMember> {
  @override
  Future<ComposerDefaultMember> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final subscription = repo
        .watch(composerDefaultMemberPreference)
        .listen(
          (value) {
            state = AsyncValue.data(ComposerDefaultMember.fromStorage(value));
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
          },
        );
    ref.onDispose(subscription.cancel);
    return ComposerDefaultMember.fromStorage(
      await repo.get(composerDefaultMemberPreference),
    );
  }

  Future<void> set(ComposerDefaultMember value) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(composerDefaultMemberPreference, value.storageValue);
    state = AsyncValue.data(value);
  }
}

/// Per-device memory of the member last acted as in a composer. Stored only in
/// SharedPreferences — never synced — and read by [ComposerDefaultMember.lastUsed].
final lastUsedSpeakingAsMemberProvider =
    AsyncNotifierProvider<LastUsedSpeakingAsMemberNotifier, String?>(
      LastUsedSpeakingAsMemberNotifier.new,
    );

class LastUsedSpeakingAsMemberNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kLastUsedSpeakingAsMember);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> set(String memberId) async {
    // "Last used" must only ever hold a real member id.
    if (memberId.isEmpty || memberId == unknownSentinelMemberId) return;
    state = AsyncValue.data(memberId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastUsedSpeakingAsMember, memberId);
  }

  Future<void> clear() async {
    state = const AsyncValue.data(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastUsedSpeakingAsMember);
  }
}

/// Synced app preference for the fronting-reminder suppress window — the
/// minimum minutes that must pass after the most-recent front log before
/// the next reminder fires (0 disables).
final frontingReminderSuppressMinutesProvider =
    AsyncNotifierProvider<FrontingReminderSuppressMinutesNotifier, int>(
      FrontingReminderSuppressMinutesNotifier.new,
    );

class FrontingReminderSuppressMinutesNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final subscription = repo
        .watch(frontingReminderSuppressMinutesPreference)
        .listen(
          (value) {
            state = AsyncValue.data(value);
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
          },
        );
    ref.onDispose(subscription.cancel);
    return repo.get(frontingReminderSuppressMinutesPreference);
  }

  Future<void> set(int value) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(frontingReminderSuppressMinutesPreference, value);
    state = AsyncValue.data(value);
  }
}

/// Narrow provider for `quickSwitchThresholdSeconds`.
final quickSwitchThresholdProvider = Provider<int>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.quickSwitchThresholdSeconds) ??
      30;
});

/// Narrow provider for `showQuickFront` flag.
final showQuickFrontProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.showQuickFront) ??
      true;
});

/// Narrow provider for `pinLockEnabled` flag.
final pinLockEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.pinLockEnabled) ??
      false;
});

/// Narrow provider for `biometricLockEnabled` flag.
final biometricLockEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.biometricLockEnabled) ??
      false;
});

/// Narrow provider for `autoLockDelaySeconds`.
final autoLockDelaySecondsProvider = Provider<int>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.autoLockDelaySeconds) ??
      0;
});

/// Narrow provider for `perMemberAccentColors` flag.
final perMemberAccentColorsProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.perMemberAccentColors) ??
      true;
});

/// Grouped provider for all feature flags.
final featureFlagsProvider =
    Provider<
      ({
        bool chat,
        bool polls,
        bool habits,
        bool sleep,
        bool notes,
        bool reminders,
        bool boards,
      })
    >((ref) {
      final s = ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s);
      return (
        chat: s?.chatEnabled ?? true,
        polls: s?.pollsEnabled ?? true,
        habits: s?.habitsEnabled ?? true,
        sleep: s?.sleepTrackingEnabled ?? true,
        notes: s?.notesEnabled ?? true,
        reminders: s?.remindersEnabled ?? true,
        boards: s?.boardsEnabled ?? false,
      );
    });

/// Narrow provider for nav bar items.
final navBarItemsProvider = Provider<List<String>>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.navBarItems) ??
      const [];
});

/// Narrow provider for nav bar overflow items.
final navBarOverflowItemsProvider = Provider<List<String>>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.navBarOverflowItems) ??
      const [];
});

/// Narrow provider for `sleepSuggestionEnabled` flag.
final sleepSuggestionEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.sleepSuggestionEnabled) ??
      false;
});

/// Narrow provider for sleep suggestion time (hour + minute).
final sleepSuggestionTimeProvider = Provider<({int hour, int minute})>((ref) {
  final settings = ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s);
  return (
    hour: settings?.sleepSuggestionHour ?? 22,
    minute: settings?.sleepSuggestionMinute ?? 0,
  );
});

/// Narrow provider for `wakeSuggestionEnabled` flag.
final wakeSuggestionEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.wakeSuggestionEnabled) ??
      false;
});

/// Narrow provider for `wakeSuggestionAfterHours`.
final wakeSuggestionAfterHoursProvider = Provider<double>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.wakeSuggestionAfterHours) ??
      8.0;
});

/// Narrow provider for `defaultSleepQuality` (device-local).
/// Returns null when no default is set (user picks each time).
final defaultSleepQualityProvider = Provider<SleepQuality?>((ref) {
  return ref
      .watch(systemSettingsProvider)
      .whenOrNull(data: (s) => s.defaultSleepQuality);
});

const _kShowFrontingViewToggle = 'prism.local.show_fronting_view_toggle';

class ShowFrontingViewToggleNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShowFrontingViewToggle) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowFrontingViewToggle, value);
  }
}

final showFrontingViewToggleProvider =
    AsyncNotifierProvider<ShowFrontingViewToggleNotifier, bool>(
      ShowFrontingViewToggleNotifier.new,
    );
