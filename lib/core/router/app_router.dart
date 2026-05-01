import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import '../../features/fronting/views/fronting_screen.dart';
import '../../features/fronting/views/session_detail_screen.dart';
import '../../features/fronting/views/sleep_screen.dart';
import '../../features/fronting/views/timeline_screen.dart';
import '../../features/fronting/views/edit_front_session_screen.dart';
import '../../features/members/views/members_screen.dart';
import '../../features/members/views/member_detail_screen.dart';
import '../../features/chat/views/chat_screen.dart';
import '../../features/chat/views/chat_search_screen.dart';
import '../../features/chat/views/conversation_screen.dart';
import '../../features/polls/views/polls_list_screen.dart';
import '../../features/polls/views/poll_detail_screen.dart';
import '../../features/settings/views/settings_screen.dart';
import '../../features/settings/views/sleep_feature_settings_screen.dart';
import '../../features/settings/views/polls_feature_settings_screen.dart';
import '../../features/settings/views/notes_feature_settings_screen.dart';
import '../../features/settings/views/reminders_feature_settings_screen.dart';
import '../../features/settings/views/sync_settings_screen.dart';
import '../../features/settings/views/notification_settings_screen.dart';
import '../../features/settings/views/appearance_settings_screen.dart';
import '../../features/settings/views/statistics_screen.dart';
import '../../features/settings/views/database_diagnostics_screen.dart';
import '../../features/settings/views/component_gallery_screen.dart';
import '../../features/settings/views/debug_screen.dart';
import '../../features/settings/views/error_history_screen.dart';
import '../../features/settings/views/sync_debug_screen.dart';
import '../../features/migration/views/migration_screen.dart';
import '../../features/settings/views/sync_troubleshooting_screen.dart';
import '../../features/settings/views/device_management_screen.dart';
import '../../features/settings/views/data_browser_screen.dart';
import '../../features/members/views/groups_screen.dart';
import '../../features/members/views/group_detail_screen.dart';
import '../../features/members/views/system_management_screen.dart';
import '../../features/settings/views/secret_key_setup_screen.dart';
import '../../features/settings/views/sync_setup_screen.dart';
import '../../features/pluralkit/views/pluralkit_setup_screen.dart';
import '../../features/sharing/views/sharing_screen.dart';
import '../../features/sharing/views/friend_detail_screen.dart';
import '../../features/habits/views/habits_list_screen.dart';
import '../../features/habits/views/habit_detail_screen.dart';
import '../../features/data_management/views/import_export_screen.dart';
import '../../features/settings/views/features_settings_screen.dart';
import '../../features/settings/views/chat_feature_settings_screen.dart';
import '../../features/settings/views/habits_feature_settings_screen.dart';
import '../../features/settings/views/fronting_feature_settings_screen.dart';
import '../../features/settings/views/about_screen.dart';
import '../../features/settings/views/reset_data_screen.dart';
import '../../features/settings/views/custom_fields_screen.dart';
import '../../features/settings/views/analytics_screen.dart';
import '../../features/members/views/note_detail_screen.dart';
import '../../features/settings/views/pin_lock_settings_screen.dart';
import '../../features/reminders/views/reminders_screen.dart';
import '../../features/notes/views/notes_list_screen.dart';
import '../../features/settings/views/system_info_screen.dart';
import '../../features/settings/views/navigation_settings_screen.dart';
import '../../features/onboarding/views/onboarding_screen.dart';
import '../../features/settings/providers/settings_providers.dart';
import '../../shared/widgets/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _chatNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'chat');
final _habitsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'habits');
final _pollsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'polls');
final _settingsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'settings');
final _membersNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'members');
final _remindersNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'reminders',
);
final _notesNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'notes');
final _statisticsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'statistics',
);
final _timelineNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'timeline');
final _sleepNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'sleep');

/// Notifier that triggers GoRouter redirect re-evaluation when onboarding
/// status changes.
class _OnboardingRedirectNotifier extends ChangeNotifier {
  bool? _hasCompleted;

