import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/features/settings/widgets/sync_pin_sheet.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/desktop_breakpoint.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/pin_lock_decision.dart';
import 'package:prism_plurality/shared/widgets/floating_nav_bar_backdrop.dart';

/// Gap between overflow row and primary row when the nav bar is expanded.
const _kNavBarRowGap = 6.0;

/// Width of the compact More/close trigger on the trailing edge.
const _kMoreButtonWidth = 44.0;

/// Incremented each time the user taps the already-selected tab.
/// Screens can watch this to scroll-to-top or perform other re-engage actions.
final tabRetapProvider = NotifierProvider<TabRetapNotifier, int>(
  TabRetapNotifier.new,
);

class TabRetapNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void fire() => state++;
}

/// Provides the actual floating nav bar inset to descendant widgets.
/// Use `NavBarInset.of(context)` to get the total bottom space to pad content.
class NavBarInset extends InheritedWidget {
  const NavBarInset({
    super.key,
    required this.bottomInset,
    required super.child,
  });

  /// Total height from the bottom of the screen that the nav bar occupies
  /// (bar height + margin + safe area). Screens should use this for bottom
  /// padding on scrollable content.
  final double bottomInset;

  static double of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<NavBarInset>();
    return widget?.bottomInset ?? 0;
  }

  @override
  bool updateShouldNotify(NavBarInset oldWidget) =>
      bottomInset != oldWidget.bottomInset;
}

/// Nav bar dimensions.
const kFloatingNavBarHeight = 64.0;
const kFloatingNavBarSideMargin = 16.0;
const kFloatingNavBarBottomMargin = 2.0; // Sits close to the iOS home indicator

/// Sidebar dimensions.
const _kSidebarWidth = 200.0;
const _kSidebarItemHeight = 38.0;

