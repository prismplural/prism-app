import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

const _kThemeBrightnessCache = 'prism.cache.theme_brightness';
const _kThemeStyleCache = 'prism.cache.theme_style';

/// Transient storage for a generated mnemonic during secret key setup.
/// Auto-disposed when no longer watched (Riverpod 3 auto-disposes by default).
final pendingMnemonicProvider =
    NotifierProvider<PendingMnemonicNotifier, String?>(
        PendingMnemonicNotifier.new);

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

  Future<void> updateSystemDescription(String? value) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(systemSettingsRepositoryProvider);
      await repo.updateSystemDescription(value);
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

/// Current brightness preference.
final themeBrightnessProvider = Provider<ThemeBrightness>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.themeBrightness) ??
      ref.watch(cachedThemeBrightnessProvider);
});

/// Current theme style preference.
final themeStyleProvider = Provider<ThemeStyle>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.themeStyle) ??
      ref.watch(cachedThemeStyleProvider);
});

/// Resolves a list of tab ID strings to AppShellTab objects, filtering by
/// enabled state and deduplicating.
List<AppShellTab> _resolveTabIds(
  List<String> ids,
  ({bool chat, bool polls, bool habits, bool sleep, bool notes, bool reminders}) flags,
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

/// Computes the primary nav bar tabs (shown directly in the bar).
final activeNavBarTabsProvider = Provider<List<AppShellTab>>((ref) {
  final configuredIds = ref.watch(navBarItemsProvider);
  final flags = ref.watch(featureFlagsProvider);

  // If empty, use legacy default
  final tabIds = configuredIds.isEmpty ? defaultNavBarTabIds : configuredIds;

  final tabById = {for (final t in appShellTabs) t.id.name: t};
  final seen = <String>{};
  final result = _resolveTabIds(tabIds, flags, tabById, seen);

  // Ensure Home is first and Settings is last
  result.removeWhere(
      (t) => t.id == AppShellTabId.home || t.id == AppShellTabId.settings);
  final homeTab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.home);
  final settingsTab =
      appShellTabs.firstWhere((t) => t.id == AppShellTabId.settings);
  result.insert(0, homeTab);
  if (settingsTab.isEnabled(flags)) result.add(settingsTab);

  return result;
});

/// Computes the overflow menu tabs (shown when the More trigger is expanded).
final navBarOverflowTabsProvider = Provider<List<AppShellTab>>((ref) {
  final overflowIds = ref.watch(navBarOverflowItemsProvider);
  final flags = ref.watch(featureFlagsProvider);
  if (overflowIds.isEmpty) return const [];

  final tabById = {for (final t in appShellTabs) t.id.name: t};
  // Don't deduplicate against primary here — the nav bar widget handles
  // combining them. Just resolve the overflow list independently.
  final seen = <String>{};
  return _resolveTabIds(overflowIds, flags, tabById, seen);
});

/// Narrow provider for accent color — only rebuilds dependents when accent color changes.
final accentColorHexProvider = Provider<String?>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
    data: (s) => s.accentColorHex,
  );
});

/// Narrow provider for font family selection.
final fontFamilySettingProvider = Provider<FontFamily>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
    data: (s) => s.fontFamily,
  ) ?? FontFamily.system;
});

/// Narrow provider for font scale.
final fontScaleSettingProvider = Provider<double>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
    data: (s) => s.fontScale,
  ) ?? 1.0;
});

/// Chat badge preferences map (memberId → 'all' | 'mentions_only').
final chatBadgePreferencesProvider = Provider<Map<String, String>>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
        data: (s) => s.chatBadgePreferences,
      ) ??
      {};
});

/// Narrow provider for habits badge enabled flag.
final habitsBadgeEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
    data: (s) => s.habitsBadgeEnabled,
  ) ?? false;
});

/// Current fronting timing mode preference (local-only, not synced).
final timingModeProvider = Provider<FrontingTimingMode>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.timingMode) ??
      FrontingTimingMode.flexible;
});

/// Narrow provider for `hasCompletedOnboarding` flag.
final hasCompletedOnboardingProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.hasCompletedOnboarding,
          ) ??
      false;
});

/// Narrow provider for `notesEnabled` flag.
final notesEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.notesEnabled,
          ) ??
      true;
});

/// Narrow provider for system name.
final systemNameProvider = Provider<String?>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
        data: (s) => s.systemName,
      );
});

