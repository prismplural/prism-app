import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Entry point for adding members to an existing conversation.
///
/// Call [AddMembersSheet.show] — it presents [MemberSearchSheet] in
/// multi-select mode (excluding existing participants), then commits the
/// selection via [ChatNotifier.addParticipants].
class AddMembersSheet {
  const AddMembersSheet._();

  /// Show the Add Members flow.
  ///
  /// Returns `true` when members were successfully added, or `null` when the
  /// user cancelled or an error prevented the operation.
  static Future<bool?> show(
    BuildContext context,
    Conversation conversation,
  ) async {
    final container = ProviderScope.containerOf(context);
    final selectedIds = await PrismSheet.show<Set<String>>(
      context: context,
      maxHeightFactor: 0.95,
      builder: (ctx) => _AddMembersContent(conversation: conversation),
    );

    if (selectedIds == null || selectedIds.isEmpty || !context.mounted) {
      return null;
    }

    final allMembers = container.read(activeMembersProvider).value ?? [];
    final speakingAs = container.read(speakingAsProvider);
    String? speakingAsName;
    if (speakingAs != null) {
      speakingAsName = allMembers
          .where((m) => m.id == speakingAs)
          .map((m) => m.name)
          .firstOrNull;
    }

    try {
      await container
          .read(chatNotifierProvider.notifier)
          .addParticipants(
            conversation.id,
            selectedIds.toList(),
            addedByName: speakingAsName,
          );
      return true;
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.chatAddMembersFailed(e),
        );
      }
      return null;
    }
  }
}

class _AddMembersContent extends ConsumerWidget {
  const _AddMembersContent({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(activeMembersProvider);
    final s = ref.watch(terminologySettingProvider);
    final termPlural = resolveTerminology(
      context.l10n,
      s.term,
      customSingular: s.customSingular,
      customPlural: s.customPlural,
      useEnglish: s.useEnglish,
    ).plural;

    final existingIds = conversation.participantIds.toSet();

    return membersAsync.when(
      data: (members) {
        final available = members
            .where((member) => !existingIds.contains(member.id))
            .toList();
        return MemberSearchSheet(
          members: available,
          termPlural: termPlural,
          groups: watchMemberSearchGroups(ref, available),
          multiSelect: true,
        );
      },
      loading: () => const Center(child: PrismLoadingState()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.chatAddMembersFailed(e),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }
}