/// Wraps [child] in a [Badge] for tabs that have notifications.
Widget _maybeBadge({
  required AppShellTab tab,
  required bool showSyncBadge,
  required int habitsDueCount,
  required int chatUnreadCount,
  required Widget child,
}) {
  if (tab.id == AppShellTabId.settings && showSyncBadge) {
    return Badge(isLabelVisible: true, smallSize: 8, child: child);
  }
  if (tab.id == AppShellTabId.habits && habitsDueCount > 0) {
    return Badge(label: Text('$habitsDueCount'), child: child);
  }
  if (tab.id == AppShellTabId.chat && chatUnreadCount > 0) {
    return Badge(
      label: Text(chatUnreadCount > 99 ? '99+' : '$chatUnreadCount'),
      child: child,
    );
  }
  return child;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  bool _wasDesktop = false;
  bool _locked = false;

  /// Whether the initial PIN check has completed. While false, the app shows
  /// a loading/locked state to prevent content from being visible before we
  /// know whether PIN lock is enabled.
  bool _pinCheckResolved = false;
  bool _navExpanded = false;
  final _navBarKey = GlobalKey<_FloatingNavBarState>();
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Attempt an immediate check; if providers are still loading,
    // listeners set up in build() will resolve it when they emit data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialLock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _checkInitialLock() {
    if (_pinCheckResolved) return;

    final settingsAsync = ref.read(systemSettingsProvider);
    final isPinSetAsync = ref.read(isPinSetProvider);

    final decision = initialLockDecision(
      settingsLoading: settingsAsync is AsyncLoading,
      isPinSetLoading: isPinSetAsync is AsyncLoading,
      pinLockEnabled: settingsAsync.value?.pinLockEnabled,
      isPinSet: isPinSetAsync.value,
    );

    if (!decision.resolved) return;

    setState(() {
      _locked = decision.locked;
      _pinCheckResolved = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _checkLockOnResume();
      ref.invalidate(currentDateProvider);
    }
  }

  void _checkLockOnResume() {
    final settings = ref.read(systemSettingsProvider).value;
    final shouldLock = resumeLockDecision(
      alreadyLocked: _locked,
      pinLockEnabled: settings?.pinLockEnabled,
      isPinSet: ref.read(isPinSetProvider).value,
      backgroundedAt: _backgroundedAt,
      autoLockDelaySeconds: settings?.autoLockDelaySeconds ?? 0,
    );

    if (shouldLock) {
      setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = shouldBeDesktop(width, currentlyDesktop: _wasDesktop);
    _wasDesktop = isDesktop;

    // Build visible tabs from configurable providers.
    var primaryTabs = ref.watch(activeNavBarTabsProvider);
    var overflowTabs = ref.watch(navBarOverflowTabsProvider);

    // Auto-split: if the user has >5 primary tabs but hasn't explicitly
    // configured overflow items, split the excess into overflow automatically.
    if (primaryTabs.length > 5 && overflowTabs.isEmpty) {
      overflowTabs = primaryTabs.sublist(5);
      primaryTabs = primaryTabs.sublist(0, 5);
    }

    // All tabs combined for index mapping.
    final allTabs = [...primaryTabs, ...overflowTabs];

    // Map the current shell branch index to visible tab index.
    final currentVisibleIndex = allTabs.indexWhere(
      (t) => t.branchIndex == widget.navigationShell.currentIndex,
    );

    final safeCurrentIndex = currentVisibleIndex < 0 ? 0 : currentVisibleIndex;

    // Retry the initial PIN check when providers resolve (handles cold start
    // where providers were still loading during _checkInitialLock).
    if (!_pinCheckResolved) {
      ref.listen(systemSettingsProvider, (_, _) => _checkInitialLock());
      ref.listen(isPinSetProvider, (_, _) => _checkInitialLock());
    }

    // Keep syncStatusProvider alive so DeviceRevoked events are received.
    ref.watch(syncStatusProvider);

    // Show password sheet when sync needs the user's password.
    ref.listen<SyncHealthState>(syncHealthProvider, (prev, next) {
      if (next == SyncHealthState.needsPassword &&
          prev != SyncHealthState.needsPassword) {
        _showPasswordSheetIfNeeded(context, ref);
      }
    });
    if (ref.read(syncHealthProvider) == SyncHealthState.needsPassword) {
      _showPasswordSheetIfNeeded(context, ref);
    }

    void onTabTap(int allTabsIndex) {
      if (!isDesktop) Haptics.selection();
      final tab = allTabs[allTabsIndex];
      final isRetap = tab.branchIndex == widget.navigationShell.currentIndex;
      try {
        widget.navigationShell.goBranch(
          tab.branchIndex,
          initialLocation: isRetap,
        );
      } catch (e) {
        // If restoring the saved branch state fails (e.g. stale sub-route),
        // fall back to the branch's root location.
        debugPrint(
          '[AppShell] goBranch(${tab.branchIndex}) failed: $e '
          '— falling back to root',
        );
        widget.navigationShell.goBranch(tab.branchIndex, initialLocation: true);
      }
      if (isRetap) {
        ref.read(tabRetapProvider.notifier).fire();
      }
    }

    final accentColor = Theme.of(context).colorScheme.primary;

    Widget shell;

    if (isDesktop) {
      // Desktop layout: sidebar + content side by side.
      shell = NavBarInset(
        bottomInset: 0,
        child: SyncToastListener(
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Row(
              children: [
                _FloatingSidebar(
                  tabs: allTabs,
                  currentIndex: safeCurrentIndex,
                  accentColor: accentColor,
                  onTap: onTabTap,
                ),
                Expanded(child: widget.navigationShell),
              ],
            ),
          ),
        ),
      );
    } else {
      // Mobile layout: stack with floating bottom bar.
      // Hide the nav bar on sub-routes (detail screens) — only show on root tabs.
      final location = GoRouterState.of(context).uri.path;
      final isRootTab = appShellTabs.any((t) => t.rootLocation == location);

      final mediaQuery = MediaQuery.of(context);
      final bottomSafeArea = mediaQuery.viewPadding.bottom;
      final keyboardOpen = mediaQuery.viewInsets.bottom > 0;
      final hideNavBar = keyboardOpen || !isRootTab;
      final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

      // On iOS the full safe area (~34pt) pushes the floating pill too high.
      // Use a fixed 21pt bottom to sit comfortably above the home indicator.
      final isApple =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
      final navBarBottom = isApple && bottomSafeArea > 0
          ? 21.0
          : kFloatingNavBarBottomMargin + bottomSafeArea;
      final totalInset = kFloatingNavBarHeight + navBarBottom + 8;

      shell = NavBarInset(
        bottomInset: hideNavBar ? 0 : totalInset,
        child: SyncToastListener(
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: BackdropGroup(
              child: Stack(
                children: [
                  widget.navigationShell,

                  if (!hideNavBar) ...[
                    // Gradient fade
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: FloatingNavBarBackdrop(
                        height: totalInset + 10,
                        color: scaffoldBg,
                      ),
                    ),

                    // Dismiss overlay for expanded nav bar
                    if (_navExpanded)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _navBarKey.currentState?._collapse();
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),

                    // Floating pill nav bar
                    Positioned(
                      left: kFloatingNavBarSideMargin,
                      right: kFloatingNavBarSideMargin,
                      bottom: navBarBottom,
                      child: _FloatingNavBar(
                        key: _navBarKey,
                        primaryTabs: primaryTabs,
                        overflowTabs: overflowTabs,
                        currentIndex: safeCurrentIndex,
                        accentColor: accentColor,
                        onTap: onTabTap,
                        onExpandedChanged: (expanded) {
                          setState(() => _navExpanded = expanded);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // PIN lock overlay — sits above everything including the nav bar.
    // Also show an opaque barrier while the initial PIN check is resolving
    // so that app content is never visible before we know the lock state.
    if (_locked) {
      return Stack(
        children: [
          shell,
          Positioned.fill(
            child: PinInputScreen(
              mode: PinInputMode.unlock,
              onSuccess: () => setState(() => _locked = false),
            ),
          ),
        ],
      );
    }

    if (!_pinCheckResolved) {
      return Stack(
        children: [
          shell,
          Positioned.fill(
            child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          ),
        ],
      );
    }

    return shell;
  }

  static void _showPasswordSheetIfNeeded(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final isShowing = ref.read(syncPasswordSheetVisibleProvider);
      if (isShowing) return;
      ref.read(syncPasswordSheetVisibleProvider.notifier).setValue(true);
      SyncPinSheet.show(context).whenComplete(() {
        ref.read(syncPasswordSheetVisibleProvider.notifier).setValue(false);
      });
    });
  }
}

/// Floating pill-shaped navigation bar with "More" overflow support.
///
/// When >5 tabs: shows 5 primary tabs + compact vertical-dots trigger on the
/// trailing edge. Tapping the trigger expands the pill upward to reveal a
/// second row of overflow tabs. Tapping any icon or outside collapses it.
class _FloatingNavBar extends StatefulWidget {
  const _FloatingNavBar({
    super.key,
    required this.primaryTabs,
    required this.overflowTabs,
    required this.currentIndex,
    required this.onTap,
    required this.accentColor,
    this.onExpandedChanged,
  });

  /// Tabs shown directly in the bar.
  final List<AppShellTab> primaryTabs;

  /// Tabs shown in the expanded overflow menu.
  final List<AppShellTab> overflowTabs;
  final int currentIndex;

  /// Called with the index into [primaryTabs] ++ [overflowTabs].
  final ValueChanged<int> onTap;
  final Color accentColor;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<_FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<_FloatingNavBar>
    with TickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  bool _expanded = false;

  // Sliding pill indicator for the selected tab.
  late AnimationController _pillController;
  static final _pillSpring = SpringDescription.withDampingRatio(
    mass: 0.8,
    stiffness: 250.0,
    ratio: 0.68,
  );

  bool get _needsOverflow => widget.overflowTabs.isNotEmpty;

  static const _collapsedRadius = 32.0;
  static const _expandedRadius = 28.0;
  static const _expandedHeight = kFloatingNavBarHeight * 2 + _kNavBarRowGap;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _pillController = AnimationController.unbounded(
      vsync: this,
      value: _primaryTabIndex >= 0 ? _primaryTabIndex.toDouble() : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _FloatingNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idx = _primaryTabIndex;
    if (idx >= 0 && oldWidget.currentIndex != widget.currentIndex) {
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      if (reduceMotion) {
        _pillController.value = idx.toDouble();
      } else {
        final distance = idx.toDouble() - _pillController.value;
        _pillController.animateWith(
          SpringSimulation(
            _pillSpring,
            _pillController.value,
            idx.toDouble(),
            distance * 8,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    _pillController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    Haptics.selection();
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
    widget.onExpandedChanged?.call(_expanded);
  }

  void _collapse() {
    if (_expanded) {
      setState(() => _expanded = false);
      _expandController.reverse();
      widget.onExpandedChanged?.call(false);
    }
  }

  void _handleTap(int visibleIndex) {
    _collapse();
    widget.onTap(visibleIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) => _buildContent(context, ref));
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final showSyncBadge =
        syncStatus.hasQuarantinedItems || syncStatus.lastError != null;
    final habitsBadgeEnabled = ref.watch(habitsBadgeEnabledProvider);
    final dueCount = habitsBadgeEnabled ? ref.watch(dueHabitsCountProvider) : 0;
    final chatUnreadCount = ref.watch(unreadConversationCountProvider);
    final terms = watchTerminology(context, ref);

    final isOled = Theme.of(context).scaffoldBackgroundColor == Colors.black;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_needsOverflow) {
      return _buildSimpleBar(
        showSyncBadge: showSyncBadge,
        dueCount: dueCount,
        chatUnreadCount: chatUnreadCount,
        isDark: isDark,
        terminologyPlural: terms.plural,
      );
    }

    // Overflow mode — single expanding pill
    final overflowSelected = widget.currentIndex >= widget.primaryTabs.length;

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, _) {
        final t = _expandAnimation.value;
        final currentHeight =
            kFloatingNavBarHeight +
            (_expandedHeight - kFloatingNavBarHeight) * t;
        final radius =
            _collapsedRadius + (_expandedRadius - _collapsedRadius) * t;

        return Semantics(
          container: true,
          label: context.l10n.navigationBar,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter.grouped(
              filter: ImageFilter.blur(
                sigmaX: PrismTokens.glassBlurStrong,
                sigmaY: PrismTokens.glassBlurStrong,
              ),
              child: Container(
                height: currentHeight,
                decoration: _barDecoration(isDark, isOled, radius),
                child: Column(
                  children: [
                    // Overflow row (top, revealed by expansion)
                    ClipRect(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: t,
                        child: SizedBox(
                          height: kFloatingNavBarHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                widget.overflowTabs.length,
                                (i) {
                                  final tab = widget.overflowTabs[i];
                                  final isSelected = i == _overflowTabIndex;
                                  // Staggered entrance: each icon delays 40ms
                                  final staggerStart = (i * 0.08).clamp(
                                    0.0,
                                    0.6,
                                  );
                                  final staggerEnd = (staggerStart + 0.5).clamp(
                                    0.0,
                                    1.0,
                                  );
                                  final itemT = Interval(
                                    staggerStart,
                                    staggerEnd,
                                    curve: Curves.easeOut,
                                  ).transform(t);

                                  return Expanded(
                                    child: Opacity(
                                      opacity: itemT,
                                      child: Transform.translate(
                                        offset: Offset(0, (1 - itemT) * 8),
                                        child: _NavBarItem(
                                          tab: tab,
                                          terminologyPlural: terms.plural,
                                          isSelected: isSelected,
                                          accentColor: widget.accentColor,
                                          isDark: isDark,
                                          showSyncBadge: showSyncBadge,
                                          habitsDueCount: dueCount,
                                          chatUnreadCount: chatUnreadCount,
                                          showItemPill: true,
                                          onTap: () => _handleTap(
                                            widget.primaryTabs.length + i,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Subtle separator line between rows
                    if (t > 0)
                      Opacity(
                        opacity: t,
                        child: Container(
                          height: _kNavBarRowGap * t,
                          alignment: Alignment.center,
                          child: Container(
                            height: 0.5,
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            color: isDark
                                ? AppColors.warmWhite.withValues(alpha: 0.08)
                                : AppColors.warmBlack.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                    // Primary row (bottom, fills remaining space)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final availableForTabs =
                                constraints.maxWidth - _kMoreButtonWidth;
                            final segWidth =
                                availableForTabs / widget.primaryTabs.length;
                            final pillColor = isDark
                                ? AppColors.warmWhite.withValues(alpha: 0.15)
                                : AppColors.warmBlack.withValues(alpha: 0.08);

                            final pillWidth = segWidth - 16;
                            return Stack(
                              children: [
                                // Sliding pill (hidden when overflow tab selected)
                                if (_primaryTabIndex >= 0)
                                  AnimatedBuilder(
                                    animation: _pillController,
                                    builder: (context, child) {
                                      return Transform.translate(
                                        offset: Offset(
                                          _pillController.value * segWidth + 8,
                                          0,
                                        ),
                                        child: child,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: pillColor,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: SizedBox(
                                          width: pillWidth,
                                          height: 32,
                                        ),
                                      ),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    // 5 primary tab icons
                                    ...List.generate(
                                      widget.primaryTabs.length,
                                      (i) {
                                        final tab = widget.primaryTabs[i];
                                        final isSelected =
                                            i == _primaryTabIndex;
                                        return Expanded(
                                          child: _NavBarItem(
                                            tab: tab,
                                            isSelected: isSelected,
                                            accentColor: widget.accentColor,
                                            isDark: isDark,
                                            showSyncBadge: showSyncBadge,
                                            habitsDueCount: dueCount,
                                            chatUnreadCount: chatUnreadCount,
                                            onTap: () => _handleTap(i),
                                          ),
                                        );
                                      },
                                    ),
                                    // Compact More/close trigger on trailing edge
                                    _MoreTrigger(
                                      expanded: _expanded || overflowSelected,
                                      animationValue: t,
                                      accentColor: widget.accentColor,
                                      isDark: isDark,
                                      onTap: _toggleExpand,
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int get _primaryTabIndex {
    if (widget.currentIndex >= widget.primaryTabs.length) return -1;
    return widget.currentIndex;
  }

  int get _overflowTabIndex {
    final offset = widget.primaryTabs.length;
    if (widget.currentIndex < offset) return -1;
    return widget.currentIndex - offset;
  }

  BoxDecoration _barDecoration(bool isDark, bool isOled, double radius) {
    return BoxDecoration(
      color: Color.alphaBlend(
        widget.accentColor.withValues(alpha: isDark ? 0.08 : 0.06),
        isDark
            ? (isOled
                  ? AppColors.oledSurface1.withValues(alpha: 0.85)
                  : AppColors.warmWhite.withValues(alpha: 0.08))
            : AppColors.warmWhite.withValues(alpha: 0.7),
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark
            ? AppColors.warmWhite.withValues(alpha: 0.1)
            : AppColors.warmBlack.withValues(alpha: 0.08),
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.warmBlack.withValues(alpha: isDark ? 0.4 : 0.1),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Simple bar for <=5 tabs — no More trigger.
  Widget _buildSimpleBar({
    required bool showSyncBadge,
    required int dueCount,
    required int chatUnreadCount,
    required bool isDark,
    required String terminologyPlural,
  }) {
    final isOled = Theme.of(context).scaffoldBackgroundColor == Colors.black;
    final tabCount = widget.primaryTabs.length;

    // Pill colors
    final pillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.15)
        : AppColors.warmBlack.withValues(alpha: 0.08);

    return Semantics(
      container: true,
      label: context.l10n.navigationBar,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_collapsedRadius),
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
            sigmaX: PrismTokens.glassBlurStrong,
            sigmaY: PrismTokens.glassBlurStrong,
          ),
          child: Container(
            height: kFloatingNavBarHeight,
            decoration: _barDecoration(isDark, isOled, _collapsedRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final segmentWidth = constraints.maxWidth / tabCount;
                  final pillWidth = segmentWidth - 16;
                  return Stack(
                    children: [
                      // Sliding pill — uses Transform.translate (paint-only,
                      // no layout pass) for smooth 60fps on low-end devices.
                      AnimatedBuilder(
                        animation: _pillController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(
                              _pillController.value * segmentWidth + 8,
                              0,
                            ),
                            child: child,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: pillColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SizedBox(width: pillWidth, height: 32),
                          ),
                        ),
                      ),
                      // Tab items
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(tabCount, (index) {
                          final tab = widget.primaryTabs[index];
                          final isSelected = index == widget.currentIndex;
                          return Expanded(
                            child: _NavBarItem(
                              tab: tab,
                              terminologyPlural: terminologyPlural,
                              isSelected: isSelected,
                              accentColor: widget.accentColor,
                              isDark: isDark,
                              showSyncBadge: showSyncBadge,
                              habitsDueCount: dueCount,
                              chatUnreadCount: chatUnreadCount,
                              onTap: () => widget.onTap(index),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact vertical-dots trigger that rotates to an X when expanded.
class _MoreTrigger extends StatelessWidget {
  const _MoreTrigger({
    required this.expanded,
    required this.animationValue,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  final bool expanded;
  final double animationValue;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = expanded
        ? accentColor
        : (isDark
              ? AppColors.warmWhite.withValues(alpha: 0.5)
              : AppColors.warmBlack.withValues(alpha: 0.4));

    return Semantics(
      button: true,
      label: expanded ? context.l10n.closeMenu : context.l10n.moreTabs,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _kMoreButtonWidth,
          height: kFloatingNavBarHeight,
          child: Center(
            child: Transform.rotate(
              angle: animationValue * 0.785, // 45 degrees
              child: Icon(AppIcons.moreVert, size: 22, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual nav bar item.
class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.tab,
    this.terminologyPlural,
    required this.isSelected,
    required this.accentColor,
    required this.isDark,
    required this.showSyncBadge,
    required this.habitsDueCount,
    required this.chatUnreadCount,
    required this.onTap,
    this.showItemPill = false,
  });

  final AppShellTab tab;
  final String? terminologyPlural;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;
  final bool showSyncBadge;
  final int habitsDueCount;
  final int chatUnreadCount;
  final VoidCallback onTap;

  /// When true, render a per-item pill behind the icon (for overflow row).
  final bool showItemPill;

  @override
  Widget build(BuildContext context) {
    final itemIcon = isSelected ? tab.activeIcon : tab.icon;
    final itemLabel = tab.localizedLabel(
      context,
      terminologyPlural: terminologyPlural,
    );

    Widget iconWidget = Icon(
      itemIcon,
      size: 23,
      color: isSelected
          ? accentColor
          : (isDark
                ? AppColors.warmWhite.withValues(alpha: 0.5)
                : AppColors.warmBlack.withValues(alpha: 0.4)),
    );

    iconWidget = _maybeBadge(
      tab: tab,
      showSyncBadge: showSyncBadge,
      habitsDueCount: habitsDueCount,
      chatUnreadCount: chatUnreadCount,
      child: iconWidget,
    );

    final semanticLabel = tab.id == AppShellTabId.chat && chatUnreadCount > 0
        ? context.l10n.navUnreadCount(itemLabel, chatUnreadCount)
        : itemLabel;

    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 32,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: showItemPill && isSelected ? 56 : 40,
                alignment: Alignment.center,
                decoration: showItemPill
                    ? BoxDecoration(
                        color: isSelected
                            ? (isDark
                                  ? AppColors.warmWhite.withValues(alpha: 0.15)
                                  : AppColors.warmBlack.withValues(alpha: 0.08))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      )
                    : null,
                child: iconWidget,
              ),
            ),
            Text(
              itemLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? AppColors.warmWhite : AppColors.warmBlack)
                    : (isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.5)
                          : AppColors.warmBlack.withValues(alpha: 0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desktop sidebar navigation.
class _FloatingSidebar extends ConsumerWidget {
  const _FloatingSidebar({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    required this.accentColor,
  });

  final List<AppShellTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final showSyncBadge =
        syncStatus.hasQuarantinedItems || syncStatus.lastError != null;
    final habitsBadgeEnabled = ref.watch(habitsBadgeEnabledProvider);
    final dueCount = habitsBadgeEnabled ? ref.watch(dueHabitsCountProvider) : 0;
    final chatUnreadCount = ref.watch(unreadConversationCountProvider);
    final terms = watchTerminology(context, ref);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOled = Theme.of(context).scaffoldBackgroundColor == Colors.black;

    return Semantics(
      container: true,
      label: context.l10n.mainNavigation,
      child: SafeArea(
        right: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
            child: Container(
              width: _kSidebarWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accentColor.withValues(alpha: isDark ? 0.04 : 0.03),
                  isDark
                      ? (isOled
                            ? AppColors.oledSurface1.withValues(alpha: 0.50)
                            : AppColors.warmWhite.withValues(alpha: 0.06))
                      : AppColors.warmWhite.withValues(alpha: 0.55),
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? AppColors.warmWhite.withValues(alpha: 0.1)
                      : AppColors.warmBlack.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.warmBlack.withValues(
                      alpha: isDark ? 0.3 : 0.08,
                    ),
                    blurRadius: 12,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: List.generate(tabs.length, (index) {
                    final tab = tabs[index];
                    final isSelected = index == currentIndex;

                    return _SidebarItem(
                      tab: tab,
                      terminologyPlural: terms.plural,
                      isSelected: isSelected,
                      accentColor: accentColor,
                      isDark: isDark,
                      showSyncBadge: showSyncBadge,
                      habitsDueCount: dueCount,
                      chatUnreadCount: chatUnreadCount,
                      onTap: () => onTap(index),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single sidebar navigation item with hover support.
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.tab,
    required this.terminologyPlural,
    required this.isSelected,
    required this.accentColor,
    required this.isDark,
    required this.showSyncBadge,
    required this.habitsDueCount,
    required this.chatUnreadCount,
    required this.onTap,
  });

  final AppShellTab tab;
  final String terminologyPlural;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;
  final bool showSyncBadge;
  final int habitsDueCount;
  final int chatUnreadCount;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final fillColor = widget.isSelected
        ? (widget.isDark
              ? AppColors.warmWhite.withValues(alpha: 0.12)
              : AppColors.warmBlack.withValues(alpha: 0.06))
        : _hovering
        ? (widget.isDark
              ? AppColors.warmWhite.withValues(alpha: 0.06)
              : AppColors.warmBlack.withValues(alpha: 0.03))
        : Colors.transparent;

    final iconColor = widget.isSelected
        ? widget.accentColor
        : (widget.isDark
              ? AppColors.warmWhite.withValues(alpha: 0.5)
              : AppColors.warmBlack.withValues(alpha: 0.4));

    final labelColor = widget.isSelected
        ? (widget.isDark ? AppColors.warmWhite : AppColors.warmBlack)
        : (widget.isDark
              ? AppColors.warmWhite.withValues(alpha: 0.6)
              : AppColors.warmBlack.withValues(alpha: 0.5));

    return Semantics(
      selected: widget.isSelected,
      button: true,
      label: widget.tab.localizedLabel(
        context,
        terminologyPlural: widget.terminologyPlural,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Anim.sm,
            height: _kSidebarItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _maybeBadge(
                  tab: widget.tab,
                  showSyncBadge: widget.showSyncBadge,
                  habitsDueCount: widget.habitsDueCount,
                  chatUnreadCount: widget.chatUnreadCount,
                  child: Icon(
                    widget.isSelected ? widget.tab.activeIcon : widget.tab.icon,
                    size: 20,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.tab.localizedLabel(
                    context,
                    terminologyPlural: widget.terminologyPlural,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: labelColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
