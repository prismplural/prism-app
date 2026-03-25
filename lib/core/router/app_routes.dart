import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

abstract final class AppRoutePaths {
  // Tabs
  static const home = '/';
  static const chat = '/chat';
  static const habits = '/habits';
  static const polls = '/polls';
  static const settings = '/settings';
  static const members = '/members';
  static const reminders = '/reminders';
  static const notes = '/notes';
  static const statistics = '/statistics';

  // Settings sub-routes
  static const settingsMembers = '/settings/members';
  static const settingsNotifications = '/settings/notifications';
  static const settingsFeatures = '/settings/features';
  static const settingsFeaturesChat = '/settings/features/chat';
  static const settingsFeaturesHabits = '/settings/features/habits';
  static const settingsFeaturesFronting = '/settings/features/fronting';
  static const settingsFeaturesSleep = '/settings/features/sleep';
  static const settingsFeaturesPolls = '/settings/features/polls';
  static const settingsFeaturesNotes = '/settings/features/notes';
  static const settingsFeaturesReminders = '/settings/features/reminders';
  static const settingsAppearance = '/settings/appearance';
  static const settingsHabits = '/settings/habits';
  static const settingsStatistics = '/settings/statistics';
  static const settingsSync = '/settings/sync';
  static const settingsImportExport = '/settings/import-export';
  static const settingsReset = '/settings/reset';
  static const settingsEncryptionInfo = '/settings/encryption-info';
  static const settingsSharing = '/settings/sharing';
  static const settingsDatabase = '/settings/database';
  static const settingsAbout = '/settings/about';
  static const settingsDebug = '/settings/debug';
  static const settingsSyncDebug = '/settings/sync-debug';
  static const settingsErrors = '/settings/errors';
  static const settingsPluralkit = '/settings/pluralkit';
  static const settingsMigration = '/settings/migration';
  static const settingsSyncTroubleshooting = '/settings/sync-troubleshooting';
  static const settingsDevices = '/settings/devices';
  static const settingsDataBrowser = '/settings/data-browser';
  static const settingsTimelineSanitization = '/settings/timeline-sanitization';
  static const settingsMembersManage = '/settings/members/manage';
  static const settingsGroups = '/settings/members/groups';
  static const settingsCustomFields = '/settings/custom-fields';
  static const settingsAnalytics = '/settings/analytics';
  static const settingsPinLock = '/settings/pin-lock';
  static const settingsReminders = '/settings/reminders';
  static const settingsNavigation = '/settings/navigation';
  static const settingsSystemInfo = '/settings/system-info';

  // Parameterized helpers — groups
  static String settingsGroup(String id) => '/settings/members/groups/$id';

  // Full-screen routes
  static const onboarding = '/onboarding';
  static const secretKeySetup = '/secret-key-setup';
  static const syncSetup = '/sync-setup';

  // Parameterized helpers
  static String chatConversation(String id) => '/chat/$id';
  static String session(String id) => '/session/$id';
  static String sessionEdit(String id) => '/session/$id/edit';
  static String poll(String id) => '/polls/$id';
  static String habit(String id) => '/habits/$id';
  static String note(String id) => '/notes/$id';
  static String member(String id) => '/members/$id';
  static String settingsMember(String id) => '/settings/members/$id';
  static String settingsHabit(String id) => '/settings/habits/$id';
  static String settingsFriend(String id) => '/settings/sharing/$id';
}

abstract final class AppRouteNames {
  static const home = 'home';
  static const chat = 'chat';
  static const habits = 'habits';
  static const polls = 'polls';
  static const settings = 'settings';
  static const members = 'members';
  static const reminders = 'reminders';
  static const notes = 'notes';
  static const statistics = 'statistics';
  static const settingsSync = 'settings-sync';
  static const onboarding = 'onboarding';
  static const secretKeySetup = 'secret-key-setup';
  static const syncSetup = 'sync-setup';
}

enum AppShellTabId { home, chat, habits, polls, settings, members, reminders, notes, statistics }

class AppShellTab {
  const AppShellTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.branchIndex,
    required this.rootLocation,
  });

  final AppShellTabId id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int branchIndex;
  final String rootLocation;

  /// Whether this tab is locked in the nav bar (cannot be removed/reordered).
  bool get isLocked => id == AppShellTabId.home || id == AppShellTabId.settings;

  /// Display label, substituting user's terminology for the Members tab.
  String displayLabel({String? terminologyPlural}) {
    if (id == AppShellTabId.members && terminologyPlural != null) {
      return terminologyPlural;
    }
    return label;
  }

  bool isEnabled(SystemSettings? settings) {
    return switch (id) {
      AppShellTabId.home => true,
      AppShellTabId.chat => settings?.chatEnabled ?? true,
      AppShellTabId.habits => settings?.habitsEnabled ?? true,
      AppShellTabId.polls => settings?.pollsEnabled ?? true,
      AppShellTabId.settings => true,
      AppShellTabId.members => true,
      AppShellTabId.reminders => settings?.remindersEnabled ?? true,
      AppShellTabId.notes => settings?.notesEnabled ?? true,
      AppShellTabId.statistics => true,
    };
  }
}

const appShellTabs = [
  AppShellTab(
    id: AppShellTabId.home,
    label: 'Home',
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
    branchIndex: 0,
    rootLocation: AppRoutePaths.home,
  ),
  AppShellTab(
    id: AppShellTabId.chat,
    label: 'Chat',
    icon: Icons.chat_bubble_outline,
    activeIcon: Icons.chat_bubble,
    branchIndex: 1,
    rootLocation: AppRoutePaths.chat,
  ),
  AppShellTab(
    id: AppShellTabId.habits,
    label: 'Habits',
    icon: Icons.check_circle_outline,
    activeIcon: Icons.check_circle,
    branchIndex: 2,
    rootLocation: AppRoutePaths.habits,
  ),
  AppShellTab(
    id: AppShellTabId.polls,
    label: 'Polls',
    icon: Icons.poll_outlined,
    activeIcon: Icons.poll,
    branchIndex: 3,
    rootLocation: AppRoutePaths.polls,
  ),
  AppShellTab(
    id: AppShellTabId.settings,
    label: 'Settings',
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    branchIndex: 4,
    rootLocation: AppRoutePaths.settings,
  ),
  AppShellTab(
    id: AppShellTabId.members,
    label: 'Members',
    icon: Icons.people_outline,
    activeIcon: Icons.people,
    branchIndex: 5,
    rootLocation: AppRoutePaths.members,
  ),
  AppShellTab(
    id: AppShellTabId.reminders,
    label: 'Reminders',
    icon: Icons.alarm_outlined,
    activeIcon: Icons.alarm,
    branchIndex: 6,
    rootLocation: AppRoutePaths.reminders,
  ),
  AppShellTab(
    id: AppShellTabId.notes,
    label: 'Notes',
    icon: Icons.note_outlined,
    activeIcon: Icons.note,
    branchIndex: 7,
    rootLocation: AppRoutePaths.notes,
  ),
  AppShellTab(
    id: AppShellTabId.statistics,
    label: 'Statistics',
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart,
    branchIndex: 8,
    rootLocation: AppRoutePaths.statistics,
  ),
];

/// The default nav bar tab IDs when no custom configuration exists.
const defaultNavBarTabIds = ['home', 'chat', 'habits', 'polls', 'settings'];
