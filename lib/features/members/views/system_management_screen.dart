import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Screen for bulk member operations: activate/deactivate, delete, and reorder.
class SystemManagementScreen extends ConsumerStatefulWidget {
  const SystemManagementScreen({super.key});

  @override
  ConsumerState<SystemManagementScreen> createState() =>
      _SystemManagementScreenState();
}

class _SystemManagementScreenState
    extends ConsumerState<SystemManagementScreen> {
  bool _showInactive = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _bulkToggleActive(List<Member> members) async {
    final notifier = ref.read(membersNotifierProvider.notifier);
    final targetActive = _showInactive; // if viewing inactive, activate them
    for (final member in members) {
      if (_selectedIds.contains(member.id)) {
        await notifier.updateMember(
          member.copyWith(isActive: targetActive),
        );
      }
    }
    _clearSelection();
  }

  Future<void> _bulkDelete(List<Member> members) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete Selected ${ref.read(terminologyProvider).plural}',
      message: 'Are you sure you want to delete ${_selectedIds.length} '
          '${ref.read(terminologyProvider).singularLower}(s)? This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    final notifier = ref.read(membersNotifierProvider.notifier);
    for (final id in _selectedIds.toList()) {
      await notifier.deleteMember(id);
    }
    _clearSelection();
  }

  void _onReorder(List<Member> members, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<Member>.from(members);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    ref.read(membersNotifierProvider.notifier).reorderMembers(reordered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(allMembersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(ref.watch(terminologyProvider).manageText),
        actions: [
          if (_selectionMode)
            IconButton(
              icon: Icon(AppIcons.close),
              tooltip: 'Cancel selection',
              onPressed: _clearSelection,
            ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allMembers) {
          final activeMembers =
              allMembers.where((m) => m.isActive).toList();
          final inactiveMembers =
              allMembers.where((m) => !m.isActive).toList();
          final displayedMembers =
              _showInactive ? inactiveMembers : activeMembers;

          // Sort by displayOrder for consistent ordering.
          displayedMembers
              .sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

          return Column(
            children: [
              // ── Counts ────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _CountChip(
                      label: 'Active',
                      count: activeMembers.length,
                      selected: !_showInactive,
                      onTap: () => setState(() {
                        _showInactive = false;
                        _clearSelection();
                      }),
                    ),
                    const SizedBox(width: 8),
                    _CountChip(
                      label: 'Inactive',
                      count: inactiveMembers.length,
                      selected: _showInactive,
                      onTap: () => setState(() {
                        _showInactive = true;
                        _clearSelection();
                      }),
                    ),
                  ],
                ),
              ),

              // ── Bulk action bar ───────────────────
              if (_selectionMode && _selectedIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Text(
                        '${_selectedIds.length} selected',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: Icon(
                          _showInactive
                              ? AppIcons.visibility
                              : AppIcons.visibilityOff,
                          size: 18,
                        ),
                        label: Text(
                          _showInactive
                              ? 'Activate'
                              : 'Deactivate',
                        ),
                        onPressed: () =>
                            _bulkToggleActive(displayedMembers),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: Icon(AppIcons.delete, size: 18),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: () => _bulkDelete(displayedMembers),
                      ),
                    ],
                  ),
                ),

              // ── Member list (reorderable) ─────────
              Expanded(
                child: displayedMembers.isEmpty
                    ? Center(
                        child: Text(
                          _showInactive
                              ? 'No inactive ${ref.read(terminologyProvider).pluralLower}'
                              : 'No active ${ref.read(terminologyProvider).pluralLower}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
                        itemCount: displayedMembers.length,
                        onReorder: (oldIndex, newIndex) =>
                            _onReorder(displayedMembers, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final member = displayedMembers[index];
                          final isSelected =
                              _selectedIds.contains(member.id);

                          return PrismListRow(
                            key: ValueKey(member.id),
                            leading: _selectionMode
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (_) =>
                                        _toggleSelection(member.id),
                                  )
                                : CircleAvatar(
                                    child: Text(member.emoji),
                                  ),
                            title: Text(member.name),
                            subtitle: member.pronouns != null
                                ? Text(member.pronouns!)
                                : null,
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: Icon(AppIcons.dragHandle),
                            ),
                            onTap: _selectionMode
                                ? () => _toggleSelection(member.id)
                                : null,
                            onLongPress: _selectionMode
                                ? null
                                : () => _enterSelectionMode(member.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
