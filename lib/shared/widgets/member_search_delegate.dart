import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

/// Search delegate for finding system members by name or pronouns.
///
/// Returns the selected member's ID, or null if dismissed.
/// Members are passed in via the constructor since [SearchDelegate]
/// does not integrate well with Riverpod.
class MemberSearchDelegate extends SearchDelegate<String?> {
  MemberSearchDelegate({
    required this.members,
    this.searchHint = 'Search members...',
    this.emptyLabel = 'No members found',
  });

  final List<Member> members;
  final String searchHint;
  final String emptyLabel;

  @override
  String get searchFieldLabel => searchHint;

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

  List<Member> _filteredMembers() {
    if (query.isEmpty) return members;
    final lowerQuery = query.toLowerCase();
    return members.where((m) {
      final nameMatch = m.name.toLowerCase().contains(lowerQuery);
      final pronounsMatch =
          m.pronouns?.toLowerCase().contains(lowerQuery) ?? false;
      return nameMatch || pronounsMatch;
    }).toList();
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final filtered = _filteredMembers();

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
              emptyLabel,
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
