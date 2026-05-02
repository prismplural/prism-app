import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/migration/views/fronting_upgrade_sheet.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/features/settings/widgets/sync_pin_sheet.dart';
import 'package:prism_plurality/features/settings/widgets/sync_toast_listener.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/desktop_breakpoint.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/nav_bar_layout.dart';
import 'package:prism_plurality/shared/utils/pin_lock_decision.dart';
import 'package:prism_plurality/shared/widgets/floating_nav_bar_backdrop.dart';

/// Gap between overflow row and primary row when the nav bar is expanded.
const _kNavBarRowGap = 6.0;

/// Width of the compact More/close trigger on the trailing edge.
const _kMoreButtonWidth = 44.0;

/// Border width used by the floating nav container decoration.
const _kNavBarBorderWidth = 1.0;

/// Extra vertical breathing room around the icon + label stack so scaled text
/// still fits after decoration insets and font metric differences.
const _kNavBarItemVerticalPadding = 12.0;

@visibleForTesting
double floatingNavBarExpandedHeight(
  int overflowRows, {
  double rowHeight = kFloatingNavBarHeight,
  double? overflowRowHeight,
}) {
  final resolvedOverflowRowHeight = overflowRowHeight ?? rowHeight;
  if (overflowRows <= 0) return rowHeight;
  return rowHeight +
      (resolvedOverflowRowHeight * overflowRows) +
      (_kNavBarRowGap * overflowRows);
}

/// Pure decision used by [AppShell] to decide whether to auto-surface
/// the per-member fronting upgrade modal, and whether the modal should
/// be dismissible.
///
/// Defined as a top-level function so the rule lives in one place and
/// can be unit-tested without spinning up the full widget tree.
///
/// Inputs:
/// - [gate]: resolved [FrontingMigrationGateStatus] from
///   [frontingMigrationGateProvider].
/// - [rawMode]: the underlying `pending_fronting_migration_mode`
///   string. Kept for diagnostic context and future mode-specific policy.
///
/// Returns:
/// - `shouldShow == false`: gate is `complete`.
/// - `shouldShow == true, isDismissible == false`: any state where the
///   user must pick a recovery path before runtime new-shape work
///   resumes — `blocked`, `inProgress`, or `needsModal`.
@visibleForTesting
FrontingUpgradeSheetDecision frontingUpgradeSheetDecision({
  required FrontingMigrationGateStatus gate,
  required String? rawMode,
}) {
  switch (gate) {
    case FrontingMigrationGateStatus.complete:
      return const FrontingUpgradeSheetDecision.hidden();
    case FrontingMigrationGateStatus.blocked:
    case FrontingMigrationGateStatus.inProgress:
      // Hard read-only states — modal is the only recovery surface.
      return const FrontingUpgradeSheetDecision.show(isDismissible: false);
    case FrontingMigrationGateStatus.needsModal:
      // First-time prompt, legacy deferred sentinel, or crashed-retry
      // sentinels. Present non-dismissible until the user picks a path.
      return const FrontingUpgradeSheetDecision.show(isDismissible: false);
  }
}

/// Result of [frontingUpgradeSheetDecision].
@immutable
@visibleForTesting
class FrontingUpgradeSheetDecision {
  const FrontingUpgradeSheetDecision.hidden()
    : shouldShow = false,
      isDismissible = false;
  const FrontingUpgradeSheetDecision.show({required this.isDismissible})
    : shouldShow = true;

  final bool shouldShow;
  final bool isDismissible;

  @override
  bool operator ==(Object other) =>
      other is FrontingUpgradeSheetDecision &&
      other.shouldShow == shouldShow &&
      other.isDismissible == isDismissible;

  @override
  int get hashCode => Object.hash(shouldShow, isDismissible);

  @override
  String toString() =>
      'FrontingUpgradeSheetDecision('
      'shouldShow: $shouldShow, isDismissible: $isDismissible)';
}

double _measureNavBarLabelHeight({
  required List<String> labels,
  required double slotWidth,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  if (labels.isEmpty) return 0;

  var maxLabelHeight = 0.0;
  final maxWidth = math.max(0.0, slotWidth);

  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    maxLabelHeight = math.max(maxLabelHeight, painter.height);
  }

  return maxLabelHeight;
}

