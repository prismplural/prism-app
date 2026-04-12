import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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
        await notifier.updateMember(member.copyWith(isActive: targetActive));
      }
    }
    _clearSelection();
  }

  Future<void> _bulkDelete(List<Member> members) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.terminologyDeleteSelected(readTerminology(context, ref).plural),
      message:
          'Are you sure you want to delete ${_selectedIds.length} '
          '${readTerminology(context, ref).singularLower}(s)? This action cannot be undone.',
      confirmLabel: context.l10n.delete,
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
    final l10n = context.l10n;
    final membersAsync = ref.watch(allMembersProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.terminologyManage(watchTerminology(context, ref).plural),
        showBackButton: true,
        trailing: _selectionMode
            ? PrismTopBarAction(
                icon: AppIcons.close,
                tooltip: l10n.memberCancelSelectionTooltip,
                onPressed: _clearSelection,
              )
            : null,
      ),
      bodyPadding: EdgeInsets.zero,
      body: membersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allMembers) {
          final activeMembers = allMembers.where((m) => m.isActive).toList();
          final inactiveMembers = allMembers.where((m) => !m.isActive).toList();
          final displayedMembers = _showInactive
              ? inactiveMembers
              : activeMembers;

          displayedMembers.sort(
            (a, b) => a.displayOrder.compareTo(b.displayOrder),
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    _CountChip(
                      label: l10n.memberActive,
                      count: activeMembers.length,
                      selected: !_showInactive,
                      onTap: () => setState(() {
                        _showInactive = false;
                        _clearSelection();
                      }),
                    ),
                    const SizedBox(width: 8),
                    _CountChip(
                      label: l10n.memberArchived,
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
                        l10n.memberSelectedCount(_selectedIds.length),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      PrismButton(
                        label: _showInactive ? l10n.memberBulkActivate : l10n.memberBulkDeactivate,
                        icon: _showInactive
                            ? AppIcons.visibility
                            : AppIcons.visibilityOff,
                        tone: PrismButtonTone.subtle,
                        onPressed: () => _bulkToggleActive(displayedMembers),
                      ),
                      const SizedBox(width: 8),
                      PrismButton(
                        label: l10n.delete,
                        icon: AppIcons.delete,
                        tone: PrismButtonTone.destructive,
                        onPressed: () => _bulkDelete(displayedMembers),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: displayedMembers.isEmpty
                    ? Center(
                        child: Text(
                          _showInactive
                              ? l10n.memberNoInactive(readTerminology(context, ref).pluralLower)
                              : l10n.memberNoActive(readTerminology(context, ref).pluralLower),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: EdgeInsets.only(
                          bottom: NavBarInset.of(context),
                        ),
                        itemCount: displayedMembers.length,
                        onReorder: (oldIndex, newIndex) =>
                            _onReorder(displayedMembers, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final member = displayedMembers[index];
                          final isSelected = _selectedIds.contains(member.id);

                          if (_selectionMode) {
                            return PrismCheckboxRow(
                              key: ValueKey(member.id),
                              checkboxAffinity: PrismCheckboxAffinity.leading,
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(member.id),
                              title: Text(member.name),
                              subtitle: member.pronouns != null
                                  ? Text(member.pronouns!)
                                  : null,
                              trailing: ReorderableDragStartListener(
                                index: index,
                                child: Icon(AppIcons.dragHandle),
                              ),
                            );
                          }

                          return PrismListRow(
                            key: ValueKey(member.id),
                            leading: CircleAvatar(child: Text(member.emoji)),
                            title: Text(member.name),
                            subtitle: member.pronouns != null
                                ? Text(member.pronouns!)
                                : null,
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: Icon(AppIcons.dragHandle),
                            ),
                            onLongPress: () => _enterSelectionMode(member.id),
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
    return PrismChip(
      label: '$label ($count)',
      selected: selected,
      onTap: onTap,
    );
  }
}
