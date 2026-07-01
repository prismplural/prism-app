import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

const int _kOnboardingFrontingSearchThreshold = 15;

class WhosFrontingStep extends ConsumerWidget {
  const WhosFrontingStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Onboarding picker: hide the Unknown sentinel — users are picking their
    // own members, not the system placeholder.
    final membersAsync = ref.watch(userVisibleAllMemberListProvider);
    final activeSessions =
        ref
            .watch(activeSessionsProvider)
            .whenOrNull(data: (sessions) => sessions) ??
        const [];
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
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final primary = theme.colorScheme.primary;
        final importedActiveIds = onboarding.selectedFronterId == null
            ? activeSessions
                  .where(
                    (session) => !session.isSleep && session.memberId != null,
                  )
                  .map((session) => session.memberId!)
                  .toSet()
            : <String>{};
        final importedActiveNames = [
          for (final member in members)
            if (importedActiveIds.contains(member.id)) member.name,
        ];

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

        watchMemberSearchGroupSources(ref);

        if (members.length >= _kOnboardingFrontingSearchThreshold) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _StepIntro(
                  importedActiveNames: importedActiveNames,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _LargeSystemSearchTrigger(
                        members: members,
                        selectedFronterId: onboarding.selectedFronterId,
                        importedActiveNames: importedActiveNames,
                        termPlural: terms.plural,
                        onTap: () => _openSearchSheet(
                          context,
                          ref,
                          notifier,
                          members,
                          terms.plural,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SkipButton(onPressed: notifier.skipFronterSelection),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              _StepIntro(
                importedActiveNames: importedActiveNames,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: PrismButton(
                  key: const Key('onboardingFrontingSearchButton'),
                  label: context.l10n.search,
                  icon: AppIcons.search,
                  density: PrismControlDensity.compact,
                  onPressed: () => _openSearchSheet(
                    context,
                    ref,
                    notifier,
                    members,
                    terms.plural,
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                        onboarding.selectedFronterId == member.id ||
                        importedActiveIds.contains(member.id);

                    return GestureDetector(
                      onTap: () => notifier.setSelectedFronter(member.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary.withValues(alpha: 0.2)
                              : theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(16),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MemberAvatar(
                              memberId: member.id,
                              avatarImageData: member.avatarImageData,
                              memberName: member.name,
                              emoji: member.emoji,
                              customColorEnabled: member.customColorEnabled,
                              customColorHex: member.customColorHex,
                              size: 52,
                              deferAvatarLookup: true,
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
                                      : theme.colorScheme.onSurface,
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
              const SizedBox(height: 12),
              _SkipButton(onPressed: notifier.skipFronterSelection),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSearchSheet(
    BuildContext context,
    WidgetRef ref,
    OnboardingNotifier notifier,
    List<Member> members,
    String termPlural,
  ) async {
    final groups = readMemberSearchGroups(ref, members);
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

class _StepIntro extends StatelessWidget {
  const _StepIntro({required this.importedActiveNames, required this.isDark});

  final List<String> importedActiveNames;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final hintColor = isDark
        ? AppColors.mutedTextDark
        : AppColors.mutedTextLight;
    return Column(
      children: [
        if (importedActiveNames.isNotEmpty) ...[
          Text(
            context.l10n.onboardingWhosFrontingImportedCurrent(
              importedActiveNames.join(', '),
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          context.l10n.onboardingWhosFrontingSelectHint,
          textAlign: TextAlign.center,
          style: TextStyle(color: hintColor, fontSize: 14),
        ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PrismButton(
      label: context.l10n.onboardingWhosFrontingSkip,
      onPressed: onPressed,
      density: PrismControlDensity.compact,
    );
  }
}

class _LargeSystemSearchTrigger extends ConsumerWidget {
  const _LargeSystemSearchTrigger({
    required this.members,
    required this.selectedFronterId,
    required this.importedActiveNames,
    required this.termPlural,
    required this.onTap,
  });

  final List<Member> members;
  final String? selectedFronterId;
  final List<String> importedActiveNames;
  final String termPlural;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedMember = _selectedMember;
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final selectedName = selectedMember?.effectiveName(
      preferDisplayName: prefer,
    );

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
                  memberId: selectedMember.id,
                  memberName: selectedName!,
                  emoji: selectedMember.emoji,
                  avatarImageData: selectedMember.avatarImageData,
                  customColorEnabled: selectedMember.customColorEnabled,
                  customColorHex: selectedMember.customColorHex,
                  size: 28,
                  deferAvatarLookup: true,
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
                  selectedName ??
                      (importedActiveNames.isNotEmpty
                          ? importedActiveNames.join(', ')
                          : null) ??
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
