import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Pinned glass row at the top of the home-screen scroll view, surfacing
/// members who are currently "always present" — either explicitly opted-in
/// via [Member.isAlwaysFronting], or auto-promoted because their open
/// fronting session has been running for at least
/// [kAutoPromoteThreshold].
///
/// Renders nothing when no member qualifies — the wrapping
/// `SliverPersistentHeader` collapses to zero height in that case.
///
/// The single `Semantics(container: true, label: ...)` wrap merges all
/// child nodes into one screen-reader announcement; avatars and labels
/// inside are marked `excludeSemantics: true` so the reader doesn't
/// enumerate every avatar tile separately.
class AlwaysPresentHeader extends ConsumerWidget {
  const AlwaysPresentHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qualifying = ref.watch(alwaysPresentMembersProvider).value;
    if (qualifying == null || qualifying.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final members = qualifying.map((q) => q.member).toList(growable: false);
    final names = _joinNames(members);
    final duration = _shortestAge(qualifying);
    final durationLabel = _formatDuration(context, duration);
    final headerLabel = context.l10n.frontingAlwaysPresentLabel(durationLabel);
    final semanticsLabel =
        context.l10n.frontingAlwaysPresentSemantics(names, durationLabel);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        container: true,
        label: semanticsLabel,
        excludeSemantics: true,
        child: TintedGlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _AvatarStack(members: members),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      names,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The duration the header surfaces is the shortest age among qualifying
/// members. "Always present · 2 weeks" reads as "the most-recently-arrived
/// always-present fronter has been here 2 weeks" — the most conservative,
/// honest framing.
Duration _shortestAge(List<AlwaysPresentMember> qualifying) {
  Duration shortest = qualifying.first.age;
  for (final q in qualifying.skip(1)) {
    if (q.age < shortest) shortest = q.age;
  }
  return shortest;
}

String _joinNames(List<Member> members) {
  if (members.isEmpty) return '';
  if (members.length == 1) return members[0].name;
  if (members.length == 2) return '${members[0].name} & ${members[1].name}';
  // Three or more: list-form with a final ampersand. Matches the
  // existing period-row naming convention.
  final head = members.take(members.length - 1).map((m) => m.name).join(', ');
  return '$head & ${members.last.name}';
}

/// Formats a duration for the always-present header label.
///
/// Buckets: weeks, days, hours. (Sub-hour never qualifies — auto-promote
/// is 7d and explicit always-fronting members render as days/weeks once
/// their session has been open long enough; the hours bucket exists for
/// the "explicit member, just-started session" edge.)
String _formatDuration(BuildContext context, Duration age) {
  final l10n = context.l10n;
  final totalDays = age.inDays;
  if (totalDays >= 7) {
    final weeks = totalDays ~/ 7;
    return l10n.frontingAlwaysPresentDurationWeeks(weeks);
  }
  if (totalDays >= 1) {
    return l10n.frontingAlwaysPresentDurationDays(totalDays);
  }
  final hours = age.inHours;
  // Floor at 1 hour for display; sub-hour ages here only happen when an
  // explicit-always-fronting member just started a session.
  return l10n.frontingAlwaysPresentDurationHours(hours < 1 ? 1 : hours);
}

/// Compact overlapping avatar row, capped at three visible avatars
/// followed by a "+N" pill when there are more.
///
/// Mirrors the period-row stack in `session_history_list.dart` so the
/// pinned header reads as the same visual family as the inline list.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<Member> members;

  static const double _avatarSize = 36;
  static const double _overlap = 12;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const SizedBox(width: _avatarSize, height: _avatarSize);
    }

    final visible = members.take(3).toList();
    final extra = members.length - visible.length;
    final stackWidth = _avatarSize +
        (visible.length - 1) * (_avatarSize - _overlap) +
        (extra > 0 ? (_avatarSize - _overlap) : 0);

    return SizedBox(
      width: stackWidth,
      height: _avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (_avatarSize - _overlap),
              child: _BorderedAvatar(member: visible[i]),
            ),
          if (extra > 0)
            Positioned(
              left: visible.length * (_avatarSize - _overlap),
              child: _ExtraCountChip(count: extra),
            ),
        ],
      ),
    );
  }
}

class _BorderedAvatar extends StatelessWidget {
  const _BorderedAvatar({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.surface, width: 2),
      ),
      child: MemberAvatar(
        avatarImageData: member.avatarImageData,
        memberName: member.name,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: _AvatarStack._avatarSize,
      ),
    );
  }
}

class _ExtraCountChip extends StatelessWidget {
  const _ExtraCountChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: _AvatarStack._avatarSize,
      height: _AvatarStack._avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Sliver delegate that hosts the [AlwaysPresentHeader] at the top of
/// the home-screen scroll view.
///
/// [count] reflects the number of qualifying members. When zero, both
/// extents collapse to 0 so the sliver reserves no scroll space — without
/// this, an empty header still leaves a 76px gap above the rest of the
/// home content.
class AlwaysPresentSliverDelegate extends SliverPersistentHeaderDelegate {
  const AlwaysPresentSliverDelegate({required this.count});

  /// Number of members currently qualifying for the always-present header.
  /// Drives extent collapse and rebuild parity.
  final int count;

  @override
  double get minExtent => count > 0 ? 76 : 0;

  @override
  double get maxExtent => count > 0 ? 76 : 0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    if (count == 0) return const SizedBox.shrink();
    return const AlwaysPresentHeader();
  }

  @override
  bool shouldRebuild(covariant AlwaysPresentSliverDelegate oldDelegate) =>
      oldDelegate.count != count;
}
