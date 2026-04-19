import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

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
  static const settingsSharing = '/settings/sharing';
  static const settingsDatabase = '/settings/database';
  static const settingsAbout = '/settings/about';
  static const settingsDebug = '/settings/debug';
  static const settingsComponentGallery = '/settings/component-gallery';
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
  static const timeline = '/timeline';

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
  static const timeline = 'timeline';
}

enum AppShellTabId {
  home,
  chat,
  habits,
  polls,
  settings,
  members,
  reminders,
  notes,
  statistics,
  timeline,
}

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
  /// Only Home is locked — it must always be the first primary tab.
  bool get isLocked => id == AppShellTabId.home;

  /// Display label, substituting user's terminology for the Members tab.
  String displayLabel({String? terminologyPlural}) {
    if (id == AppShellTabId.members && terminologyPlural != null) {
      return terminologyPlural;
    }
    return label;
  }

  /// Localized display label using [context] for l10n.
  /// For the Members tab, uses [terminologyPlural] (the user's custom term) if provided.
  String localizedLabel(BuildContext context, {String? terminologyPlural}) {
    if (id == AppShellTabId.members && terminologyPlural != null) {
      return terminologyPlural;
    }
    final l10n = context.l10n;
    return switch (id) {
      AppShellTabId.home => l10n.navHome,
      AppShellTabId.chat => l10n.navChat,
      AppShellTabId.habits => l10n.navHabits,
      AppShellTabId.polls => l10n.navPolls,
      AppShellTabId.settings => l10n.navSettings,
      AppShellTabId.members => l10n.navMembers,
      AppShellTabId.reminders => l10n.navReminders,
      AppShellTabId.notes => l10n.navNotes,
      AppShellTabId.statistics => l10n.navStatistics,
      AppShellTabId.timeline => l10n.navTimeline,
    };
  }

  bool isEnabled(
    ({
      bool chat,
      bool polls,
      bool habits,
      bool sleep,
      bool notes,
      bool reminders,
    })
    flags,
  ) {
    return switch (id) {
      AppShellTabId.home => true,
      AppShellTabId.chat => flags.chat,
      AppShellTabId.habits => flags.habits,
      AppShellTabId.polls => flags.polls,
      AppShellTabId.settings => true,
      AppShellTabId.members => true,
      AppShellTabId.reminders => flags.reminders,
      AppShellTabId.notes => flags.notes,
      AppShellTabId.statistics => true,
      AppShellTabId.timeline => true,
    };
  }
}

final appShellTabs = [
  AppShellTab(
    id: AppShellTabId.home,
    label: 'Home',
    icon: AppIcons.navHome,
    activeIcon: AppIcons.navHomeActive,
    branchIndex: 0,
    rootLocation: AppRoutePaths.home,
  ),
  AppShellTab(
    id: AppShellTabId.chat,
    label: 'Chat',
    icon: AppIcons.navChat,
    activeIcon: AppIcons.navChatActive,
    branchIndex: 1,
    rootLocation: AppRoutePaths.chat,
  ),
  AppShellTab(
    id: AppShellTabId.habits,
    label: 'Habits',
    icon: AppIcons.navHabits,
    activeIcon: AppIcons.navHabitsActive,
    branchIndex: 2,
    rootLocation: AppRoutePaths.habits,
  ),
  AppShellTab(
    id: AppShellTabId.polls,
    label: 'Polls',
    icon: AppIcons.navPolls,
    activeIcon: AppIcons.navPollsActive,
    branchIndex: 3,
    rootLocation: AppRoutePaths.polls,
  ),
  AppShellTab(
    id: AppShellTabId.settings,
    label: 'Settings',
    icon: AppIcons.navSettings,
    activeIcon: AppIcons.navSettingsActive,
    branchIndex: 4,
    rootLocation: AppRoutePaths.settings,
  ),
  AppShellTab(
    id: AppShellTabId.members,
    label: 'Members',
    icon: AppIcons.navMembers,
    activeIcon: AppIcons.navMembersActive,
    branchIndex: 5,
    rootLocation: AppRoutePaths.members,
  ),
  AppShellTab(
    id: AppShellTabId.reminders,
    label: 'Reminders',
    icon: AppIcons.navReminders,
    activeIcon: AppIcons.navRemindersActive,
    branchIndex: 6,
    rootLocation: AppRoutePaths.reminders,
  ),
  AppShellTab(
    id: AppShellTabId.notes,
    label: 'Notes',
    icon: AppIcons.navNotes,
    activeIcon: AppIcons.navNotesActive,
    branchIndex: 7,
    rootLocation: AppRoutePaths.notes,
  ),
  AppShellTab(
    id: AppShellTabId.statistics,
    label: 'Statistics',
    icon: AppIcons.navStatistics,
    activeIcon: AppIcons.navStatisticsActive,
    branchIndex: 8,
    rootLocation: AppRoutePaths.statistics,
  ),
  AppShellTab(
    id: AppShellTabId.timeline,
    label: 'Timeline',
    icon: AppIcons.navTimeline,
    activeIcon: AppIcons.navTimelineActive,
    branchIndex: 9,
    rootLocation: AppRoutePaths.timeline,
  ),
];

/// The default nav bar tab IDs when no custom configuration exists.
const defaultNavBarTabIds = ['home', 'chat', 'habits', 'polls', 'settings'];

/// The default overflow (More menu) tab IDs when no custom configuration
/// exists. Tabs whose feature flag is off are filtered out by
/// [AppShellTab.isEnabled], so disabling Notes or Reminders in onboarding
/// removes them automatically.
const defaultNavBarOverflowTabIds = ['notes', 'reminders'];

/// Maximum number of tabs that can appear in the primary nav bar. Excess
/// tabs spill into the overflow menu. This constraint is enforced by
/// [normalizeNavLayout] and is the single source of truth for both the
/// settings UI and the rendered nav bar.
const int kMaxPrimaryNavTabs = 5;
