import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

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
          children: groups.map((group) {
            final accentColor = group.colorHex != null &&
                    group.colorHex!.isNotEmpty
                ? AppColors.fromHex(group.colorHex!)
                : null;
            return PrismChip(
              label: group.name,
              selected: false,
              onTap: () => context.push(AppRoutePaths.settingsGroup(group.id)),
              avatar: group.emoji != null && group.emoji!.isNotEmpty
                  ? Text(group.emoji!, style: const TextStyle(fontSize: 12))
                  : null,
              tintColor: accentColor,
            );
          }).toList(),
        );
      },
    );
  }
}

