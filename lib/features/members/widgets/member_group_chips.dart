import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// Inline widget showing small colored chips for each group a member belongs to.
///
/// Watches [memberGroupsProvider] for the given [memberId] and renders a
/// [Wrap] of tappable chips. Each chip shows the group emoji (if any) and name.
/// Tapping navigates to the group detail screen.
///
/// Returns [SizedBox.shrink] when the member has no groups.
class MemberGroupChips extends ConsumerWidget {
  const MemberGroupChips({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(memberGroupsProvider(memberId));

    return groupsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (groups) {
        if (groups.isEmpty) return const SizedBox.shrink();

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: groups.map((group) => _GroupChip(group: group)).toList(),
        );
      },
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.group});

  final MemberGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;

    final backgroundColor = accentColor?.withValues(alpha: 0.15) ??
        theme.colorScheme.surfaceContainerHighest;
    final foregroundColor =
        accentColor ?? theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () => context.push(AppRoutePaths.settingsGroup(group.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (group.emoji != null && group.emoji!.isNotEmpty) ...[
              Text(
                group.emoji!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              group.name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
