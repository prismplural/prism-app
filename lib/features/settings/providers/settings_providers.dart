import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';

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
class SettingsNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> updateSystemName(String? name) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateSystemName(name);
  }

  Future<void> updateTerminology(
    SystemTerminology terminology, {
    String? customTerminology,
    String? customPluralTerminology,
  }) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateTerminologyFields(
      terminology: terminology,
      customTerminology: customTerminology,
      customPluralTerminology: customPluralTerminology,
    );
  }

  Future<void> updateAccentColor(String hex) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateAccentColorHex(hex);
  }

  Future<void> updatePerMemberAccentColors(bool enabled) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updatePerMemberAccentColors(enabled);
  }

  Future<void> updateQuickSwitchThreshold(int seconds) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateQuickSwitchThresholdSeconds(seconds);
  }

  Future<void> toggleQuickFront(bool enabled) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateShowQuickFront(enabled);
  }

  Future<void> updateFrontingReminders({
    required bool enabled,
    int? intervalMinutes,
  }) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    if (intervalMinutes != null) {
      await repo.updateFrontingReminders(
        enabled: enabled,
        intervalMinutes: intervalMinutes,
      );
    } else {
      await repo.updateFrontingRemindersEnabled(enabled);
    }
  }

  Future<void> updateThemeMode(AppThemeMode mode) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateThemeMode(mode);
  }

  Future<void> updateThemeBrightness(ThemeBrightness brightness) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateThemeBrightness(brightness);
  }

  Future<void> updateThemeStyle(ThemeStyle style) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateThemeStyle(style);
  }

  /// Save the current accent color before switching to Material You,
  /// and restore it when switching away.
  Future<void> handleThemeStyleChange(ThemeStyle style) async {
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
  }

  Future<void> updateSyncThemeEnabled(bool enabled) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateSyncThemeEnabled(enabled);
  }

  Future<void> updateChatLogsFront(bool enabled) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateChatLogsFront(enabled);
  }

  Future<void> updateTimingMode(FrontingTimingMode mode) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateTimingMode(mode);
  }

  Future<void> updateHabitsBadgeEnabled(bool value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateHabitsBadgeEnabled(value);
  }

  Future<void> updateNotesEnabled(bool value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateNotesEnabled(value);
  }

  Future<void> updateRemindersEnabled(bool value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateRemindersEnabled(value);
  }

  Future<void> updateSystemDescription(String? value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateSystemDescription(value);
  }

  Future<void> updateSystemAvatarData(Uint8List? value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateSystemAvatarData(value);
  }

  Future<void> updateFontScale(double value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateFontScale(value);
  }

  Future<void> updateFontFamily(FontFamily value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateFontFamily(value);
  }

  Future<void> updatePinLockEnabled(bool value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updatePinLockEnabled(value);
  }

  Future<void> updateBiometricLockEnabled(bool value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateBiometricLockEnabled(value);
  }

  Future<void> updateAutoLockDelaySeconds(int value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateAutoLockDelaySeconds(value);
  }

  Future<void> updateNavBarItems(List<String> items) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateNavBarItems(items);
  }

  Future<void> updateNavBarOverflowItems(List<String> items) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateNavBarOverflowItems(items);
  }

  Future<void> updateSyncNavigationEnabled(bool value) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateSyncNavigationEnabled(value);
  }

  Future<void> updateChatBadgePreferences(Map<String, String> prefs) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateChatBadgePreferences(prefs);
  }

  /// Update one or more feature toggles.
  Future<void> updateFeatureToggle({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
  }) async {
    final repo = ref.read(systemSettingsRepositoryProvider);
    await repo.updateFeatureToggles(
      chatEnabled: chatEnabled,
      pollsEnabled: pollsEnabled,
      habitsEnabled: habitsEnabled,
      sleepTrackingEnabled: sleepTrackingEnabled,
    );
  }
}

final settingsNotifierProvider = NotifierProvider<SettingsNotifier, void>(
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

/// Current brightness preference.
final themeBrightnessProvider = Provider<ThemeBrightness>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.themeBrightness) ??
      ThemeBrightness.system;
});

/// Current theme style preference.
final themeStyleProvider = Provider<ThemeStyle>((ref) {
  return ref
          .watch(systemSettingsProvider)
          .whenOrNull(data: (s) => s.themeStyle) ??
      ThemeStyle.standard;
});

/// Resolves a list of tab ID strings to AppShellTab objects, filtering by
/// enabled state and deduplicating.
List<AppShellTab> _resolveTabIds(
  List<String> ids,
  SystemSettings? settings,
  Map<String, AppShellTab> tabById,
  Set<String> seen,
) {
  final result = <AppShellTab>[];
  for (final id in ids) {
    if (!seen.add(id)) continue;
    final tab = tabById[id];
    if (tab != null && tab.isEnabled(settings)) {
      result.add(tab);
    }
  }
  return result;
}

/// Computes the primary nav bar tabs (shown directly in the bar).
final activeNavBarTabsProvider = Provider<List<AppShellTab>>((ref) {
  final settings = ref.watch(systemSettingsProvider).value;
  final configuredIds = settings?.navBarItems ?? const [];

  // If empty, use legacy default
  final tabIds = configuredIds.isEmpty ? defaultNavBarTabIds : configuredIds;

  final tabById = {for (final t in appShellTabs) t.id.name: t};
  final seen = <String>{};
  final result = _resolveTabIds(tabIds, settings, tabById, seen);

  // Ensure Home is first and Settings is last
  result.removeWhere(
      (t) => t.id == AppShellTabId.home || t.id == AppShellTabId.settings);
  final homeTab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.home);
  final settingsTab =
      appShellTabs.firstWhere((t) => t.id == AppShellTabId.settings);
  result.insert(0, homeTab);
  if (settingsTab.isEnabled(settings)) result.add(settingsTab);

  return result;
});

/// Computes the overflow menu tabs (shown when the More trigger is expanded).
final navBarOverflowTabsProvider = Provider<List<AppShellTab>>((ref) {
  final settings = ref.watch(systemSettingsProvider).value;
  final overflowIds = settings?.navBarOverflowItems ?? const [];
  if (overflowIds.isEmpty) return const [];

  final tabById = {for (final t in appShellTabs) t.id.name: t};
  // Don't deduplicate against primary here — the nav bar widget handles
  // combining them. Just resolve the overflow list independently.
  final seen = <String>{};
  return _resolveTabIds(overflowIds, settings, tabById, seen);
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
