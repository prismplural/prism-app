import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/member_filter.dart';
import 'package:prism_plurality/shared/utils/member_picker_order.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

/// Typed result returned by [MemberSearchSheet.showSingle].
///
/// Using a sealed class avoids sentinel-string drift: callers switch
/// exhaustively and the compiler catches unhandled cases.
sealed class MemberSearchSingleResult {
  const MemberSearchSingleResult();
}

/// The user dismissed the sheet without choosing.
final class MemberSearchResultDismissed extends MemberSearchSingleResult {
  const MemberSearchResultDismissed();
}

/// The user selected a member.
final class MemberSearchResultSelected extends MemberSearchSingleResult {
  const MemberSearchResultSelected(this.memberId);
  final String memberId;
}

/// The user tapped the caller-provided "clear / none" row.
final class MemberSearchResultCleared extends MemberSearchSingleResult {
  const MemberSearchResultCleared();
}

/// The user tapped the caller-provided "unknown" row.
final class MemberSearchResultUnknown extends MemberSearchSingleResult {
  const MemberSearchResultUnknown();
}

/// A group chip offered to the user in the filter bar.
///
/// The caller supplies which member IDs belong to this group; the sheet
/// never reads providers directly.
class MemberSearchGroup {
  const MemberSearchGroup({
    required this.id,
    required this.name,
    required this.memberIds,
    this.emoji,
    this.colorHex,
  });

  final String id;
  final String name;

  /// Member IDs belonging to this group. Used to filter the list.
  final Set<String> memberIds;

  final String? emoji;
  final String? colorHex;
}

/// A caller-defined row placed above the member list (e.g. "None", "Unknown").
///
/// In single-select mode, set [result] to pop with a typed outcome.
/// In multi-select mode (or for custom behaviour), set [onTap] instead.
class MemberSearchSpecialRow {
  const MemberSearchSpecialRow({
    required this.rowKey,
    required this.title,
    this.leading,
    this.result,
    this.onTap,
  });

  /// Stable key for the underlying list item.
  final String rowKey;
  final String title;
  final Widget? leading;

  /// Popped when tapped in single-select mode.
  final MemberSearchSingleResult? result;

  /// Custom tap override — takes precedence over [result].
  final VoidCallback? onTap;
}

const double _kRowExtent = 64.0;
const double _kChipBarHeight = 56.0;

/// Caller-driven full-screen member search sheet.
///
/// Present via [MemberSearchSheet.showSingle] or [MemberSearchSheet.showMulti].
/// The caller supplies the member list, groups, and special rows — the sheet
/// never reads providers internally.
///
/// **Single-select** — pops immediately with a [MemberSearchSingleResult].
/// **Multi-select** — shows a checkmark action and selected-count title; pops
/// with `Set<String>`.
class MemberSearchSheet extends StatefulWidget {
  const MemberSearchSheet({
    super.key,
    required this.members,
    required this.termPlural,
    this.groups = const [],
    this.specialRows = const [],
    this.multiSelect = false,
    this.initialSelected = const {},
    this.allowEmptySelection = false,
    this.title,
    this.trailingBuilder,
    this.scrollController,
    this.fronterIds = const {},
    this.fronterSectionLabel,
  });

  /// All candidate members. Filtering is done internally.
  final List<Member> members;

  /// Plural display term, e.g. "Members" or "Headmates". Used in the title,
  /// search hint, and the "All …" chip.
  final String termPlural;

  final List<MemberSearchGroup> groups;

  /// Optional rows shown above the member list.
  final List<MemberSearchSpecialRow> specialRows;

  final bool multiSelect;

  /// Pre-selected IDs for multi-select mode.
  final Set<String> initialSelected;

  /// When true, multi-select mode allows confirming an empty selected set.
  ///
  /// Most callers require at least one member, so this defaults to false.
  final bool allowEmptySelection;

  /// Optional sheet title override.
  ///
  /// Useful for single-select surfaces where the generic plural title ("Select
  /// members") does not match the one-person task.
  final String? title;

