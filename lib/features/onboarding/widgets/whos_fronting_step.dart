import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';

class WhosFrontingStep extends ConsumerWidget {
  const WhosFrontingStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(allMembersProvider);
    final onboarding = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    return membersAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.warmWhite
              : AppColors.warmBlack,
        ),
      ),
      error: (e, _) => Center(
        child: Text(
          'Error loading members: $e',
          style: TextStyle(color: Colors.red.shade300),
        ),
      ),
      data: (members) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary = Theme.of(context).colorScheme.primary;

        if (members.isEmpty) {
          return Center(
            child: Text(
              'No members added yet.\nGo back to add members first.',
              style: TextStyle(
                color: isDark ? AppColors.mutedTextDark : AppColors.mutedTextLight,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Text(
                'Tap to select who is currently fronting',
                style: TextStyle(
                  color: isDark ? AppColors.mutedTextDark : AppColors.mutedTextLight,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
                          borderRadius: BorderRadius.circular(16),
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
                                    ? AppColors.warmWhite.withValues(alpha: 0.15)
                                    : AppColors.warmBlack.withValues(alpha: 0.08),
                              ),
                              child: member.avatarImageData != null
                                  ? ClipOval(
                                      child: Image.memory(
                                        member.avatarImageData!,
                                        fit: BoxFit.cover,
                                        width: 52,
                                        height: 52,
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        member.emoji,
                                        style:
                                            const TextStyle(fontSize: 24),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            // Name
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
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
}
