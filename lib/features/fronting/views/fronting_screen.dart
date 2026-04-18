import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/add_front_session_sheet.dart';
import 'package:prism_plurality/features/fronting/views/empty_system_view.dart';
import 'package:prism_plurality/features/fronting/views/start_sleep_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/polls/views/create_poll_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_mode_card.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_view.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

class FrontingScreen extends ConsumerStatefulWidget {
  const FrontingScreen({super.key});

  @override
  ConsumerState<FrontingScreen> createState() => _FrontingScreenState();
}

class _FrontingScreenState extends ConsumerState<FrontingScreen> {
  final _scrollController = ScrollController();
  bool _graceElapsed = false;
  Timer? _graceTimer;
  bool _markedMembersFirstEmit = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _graceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _graceElapsed = true);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      final currentLimit = ref.read(sessionLimitProvider);
      final sessions = ref.read(unifiedHistoryProvider).value;
      if (sessions != null && sessions.length >= currentLimit) {
        ref.read(sessionLimitProvider.notifier).loadMore();
        SemanticsService.sendAnnouncement(
          View.of(context),
          context.l10n.frontingLoadingOlderSessions,
          TextDirection.ltr,
        );
      }
    }
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);

    if (!_markedMembersFirstEmit && !membersAsync.isLoading) {
      _markedMembersFirstEmit = true;
      BootTimings.mark('members first emit');
    }
    // Scroll to top when the home tab is re-tapped.
    ref.listen(tabRetapProvider, (_, _) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });

    final isEmpty = membersAsync.whenOrNull(data: (members) => members.isEmpty);

    final systemName = ref.watch(systemNameProvider) ?? 'Prism';

    if (isEmpty == true) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            PrismTopBar(title: systemName),
            const Expanded(child: EmptySystemView()),
          ],
        ),
      );
    }

    final sleepAsync = ref.watch(activeSleepSessionProvider);
    final isSleeping = sleepAsync.value != null;
    final isTimelineView = ref.watch(timelineViewActiveProvider);

    // "Initial load only" — hasValue is false while the stream has not
    // emitted yet; reloads keep hasValue=true so this flag goes false and we
    // show the stale content normally while new data fetches.
    bool initialLoading(AsyncValue v) => v.isLoading && !v.hasValue;

    final showInitialLoader =
        !isTimelineView &&
        _graceElapsed &&
        (initialLoading(membersAsync) || initialLoading(sleepAsync));

    if (showInitialLoader) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            PrismTopBar(title: systemName),
            const Expanded(child: Center(child: PrismLoadingState())),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isTimelineView
          ? _buildTimelineView(theme, systemName, isSleeping, sleepAsync.value)
          : _buildListView(theme, systemName, isSleeping, sleepAsync.value),
    );
  }

  Widget? _buildViewToggle() {
    final showToggle =
        ref.watch(showFrontingViewToggleProvider).whenOrNull(data: (v) => v) ?? true;
    if (!showToggle) return null;

    final isTimelineView = ref.watch(timelineViewActiveProvider);
    return PrismTopBarAction(
      icon: isTimelineView
          ? AppIcons.viewListRounded
          : AppIcons.timelineRounded,
      tooltip: isTimelineView
          ? context.l10n.frontingListView
          : context.l10n.frontingTimelineView,
      onPressed: () => ref.read(timelineViewActiveProvider.notifier).toggle(),
    );
  }

  Widget _buildListView(
    ThemeData theme,
    String systemName,
    bool isSleeping,
    FrontingSession? sleepSession,
  ) {
    final showQuickFront = ref.watch(showQuickFrontProvider);
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPinnedTopBar(
          child: PrismTopBar(
            title: systemName,
            leading: _buildViewToggle(),
            trailing: _AddButton(
              isSleeping: isSleeping,
              sleepSession: sleepSession,
            ),
          ),
        ),

        // 1. Quick Front (shown based on user setting)
        if (showQuickFront)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: QuickFrontSection(),
            ),
          ),

        // 2. Home banners share one placement under Quick Front.
        SliverToBoxAdapter(child: FrontingBannerStack(theme: theme)),

        // 3. Active sleep session card
        if (isSleeping)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SleepModeCard(),
            ),
          ),

        // 4. Sessions grouped by day (active session naturally at top)
        const SessionHistoryList(),

        // 5. Loading indicator for infinite scroll
        Consumer(
          builder: (context, ref, _) {
            final limit = ref.watch(sessionLimitProvider);
            final sessions = ref.watch(unifiedHistoryProvider).value;
            final hasMore = sessions != null && sessions.length >= limit;
            if (!hasMore) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: PrismLoadingState(),
              ),
            );
          },
        ),

        // Bottom padding to clear floating nav bar
        SliverPadding(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        ),
      ],
    );
  }

  Widget _buildTimelineView(
    ThemeData theme,
    String systemName,
    bool isSleeping,
    FrontingSession? sleepSession,
  ) {
    final showQuickFront = ref.watch(showQuickFrontProvider);
    return Column(
      children: [
        PrismTopBar(
          title: systemName,
          leading: _buildViewToggle(),
          trailing: _AddButton(
            isSleeping: isSleeping,
            sleepSession: sleepSession,
          ),
        ),
        if (showQuickFront)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: QuickFrontSection(),
          ),
        if (isSleeping)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SleepModeCard(),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
            child: const TimelineView(),
          ),
        ),
      ],
    );
  }
}

