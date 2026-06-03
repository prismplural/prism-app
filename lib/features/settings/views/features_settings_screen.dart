import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/chat_feature_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/fronting_feature_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/habits_feature_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/sleep_feature_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/polls_feature_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/notes_feature_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/reminders_feature_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/boards_feature_settings_screen.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Screen for enabling/disabling app features.
/// Each feature navigates to its own subview with toggle and settings.
class FeaturesSettingsScreen extends ConsumerWidget {
  const FeaturesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.featuresTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          PrismSection(
            title: '',
            child: PrismGroupedSectionCard(
              child: Column(
                children: [
                  _featureRow(
                    context,
                    icon: AppIcons.chatOutlined,
                    iconColor: Colors.blue,
                    title: context.l10n.featureChatTitle,
                    enabled: flags.chat,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/chat',
                      builder: (_) => const ChatFeatureSettingsScreen(),
                    ),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  PrismSettingsRow(
                    icon: AppIcons.frontHandOutlined,
                    iconColor: Colors.purple,
                    title: context.l10n.featureFrontingTitle,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/fronting',
                      builder: (_) => const FrontingFeatureSettingsScreen(),
                    ),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: AppIcons.checkCircleOutline,
                    iconColor: Colors.green,
                    title: context.l10n.featureHabitsTitle,
                    enabled: flags.habits,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/habits',
                      builder: (_) => const HabitsFeatureSettingsScreen(),
                    ),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: AppIcons.bedtimeOutlined,
                    iconColor: Colors.indigo,
                    title: context.l10n.featureSleepTitle,
                    enabled: flags.sleep,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/sleep',
                      builder: (_) =>
                          const SleepFeatureSettingsScreen(args: null),
                    ),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: AppIcons.pollOutlined,
                    iconColor: Colors.purple,
                    title: context.l10n.featurePollsTitle,
                    enabled: flags.polls,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/polls',
                      builder: (_) => const PollsFeatureSettingsScreen(),
                    ),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: AppIcons.stickyNote2Outlined,
                    iconColor: Colors.teal,
                    title: context.l10n.featureNotesTitle,
                    enabled: flags.notes,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/notes',
                      builder: (_) => const NotesFeatureSettingsScreen(),
                    ),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: AppIcons.alarm,
                    iconColor: Colors.amber,
                    title: context.l10n.featureRemindersTitle,
                    enabled: flags.reminders,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/reminders',
                      builder: (_) => const RemindersFeatureSettingsScreen(),
                    ),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: AppIcons.navBoards,
                    iconColor: Colors.pink,
                    title: context.l10n.featureBoardsTitle,
                    enabled: flags.boards,
                    onTap: () => _openFeature(
                      context,
                      path: '/settings/features/boards',
                      builder: (_) => const BoardsFeatureSettingsScreen(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              context.l10n.featuresDisablingHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigates to a per-feature settings sub-screen. On wide desktop windows
  /// the target opens in a modal side sheet over the settings pane; on narrow
  /// windows it falls back to the existing full-screen route navigation.
  void _openFeature(
    BuildContext context, {
    required String path,
    required WidgetBuilder builder,
  }) {
    if (shouldUseDetailSideSheet(context)) {
      showDetailSideSheet(context, builder: builder);
    } else {
      context.go(path);
    }
  }

  Widget _featureRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final chevronColor = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.7,
    );

    return PrismSettingsRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      showChevron: false,
      trailing: Semantics(
        label: enabled
            ? context.l10n.featuresEnabled
            : context.l10n.featuresDisabled,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enabled) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Icon(AppIcons.chevronRightRounded, color: chevronColor),
          ],
        ),
      ),
      onTap: onTap,
    );
  }
}
