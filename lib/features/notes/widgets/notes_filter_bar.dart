import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class NotesFilterBar extends StatelessWidget {
  const NotesFilterBar({
    super.key,
    required this.searchController,
    required this.searchQuery,
    this.autofocus = true,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onClearAllFilters,
    this.filterMemberId,
    this.filterMemberAvatar,
    this.filterMemberName,
    this.onClearMemberFilter,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final bool autofocus;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onClearAllFilters;
  final String? filterMemberId;
  final Widget? filterMemberAvatar;
  final String? filterMemberName;
  final VoidCallback? onClearMemberFilter;

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
          // Search row
          TintedGlassSurface(
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  AppIcons.search,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PrismTextField(
                    controller: searchController,
                    autofocus: autofocus,
                    hintText: l10n.memberNoteSearchHint,
                    fieldStyle: PrismTextFieldStyle.borderless,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    onChanged: onSearchChanged,
                  ),
                ),
                if (searchQuery.isNotEmpty)
                  Semantics(
                    button: true,
                    label: l10n.memberNoteClearFilters,
                    child: GestureDetector(
                      onTap: onClearSearch,
                      child: Icon(
                        AppIcons.close,
                        size: 18,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Member filter chip + clear-all row
          if (filterMemberId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: PrismChip(
                      label: filterMemberName ?? l10n.memberNoteFilterNoMember,
                      selected: true,
                      onTap: onClearMemberFilter,
                      avatar: filterMemberAvatar,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    key: const Key('clearAllFilters'),
                    onTap: onClearAllFilters,
                    child: Icon(
                      AppIcons.close,
                      size: 18,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
