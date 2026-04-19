import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';

/// Bottom sheet for managing which groups a member belongs to.
///
/// Shows a checklist of all groups with the member's current membership
/// pre-checked. Toggling a row immediately adds or removes the member.
///
/// When no groups exist, an empty-state prompt links to the groups settings
/// screen so the user can create one.
///
/// Intended to be presented via [PrismSheet.show] with
/// `title: l10n.memberGroupManageTitle` so the Prism sheet chrome renders the
/// title and drag handle.
class ManageGroupsSheet extends ConsumerWidget {
  const ManageGroupsSheet({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final allGroupsAsync = ref.watch(allGroupsProvider);
    final memberGroupsAsync = ref.watch(memberGroupsProvider(memberId));
    final groups = allGroupsAsync.value ?? [];
    final memberGroupIds =
        (memberGroupsAsync.value ?? []).map((g) => g.id).toSet();

    if (groups.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.memberGroupManageNoGroups),
          const SizedBox(height: 12),
          PrismButton(
            label: l10n.memberGroupManageNoGroupsAction,
            tone: PrismButtonTone.subtle,
            density: PrismControlDensity.compact,
            onPressed: () {
              Navigator.of(context).pop();
              context.push(AppRoutePaths.settingsGroups);
            },
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          final isChecked = memberGroupIds.contains(group.id);
          return PrismCheckboxRow(
            title: Text(group.name),
            value: isChecked,
            onChanged: (checked) async {
              if (checked) {
                await ref
                    .read(groupNotifierProvider.notifier)
                    .addMemberToGroup(group.id, memberId);
              } else {
                await ref
                    .read(groupNotifierProvider.notifier)
                    .removeMemberFromGroup(group.id, memberId);
              }
            },
          );
        },
      ),
    );
  }
}