  bool? get hasCompleted => _hasCompleted;

  set hasCompleted(bool? value) {
    if (_hasCompleted != value) {
      _hasCompleted = value;
      notifyListeners();
    }
  }

  @override
  // ignore: unnecessary_overrides
  void dispose() {
    super.dispose();
  }

  /// Resets the global [_onboardingRedirectNotifier] state for testing.
  @visibleForTesting
  // ignore: unused_element
  static void resetForTesting() {
    _onboardingRedirectNotifier._hasCompleted = false;
  }
}

// NOTE: File-level global — can retain stale state across hot reload.
// Tightly coupled to GoRouter's refreshListenable API, so not easily fixable
// without a GoRouter lifecycle change. Acceptable for production; be aware
// during development that a hot restart (not hot reload) resets this.
final _onboardingRedirectNotifier = _OnboardingRedirectNotifier();

final routerProvider = Provider<GoRouter>((ref) {
  // Update the redirect notifier reactively.
  ref.listen(systemSettingsProvider, (_, next) {
    _onboardingRedirectNotifier.hasCompleted = next.whenOrNull(
      data: (s) => s.hasCompletedOnboarding,
    );
  });

  // Also set the initial value.
  _onboardingRedirectNotifier.hasCompleted = ref
      .read(systemSettingsProvider)
      .whenOrNull(data: (s) => s.hasCompletedOnboarding);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutePaths.home,
    refreshListenable: _onboardingRedirectNotifier,
    onException: (context, state, router) {
      debugPrint(
        '[GoRouter] exception navigating to ${state.uri}: '
        '${state.error}',
      );
      // Only redirect to home if we're not already there, to avoid
      // swallowing tab-switch failures silently.
      if (state.matchedLocation != AppRoutePaths.home) {
        router.go(AppRoutePaths.home);
      }
    },
    redirect: (context, state) async {
      final hasCompleted = _onboardingRedirectNotifier.hasCompleted;

      // While settings are still loading, don't redirect
      if (hasCompleted == null) return null;

      final isOnboarding = state.matchedLocation == AppRoutePaths.onboarding;

      if (!hasCompleted && !isOnboarding) {
        return AppRoutePaths.onboarding;
      }
      if (hasCompleted && isOnboarding) {
        // Guard: if hasCompletedOnboarding was synced via CRDT but no
        // members exist yet on this device, keep showing onboarding so
        // Device B doesn't land on an empty home screen.
        final memberRepo = ref.read(memberRepositoryProvider);
        final count = await memberRepo.getCount();
        if (count == 0) return null;
        return AppRoutePaths.home;
      }
      return null;
    },
    routes: [
      // Onboarding (full-screen)
      GoRoute(
        name: AppRouteNames.onboarding,
        path: AppRoutePaths.onboarding,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),
      // Full-screen route for Secret Key setup (shown once after key generation)
      GoRoute(
        name: AppRouteNames.secretKeySetup,
        path: AppRoutePaths.secretKeySetup,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          // Try state.extra first, then fall back to transient provider
          final mnemonic = switch (state.extra) {
            final String value when value.trim().isNotEmpty => value,
            _ => ref.read(pendingMnemonicProvider),
          };
          return SecretKeySetupScreen(
            mnemonic: mnemonic,
            onComplete: () => context.goNamed(AppRouteNames.settingsSync),
          );
        },
      ),
      // Full-screen route for sync setup wizard
      GoRoute(
        name: AppRouteNames.syncSetup,
        path: AppRoutePaths.syncSetup,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SyncSetupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0: Home (fronting)
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.home,
                path: AppRoutePaths.home,
                builder: (context, state) => const FrontingScreen(),
                routes: [
                  GoRoute(
                    path: 'session/:id',
                    builder: (context, state) => SessionDetailScreen(
                      sessionId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => EditFrontSessionScreen(
                          sessionId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: Chat
          StatefulShellBranch(
            navigatorKey: _chatNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.chat,
                path: AppRoutePaths.chat,
                builder: (context, state) => const ChatScreen(),
                routes: [
                  GoRoute(
                    path: 'search',
                    builder: (context, state) => const ChatSearchScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => ConversationScreen(
                      conversationId: state.pathParameters['id']!,
                      initialMessageId: state.uri.queryParameters['messageId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Branch 2: Habits
          StatefulShellBranch(
            navigatorKey: _habitsNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.habits,
                path: AppRoutePaths.habits,
                builder: (context, state) => const HabitsListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        HabitDetailScreen(habitId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          // Branch 3: Polls
          StatefulShellBranch(
            navigatorKey: _pollsNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.polls,
                path: AppRoutePaths.polls,
                builder: (context, state) => const PollsListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        PollDetailScreen(pollId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          // Branch 4: Settings (includes members management)
          StatefulShellBranch(
            navigatorKey: _settingsNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.settings,
                path: AppRoutePaths.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  // Members routes (under settings)
                  GoRoute(
                    path: 'members',
                    builder: (context, state) => const MembersScreen(),
                    routes: [
                      GoRoute(
                        path: 'manage',
                        builder: (context, state) =>
                            const SystemManagementScreen(),
                      ),
                      GoRoute(
                        path: 'groups',
                        builder: (context, state) => const GroupsScreen(),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) => GroupDetailScreen(
                              groupId: state.pathParameters['id']!,
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => MemberDetailScreen(
                          memberId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'habits',
                    builder: (context, state) => const HabitsListScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => HabitDetailScreen(
                          habitId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'sleep',
                    redirect: (context, state) => '/settings/features/sleep',
                  ),
                  GoRoute(
                    name: AppRouteNames.settingsSync,
                    path: 'sync',
                    builder: (context, state) => const SyncSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) =>
                        const NotificationSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'appearance',
                    builder: (context, state) =>
                        const AppearanceSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'statistics',
                    builder: (context, state) => const StatisticsScreen(),
                  ),
                  GoRoute(
                    path: 'database',
                    builder: (context, state) =>
                        const DatabaseDiagnosticsScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutScreen(),
                  ),
                  GoRoute(
                    path: 'debug',
                    redirect: (context, state) =>
                        !kReleaseMode ? null : AppRoutePaths.settings,
                    builder: (context, state) => const DebugScreen(),
                    routes: [
                      GoRoute(
                        path: 'pluralkit-group-tester',
                        redirect: (context, state) =>
                            !kReleaseMode ? null : AppRoutePaths.settings,
                        builder: (context, state) =>
                            const PluralKitGroupTesterScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'component-gallery',
                    redirect: (context, state) =>
                        !kReleaseMode ? null : AppRoutePaths.settings,
                    builder: (context, state) => const ComponentGalleryScreen(),
                  ),
                  GoRoute(
                    path: 'sync-debug',
                    builder: (context, state) => const SyncDebugScreen(),
                  ),
                  GoRoute(
                    path: 'errors',
                    builder: (context, state) => const ErrorHistoryScreen(),
                  ),
                  GoRoute(
                    path: 'migration',
                    builder: (context, state) => const MigrationScreen(),
                  ),
                  GoRoute(
                    path: 'pluralkit',
                    builder: (context, state) => const PluralKitSetupScreen(),
                  ),
                  GoRoute(
                    path: 'sync-troubleshooting',
                    builder: (context, state) =>
                        const SyncTroubleshootingScreen(),
                  ),
                  GoRoute(
                    path: 'devices',
                    builder: (context, state) => const DeviceManagementScreen(),
                  ),
                  GoRoute(
                    path: 'data-browser',
                    builder: (context, state) => const DataBrowserScreen(),
                  ),
                  GoRoute(
                    path: 'import-export',
                    builder: (context, state) => const ImportExportScreen(),
                  ),
                  GoRoute(
                    path: 'features',
                    builder: (context, state) => const FeaturesSettingsScreen(),
                    routes: [
                      GoRoute(
                        path: 'chat',
                        builder: (context, state) =>
                            const ChatFeatureSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'habits',
                        builder: (context, state) =>
                            const HabitsFeatureSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'fronting',
                        builder: (context, state) =>
                            const FrontingFeatureSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'sleep',
                        builder: (context, state) => SleepFeatureSettingsScreen(
                          args: state.extra is SleepFeatureSettingsArgs
                              ? state.extra as SleepFeatureSettingsArgs
                              : null,
                        ),
                      ),
                      GoRoute(
                        path: 'polls',
                        builder: (context, state) =>
                            const PollsFeatureSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'notes',
                        builder: (context, state) =>
                            const NotesFeatureSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'reminders',
                        builder: (context, state) =>
                            const RemindersFeatureSettingsScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reset',
                    builder: (context, state) => const ResetDataScreen(),
                  ),
                  GoRoute(
                    path: 'custom-fields',
                    builder: (context, state) => const CustomFieldsScreen(),
                  ),
                  GoRoute(
                    path: 'analytics',
                    builder: (context, state) => const AnalyticsScreen(),
                  ),
                  GoRoute(
                    path: 'pin-lock',
                    builder: (context, state) => const PinLockSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'reminders',
                    builder: (context, state) => const RemindersScreen(),
                  ),
                  GoRoute(
                    path: 'notes/:id',
                    builder: (context, state) =>
                        NoteDetailScreen(noteId: state.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'navigation',
                    builder: (context, state) =>
                        const NavigationSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'system-info',
                    builder: (context, state) => const SystemInfoScreen(),
                  ),
                  if (kDebugMode)
                    GoRoute(
                      path: 'sharing',
                      builder: (context, state) => const SharingScreen(),
                      routes: [
                        GoRoute(
                          path: ':friendId',
                          builder: (context, state) => FriendDetailScreen(
                            friendId: state.pathParameters['friendId']!,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
          // Branch 5: Members (top-level tab)
          StatefulShellBranch(
            navigatorKey: _membersNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.members,
                path: AppRoutePaths.members,
                builder: (context, state) =>
                    const MembersScreen(showBackButton: false),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => MemberDetailScreen(
                      memberId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Branch 6: Reminders (top-level tab)
          StatefulShellBranch(
            navigatorKey: _remindersNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.reminders,
                path: AppRoutePaths.reminders,
                builder: (context, state) =>
                    const RemindersScreen(showBackButton: false),
              ),
            ],
          ),
          // Branch 7: Notes (top-level tab)
          StatefulShellBranch(
            navigatorKey: _notesNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.notes,
                path: AppRoutePaths.notes,
                builder: (context, state) =>
                    const NotesListScreen(showBackButton: false),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        NoteDetailScreen(noteId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          // Branch 8: Statistics (top-level tab)
          StatefulShellBranch(
            navigatorKey: _statisticsNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.statistics,
                path: AppRoutePaths.statistics,
                builder: (context, state) =>
                    const AnalyticsScreen(showBackButton: false),
              ),
            ],
          ),
          // Branch 9: Timeline (optional top-level tab)
          StatefulShellBranch(
            navigatorKey: _timelineNavigatorKey,
            routes: [
              GoRoute(
                name: AppRouteNames.timeline,
                path: AppRoutePaths.timeline,
                builder: (context, state) => const TimelineScreen(),
              ),
            ],
          ),
          // Branch 10: Sleep (opt-in tab; feature-flagged)
          StatefulShellBranch(
            navigatorKey: _sleepNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutePaths.sleep,
                redirect: (context, state) {
                  final flags = ref.read(featureFlagsProvider);
                  return flags.sleep ? null : AppRoutePaths.home;
                },
                builder: (context, state) =>
                    const SleepScreen(showBackButton: false),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
