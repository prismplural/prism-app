import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/member_filter.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

/// Search delegate for finding system members by name or pronouns.
///
/// Returns the selected member's ID, or null if dismissed.
/// Members are passed in via the constructor since [SearchDelegate]
/// does not integrate well with Riverpod.
class MemberSearchDelegate extends SearchDelegate<String?> {
  MemberSearchDelegate({
    required this.members,
    this.searchHint,
    this.emptyLabel,
    this.termPlural = 'members',
  });

  final List<Member> members;
  final String? searchHint;
  final String? emptyLabel;

  /// Plural terminology word used for the default empty-state label
  /// when [emptyLabel] is not provided. Defaults to "members".
  final String termPlural;

  @override
  String get searchFieldLabel => searchHint ?? '';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: Icon(AppIcons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(AppIcons.arrowBack),
      onPressed: () => close(context, null),
    );
  }

  List<Member> _filteredMembers() => filterMembers(members, query);

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final filtered = _filteredMembers();
    final l10n = AppLocalizations.of(context);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.searchOff,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              emptyLabel ?? l10n.noMembersFound(termPlural),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final member = filtered[index];
        return ListTile(
          leading: MemberAvatar(
            avatarImageData: member.avatarImageData,
            memberName: member.name,
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
          ),
          title: Text(member.name),
          subtitle: member.pronouns != null && member.pronouns!.isNotEmpty
              ? Text(member.pronouns!)
              : null,
          onTap: () => close(context, member.id),
        );
      },
    );
  }
}
