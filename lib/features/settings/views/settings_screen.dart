import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Main settings screen. Clean navigation list matching SwiftUI's layout:
/// sections with icon-labeled links to sub-screens.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final terms = ref.watch(terminologyProvider);
    final membersAsync = ref.watch(activeMembersProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final theme = Theme.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    return PrismPageScaffold(
      bodyPadding: EdgeInsets.zero,
      body: Stack(
        children: [
          settingsAsync.when(
            loading: () => const PrismLoadingState(),
            error: (e, _) => Center(child: Text(context.l10n.errorWithDetail(e))),
            data: (settings) => ListView(
              padding: EdgeInsets.only(
                top: topInset + 32,
                bottom: NavBarInset.of(context),
              ),
              children: [
                // System identity card (read-only, taps to System Information)
                _buildSystemCard(context, settings, membersAsync, terms),
                const SizedBox(height: 8),
                _buildSection(
                  title: context.l10n.settingsSectionSystem,
                  rows: [
                    _SettingsLink(
                      icon: AppIcons.infoOutline,
                      iconColor: Colors.purple,
                      title: context.l10n.settingsSystemInformation,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsSystemInfo),
                    ),
                    _SettingsLink(
                      icon: AppIcons.peopleOutline,
                      iconColor: Colors.blue,
                      title: terms.plural,
                      onTap: () => context.push(AppRoutePaths.settingsMembers),
                    ),
                    _SettingsLink(
                      icon: AppIcons.workspacesOutlined,
                      iconColor: Colors.cyan,
                      title: context.l10n.settingsGroups,
                      onTap: () => context.push(AppRoutePaths.settingsGroups),
                    ),
                    _SettingsLink(
                      icon: AppIcons.tuneOutlined,
                      iconColor: Colors.deepPurple,
                      title: context.l10n.settingsCustomFields,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsCustomFields),
                    ),
                    _SettingsLink(
                      icon: AppIcons.barChartOutlined,
                      iconColor: Colors.green,
                      title: context.l10n.settingsStatistics,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsAnalytics),
                    ),
                  ],
                ),
                _buildSection(
                  title: context.l10n.settingsSectionApp,
                  rows: [
                    _SettingsLink(
                      icon: AppIcons.paletteOutlined,
                      iconColor: Colors.pink,
                      title: context.l10n.settingsAppearance,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsAppearance),
                    ),
                    _SettingsLink(
                      icon: AppIcons.tabOutlined,
                      iconColor: Colors.teal,
                      title: context.l10n.settingsNavigation,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsNavigation),
                    ),
                    _SettingsLink(
                      icon: AppIcons.toggleOnOutlined,
                      iconColor: Colors.deepOrange,
                      title: context.l10n.settingsFeatures,
                      onTap: () => context.push(AppRoutePaths.settingsFeatures),
                    ),
                    _SettingsLink(
                      icon: AppIcons.lockOutline,
                      iconColor: Colors.indigo,
                      title: context.l10n.settingsPrivacySecurity,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsPinLock),
                    ),
                    _SettingsLink(
                      icon: AppIcons.notificationsOutlined,
                      iconColor: Colors.orange,
                      title: context.l10n.settingsNotifications,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsNotifications),
                    ),
                    ListTile(
                      title: Text(context.l10n.settingsLanguageTitle),
                      subtitle: Text(context.l10n.settingsLanguageSubtitle),
                      leading: Icon(PhosphorIcons.translate()),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                    ),
                  ],
                ),
                _buildSection(
                  title: context.l10n.settingsSectionData,
                  rows: [
                    _SettingsLink(
                      icon: AppIcons.sync,
                      iconColor: Colors.teal,
                      title: context.l10n.settingsSync,
                      statusDot: syncStatus.lastError != null
                          ? Colors.red
                          : syncStatus.hasQuarantinedItems
                              ? Colors.amber.shade700
                              : syncStatus.lastSyncAt != null
                                  ? Colors.green
                                  : null,
                      onTap: () => context.push(AppRoutePaths.settingsSync),
                    ),
                    // Sharing is gated until friend state is persisted to the database.
                    if (kDebugMode)
                      _SettingsLink(
                        icon: AppIcons.shareOutlined,
                        iconColor: Colors.cyan,
                        title: context.l10n.settingsSharing,
                        onTap: () =>
                            context.push(AppRoutePaths.settingsSharing),
                      ),
                    _SettingsLink(
                      icon: AppIcons.importExport,
                      iconColor: Colors.amber,
                      title: context.l10n.settingsImportExport,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsImportExport),
                    ),
                    _SettingsLink(
                      icon: AppIcons.restartAlt,
                      iconColor: Colors.red,
                      title: context.l10n.settingsResetData,
                      onTap: () => context.push(AppRoutePaths.settingsReset),
                    ),
                  ],
                ),
                _buildSection(
                  title: context.l10n.settingsSectionAbout,
                  rows: [
                    _SettingsLink(
                      icon: AppIcons.infoOutline,
                      iconColor: Colors.purple,
                      title: context.l10n.settingsAbout,
                      onTap: () => context.push(AppRoutePaths.settingsAbout),
                    ),
                    _SettingsLink(
                      icon: AppIcons.enhancedEncryptionOutlined,
                      iconColor: Colors.blueGrey,
                      title: context.l10n.settingsEncryptionPrivacy,
                      onTap: () =>
                          context.push(AppRoutePaths.settingsEncryptionInfo),
                    ),
                    _SettingsLink(
                      icon: AppIcons.bugReportOutlined,
                      iconColor: Colors.orange,
                      title: context.l10n.settingsDebug,
                      onTap: () => context.push(AppRoutePaths.settingsDebug),
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

  static Widget _buildSection(
      {required String title, required List<Widget> rows}) {
    final children = <Widget>[];
    for (var index = 0; index < rows.length; index++) {
      children.add(rows[index]);
      if (index < rows.length - 1) {
        children.add(const Divider(height: 1, indent: 60, endIndent: 12));
      }
    }

    return PrismSection(
      title: title,
      child: PrismSectionCard(child: Column(children: children)),
    );
  }

  /// Read-only system identity card with the original full layout.
  /// Tapping anywhere navigates to the System Information editing screen.
  static Widget _buildSystemCard(
    BuildContext context,
    dynamic settings,
    AsyncValue<List<dynamic>> membersAsync,
    dynamic terms,
  ) {
    final theme = Theme.of(context);
    final members = membersAsync.whenOrNull(data: (m) => m) ?? [];
    final Uint8List? avatarData = settings.systemAvatarData;
    final String? description = settings.systemDescription;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => context.push(AppRoutePaths.settingsSystemInfo),
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
                            ? _AvatarCluster(members: members)
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
                          settings.systemName ?? context.l10n.settingsFallbackSystemName,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFamily: theme.textTheme.headlineLarge?.fontFamily,
                            fontWeight: FontWeight.bold,
                            letterSpacing: theme.textTheme.headlineLarge?.letterSpacing ?? 0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (members.isNotEmpty)
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
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ],
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
    this.statusDot,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;

  /// When set, shows a colored dot to the left of the chevron.
  final Color? statusDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSettingsRow(
      icon: icon,
      title: title,
      iconColor: iconColor,
      onTap: onTap,
      trailing: statusDot != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusDot,
                  ),
                ),
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
  }
}

/// Circular cluster of member avatars arranged in a ring pattern.
/// Shows up to 7 avatars in a circle layout, with a "+N" indicator for overflow.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({required this.members});

  final List<dynamic> members;

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
          if (overflow > 0)
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