/// Displays a warning banner when the post-edit (or future post-sync) rescan
/// detects timeline validation issues. Hidden when the count is zero.
class _TimelineIssueBanner extends ConsumerWidget {
  const _TimelineIssueBanner({
    required this.theme,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final ThemeData theme;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issueCount = ref.watch(frontingIssueCountProvider);
    if (issueCount <= 0) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: InfoBanner(
        icon: AppIcons.warningAmberRounded,
        iconColor: theme.colorScheme.error,
        title: context.l10n.frontingTimelineIssuesFound,
        message: context.l10n.frontingTimelineIssuesBannerMessage(issueCount),
        buttonText: context.l10n.frontingTimelineIssuesReview,
        onButtonPressed: () => context.push('/settings/timeline-sanitization'),
      ),
    );
  }
}

/// App bar action button: tap for Log Front, long-press for context menu.
class _AddButton extends ConsumerStatefulWidget {
  const _AddButton({required this.isSleeping, required this.sleepSession});

  final bool isSleeping;
  final FrontingSession? sleepSession;

  @override
  ConsumerState<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends ConsumerState<_AddButton> {
  final _popupKey = GlobalKey<BlurPopupAnchorState>();

  bool get isSleeping => widget.isSleeping;
  FrontingSession? get sleepSession => widget.sleepSession;

  @override
  Widget build(BuildContext context) {
    final terms = watchTerminology(context, ref);
    final pkState = ref.watch(pluralKitSyncProvider);
    final pkReady = pkState.isConnected &&
        !pkState.needsMapping &&
        !pkState.isSyncing;

    // Build menu items for the blur popup.
    final menuItems = <_MenuItem>[];

    if (isSleeping && sleepSession != null) {
      menuItems.add(
        _MenuItem(
          icon: AppIcons.wbSunnyRounded,
          label: context.l10n.frontingMenuWakeUpAs,
          onTap: (close) {
            close();
            _showWakeUpPicker(context, ref);
          },
        ),
      );
    }

    menuItems.addAll([
      _MenuItem(
        icon: AppIcons.personOutline,
        label: context.l10n.frontingMenuLogFront,
        onTap: (close) {
          close();
          _openAddSessionSheet(context);
        },
      ),
      _MenuItem(
        icon: AppIcons.personAddOutlined,
        label: context.l10n.terminologyAddButton(terms.singular),
        onTap: (close) {
          close();
          PrismSheet.showFullScreen(
            context: context,
            builder: (context, scrollController) =>
                AddEditMemberSheet(scrollController: scrollController),
          );
        },
      ),
      _MenuItem(
        icon: AppIcons.pollOutlined,
        label: context.l10n.frontingMenuNewPoll,
        onTap: (close) {
          close();
          PrismSheet.showFullScreen(
            context: context,
            builder: (context, scrollController) =>
                CreatePollSheet(scrollController: scrollController),
          );
        },
      ),
      if (pkReady)
        _MenuItem(
          icon: AppIcons.refresh,
          label: context.l10n.frontingMenuSyncPluralKit,
          onTap: (close) {
            close();
            _runPluralKitSync(context, ref);
          },
        ),
      _MenuItem(
        icon: AppIcons.bedtimeRounded,
        label: context.l10n.frontingMenuStartSleep,
        enabled: !isSleeping,
        onTap: (close) {
          close();
          PrismSheet.showFullScreen(
            context: context,
            useRootNavigator: true,
            builder: (ctx, sc) => StartSleepSheet(scrollController: sc),
          );
        },
      ),
    ]);

    return BlurPopupAnchor(
      key: _popupKey,
      trigger: BlurPopupTrigger.manual,
      preferredDirection: BlurPopupDirection.down,
      width: 200,
      maxHeight: 320,
      itemCount: menuItems.length,
      itemBuilder: (context, index, close) {
        final item = menuItems[index];
        final theme = Theme.of(context);
        return PrismListRow(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: Icon(
            item.icon,
            size: 20,
            color: item.enabled
                ? theme.colorScheme.onSurface
                : theme.disabledColor,
          ),
          title: Text(
            item.label,
            style: TextStyle(
              fontSize: 14,
              color: item.enabled
                  ? theme.colorScheme.onSurface
                  : theme.disabledColor,
            ),
          ),
          enabled: item.enabled,
          onTap: item.enabled ? () => item.onTap(close) : null,
        );
      },
      child: PrismTopBarAction(
        icon: AppIcons.add,
        tooltip: context.l10n.frontingAddEntry,
        onPressed: () => _openAddSessionSheet(context),
        onLongPress: () => _popupKey.currentState?.show(),
      ),
    );
  }

  void _openAddSessionSheet(BuildContext context) {
    AddFrontSessionSheet.show(context);
  }

  Future<void> _runPluralKitSync(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(pluralKitSyncProvider.notifier).syncRecentData(
            isManual: true,
            direction: ref.read(pkSyncDirectionProvider),
          );
      if (!context.mounted) return;
      PrismToast.success(
        context,
        message: context.l10n.frontingPluralKitSyncDoneToast,
      );
    } catch (e) {
      if (!context.mounted) return;
      PrismToast.error(
        context,
        message: context.l10n.frontingPluralKitSyncFailedToast(e),
      );
    }
  }

