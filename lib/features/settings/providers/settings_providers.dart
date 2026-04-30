import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart' hide CornerStyle;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart' as domain;
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

const _kThemeBrightnessCache = 'prism.cache.theme_brightness';
const _kThemeStyleCache = 'prism.cache.theme_style';
const _kThemeCornerStyleCache = 'prism.cache.theme_corner_style';
const _kIgnoreSyncedAppearance = 'prism.pref.ignore_synced_appearance';
const _kUseProxyTagsForAuthoring = 'prism.pref.use_proxy_tags_for_authoring';
const _kHardLockSyncOnAppLock = 'prism.pref.hard_lock_sync_on_app_lock';

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

  Future<void> updateAccentColor(String hex) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateAccentColorHex(hex);
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
    });
  }

  Future<void> updateThemeStyle(ThemeStyle style) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateThemeStyle(style);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeStyleCache, style.name);
    });
  }

  Future<void> updateCornerStyle(CornerStyle style) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      // Bridge: UI enum → domain enum
      await repo.updateCornerStyle(domain.CornerStyle.values[style.index]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kThemeCornerStyleCache, style.index);
    });
  }

  /// Save the current accent color before switching to Material You,
  /// and restore it when switching away.
  Future<void> handleThemeStyleChange(ThemeStyle style) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      final current = await repo.getSettings();

      if (style == ThemeStyle.materialYou &&
          current.themeStyle != ThemeStyle.materialYou) {
        // Save current accent color to DB before switching to Material You.
        await repo.updatePreviousAccentColorHex(current.accentColorHex);
      } else if (style != ThemeStyle.materialYou &&
          current.themeStyle == ThemeStyle.materialYou) {
        // Restore saved accent color when switching away from Material You.
        final saved = current.previousAccentColorHex;
        if (saved.isNotEmpty) {
          await repo.updateAccentColorHex(saved);
        }
      }

      await repo.updateThemeStyle(style);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeStyleCache, style.name);
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

  Future<void> updateSyncNavigationEnabled(bool value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSyncNavigationEnabled(value);
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
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateFeatureToggles(
        chatEnabled: chatEnabled,
        pollsEnabled: pollsEnabled,
        habitsEnabled: habitsEnabled,
        sleepTrackingEnabled: sleepTrackingEnabled,
      );
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
final cachedThemeBrightnessProvider = Provider<ThemeBrightness>(
  (_) => ThemeBrightness.system,
);

final cachedThemeStyleProvider = Provider<ThemeStyle>(
  (_) => ThemeStyle.standard,
);

/// Seeded from SharedPreferences in main() before runApp().
/// Falls back to rounded if no cache exists.
/// Override in ProviderScope to supply the cached value.
final cachedCornerStyleProvider = Provider<CornerStyle>(
  (_) => CornerStyle.rounded,
);

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
  ({bool chat, bool polls, bool habits, bool sleep, bool notes, bool reminders})
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
/// - Home is always the first primary tab.
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
  })
  flags,
}) {
  final tabById = {for (final t in appShellTabs) t.id.name: t};
  final seen = <String>{};

  var primary = _resolveTabIds(primaryIds, flags, tabById, seen);

  // Force Home to position 0 (always-enabled).
  primary.removeWhere((t) => t.id == AppShellTabId.home);
  final homeTab = tabById[AppShellTabId.home.name]!;
  primary.insert(0, homeTab);
  seen.add(AppShellTabId.home.name);

  final overflow = _resolveTabIds(overflowIds, flags, tabById, seen);

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
  final primaryIds = configured.isEmpty ? defaultNavBarTabIds : configured;
  final resolvedOverflowIds = overflowIds.isEmpty && configured.isEmpty
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
/// When ignoreSyncedAppearance is ON, returns null so accent defaults to the cached/local value.
final accentColorHexProvider = Provider<String?>((ref) {
  final ignoreSynced =
      ref.watch(ignoreSyncedAppearanceProvider).whenOrNull(data: (v) => v) ??
      false;
  if (ignoreSynced) return null;
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
