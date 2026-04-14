import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';

/// Reusable member selection dropdown.
///
/// Shows a [PrismSelect] populated with active system members.
/// Each item can render an avatar, emoji, and optional pronouns.
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
    final membersAsync = ref.watch(activeMembersProvider);

    return membersAsync.when(
      loading: () => const SizedBox(
        height: 56,
        child: PrismLoadingState(),
      ),
      error: (e, _) => Text(
        context.l10n.errorLoadingMembers(readTerminology(context, ref).pluralLower, e),
      ),
      data: (members) {
        final filtered = members
            .where((m) => !excludeIds.contains(m.id))
            .toList();
        final effectiveLabel = label ?? watchTerminology(context, ref).singular;
        const unknownLeading = Text('\u2753', style: TextStyle(fontSize: 18));

        return PrismSelect<String?>(
          value: selectedMemberId,
          labelText: effectiveLabel,
          items: [
            if (includeUnknown)
              PrismSelectItem<String?>(
                value: null,
                label: context.l10n.unknown,
                leading: unknownLeading,
                fieldLeading: unknownLeading,
              ),
            ...filtered.map(
              (member) => PrismSelectItem<String?>(
                value: member.id,
                label: member.name,
                subtitle: member.pronouns != null && member.pronouns!.isNotEmpty
                    ? member.pronouns
                    : null,
                leading: MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  memberName: member.name,
                  emoji: member.emoji,
                  customColorEnabled: member.customColorEnabled,
                  customColorHex: member.customColorHex,
                  size: 28,
                ),
                fieldLeading: MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  memberName: member.name,
                  emoji: member.emoji,
                  customColorEnabled: member.customColorEnabled,
                  customColorHex: member.customColorHex,
                  size: 24,
                ),
              ),
            ),
          ],
          onChanged: onSelected,
        );
      },
    );
  }
}
