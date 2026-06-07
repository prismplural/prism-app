import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';
import 'package:prism_plurality/features/fronting/views/start_sleep_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_mode_card.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_session_row.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_stat_cards.dart';
import 'package:prism_plurality/features/settings/views/sleep_feature_settings_screen.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/clamped_body.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;

    final history = ref.read(sleepHistoryProvider);
    if (history.isLoading) return;
    final loaded = history.value?.length ?? 0;
    final currentLimit = ref.read(sleepHistoryLimitProvider);
    if (loaded >= currentLimit) {
      ref.read(sleepHistoryLimitProvider.notifier).loadMore();
    }
  }

  void _openAddSheet() {
    PrismSheet.showFullScreen(
      context: context,
      useRootNavigator: true,
      builder: (ctx, sc) => StartSleepSheet(scrollController: sc),
    );
  }

  void _openSettings() {
    context.push(
      AppRoutePaths.settingsFeaturesSleep,
      extra: const SleepFeatureSettingsArgs(fromSleepView: true),
    );
  }

  void _openSessionDetail(FrontingSession session) {
    showAdaptiveDetailSurface<void>(
      context: context,
      builder: (_) => SessionDetailScreen(sessionId: session.id),
      route: (context) => context.push(AppRoutePaths.sleepSession(session.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activeSleep = ref.watch(activeSleepSessionProvider).value;
    final sessionsAsync = ref.watch(sleepHistoryProvider);
    final statsAsync = ref.watch(sleepStatsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClampedBody(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPinnedTopBar(
              child: PrismTopBar(
                title: l10n.sleepScreenTitle,
                showBackButton: widget.showBackButton,
                actions: [
                  PrismTopBarAction(
                    icon: AppIcons.navSettings,
                    tooltip: l10n.sleepScreenSettingsTooltip,
                    onPressed: _openSettings,
                  ),
                  PrismTopBarAction(
                    icon: AppIcons.add,
                    tooltip: l10n.sleepScreenAddTooltip,
                    onPressed: _openAddSheet,
                  ),
                ],
              ),
            ),

            if (activeSleep != null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SleepModeCard(),
                ),
              ),

            // Stat cards (visibility rule lives inside the widget)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SleepStatCards(),
              ),
            ),

            ..._buildBody(
              l10n: l10n,
              sessionsAsync: sessionsAsync,
              statsAsync: statsAsync,
            ),

            SliverPadding(
              padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody({
    required dynamic l10n,
    required AsyncValue<List<FrontingSession>> sessionsAsync,
    required AsyncValue<dynamic> statsAsync,
  }) {
    return sessionsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const [
        _SleepStateSliver(child: Center(child: PrismLoadingState())),
      ],
      error: (e, _) => [
        _SleepStateSliver(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('$e')),
        ),
      ],
      data: (sessions) {
        // EmptyState only when there are zero sleep sessions ever
        // (active or recent).
        final activeSleep = ref.read(activeSleepSessionProvider).value;
        if (sessions.isEmpty && activeSleep == null) {
          return [
            _SleepStateSliver(
              child: EmptyState(
                icon: Icon(AppIcons.navSleep),
                title: l10n.sleepEmptyTitle,
                subtitle: l10n.sleepEmptyBody,
                actionLabel: l10n.sleepScreenAddTooltip,
                actionIcon: AppIcons.add,
                onAction: _openAddSheet,
              ),
            ),
          ];
        }

        final grouped = groupSleepByEndDate(sessions);
        final sortedKeys = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.sleepRecentSectionHeader,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final dayKey in sortedKeys)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: PrismSectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final session in grouped[dayKey]!)
                        SleepSessionRow(
                          session: session,
                          onTap: () => _openSessionDetail(session),
                          onLongPress: () => _confirmDelete(session),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ];
      },
    );
  }

  Future<void> _confirmDelete(FrontingSession session) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.frontingDeleteSleepTitle,
      message: context.l10n.frontingDeleteSleepMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!mounted) return;
    if (confirmed) {
      Haptics.heavy();
      await ref.read(sleepNotifierProvider.notifier).deleteSleep(session.id);
    }
  }
}

class _SleepStateSliver extends StatelessWidget {
  const _SleepStateSliver({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final remainingExtent =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent;
        final minHeight = remainingExtent.isFinite && remainingExtent > 0
            ? remainingExtent
            : 0.0;

        return SliverToBoxAdapter(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: child,
          ),
        );
      },
    );
  }
}
