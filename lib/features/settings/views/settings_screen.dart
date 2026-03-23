import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

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
            error: (e, _) => Center(child: Text('Error: $e')),
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
                  title: 'System',
                  rows: [
                    _SettingsLink(
                      icon: Icons.info_outline,
                      iconColor: Colors.purple,
                      title: 'System Information',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsSystemInfo),
                    ),
                    _SettingsLink(
                      icon: Icons.people_outline,
                      iconColor: Colors.blue,
                      title: terms.plural,
                      onTap: () => context.push(AppRoutePaths.settingsMembers),
                    ),
                    _SettingsLink(
                      icon: Icons.tune_outlined,
                      iconColor: Colors.deepPurple,
                      title: 'Custom Fields',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsCustomFields),
                    ),
                    _SettingsLink(
                      icon: Icons.bar_chart_outlined,
                      iconColor: Colors.green,
                      title: 'Statistics',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsAnalytics),
                    ),
                  ],
                ),
                _buildSection(
                  title: 'App',
                  rows: [
                    _SettingsLink(
                      icon: Icons.palette_outlined,
                      iconColor: Colors.pink,
                      title: 'Appearance',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsAppearance),
                    ),
                    _SettingsLink(
                      icon: Icons.tab_outlined,
                      iconColor: Colors.teal,
                      title: 'Navigation',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsNavigation),
                    ),
                    _SettingsLink(
                      icon: Icons.toggle_on_outlined,
                      iconColor: Colors.deepOrange,
                      title: 'Features',
                      onTap: () => context.push(AppRoutePaths.settingsFeatures),
                    ),
                    _SettingsLink(
                      icon: Icons.bedtime,
                      iconColor: Colors.indigo,
                      title: 'Sleep',
                      onTap: () => context.push(AppRoutePaths.settingsSleep),
                    ),
                    _SettingsLink(
                      icon: Icons.lock_outline,
                      iconColor: Colors.indigo,
                      title: 'Privacy & Security',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsPinLock),
                    ),
                    if (settings.remindersEnabled)
                      _SettingsLink(
                        icon: Icons.alarm,
                        iconColor: Colors.amber,
                        title: 'Reminders',
                        onTap: () =>
                            context.push(AppRoutePaths.settingsReminders),
                      ),
                    _SettingsLink(
                      icon: Icons.notifications_outlined,
                      iconColor: Colors.orange,
                      title: 'Notifications',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsNotifications),
                    ),
                  ],
                ),
                _buildSection(
                  title: 'Data',
                  rows: [
                    _SettingsLink(
                      icon: Icons.sync,
                      iconColor: Colors.teal,
                      title: 'Sync',
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
                        icon: Icons.share_outlined,
                        iconColor: Colors.cyan,
                        title: 'Sharing',
                        onTap: () =>
                            context.push(AppRoutePaths.settingsSharing),
                      ),
                    _SettingsLink(
                      icon: Icons.import_export,
                      iconColor: Colors.amber,
                      title: 'Import & Export',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsImportExport),
                    ),
                    _SettingsLink(
                      icon: Icons.restart_alt,
                      iconColor: Colors.red,
                      title: 'Reset Data',
                      onTap: () => context.push(AppRoutePaths.settingsReset),
                    ),
                  ],
                ),
                _buildSection(
                  title: 'About',
                  rows: [
                    _SettingsLink(
                      icon: Icons.info_outline,
                      iconColor: Colors.purple,
                      title: 'About',
                      onTap: () => context.push(AppRoutePaths.settingsAbout),
                    ),
                    _SettingsLink(
                      icon: Icons.enhanced_encryption_outlined,
                      iconColor: Colors.blueGrey,
                      title: 'Encryption & Privacy',
                      onTap: () =>
                          context.push(AppRoutePaths.settingsEncryptionInfo),
                    ),
                    _SettingsLink(
                      icon: Icons.bug_report_outlined,
                      iconColor: Colors.orange,
                      title: 'Debug',
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
                                  Icons.group,
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
                          settings.systemName ?? 'My System',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
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
                  Icons.chevron_right_rounded,
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
