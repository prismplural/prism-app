import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
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
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/members/widgets/member_groups_section.dart';
import 'package:prism_plurality/features/members/widgets/proxy_tags_section.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_display.dart';
import 'package:prism_plurality/features/boards/widgets/board_message_section.dart';
import 'package:prism_plurality/features/members/widgets/notes_section.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';

/// Detail screen for a single system member, pushed via go_router.
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
          child: Text(
            'Error loading ${readTerminology(context, ref).singularLower}: $e',
          ),
        ),
      ),
      data: (member) {
        if (member == null) {
          return PrismPageScaffold(
            topBar: const PrismTopBar(title: '', showBackButton: true),
            body: Center(
              child: Text(
                '${readTerminology(context, ref).singular} not found',
              ),
            ),
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
    final l10n = context.l10n;
    final terms = watchTerminology(context, ref);
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final isFronting =
        activeSessionsAsync.whenOrNull(data: _isFronting) ?? false;

    final memberAccent =
        (member.customColorEnabled &&
            member.customColorHex != null &&
            member.customColorHex!.isNotEmpty)
        ? AppColors.fromHex(member.customColorHex!)
        : null;

    Widget body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, NavBarInset.of(context)),
      child: _buildBodyColumn(context, theme, isFronting),
    );

    if (memberAccent != null) {
      body = Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(primary: memberAccent),
        ),
        child: body,
      );
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: l10n.memberEditTooltip(terms.singularLower),
            onPressed: () => _openEditSheet(context),
          ),
          _MoreMenuButton(
            member: member,
            onAction: (action) => _handleMenuAction(context, ref, action),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: body,
    );
  }

  Widget _buildBodyColumn(
    BuildContext context,
    ThemeData theme,
    bool isFronting,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        MemberProfileHeader(member: member, isFronting: isFronting),
        if (member.bio != null && member.bio!.isNotEmpty) ...[
          const SizedBox(height: 12),
          MarkdownText(
            data: member.bio!,
            enabled: member.markdownEnabled,
            baseStyle: theme.textTheme.bodyLarge,
          ),
        ],
        const SizedBox(height: 24),
        CustomFieldsDisplay(memberId: member.id),
        NotesSection(memberId: member.id),
        MemberGroupsSection(memberId: member.id, memberName: member.name),
        ProxyTagsSection(member: member),
        _FrontingStatsSection(memberId: member.id),
        const SizedBox(height: 8),
        _RecentSessionsSection(memberId: member.id),
        const SizedBox(height: 8),
        _ConversationsSection(memberId: member.id),
        BoardMessageSection(memberId: member.id),
        const SizedBox(height: 32),
      ],
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

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.setFronter:
        try {
          await ref.read(frontingNotifierProvider.notifier).startFronting([
            member.id,
          ]);
          if (context.mounted) {
            PrismToast.show(
              context,
              message: context.l10n.memberIsFronting(member.name),
            );
          }
        } catch (e) {
          if (context.mounted) {
            PrismToast.error(
              context,
              message: context.l10n.frontingErrorWakingUp(e),
            );
          }
        }
      case _MenuAction.toggleActive:
        await ref
            .read(membersNotifierProvider.notifier)
            .updateMember(member.copyWith(isActive: !member.isActive));
      case _MenuAction.delete:
        await _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final terms = readTerminology(context, ref);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete ${terms.singularLower}?',
      message:
          'Are you sure you want to delete ${member.name}? '
          'This action cannot be undone.',
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      unawaited(
        ref.read(membersNotifierProvider.notifier).deleteMember(member.id),
      );
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
    final l10n = context.l10n;
    final statsAsync = ref.watch(memberFrontingStatsProvider(memberId));

    return statsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: PrismLoadingState(),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (stats) {
        if (stats.totalSessions == 0) {
          return const SizedBox.shrink();
        }

        return _SectionCard(
          icon: AppIcons.barChartOutlined,
          title: l10n.memberSectionFrontingStats,
          theme: theme,
          child: Column(
            children: [
              _StatRow(
                label: l10n.memberStatsTotalSessions,
                value: '${stats.totalSessions}',
                theme: theme,
              ),
              const Divider(height: 1),
              _StatRow(
                label: l10n.memberStatsTotalTime,
                value: stats.totalDuration.toRoundedString(),
                theme: theme,
              ),
              if (stats.lastFronted != null) ...[
                const Divider(height: 1),
                _StatRow(
                  label: l10n.memberStatsLastFronted,
                  value: _formatTimestamp(l10n, stats.lastFronted!),
                  theme: theme,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatTimestamp(dynamic l10n, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) return l10n.memberStatsToday as String;
    if (diff.inDays == 1) return l10n.memberStatsYesterday as String;
    if (diff.inDays < 7) return l10n.memberStatsDaysAgo(diff.inDays) as String;
    if (diff.inDays < 30) {
      return l10n.memberStatsWeeksAgo(diff.inDays ~/ 7) as String;
    }
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
          title: context.l10n.memberSectionRecentSessions,
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
    final l10n = context.l10n;
    final startDate = _formatDate(l10n, session.startTime);
    final duration = session.duration.toRoundedString();

    return InkWell(
      onTap: () => context.go(AppRoutePaths.session(session.id)),
      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              session.isActive ? AppIcons.flashOn : AppIcons.schedule,
              size: 18,
              color: session.isActive
                  ? AppColors.fronting(theme.brightness)
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(startDate, style: theme.textTheme.bodyMedium)),
            Text(
              session.isActive ? l10n.memberSessionActive : duration,
              style: theme.textTheme.bodySmall?.copyWith(
                color: session.isActive
                    ? AppColors.fronting(theme.brightness)
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: session.isActive
                    ? FontWeight.w600
                    : FontWeight.normal,
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

  String _formatDate(dynamic l10n, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return l10n.memberSessionTodayAt('$hour:$minute') as String;
    }
    if (diff.inDays == 1) return l10n.memberStatsYesterday as String;

    return '${dt.month}/${dt.day}/${dt.year}';
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
          title: context.l10n.memberSectionConversations,
          theme: theme,
          child: Column(
            children: [
              for (var i = 0; i < conversations.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ConversationTile(
                  conversation: conversations[i],
                  memberId: memberId,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation, required this.memberId});

  final Conversation conversation;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title =
        conversation.title ??
        conversation.emoji ??
        context.l10n.memberConversationFallback;

    final allMembersAsync = ref.watch(allMembersProvider);
    final subtitle = allMembersAsync.whenOrNull(
      data: (members) {
        final others = members
            .where(
              (m) =>
                  m.id != memberId &&
                  conversation.participantIds.contains(m.id),
            )
            .toList();
        if (others.isEmpty) return '';
        if (others.length == 1) return others[0].name;
        if (others.length == 2) return '${others[0].name}, ${others[1].name}';
        final extra = others.length - 2;
        return '${others[0].name}, ${others[1].name} +$extra more';
      },
    );

    return InkWell(
      onTap: () => context.go(AppRoutePaths.chatConversation(conversation.id)),
      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (conversation.emoji != null) ...[
              Text(conversation.emoji!, style: const TextStyle(fontSize: 20)),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
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
            child: PrismSectionCard(child: child),
          ),
        ],
      ),
    );
  }
}

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

class _MoreMenuButton extends StatelessWidget {
  const _MoreMenuButton({required this.member, required this.onAction});

  final Member member;
  final ValueChanged<_MenuAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (
        action: _MenuAction.setFronter,
        label: l10n.memberSetAsFronter,
        icon: AppIcons.flashOn,
        destructive: false,
      ),
      (
        action: _MenuAction.toggleActive,
        label: member.isActive ? l10n.deactivate : l10n.activate,
        icon: member.isActive ? AppIcons.visibilityOff : AppIcons.visibility,
        destructive: false,
      ),
      (
        action: _MenuAction.delete,
        label: l10n.delete,
        icon: AppIcons.deleteOutline,
        destructive: true,
      ),
    ];

    return BlurPopupAnchor(
      trigger: BlurPopupTrigger.tap,
      preferredDirection: BlurPopupDirection.down,
      width: 200,
      maxHeight: 240,
      itemCount: items.length,
      itemBuilder: (context, index, close) {
        final item = items[index];
        final theme = Theme.of(context);
        final color = item.destructive
            ? theme.colorScheme.error
            : theme.colorScheme.onSurface;
        return PrismListRow(
          dense: true,
          leading: Icon(item.icon, size: 20, color: color),
          title: Text(item.label, style: TextStyle(fontSize: 14, color: color)),
          onTap: () {
            close();
            onAction(item.action);
          },
        );
      },
      child: PrismTopBarAction(
        icon: AppIcons.moreVert,
        tooltip: l10n.memberMoreOptionsTooltip,
        onPressed: null,
      ),
    );
  }
}
