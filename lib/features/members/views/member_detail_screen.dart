import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/members/widgets/member_group_chips.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_display.dart';
import 'package:prism_plurality/features/members/widgets/notes_section.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

/// Detail screen for a single system member, pushed via go_router.
///
/// Displays the member's full profile including avatar, name, pronouns, bio,
/// age, admin status, and whether they are currently fronting. Provides
/// actions for editing, setting as fronter, toggling active status, and
/// deleting. Also shows fronting stats, recent sessions, and conversations.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));

    return memberAsync.when(
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: '', showBackButton: true),
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: '', showBackButton: true),
        body: Center(
            child: Text('Error loading ${ref.read(terminologyProvider).singularLower}: $e')),
      ),
      data: (member) {
        if (member == null) {
          return PrismPageScaffold(
            topBar: const PrismTopBar(title: '', showBackButton: true),
            body: Center(
                child: Text(
                    '${ref.read(terminologyProvider).singular} not found')),
          );
        }
        return _MemberDetailBody(member: member);
      },
    );
  }
}

class _MemberDetailBody extends ConsumerWidget {
  const _MemberDetailBody({required this.member});

  final Member member;

  bool _isFronting(List<dynamic> sessions) {
    return sessions.any((s) => s.memberId == member.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final isFronting = activeSessionsAsync.whenOrNull(
          data: _isFronting,
        ) ??
        false;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: 'Edit',
            onPressed: () => _openEditSheet(context),
          ),
          PrismPopupMenu<_MenuAction>(
              items: [
                PrismMenuItem(value: _MenuAction.setFronter, label: 'Set as fronter', icon: AppIcons.flashOn),
                PrismMenuItem(
                  value: _MenuAction.toggleActive,
                  label: member.isActive ? 'Deactivate' : 'Activate',
                  icon: member.isActive ? AppIcons.visibilityOff : AppIcons.visibility,
                ),
                PrismMenuItem(value: _MenuAction.delete, label: 'Delete', icon: AppIcons.deleteOutline, destructive: true),
              ],
              onSelected: (action) =>
                  _handleMenuAction(context, ref, action),
              tooltip: 'More options',
            ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, NavBarInset.of(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Header: Avatar left, info right (matches SwiftUI layout)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  emoji: member.emoji,
                  customColorEnabled: member.customColorEnabled,
                  customColorHex: member.customColorHex,
                  size: 80,
                  showBorder: true,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (member.pronouns != null &&
                          member.pronouns!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          member.pronouns!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (member.age != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Age ${member.age}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (isFronting)
                            _Chip(
                              icon: AppIcons.flashOn,
                              label: 'Fronting',
                              backgroundColor:
                                  AppColors.fronting.withValues(alpha: 0.15),
                              foregroundColor: AppColors.fronting,
                            ),
                          if (member.isAdmin)
                            _Chip(
                              icon: AppIcons.shieldOutlined,
                              label: 'Admin',
                              backgroundColor:
                                  theme.colorScheme.tertiaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onTertiaryContainer,
                            ),
                          if (!member.isActive)
                            _Chip(
                              icon: AppIcons.visibilityOffOutlined,
                              label: 'Inactive',
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              foregroundColor:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Group chips
            MemberGroupChips(memberId: member.id),

            // Bio
            if (member.bio != null && member.bio!.isNotEmpty)
              _DetailSection(
                icon: AppIcons.notesOutlined,
                title: 'Notes',
                child: MarkdownText(
                  data: member.bio!,
                  enabled: member.markdownEnabled,
                  baseStyle: theme.textTheme.bodyLarge,
                ),
              ),

            // Custom Fields
            CustomFieldsDisplay(memberId: member.id),

            // Notes
            NotesSection(memberId: member.id),

            // Fronting Stats
            _FrontingStatsSection(memberId: member.id),

            const SizedBox(height: 8),

            // Recent Sessions
            _RecentSessionsSection(memberId: member.id),

            const SizedBox(height: 8),

            // Conversations
            _ConversationsSection(memberId: member.id),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _openEditSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddEditMemberSheet(
        member: member,
        scrollController: scrollController,
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) {
    switch (action) {
      case _MenuAction.setFronter:
        ref.read(frontingNotifierProvider.notifier).startFronting(member.id);
        PrismToast.show(context, message: '${member.name} is now fronting');
      case _MenuAction.toggleActive:
        ref.read(membersNotifierProvider.notifier).updateMember(
              member.copyWith(isActive: !member.isActive),
            );
      case _MenuAction.delete:
        _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final terms = ref.read(terminologyProvider);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete ${terms.singularLower}?',
      message: 'Are you sure you want to delete ${member.name}? '
          'This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      ref.read(membersNotifierProvider.notifier).deleteMember(member.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

// ── Fronting Stats Section ──────────────────────────────────────────────────

class _FrontingStatsSection extends ConsumerWidget {
  const _FrontingStatsSection({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(memberFrontingStatsProvider(memberId));

    return statsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (stats) {
        if (stats.totalSessions == 0) {
          return const SizedBox.shrink();
        }

        return _SectionCard(
          icon: AppIcons.barChartOutlined,
          title: 'Fronting Stats',
          theme: theme,
          child: Column(
            children: [
              _StatRow(
                label: 'Total sessions',
                value: '${stats.totalSessions}',
                theme: theme,
              ),
              const Divider(height: 1),
              _StatRow(
                label: 'Total time',
                value: _formatDuration(stats.totalDuration),
                theme: theme,
              ),
              if (stats.lastFronted != null) ...[
                const Divider(height: 1),
                _StatRow(
                  label: 'Last fronted',
                  value: _formatTimestamp(stats.lastFronted!),
                  theme: theme,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) {
      final hours = d.inHours % 24;
      return '${d.inDays}d ${hours}h';
    }
    if (d.inHours > 0) {
      final minutes = d.inMinutes % 60;
      return '${d.inHours}h ${minutes}m';
    }
    return '${d.inMinutes}m';
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7} weeks ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

// ── Recent Sessions Section ─────────────────────────────────────────────────

class _RecentSessionsSection extends ConsumerWidget {
  const _RecentSessionsSection({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessionsAsync = ref.watch(memberRecentSessionsProvider(memberId));

    return sessionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (sessions) {
        if (sessions.isEmpty) return const SizedBox.shrink();

        return _SectionCard(
          icon: AppIcons.historyOutlined,
          title: 'Recent Sessions',
          theme: theme,
          child: Column(
            children: [
              for (var i = 0; i < sessions.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _SessionTile(session: sessions[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startDate = _formatDate(session.startTime);
    final duration = _formatDuration(session.duration);

    return InkWell(
      onTap: () => context.go(AppRoutePaths.session(session.id)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              session.isActive ? AppIcons.flashOn : AppIcons.schedule,
              size: 18,
              color: session.isActive
                  ? AppColors.fronting
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                startDate,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              session.isActive ? 'Active' : duration,
              style: theme.textTheme.bodySmall?.copyWith(
                color: session.isActive
                    ? AppColors.fronting
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    session.isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              AppIcons.chevronRight,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return 'Today at $hour:$minute';
    }
    if (diff.inDays == 1) return 'Yesterday';

    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

// ── Conversations Section ───────────────────────────────────────────────────

class _ConversationsSection extends ConsumerWidget {
  const _ConversationsSection({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final convsAsync = ref.watch(memberConversationsProvider(memberId));

    return convsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (conversations) {
        if (conversations.isEmpty) return const SizedBox.shrink();

        return _SectionCard(
          icon: AppIcons.chatOutlined,
          title: 'Conversations',
          theme: theme,
          child: Column(
            children: [
              for (var i = 0; i < conversations.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ConversationTile(conversation: conversations[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = ref.watch(terminologyProvider);
    final title =
        conversation.title ?? conversation.emoji ?? 'Conversation';

    return InkWell(
      onTap: () => context.go(AppRoutePaths.chatConversation(conversation.id)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (conversation.emoji != null) ...[
              Text(
                conversation.emoji!,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 12),
            ] else ...[
              Icon(
                AppIcons.chatBubbleOutline,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${conversation.participantIds.length} ${conversation.participantIds.length == 1 ? terms.singularLower : terms.pluralLower}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              AppIcons.chevronRight,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ──────────────────────────────────────────────────────────

enum _MenuAction { setFronter, toggleActive, delete }

/// A card container for detail sections with an icon + title header.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.theme,
    required this.child,
  });

  final IconData icon;
  final String title;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// A row showing a label and value side by side inside a stats card.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small informational chip used in the badges row.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = foregroundColor ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A section showing an icon, title, and content text or custom child widget.
class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.icon,
    required this.title,
    this.content,
    this.child,
  }) : assert(content != null || child != null);

  final IconData icon;
  final String title;
  final String? content;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: child ??
                    Text(
                      content!,
                      style: theme.textTheme.bodyLarge,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
