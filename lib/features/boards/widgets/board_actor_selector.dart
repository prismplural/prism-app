import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/boards/providers/board_actor_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Board actor selection is separate from any view/recipient filter.
class BoardActorSelector extends ConsumerWidget {
  const BoardActorSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(boardActorMemberProvider);
    final members = (ref.watch(userVisibleMemberListProvider).value ?? [])
        .where((member) => member.isActive && !member.isDeleted)
        .toList();
    final terms = watchTerminology(context, ref);
    final label = actor == null
        ? context.l10n.boardsComposeSelectAuthor
        : '${context.l10n.boardsComposeWhoIsPosting} ${actor.name}';
    return Stack(
      alignment: Alignment.center,
      children: [
        PrismTopBarAction(
          key: const ValueKey('boards.actorSelector'),
          icon: actor == null ? Icons.person_outline : Icons.swap_horiz,
          tooltip: label,
          onPressed: members.isEmpty
              ? null
              : () async {
                  final result = await MemberSearchSheet.showSingle(
                    context,
                    members: members,
                    termPlural: terms.plural,
                    title: context.l10n.boardsComposeWhoIsPosting,
                    groups: readMemberSearchGroups(ref, members),
                  );
                  if (!context.mounted) return;
                  if (result is MemberSearchResultSelected) {
                    ref
                        .read(boardActorProvider.notifier)
                        .setMember(result.memberId);
                  }
                },
        ),
        if (actor != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: MemberAvatar(
                memberId: actor.id,
                memberName: actor.name,
                avatarImageData: actor.avatarImageData,
                emoji: actor.emoji,
                size: 16,
              ),
            ),
          ),
      ],
    );
  }
}
