import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

/// Systems with more members than this threshold use the search sheet instead
/// of the chip row, keeping the picker fast for large systems.
const int _kSpeakingAsPickerSearchThreshold = 15;

/// Horizontal scrollable row of member avatars for selecting who is "speaking."
///
/// For systems with fewer than [_kSpeakingAsPickerSearchThreshold] members the
/// existing chip row is shown. For larger systems a compact trigger row launches
/// the shared [MemberSearchSheet] so the user can search by name.
class SpeakingAsPicker extends ConsumerWidget {
  const SpeakingAsPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final speakingAs = ref.watch(speakingAsProvider);
    final termPlural = watchTerminology(context, ref).plural;

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              context.l10n.chatNoMembersAvailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        // Auto-select first member if none selected (both paths).
        if (speakingAs == null && members.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(speakingAsProvider.notifier).setMember(members.first.id);
          });
        }

        final searchGroups = watchMemberSearchGroups(ref, members);

        if (members.length >= _kSpeakingAsPickerSearchThreshold) {
          return _buildSearchTrigger(
            context,
            ref,
            theme,
            members,
            speakingAs,
            termPlural,
            searchGroups,
          );
        }

        return SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final member = members[index];
              return PrismChip(
                label: member.name,
                selected: member.id == speakingAs,
                onTap: () =>
                    ref.read(speakingAsProvider.notifier).setMember(member.id),
                avatar: MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  memberName: member.name,
                  emoji: member.emoji,
                  customColorEnabled: member.customColorEnabled,
                  customColorHex: member.customColorHex,
                  size: 24,
                ),
                selectedColor:
                    member.customColorEnabled && member.customColorHex != null
                    ? AppColors.fromHex(member.customColorHex!)
                    : null,
              );
            },
          ),
        );
      },
      loading: () => SizedBox(
        height: 48,
        child: Center(
          child: PrismSpinner(
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          context.l10n.chatErrorLoadingMembersShort,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTrigger(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    List<Member> members,
    String? speakingAs,
    String termPlural,
    List<MemberSearchGroup> groups,
  ) {
    final displayMember = speakingAs != null
        ? members.firstWhere(
            (m) => m.id == speakingAs,
            orElse: () => members.first,
          )
        : members.first;

    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: InkWell(
          key: const Key('speakingAsSearchTrigger'),
          borderRadius: BorderRadius.circular(24),
          onTap: () =>
              _openSearchSheet(context, ref, members, termPlural, groups),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                MemberAvatar(
                  memberName: displayMember.name,
                  emoji: displayMember.emoji,
                  avatarImageData: displayMember.avatarImageData,
                  customColorEnabled: displayMember.customColorEnabled,
                  customColorHex: displayMember.customColorHex,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(displayMember.name, style: theme.textTheme.bodyMedium),
                const Spacer(),
                Icon(
                  AppIcons.expandMore,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSearchSheet(
    BuildContext context,
    WidgetRef ref,
    List<Member> members,
    String termPlural,
    List<MemberSearchGroup> groups,
  ) async {
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: termPlural,
      groups: groups,
    );
    if (!context.mounted) return;
    if (result is MemberSearchResultSelected) {
      ref.read(speakingAsProvider.notifier).setMember(result.memberId);
    }
  }
}
