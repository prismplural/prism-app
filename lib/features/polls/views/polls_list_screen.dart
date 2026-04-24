import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/polls/providers/poll_providers.dart';
import 'package:prism_plurality/features/polls/models/poll_summary.dart';
import 'package:prism_plurality/features/polls/views/create_poll_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';

import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

enum _PollFilter { active, closed, all }

/// Main polls list screen with filter menu in the app bar.
class PollsListScreen extends ConsumerStatefulWidget {
  const PollsListScreen({super.key});

  @override
  ConsumerState<PollsListScreen> createState() => _PollsListScreenState();
}

class _PollsListScreenState extends ConsumerState<PollsListScreen> {
  _PollFilter _filter = _PollFilter.all;

  AsyncValue<List<PollSummary>> _pollsForFilter(WidgetRef ref) {
    return switch (_filter) {
      _PollFilter.active => ref.watch(activePollsProvider),
      _PollFilter.closed => ref.watch(closedPollsProvider),
      _PollFilter.all => ref.watch(allPollsProvider),
    };
  }

  void _invalidateForFilter() {
    switch (_filter) {
      case _PollFilter.active:
        ref.invalidate(activePollsProvider);
      case _PollFilter.closed:
        ref.invalidate(closedPollsProvider);
      case _PollFilter.all:
        ref.invalidate(allPollsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pollsAsync = _pollsForFilter(ref);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          _invalidateForFilter();
        },
        child: CustomScrollView(
          physics: pollsAsync.whenOrNull(
            data: (polls) =>
                polls.isEmpty ? const NeverScrollableScrollPhysics() : null,
          ),
          slivers: [
            SliverPinnedTopBar(
              child: PrismTopBar(
                title: context.l10n.pollsListTitle,
                actions: [
                  BlurPopupAnchor(
                    preferredDirection: BlurPopupDirection.down,
                    width: 180,
                    maxHeight: 200,
                    itemCount: _PollFilter.values.length,
                    itemBuilder: (context, index, close) {
                      final filter = _PollFilter.values[index];
                      final isSelected = _filter == filter;
                      final filterTheme = Theme.of(context);
                      final (icon, label) = switch (filter) {
                        _PollFilter.active => (
                          AppIcons.howToVoteOutlined,
                          context.l10n.pollsFilterActive,
                        ),
                        _PollFilter.closed => (
                          AppIcons.checkCircleOutline,
                          context.l10n.pollsFilterClosed,
                        ),
                        _PollFilter.all => (
                          AppIcons.pollOutlined,
                          context.l10n.pollsFilterAll,
                        ),
                      };
                      return PrismListRow(
                        dense: true,
                        leading: Icon(
                          icon,
                          size: 20,
                          color: isSelected
                              ? filterTheme.colorScheme.primary
                              : filterTheme.colorScheme.onSurface,
                        ),
                        title: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? filterTheme.colorScheme.primary
                                : filterTheme.colorScheme.onSurface,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                AppIcons.check,
                                size: 18,
                                color: filterTheme.colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          close();
                          setState(() => _filter = filter);
                        },
                      );
                    },
                    child: PrismGlassIconButton(
                      icon: AppIcons.filterList,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).showMenuTooltip,
                      onPressed: null,
                      enabled: true,
                      size: PrismTokens.topBarActionSize,
                      tint: _filter != _PollFilter.active
                          ? theme.colorScheme.primary
                          : null,
                    ),
                  ),
                  PrismTopBarAction(
                    icon: AppIcons.add,
                    tooltip: context.l10n.pollsCreateTooltip,
                    onPressed: () => _showCreateSheet(context),
                  ),
                ],
              ),
            ),

            // Poll list
            pollsAsync.when(
              skipLoadingOnReload: true,
              data: (polls) {
                if (polls.isEmpty) {
                  final (icon, title, subtitle) = switch (_filter) {
                    _PollFilter.active => (
                      Icon(AppIcons.howToVoteOutlined),
                      context.l10n.pollsEmptyActiveTitle,
                      context.l10n.pollsEmptyActiveSubtitle,
                    ),
                    _PollFilter.closed => (
                      Icon(AppIcons.checkCircleOutline),
                      context.l10n.pollsEmptyClosedTitle,
                      context.l10n.pollsEmptyClosedSubtitle,
                    ),
                    _PollFilter.all => (
                      Icon(AppIcons.pollOutlined),
                      context.l10n.pollsEmptyAllTitle,
                      context.l10n.pollsEmptyAllSubtitle,
                    ),
                  };

                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: icon,
                      title: title,
                      subtitle: subtitle,
                      actionLabel: _filter == _PollFilter.all
                          ? context.l10n.pollsEmptyCreateLabel
                          : null,
                      onAction: _filter == _PollFilter.all
                          ? () => _showCreateSheet(context)
                          : null,
                    ),
                  );
                }

                final sorted = [...polls]
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                return SliverList.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    return _PollCard(poll: sorted[index]);
                  },
                );
              },
              loading: () => const PrismLoadingState.sliver(),
              error: (error, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.errorOutline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.pollsLoadError,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('$error', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom padding to clear floating nav bar
            SliverPadding(
              padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          CreatePollSheet(scrollController: scrollController),
    );
  }
}

// -- Poll card -------------------------------------------------------------

class _PollCard extends StatelessWidget {
  const _PollCard({required this.poll});

  final PollSummary poll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isExpired = poll.expiresAt != null && poll.expiresAt!.isBefore(now);
    final isClosed = poll.isClosed || isExpired;

    final totalVotes = poll.voteCount;

    return GestureDetector(
      onTap: () => context.go(AppRoutePaths.poll(poll.id)),
      child: PrismSurface(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        borderRadius: 14,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      poll.question,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isClosed)
                    PrismPill(
                      label: isExpired
                          ? context.l10n.pollsExpired
                          : context.l10n.pollsClosed,
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Info row
              Row(
                children: [
                  Icon(
                    AppIcons.howToVoteOutlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.pollsVoteCount(totalVotes),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    AppIcons.listView,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.pollsOptionCount(poll.optionCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (poll.expiresAt != null && !isClosed) ...[
                    const Spacer(),
                    Icon(
                      AppIcons.schedule,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatCountdown(context, poll.expiresAt!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),

              // Settings indicators
              if (poll.isAnonymous || poll.allowsMultipleVotes) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (poll.isAnonymous)
                      _InfoChip(
                        icon: AppIcons.visibilityOffOutlined,
                        label: context.l10n.pollsAnonymous,
                      ),
                    if (poll.allowsMultipleVotes)
                      _InfoChip(
                        icon: AppIcons.checkBoxOutlined,
                        label: context.l10n.pollsMultiVote,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatCountdown(BuildContext context, DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return context.l10n.pollsExpired;
    if (diff.inDays > 0) return context.l10n.pollsCountdownDays(diff.inDays);
    if (diff.inHours > 0) return context.l10n.pollsCountdownHours(diff.inHours);
    if (diff.inMinutes > 0) {
      return context.l10n.pollsCountdownMinutes(diff.inMinutes);
    }
    return context.l10n.pollsCountdownEndingSoon;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
