import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
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

class NotesFilterBar extends StatelessWidget implements PreferredSizeWidget {
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

  @override
  Size get preferredSize {
    final searchHeight = showSearch ? 60.0 : 0.0;
    final memberFilterHeight = memberFilters.isEmpty ? 0.0 : 44.0;
    return Size.fromHeight(searchHeight + memberFilterHeight);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
              padding: EdgeInsets.only(top: showSearch ? 8 : 0),
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