double _measurePrimaryNavBarRowHeight({
  required List<String> primaryLabels,
  required double barWidth,
  required bool usesOverflowMenu,
  required int primaryCount,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  if (primaryCount <= 0) return kFloatingNavBarHeight;

  final primarySlotWidth = math.max(
    0.0,
    (barWidth - (usesOverflowMenu ? 16.0 + _kMoreButtonWidth : 24.0)) /
        primaryCount,
  );
  final maxPrimaryLabelHeight = _measureNavBarLabelHeight(
    labels: primaryLabels,
    slotWidth: primarySlotWidth,
    labelStyle: labelStyle,
    textScaler: textScaler,
    textDirection: textDirection,
  );

  return math.max(
    kFloatingNavBarHeight,
    kNavBarItemIconHeight +
        maxPrimaryLabelHeight +
        _kNavBarItemVerticalPadding +
        (_kNavBarBorderWidth * 2),
  );
}

double _measureOverflowNavBarRowHeight({
  required List<String> overflowLabels,
  required double barWidth,
  required int overflowColumns,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  if (overflowLabels.isEmpty || overflowColumns <= 0) {
    return kFloatingNavBarHeight;
  }

  final overflowSlotWidth = math.max(0.0, (barWidth - 24.0) / overflowColumns);
  final maxOverflowLabelHeight = _measureNavBarLabelHeight(
    labels: overflowLabels,
    slotWidth: overflowSlotWidth,
    labelStyle: labelStyle,
    textScaler: textScaler,
    textDirection: textDirection,
  );

  return math.max(
    kFloatingNavBarHeight,
    kNavBarItemIconHeight +
        maxOverflowLabelHeight +
        _kNavBarItemVerticalPadding,
  );
}

class AppShellMobileNavLayout {
  const AppShellMobileNavLayout({
    required this.spec,
    required this.primaryTabs,
    required this.overflowTabs,
    required this.rowHeight,
    required this.overflowRowHeight,
  });

  final NavBarLayoutSpec spec;
  final List<AppShellTab> primaryTabs;
  final List<AppShellTab> overflowTabs;
  final double rowHeight;
  final double overflowRowHeight;

  List<AppShellTab> get allTabs => [...primaryTabs, ...overflowTabs];
  double get expandedHeight => floatingNavBarExpandedHeight(
    spec.overflowRows,
    rowHeight: rowHeight,
    overflowRowHeight: overflowRowHeight,
  );
}

/// Cheap signature for [computeAdaptiveMobileNavLayout] inputs. Built from
/// the values that influence label measurement: bar width, the label strings,
/// text scale, text direction, and the label style height (font size +
/// weight). Two signatures that compare equal produce identical layouts, so
/// we can skip the ~20-30 `TextPainter.layout()` calls the function performs.
@immutable
class _NavLayoutSignature {
  const _NavLayoutSignature({
    required this.barWidth,
    required this.primaryLabels,
    required this.overflowLabels,
    required this.textScaleFactor,
    required this.textDirection,
    required this.fontSize,
    required this.fontWeight,
  });

  final double barWidth;
  final List<String> primaryLabels;
  final List<String> overflowLabels;
  final double textScaleFactor;
  final TextDirection textDirection;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _NavLayoutSignature &&
        other.barWidth == barWidth &&
        other.textScaleFactor == textScaleFactor &&
        other.textDirection == textDirection &&
        other.fontSize == fontSize &&
        other.fontWeight == fontWeight &&
        _listEquals(other.primaryLabels, primaryLabels) &&
        _listEquals(other.overflowLabels, overflowLabels);
  }

  @override
  int get hashCode => Object.hash(
    barWidth,
    textScaleFactor,
    textDirection,
    fontSize,
    fontWeight,
    Object.hashAll(primaryLabels),
    Object.hashAll(overflowLabels),
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Counter incremented inside [computeAdaptiveMobileNavLayout] for every
/// call that does not hit the memoization cache. Tests read this to assert
/// that repeated rebuilds with identical inputs reuse the cached layout.
@visibleForTesting
int debugAdaptiveMobileNavLayoutComputeCount = 0;

AppShellMobileNavLayout computeAdaptiveMobileNavLayout({
  required double barWidth,
  required List<AppShellTab> primaryTabs,
  required List<AppShellTab> overflowTabs,
  required List<String> primaryLabels,
  required List<String> overflowLabels,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  assert(primaryTabs.length == primaryLabels.length);
  assert(overflowTabs.length == overflowLabels.length);

  debugAdaptiveMobileNavLayoutComputeCount++;

  final spec = computeNavBarLayoutSpec(
    barWidth: barWidth,
    primaryLabels: primaryLabels,
    overflowLabels: overflowLabels,
    labelStyle: labelStyle,
    textScaler: textScaler,
    textDirection: textDirection,
  );
  final split = splitNavBarTabsForLayout(
    primary: primaryTabs,
    overflow: overflowTabs,
    spec: spec,
  );
  final visualPrimaryLabels = primaryLabels
      .take(spec.collapsedPrimaryCount)
      .toList();
  final visualOverflowLabels = [
    ...primaryLabels.skip(spec.collapsedPrimaryCount),
    ...overflowLabels,
  ];
  final rowHeight = _measurePrimaryNavBarRowHeight(
    primaryLabels: visualPrimaryLabels,
    barWidth: barWidth,
    usesOverflowMenu: spec.usesOverflowMenu,
    primaryCount: split.primary.length,
    labelStyle: labelStyle,
    textScaler: textScaler,
    textDirection: textDirection,
  );
  final overflowRowHeight = _measureOverflowNavBarRowHeight(
    overflowLabels: visualOverflowLabels,
    barWidth: barWidth,
    overflowColumns: spec.overflowColumns,
    labelStyle: labelStyle,
    textScaler: textScaler,
    textDirection: textDirection,
  );

  return AppShellMobileNavLayout(
    spec: spec,
    primaryTabs: split.primary,
    overflowTabs: split.overflow,
    rowHeight: rowHeight,
    overflowRowHeight: overflowRowHeight,
  );
}

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
  required int boardsBadge,
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
  if (tab.id == AppShellTabId.boards && boardsBadge > 0) {
    return Badge(
      label: Text(boardsBadge > 99 ? '99+' : '$boardsBadge'),
      child: child,
    );
  }
  return child;
}

/// True when the two members have identical values for every field that
/// PluralKit's member API cares about. Changes to purely-local fields
/// (emoji, avatar bytes, isAdmin, etc.) don't trigger a PK push.
bool _pkSyncRelevantFieldsEqual(Member a, Member b) {
  return a.name == b.name &&
      a.displayName == b.displayName &&
      a.pronouns == b.pronouns &&
      a.bio == b.bio &&
      a.birthday == b.birthday &&
      a.customColorEnabled == b.customColorEnabled &&
      a.customColorHex == b.customColorHex;
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
  int _lockGeneration = 0;

  /// Whether the initial PIN check has completed. While false, the app shows
  /// a loading/locked state to prevent content from being visible before we
  /// know whether PIN lock is enabled.
  bool _pinCheckResolved = false;
  bool _navExpanded = false;
  final _navBarKey = GlobalKey<_FloatingNavBarState>();
  DateTime? _backgroundedAt;

  // Memoized mobile nav layout. Cached across rebuilds triggered by unrelated
  // providers (sync health, badge counts, theme) so we don't re-run the ~20-30
  // `TextPainter.layout()` calls in `computeAdaptiveMobileNavLayout` every
  // frame. Invalidated automatically when the signature changes (label set,
  // text scale, locale, bar width).
  _NavLayoutSignature? _cachedNavLayoutSignature;
  AppShellMobileNavLayout? _cachedNavLayout;

  AppShellMobileNavLayout _memoizedMobileNavLayout({
    required double barWidth,
    required List<AppShellTab> primaryTabs,
    required List<AppShellTab> overflowTabs,
    required List<String> primaryLabels,
    required List<String> overflowLabels,
    required TextStyle labelStyle,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    final signature = _NavLayoutSignature(
      barWidth: barWidth,
      primaryLabels: primaryLabels,
      overflowLabels: overflowLabels,
      textScaleFactor: textScaler.scale(1),
      textDirection: textDirection,
      fontSize: labelStyle.fontSize ?? 12.0,
      fontWeight: labelStyle.fontWeight ?? FontWeight.w500,
    );
    final cached = _cachedNavLayout;
    if (cached != null && _cachedNavLayoutSignature == signature) {
      return cached;
    }
    final layout = computeAdaptiveMobileNavLayout(
      barWidth: barWidth,
      primaryTabs: primaryTabs,
      overflowTabs: overflowTabs,
      primaryLabels: primaryLabels,
      overflowLabels: overflowLabels,
      labelStyle: labelStyle,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    _cachedNavLayoutSignature = signature;
    _cachedNavLayout = layout;
    return layout;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Attempt an immediate check; if providers are still loading,
    // listeners set up in build() will resolve it when they emit data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialLock();
      // Kick the PK auto-poll into "foregrounded" state on first build.
      ref.read(pkAutoPollProvider.notifier).markForegrounded(true);
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
    if (decision.locked) {
      _startHardSyncLockIfEnabled(++_lockGeneration);
    }
  }

  void _lockApp() {
    if (_locked) return;
    final generation = ++_lockGeneration;
    setState(() => _locked = true);
    _startHardSyncLockIfEnabled(generation);
  }

  void _unlockApp() {
    ++_lockGeneration;
    setState(() => _locked = false);
  }

  void _startHardSyncLockIfEnabled(int generation) {
    unawaited(_hardLockSyncIfEnabled(generation));
  }

  Future<void> _hardLockSyncIfEnabled(int generation) async {
    try {
      final enabled = await ref.read(hardLockSyncOnAppLockProvider.future);
      if (!mounted || !enabled || !_locked || generation != _lockGeneration) {
        return;
      }
      await ref.read(syncHealthProvider.notifier).lock(hard: true);
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'prism_plurality',
          context: ErrorDescription('hard locking sync on app lock'),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      ref.read(pkAutoPollProvider.notifier).markForegrounded(false);
    } else if (state == AppLifecycleState.resumed) {
      _checkLockOnResume();
      ref.invalidate(currentDateProvider);
      ref.read(pkAutoPollProvider.notifier).markForegrounded(true);
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
      _lockApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = shouldBeDesktop(width, currentlyDesktop: _wasDesktop);
    _wasDesktop = isDesktop;

    // Providers resolve the configured nav layout. On mobile we may render a
    // smaller primary set at runtime when the current width/text scale cannot
    // fit all configured labels without clipping.
    final configuredPrimaryTabs = ref.watch(activeNavBarTabsProvider);
    final configuredOverflowTabs = ref.watch(navBarOverflowTabsProvider);
    final configuredTabs = [
      ...configuredPrimaryTabs,
      ...configuredOverflowTabs,
    ];

    // Retry the initial PIN check when providers resolve (handles cold start
    // where providers were still loading during _checkInitialLock).
    if (!_pinCheckResolved) {
      ref.listen(systemSettingsProvider, (_, _) => _checkInitialLock());
      ref.listen(isPinSetProvider, (_, _) => _checkInitialLock());
    }

    // Keep syncStatusProvider alive so DeviceRevoked events are received.
    ref.watch(syncStatusProvider);

    // Keep the local privacy preference loaded for app-lock decisions.
    ref.watch(hardLockSyncOnAppLockProvider);

    // Keep the PK auto-poll notifier alive for its timer lifecycle.
    ref.watch(pkAutoPollProvider);

    // Push any pending fronting sessions to PluralKit whenever the active
    // session changes (start / end / switch fronter). Fire-and-forget —
    // the notifier no-ops when PK isn't connected or mapping is incomplete.
    ref.listen(activeSessionProvider, (_, _) {
      ref.read(pluralKitSyncProvider.notifier).pushPendingSwitches();
      // Prevent the next auto-poll tick from re-ingesting the switch we
      // just authored locally.
      ref.read(pkAutoPollProvider.notifier).noteLocalPush();
    });

    // Push edits to linked PK members when their sync-relevant fields change.
    // Fire-and-forget; the notifier no-ops when PK isn't connected, direction
    // is pull-only, or the member isn't linked.
    ref.listen(allMembersProvider, (prev, next) {
      final prevList = prev?.value;
      final nextList = next.value;
      if (prevList == null || nextList == null) return;
      final prevById = {for (final m in prevList) m.id: m};
      final pkSync = ref.read(pluralKitSyncProvider.notifier);
      for (final m in nextList) {
        if (m.pluralkitId == null || m.pluralkitId!.isEmpty) continue;
        final before = prevById[m.id];
        if (before == null) continue; // newly inserted — handled by imports
        if (_pkSyncRelevantFieldsEqual(before, m)) continue;
        pkSync.pushMemberUpdate(m);
      }
    });

    // Show password sheet when sync needs the user's password — but not
    // while the PIN lock overlay is up (or still resolving), otherwise the
    // root modal sheet renders above the lock screen.
    ref.listen<SyncHealthState>(syncHealthProvider, (prev, next) {
      if (next == SyncHealthState.needsPassword &&
          prev != SyncHealthState.needsPassword &&
          !_locked &&
          _pinCheckResolved) {
        _showPasswordSheetIfNeeded(context, ref);
      }
    });
    if (!_locked &&
        _pinCheckResolved &&
        ref.read(syncHealthProvider) == SyncHealthState.needsPassword) {
      _showPasswordSheetIfNeeded(context, ref);
    }

    // Show the per-member fronting upgrade modal post-unlock.  Mirrors
    // the password-sheet trigger above: only fires once the PIN check
    // has resolved and the lock overlay is down, so the modal renders
    // over the home tabs (not over the lock).
    //
    // We watch the resolved [frontingMigrationGateProvider] rather than
    // the raw mode string so the policy lives at the gate provider and
    // every consumer (PK push/poll, sync apply, this listener) agrees
    // on what blocks runtime new-shape work. See WS1 step 4 + 5 in the
    // remediation plan.
    //
    // Behavior per status:
    // - [FrontingMigrationGateStatus.complete]: hidden.
    // - [FrontingMigrationGateStatus.needsModal]: present non-dismissible.
    // - [FrontingMigrationGateStatus.inProgress]: present non-dismissible.
    //   The modal opens straight to a "Finish migration" screen that
    //   calls `resumeCleanup()` (the Drift transaction committed but a
    //   post-tx step failed).
    // - [FrontingMigrationGateStatus.blocked]: present non-dismissible.
    //   v7 onUpgrade refused the composite index because of duplicates;
    //   the modal is the user's only recovery path.
    ref.listen<FrontingMigrationGateStatus>(frontingMigrationGateProvider, (
      prev,
      next,
    ) {
      if (!_pinCheckResolved || _locked) return;
      final mode = ref.read(frontingMigrationModeProvider).value;
      _showFrontingUpgradeSheetIfNeeded(context, ref, next, mode);
    });
    if (!_locked && _pinCheckResolved) {
      final gate = ref.read(frontingMigrationGateProvider);
      final mode = ref.read(frontingMigrationModeProvider).value;
      _showFrontingUpgradeSheetIfNeeded(context, ref, gate, mode);
    }

    void onTabSelected(AppShellTab tab, {required bool useHaptics}) {
      if (useHaptics) Haptics.selection();
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
      final currentVisibleIndex = configuredTabs.indexWhere(
        (t) => t.branchIndex == widget.navigationShell.currentIndex,
      );
      final safeCurrentIndex = currentVisibleIndex < 0
          ? 0
          : currentVisibleIndex;

      // Desktop layout: sidebar + content side by side.
      shell = NavBarInset(
        bottomInset: 0,
        child: SyncToastListener(
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Row(
              children: [
                _FloatingSidebar(
                  tabs: configuredTabs,
                  currentIndex: safeCurrentIndex,
                  accentColor: accentColor,
                  onTap: (index) =>
                      onTabSelected(configuredTabs[index], useHaptics: false),
                ),
                Expanded(child: widget.navigationShell),
              ],
            ),
          ),
        ),
      );
    } else {
      final terms = watchTerminology(context, ref);
      final primaryLabels = configuredPrimaryTabs
          .map(
            (tab) =>
                tab.localizedLabel(context, terminologyPlural: terms.plural),
          )
          .toList();
      final overflowLabels = configuredOverflowTabs
          .map(
            (tab) =>
                tab.localizedLabel(context, terminologyPlural: terms.plural),
          )
          .toList();
      final navBarWidth = math.max(
        0.0,
        width - (kFloatingNavBarSideMargin * 2),
      );
      final mobileLayout = _memoizedMobileNavLayout(
        barWidth: navBarWidth,
        primaryTabs: configuredPrimaryTabs,
        overflowTabs: configuredOverflowTabs,
        primaryLabels: primaryLabels,
        overflowLabels: overflowLabels,
        labelStyle: navBarLabelTextStyle(context, isSelected: true),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      );
      final currentVisibleIndex = mobileLayout.allTabs.indexWhere(
        (t) => t.branchIndex == widget.navigationShell.currentIndex,
      );
      final safeCurrentIndex = currentVisibleIndex < 0
          ? 0
          : currentVisibleIndex;

      // Mobile layout: stack with floating bottom bar.
      // Hide the nav bar on sub-routes (detail screens) — only show on root tabs.
      final location = GoRouterState.of(context).uri.path;
      final isRootTab = appShellTabs.any((t) => t.rootLocation == location);

      final mediaQuery = MediaQuery.of(context);
      final bottomSafeArea = mediaQuery.viewPadding.bottom;
      final keyboardOpen = mediaQuery.viewInsets.bottom > 0;
      final hideNavBar = keyboardOpen || !isRootTab;
      if (hideNavBar && _navExpanded) {
        // Bar is gone — discard any stale expanded state so the overlay
        // doesn't re-appear when the bar returns.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_navExpanded) setState(() => _navExpanded = false);
        });
      }
      final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

      // On iOS the full safe area (~34pt) pushes the floating pill too high.
      // Use a fixed 21pt bottom to sit comfortably above the home indicator.
      final isApple =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
      final navBarBottom = isApple && bottomSafeArea > 0
          ? 21.0
          : kFloatingNavBarBottomMargin + bottomSafeArea;
      final totalInset = mobileLayout.rowHeight + navBarBottom + 8;

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
                            // Safety: the child may have already rebuilt with
                            // fresh state (bar was hidden and re-shown) so
                            // `_collapse()` can no-op. Reset parent state
                            // unconditionally to avoid a stuck invisible
                            // overlay blocking the screen.
                            if (_navExpanded) {
                              setState(() => _navExpanded = false);
                            }
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
                        primaryTabs: mobileLayout.primaryTabs,
                        overflowTabs: mobileLayout.overflowTabs,
                        overflowColumns: mobileLayout.spec.overflowColumns,
                        overflowRows: mobileLayout.spec.overflowRows,
                        rowHeight: mobileLayout.rowHeight,
                        overflowRowHeight: mobileLayout.overflowRowHeight,
                        currentIndex: safeCurrentIndex,
                        accentColor: accentColor,
                        onTap: (index) => onTabSelected(
                          mobileLayout.allTabs[index],
                          useHaptics: true,
                        ),
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
              onSuccess: _unlockApp,
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

  /// Tracks whether the upgrade modal is already showing so listener
  /// re-fires (each settings stream emit) don't stack duplicate
  /// sheets. Reset in `whenComplete` so a failed/retried modal can re-open.
  bool _frontingUpgradeSheetShowing = false;

  void _showFrontingUpgradeSheetIfNeeded(
    BuildContext context,
    WidgetRef ref,
    FrontingMigrationGateStatus gate,
    String? rawMode,
  ) {
    final decision = frontingUpgradeSheetDecision(gate: gate, rawMode: rawMode);
    if (!decision.shouldShow) return;
    if (_frontingUpgradeSheetShowing) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (_frontingUpgradeSheetShowing) return;
      _frontingUpgradeSheetShowing = true;
      showFrontingUpgradeSheet(
        context,
        isDismissible: decision.isDismissible,
      ).whenComplete(() {
        _frontingUpgradeSheetShowing = false;
      });
    });
  }
}

/// Floating pill-shaped navigation bar with "More" overflow support.
///
/// On mobile this can render fewer than the configured primary tabs when
/// larger labels or text scaling would otherwise clip. Tapping the More
/// trigger expands the pill upward to reveal the rendered overflow rows.
class _FloatingNavBar extends StatefulWidget {
  _FloatingNavBar({
    super.key,
    required this.primaryTabs,
    required this.overflowTabs,
    required this.overflowColumns,
    required this.overflowRows,
    required this.rowHeight,
    required this.overflowRowHeight,
    required this.currentIndex,
    required this.onTap,
    required this.accentColor,
    this.onExpandedChanged,
  }) : assert(
         overflowTabs.isEmpty
             ? overflowColumns == 0 && overflowRows == 0
             : overflowColumns > 0 && overflowRows > 0,
       );

  /// Tabs shown directly in the bar.
  final List<AppShellTab> primaryTabs;

  /// Tabs shown in the expanded overflow menu.
  final List<AppShellTab> overflowTabs;
  final int overflowColumns;
  final int overflowRows;
  final double rowHeight;
  final double overflowRowHeight;
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
  double get _overflowAreaHeight {
    if (!_needsOverflow) return 0;
    return widget.overflowRowHeight * widget.overflowRows +
        _kNavBarRowGap * (widget.overflowRows - 1);
  }

  /// Overflow tabs arranged into visual rows with the partial row on top.
  /// Each slot carries the tab's original index for tap/selection mapping;
  /// `null` slots render as empty space.
  List<List<({int index, AppShellTab tab})?>> get _overflowRowSlots {
    final indexed = [
      for (var i = 0; i < widget.overflowTabs.length; i++)
        (index: i, tab: widget.overflowTabs[i]),
    ];
    return arrangeOverflowRows(indexed, widget.overflowColumns);
  }

  double get _expandedHeight => floatingNavBarExpandedHeight(
    widget.overflowRows,
    rowHeight: widget.rowHeight,
    overflowRowHeight: widget.overflowRowHeight,
  );

  static const _collapsedRadius = 32.0;
  static const _expandedRadius = 28.0;

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
    final primaryChanged = !_sameBranchIndices(
      widget.primaryTabs,
      oldWidget.primaryTabs,
    );
    // If the set of primary tabs changed (tab moved in/out of overflow), the
    // pill's spring target can be stale — snap it to the current index.
    if (primaryChanged) {
      _pillController.stop();
      _pillController.value = idx >= 0 ? idx.toDouble() : 0;
      return;
    }
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

  static bool _sameBranchIndices(List<AppShellTab> a, List<AppShellTab> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].branchIndex != b[i].branchIndex) return false;
    }
    return true;
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
    final boardsBadge = ref.watch(boardsTabBadgeProvider);
    final terms = watchTerminology(context, ref);

    final isOled = Theme.of(context).scaffoldBackgroundColor == Colors.black;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_needsOverflow) {
      return _buildSimpleBar(
        showSyncBadge: showSyncBadge,
        dueCount: dueCount,
        chatUnreadCount: chatUnreadCount,
        boardsBadge: boardsBadge,
        isDark: isDark,
        terminologyPlural: terms.plural,
      );
    }

    // Overflow mode — expanding pill with adaptive overflow rows.
    final overflowSelected = widget.currentIndex >= widget.primaryTabs.length;

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, _) {
        final t = _expandAnimation.value;
        final currentHeight =
            widget.rowHeight + (_expandedHeight - widget.rowHeight) * t;
        final radius =
            _collapsedRadius + (_expandedRadius - _collapsedRadius) * t;

        final shapes = PrismShapes.of(context);
        return Semantics(
          container: true,
          label: context.l10n.navigationBar,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(shapes.radius(radius)),
            child: BackdropFilter.grouped(
              filter: ImageFilter.blur(
                sigmaX: PrismTokens.glassBlurStrong,
                sigmaY: PrismTokens.glassBlurStrong,
              ),
              child: Container(
                height: currentHeight,
                decoration: _barDecoration(isDark, isOled, radius, shapes),
                child: Column(
                  children: [
                    // Overflow rows (top, revealed by expansion). The partial
                    // row sits on top so the full row is adjacent to the
                    // primary row — more ergonomic than a gap-on-bottom layout.
                    ClipRect(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: t,
                        child: SizedBox(
                          height: _overflowAreaHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              children: [
                                for (
                                  var r = 0;
                                  r < _overflowRowSlots.length;
                                  r++
                                ) ...[
                                  if (r > 0)
                                    const SizedBox(height: _kNavBarRowGap),
                                  SizedBox(
                                    height: widget.overflowRowHeight,
                                    child: _buildOverflowRow(
                                      slots: _overflowRowSlots[r],
                                      expandProgress: t,
                                      terminologyPlural: terms.plural,
                                      isDark: isDark,
                                      showSyncBadge: showSyncBadge,
                                      dueCount: dueCount,
                                      chatUnreadCount: chatUnreadCount,
                                      boardsBadge: boardsBadge,
                                    ),
                                  ),
                                ],
                              ],
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
                                      final isRtl =
                                          Directionality.of(context) ==
                                          TextDirection.rtl;
                                      final slot = isRtl
                                          ? (widget.primaryTabs.length -
                                                1 -
                                                _pillController.value)
                                          : _pillController.value;
                                      return Transform.translate(
                                        offset: Offset(slot * segWidth + 8, 0),
                                        child: child,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: pillColor,
                                          borderRadius: BorderRadius.circular(
                                            PrismShapes.of(context).radius(16),
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
                                            terminologyPlural: terms.plural,
                                            isSelected: isSelected,
                                            accentColor: widget.accentColor,
                                            isDark: isDark,
                                            showSyncBadge: showSyncBadge,
                                            habitsDueCount: dueCount,
                                            chatUnreadCount: chatUnreadCount,
                                            boardsBadge: boardsBadge,
                                            rowHeight: widget.rowHeight,
                                            onTap: () => _handleTap(i),
                                          ),
                                        );
                                      },
                                    ),
                                    // Compact More/close trigger on trailing edge
                                    _MoreTrigger(
                                      isExpanded: _expanded,
                                      isHighlighted:
                                          _expanded || overflowSelected,
                                      animationValue: t,
                                      accentColor: widget.accentColor,
                                      isDark: isDark,
                                      rowHeight: widget.rowHeight,
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

  Widget _buildOverflowSlot({
    required ({int index, AppShellTab tab})? slot,
    required double expandProgress,
    required String terminologyPlural,
    required bool isDark,
    required bool showSyncBadge,
    required int dueCount,
    required int chatUnreadCount,
  required int boardsBadge,
  }) {
    if (slot == null) return const SizedBox.shrink();
    // Stagger on the original tab index so icons animate in reading order
    // regardless of how the grid aligns partial rows.
    final staggerStart = (slot.index * 0.08).clamp(0.0, 0.6);
    final staggerEnd = (staggerStart + 0.5).clamp(0.0, 1.0);
    final itemT = Interval(
      staggerStart,
      staggerEnd,
      curve: Curves.easeOut,
    ).transform(expandProgress);
    final isSelected = slot.index == _overflowTabIndex;

    return Opacity(
      opacity: itemT,
      child: Transform.translate(
        offset: Offset(0, (1 - itemT) * 8),
        child: _NavBarItem(
          tab: slot.tab,
          terminologyPlural: terminologyPlural,
          isSelected: isSelected,
          accentColor: widget.accentColor,
          isDark: isDark,
          showSyncBadge: showSyncBadge,
          habitsDueCount: dueCount,
          chatUnreadCount: chatUnreadCount,
          boardsBadge: boardsBadge,
          rowHeight: widget.rowHeight,
          showItemPill: true,
          onTap: () => _handleTap(widget.primaryTabs.length + slot.index),
        ),
      ),
    );
  }

  Widget _buildOverflowRow({
    required List<({int index, AppShellTab tab})?> slots,
    required double expandProgress,
    required String terminologyPlural,
    required bool isDark,
    required bool showSyncBadge,
    required int dueCount,
    required int chatUnreadCount,
  required int boardsBadge,
  }) {
    final populatedSlots = slots
        .whereType<({int index, AppShellTab tab})>()
        .toList();
    if (populatedSlots.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotColumns = widget.overflowRows > 1
            ? widget.overflowColumns
            : populatedSlots.length;
        final slotWidth = slotColumns <= 0
            ? 0.0
            : constraints.maxWidth / slotColumns;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final slot in populatedSlots)
              SizedBox(
                width: slotWidth,
                child: _buildOverflowSlot(
                  slot: slot,
                  expandProgress: expandProgress,
                  terminologyPlural: terminologyPlural,
                  isDark: isDark,
                  showSyncBadge: showSyncBadge,
                  dueCount: dueCount,
                  chatUnreadCount: chatUnreadCount,
                  boardsBadge: boardsBadge,
                ),
              ),
          ],
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

  BoxDecoration _barDecoration(
    bool isDark,
    bool isOled,
    double radius,
    PrismShapes shapes,
  ) {
    return BoxDecoration(
      color: Color.alphaBlend(
        widget.accentColor.withValues(alpha: isDark ? 0.08 : 0.06),
        isDark
            ? (isOled
                  ? AppColors.oledSurface1.withValues(alpha: 0.85)
                  : AppColors.warmWhite.withValues(alpha: 0.08))
            : AppColors.warmWhite.withValues(alpha: 0.7),
      ),
      borderRadius: BorderRadius.circular(shapes.radius(radius)),
      border: Border.all(
        width: _kNavBarBorderWidth,
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
  required int boardsBadge,
    required bool isDark,
    required String terminologyPlural,
  }) {
    final isOled = Theme.of(context).scaffoldBackgroundColor == Colors.black;
    final tabCount = widget.primaryTabs.length;
    final shapes = PrismShapes.of(context);

    // Pill colors
    final pillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.15)
        : AppColors.warmBlack.withValues(alpha: 0.08);

    return Semantics(
      container: true,
      label: context.l10n.navigationBar,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(shapes.radius(_collapsedRadius)),
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
            sigmaX: PrismTokens.glassBlurStrong,
            sigmaY: PrismTokens.glassBlurStrong,
          ),
          child: Container(
            height: widget.rowHeight,
            decoration: _barDecoration(
              isDark,
              isOled,
              _collapsedRadius,
              shapes,
            ),
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
                          final isRtl =
                              Directionality.of(context) == TextDirection.rtl;
                          final slot = isRtl
                              ? (tabCount - 1 - _pillController.value)
                              : _pillController.value;
                          return Transform.translate(
                            offset: Offset(slot * segmentWidth + 8, 0),
                            child: child,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: pillColor,
                              borderRadius: BorderRadius.circular(
                                shapes.radius(16),
                              ),
                            ),
                            child: SizedBox(width: pillWidth, height: 32),
                          ),
                        ),
                      ),
                      // Tab items — force the row to fill the nav bar
                      // height so each item's content vertically centers the
                      // same way it does in overflow mode (where the tall
                      // _MoreTrigger sibling forces the row to full height).
                      SizedBox(
                        height: widget.rowHeight,
                        child: Row(
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
                                boardsBadge: boardsBadge,
                                rowHeight: widget.rowHeight,
                                onTap: () => widget.onTap(index),
                              ),
                            );
                          }),
                        ),
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
    required this.isExpanded,
    required this.isHighlighted,
    required this.animationValue,
    required this.accentColor,
    required this.isDark,
    required this.rowHeight,
    required this.onTap,
  });

  final bool isExpanded;
  final bool isHighlighted;
  final double animationValue;
  final Color accentColor;
  final bool isDark;
  final double rowHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = isHighlighted
        ? accentColor
        : (isDark
              ? AppColors.warmWhite.withValues(alpha: 0.5)
              : AppColors.warmBlack.withValues(alpha: 0.4));

    return Semantics(
      button: true,
      expanded: isExpanded,
      label: isExpanded ? context.l10n.closeMenu : context.l10n.moreTabs,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _kMoreButtonWidth,
          height: rowHeight,
          child: Center(
            child: Transform.rotate(
              angle: animationValue * 0.785, // 45 degrees
              child: Icon(
                AppIcons.moreVert,
                size: kNavBarMoreTriggerIconSize,
                color: iconColor,
              ),
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
    required this.terminologyPlural,
    required this.isSelected,
    required this.accentColor,
    required this.isDark,
    required this.showSyncBadge,
    required this.habitsDueCount,
    required this.chatUnreadCount,
    required this.boardsBadge,
    required this.rowHeight,
    required this.onTap,
    this.showItemPill = false,
  });

  final AppShellTab tab;
  final String terminologyPlural;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;
  final bool showSyncBadge;
  final int habitsDueCount;
  final int chatUnreadCount;
  final int boardsBadge;
  final double rowHeight;
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
      size: kNavBarItemIconSize,
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
      boardsBadge: boardsBadge,
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
              height: kNavBarItemIconHeight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: showItemPill && isSelected
                    ? kNavBarSelectedItemPillWidth
                    : kNavBarItemWidth,
                alignment: Alignment.center,
                decoration: showItemPill
                    ? BoxDecoration(
                        color: isSelected
                            ? (isDark
                                  ? AppColors.warmWhite.withValues(alpha: 0.15)
                                  : AppColors.warmBlack.withValues(alpha: 0.08))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          PrismShapes.of(context).radius(16),
                        ),
                      )
                    : null,
                child: iconWidget,
              ),
            ),
            Text(
              itemLabel,
              style: navBarLabelTextStyle(
                context,
                isSelected: isSelected,
                color: isSelected
                    ? (isDark ? AppColors.warmWhite : AppColors.warmBlack)
                    : (isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.5)
                          : AppColors.warmBlack.withValues(alpha: 0.4)),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
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
    final boardsBadge = ref.watch(boardsTabBadgeProvider);
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
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(16),
                ),
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
                      boardsBadge: boardsBadge,
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
    required this.boardsBadge,
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
  final int boardsBadge;
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
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(10),
              ),
            ),
            child: Row(
              children: [
                _maybeBadge(
                  tab: widget.tab,
                  showSyncBadge: widget.showSyncBadge,
                  habitsDueCount: widget.habitsDueCount,
                  chatUnreadCount: widget.chatUnreadCount,
                  boardsBadge: widget.boardsBadge,
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
