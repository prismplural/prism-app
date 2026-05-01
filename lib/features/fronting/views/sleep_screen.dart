import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';
import 'package:prism_plurality/features/fronting/views/edit_sleep_sheet.dart';
import 'package:prism_plurality/features/fronting/views/start_sleep_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_mode_card.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_session_row.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_stat_cards.dart';
import 'package:prism_plurality/features/settings/views/sleep_feature_settings_screen.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

/// Initial page size for the recent sleep sessions list. Pagination
/// increments this in steps of [_kSleepPageSize] when the user scrolls
/// near the bottom.
const int _kSleepPageSize = 20;

class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen> {
  final _scrollController = ScrollController();
  int _limit = _kSleepPageSize;

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
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      final loaded =
          ref.read(recentSleepSessionsPaginatedProvider(_limit)).value?.length ??
              0;
      if (loaded >= _limit) {
        setState(() => _limit += _kSleepPageSize);
      }
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

  Future<void> _openEditSheet(FrontingSession session) async {
    await EditSleepSheet.show(context, session);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activeSleep = ref.watch(activeSleepSessionProvider).value;
    final sessionsAsync = ref.watch(
      recentSleepSessionsPaginatedProvider(_limit),
    );
    final statsAsync = ref.watch(sleepStatsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
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
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: PrismLoadingState()),
        ),
      ],
      error: (e, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e'),
          ),
        ),
      ],
      data: (sessions) {
        // EmptyState only when there are zero sleep sessions ever
        // (active or recent).
        final activeSleep = ref.read(activeSleepSessionProvider).value;
        if (sessions.isEmpty && activeSleep == null) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
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
                          onTap: () => _openEditSheet(session),
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
