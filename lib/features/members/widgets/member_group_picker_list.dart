import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/group_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

const double memberGroupPickerRowExtent = 64.0;
const double memberGroupPickerDepthIndent = 24.0;

/// Searchable, hierarchy-aware group picker list shared by group selection
/// sheets.
class MemberGroupPickerList extends ConsumerStatefulWidget {
  const MemberGroupPickerList({
    super.key,
    required this.selectedGroupIds,
    required this.onGroupTap,
    this.scrollController,
    this.leadingRows = const [],
    this.enabled = true,
    this.showMemberCounts = true,
    this.includeGroup,
    this.semanticLabelBuilder,
  });

  final Set<String> selectedGroupIds;
  final void Function(MemberGroup group) onGroupTap;
  final ScrollController? scrollController;
  final List<Widget> leadingRows;
  final bool enabled;
  final bool showMemberCounts;
  final bool Function(MemberGroup group)? includeGroup;
  final String Function(MemberGroup group, int depth, bool isSelected)?
  semanticLabelBuilder;

  @override
  ConsumerState<MemberGroupPickerList> createState() =>
      _MemberGroupPickerListState();
}

class _MemberGroupPickerListState extends ConsumerState<MemberGroupPickerList> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;

  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) => setState(() => _query = q);

  List<({MemberGroup group, int depth})> _filterGroups(
    List<({MemberGroup group, int depth})> flatGroups,
    Map<String?, List<MemberGroup>> groupTree,
  ) {
    bool included(MemberGroup group) =>
        widget.includeGroup?.call(group) ?? true;

    if (_query.isEmpty) {
      return [
        for (final entry in flatGroups)
          if (included(entry.group)) entry,
      ];
    }

    final normalizedQuery = unorm.nfkc(_query).toLowerCase();
    bool matches(MemberGroup group) =>
        unorm.nfkc(group.name).toLowerCase().contains(normalizedQuery);

    final groupsById = {
      for (final entry in flatGroups) entry.group.id: entry.group,
    };
    final visibleIds = <String>{};
    for (final entry in flatGroups) {
      if (!included(entry.group) || !matches(entry.group)) continue;
      visibleIds.add(entry.group.id);
      for (final descendantId in GroupTreeUtils.getDescendantGroupIds(
        entry.group.id,
        groupTree,
      )) {
        final descendant = groupsById[descendantId];
        if (descendant != null && included(descendant)) {
          visibleIds.add(descendantId);
        }
      }
    }

    final result = <({MemberGroup group, int depth})>[];
    final stack = <({int depth, bool visible})>[];
    for (final entry in flatGroups) {
      while (stack.isNotEmpty && stack.last.depth >= entry.depth) {
        stack.removeLast();
      }

      final isVisible =
          included(entry.group) && visibleIds.contains(entry.group.id);
      if (isVisible) {
        final visibleAncestors = stack.where((frame) => frame.visible).length;
        result.add((group: entry.group, depth: visibleAncestors));
      }
      stack.add((depth: entry.depth, visible: isVisible));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final flatGroups = ref.watch(flatGroupListProvider);
    final groupTree = ref.watch(groupTreeProvider);
    final showCounts = widget.showMemberCounts;
    final memberCounts = showCounts
        ? ref.watch(groupMemberCountsProvider)
        : const <String, int>{};
    final hideMemberCount = showCounts
        ? ref
                  .watch(hideTotalMemberCountProvider)
                  .whenOrNull(data: (value) => value) ??
              true
        : true;
    final terms = showCounts ? watchTerminology(context, ref) : null;
    final filtered = _filterGroups(flatGroups, groupTree);

    return CustomScrollView(
      controller: widget.scrollController,
      primary: widget.scrollController == null,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: PrismTextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: false,
              hintText: l10n.memberGroupSearchHint,
              prefixIcon: Icon(AppIcons.search),
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
        if (widget.leadingRows.isNotEmpty)
          SliverList.builder(
            itemCount: widget.leadingRows.length,
            itemBuilder: (context, index) => widget.leadingRows[index],
          ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: ExcludeSemantics(child: Icon(AppIcons.searchOff)),
              title: l10n.memberGroupSearchEmpty,
              subtitle: '',
            ),
          )
        else
          SliverFixedExtentList(
            itemExtent: memberGroupPickerRowExtent,
            delegate: SliverChildBuilderDelegate((context, index) {
              final entry = filtered[index];
              return _buildGroupRow(
                entry.group,
                entry.depth,
                memberCounts[entry.group.id] ?? 0,
                terms,
                showMemberCount: showCounts && !hideMemberCount,
              );
            }, childCount: filtered.length),
          ),
      ],
    );
  }

  Widget _buildGroupRow(
    MemberGroup group,
    int depth,
    int memberCount,
    Terminology? terms, {
    required bool showMemberCount,
  }) {
    final isSelected = widget.selectedGroupIds.contains(group.id);
    final l10n = context.l10n;

    final row = PrismListRow(
      key: ValueKey(group.id),
      selected: isSelected,
      enabled: widget.enabled,
      padding: EdgeInsets.only(
        left: 16 + (depth * memberGroupPickerDepthIndent),
        right: 16,
        top: 14,
        bottom: 14,
      ),
      leading: GroupAvatar(group: group, size: 36, showEmojiOnAvatar: false),
      title: Text(group.name),
      subtitle: showMemberCount
          ? Text(
              l10n.memberCount(
                memberCount,
                terms!.singularLower,
                terms.pluralLower,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: isSelected ? Icon(AppIcons.check) : null,
      onTap: widget.enabled ? () => widget.onGroupTap(group) : null,
    );

    final semanticLabel = widget.semanticLabelBuilder?.call(
      group,
      depth,
      isSelected,
    );
    if (semanticLabel == null) return row;

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: row,
    );
  }
}
