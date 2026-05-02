import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_args.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Detail screen for a multi-contributor fronting period.
///
/// Single-contributor periods are routed directly to [SessionDetailScreen]
/// (see `_PeriodTile.onTap`); this screen only renders for 2+ contributors.
///
/// Header renders immediately from a [PeriodDetailArgs] hint passed via
/// `state.extra` so navigation feels instant. Reactive period data comes
/// from `derivedPeriodsProvider` once it resolves — when an open-ended
/// session closes mid-mount, the live timer disappears via the provider
/// subscription (no cached `isLive`).
class PeriodDetailScreen extends ConsumerWidget {
  const PeriodDetailScreen({
    super.key,
    required this.sessionIds,
    this.hint,
  });

  final List<String> sessionIds;
  final PeriodDetailArgs? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: context.l10n.frontingSessionDetailDeleteTooltip,
            // Wired in Task 11.
            onPressed: () {},
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          _Header(sessionIds: sessionIds, hint: hint),
          // Future tasks fill in: co-fronters (T6), brief/always-present (T8),
          // comments (T9), stale handling (T13).
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.sessionIds, required this.hint});

  final List<String> sessionIds;
  final PeriodDetailArgs? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reactive isOpenEnded: prefer the matched FrontingPeriod from
    // derivedPeriodsProvider; fall back to hint for first paint. Task 7
    // will replace the inline set-equality lookup below with the shared
    // findPeriodBySessionIds helper.
    final periodsAsync = ref.watch(derivedPeriodsProvider);
    final matchedPeriod = periodsAsync.whenOrNull(
      data: (periods) => _findPeriodBySessionIds(periods, sessionIds),
    );
    final isOpenEnded =
        matchedPeriod?.isOpenEnded ?? hint?.isOpenEnded ?? false;

    if (hint == null) {
      // Deep-link / no-hint case: small loading shimmer in the section card.
      return const PrismSectionCard(
        margin: EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          height: 80,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final h = hint!;
    final names = _namesString(h.activeMembers);

    final locale = context.dateLocale;
    final startStr = h.start.toTimeString(locale);
    final endStr = isOpenEnded ? 'ongoing' : h.end.toTimeString(locale);
    final timeRange = '$startStr – $endStr';

    final duration = h.end.difference(h.start);

    return PrismSectionCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        label:
            'Period: $names, fronting from $startStr to $endStr, duration ${duration.toRoundedString()}',
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GroupMemberAvatar(
              size: 56,
              members: [
                for (final m in h.activeMembers)
                  GroupAvatarMember(
                    avatarImageData: m.avatarImageData,
                    emoji: m.emoji,
                    customColorEnabled: m.customColorEnabled,
                    customColorHex: m.customColorHex,
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    names,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: 6),
                  if (isOpenEnded)
                    Row(
                      children: [
                        FrontingDurationText(
                          startTime: h.start,
                          rounded: true,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          '  ·  $timeRange',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  else
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: duration.toRoundedString(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  $timeRange',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Finds the period whose sessionIds set matches [ids] by set equality.
  /// Task 7 will extract this into lib/features/fronting/services/period_lookup.dart.
  FrontingPeriod? _findPeriodBySessionIds(
    List<FrontingPeriod> periods,
    List<String> ids,
  ) {
    if (ids.isEmpty) return null;
    final target = ids.toSet();
    for (final p in periods) {
      final candidate = p.sessionIds.toSet();
      if (candidate.length == target.length && candidate.containsAll(target)) {
        return p;
      }
    }
    return null;
  }

  // Same logic as _PeriodTile._namesString, but UNTRUNCATED — show every name.
  String _namesString(List<Member> members) {
    final names = members.map((m) => m.name).toList();
    if (names.isEmpty) return 'Unknown';
    if (names.length == 1) return names[0];
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    final allButLast = names.sublist(0, names.length - 1).join(', ');
    return '$allButLast & ${names.last}';
  }
}
