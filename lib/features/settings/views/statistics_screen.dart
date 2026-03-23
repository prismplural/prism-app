import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/settings/providers/statistics_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Screen displaying system statistics: member counts, session data,
/// most frequent fronters, and average session duration.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCountAsync = ref.watch(memberCountStatProvider);
    final sessionCountAsync = ref.watch(sessionCountStatProvider);
    final membersAsync = ref.watch(allMembersStatProvider);
    final sessionsAsync = ref.watch(allSessionsStatProvider);
    final conversationsAsync = ref.watch(allConversationsCountProvider);
    final pollsAsync = ref.watch(allPollsCountProvider);
    final topFrontersAsync = ref.watch(topFrontersProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Statistics', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          // ── Key Numbers ─────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Overview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _StatRow(
                    label: 'Total members',
                    valueAsync: memberCountAsync.whenData((c) => '$c'),
                  ),
                  membersAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (members) {
                      final active = members.where((m) => m.isActive).length;
                      final inactive = members.length - active;
                      return Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          '$active active, $inactive inactive',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 16),
                  _StatRow(
                    label: 'Total sessions',
                    valueAsync: sessionCountAsync.whenData((c) => '$c'),
                  ),
                  const Divider(height: 16),
                  _StatRow(
                    label: 'Conversations',
                    valueAsync:
                        conversationsAsync.whenData((c) => '$c'),
                  ),
                  const Divider(height: 16),
                  _StatRow(
                    label: 'Polls',
                    valueAsync: pollsAsync.whenData((p) => '$p'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Most Frequent Fronters ──────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Most Frequent Fronters',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTopFronters(context, topFrontersAsync),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Average Session Duration ────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Average Session Duration',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  sessionsAsync.when(
                    loading: () => const PrismLoadingState(),
                    error: (e, _) => Text('Error: $e'),
                    data: (sessions) {
                      final completed =
                          sessions.where((s) => s.endTime != null).toList();
                      if (completed.isEmpty) {
                        return Text(
                          'No completed sessions yet',
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
          ),
        ],
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
            'No fronting data yet',
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        valueAsync.when(
          loading: () => const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
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

class _TopFronterRow extends StatelessWidget {
  const _TopFronterRow({
    required this.rank,
    required this.member,
    required this.sessionCount,
  });

  final int rank;
  final Member? member;
  final int sessionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = member?.name ?? 'Unknown';
    final emoji = member?.emoji ?? '\u2754';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '#$rank',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          MemberAvatar(
            emoji: emoji,
            avatarImageData: member?.avatarImageData,
            customColorEnabled: member?.customColorEnabled ?? false,
            customColorHex: member?.customColorHex,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '$sessionCount sessions',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
