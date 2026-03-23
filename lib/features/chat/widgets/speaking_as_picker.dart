import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

/// Horizontal scrollable row of member avatars for selecting who is "speaking."
class SpeakingAsPicker extends ConsumerWidget {
  const SpeakingAsPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final speakingAs = ref.watch(speakingAsProvider);

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: Text(
              'No members available',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        // Auto-select first member if none selected
        if (speakingAs == null && members.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(speakingAsProvider.notifier)
                .setMember(members.first.id);
          });
        }

        return SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final member = members[index];
              final isSelected = member.id == speakingAs;
              return _MemberChip(
                member: member,
                isSelected: isSelected,
                onTap: () {
                  ref
                      .read(speakingAsProvider.notifier)
                      .setMember(member.id);
                },
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Error loading members',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.member,
    required this.isSelected,
    required this.onTap,
  });

  final Member member;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          border: isSelected
              ? Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MemberAvatar(
              avatarImageData: member.avatarImageData,
              emoji: member.emoji,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: 28,
            ),
            const SizedBox(width: 6),
            Text(
              member.name,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
