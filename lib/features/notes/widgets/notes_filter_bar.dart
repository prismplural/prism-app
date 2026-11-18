import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class NotesMemberFilter {
  const NotesMemberFilter({
    required this.id,
    required this.label,
    this.member,
    this.avatar,
  });

  final String id;
  final String label;
  final Member? member;
  final Widget? avatar;
}

class NotesFilterBar extends StatelessWidget
    implements PreferredSizeWidget, PrismScaledHeight {
  const NotesFilterBar({
    super.key,
    required this.showSearch,
    required this.searchController,
    required this.searchQuery,
    this.autofocus = true,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onClearAllFilters,
    this.memberFilters = const [],
    this.onClearMemberFilter,
  });

  final bool showSearch;
  final TextEditingController searchController;
  final String searchQuery;
  final bool autofocus;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onClearAllFilters;
  final List<NotesMemberFilter> memberFilters;
  final ValueChanged<String>? onClearMemberFilter;

  /// Horizontal inset applied around the bar's content.
  static const double horizontalPadding = 16;

  /// Height of the search slot this bar used to reserve; still the minimum, so
  /// 1x geometry is unchanged.
  static const double searchSlotHeight = 60;

  /// Bottom padding under the filter row.
  static const double bottomPadding = 8;

  /// The same value, kept for callers that read the slot arithmetic.
  static const double searchSlotBottomPadding = bottomPadding;

  /// Vertical content padding inside [PrismTextField] (12 + 12).
  static const double _fieldVerticalPadding = 24;

  /// Vertical padding inside a [PrismChip] (6 + 6).
  static const double _chipVerticalPadding = 12;

  /// A selected [PrismChip] draws a 1.5dp border, and `BoxDecoration.padding` adds
  /// the border's dimensions to the chip's layout — so a filter chip is 3dp taller
  /// than its padding plus content. Every chip in this bar is selected.
  static const double _chipBorderWidth = 1.5;

  /// Gap between the search field and the chip strip when both are shown.
  static const double _chipGapAbove = 8;

  @override
  Size get preferredSize {
    final searchHeight = showSearch ? 60.0 : 0.0;
    final memberFilterHeight = memberFilters.isEmpty ? 0.0 : 44.0;
    return Size.fromHeight(searchHeight + memberFilterHeight);
  }

  /// Height the filter bar needs at the ambient text scale: the search field's
  /// line box plus its content padding, the chip strip's tallest chip (label line
  /// or the member avatar, which scales with the text as `MemberChip` does) plus
  /// its padding, and the gaps. Never smaller than the fixed slot this bar used to
  /// reserve, so nothing shrinks at normal text.
  ///
  /// Width does not enter: the field is single-line and the chip strip scrolls
  /// horizontally, so both are one line whatever the width.
  @override
  double preferredHeightFor(BuildContext context, {double? availableWidth}) {
    final theme = Theme.of(context);
    final fieldStyle = theme.textTheme.bodyLarge ?? const TextStyle();
    final chipStyle = theme.textTheme.labelMedium ?? const TextStyle();
    final scaler = MediaQuery.textScalerOf(context);

    final field = showSearch
        ? _fieldVerticalPadding +
              prismLineHeight(
                context,
                fieldStyle,
                text: searchQuery.isEmpty
                    ? context.l10n.memberNoteSearchHint
                    : searchQuery,
              )
        : 0.0;

    var chip = 0.0;
    if (memberFilters.isNotEmpty) {
      var label = 0.0;
      for (final filter in memberFilters) {
        label = math.max(
          label,
          prismLineHeight(context, chipStyle, text: filter.label),
        );
      }
      // `MemberChip` scales its 20dp avatar with the text scale; the chip's own
      // border adds `_chipBorderWidth` on each side.
      chip =
          _chipVerticalPadding +
          _chipBorderWidth * 2 +
          math.max(label, scaler.scale(20));
    }

    final gap = showSearch && chip > 0 ? _chipGapAbove : 0.0;
    final measured = field + gap + chip + bottomPadding;
    return math.max(preferredSize.height, measured);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSearch)
            PrismTextField(
              controller: searchController,
              autofocus: autofocus,
              hintText: l10n.memberNoteSearchHint,
              prefixIcon: Icon(AppIcons.search),
              suffix: searchQuery.isEmpty
                  ? null
                  : PrismGlassIconButton(
                      icon: AppIcons.close,
                      tooltip: l10n.memberNoteClearFilters,
                      size: 32,
                      iconSize: 16,
                      tint: colorScheme.surfaceContainerHighest,
                      onPressed: onClearSearch,
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              onChanged: onSearchChanged,
            ),

          if (memberFilters.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: showSearch ? _chipGapAbove : 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final filter in memberFilters) ...[
                            if (filter.member case final member?)
                              MemberChip(
                                member: member,
                                resolvedName: filter.label,
                                onTap: onClearMemberFilter == null
                                    ? null
                                    : () => onClearMemberFilter!(filter.id),
                                style: MemberChipStyle.filled,
                                avatarSize: 20,
                              )
                            else
                              PrismChip(
                                label: filter.label,
                                selected: true,
                                onTap: onClearMemberFilter == null
                                    ? null
                                    : () => onClearMemberFilter!(filter.id),
                                avatar: filter.avatar,
                              ),
                            if (filter != memberFilters.last)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PrismGlassIconButton(
                    key: const Key('clearAllFilters'),
                    icon: AppIcons.close,
                    tooltip: l10n.memberNoteClearFilters,
                    size: 32,
                    iconSize: 16,
                    tint: colorScheme.surfaceContainerHighest,
                    onPressed: onClearAllFilters,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
