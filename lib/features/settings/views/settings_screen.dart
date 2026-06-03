import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
// Leaf settings screens shown inline in the detail pane on wide windows.
import 'package:prism_plurality/features/settings/views/appearance_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/navigation_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/features_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/notification_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/sync_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/media_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/reset_data_screen.dart';
import 'package:prism_plurality/features/settings/views/about_screen.dart';
import 'package:prism_plurality/features/settings/views/pin_lock_settings_screen.dart';
import 'package:prism_plurality/features/settings/views/analytics_screen.dart';
import 'package:prism_plurality/features/settings/views/debug_screen.dart';
import 'package:prism_plurality/features/settings/views/system_info_screen.dart';
import 'package:prism_plurality/features/settings/views/custom_fields_screen.dart';
import 'package:prism_plurality/features/data_management/views/import_export_screen.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

/// Main settings screen. Clean navigation list matching SwiftUI's layout:
/// sections with icon-labeled links to sub-screens.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with ListDetailSelectionState<SettingsScreen> {
  // Builder for the leaf settings screen currently shown in the detail pane.
  WidgetBuilder? _detailBuilder;

  /// Open a leaf settings destination: inline in the detail pane on wide
  /// windows, or push the full-screen route on narrow ones.
  void _select(String key, String route, WidgetBuilder builder) {
    if (isDetailPaneVisible) {
      setState(() {
        final shouldClear = selectedDetailId == key;
        selectedDetailId = shouldClear ? null : key;
        _detailBuilder = shouldClear ? null : builder;
      });
    } else {
      context.push(route);
    }
  }

  /// A leaf settings row: opens inline in the detail pane on wide windows
  /// (no chevron — it opens here), or pushes the full-screen route on narrow.
  Widget _leafLink({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String selectionKey,
    required String route,
    required WidgetBuilder builder,
    ({IconData icon, Color color})? statusIcon,
  }) {
    return _SettingsLink(
      icon: icon,
      iconColor: iconColor,
      title: title,
      statusIcon: statusIcon,
      selected: isDetailSelected(selectionKey),
      showChevron: !isDetailPaneVisible,
      onTap: () => _select(selectionKey, route, builder),
    );
  }

  /// A full-section row (e.g. Members, Groups): always navigates full-screen.
  /// Keeps its chevron to signal that it leaves the settings pane.
  Widget _navLink({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String route,
  }) {
    return _SettingsLink(
      icon: icon,
      iconColor: iconColor,
      title: title,
      onTap: () => context.push(route),
    );
  }

  Widget _buildDetailPane() {
    final builder = _detailBuilder;
    if (selectedDetailId == null || builder == null) {
      return EmptyState(
        icon: Icon(AppIcons.tuneOutlined),
        title: context.l10n.navSettings,
        subtitle: context.l10n.settingsSelectEmptySubtitle,
      );
    }
    // Keyed so switching destinations cross-fades and resets sub-screen state.
    return KeyedSubtree(
      key: ValueKey(selectedDetailId),
      child: builder(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListDetailLayout(
      onClearSelection: _clearDetailPane,
      detail: (context) => _buildDetailPane(),
      list: (context, isWide) {
        setListDetailWide(isWide);
        return _buildListPane(context);
      },
    );
  }

  void _clearDetailPane() {
    if (selectedDetailId == null && _detailBuilder == null) return;
    setState(() {
      selectedDetailId = null;
      _detailBuilder = null;
    });
  }

  Widget _buildListPane(BuildContext context) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final terms = watchTerminology(context, ref);
    // System card displays member count + avatar stack — exclude the Unknown
    // sentinel so it doesn't inflate the count or appear in the stack.
    final membersAsync = ref.watch(userVisibleMembersProvider);
    final hideTotalMemberCount =
        ref
            .watch(hideTotalMemberCountProvider)
            .whenOrNull(data: (value) => value) ??
        true;
    final syncStatus = ref.watch(syncStatusProvider);
    final theme = Theme.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    return PrismPageScaffold(
      bodyPadding: EdgeInsets.zero,
      body: Stack(
        children: [
          settingsAsync.when(
            loading: () => const PrismLoadingState(),
            error: (e, _) =>
                Center(child: Text(context.l10n.errorWithDetail(e))),
            data: (settings) => ListView(
              padding: EdgeInsets.only(
                top: topInset + 32,
                bottom: NavBarInset.of(context),
              ),
              children: [
                // System identity card (read-only, taps to System Information)
                _buildSystemCard(
                  context,
                  settings,
                  membersAsync,
                  terms,
                  hideTotalMemberCount: hideTotalMemberCount,
                ),
                const SizedBox(height: 8),
                _buildSection(
                  title: context.l10n.settingsSectionSystem,
                  rows: [
                    _leafLink(
                      icon: AppIcons.infoOutline,
                      iconColor: Colors.purple,
                      title: context.l10n.settingsSystemInformation,
                      selectionKey: 'system-info',
                      route: AppRoutePaths.settingsSystemInfo,
                      builder: (_) => const SystemInfoScreen(),
                    ),
                    // Members & Groups are their own two-pane sections — they
                    // navigate full-screen rather than nesting in this pane.
                    _navLink(
                      icon: AppIcons.peopleOutline,
                      iconColor: Colors.blue,
                      title: terms.plural,
                      route: AppRoutePaths.settingsMembers,
                    ),
                    _navLink(
                      icon: AppIcons.workspacesOutlined,
                      iconColor: Colors.cyan,
                      title: context.l10n.settingsGroups,
                      route: AppRoutePaths.settingsGroups,
                    ),
                    _leafLink(
                      icon: AppIcons.tuneOutlined,
                      iconColor: Colors.deepPurple,
                      title: context.l10n.settingsCustomFields,
                      selectionKey: 'custom-fields',
                      route: AppRoutePaths.settingsCustomFields,
                      builder: (_) => const CustomFieldsScreen(),
                    ),
                    _leafLink(
                      icon: AppIcons.photoLibrary,
                      iconColor: Colors.amber,
                      title: 'Media',
                      selectionKey: 'media',
                      route: AppRoutePaths.settingsMedia,
                      builder: (_) => const MediaSettingsScreen(),
                    ),
                    _leafLink(
                      icon: AppIcons.barChartOutlined,
                      iconColor: Colors.green,
                      title: context.l10n.settingsStatistics,
                      selectionKey: 'analytics',
                      route: AppRoutePaths.settingsAnalytics,
                      builder: (_) => const AnalyticsScreen(),
                    ),
                  ],
                ),
                _buildSection(
                  title: context.l10n.settingsSectionApp,
                  rows: [
                    _leafLink(
                      icon: AppIcons.paletteOutlined,
                      iconColor: Colors.pink,
                      title: context.l10n.settingsAppearance,
                      selectionKey: 'appearance',
                      route: AppRoutePaths.settingsAppearance,
                      builder: (_) => const AppearanceSettingsScreen(),
                    ),
                    _leafLink(
                      icon: AppIcons.tabOutlined,
                      iconColor: Colors.teal,
                      title: context.l10n.settingsNavigation,
                      selectionKey: 'navigation',
                      route: AppRoutePaths.settingsNavigation,
                      builder: (_) => const NavigationSettingsScreen(),
                    ),
                    _leafLink(
                      icon: AppIcons.toggleOnOutlined,
                      iconColor: Colors.deepOrange,
                      title: context.l10n.settingsFeatures,
                      selectionKey: 'features',
                      route: AppRoutePaths.settingsFeatures,
                      builder: (_) => const FeaturesSettingsScreen(),
                    ),
                    _leafLink(
                      icon: AppIcons.lockOutline,
                      iconColor: Colors.indigo,
                      title: context.l10n.settingsPrivacySecurity,
                      selectionKey: 'pinlock',
                      route: AppRoutePaths.settingsPinLock,
                      builder: (_) => const PinLockSettingsScreen(),
                    ),
                    _leafLink(
                      icon: AppIcons.notificationsOutlined,
                      iconColor: Colors.orange,
                      title: context.l10n.settingsNotifications,
                      selectionKey: 'notifications',
                      route: AppRoutePaths.settingsNotifications,
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  ],
                ),
                _buildSection(
                  title: context.l10n.settingsSectionData,
                  rows: [
                    _leafLink(
                      icon: AppIcons.sync,
                      iconColor: Colors.teal,
                      title: context.l10n.settingsSync,
                      selectionKey: 'sync',
                      route: AppRoutePaths.settingsSync,
                      builder: (_) => const SyncSettingsScreen(),
                      statusIcon: syncStatus.lastError != null
                          ? (icon: AppIcons.errorOutline, color: Colors.red)
                          : syncStatus.hasSyncIssues
                          ? (
                              icon: AppIcons.warningAmber,
                              color: Colors.amber.shade700,
                            )
                          : syncStatus.lastSyncAt != null
                          ? (icon: AppIcons.cloudDone, color: Colors.green)
                          : null,
                    ),
                    // Sharing is gated until friend state is persisted to the database.
                    if (kDebugMode)
                      _navLink(
                        icon: AppIcons.shareOutlined,
                        iconColor: Colors.cyan,
                        title: context.l10n.settingsSharing,
                        route: AppRoutePaths.settingsSharing,
                      ),
                    _leafLink(
                      icon: AppIcons.importExport,
                      iconColor: Colors.amber,
                      title: context.l10n.settingsImportExport,
                      selectionKey: 'import-export',
                      route: AppRoutePaths.settingsImportExport,
                      builder: (_) => const ImportExportScreen(),
                    ),
                    _leafLink(
                      icon: AppIcons.restartAlt,
                      iconColor: Colors.red,
                      title: context.l10n.settingsResetData,
                      selectionKey: 'reset',
                      route: AppRoutePaths.settingsReset,
                      builder: (_) => const ResetDataScreen(),
                    ),
                  ],
                ),
                _buildAboutRow(context, theme),
                if (!kReleaseMode)
                  _buildSection(
                    title: '',
                    rows: [
                      _leafLink(
                        icon: AppIcons.bugReportOutlined,
                        iconColor: Colors.orange,
                        title: context.l10n.settingsDebug,
                        selectionKey: 'debug',
                        route: AppRoutePaths.settingsDebug,
                        builder: (_) => const DebugScreen(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Gradient fade: solid through the status-bar area, then fades to
          // transparent before content starts at topInset + 32.
          IgnorePointer(
            child: Container(
              height: topInset + 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.6, 1.0],
                  colors: [
                    theme.scaffoldBackgroundColor,
                    theme.scaffoldBackgroundColor,
                    theme.scaffoldBackgroundColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutRow(BuildContext context, ThemeData theme) {
    final cornerStyle = PrismShapes.of(context).cornerStyle;
    return Padding(
      padding: PrismTokens.sectionPadding,
      child: PrismGroupedSectionCard(
        child: PrismListRow(
          title: Text(context.l10n.settingsAbout),
          selected: isDetailSelected('about'),
          onTap: () => _select(
            'about',
            AppRoutePaths.settingsAbout,
            (_) => const AboutScreen(),
          ),
          showChevron: !isDetailPaneVisible,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.prismPurple,
              borderRadius: cornerStyle == CornerStyle.angular
                  ? BorderRadius.zero
                  : BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              'assets/icon_layers/Prism-Logo-Foreground.png',
              width: 28,
              height: 28,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildSection({
    required String title,
    required List<Widget> rows,
  }) {
    final children = <Widget>[];
    for (var index = 0; index < rows.length; index++) {
      children.add(rows[index]);
      if (index < rows.length - 1) {
        children.add(const Divider(height: 1, indent: 60, endIndent: 12));
      }
    }

    return PrismSection(
      title: title,
      child: PrismGroupedSectionCard(child: Column(children: children)),
    );
  }

  /// Read-only system identity card with the original full layout.
  /// Tapping anywhere navigates to the System Information editing screen.
  Widget _buildSystemCard(
    BuildContext context,
    dynamic settings,
    AsyncValue<List<dynamic>> membersAsync,
    dynamic terms, {
    required bool hideTotalMemberCount,
  }) {
    final theme = Theme.of(context);
    final members = membersAsync.whenOrNull(data: (m) => m) ?? [];
    final Uint8List? avatarData = settings.systemAvatarData;
    final String? description = settings.systemDescription;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        button: true,
        label: 'System info',
        child: GestureDetector(
          onTap: () => _select(
            'system-info',
            AppRoutePaths.settingsSystemInfo,
            (_) => const SystemInfoScreen(),
          ),
          behavior: HitTestBehavior.opaque,
          child: PrismSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // System avatar or member avatar cluster
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: avatarData != null
                          ? CircleAvatar(
                              radius: members.length > 1 ? 58 : 40,
                              backgroundImage: MemoryImage(avatarData),
                            )
                          : members.isNotEmpty
                          ? _AvatarCluster(
                              members: members,
                              hideOverflowCount: hideTotalMemberCount,
                            )
                          : CircleAvatar(
                              radius: 40,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                AppIcons.group,
                                size: 28,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),

                    // System name + member count
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.systemName ??
                                context.l10n.settingsFallbackSystemName,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontFamily:
                                  theme.textTheme.headlineLarge?.fontFamily,
                              fontWeight: FontWeight.bold,
                              letterSpacing:
                                  theme
                                      .textTheme
                                      .headlineLarge
                                      ?.letterSpacing ??
                                  0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (!hideTotalMemberCount && members.isNotEmpty)
                            Text(
                              '${members.length} ${members.length == 1 ? terms.singular.toLowerCase() : terms.plural.toLowerCase()}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                // System description
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // Card is the tap target; keep the preview non-interactive so
                  // a link/spoiler span can't swallow the tap.
                  IgnorePointer(
                    child: PrismMarkdownText(
                      data: description,
                      enabled: true,
                      selectable: false,
                      baseStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings navigation link with an icon circle, title, and chevron.
class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.statusIcon,
    required this.onTap,
    this.selected = false,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;

  /// When set, shows a small status icon to the left of the chevron.
  final ({IconData icon, Color color})? statusIcon;
  final VoidCallback onTap;

  /// Highlights the row as the active selection in the two-pane layout.
  final bool selected;

  /// Whether to show the trailing chevron. In-pane rows hide it (they open
  /// here, not navigate); full-section rows keep it to signal they leave.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = PrismSettingsRow(
      icon: icon,
      title: title,
      iconColor: iconColor,
      onTap: onTap,
      showChevron: showChevron,
      trailing: statusIcon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon!.icon, size: 16, color: statusIcon!.color),
                const SizedBox(width: 8),
                Icon(
                  AppIcons.chevronRightRounded,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ],
            )
          : null,
    );
    if (!selected) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(PrismTokens.radiusMedium),
        ),
      ),
      child: row,
    );
  }
}

/// Circular cluster of member avatars arranged in a ring pattern.
/// Shows up to 7 avatars in a circle layout, with a "+N" indicator for overflow.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({
    required this.members,
    required this.hideOverflowCount,
  });

  final List<dynamic> members;
  final bool hideOverflowCount;

  static const double _clusterSize = 116;
  static const double _avatarSize = 32;
  static const int _maxVisible = 8; // 1 center + up to 7 in ring

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = members.take(_maxVisible).toList();
    final overflow = members.length - _maxVisible;

    if (visible.length == 1) {
      return MemberAvatar(
        avatarImageData: visible[0].avatarImageData,
        emoji: visible[0].emoji,
        customColorEnabled: visible[0].customColorEnabled,
        customColorHex: visible[0].customColorHex,
        size: _clusterSize,
      );
    }

    // First member goes in the center, rest in a ring
    final center = visible.first;
    final ring = visible.skip(1).toList();

    return SizedBox(
      width: _clusterSize,
      height: _clusterSize,
      child: Stack(
        children: [
          // Center avatar
          Positioned(
            left: (_clusterSize - _avatarSize) / 2,
            top: (_clusterSize - _avatarSize) / 2,
            child: MemberAvatar(
              avatarImageData: center.avatarImageData,
              emoji: center.emoji,
              customColorEnabled: center.customColorEnabled,
              customColorHex: center.customColorHex,
              size: _avatarSize,
            ),
          ),
          // Ring avatars
          for (int i = 0; i < ring.length; i++)
            _positionedAvatar(ring[i], i, ring.length, theme),
          if (!hideOverflowCount && overflow > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _positionedAvatar(
    dynamic member,
    int index,
    int total,
    ThemeData theme,
  ) {
    // Arrange avatars in a circle around the center
    final angle = (index / total) * 2 * math.pi - math.pi / 2;
    const radius = (_clusterSize - _avatarSize) / 2;
    final cx = _clusterSize / 2 + radius * math.cos(angle) - _avatarSize / 2;
    final cy = _clusterSize / 2 + radius * math.sin(angle) - _avatarSize / 2;

    return Positioned(
      left: cx,
      top: cy,
      child: MemberAvatar(
        avatarImageData: member.avatarImageData,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: _avatarSize,
      ),
    );
  }
}
