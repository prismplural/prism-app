import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/delete_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/member_group_row.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Detail screen for a single member group.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    this.settingsBranch = true,
  });

  final String groupId;
  final bool settingsBranch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final groupAsync = ref.watch(groupByIdProvider(groupId));

    return groupAsync.when(
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: '', showBackButton: true),
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: '', showBackButton: true),
        body: Center(child: Text(l10n.memberGroupErrorLoadingDetail(e))),
      ),
      data: (group) {
        if (group == null) {
          return PrismPageScaffold(
            topBar: const PrismTopBar(title: '', showBackButton: true),
            body: Center(child: Text(l10n.memberGroupNotFound)),
          );
        }
        return _GroupDetailBody(group: group, settingsBranch: settingsBranch);
      },
    );
  }
}

class _GroupDetailBody extends ConsumerWidget {
  const _GroupDetailBody({required this.group, required this.settingsBranch});

  final MemberGroup group;
  final bool settingsBranch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final terms = watchTerminology(context, ref);
    final entriesAsync = ref.watch(groupEntriesProvider(group.id));
    ref.watch(activeMembersProvider);
    final allGroupsAsync = ref.watch(allGroupsProvider);
    ref.watch(allGroupEntriesProvider);
    final tree = ref.watch(groupTreeProvider);
    final groupDepth = GroupTreeUtils.getGroupDepth(group.id, tree);
    final canAddSubGroup =
        allGroupsAsync.hasValue && groupDepth < GroupTreeUtils.maxGroupDepth;
    final allGroups =
        allGroupsAsync.whenOrNull(data: (g) => g) ?? const <MemberGroup>[];
    final ancestors = _resolveAncestors(group, allGroups);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: l10n.edit,
            onPressed: () => _openEditSheet(context),
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: l10n.delete,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GroupInfoHeader(group: group, ancestors: ancestors),
            ),

            const SizedBox(height: 24),

            entriesAsync.whenOrNull(
                  data: (entries) {
                    if (entries.isEmpty) return null;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      child: Row(
                        children: [
                          Expanded(
                            child: PrismButton(
                              label: l10n.memberGroupFrontGroup,
                              icon: Icons.group_outlined,
                              tone: PrismButtonTone.subtle,
                              expanded: true,
                              semanticLabel: l10n
                                  .memberGroupFrontGroupSemantics(
                                    group.name,
                                    terms.pluralLower,
                                  ),
                              onPressed: () =>
                                  _onFrontGroup(context, ref, group, entries),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PrismButton(
                              label: l10n.memberGroupStartChat,
                              icon: Icons.chat_bubble_outline,
                              tone: PrismButtonTone.subtle,
                              expanded: true,
                              onPressed: () => _onStartChat(context, entries),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ) ??
                const SizedBox.shrink(),

            _SubGroupsSection(
              groupId: group.id,
              settingsBranch: settingsBranch,
              canAddSubGroup: canAddSubGroup,
              onAddSubGroup: () => _addSubGroup(context),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Icon(
                    AppIcons.peopleOutline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.memberGroupSectionMembers(terms.plural),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PrismInlineIconButton(
                    icon: AppIcons.personAddOutlined,
                    tooltip: l10n.memberGroupAddMember(terms.singularLower),
                    size: 32,
                    iconSize: 20,
                    color: theme.colorScheme.primary,
                    onPressed: () => _addMember(context, ref),
                  ),
                ],
              ),
            ),

            entriesAsync.when(
              loading: () => const PrismLoadingState(),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Error: $e'),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: EmptyState(
                      icon: Icon(AppIcons.personAddOutlined),
                      title: l10n.memberGroupNoMembers(terms.pluralLower),
                      subtitle: l10n.memberGroupNoMembersSubtitle(
                        terms.pluralLower,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _GroupMemberTile(
                    entry: entries[index],
                    groupId: group.id,
                    settingsBranch: settingsBranch,
                  ),
                );
              },
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _openEditSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditGroupSheet(
        scrollController: scrollController,
        group: group,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final hasChildren = ref.read(childGroupsProvider(group.id)).isNotEmpty;

    if (hasChildren) {
      unawaited(
        PrismSheet.show(
          context: context,
          builder: (context) => DeleteGroupSheet(group: group),
        ),
      );
      return;
    }

    final l10n = context.l10n;
    final terms = readTerminology(context, ref);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.memberGroupDeleteTitle,
      message: l10n.memberGroupDeleteMessage(group.name, terms.plural),
      confirmLabel: l10n.memberGroupDeleteConfirm,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      unawaited(ref.read(groupNotifierProvider.notifier).deleteGroup(group.id));
      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.memberGroupDeleted(group.name),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final entries =
        ref.read(groupEntriesProvider(group.id)).whenOrNull(data: (e) => e) ??
        [];
    final existingMemberIds = entries.map((e) => e.memberId).toSet();
    // Non-fronting picker: hide the Unknown sentinel — you don't add the
    // placeholder member to a group.
    final availableMembers =
        (ref.read(userVisibleMembersProvider).value ?? const <Member>[])
            .where((member) => !existingMemberIds.contains(member.id))
            .toList();

    final selectedIds = await MemberSearchSheet.showMulti(
      context,
      members: availableMembers,
      termPlural: readTerminology(context, ref).plural,
      groups: readMemberSearchGroups(ref, availableMembers),
    );
    if (!context.mounted || selectedIds == null || selectedIds.isEmpty) return;

    final notifier = ref.read(groupNotifierProvider.notifier);
    for (final memberId in selectedIds) {
      await notifier.addMemberToGroup(group.id, memberId);
    }

    if (!context.mounted) return;
    Haptics.success();
    PrismToast.show(
      context,
      message: context.l10n.memberAdded(readTerminology(context, ref).singular),
    );
  }

  void _addSubGroup(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditGroupSheet(
        scrollController: scrollController,
        initialParentGroupId: group.id,
      ),
    );
  }

  Future<void> _onFrontGroup(
    BuildContext context,
    WidgetRef ref,
    MemberGroup group,
    List<MemberGroupEntry> entries,
  ) async {
    final l10n = context.l10n;
    final terms = readTerminology(context, ref);
    final memberIds = entries.map((e) => e.memberId).toList();
    if (memberIds.isEmpty) return;

    // Bail if fronting state hasn't loaded yet — collapsing to [] would
    // incorrectly treat everyone as not-fronting and replace the active front.
    final activeSessionsAsync = ref.read(activeSessionsProvider);
    if (!activeSessionsAsync.hasValue) return;
    final activeSessions = activeSessionsAsync.value!;
    // Each session is one member's continuous presence; co-fronting is emergent.
    final alreadyFronting = activeSessions
        .map((s) => s.memberId)
        .whereType<String>()
        .toSet();
    final toAdd = memberIds
        .where((id) => !alreadyFronting.contains(id))
        .toList();

    if (toAdd.isEmpty) {
      // All members already fronting — show a toast instead of a dialog
      if (!context.mounted) return;
      PrismToast.show(
        context,
        message: l10n.memberGroupFrontAllAlreadyFronting(
          terms.pluralLower,
          terms.plural,
        ),
      );
      return;
    }

    final alreadyInGroup = alreadyFronting.intersection(memberIds.toSet());

    if (alreadyInGroup.isNotEmpty) {
      // Some are already fronting — confirm adding the rest
      if (!context.mounted) return;
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: l10n.memberGroupFrontSomeAlreadyFronting(
          alreadyInGroup.length,
          alreadyInGroup.length == 1 ? terms.singularLower : terms.pluralLower,
          toAdd.length,
        ),
      );
      if (!confirmed || !context.mounted) return;
      await ref.read(frontingNotifierProvider.notifier).startFronting(toAdd);
      return;
    }

    // Check if all group members are inactive
    final allMembers =
        ref.read(allMembersProvider).whenOrNull(data: (m) => m) ?? [];
    final groupMembers = allMembers
        .where((m) => memberIds.contains(m.id))
        .toList();
    final allInactive =
        groupMembers.isNotEmpty && groupMembers.every((m) => !m.isActive);

    if (!context.mounted) return;
    if (allInactive) {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: l10n.memberGroupFrontAllInactive(group.name, terms.pluralLower),
      );
      if (!confirmed || !context.mounted) return;
    } else {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: l10n.memberGroupFrontGroupConfirmTitle(group.name),
        message: toAdd.length > 1
            ? l10n.memberGroupFrontGroupConfirmMessage(
                toAdd.length,
                toAdd.length == 1 ? terms.singularLower : terms.pluralLower,
              )
            : null,
      );
      if (!confirmed || !context.mounted) return;
    }

    // Start a per-member session for each group member not already fronting.
    // Each id in `toAdd` gets its own session row sharing the same start_time.
    await ref.read(frontingNotifierProvider.notifier).startFronting(toAdd);
  }

  void _onStartChat(BuildContext context, List<MemberGroupEntry> entries) {
    final memberIds = entries.map((e) => e.memberId).toList();
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateConversationSheet(
        scrollController: scrollController,
        initialMemberIds: memberIds,
      ),
    );
  }
}

