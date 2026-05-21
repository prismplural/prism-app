import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/profile_entity_mentions_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/mentions/entity_mention.dart';
import 'package:prism_plurality/shared/mentions/entity_mention_visibility.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

Future<void> openProfileEntityMention(
  BuildContext context,
  WidgetRef ref,
  ProfileEntityMentionResolution resolution,
) async {
  final target = resolution.target;
  final fresh = await _freshResolutionForNavigation(ref, target);
  if (!fresh.visible || !context.mounted) return;

  switch (target.type) {
    case EntityMentionType.member:
      await context.push(AppRoutePaths.member(target.id));
    case EntityMentionType.group:
      await context.push(AppRoutePaths.group(target.id));
    case EntityMentionType.note:
      await context.push(AppRoutePaths.note(target.id));
    case EntityMentionType.board:
      await context.push(AppRoutePaths.boardPost(target.id));
    case EntityMentionType.conversation:
      final conversation = fresh.entity;
      if (conversation is Conversation) {
        await _openConversationMention(context, ref, conversation);
      }
  }
}

Future<ProfileEntityMentionResolution> _freshResolutionForNavigation(
  WidgetRef ref,
  EntityMentionTarget target,
) async {
  switch (target.type) {
    case EntityMentionType.member:
      final members = ref.read(userVisibleMembersProvider).value ?? const [];
      final member = members.cast<Member?>().firstWhere(
        (member) => member?.id == target.id,
        orElse: () => null,
      );
      return ProfileEntityMentionResolution(
        target: target,
        visible: canMentionMember(member),
        entity: member,
      );
    case EntityMentionType.group:
      final groups = ref.read(allGroupsProvider).value ?? const [];
      final visibleGroupIds = ref
          .read(flatGroupListProvider)
          .map((item) => item.group.id)
          .toSet();
      MemberGroup? group;
      for (final candidate in groups) {
        if (candidate.id == target.id) {
          group = candidate;
          break;
        }
      }
      final visible = canMentionGroup(group, visibleGroupIds);
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        entity: visible ? group : null,
      );
    case EntityMentionType.note:
      final note = ref.read(notesEnabledProvider)
          ? await ref
                .read(notesRepositoryProvider)
                .getMentionNoteById(target.id)
          : null;
      final visible = canMentionNote(
        note,
        notesEnabled: ref.read(notesEnabledProvider),
      );
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        entity: visible ? note : null,
      );
    case EntityMentionType.board:
      final post = ref.read(boardsEnabledProvider)
          ? await ref
                .read(memberBoardPostsRepositoryProvider)
                .getPostById(target.id)
          : null;
      final visible =
          ref.read(boardsEnabledProvider) &&
          canActiveFrontViewBoardPost(
            post,
            activeFronters: ref.read(profileMentionActiveFrontersProvider),
          );
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        entity: visible ? post : null,
      );
    case EntityMentionType.conversation:
      final conversation = ref.read(chatEnabledProvider)
          ? await ref
                .read(conversationRepositoryProvider)
                .getMentionConversationById(target.id)
          : null;
      final visible =
          ref.read(chatEnabledProvider) &&
          canActiveFrontViewConversation(
            conversation,
            activeFronters: ref.read(profileMentionActiveFrontersProvider),
          );
      return ProfileEntityMentionResolution(
        target: target,
        visible: visible,
        entity: visible ? conversation : null,
      );
  }
}

Future<void> _openConversationMention(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation,
) async {
  final speakingAs = ref.read(speakingAsProvider);
  final activeMembers =
      ref.read(activeMembersProvider).value ?? const <Member>[];
  final activeMemberById = {
    for (final member in activeMembers)
      if (canMentionMember(member)) member.id: member,
  };

  final currentMember = speakingAs == null
      ? null
      : activeMemberById[speakingAs];
  final currentPermissions = ConversationPermissions(
    conversation: conversation,
    speakingAsMemberId: speakingAs,
    speakingAsMember: currentMember,
  );
  if (currentPermissions.canView) {
    await context.push(AppRoutePaths.chatConversation(conversation.id));
    return;
  }

  final visibleFronters = activeFrontersWhoCanViewConversation(
    conversation,
    activeFronters: ref.read(profileMentionActiveFrontersProvider),
  );
  if (visibleFronters.isEmpty || !context.mounted) return;

  Member? viewer;
  if (visibleFronters.length == 1) {
    viewer = await _confirmSingleConversationViewer(
      context,
      visibleFronters.single,
    );
  } else {
    viewer = await _chooseConversationViewer(context, visibleFronters);
  }
  if (viewer == null || !context.mounted) return;

  await context.push(
    AppRoutePaths.chatConversationAs(conversation.id, viewer.id),
  );
}

Future<Member?> _confirmSingleConversationViewer(
  BuildContext context,
  Member member,
) async {
  final confirmed = await PrismDialog.confirm(
    context: context,
    title: context.l10n.profileMentionOpenConversationTitle,
    message: context.l10n.profileMentionOpenConversationMessage(member.name),
    confirmLabel: context.l10n.profileMentionOpenConversationConfirm(
      member.name,
    ),
    cancelLabel: context.l10n.cancel,
  );
  return confirmed ? member : null;
}

Future<Member?> _chooseConversationViewer(
  BuildContext context,
  List<Member> members,
) {
  return PrismDialog.show<Member>(
    context: context,
    title: context.l10n.profileMentionOpenConversationTitle,
    message: context.l10n.profileMentionOpenConversationPickerMessage,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: members.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final member = members[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(dialogContext).pop(member),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: Text(
                  member.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
    actions: [
      Builder(
        builder: (dialogContext) => PrismButton(
          label: dialogContext.l10n.cancel,
          tone: PrismButtonTone.outlined,
          onPressed: () => Navigator.of(dialogContext).pop(null),
        ),
      ),
    ],
  );
}
