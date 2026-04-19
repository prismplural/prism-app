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
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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

class _ConversationInfoSheetState extends ConsumerState<ConversationInfoSheet> {
  bool _isEditing = false;
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
      setState(() => _isEditing = false);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(chatNotifierProvider.notifier)
          .updateConversation(
            conversationId,
            title: newTitle,
            emoji: currentEmoji,
          );
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.chatInfoFailedSaveTitle(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEditing = false;
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
      await ref
          .read(chatNotifierProvider.notifier)
          .updateConversation(
            conversationId,
            title: currentTitle,
            emoji: emoji,
          );
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.chatInfoFailedSaveEmoji(e));
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
      PrismToast.success(context, message: context.l10n.chatInfoConversationArchived);
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
      title: context.l10n.chatLeaveConversationTitle,
      message: context.l10n.chatLeaveConversationMessage,
      confirmLabel: context.l10n.chatLeaveConversationConfirm,
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
      title: context.l10n.chatDeleteConversationTitle,
      message: context.l10n.chatDeleteConversationFullMessage,
      confirmLabel: context.l10n.delete,
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
    final conversationAsync = ref.watch(
      conversationByIdProvider(widget.conversationId),
    );
    final speakingAsMemberId = ref.watch(speakingAsProvider);
    final speakingAsMemberAsync = speakingAsMemberId != null
        ? ref.watch(memberByIdProvider(speakingAsMemberId))
        : const AsyncValue<Member?>.data(null);

    return conversationAsync.when(
      loading: () => const SafeArea(child: PrismLoadingState()),
      error: (e, _) => SafeArea(
        child: Center(child: Text(context.l10n.errorWithDetail(e))),
      ),
      data: (conversation) {
        if (conversation == null) {
          return SafeArea(
            child: Column(
              children: [
                PrismSheetTopBar(title: context.l10n.chatInfoTitle),
                Expanded(child: Center(child: Text(context.l10n.chatConversationNotFound))),
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
          child: ClipRect(
            child: Column(
            children: [
              PrismSheetTopBar(
                title: conversation.title ?? context.l10n.chatConversationInfo,
                trailing: _saving
                    ? PrismSpinner(
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      )
                    : permissions.canEditTitleEmoji
                        ? PrismButton(
                            label: _isEditing
                                ? context.l10n.done
                                : context.l10n.edit,
                            density: PrismControlDensity.compact,
                            tone: PrismButtonTone.subtle,
                            onPressed: () {
                              if (_isEditing) {
                                _saveTitle(
                                  conversation.id,
                                  conversation.emoji,
                                );
                              } else {
                                _titleController.text =
                                    conversation.title ?? '';
                                setState(() => _isEditing = true);
                              }
                            },
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
                    _buildHeader(context, conversation, permissions, theme),
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
                      _buildDmSection(conversation, speakingAsMemberId, theme),

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
                                context.l10n.chatInfoCannotManage(speakingAsMember?.name ?? context.l10n.unknown),
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
        Semantics(
          button: true,
          label: context.l10n.chatInfoEditEmoji,
          child: GestureDetector(
            onTap: _isEditing && permissions.canEditTitleEmoji
                ? () => _pickEmoji(conversation.id, conversation.title)
                : null,
            child: Text(
              conversation.emoji ?? (conversation.isDirectMessage ? '' : ''),
              style: const TextStyle(fontSize: 64),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Title: editable when in edit mode, otherwise display
        if (_isEditing && permissions.canEditTitleEmoji)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: PrismTextField(
              controller: _titleController,
              autofocus: true,
              labelText: context.l10n.chatInfoConversationTitle,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  _saveTitle(conversation.id, conversation.emoji),
            ),
          )
        else
          Text(
            conversation.title ??
                (conversation.isDirectMessage
                    ? context.l10n.chatInfoDirectMessage
                    : context.l10n.chatInfoGroupChat),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),

        const SizedBox(height: 4),
        Text(
          context.l10n.chatInfoCreatedAt(conversation.createdAt.toDateString(context.dateLocale)),
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
              context.l10n.chatInfoParticipants(conversation.participantIds.length),
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            if (permissions.canAddMembers)
              PrismIconButton(
                icon: AppIcons.personAdd,
                size: 32,
                iconSize: 18,
                tooltip: context.l10n.chatInfoAddMembers,
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
                  memberName: member.name,
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
        PrismListRow(
          leading: Icon(AppIcons.archiveOutlined),
          title: Text(context.l10n.chatInfoArchiveConversation),
          onTap: () => _archive(conversation.id, speakingAsMemberId),
        ),

        // Leave
        if (permissions.canLeave)
          PrismListRow(
            leading: Icon(AppIcons.exitToApp),
            title: Text(context.l10n.chatInfoLeaveConversation),
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
          PrismListRow(
            leading: Icon(
              AppIcons.deleteOutline,
              color: theme.colorScheme.error,
            ),
            title: Text(
              context.l10n.chatInfoDeleteConversation,
              style: TextStyle(color: theme.colorScheme.error),
            ),
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
          return PrismListRow(
            leading: const MemberAvatar(
              emoji: '?',
              customColorEnabled: false,
              size: 40,
            ),
            title: Text(context.l10n.chatInfoUnknownMember),
          );
        }

        final isOwner =
            participantId ==
            (conversation.creatorId ??
                (conversation.participantIds.isNotEmpty
                    ? conversation.participantIds.first
                    : null));

        final tile = PrismListRow(
          leading: MemberAvatar(
            avatarImageData: member.avatarImageData,
            memberName: member.name,
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
                _RoleChip(label: context.l10n.chatInfoOwner, theme: theme),
              ],
              if (member.isAdmin && !isOwner) ...[
                const SizedBox(width: 8),
                _RoleChip(label: context.l10n.chatInfoAdmin, theme: theme),
              ],
            ],
          ),
          subtitle: member.pronouns != null ? Text(member.pronouns!) : null,
        );

        if (!permissions.canRemoveMembers) return tile;

        return Dismissible(
          key: ValueKey(participantId),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            color: theme.colorScheme.error.withValues(alpha: 0.2),
            child: Icon(AppIcons.personRemove, color: theme.colorScheme.error),
          ),
          confirmDismiss: (_) async {
            await onRemove(participantId);
            return false; // We handle removal in the callback
          },
          child: tile,
        );
      },
      loading: () => PrismListRow(
        title: Text(context.l10n.loading),
      ),
      error: (_, _) => PrismListRow(
        title: Text(context.l10n.chatInfoErrorLoadingMember),
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

    final noneLabel = context.l10n.chatInfoCategoryNone;
    final currentName = currentCategoryId != null
        ? categories
                  .where((c) => c.id == currentCategoryId)
                  .map((c) => c.name)
                  .firstOrNull ??
              noneLabel
        : noneLabel;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: true,
        label: context.l10n.chatInfoCategorySemantics(currentName),
        child: PrismListRow(
          title: Text(context.l10n.chatInfoCategory),
          subtitle: Text(currentName),
          trailing: Icon(AppIcons.chevronRightRounded),
          onTap: () =>
              _showCategorySheet(context, ref, categories, currentName),
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
            title: Text(context.l10n.chatInfoCategoryNone),
            trailing: currentCategoryId == null
                ? Icon(AppIcons.checkRounded)
                : null,
            onTap: () {
              ref
                  .read(chatNotifierProvider.notifier)
                  .updateConversation(conversationId, clearCategory: true);
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
                ref
                    .read(chatNotifierProvider.notifier)
                    .updateConversation(conversationId, categoryId: cat.id);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
