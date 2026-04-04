import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/headmate_picker.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

/// Detail screen for a single member group.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupByIdProvider(groupId));

    return groupAsync.when(
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: '', showBackButton: true),
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: '', showBackButton: true),
        body: Center(child: Text('Error loading group: $e')),
      ),
      data: (group) {
        if (group == null) {
          return const PrismPageScaffold(
            topBar: PrismTopBar(title: '', showBackButton: true),
            body: Center(child: Text('Group not found')),
          );
        }
        return _GroupDetailBody(group: group);
      },
    );
  }
}

class _GroupDetailBody extends ConsumerWidget {
  const _GroupDetailBody({required this.group});

  final MemberGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(groupEntriesProvider(group.id));

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
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, ref),
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

            // Group info header
            _GroupInfoHeader(group: group),

            const SizedBox(height: 24),

            // Members section
            Row(
              children: [
                Icon(AppIcons.peopleOutline,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Members',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            entriesAsync.when(
              loading: () => const PrismLoadingState(),
              error: (e, _) => Text('Error: $e'),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: EmptyState(
                      icon: Icon(AppIcons.personAddOutlined),
                      title: 'No members',
                      subtitle: 'Add members to this group',
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _GroupMemberTile(
                    entry: entries[index],
                    groupId: group.id,
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Add member button
            Center(
              child: TextButton.icon(
                onPressed: () => _addMember(context, ref),
                icon: Icon(AppIcons.personAddOutlined),
                label: const Text('Add member'),
              ),
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
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete group',
      message: 'Are you sure you want to delete "${group.name}"? '
          'Members will not be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      ref.read(groupNotifierProvider.notifier).deleteGroup(group.id);
      if (context.mounted) {
        PrismToast.show(context, message: '${group.name} deleted');
        Navigator.of(context).pop();
      }
    }
  }

  void _addMember(BuildContext context, WidgetRef ref) {
    final entries =
        ref.read(groupEntriesProvider(group.id)).whenOrNull(data: (e) => e) ??
            [];
    final existingMemberIds = entries.map((e) => e.memberId).toSet();

    PrismDialog.show<void>(
      context: context,
      title: 'Add member',
      builder: (ctx) => HeadmatePicker(
        excludeIds: existingMemberIds,
        onSelected: (memberId) {
          if (memberId != null) {
            ref
                .read(groupNotifierProvider.notifier)
                .addMemberToGroup(group.id, memberId);
            Haptics.success();
            Navigator.of(ctx).pop();
            PrismToast.show(context, message: 'Member added');
          }
        },
      ),
    );
  }
}

class _GroupInfoHeader extends StatelessWidget {
  const _GroupInfoHeader({required this.group});

  final MemberGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Emoji or colored circle
        if (group.emoji != null && group.emoji!.isNotEmpty)
          SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: Text(
                group.emoji!,
                style: const TextStyle(fontSize: 36),
              ),
            ),
          )
        else
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor ?? theme.colorScheme.primaryContainer,
            ),
            child: Icon(
              AppIcons.folderOutlined,
              size: 28,
              color: accentColor != null
                  ? AppColors.warmWhite
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (group.description != null &&
                  group.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                MarkdownText(
                  data: group.description!,
                  enabled: true,
                  baseStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (hasColor) ...[
                const SizedBox(height: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupMemberTile extends ConsumerWidget {
  const _GroupMemberTile({
    required this.entry,
    required this.groupId,
  });

  final MemberGroupEntry entry;
  final String groupId;

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
            child: Icon(AppIcons.removeCircleOutline,
                color: theme.colorScheme.onError),
          ),
          confirmDismiss: (_) => _confirmRemove(context, ref, member),
          child: MemberCard(
            member: member,
            onTap: () =>
                context.push(AppRoutePaths.settingsMember(member.id)),
          ),
        );
      },
    );
  }

  Future<bool> _confirmRemove(
      BuildContext context, WidgetRef ref, Member member) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Remove member',
      message:
          'Remove ${member.name} from this group? The member will not be deleted.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed) {
      Haptics.selection();
      ref
          .read(groupNotifierProvider.notifier)
          .removeMemberFromGroup(groupId, entry.memberId);
      if (context.mounted) {
        PrismToast.show(context, message: '${member.name} removed');
      }
    }
    return false; // Don't auto-dismiss; provider stream will update
  }
}
