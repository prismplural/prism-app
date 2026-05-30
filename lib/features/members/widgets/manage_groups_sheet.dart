import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/group_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

const double _kRowExtent = 64.0;
const double _kDepthIndent = 24.0;

/// Full-screen sheet for managing which groups a member belongs to.
///
/// Shows all groups in settings tree order with search, group avatars, and
/// depth-based indentation. Selection is confirmed via the trailing checkmark;
/// dismissing without confirming discards changes.
///
/// Present via [ManageGroupsSheet.show].
class ManageGroupsSheet extends ConsumerStatefulWidget {
  const ManageGroupsSheet({
    super.key,
    required this.memberId,
    required this.memberName,
    this.scrollController,
  });

  final String memberId;
  final String memberName;
  final ScrollController? scrollController;

  static Future<void> show(
    BuildContext context, {
    required String memberId,
    required String memberName,
  }) {
    return PrismSheet.showFullScreen<void>(
      context: context,
      builder: (sheetContext, scrollController) => ManageGroupsSheet(
        memberId: memberId,
        memberName: memberName,
        scrollController: scrollController,
      ),
    );
  }

  @override
  ConsumerState<ManageGroupsSheet> createState() => _ManageGroupsSheetState();
}

class _ManageGroupsSheetState extends ConsumerState<ManageGroupsSheet> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;

  String _query = '';
  Set<String>? _selectedGroupIds;
  Set<String>? _initialGroupIds;
  bool _initialized = false;
  bool _isSaving = false;

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

  void _initSelection(Set<String> memberGroupIds) {
    if (!_initialized) {
      _initialGroupIds = Set.from(memberGroupIds);
      _selectedGroupIds = Set.from(memberGroupIds);
      _initialized = true;
    }
  }

  void _onQueryChanged(String q) => setState(() => _query = q);

  void _toggleGroup(String groupId) => setState(() {
        if (_selectedGroupIds!.contains(groupId)) {
          _selectedGroupIds!.remove(groupId);
        } else {
          _selectedGroupIds!.add(groupId);
        }
      });

  Future<void> _confirm() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final notifier = ref.read(groupNotifierProvider.notifier);
    final added = _selectedGroupIds!.difference(_initialGroupIds!);
    final removed = _initialGroupIds!.difference(_selectedGroupIds!);

    for (final groupId in added) {
      await notifier.addMemberToGroup(groupId, widget.memberId);
    }
    for (final groupId in removed) {
      await notifier.removeMemberFromGroup(groupId, widget.memberId);
    }

    if (mounted) Navigator.of(context).pop();
  }

  List<({MemberGroup group, int depth})> _filterGroups(
    List<({MemberGroup group, int depth})> flatGroups,
    Map<String?, List<MemberGroup>> groupTree,
  ) {
    if (_query.isEmpty) return flatGroups;
    final normalizedQuery = unorm.nfkc(_query).toLowerCase();

    bool matches(MemberGroup g) =>
        unorm.nfkc(g.name).toLowerCase().contains(normalizedQuery);

    // Visible = matches, or descends from a match, so searching a parent's
    // name surfaces its whole subtree.
    final visibleIds = <String>{};
    for (final entry in flatGroups) {
      if (matches(entry.group)) {
        visibleIds.add(entry.group.id);
        visibleIds.addAll(
          GroupTreeUtils.getDescendantGroupIds(entry.group.id, groupTree),
        );
      }
    }

    // Indent by visible ancestors, not original depth, so a match whose parent
    // is filtered out sits flush-left. Walk every entry — not just visible ones
    // — or a hidden node strands its parent's frame on the stack and
    // over-indents a later match in a sibling subtree.
    final result = <({MemberGroup group, int depth})>[];
    final stack = <({int depth, bool visible})>[];
    for (final entry in flatGroups) {
      while (stack.isNotEmpty && stack.last.depth >= entry.depth) {
        stack.removeLast();
      }
      final isVisible = visibleIds.contains(entry.group.id);
      if (isVisible) {
        final visibleAncestors = stack.where((f) => f.visible).length;
        result.add((group: entry.group, depth: visibleAncestors));
      }
      stack.add((depth: entry.depth, visible: isVisible));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allGroupsAsync = ref.watch(allGroupsProvider);
    final memberGroupsAsync = ref.watch(memberGroupsProvider(widget.memberId));

    if (!allGroupsAsync.hasValue || !memberGroupsAsync.hasValue) {
      final theme = Theme.of(context);
      return Center(
        child: PrismSpinner(color: theme.colorScheme.primary),
      );
    }

    final groups = allGroupsAsync.value!;
    final memberGroupIds = memberGroupsAsync.value!.map((g) => g.id).toSet();

    _initSelection(memberGroupIds);

    if (groups.isEmpty) {
      return _buildEmptyGroupsState();
    }

    final flatGroups = ref.watch(flatGroupListProvider);
    final memberCounts = ref.watch(groupMemberCountsProvider);
    final groupTree = ref.watch(groupTreeProvider);
    final filtered = _filterGroups(flatGroups, groupTree);

    final topBar = PrismSheetTopBar(
      title: l10n.memberGroupManageTitle,
      trailing: PrismGlassIconButton(
        icon: AppIcons.check,
        tooltip: l10n.save,
        onPressed: _isSaving ? null : _confirm,
      ),
    );

    final body = CustomScrollView(
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
            itemExtent: _kRowExtent,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = filtered[index];
                return _buildGroupRow(
                  entry.group,
                  entry.depth,
                  memberCounts[entry.group.id] ?? 0,
                );
              },
              childCount: filtered.length,
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < PrismTokens.topBarHeight) {
          return CustomScrollView(
            controller: widget.scrollController,
            primary: widget.scrollController == null,
            slivers: [
              SliverToBoxAdapter(child: topBar),
              ...body.slivers,
            ],
          );
        }

        return Column(
          children: [
            topBar,
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _buildGroupRow(MemberGroup group, int depth, int memberCount) {
    final isSelected = _selectedGroupIds!.contains(group.id);
    final l10n = context.l10n;

    return PrismListRow(
      key: ValueKey(group.id),
      selected: isSelected,
      // Freeze toggles mid-save: the diff is already computed, so a late tap
      // would be dropped before the pop.
      enabled: !_isSaving,
      padding: EdgeInsets.only(
        left: 16 + (depth * _kDepthIndent),
        right: 16,
        top: 14,
        bottom: 14,
      ),
      leading: GroupAvatar(
        group: group,
        size: 36,
        showEmojiOnAvatar: false,
      ),
      title: Text(group.name),
      subtitle: Text(
        l10n.memberCount(memberCount),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isSelected ? Icon(AppIcons.check) : null,
      onTap: () => _toggleGroup(group.id),
    );
  }

  Widget _buildEmptyGroupsState() {
    final l10n = context.l10n;
    final topBar = PrismSheetTopBar(
      title: l10n.memberGroupManageTitle,
    );

    return Column(
      children: [
        topBar,
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
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
              ),
            ),
          ),
        ),
      ],
    );
  }
}
