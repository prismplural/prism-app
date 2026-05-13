import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/migration/widgets/fronting_upgrade_banner.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/quick_front_hint_provider.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/add_front_session_sheet.dart';
import 'package:prism_plurality/features/fronting/views/empty_system_view.dart';
import 'package:prism_plurality/features/fronting/views/start_sleep_sheet.dart';
import 'package:prism_plurality/features/fronting/widgets/always_present_header.dart';
import 'package:prism_plurality/features/fronting/widgets/quick_front_section.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_unmapped_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_unpushed_members_notice.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_mode_card.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
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
  // 1B: latches when we've seeded `timelineViewActiveProvider` from
  // the user's `fronting_list_view_mode` preference for this screen
  // instance. The home tab is in an `IndexedStack` keep-alive, so
  // "first build" effectively means "first visit per app session."
  // After the seed, the user's toggle wins until the next mount — a
  // setting change via sync from another device while the user is
  // mid-screen does NOT override their current toggle position.
  bool _toggleInitialized = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _graceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _graceElapsed = true);
    });
  }

  /// Seeds `timelineViewActiveProvider` from the user's
  /// `fronting_list_view_mode` preference. Idempotent within a single
  /// `FrontingScreen` instance. Called from `build` because the
  /// preference is a `StreamProvider<SystemSettings>` whose first emit
  /// can land after `initState` runs.
  void _maybeInitializeToggleFromPref() {
    if (_toggleInitialized) return;
    final mode = ref
        .read(systemSettingsProvider)
        .whenOrNull(data: (s) => s.frontingListViewMode);
    if (mode == null) return;
    _toggleInitialized = true;
    final shouldShowTimeline = mode == FrontingListViewMode.timeline;
    if (ref.read(timelineViewActiveProvider) == shouldShowTimeline) return;
    // Setting notifier state synchronously inside build is illegal —
    // defer to the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(timelineViewActiveProvider.notifier)
          .setActive(shouldShowTimeline);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      final currentLimit = ref.read(sessionLimitProvider);
      final history = ref.read(unifiedHistoryProvider);
      if (history.isLoading) return;
      final sessions = history.value;
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

    // 1B: seed the list↔timeline toggle from the
    // `fronting_list_view_mode` preference on first emit. Watching the
    // provider here ensures the seed runs once the StreamProvider has
    // data — typically the first or second build. Subsequent emits
    // (e.g., a sync push from another device) won't re-seed because
    // `_toggleInitialized` latches.
    ref.watch(systemSettingsProvider);
    _maybeInitializeToggleFromPref();
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
          ? _buildTimelineView(systemName, isSleeping, sleepAsync.value)
          : _buildListView(theme, systemName, isSleeping, sleepAsync.value),
    );
  }

  Widget? _buildViewToggle() {
    final showToggle =
        ref.watch(showFrontingViewToggleProvider).whenOrNull(data: (v) => v) ??
        true;
    if (!showToggle) return null;

    final isTimelineView = ref.watch(timelineViewActiveProvider);
    return PrismTopBarAction(
      icon: isTimelineView
          ? AppIcons.viewListRounded
          : AppIcons.timelineRounded,
      tooltip: isTimelineView
          ? context.l10n.frontingListView
          : context.l10n.frontingTimelineView,
      onPressed: () {
        // Latch before toggling: a user tap during the window before
        // `systemSettingsProvider` first emits would otherwise be
        // overwritten by `_maybeInitializeToggleFromPref` on the next
        // build. The user's explicit choice wins from this point on.
        _toggleInitialized = true;
        ref.read(timelineViewActiveProvider.notifier).toggle();
      },
    );
  }

  Widget _buildListView(
    ThemeData theme,
    String systemName,
    bool isSleeping,
    FrontingSession? sleepSession,
  ) {
    final showQuickFront = ref.watch(showQuickFrontProvider);
    // Watching here (rather than only inside the widget) lets the sliver's
    // [AlwaysPresentSliverDelegate] collapse its extent to 0 when no
    // member qualifies, so the home content does not keep an empty gap.
    final alwaysPresentCount =
        ref.watch(alwaysPresentMembersProvider).value?.length ?? 0;
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
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _QuickFrontHomeBlock(),
            ),
          ),

        // 2. Action banners stay near the top of the home feed.
        const SliverToBoxAdapter(child: FrontingActionBannerStack()),

        // 3. Always-present fronters sit under Quick Front, then pin while
        // the rest of the fronting feed scrolls.
        SliverPersistentHeader(
          pinned: true,
          delegate: AlwaysPresentSliverDelegate(count: alwaysPresentCount),
        ),

        // 4. Sleep-oriented banners stay out of timeline mode.
        SliverToBoxAdapter(child: FrontingSleepBannerStack(theme: theme)),

        // 5. Active sleep session card
        if (isSleeping)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SleepModeCard(),
            ),
          ),

        // 6. Sessions grouped by day (active session naturally at top)
        const SessionHistoryList(),

        // 7. Loading indicator for infinite scroll
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
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _QuickFrontHomeBlock(),
          ),
        const FrontingActionBannerStack(),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: showQuickFront ? 0 : 8,
              bottom: NavBarInset.of(context),
            ),
            child: const Stack(
              children: [
                Positioned.fill(child: TimelineView()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: CurrentFrontingPresenceRow(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickFrontHomeBlock extends ConsumerWidget {
  const _QuickFrontHomeBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final showInstruction = ref.watch(quickFrontHoldInstructionVisibleProvider);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showInstruction) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth = constraints.maxWidth / 4;
              final ringSize = slotWidth < quickFrontRingSize
                  ? slotWidth
                  : quickFrontRingSize;
              final circleInset = ((slotWidth - ringSize) / 2).clamp(
                0.0,
                double.infinity,
              );

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: circleInset),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.featureFrontingShowQuickFront,
                        style: labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        context.l10n.frontingQuickFrontHoldInstruction,
                        style: labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
        ],
        const QuickFrontSection(),
      ],
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
    final activeMembers = ref.watch(activeMembersProvider).value ?? const [];
    final wakeUpGroups = watchMemberSearchGroups(ref, activeMembers);
    final pkState = ref.watch(pluralKitSyncProvider);
    final pkReady =
        pkState.canAutoSync && !pkState.isSyncing;

    // Build menu items for the blur popup.
    final menuItems = <_MenuItem>[];

    if (isSleeping && sleepSession != null) {
      menuItems.add(
        _MenuItem(
          icon: AppIcons.wbSunnyRounded,
          label: context.l10n.frontingMenuWakeUpAs,
          onTap: (close) {
            close();
            _showWakeUpPicker(
              context,
              ref,
              activeMembers,
              terms.plural,
              wakeUpGroups,
            );
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
        icon: AppIcons.history,
        label: context.l10n.frontingMenuLogPastSession,
        onTap: (close) {
          close();
          _openAddSessionSheet(context, initialHistorical: true);
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

  void _openAddSessionSheet(
    BuildContext context, {
    bool initialHistorical = false,
  }) {
    AddFrontSessionSheet.show(context, initialHistorical: initialHistorical);
  }

  Future<void> _runPluralKitSync(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(pkSyncModeProvider.notifier).load();
      await ref.read(pkSyncDirectionProvider.notifier).load();
      if (!context.mounted) return;

      final mode = ref.read(pkSyncModeProvider);
      final direction = ref.read(pkSyncDirectionProvider);
      if (mode == PkSyncMode.liveFrontsOnly) {
        await ref
            .read(pluralKitSyncProvider.notifier)
            .syncLiveFrontersOnly(isManual: true, direction: direction);
      } else {
        final syncState = ref.read(pluralKitSyncProvider);
        if (_canCurrentSyncDrainDestructivePush(
          syncState: syncState,
          mode: mode,
          direction: direction,
        )) {
          final confirmed = await _confirmPluralKitDeleteRisk(context, ref);
          if (!context.mounted || !confirmed) return;
        }

        await ref
            .read(pluralKitSyncProvider.notifier)
            .syncRecentData(isManual: true, direction: direction);
      }

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

  bool _canCurrentSyncDrainDestructivePush({
    required PluralKitSyncState syncState,
    required PkSyncMode mode,
    required PkSyncDirection direction,
  }) {
    if (mode != PkSyncMode.fullSync) return false;
    if (!direction.pushEnabled) return false;
    if (direction.pullEnabled && syncState.lastSyncDate == null) return false;
    return true;
  }

  Future<bool> _confirmPluralKitDeleteRisk(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final PkDeleteRiskPreview preview;
    try {
      preview = await ref
          .read(pluralKitSyncProvider.notifier)
          .previewPendingDestructivePush();
    } catch (_) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.pluralkitDeleteRiskPreviewFailed,
        );
      }
      return false;
    }

    if (!context.mounted) return false;
    if (!preview.hasRemovals || !preview.isSignificant) return true;

    return PrismDialog.confirm(
      context: context,
      title: context.l10n.pluralkitDeleteRiskTitle,
      message: _formatDeleteRiskMessage(context, preview),
      confirmLabel: context.l10n.pluralkitDeleteRiskConfirm,
      cancelLabel: context.l10n.pluralkitDeleteRiskCancel,
      destructive: true,
      icon: AppIcons.warningAmber,
    );
  }

  String _formatDeleteRiskMessage(
    BuildContext context,
    PkDeleteRiskPreview preview,
  ) {
    final deleteText = _formatDeleteRiskItems(context, preview);
    if (preview.totalSkipped > 0) {
      return context.l10n.pluralkitDeleteRiskMessageWithSkipped(
        deleteText,
        preview.totalSkipped,
      );
    }
    return context.l10n.pluralkitDeleteRiskMessage(deleteText);
  }

  String _formatDeleteRiskItems(
    BuildContext context,
    PkDeleteRiskPreview preview,
  ) {
    final items = <String>[
      if (preview.membersToDelete > 0)
        context.l10n.pluralkitDeleteRiskMembers(preview.membersToDelete),
      if (preview.switchesToDelete > 0)
        context.l10n.pluralkitDeleteRiskSwitches(preview.switchesToDelete),
      if (preview.groupMembershipsToRemove > 0)
        context.l10n.pluralkitDeleteRiskGroupMemberships(
          preview.groupMembershipsToRemove,
        ),
    ];

    if (items.length <= 1) return items.isEmpty ? '' : items.first;
    if (items.length == 2) {
      return context.l10n.pluralkitDeleteRiskJoinTwo(items[0], items[1]);
    }
    return context.l10n.pluralkitDeleteRiskJoinThree(
      items[0],
      items[1],
      items[2],
    );
  }

  Future<void> _showWakeUpPicker(
    BuildContext context,
    WidgetRef ref,
    List<Member> members,
    String termPlural,
    List<MemberSearchGroup> groups,
  ) async {
    final session = sleepSession;
    if (session == null) return;

    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: termPlural,
      groups: groups,
    );

    if (!mounted || !context.mounted) return;
    if (result is! MemberSearchResultSelected) return;
    final activeSession = ref.read(activeSleepSessionProvider).value;
    if (activeSession?.id != session.id) return;

    try {
      await ref.read(sleepNotifierProvider.notifier).endSleep(session.id);
      await ref.read(frontingNotifierProvider.notifier).startFronting([
        result.memberId,
      ]); // single-member start post-sleep
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorWakingUp(e),
        );
      }
    }
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
    final minutesSinceBedtime = (nowMinutes - bedtimeMinutes + 1440) % 1440;
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

class FrontingActionBannerStack extends StatelessWidget {
  const FrontingActionBannerStack({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fronting per-member upgrade banner — only renders when
        // migration cleanup needs to be resumed. Auto-hidden after
        // migration completes via Riverpod state.
        FrontingUpgradeBanner(padding: EdgeInsets.fromLTRB(16, 8, 16, 0)),
        PluralKitUnmappedFrontersNoticeBanner(),
        PluralKitUnpushedMembersNoticeBanner(),
      ],
    );
  }
}

class FrontingSleepBannerStack extends StatelessWidget {
  const FrontingSleepBannerStack({required this.theme, super.key});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BedtimeReminderBanner(
          theme: theme,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        ),
      ],
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
        const FrontingActionBannerStack(),
        FrontingSleepBannerStack(theme: theme),
      ],
    );
  }
}
