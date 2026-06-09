import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_group_picker_list.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

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
  Set<String>? _selectedGroupIds;
  Set<String>? _initialGroupIds;
  bool _initialized = false;
  bool _isSaving = false;

  void _initSelection(Set<String> memberGroupIds) {
    if (!_initialized) {
      _initialGroupIds = Set.from(memberGroupIds);
      _selectedGroupIds = Set.from(memberGroupIds);
      _initialized = true;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allGroupsAsync = ref.watch(allGroupsProvider);
    final memberGroupsAsync = ref.watch(memberGroupsProvider(widget.memberId));

    if (!allGroupsAsync.hasValue || !memberGroupsAsync.hasValue) {
      final theme = Theme.of(context);
      return Center(child: PrismSpinner(color: theme.colorScheme.primary));
    }

    final groups = allGroupsAsync.value!;
    final memberGroupIds = memberGroupsAsync.value!.map((g) => g.id).toSet();

    _initSelection(memberGroupIds);

    if (groups.isEmpty) {
      return _buildEmptyGroupsState();
    }

    final topBar = PrismSheetTopBar(
      title: l10n.memberGroupManageTitle,
      trailing: PrismGlassIconButton(
        icon: AppIcons.check,
        tooltip: l10n.save,
        size: PrismTokens.topBarActionSize,
        onPressed: _isSaving ? null : _confirm,
      ),
    );

    final body = MemberGroupPickerList(
      scrollController: widget.scrollController,
      selectedGroupIds: _selectedGroupIds!,
      enabled: !_isSaving,
      onGroupTap: (group) => _toggleGroup(group.id),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < PrismTokens.topBarHeight) {
          return CustomScrollView(
            controller: widget.scrollController,
            primary: widget.scrollController == null,
            slivers: [SliverToBoxAdapter(child: topBar)],
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

  Widget _buildEmptyGroupsState() {
    final l10n = context.l10n;
    final topBar = PrismSheetTopBar(title: l10n.memberGroupManageTitle);

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
