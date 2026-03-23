import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';

/// Reusable member selection dropdown.
///
/// Shows a [DropdownButtonFormField] populated with active system members.
/// Each item displays the member's emoji and name. Optionally includes an
/// "Unknown" option at the top when [includeUnknown] is true.
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
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
          'Error loading ${ref.read(terminologyProvider).pluralLower}: $e'),
      data: (members) {
        final filtered = members
            .where((m) => !excludeIds.contains(m.id))
            .toList();
        final effectiveLabel =
            label ?? ref.watch(terminologyProvider).singular;

        return DropdownButtonFormField<String?>(
          initialValue: selectedMemberId,
          decoration: InputDecoration(
            labelText: effectiveLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            if (includeUnknown)
              const DropdownMenuItem<String?>(
                value: null,
                child: Row(
                  children: [
                    Text('\u2753', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Text('Unknown'),
                  ],
                ),
              ),
            ...filtered.map(
              (member) => DropdownMenuItem<String?>(
                value: member.id,
                child: Row(
                  children: [
                    Text(member.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        member.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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
