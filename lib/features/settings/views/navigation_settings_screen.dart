import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/nav_bar_layout.dart'
    show
        arrangeOverflowRows,
        kNavBarItemIconHeight,
        kNavBarItemIconSize,
        kNavBarItemWidth,
        kNavBarMoreTriggerIconSize,
        navBarLabelTextStyle;
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

const _kPreviewRowGap = 6.0;
const _kPreviewMoreButtonWidth = 44.0;

@visibleForTesting
AppShellMobileNavLayout computeAdaptiveNavLayoutForCurrentDevice(
  BuildContext context, {
  required List<AppShellTab> primary,
  required List<AppShellTab> overflow,
  required String terminologyPlural,
}) {
  return computeAdaptiveMobileNavLayout(
    barWidth:
        (MediaQuery.sizeOf(context).width - (kFloatingNavBarSideMargin * 2))
            .clamp(0.0, double.infinity)
            .toDouble(),
    primaryTabs: primary,
    overflowTabs: overflow,
    primaryLabels: [
      for (final tab in primary)
        tab.localizedLabel(context, terminologyPlural: terminologyPlural),
    ],
    overflowLabels: [
      for (final tab in overflow)
        tab.localizedLabel(context, terminologyPlural: terminologyPlural),
    ],
    labelStyle: navBarLabelTextStyle(context, isSelected: true),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  );
}

class NavigationSettingsScreen extends ConsumerWidget {
  const NavigationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryTabs = ref.watch(activeNavBarTabsProvider);
    final overflowTabs = ref.watch(navBarOverflowTabsProvider);
    final flags = ref.watch(featureFlagsProvider);
    final syncNavigationEnabled = ref.watch(syncNavigationEnabledProvider);
    final terms = watchTerminology(context, ref);

    // All tab IDs currently placed (primary + overflow)
    final placedIds = {
      ...primaryTabs.map((t) => t.id),
      ...overflowTabs.map((t) => t.id),
    };

    // Enabled tabs not placed anywhere
    final availableTabs = [
      for (final tab in appShellTabs)
        if (!placedIds.contains(tab.id) && tab.isEnabled(flags)) tab,
    ];

    // Disabled tabs (feature is off)
    final disabledTabs = [
      for (final tab in appShellTabs)
        if (!tab.isLocked && !tab.isEnabled(flags)) tab,
    ];

    bool canAddToPrimary(AppShellTab tab) {
      if (primaryTabs.length >= kMaxPrimaryNavTabs) {
        return false;
      }

      return _rendersInPrimaryOnCurrentDevice(
        context,
        primary: [...primaryTabs, tab],
        overflow: overflowTabs,
        candidate: tab,
        terminologyPlural: terms.plural,
      );
    }

    bool canMoveToPrimary(AppShellTab tab) {
      if (primaryTabs.length >= kMaxPrimaryNavTabs) {
        return false;
      }

      return _rendersInPrimaryOnCurrentDevice(
        context,
        primary: [...primaryTabs, tab],
        overflow: [
          for (final overflowTab in overflowTabs)
            if (overflowTab.id != tab.id) overflowTab,
        ],
        candidate: tab,
        terminologyPlural: terms.plural,
      );
    }

