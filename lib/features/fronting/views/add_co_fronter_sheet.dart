import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Simple bottom sheet for adding co-fronters to the active session.
class AddCoFronterSheet extends ConsumerStatefulWidget {
  const AddCoFronterSheet({
    super.key,
    required this.currentFronterId,
    required this.existingCoFronterIds,
  });

  final String? currentFronterId;
  final List<String> existingCoFronterIds;

  @override
  ConsumerState<AddCoFronterSheet> createState() => _AddCoFronterSheetState();
}

class _AddCoFronterSheetState extends ConsumerState<AddCoFronterSheet> {
  final Set<String> _selectedIds = {};
  bool _saving = false;

  Set<String> get _excludedIds => {
        if (widget.currentFronterId != null) widget.currentFronterId!,
        ...widget.existingCoFronterIds,
      };

  Future<void> _add() async {
    if (_selectedIds.isEmpty) return;

    setState(() => _saving = true);

    try {
      final notifier = ref.read(frontingNotifierProvider.notifier);
      for (final id in _selectedIds) {
        await notifier.addCoFronter(id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Error adding co-fronters: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PrismButton(
                  label: 'Cancel',
                  tone: PrismButtonTone.subtle,
                  onPressed: () => Navigator.of(context).pop(),
                  enabled: !_saving,
                ),
                Text(
                  'Add Co-Fronters',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                PrismButton(
                  onPressed: _add,
                  enabled: !_saving && _selectedIds.isNotEmpty,
                  isLoading: _saving,
                  label: 'Add',
                  tone: PrismButtonTone.filled,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Member list
          membersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: PrismLoadingState(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e'),
            ),
            data: (members) {
              final available = members
                  .where((m) => !_excludedIds.contains(m.id))
                  .toList();

              if (available.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No other members available',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }

              return Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: available.length,
                  itemBuilder: (context, index) {
                    final member = available[index];
                    return PrismListRow(
                      leading: MemberAvatar(
                        avatarImageData: member.avatarImageData,
                        emoji: member.emoji,
                        customColorEnabled: member.customColorEnabled,
                        customColorHex: member.customColorHex,
                        size: 40,
                      ),
                      title: Text(member.name),
                      subtitle: member.pronouns != null
                          ? Text(member.pronouns!)
                          : null,
                      trailing: Checkbox(
                        value: _selectedIds.contains(member.id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedIds.add(member.id);
                            } else {
                              _selectedIds.remove(member.id);
                            }
                          });
                        },
                      ),
                      onTap: () {
                        setState(() {
                          if (_selectedIds.contains(member.id)) {
                            _selectedIds.remove(member.id);
                          } else {
                            _selectedIds.add(member.id);
                          }
                        });
                      },
                    );
                  },
                ),
              );
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