/// Narrow provider for display font in home app bar.
final displayFontInAppBarProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.displayFontInAppBar,
          ) ??
      true;
});

/// Narrow provider for `syncThemeEnabled` flag.
final syncThemeEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.syncThemeEnabled,
          ) ??
      false;
});

/// Narrow provider for `syncNavigationEnabled` flag.
final syncNavigationEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.syncNavigationEnabled,
          ) ??
      true;
});

/// Narrow provider for `chatEnabled` flag.
final chatEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.chatEnabled,
          ) ??
      true;
});

/// Narrow provider for `gifSearchEnabled` flag.
final gifSearchEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.gifSearchEnabled,
          ) ??
      true;
});

final gifConsentStateProvider = Provider<GifConsentState>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.gifConsentState,
          ) ??
      GifConsentState.unknown;
});

/// Narrow provider for `voiceNotesEnabled` flag.
final voiceNotesEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.voiceNotesEnabled,
          ) ??
      true;
});

/// Narrow provider for locale override. Returns null for system default.
final localeOverrideProvider = Provider<Locale?>((ref) {
  final code = ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.localeOverride,
          );
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
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.pollsEnabled,
          ) ??
      true;
});

/// Narrow provider for `habitsEnabled` flag.
final habitsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.habitsEnabled,
          ) ??
      true;
});

/// Narrow provider for `sleepTrackingEnabled` flag.
final sleepTrackingEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.sleepTrackingEnabled,
          ) ??
      true;
});

/// Narrow provider for `remindersEnabled` flag.
final remindersEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.remindersEnabled,
          ) ??
      true;
});

/// Narrow provider for `frontingRemindersEnabled` flag.
final frontingRemindersEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.frontingRemindersEnabled,
          ) ??
      false;
});

/// Narrow provider for `frontingReminderIntervalMinutes`.
final frontingReminderIntervalProvider = Provider<int>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.frontingReminderIntervalMinutes,
          ) ??
      60;
});

/// Narrow provider for `chatLogsFront` flag.
final chatLogsFrontProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.chatLogsFront,
          ) ??
      false;
});

/// Narrow provider for `quickSwitchThresholdSeconds`.
final quickSwitchThresholdProvider = Provider<int>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.quickSwitchThresholdSeconds,
          ) ??
      30;
});

/// Narrow provider for `pinLockEnabled` flag.
final pinLockEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.pinLockEnabled,
          ) ??
      false;
});

/// Narrow provider for `biometricLockEnabled` flag.
final biometricLockEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.biometricLockEnabled,
          ) ??
      false;
});

/// Narrow provider for `autoLockDelaySeconds`.
final autoLockDelaySecondsProvider = Provider<int>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.autoLockDelaySeconds,
          ) ??
      0;
});

/// Narrow provider for `perMemberAccentColors` flag.
final perMemberAccentColorsProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.perMemberAccentColors,
          ) ??
      true;
});

/// Grouped provider for all feature flags.
final featureFlagsProvider = Provider<
    ({
      bool chat,
      bool polls,
      bool habits,
      bool sleep,
      bool notes,
      bool reminders,
    })>((ref) {
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
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.navBarItems,
          ) ??
      const [];
});

/// Narrow provider for nav bar overflow items.
final navBarOverflowItemsProvider = Provider<List<String>>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
            data: (s) => s.navBarOverflowItems,
          ) ??
      const [];
});

/// Narrow provider for `sleepSuggestionEnabled` flag.
final sleepSuggestionEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
        data: (s) => s.sleepSuggestionEnabled,
      ) ??
      false;
});

/// Narrow provider for sleep suggestion time (hour + minute).
final sleepSuggestionTimeProvider = Provider<({int hour, int minute})>((ref) {
  final settings = ref.watch(systemSettingsProvider).whenOrNull(data: (s) => s);
  return (hour: settings?.sleepSuggestionHour ?? 22, minute: settings?.sleepSuggestionMinute ?? 0);
});

/// Narrow provider for `wakeSuggestionEnabled` flag.
final wakeSuggestionEnabledProvider = Provider<bool>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
        data: (s) => s.wakeSuggestionEnabled,
      ) ??
      false;
});

/// Narrow provider for `wakeSuggestionAfterHours`.
final wakeSuggestionAfterHoursProvider = Provider<double>((ref) {
  return ref.watch(systemSettingsProvider).whenOrNull(
        data: (s) => s.wakeSuggestionAfterHours,
      ) ??
      8.0;
});
