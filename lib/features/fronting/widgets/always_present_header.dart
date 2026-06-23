import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';

/// Sticky glass row in the home-screen scroll view, surfacing members who are
/// currently pinned in the header.
///
/// Explicit `isAlwaysFronting` members keep the "Always present" label. Members
/// surfaced only because their session has been running for a long time show
/// just the duration, so the UI does not imply an explicit opt-in.
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
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final names = _joinNames(
      members
          .map((m) => m.effectiveName(preferDisplayName: prefer))
          .toList(growable: false),
    );
    final durationLabel = _shortestAge(qualifying).toRoundedString();
    final explicitCount = qualifying
        .where((q) => q.member.isAlwaysFronting)
        .length;
    final allExplicit = explicitCount == qualifying.length;
    final noneExplicit = explicitCount == 0;
    final headerLabel = allExplicit
        ? context.l10n.frontingAlwaysPresentLabel(durationLabel)
        : noneExplicit
        ? context.l10n.frontingLongRunningLabel(durationLabel)
        : context.l10n.frontingMixedPinnedLabel(durationLabel);
    final semanticsLabel = allExplicit
        ? context.l10n.frontingAlwaysPresentSemantics(names, durationLabel)
        : noneExplicit
        ? context.l10n.frontingLongRunningSemantics(names, durationLabel)
        : context.l10n.frontingMixedPinnedLabel(durationLabel);
    final sessionId = qualifying.first.session.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        container: true,
        button: true,
        label: semanticsLabel,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              showAdaptiveDetailSurface<void>(
                context: context,
                builder: (_) => SessionDetailScreen(sessionId: sessionId),
                route: (context) =>
                    context.go(AppRoutePaths.session(sessionId)),
              );
            },
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  GroupMemberAvatar(
                    size: 36,
                    members: [
                      for (final member in members)
                        GroupAvatarMember(
                          memberId: member.id,
                          avatarImageData: member.avatarImageData,
                          deferAvatarLookup: true,
                          emoji: member.emoji,
                          customColorEnabled: member.customColorEnabled,
                          customColorHex: member.customColorHex,
                        ),
                    ],
                  ),
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
        ),
      ),
    );
  }
}

Duration _shortestAge(List<AlwaysPresentMember> qualifying) {
  Duration shortest = qualifying.first.age;
  for (final q in qualifying.skip(1)) {
    if (q.age < shortest) shortest = q.age;
  }
  return shortest;
}

String _joinNames(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names[0];
  if (names.length == 2) return '${names[0]} & ${names[1]}';
  final head = names.take(names.length - 1).join(', ');
  return '$head & ${names.last}';
}

/// Sliver delegate that hosts the sticky [AlwaysPresentHeader].
class AlwaysPresentSliverDelegate extends SliverPersistentHeaderDelegate {
  const AlwaysPresentSliverDelegate({required this.count});

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
