import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/selected_member_picker.dart';

/// Reusable member selector.
///
/// Shows the selected member summary and opens [MemberSearchSheet] to choose
/// from active system members.
/// Optionally includes an "Unknown" option at the top when [includeUnknown]
/// is true.
class HeadmatePicker extends ConsumerWidget {
  const HeadmatePicker({
    super.key,
    required this.onSelected,
    this.selectedMemberId,
    this.excludeIds = const {},
    this.includeUnknown = false,
    this.label,
  });

  /// Called when a member is selected. Passes null if "Unknown" is chosen.
  final ValueChanged<String?> onSelected;

  /// The currently selected member ID, or null for none / unknown.
  final String? selectedMemberId;

  /// Member IDs to exclude from the list.
  final Set<String> excludeIds;

  /// Whether to include an "Unknown" option at the top of the list.
  final bool includeUnknown;

  /// Label shown on the dropdown field. Defaults to the current terminology singular.
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Picker source list: hide the Unknown sentinel from the searchable
    // members. When [includeUnknown] is true the sheet still surfaces an
    // explicit "Unknown" specialRow below — selecting it returns null
    // (rather than the sentinel id), which is what callers expect.
    final membersAsync = ref.watch(userVisibleMembersProvider);

    return membersAsync.when(
      loading: () => const SizedBox(height: 56, child: PrismLoadingState()),
      error: (e, _) => Text(
        context.l10n.errorLoadingMembers(
          readTerminology(context, ref).pluralLower,
          e,
        ),
      ),
      data: (members) {
        final filtered = members
            .where((m) => !excludeIds.contains(m.id))
            .toList();
        final effectiveLabel = label ?? watchTerminology(context, ref).singular;
        final terminology = readTerminology(context, ref);
        final searchGroups = watchMemberSearchGroups(ref, filtered);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(effectiveLabel, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SelectedMemberPicker(
              selectedMemberId: selectedMemberId,
              includeUnknown: includeUnknown,
              unknownSelected: includeUnknown && selectedMemberId == null,
              members: filtered,
              onPressed: () => _openSearch(
                context,
                filtered,
                terminology.plural,
                context.l10n.selectMember(terminology.singular),
                searchGroups,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSearch(
    BuildContext context,
    List<Member> members,
    String termPlural,
    String title,
    List<MemberSearchGroup> groups,
  ) async {
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: termPlural,
      title: title,
      groups: groups,
      specialRows: [
        if (includeUnknown)
          MemberSearchSpecialRow(
            rowKey: '__unknown__',
            title: context.l10n.unknown,
            leading: const Text('\u2753', style: TextStyle(fontSize: 18)),
            result: const MemberSearchResultUnknown(),
          ),
      ],
    );

    if (!context.mounted) return;
    switch (result) {
      case MemberSearchResultSelected(:final memberId):
        onSelected(memberId);
      case MemberSearchResultUnknown():
      case MemberSearchResultCleared():
        onSelected(null);
      case MemberSearchResultDismissed():
        break;
    }
  }
}