class _GroupInfoHeader extends StatelessWidget {
  const _GroupInfoHeader({required this.group, required this.ancestors});

  final MemberGroup group;
  final List<MemberGroup> ancestors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;
    final radius = BorderRadius.circular(PrismShapes.of(context).radius(14));
    final hasEmoji = group.emoji != null && group.emoji!.isNotEmpty;

    return Material(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasColor) Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hasColor ? 12 : 16, 16, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TintedGlassSurface.circle(
                      size: 56,
                      tint: accentColor ?? theme.colorScheme.primary,
                      child: Center(
                        child: hasEmoji
                            ? Text(
                                group.emoji!,
                                style: const TextStyle(fontSize: 30),
                              )
                            : Icon(
                                AppIcons.folderOutlined,
                                size: 26,
                                color: accentColor ?? theme.colorScheme.primary,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ancestors.isNotEmpty) ...[
                            _AncestorBreadcrumb(ancestors: ancestors),
                            const SizedBox(height: 2),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              group.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (group.description != null &&
                              group.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            MarkdownText(
                              data: group.description!,
                              enabled: true,
                              baseStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubGroupsSection extends ConsumerWidget {
  const _SubGroupsSection({
    required this.groupId,
    required this.settingsBranch,
    required this.canAddSubGroup,
    required this.onAddSubGroup,
  });

  final String groupId;
  final bool settingsBranch;
  final bool canAddSubGroup;
  final VoidCallback onAddSubGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final children = ref.watch(childGroupsProvider(groupId));

    if (children.isEmpty && !canAddSubGroup) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Icon(
                AppIcons.folderOutlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.memberGroupSubGroupsLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canAddSubGroup)
                PrismInlineIconButton(
                  icon: AppIcons.add,
                  tooltip: l10n.memberGroupAddSubGroup,
                  size: 32,
                  iconSize: 20,
                  color: theme.colorScheme.primary,
                  onPressed: onAddSubGroup,
                ),
            ],
          ),
        ),
        if (children.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: children.length,
            itemBuilder: (context, index) {
              final group = children[index];
              final count = ref.watch(
                groupMemberCountsProvider.select((m) => m[group.id] ?? 0),
              );
              return MemberGroupRow(
                group: group,
                memberCount: count,
                onTap: () => context.push(
                  settingsBranch
                      ? AppRoutePaths.settingsGroup(group.id)
                      : AppRoutePaths.memberGroup(group.id),
                ),
              );
            },
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _GroupMemberTile extends ConsumerWidget {
  const _GroupMemberTile({
    required this.entry,
    required this.groupId,
    required this.settingsBranch,
  });

  final MemberGroupEntry entry;
  final String groupId;
  final bool settingsBranch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memberAsync = ref.watch(memberByIdProvider(entry.memberId));

    return memberAsync.when(
      loading: () => const SizedBox(height: 64),
      error: (_, _) => const SizedBox.shrink(),
      data: (member) {
        if (member == null) return const SizedBox.shrink();

        return Dismissible(
          key: ValueKey('member_${entry.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: theme.colorScheme.error,
            child: Icon(
              AppIcons.removeCircleOutline,
              color: theme.colorScheme.onError,
            ),
          ),
          confirmDismiss: (_) => _confirmRemove(context, ref, member),
          child: MemberCard(
            member: member,
            onTap: () => context.push(
              settingsBranch
                  ? AppRoutePaths.settingsMember(member.id)
                  : AppRoutePaths.member(member.id),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final l10n = context.l10n;
    final terms = readTerminology(context, ref);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.memberRemoveFromGroupTitle(terms.singular),
      message: l10n.memberRemoveFromGroupMessage(
        member.name,
        terms.singularLower,
      ),
      confirmLabel: l10n.confirm,
      destructive: true,
    );
    if (confirmed) {
      Haptics.selection();
      unawaited(
        ref
            .read(groupNotifierProvider.notifier)
            .removeMemberFromGroup(groupId, entry.memberId),
      );
      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.memberRemoved(member.name),
        );
      }
    }
    return false; // Don't auto-dismiss; provider stream will update
  }
}

List<MemberGroup> _resolveAncestors(MemberGroup group, List<MemberGroup> all) {
  final byId = {for (final g in all) g.id: g};
  final chain = <MemberGroup>[];
  final visited = <String>{group.id};
  String? cur = group.parentGroupId;
  while (cur != null &&
      !visited.contains(cur) &&
      chain.length < GroupTreeUtils.maxGroupDepth) {
    final parent = byId[cur];
    if (parent == null) break;
    chain.insert(0, parent);
    visited.add(cur);
    cur = parent.parentGroupId;
  }
  return chain;
}

class _AncestorBreadcrumb extends StatelessWidget {
  const _AncestorBreadcrumb({required this.ancestors});

  final List<MemberGroup> ancestors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final separatorColor = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.5,
    );

    final children = <Widget>[];
    for (var i = 0; i < ancestors.length; i++) {
      final ancestor = ancestors[i];
      if (ancestor.emoji != null && ancestor.emoji!.isNotEmpty) {
        children.add(
          Text(ancestor.emoji!, style: const TextStyle(fontSize: 12)),
        );
        children.add(const SizedBox(width: 4));
      }
      children.add(
        Flexible(
          child: Text(
            ancestor.name,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      children.add(const SizedBox(width: 6));
      children.add(
        Icon(AppIcons.chevronRight, size: 12, color: separatorColor),
      );
      if (i < ancestors.length - 1) {
        children.add(const SizedBox(width: 6));
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