  void _showWakeUpPicker(BuildContext context, WidgetRef ref) {
    final members = ref.read(activeMembersProvider).value ?? [];

    PrismDialog.show<void>(
      context: context,
      title: context.l10n.frontingWakeUpAsTitle,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: members
              .map(
                (member) => PrismListRow(
                  padding: EdgeInsets.zero,
                  leading: Text(
                    member.emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(member.name),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await ref
                          .read(sleepNotifierProvider.notifier)
                          .endSleep(sleepSession!.id);
                      await ref
                          .read(frontingNotifierProvider.notifier)
                          .startFronting(member.id);
                    } catch (e) {
                      if (context.mounted) {
                        PrismToast.error(
                          context,
                          message: context.l10n.frontingErrorWakingUp(e),
                        );
                      }
                    }
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final void Function(VoidCallback close) onTap;
  final bool enabled;
}


/// Banner reminding the user to start sleep when their configured bedtime
/// has arrived and no sleep session is currently active.
///
/// Uses a periodic timer to self-update so the banner appears even if the
/// user is idle on the fronting screen when bedtime arrives.
class _BedtimeReminderBanner extends ConsumerStatefulWidget {
  const _BedtimeReminderBanner({
    required this.theme,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final ThemeData theme;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<_BedtimeReminderBanner> createState() =>
      _BedtimeReminderBannerState();
}

class _BedtimeReminderBannerState
    extends ConsumerState<_BedtimeReminderBanner> {
  static const _dismissedPrefsKey = 'prism.bedtime_dismissed_date';
  static const _windowMinutes = 240; // 4 hours after bedtime

  Timer? _timer;
  String? _dismissedDate;

  @override
  void initState() {
    super.initState();
    _loadDismissedDate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _loadDismissedDate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _dismissedDate = prefs.getString(_dismissedPrefsKey));
  }

  Future<void> _dismissForToday() async {
    final today = _todayKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedPrefsKey, today);
    if (!mounted) return;
    setState(() => _dismissedDate = today);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(sleepSuggestionEnabledProvider);
    if (enabled) {
      _startTimer();
    } else {
      _stopTimer();
      return const SizedBox.shrink();
    }

    final sleepAsync = ref.watch(activeSleepSessionProvider);
    final isSleeping = sleepAsync.value != null;
    if (isSleeping) return const SizedBox.shrink();

    if (_dismissedDate == _todayKey()) return const SizedBox.shrink();

    final time = ref.watch(sleepSuggestionTimeProvider);
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final bedtimeMinutes = time.hour * 60 + time.minute;
    // Modular difference handles cross-midnight bedtimes (e.g., 01:00):
    // bedtime 22:00, now 00:30 → 150 min after bedtime, still in window.
    final minutesSinceBedtime =
        (nowMinutes - bedtimeMinutes + 1440) % 1440;
    if (minutesSinceBedtime >= _windowMinutes) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: widget.padding,
      child: InfoBanner(
        icon: AppIcons.bedtimeRounded,
        iconColor: AppColors.sleep(widget.theme.brightness),
        title: context.l10n.sleepSuggestionBedtime,
        message: '',
        buttonText: context.l10n.sleepSuggestionBedtimeAction,
        onButtonPressed: () {
          PrismSheet.showFullScreen(
            context: context,
            useRootNavigator: true,
            builder: (ctx, sc) => StartSleepSheet(scrollController: sc),
          );
        },
        onDismiss: _dismissForToday,
        dismissTooltip: context.l10n.sleepSuggestionBedtimeDismiss,
      ),
    );
  }
}

class FrontingBannerStack extends StatelessWidget {
  const FrontingBannerStack({required this.theme, super.key});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TimelineIssueBanner(
          theme: theme,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        ),
        _BedtimeReminderBanner(
          theme: theme,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        ),
      ],
    );
  }
}
