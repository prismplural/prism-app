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
/// existing chip row is shown; a leading search button always opens the full
/// [MemberSearchSheet] for quick name lookup. For larger systems a compact
/// trigger row launches the search sheet directly.
///
/// Set [autoSelectFirst] to `false` when an explicit selection is required (e.g.
/// compose sheets where an anonymous post is not acceptable). With
/// [autoSelectFirst] `true` (the default) the picker falls back to the first
/// member when no one is selected, which suits always-needs-a-sender contexts
/// like chat.
class SpeakingAsPicker extends ConsumerWidget {
  const SpeakingAsPicker({super.key, this.autoSelectFirst = true});

  /// When `false`, the picker will not auto-select the first member as a
  /// fallback. Callers are responsible for blocking submission until a member
  /// is chosen.
  final bool autoSelectFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Non-fronting picker: hide the Unknown sentinel — speaking as the
    // placeholder member doesn't make sense in chat.
    final membersAsync = ref.watch(userVisibleMembersProvider);
    final speakingAs = ref.watch(speakingAsProvider);
    final terms = watchTerminology(context, ref);

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              context.l10n.chatNoMembersAvailable(terms.pluralLower),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        // Auto-select first member when allowed and nothing is selected.
        if (speakingAs == null && members.isNotEmpty && autoSelectFirst) {
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
            terms.plural,
            searchGroups,
          );
        }

        return SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            // +1 for the leading search button.
            itemCount: members.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildSearchButton(
                  context,
                  ref,
                  theme,
                  members,
                  terms.plural,
                  searchGroups,
                );
              }
              final member = members[index - 1];
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
          context.l10n.chatErrorLoadingMembersShort(terms.pluralLower),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchButton(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    List<Member> members,
    String termPlural,
    List<MemberSearchGroup> groups,
  ) {
    return Center(
      child: Tooltip(
        message: context.l10n.search,
        child: InkWell(
          key: const Key('speakingAsSearchChip'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openSearchSheet(context, ref, members, termPlural, groups),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(
              AppIcons.search,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
    // When autoSelectFirst is false and nothing is chosen, show a placeholder.
    final Member? displayMember = speakingAs != null
        ? members.firstWhere(
            (m) => m.id == speakingAs,
            orElse: () => members.first,
          )
        : (autoSelectFirst ? members.first : null);

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
                if (displayMember != null) ...[
                  MemberAvatar(
                    memberName: displayMember.name,
                    emoji: displayMember.emoji,
                    avatarImageData: displayMember.avatarImageData,
                    customColorEnabled: displayMember.customColorEnabled,
                    customColorHex: displayMember.customColorHex,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    displayMember.name,
                    style: theme.textTheme.bodyMedium,
                  ),
                ] else ...[
                  Icon(
                    AppIcons.personOutline,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.boardsComposeToNoHeadmate,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
