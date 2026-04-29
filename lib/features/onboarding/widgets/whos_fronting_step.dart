import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

const int _kOnboardingFrontingSearchThreshold = 15;

class WhosFrontingStep extends ConsumerWidget {
  const WhosFrontingStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Onboarding picker: hide the Unknown sentinel — users are picking their
    // own members, not the system placeholder.
    final membersAsync = ref.watch(userVisibleAllMembersProvider);
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final terms = resolveTerminology(
      context.l10n,
      onboarding.selectedTerminology,
      customSingular: onboarding.customTermSingular,
      customPlural: onboarding.customTermPlural,
      useEnglish: onboarding.terminologyUseEnglish,
    );

    return membersAsync.when(
      loading: () => PrismLoadingState(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.warmWhite
            : AppColors.warmBlack,
      ),
      error: (e, _) => Center(
        child: Text(
          context.l10n.errorLoadingMembers(terms.pluralLower, e),
          style: TextStyle(color: Colors.red.shade300),
        ),
      ),
      data: (members) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary = Theme.of(context).colorScheme.primary;

        if (members.isEmpty) {
          return Center(
            child: Text(
              context.l10n.onboardingWhosFrontingNoMembers(terms.pluralLower),
              style: TextStyle(
                color: isDark
                    ? AppColors.mutedTextDark
                    : AppColors.mutedTextLight,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }

        if (members.length >= _kOnboardingFrontingSearchThreshold) {
          final searchGroups = watchMemberSearchGroups(ref, members);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  context.l10n.onboardingWhosFrontingSelectHint,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.mutedTextDark
                        : AppColors.mutedTextLight,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _LargeSystemSearchTrigger(
                        members: members,
                        selectedFronterId: onboarding.selectedFronterId,
                        termPlural: terms.plural,
                        onTap: () => _openSearchSheet(
                          context,
                          notifier,
                          members,
                          terms.plural,
                          searchGroups,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Text(
                context.l10n.onboardingWhosFrontingSelectHint,
                style: TextStyle(
                  color: isDark
                      ? AppColors.mutedTextDark
                      : AppColors.mutedTextLight,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isSelected =
                        onboarding.selectedFronterId == member.id;

                    return GestureDetector(
                      onTap: () => notifier.setSelectedFronter(member.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary.withValues(alpha: 0.2)
                              : isDark
                              ? AppColors.warmWhite.withValues(alpha: 0.1)
                              : AppColors.parchmentElevated,
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(16),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Avatar/Emoji circle
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark
                                    ? AppColors.warmWhite.withValues(
                                        alpha: 0.15,
                                      )
                                    : AppColors.warmBlack.withValues(
                                        alpha: 0.08,
                                      ),
                              ),
                              child: member.avatarImageData != null
                                  ? ClipOval(
                                      child: Image.memory(
                                        member.avatarImageData!,
                                        fit: BoxFit.cover,
                                        width: 52,
                                        height: 52,
                                        semanticLabel: context.l10n
                                            .memberAvatarSemantics(member.name),
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        member.emoji,
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            // Name
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                member.name,
                                style: TextStyle(
                                  color: isSelected
                                      ? primary
                                      : isDark
                                      ? AppColors.warmWhite
                                      : AppColors.warmBlack,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSearchSheet(
    BuildContext context,
    OnboardingNotifier notifier,
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
      notifier.setSelectedFronter(result.memberId);
    }
  }
}

class _LargeSystemSearchTrigger extends StatelessWidget {
  const _LargeSystemSearchTrigger({
    required this.members,
    required this.selectedFronterId,
    required this.termPlural,
    required this.onTap,
  });

  final List<Member> members;
  final String? selectedFronterId;
  final String termPlural;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedMember = _selectedMember;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('onboardingFrontingSearchTrigger'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              if (selectedMember != null)
                MemberAvatar(
                  memberName: selectedMember.name,
                  emoji: selectedMember.emoji,
                  avatarImageData: selectedMember.avatarImageData,
                  customColorEnabled: selectedMember.customColorEnabled,
                  customColorHex: selectedMember.customColorHex,
                  size: 28,
                )
              else
                Icon(
                  AppIcons.search,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedMember?.name ??
                      context.l10n.frontingSearchMembersHint(termPlural),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Icon(
                AppIcons.expandMore,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Member? get _selectedMember {
    if (selectedFronterId == null) return null;
    for (final member in members) {
      if (member.id == selectedFronterId) return member;
    }
    return null;
  }
}