  /// Optional trailing widget builder for each member row.
  ///
  /// Return non-null to show a custom widget in the trailing slot. In
  /// multi-select mode the selection check icon is shown alongside the
  /// returned widget.
  final Widget? Function(Member member)? trailingBuilder;

  /// Scroll controller supplied by [PrismSheet.showFullScreen] when the sheet
  /// is presented modally, allowing drag-to-dismiss to follow list scrolling.
  final ScrollController? scrollController;

  /// Member ids currently fronting. When non-empty, single-select mode floats
  /// them to the top of the unfiltered list, separated from the rest. Empty
  /// keeps the list flat.
  final Set<String> fronterIds;

  /// Optional muted label above the floated fronter block (e.g. "Fronting").
  final String? fronterSectionLabel;

  /// Show in single-select mode. Never returns `null` — maps a dismissed sheet
  /// to [MemberSearchResultDismissed].
  ///
  /// [trailingBuilder] is forwarded to the sheet so callers (e.g. the Manage
  /// PluralKit links screen's "Add link to existing member" flow) can render
  /// per-row state captions in the trailing slot.
  static Future<MemberSearchSingleResult> showSingle(
    BuildContext context, {
    required List<Member> members,
    required String termPlural,
    String? title,
    List<MemberSearchGroup> groups = const [],
    List<MemberSearchSpecialRow> specialRows = const [],
    Widget? Function(Member member)? trailingBuilder,
    Set<String> fronterIds = const {},
    String? fronterSectionLabel,
  }) async {
    final result = await PrismSheet.showFullScreen<MemberSearchSingleResult>(
      context: context,
      builder: (sheetContext, scrollController) => MemberSearchSheet(
        members: members,
        termPlural: termPlural,
        title: title,
        groups: groups,
        specialRows: specialRows,
        trailingBuilder: trailingBuilder,
        scrollController: scrollController,
        fronterIds: fronterIds,
        fronterSectionLabel: fronterSectionLabel,
      ),
    );
    return result ?? const MemberSearchResultDismissed();
  }

  /// Show in multi-select mode. Returns `null` on dismiss, or the confirmed
  /// set of selected IDs.
  static Future<Set<String>?> showMulti(
    BuildContext context, {
    required List<Member> members,
    required String termPlural,
    Set<String> initialSelected = const {},
    bool allowEmptySelection = false,
    List<MemberSearchGroup> groups = const [],
    List<MemberSearchSpecialRow> specialRows = const [],
    Widget? Function(Member member)? trailingBuilder,
  }) async {
    return PrismSheet.showFullScreen<Set<String>>(
      context: context,
      builder: (sheetContext, scrollController) => MemberSearchSheet(
        members: members,
        termPlural: termPlural,
        groups: groups,
        specialRows: specialRows,
        multiSelect: true,
        initialSelected: initialSelected,
        allowEmptySelection: allowEmptySelection,
        trailingBuilder: trailingBuilder,
        scrollController: scrollController,
      ),
    );
  }

  @override
  State<MemberSearchSheet> createState() => _MemberSearchSheetState();
}

