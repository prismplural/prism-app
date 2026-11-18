import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/statistics_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/clamped_body.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Screen displaying system statistics: member counts, session data,
/// most frequent fronters, and average session duration.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideMemberCounts =
        ref
            .watch(hideMemberCountsProvider)
            .whenOrNull(data: (value) => value) ??
        true;
    final memberCountAsync = hideMemberCounts
        ? null
        : ref.watch(memberCountStatProvider);
    final sessionCountAsync = ref.watch(sessionCountStatProvider);
    final membersAsync = hideMemberCounts
        ? null
        : ref.watch(allMembersStatProvider);
    final sessionsAsync = ref.watch(allSessionsStatProvider);
    final conversationsAsync = ref.watch(allConversationsCountProvider);
    final pollsAsync = ref.watch(allPollsCountProvider);
    final topFrontersAsync = ref.watch(topFrontersProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.statisticsTitle,
        showBackButton: true,
      ),
      topBarMaxWidth: PrismTokens.contentMaxWidth,
      bodyPadding: EdgeInsets.zero,
      body: ClampedBody(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
          children: [
            // ── Key Numbers ─────────────────────────────
            PrismSectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.statisticsOverview,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!hideMemberCounts) ...[
                    _StatRow(
                      label: context.l10n.statisticsTotalMembers(
                        watchTerminology(context, ref).pluralLower,
                      ),
                      valueAsync: memberCountAsync!.whenData((c) => '$c'),
                    ),
                    membersAsync!.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (members) {
                        final active = members.where((m) => m.isActive).length;
                        final inactive = members.length - active;
                        return Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            context.l10n.statisticsActiveMembersBreakdown(
                              active,
                              inactive,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 16),
                  ],
                  _StatRow(
                    label: context.l10n.statisticsTotalSessions,
                    valueAsync: sessionCountAsync.whenData((c) => '$c'),
                  ),
                  const Divider(height: 16),
                  _StatRow(
                    label: context.l10n.statisticsConversations,
                    valueAsync: conversationsAsync.whenData((c) => '$c'),
                  ),
                  const Divider(height: 16),
                  _StatRow(
                    label: context.l10n.statisticsPolls,
                    valueAsync: pollsAsync.whenData((p) => '$p'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Most Frequent Fronters ──────────────────
            PrismSectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.statisticsMostFrequentFronters,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTopFronters(context, topFrontersAsync),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Average Session Duration ────────────────
            PrismSectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.statisticsAverageSessionDuration,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  sessionsAsync.when(
                    loading: () => const PrismLoadingState(),
                    error: (e, _) => Text('Error: $e'),
                    data: (sessions) {
                      final completed = sessions
                          .where((s) => s.endTime != null)
                          .toList();
                      if (completed.isEmpty) {
                        return Text(
                          context.l10n.statisticsNoCompletedSessions,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      }
                      final totalMinutes = completed.fold<int>(
                        0,
                        (sum, s) => sum + s.duration.inMinutes,
                      );
                      final avgMinutes = totalMinutes ~/ completed.length;
                      final hours = avgMinutes ~/ 60;
                      final mins = avgMinutes % 60;
                      return Text(
                        hours > 0 ? '${hours}h ${mins}m' : '${mins}m',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopFronters(
    BuildContext context,
    AsyncValue<List<MapEntry<Member, int>>> topFrontersAsync,
  ) {
    final theme = Theme.of(context);

    return topFrontersAsync.when(
      loading: () => const PrismLoadingState(),
      error: (e, _) => Text('Error: $e'),
      data: (topFronters) {
        if (topFronters.isEmpty) {
          return Text(
            context.l10n.statisticsNoFrontingData,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }

        final top = topFronters.take(3).toList();
        return Column(
          children: [
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const Divider(height: 8),
              _TopFronterRow(
                rank: i + 1,
                member: top[i].key,
                sessionCount: top[i].value,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.valueAsync});

  final String label;
  final AsyncValue<String> valueAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A stock `OverflowBar`: the pair stays on one line exactly as before while it
    // fits, and the value moves to its own line at the end when it does not, instead
    // of both keeping their intrinsic width and running past the card.
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      spacing: 12,
      overflowSpacing: 4,
      overflowAlignment: OverflowBarAlignment.end,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        valueAsync.when(
          loading: () =>
              PrismSpinner(color: theme.colorScheme.primary, size: 16),
          error: (_, _) => Text(
            'Error',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          data: (value) => Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Width of one line of [text] at the ambient text scale and [style].
double _singleLineWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: prismTextStyleForMeasurement(context, style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _TopFronterRow extends ConsumerWidget {
  const _TopFronterRow({
    required this.rank,
    required this.member,
    required this.sessionCount,
  });

  final int rank;
  final Member? member;
  final int sessionCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final name = member?.effectiveName(preferDisplayName: prefer) ?? 'Unknown';
    final emoji = member?.emoji ?? '\u2754';

    final rankStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );
    final countStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final countLabel = context.l10n.statisticsSessions(sessionCount);
    // The numeral is sized from the glyphs it paints, with 24dp as the alignment
    // floor: a constant 24dp box broke "#10" (and "#1" at 1.5x) onto two lines.
    final rankWidth = _singleLineWidth(context, '#$rank', rankStyle) + 2;
    final rankExtent = rankWidth < 24 ? 24.0 : rankWidth;

    Widget rankBox() => SizedBox(
      width: rankExtent,
      child: Text('#$rank', style: rankStyle),
    );

    Widget avatar() => MemberAvatar(
      emoji: emoji,
      memberName: member?.effectiveName(preferDisplayName: prefer),
      avatarImageData: member?.avatarImageData,
      customColorEnabled: member?.customColorEnabled ?? false,
      customColorHex: member?.customColorHex,
      size: 36,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fit from what the row really renders: the numeral, avatar and gaps are
          // non-shrinkable, the name already ellipsises, so the count stays inline
          // exactly as before while it fits beside them and drops to its own
          // end-aligned line only when it cannot.
          final fixed =
              rankExtent +
              8 +
              36 +
              12 +
              _singleLineWidth(context, countLabel, countStyle);
          final fitsInline = fixed <= constraints.maxWidth;

          if (fitsInline) {
            return Row(
              children: [
                rankBox(),
                const SizedBox(width: 8),
                avatar(),
                const SizedBox(width: 12),
                Expanded(child: Text(name, style: theme.textTheme.bodyMedium)),
                Text(countLabel, style: countStyle),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  rankBox(),
                  const SizedBox(width: 8),
                  avatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(countLabel, style: countStyle),
              ),
            ],
          );
        },
      ),
    );
  }
}