    // Build the unified flat list: primary header + primary items + overflow header + overflow items
    final List<_UnifiedEntry> entries = [
      _UnifiedEntry.header(context.l10n.navigationNavBar),
      for (final tab in primaryTabs) _UnifiedEntry.item(tab),
      _UnifiedEntry.header(context.l10n.navigationMoreMenu),
      for (final tab in overflowTabs) _UnifiedEntry.item(tab),
    ];

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.navigationSettingsTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
        children: [
          // Preferences — grouped switches (sync layout, home view toggle).
          PrismSection(
            title: context.l10n.navigationPreferences,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  PrismSwitchRow(
                    title: context.l10n.syncNavigationLayoutTitle,
                    subtitle: context.l10n.syncNavigationLayoutSubtitle,
                    value: syncNavigationEnabled,
                    onChanged: (v) => ref
                        .read(settingsNotifierProvider.notifier)
                        .updateSyncNavigationEnabled(v),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                  PrismSwitchRow(
                    title: context.l10n.navigationShowViewToggleTitle,
                    subtitle: context.l10n.navigationShowViewToggleSubtitle,
                    value:
                        ref
                            .watch(showFrontingViewToggleProvider)
                            .whenOrNull(data: (v) => v) ??
                        true,
                    onChanged: (v) => ref
                        .read(showFrontingViewToggleProvider.notifier)
                        .setEnabled(v),
                  ),
                ],
              ),
            ),
          ),

          // Layout — preview sits at the top of the same card as the
          // reorderable list, so the preview visibly updates as items move.
          PrismSection(
            title: context.l10n.navigationLayoutSection,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _NavigationBarPreview(
                      primaryTabs: primaryTabs,
                      overflowTabs: overflowTabs,
                      terminologyPlural: terms.plural,
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: entries.length,
                    onReorder: (oldIndex, newIndex) {
                      _onReorder(
                        context,
                        ref,
                        entries,
                        oldIndex,
                        newIndex,
                        terminologyPlural: terms.plural,
                      );
                    },
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(
                          PrismShapes.of(context).radius(12),
                        ),
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final entry = entries[index];

                      if (entry.isHeader) {
                        return _SectionHeader(
                          key: ValueKey('header_${entry.headerTitle}'),
                          title: entry.headerTitle!,
                        );
                      }

                      final tab = entry.tab!;
                      final isInPrimary = _isInPrimarySection(entries, index);
                      final moveToPrimaryEnabled =
                          !tab.isLocked &&
                          !isInPrimary &&
                          canMoveToPrimary(tab);

                      return _NavItem(
                        key: ValueKey(tab.id),
                        tab: tab,
                        terminologyPlural: terms.plural,
                        isLocked: tab.isLocked,
                        reorderIndex: index,
                        onRemove: tab.isLocked
                            ? null
                            : () => _removeItem(
                                context,
                                ref,
                                entries,
                                index,
                                terminologyPlural: terms.plural,
                              ),
                        onMoveToOverflow: tab.isLocked || !isInPrimary
                            ? null
                            : () => _moveToOtherSection(
                                context,
                                ref,
                                entries,
                                index,
                                false,
                                terminologyPlural: terms.plural,
                              ),
                        onMoveToPrimary: !moveToPrimaryEnabled
                            ? null
                            : () => _moveToOtherSection(
                                context,
                                ref,
                                entries,
                                index,
                                true,
                                terminologyPlural: terms.plural,
                              ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Available tabs to add
          if (availableTabs.isNotEmpty)
            PrismSection(
              title: context.l10n.navigationAvailable,
              child: PrismSectionCard(
                child: Column(
                  children: [
                    for (int i = 0; i < availableTabs.length; i++) ...[
                      _AvailableItem(
                        tab: availableTabs[i],
                        terminologyPlural: terms.plural,
                        canAddToBar: canAddToPrimary(availableTabs[i]),
                        onAddToBar: () => _addToPrimary(
                          context,
                          ref,
                          primaryTabs,
                          overflowTabs,
                          availableTabs[i],
                          terminologyPlural: terms.plural,
                        ),
                        onAddToOverflow: () => _addToOverflow(
                          context,
                          ref,
                          primaryTabs,
                          overflowTabs,
                          availableTabs[i],
                          terminologyPlural: terms.plural,
                        ),
                      ),
                      if (i < availableTabs.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
            ),

          // Disabled features
          if (disabledTabs.isNotEmpty)
            PrismSection(
              title: context.l10n.navigationDisabledFeatures,
              child: PrismSectionCard(
                child: Column(
                  children: [
                    for (int i = 0; i < disabledTabs.length; i++) ...[
                      _DisabledItem(
                        tab: disabledTabs[i],
                        terminologyPlural: terms.plural,
                        onTap: () =>
                            context.push(AppRoutePaths.settingsFeatures),
                      ),
                      if (i < disabledTabs.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Unified list helpers ---

  /// Find the index of the overflow header in the entries list.
  /// Note: we search by position (second header) rather than by string value
  /// to remain locale-independent.
  int _overflowHeaderIndex(List<_UnifiedEntry> entries) {
    final headers = entries.where((e) => e.isHeader).toList();
    if (headers.length < 2) return entries.length;
    return entries.indexOf(headers[1]);
  }

  /// Whether the item at [index] is in the primary section (before overflow header).
  bool _isInPrimarySection(List<_UnifiedEntry> entries, int index) {
    return index < _overflowHeaderIndex(entries);
  }

  /// Handle reorder within the unified list. Headers cannot move, and Home
  /// (the only locked item) stays pinned at the top of the primary section.
  void _onReorder(
    BuildContext context,
    WidgetRef ref,
    List<_UnifiedEntry> entries,
    int oldIndex,
    int newIndex, {
    required String terminologyPlural,
  }) {
    if (newIndex > oldIndex) newIndex--;

    final entry = entries[oldIndex];

    // Headers are not draggable -- ignore
    if (entry.isHeader) return;

    // Locked items cannot move
    if (entry.tab!.isLocked) return;

    // Cannot drop onto a header position (index 0 or the overflow header index)
    // Build the reordered list to figure out final positions
    final reordered = List<_UnifiedEntry>.from(entries);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    // Validate: headers must stay in original relative order and locked items
    // must remain in their correct positions. Extract and save.
    _saveFromEntries(
      context,
      ref,
      reordered,
      terminologyPlural: terminologyPlural,
    );
  }

  /// Move an item to the other section using the arrow buttons.
  void _moveToOtherSection(
    BuildContext context,
    WidgetRef ref,
    List<_UnifiedEntry> entries,
    int index,
    bool toPrimary, {
    required String terminologyPlural,
  }) {
    final reordered = List<_UnifiedEntry>.from(entries);
    final item = reordered.removeAt(index);
    final overflowIdx = _overflowHeaderIndex(reordered);

    if (toPrimary) {
      // Insert just before the overflow header (end of primary section)
      reordered.insert(overflowIdx, item);
    } else {
      // Insert just after the overflow header (start of overflow section)
      reordered.insert(overflowIdx + 1, item);
    }
    _saveFromEntries(
      context,
      ref,
      reordered,
      terminologyPlural: terminologyPlural,
    );
  }

  /// Remove an item from the unified list entirely.
  void _removeItem(
    BuildContext context,
    WidgetRef ref,
    List<_UnifiedEntry> entries,
    int index, {
    required String terminologyPlural,
  }) {
    final reordered = List<_UnifiedEntry>.from(entries);
    reordered.removeAt(index);
    _saveFromEntries(
      context,
      ref,
      reordered,
      terminologyPlural: terminologyPlural,
    );
  }

  /// Derive primary and overflow tab lists from the unified entries and persist.
  /// Reject reorders that would move Home out of position 0; everything else
  /// flows through [normalizeNavLayout] which enforces the 5-tab cap.
  void _saveFromEntries(
    BuildContext context,
    WidgetRef ref,
    List<_UnifiedEntry> entries, {
    required String terminologyPlural,
  }) {
    final overflowIdx = _overflowHeaderIndex(entries);

    final primaryItems = <AppShellTab>[];
    final overflowItems = <AppShellTab>[];

    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.isHeader) continue;
      if (i < overflowIdx) {
        primaryItems.add(e.tab!);
      } else {
        overflowItems.add(e.tab!);
      }
    }

    // Home is locked — reject any reorder that would displace it.
    final homeIdx = primaryItems.indexWhere((t) => t.id == AppShellTabId.home);
    if (homeIdx >= 0 && homeIdx != 0) return;
    if (overflowItems.any((t) => t.id == AppShellTabId.home)) return;

    _persistNormalized(
      context,
      ref,
      primaryItems,
      overflowItems,
      terminologyPlural: terminologyPlural,
    );
  }

  // --- Add operations (from Available section) ---

  void _addToPrimary(
    BuildContext context,
    WidgetRef ref,
    List<AppShellTab> currentPrimary,
    List<AppShellTab> currentOverflow,
    AppShellTab tab, {
    required String terminologyPlural,
  }) {
    // If primary is already at cap, route the new tab to overflow so the user
    // never ends up with >5 primary items through this button.
    if (currentPrimary.length >= kMaxPrimaryNavTabs) {
      _persistNormalized(context, ref, currentPrimary, [
        ...currentOverflow,
        tab,
      ], terminologyPlural: terminologyPlural);
      return;
    }
    _persistNormalized(
      context,
      ref,
      [...currentPrimary, tab],
      currentOverflow,
      terminologyPlural: terminologyPlural,
    );
  }

  void _addToOverflow(
    BuildContext context,
    WidgetRef ref,
    List<AppShellTab> currentPrimary,
    List<AppShellTab> currentOverflow,
    AppShellTab tab, {
    required String terminologyPlural,
  }) {
    _persistNormalized(context, ref, currentPrimary, [
      ...currentOverflow,
      tab,
    ], terminologyPlural: terminologyPlural);
  }

  /// Push [primary] and [overflow] through [normalizeNavLayout] before saving
  /// so the persisted config always satisfies the 5-cap + Home-first
  /// invariants that the rendered nav bar relies on.
  void _persistNormalized(
    BuildContext context,
    WidgetRef ref,
    List<AppShellTab> primary,
    List<AppShellTab> overflow, {
    required String terminologyPlural,
  }) {
    final flags = ref.read(featureFlagsProvider);
    final normalized = normalizeNavLayout(
      primaryIds: primary.map((t) => t.id.name).toList(),
      overflowIds: overflow.map((t) => t.id.name).toList(),
      flags: flags,
    );
    final adaptiveLayout = computeAdaptiveNavLayoutForCurrentDevice(
      context,
      primary: normalized.primary,
      overflow: normalized.overflow,
      terminologyPlural: terminologyPlural,
    );
    _savePrimary(ref, adaptiveLayout.primaryTabs);
    _saveOverflow(ref, adaptiveLayout.overflowTabs);
  }

  // --- Persistence ---

  void _savePrimary(WidgetRef ref, List<AppShellTab> tabs) {
    final ids = tabs.map((t) => t.id.name).toList();
    ref.read(settingsNotifierProvider.notifier).updateNavBarItems(ids);
  }

  void _saveOverflow(WidgetRef ref, List<AppShellTab> tabs) {
    final ids = tabs.map((t) => t.id.name).toList();
    ref.read(settingsNotifierProvider.notifier).updateNavBarOverflowItems(ids);
  }

  bool _rendersInPrimaryOnCurrentDevice(
    BuildContext context, {
    required List<AppShellTab> primary,
    required List<AppShellTab> overflow,
    required AppShellTab candidate,
    required String terminologyPlural,
  }) {
    final rendered = computeAdaptiveNavLayoutForCurrentDevice(
      context,
      primary: primary,
      overflow: overflow,
      terminologyPlural: terminologyPlural,
    );

    return rendered.primaryTabs.any((tab) => tab.id == candidate.id);
  }
}

/// A unified entry in the flat reorderable list: either a section header or a tab item.
class _UnifiedEntry {
  final String? headerTitle;
  final AppShellTab? tab;

  const _UnifiedEntry.header(this.headerTitle) : tab = null;
  const _UnifiedEntry.item(this.tab) : headerTitle = null;

  bool get isHeader => headerTitle != null;
}

/// Non-draggable section header displayed within the ReorderableListView.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.tab,
    required this.terminologyPlural,
    required this.isLocked,
    required this.reorderIndex,
    this.onRemove,
    this.onMoveToOverflow,
    this.onMoveToPrimary,
  });

  final AppShellTab tab;
  final String terminologyPlural;
  final bool isLocked;
  final int reorderIndex;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveToOverflow;
  final VoidCallback? onMoveToPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismListRow(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(tab.icon, color: theme.colorScheme.primary),
      title: Text(
        tab.localizedLabel(context, terminologyPlural: terminologyPlural),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLocked)
            Icon(
              AppIcons.lockOutline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            )
          else ...[
            if (onMoveToPrimary != null)
              PrismInlineIconButton(
                icon: AppIcons.arrowUpward,
                iconSize: 18,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
                tooltip: context.l10n.navigationMoveToNavBar,
                onPressed: onMoveToPrimary,
              ),
            if (onMoveToOverflow != null)
              PrismInlineIconButton(
                icon: AppIcons.arrowDownward,
                iconSize: 18,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
                tooltip: context.l10n.navigationMoveToMoreMenu,
                onPressed: onMoveToOverflow,
              ),
            if (onRemove != null)
              PrismInlineIconButton(
                icon: AppIcons.removeCircleOutline,
                color: theme.colorScheme.error.withValues(alpha: 0.7),
                onPressed: onRemove,
                tooltip: context.l10n.navigationRemove,
              ),
          ],
          if (!isLocked)
            ReorderableDragStartListener(
              index: reorderIndex,
              child: Icon(
                AppIcons.dragHandle,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvailableItem extends StatelessWidget {
  const _AvailableItem({
    required this.tab,
    required this.terminologyPlural,
    required this.canAddToBar,
    required this.onAddToBar,
    required this.onAddToOverflow,
  });

  final AppShellTab tab;
  final String terminologyPlural;
  final bool canAddToBar;
  final VoidCallback onAddToBar;
  final VoidCallback onAddToOverflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismListRow(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(tab.icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(
        tab.localizedLabel(context, terminologyPlural: terminologyPlural),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrismInlineIconButton(
            icon: AppIcons.addCircleOutline,
            color: theme.colorScheme.primary.withValues(
              alpha: canAddToBar ? 1 : 0.7,
            ),
            tooltip: canAddToBar
                ? context.l10n.navigationAddToNavBar
                : context.l10n.add,
            onPressed: onAddToBar,
          ),
          PrismInlineIconButton(
            icon: AppIcons.moreVert,
            iconSize: 20,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
            tooltip: context.l10n.navigationAddToMoreMenu,
            onPressed: onAddToOverflow,
          ),
        ],
      ),
    );
  }
}

class _DisabledItem extends StatelessWidget {
  const _DisabledItem({
    required this.tab,
    required this.terminologyPlural,
    required this.onTap,
  });

  final AppShellTab tab;
  final String terminologyPlural;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismListRow(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        tab.icon,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
      title: Text(
        tab.localizedLabel(context, terminologyPlural: terminologyPlural),
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
      trailing: Text(
        context.l10n.navigationEnableInFeatures,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _NavigationBarPreview extends StatelessWidget {
  const _NavigationBarPreview({
    required this.primaryTabs,
    required this.overflowTabs,
    required this.terminologyPlural,
  });

  final List<AppShellTab> primaryTabs;
  final List<AppShellTab> overflowTabs;
  final String terminologyPlural;

  Widget _buildOverflowRow(
    BuildContext context, {
    required List<AppShellTab?> row,
    required int overflowColumns,
    required bool hasMultipleRows,
    required Color accentColor,
    required bool isDark,
  }) {
    final tabs = row.whereType<AppShellTab>().toList();
    if (tabs.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotColumns = hasMultipleRows ? overflowColumns : tabs.length;
        final slotWidth = slotColumns <= 0
            ? 0.0
            : constraints.maxWidth / slotColumns;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final tab in tabs)
              SizedBox(
                width: slotWidth,
                child: _PreviewNavBarItem(
                  tab: tab,
                  label: tab.localizedLabel(
                    context,
                    terminologyPlural: terminologyPlural,
                  ),
                  isSelected: false,
                  accentColor: accentColor,
                  isDark: isDark,
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shapes = PrismShapes.of(context);

    final primaryLabels = [
      for (final tab in primaryTabs)
        tab.localizedLabel(context, terminologyPlural: terminologyPlural),
    ];
    final overflowLabels = [
      for (final tab in overflowTabs)
        tab.localizedLabel(context, terminologyPlural: terminologyPlural),
    ];

    final targetBarWidth =
        (MediaQuery.sizeOf(context).width - (kFloatingNavBarSideMargin * 2))
            .clamp(0.0, double.infinity)
            .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = math.min(constraints.maxWidth, targetBarWidth);
        final layout = computeAdaptiveMobileNavLayout(
          barWidth: previewWidth,
          primaryTabs: primaryTabs,
          overflowTabs: overflowTabs,
          primaryLabels: primaryLabels,
          overflowLabels: overflowLabels,
          labelStyle: navBarLabelTextStyle(context, isSelected: true),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        );
        final selectedTabId = layout.primaryTabs.isNotEmpty
            ? layout.primaryTabs.first.id
            : null;
        final overflowRows = arrangeOverflowRows(
          layout.overflowTabs,
          layout.spec.overflowColumns,
        );
        final hasMultipleOverflowRows = overflowRows.length > 1;

        return Center(
          child: IgnorePointer(
            child: Semantics(
              container: true,
              label: context.l10n.navigationBar,
              child: Container(
                key: const Key('navigation_preview'),
                width: previewWidth,
                height: layout.expandedHeight + 2,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    theme.colorScheme.primary.withValues(
                      alpha: isDark ? 0.08 : 0.06,
                    ),
                    theme.colorScheme.surface.withValues(
                      alpha: isDark ? 0.9 : 0.98,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(
                    shapes.radius(layout.overflowTabs.isNotEmpty ? 28 : 32),
                  ),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: isDark ? 0.32 : 0.5,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.08,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (overflowRows.isNotEmpty) ...[
                      for (int i = 0; i < overflowRows.length; i++)
                        SizedBox(
                          key: ValueKey('navigation_preview_overflow_row_$i'),
                          height: layout.overflowRowHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _buildOverflowRow(
                              context,
                              row: overflowRows[i],
                              overflowColumns: layout.spec.overflowColumns,
                              hasMultipleRows: hasMultipleOverflowRows,
                              accentColor: theme.colorScheme.primary,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      Container(
                        height: _kPreviewRowGap,
                        alignment: Alignment.center,
                        child: Container(
                          height: 0.5,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: isDark ? 0.3 : 0.5,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(
                      key: const Key('navigation_preview_primary_row'),
                      height: layout.rowHeight,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 12,
                          right: layout.overflowTabs.isNotEmpty ? 4 : 12,
                        ),
                        child: Row(
                          children: [
                            for (final tab in layout.primaryTabs)
                              Expanded(
                                child: _PreviewNavBarItem(
                                  tab: tab,
                                  label: tab.localizedLabel(
                                    context,
                                    terminologyPlural: terminologyPlural,
                                  ),
                                  isSelected: selectedTabId == tab.id,
                                  accentColor: theme.colorScheme.primary,
                                  isDark: isDark,
                                ),
                              ),
                            if (layout.overflowTabs.isNotEmpty)
                              SizedBox(
                                width: _kPreviewMoreButtonWidth,
                                child: Center(
                                  child: Icon(
                                    AppIcons.moreVert,
                                    size: kNavBarMoreTriggerIconSize,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
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
}

class _PreviewNavBarItem extends StatelessWidget {
  const _PreviewNavBarItem({
    required this.tab,
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.isDark,
  });

  final AppShellTab tab;
  final String label;
  final bool isSelected;
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final shapes = PrismShapes.of(context);
    final iconColor = isSelected
        ? accentColor
        : Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: isDark ? 0.8 : 0.9);
    final labelColor = isSelected
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kNavBarItemIconHeight,
          child: Container(
            width: kNavBarItemWidth,
            alignment: Alignment.center,
            decoration: isSelected
                ? BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(shapes.radius(16)),
                  )
                : null,
            child: Icon(
              isSelected ? tab.activeIcon : tab.icon,
              size: kNavBarItemIconSize,
              color: iconColor,
            ),
          ),
        ),
        RichText(
          text: TextSpan(
            text: label,
            style: navBarLabelTextStyle(
              context,
              isSelected: isSelected,
              color: labelColor,
            ),
          ),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ],
    );
  }
}