class _MemberSearchSheetState extends State<MemberSearchSheet> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  late MemberSearchIndex _allMembersIndex;
  late List<MemberSearchIndex> _groupMemberIndexes;

  // 0 = "All", 1+ = widget.groups[index - 1]
  int _selectedChip = 0;
  String _query = '';
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
    _selectedIds = Set.from(widget.initialSelected);
    _rebuildSearchIndexes();
  }

  @override
  void didUpdateWidget(covariant MemberSearchSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.members, oldWidget.members) ||
        !identical(widget.groups, oldWidget.groups)) {
      _rebuildSearchIndexes();
      if (_selectedChip > widget.groups.length) {
        _selectedChip = 0;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _rebuildSearchIndexes() {
    final groupNamesByMemberId = _buildGroupNamesByMemberId(widget.groups);
    _allMembersIndex = MemberSearchIndex(
      widget.members,
      additionalSearchTermsByMemberId: groupNamesByMemberId,
    );
    _groupMemberIndexes = [
      for (final group in widget.groups)
        MemberSearchIndex(
          widget.members
              .where((member) => group.memberIds.contains(member.id))
              .toList(growable: false),
          additionalSearchTermsByMemberId: groupNamesByMemberId,
        ),
    ];
  }

  Map<String, List<String>> _buildGroupNamesByMemberId(
    List<MemberSearchGroup> groups,
  ) {
    final termsByMemberId = <String, List<String>>{};
    for (final group in groups) {
      final groupName = group.name.trim();
      if (groupName.isEmpty) continue;
      for (final memberId in group.memberIds) {
        termsByMemberId.putIfAbsent(memberId, () => []).add(groupName);
      }
    }
    return termsByMemberId;
  }

  List<Member> get _filteredMembers {
    final index = _selectedChip == 0
        ? _allMembersIndex
        : _groupMemberIndexes[_selectedChip - 1];
    return index.filter(_query);
  }

  void _onQueryChanged(String q) => setState(() => _query = q);

  void _selectChip(int index) => setState(() => _selectedChip = index);

  void _toggleMember(String id) => setState(() {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
  });

  void _confirmMulti() =>
      Navigator.of(context).pop(Set<String>.from(_selectedIds));

  void _popSingle(MemberSearchSingleResult result) =>
      Navigator.of(context).pop(result);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = _filteredMembers;
    final hasGroups = widget.groups.isNotEmpty;
    final title = widget.multiSelect
        ? l10n.memberSelectedCount(_selectedIds.length)
        : widget.title ?? l10n.selectMembers(widget.termPlural);

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
              hintText: l10n.frontingSearchMembersHint(widget.termPlural),
              prefixIcon: Icon(AppIcons.search),
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
            ),
          ),
        ),

        if (hasGroups)
          SliverToBoxAdapter(
            child: SizedBox(
              height: _kChipBarHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                children: [
                  _buildChip(0, 'All ${widget.termPlural}'),
                  ...widget.groups.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _buildChip(
                        e.key + 1,
                        e.value.name,
                        group: e.value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (filtered.isEmpty && widget.specialRows.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
        else
          ..._buildListSlivers(filtered),
      ],
    );

    final topBar = PrismSheetTopBar(
      title: title,
      trailing: widget.multiSelect
          ? PrismGlassIconButton(
              icon: AppIcons.check,
              tooltip: l10n.memberSearchConfirmSelectionTooltip(
                widget.termPlural.toLowerCase(),
              ),
              onPressed: _selectedIds.isEmpty && !widget.allowEmptySelection
                  ? null
                  : _confirmMulti,
            )
          : null,
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

  /// Builds the member-list slivers, floating current fronters to the top with
  /// a separator when [MemberSearchSheet.fronterIds] is set. Collapses to a
  /// flat list during search/group filtering or in multi-select mode.
  List<Widget> _buildListSlivers(List<Member> filtered) {
    final specialRows = widget.specialRows;

    final canGroup =
        !widget.multiSelect &&
        widget.fronterIds.isNotEmpty &&
        _query.isEmpty &&
        _selectedChip == 0;
    final sections = canGroup
        ? partitionMembersForPicker(filtered, widget.fronterIds)
        : null;

    if (sections == null || !sections.hasFronterSection) {
      return [
        SliverFixedExtentList(
          itemExtent: _kRowExtent,
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index < specialRows.length) {
              return _buildSpecialRow(specialRows[index]);
            }
            return _buildMemberRow(filtered[index - specialRows.length]);
          }, childCount: specialRows.length + filtered.length),
        ),
      ];
    }

    final fronters = sections.fronters;
    final others = sections.others;
    final label = widget.fronterSectionLabel;
    return [
      if (specialRows.isNotEmpty)
        SliverFixedExtentList(
          itemExtent: _kRowExtent,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildSpecialRow(specialRows[index]),
            childCount: specialRows.length,
          ),
        ),
      if (label != null && label.isNotEmpty)
        SliverToBoxAdapter(child: _buildFronterSectionLabel(label)),
      SliverFixedExtentList(
        itemExtent: _kRowExtent,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildMemberRow(fronters[index]),
          childCount: fronters.length,
        ),
      ),
      const SliverToBoxAdapter(
        // Decorative gap; the header conveys the grouping to screen readers.
        child: ExcludeSemantics(child: SizedBox(height: 12)),
      ),
      SliverFixedExtentList(
        itemExtent: _kRowExtent,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildMemberRow(others[index]),
          childCount: others.length,
        ),
      ),
    ];
  }

  Widget _buildFronterSectionLabel(String label) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _buildChip(int index, String label, {MemberSearchGroup? group}) {
    final tintColor = group?.colorHex != null
        ? AppColors.fromHex(group!.colorHex!)
        : null;
    return PrismChip(
      label: label,
      selected: _selectedChip == index,
      onTap: () => _selectChip(index),
      avatar: _buildChipAvatar(group, tintColor),
      tintColor: tintColor,
    );
  }

  Widget? _buildChipAvatar(MemberSearchGroup? group, Color? tintColor) {
    if (group == null) return null;

    final theme = Theme.of(context);
    final accent = tintColor ?? theme.colorScheme.primary;
    final colors = resolveTintedControlColors(
      theme,
      accent: accent,
      foregroundAccentWeight: 0.42,
    );
    final emoji = group.emoji;

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: colors.fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: emoji != null && emoji.isNotEmpty
          ? Text(emoji, style: const TextStyle(fontSize: 11, height: 1))
          : Icon(AppIcons.group, size: 12, color: colors.foreground),
    );
  }

  Widget _buildSpecialRow(MemberSearchSpecialRow row) {
    return PrismListRow(
      key: ValueKey(row.rowKey),
      title: Text(row.title),
      leading: row.leading,
      onTap: () {
        if (row.onTap != null) {
          row.onTap!();
        } else if (row.result != null) {
          _popSingle(row.result!);
        }
      },
    );
  }

  Widget _buildMemberRow(Member member) {
    final isSelected = widget.multiSelect && _selectedIds.contains(member.id);
    final customTrailing = widget.trailingBuilder?.call(member);

    final Widget? trailing;
    if (customTrailing != null && isSelected) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          customTrailing,
          const SizedBox(width: 4),
          Icon(AppIcons.check),
        ],
      );
    } else if (customTrailing != null) {
      trailing = customTrailing;
    } else if (isSelected) {
      trailing = Icon(AppIcons.check);
    } else {
      trailing = null;
    }

    // `PrismListRow` already emits `Semantics(button: true, selected: ...)`
    // for accessibility — don't wrap it again, or screen readers announce
    // twice.
    return PrismListRow(
      key: ValueKey(member.id),
      selected: isSelected,
      leading: MemberAvatar(
        memberName: member.name,
        emoji: member.emoji,
        avatarImageData: member.avatarImageData,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: 36,
      ),
      title: Text(member.name),
      subtitle: _buildMemberSubtitle(member),
      trailing: trailing,
      onTap: () {
        if (widget.multiSelect) {
          _toggleMember(member.id);
        } else {
          _popSingle(MemberSearchResultSelected(member.id));
        }
      },
    );
  }

  Widget? _buildMemberSubtitle(Member member) {
    final parts = <String>[];
    final fullName = member.displayName?.trim();
    if (fullName != null &&
        fullName.isNotEmpty &&
        normalizeMemberSearchText(fullName) !=
            normalizeMemberSearchText(member.name.trim())) {
      parts.add(fullName);
    }

    final pronouns = member.pronouns?.trim();
    if (pronouns != null && pronouns.isNotEmpty) {
      parts.add(pronouns);
    }

    if (parts.isEmpty) return null;
    return Text(
      parts.join(' - '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      // Icon is decorative — screen readers should not announce it.
      icon: ExcludeSemantics(child: Icon(AppIcons.searchOff)),
      title: context.l10n.noMembersFound(widget.termPlural),
      subtitle: '',
    );
  }
}
