import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/views/add_members_sheet.dart';
import 'package:prism_plurality/features/chat/views/creator_transfer_picker.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Full-screen sheet for viewing and managing conversation details.
///
/// Replaces the old push-navigation `ConversationInfoScreen` with a
/// [PrismSheet.showFullScreen] modal. Handles inline title/emoji editing,
/// participant management, archive, leave, and delete — all permission-gated.
class ConversationInfoSheet extends ConsumerStatefulWidget {
  const ConversationInfoSheet({
    super.key,
    required this.conversationId,
    required this.scrollController,
  });

  final String conversationId;
  final ScrollController scrollController;

  /// Present the conversation info sheet as a full-screen modal.
  static Future<void> show(BuildContext context, String conversationId) {
    return PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => ConversationInfoSheet(
        conversationId: conversationId,
        scrollController: scrollController,
      ),
    );
  }

  @override
  ConsumerState<ConversationInfoSheet> createState() =>
      _ConversationInfoSheetState();
}

class _ConversationInfoSheetState
    extends ConsumerState<ConversationInfoSheet> {
  bool _editingTitle = false;
  final _titleController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveTitle(String conversationId, String? currentEmoji) async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty) {
      setState(() => _editingTitle = false);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(chatNotifierProvider.notifier).updateConversation(
            conversationId,
            title: newTitle,
            emoji: currentEmoji,
          );
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Failed to save title: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _editingTitle = false;
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickEmoji(String conversationId, String? currentTitle) async {
    final emoji = await PrismEmojiPicker.showPicker(context);
    if (emoji == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(chatNotifierProvider.notifier).updateConversation(
            conversationId,
            title: currentTitle,
            emoji: emoji,
          );
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Failed to save emoji: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive(
    String conversationId,
    String? speakingAsMemberId,
  ) async {
    if (speakingAsMemberId == null) return;
    await ref
        .read(chatNotifierProvider.notifier)
        .archiveConversation(conversationId, speakingAsMemberId);
    if (mounted) {
      PrismToast.success(context, message: 'Conversation archived');
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmLeave(
    Conversation conversation,
    ConversationPermissions permissions,
    String speakingAsMemberId,
    List<Member> allParticipantMembers,
  ) async {
    // If creator is leaving, transfer ownership first.
    if (permissions.isCreator) {
      final remaining = allParticipantMembers
          .where((m) => m.id != speakingAsMemberId)
          .toList();
      if (remaining.isEmpty) {
        // Last member — just leave.
      } else {
        final newCreator = await showCreatorTransferPicker(
          context,
          remainingMembers: remaining,
        );
        if (newCreator == null) return; // cancelled
        await ref
            .read(chatNotifierProvider.notifier)
            .transferCreator(conversation.id, newCreator);
      }
    }

    if (!mounted) return;

    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Leave Conversation',
      message: 'Leave this conversation? Your past messages will remain.',
      confirmLabel: 'Leave',
      destructive: true,
    );

    if (!confirmed || !mounted) return;

    await ref
        .read(chatNotifierProvider.notifier)
        .leaveConversation(conversation.id, speakingAsMemberId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(String conversationId) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete Conversation',
      message: 'Are you sure you want to delete this conversation? '
          'All messages will be permanently removed. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (!confirmed || !mounted) return;

    await ref
        .read(chatNotifierProvider.notifier)
        .deleteConversation(conversationId);
    if (mounted) {
      Navigator.of(context).pop(); // close sheet
      context.go(AppRoutePaths.chat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversationAsync =
        ref.watch(conversationByIdProvider(widget.conversationId));
    final speakingAsMemberId = ref.watch(speakingAsProvider);
    final speakingAsMemberAsync = speakingAsMemberId != null
        ? ref.watch(memberByIdProvider(speakingAsMemberId))
        : const AsyncValue<Member?>.data(null);

    return conversationAsync.when(
      loading: () => const SafeArea(child: PrismLoadingState()),
      error: (e, _) => SafeArea(
        child: Center(child: Text('Error: $e')),
      ),
      data: (conversation) {
        if (conversation == null) {
          return const SafeArea(
            child: Column(
              children: [
                PrismSheetTopBar(title: 'Info'),
                Expanded(
                  child: Center(child: Text('Conversation not found')),
                ),
              ],
            ),
          );
        }

        final speakingAsMember = speakingAsMemberAsync.value;
        final permissions = ConversationPermissions(
          conversation: conversation,
          speakingAsMemberId: speakingAsMemberId,
          speakingAsMember: speakingAsMember,
        );

        return SafeArea(
          child: Column(
            children: [
              PrismSheetTopBar(
                title: conversation.title ?? 'Conversation Info',
                trailing: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 32,
                  ),
                  children: [
                    // HEADER SECTION
                    _buildHeader(
                      context,
                      conversation,
                      permissions,
                      theme,
                    ),
                    const Divider(height: 32),

                    // PARTICIPANTS or DM SECTION
                    if (!conversation.isDirectMessage)
                      _buildParticipantsSection(
                        context,
                        conversation,
                        permissions,
                        speakingAsMemberId,
                        speakingAsMember,
                        theme,
                      )
                    else
                      _buildDmSection(
                        conversation,
                        speakingAsMemberId,
                        theme,
                      ),

                    const Divider(height: 32),

                    // PERMISSION BANNER
                    if (!permissions.canManage &&
                        !conversation.isDirectMessage) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.infoOutline,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${speakingAsMember?.name ?? 'Current member'} can\'t manage this conversation',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ACTIONS SECTION
                    _buildActionsSection(
                      context,
                      conversation,
                      permissions,
                      speakingAsMemberId,
                      theme,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Conversation conversation,
    ConversationPermissions permissions,
    ThemeData theme,
  ) {
    return Column(
      children: [
        const SizedBox(height: 8),

        // Emoji
        GestureDetector(
          onTap: permissions.canEditTitleEmoji
              ? () => _pickEmoji(conversation.id, conversation.title)
              : null,
          child: Text(
            conversation.emoji ?? (conversation.isDirectMessage ? '' : ''),
            style: const TextStyle(fontSize: 64),
          ),
        ),
        const SizedBox(height: 12),

        // Title: inline edit or display
        if (_editingTitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: PrismTextField(
              controller: _titleController,
              autofocus: true,
              hintText: 'Conversation title',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  _saveTitle(conversation.id, conversation.emoji),
            ),
          )
        else
          GestureDetector(
            onTap: permissions.canEditTitleEmoji
                ? () {
                    _titleController.text = conversation.title ?? '';
                    setState(() => _editingTitle = true);
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    conversation.title ??
                        (conversation.isDirectMessage
                            ? 'Direct Message'
                            : 'Group Chat'),
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (permissions.canEditTitleEmoji) ...[
                  const SizedBox(width: 6),
                  Icon(
                    AppIcons.edit,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),

        const SizedBox(height: 4),
        Text(
          'Created ${conversation.createdAt.toDateString()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        // Category picker
        if (!conversation.isDirectMessage && permissions.canManage)
          _CategoryPicker(
            conversationId: conversation.id,
            currentCategoryId: conversation.categoryId,
          ),
      ],
    );
  }

  Widget _buildParticipantsSection(
    BuildContext context,
    Conversation conversation,
    ConversationPermissions permissions,
    String? speakingAsMemberId,
    Member? speakingAsMember,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Text(
              'Participants (${conversation.participantIds.length})',
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            if (permissions.canAddMembers)
              IconButton(
                icon: Icon(AppIcons.personAdd, size: 20),
                tooltip: 'Add members',
                onPressed: () => AddMembersSheet.show(context, conversation),
              ),
          ],
        ),
        const SizedBox(height: 4),

        // Participant tiles
        for (final participantId in conversation.participantIds)
          _ParticipantTile(
            participantId: participantId,
            conversation: conversation,
            permissions: permissions,
            speakingAsMemberId: speakingAsMemberId,
            speakingAsMember: speakingAsMember,
            onRemove: (memberId) async {
              // If removing creator, transfer first
              if (memberId == conversation.creatorId) {
                final remaining = <Member>[];
                for (final pid in conversation.participantIds) {
                  if (pid == memberId) continue;
                  final m = ref.read(memberByIdProvider(pid)).value;
                  if (m != null) remaining.add(m);
                }
                final newCreator = await showCreatorTransferPicker(
                  context,
                  remainingMembers: remaining,
                );
                if (newCreator == null) return;
                await ref
                    .read(chatNotifierProvider.notifier)
                    .transferCreator(conversation.id, newCreator);
              }

              final fronterName = speakingAsMember?.name ?? 'Unknown';
              await ref
                  .read(chatNotifierProvider.notifier)
                  .removeParticipant(
                    conversation.id,
                    memberId,
                    removedByName: fronterName,
                  );
            },
          ),
      ],
    );
  }

  Widget _buildDmSection(
    Conversation conversation,
    String? speakingAsMemberId,
    ThemeData theme,
  ) {
    // Show the other participant
    final otherId = conversation.participantIds
        .where((id) => id != speakingAsMemberId)
        .firstOrNull;

    if (otherId == null) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, _) {
        final memberAsync = ref.watch(memberByIdProvider(otherId));
        return memberAsync.when(
          data: (member) {
            if (member == null) return const SizedBox.shrink();
            return Column(
              children: [
                MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  emoji: member.emoji,
                  customColorEnabled: member.customColorEnabled,
                  customColorHex: member.customColorHex,
                  size: 72,
                ),
                const SizedBox(height: 12),
                Text(
                  member.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (member.pronouns != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    member.pronouns!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => const PrismLoadingState(),
          error: (_, _) => const Text('Error loading member'),
        );
      },
    );
  }

  Widget _buildActionsSection(
    BuildContext context,
    Conversation conversation,
    ConversationPermissions permissions,
    String? speakingAsMemberId,
    ThemeData theme,
  ) {
    return Column(
      children: [
        // Archive
        ListTile(
          leading: Icon(AppIcons.archiveOutlined),
          title: const Text('Archive conversation'),
          contentPadding: EdgeInsets.zero,
          onTap: () => _archive(conversation.id, speakingAsMemberId),
        ),

        // Leave
        if (permissions.canLeave)
          ListTile(
            leading: Icon(AppIcons.exitToApp),
            title: const Text('Leave conversation'),
            contentPadding: EdgeInsets.zero,
            onTap: () async {
              if (speakingAsMemberId == null) return;

              // Build participant Member list for potential transfer.
              final allParticipants = <Member>[];
              for (final pid in conversation.participantIds) {
                final m = ref.read(memberByIdProvider(pid)).value;
                if (m != null) allParticipants.add(m);
              }

              await _confirmLeave(
                conversation,
                permissions,
                speakingAsMemberId,
                allParticipants,
              );
            },
          ),

        // Delete
        if (permissions.canDeleteConversation)
          ListTile(
            leading: Icon(AppIcons.deleteOutline,
                color: theme.colorScheme.error),
            title: Text('Delete conversation',
                style: TextStyle(color: theme.colorScheme.error)),
            contentPadding: EdgeInsets.zero,
            onTap: () => _confirmDelete(conversation.id),
          ),
      ],
    );
  }
}

/// A single participant list tile with swipe-to-remove support.
class _ParticipantTile extends ConsumerWidget {
  const _ParticipantTile({
    required this.participantId,
    required this.conversation,
    required this.permissions,
    required this.speakingAsMemberId,
    required this.speakingAsMember,
    required this.onRemove,
  });

  final String participantId;
  final Conversation conversation;
  final ConversationPermissions permissions;
  final String? speakingAsMemberId;
  final Member? speakingAsMember;
  final Future<void> Function(String memberId) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memberAsync = ref.watch(memberByIdProvider(participantId));

    return memberAsync.when(
      data: (member) {
        if (member == null) {
          return const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar(
              emoji: '?',
              customColorEnabled: false,
              size: 40,
            ),
            title: Text('Unknown Member'),
          );
        }

        final isOwner = participantId == (conversation.creatorId ??
            (conversation.participantIds.isNotEmpty
                ? conversation.participantIds.first
                : null));

        final tile = ListTile(
          contentPadding: EdgeInsets.zero,
          leading: MemberAvatar(
            avatarImageData: member.avatarImageData,
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
            size: 40,
          ),
          title: Row(
            children: [
              Flexible(child: Text(member.name)),
              if (isOwner) ...[
                const SizedBox(width: 8),
                _RoleChip(label: 'Owner', theme: theme),
              ],
              if (member.isAdmin && !isOwner) ...[
                const SizedBox(width: 8),
                _RoleChip(label: 'Admin', theme: theme),
              ],
            ],
          ),
          subtitle:
              member.pronouns != null ? Text(member.pronouns!) : null,
        );

        if (!permissions.canRemoveMembers) return tile;

        return Dismissible(
          key: ValueKey(participantId),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            color: theme.colorScheme.error.withValues(alpha: 0.2),
            child: Icon(AppIcons.personRemove,
                color: theme.colorScheme.error),
          ),
          confirmDismiss: (_) async {
            await onRemove(participantId);
            return false; // We handle removal in the callback
          },
          child: tile,
        );
      },
      loading: () => const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Loading...'),
      ),
      error: (_, _) => const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Error loading member'),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Inline category picker that opens a selection sheet.
class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({
    required this.conversationId,
    required this.currentCategoryId,
  });

  final String conversationId;
  final String? currentCategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(conversationCategoriesProvider);
    final categories = categoriesAsync.value ?? [];

    if (categories.isEmpty) return const SizedBox.shrink();

    final currentName = currentCategoryId != null
        ? categories
            .where((c) => c.id == currentCategoryId)
            .map((c) => c.name)
            .firstOrNull ??
          'None'
        : 'None';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: true,
        label: 'Category: $currentName',
        child: PrismListRow(
          title: const Text('Category'),
          subtitle: Text(currentName),
          trailing: Icon(AppIcons.chevronRightRounded),
          onTap: () => _showCategorySheet(context, ref, categories, currentName),
        ),
      ),
    );
  }

  void _showCategorySheet(
    BuildContext context,
    WidgetRef ref,
    List<ConversationCategory> categories,
    String currentName,
  ) {
    PrismSheet.show(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrismListRow(
            title: const Text('None'),
            trailing: currentCategoryId == null
                ? Icon(AppIcons.checkRounded)
                : null,
            onTap: () {
              ref.read(chatNotifierProvider.notifier).updateConversation(
                    conversationId,
                    clearCategory: true,
                  );
              Navigator.of(context).pop();
            },
          ),
          for (final cat in categories)
            PrismListRow(
              title: Text(cat.name),
              trailing: cat.id == currentCategoryId
                  ? Icon(AppIcons.checkRounded)
                  : null,
              onTap: () {
                ref.read(chatNotifierProvider.notifier).updateConversation(
                      conversationId,
                      categoryId: cat.id,
                    );
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
