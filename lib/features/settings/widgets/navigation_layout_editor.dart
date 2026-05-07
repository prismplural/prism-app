import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/nav_bar_layout.dart'
    show
        arrangeOverflowRows,
        kNavBarItemIconHeight,
        kNavBarItemIconSize,
        kNavBarItemWidth,
        kMaxAdaptiveOverflowColumns,
        kNavBarMoreTriggerIconSize,
        NavBarLayoutSpec,
        navBarLabelTextStyle;
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';

const _kPreviewRowGap = 6.0;
const _kPreviewMoreButtonWidth = 44.0;

typedef NavigationFeatureFlags = ({
  bool chat,
  bool polls,
  bool habits,
  bool sleep,
  bool notes,
  bool reminders,
  bool boards,
});

typedef NavigationLayoutChanged =
    void Function(List<AppShellTab> primary, List<AppShellTab> overflow);

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

class NavigationLayoutEditor extends StatelessWidget {
  const NavigationLayoutEditor({
    super.key,
    required this.primaryTabs,
    required this.overflowTabs,
    required this.flags,
    required this.terminologyPlural,
    required this.onLayoutChanged,
    this.showDisabledFeatures = true,
    this.onDisabledFeatureTap,
    this.intro,
    this.sectionPadding = PrismTokens.sectionPadding,
    this.showLayoutTitle = true,
    this.adaptPreviewToDeviceWidth = true,
    this.adaptSavedLayoutToDeviceWidth = true,
  });

  final List<AppShellTab> primaryTabs;
  final List<AppShellTab> overflowTabs;
  final NavigationFeatureFlags flags;
  final String terminologyPlural;
  final NavigationLayoutChanged onLayoutChanged;
  final bool showDisabledFeatures;
  final VoidCallback? onDisabledFeatureTap;
  final Widget? intro;
  final EdgeInsets sectionPadding;
  final bool showLayoutTitle;
  final bool adaptPreviewToDeviceWidth;
  final bool adaptSavedLayoutToDeviceWidth;

  @override
  Widget build(BuildContext context) {
    final placedIds = {
      ...primaryTabs.map((tab) => tab.id),
      ...overflowTabs.map((tab) => tab.id),
    };
    final availableTabs = [
      for (final tab in appShellTabs)
        if (!placedIds.contains(tab.id) && tab.isEnabled(flags)) tab,
    ];
    final disabledTabs = [
      for (final tab in appShellTabs)
        if (!tab.isRequired && !tab.isEnabled(flags)) tab,
    ];
    final entries = [
      _UnifiedEntry.header(context.l10n.navigationNavBar),
      for (final tab in primaryTabs) _UnifiedEntry.item(tab),
      _UnifiedEntry.header(context.l10n.navigationMoreMenu),
      for (final tab in overflowTabs) _UnifiedEntry.item(tab),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?intro,
        PrismSection(
          title: showLayoutTitle ? context.l10n.navigationLayoutSection : '',
          padding: sectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavigationBarPreview(
                primaryTabs: primaryTabs,
                overflowTabs: overflowTabs,
                terminologyPlural: terminologyPlural,
                adaptToDeviceWidth: adaptPreviewToDeviceWidth,
              ),
              const SizedBox(height: 12),
              PrismSectionCard(
                padding: EdgeInsets.zero,
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  onReorder: (oldIndex, newIndex) {
                    _onReorder(context, entries, oldIndex, newIndex);
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
                        _canMoveToPrimary(context, tab);

                    return _NavItem(
                      key: ValueKey(tab.id),
                      tab: tab,
                      terminologyPlural: terminologyPlural,
                      isLocked: tab.isLocked,
                      reorderIndex: index,
                      onRemove: tab.isRequired
                          ? null
                          : () => _removeItem(context, entries, index),
                      onMoveToOverflow: tab.isLocked || !isInPrimary
                          ? null
                          : () => _moveToOtherSection(
                              context,
                              entries,
                              index,
                              false,
                            ),
                      onMoveToPrimary: !moveToPrimaryEnabled
                          ? null
                          : () => _moveToOtherSection(
                              context,
                              entries,
                              index,
                              true,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (availableTabs.isNotEmpty)
          PrismSection(
            title: context.l10n.navigationAvailable,
            padding: sectionPadding,
            child: PrismSectionCard(
              child: Column(
                children: [
                  for (int i = 0; i < availableTabs.length; i++) ...[
                    _AvailableItem(
                      tab: availableTabs[i],
                      terminologyPlural: terminologyPlural,
                      canAddToBar: _canAddToPrimary(context, availableTabs[i]),
                      onAddToBar: () => _addToPrimary(
                        context,
                        primaryTabs,
                        overflowTabs,
                        availableTabs[i],
                      ),
                      onAddToOverflow: () => _addToOverflow(
                        context,
                        primaryTabs,
                        overflowTabs,
                        availableTabs[i],
                      ),
                    ),
                    if (i < availableTabs.length - 1)
                      const Divider(height: 1, indent: 56),
                  ],
                ],
              ),
            ),
          ),
        if (showDisabledFeatures && disabledTabs.isNotEmpty)
          PrismSection(
            title: context.l10n.navigationDisabledFeatures,
            padding: sectionPadding,
            child: PrismSectionCard(
              child: Column(
                children: [
                  for (int i = 0; i < disabledTabs.length; i++) ...[
                    _DisabledItem(
                      tab: disabledTabs[i],
                      terminologyPlural: terminologyPlural,
                      onTap: onDisabledFeatureTap,
                    ),
                    if (i < disabledTabs.length - 1)
                      const Divider(height: 1, indent: 56),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  int _overflowHeaderIndex(List<_UnifiedEntry> entries) {
    final headers = entries.where((entry) => entry.isHeader).toList();
    if (headers.length < 2) return entries.length;
    return entries.indexOf(headers[1]);
  }

  bool _isInPrimarySection(List<_UnifiedEntry> entries, int index) {
    return index < _overflowHeaderIndex(entries);
  }

  void _onReorder(
    BuildContext context,
    List<_UnifiedEntry> entries,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex--;
    final entry = entries[oldIndex];
    if (entry.isHeader || entry.tab!.isLocked) return;

    final reordered = List<_UnifiedEntry>.from(entries);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    _saveFromEntries(context, reordered);
  }

  void _moveToOtherSection(
    BuildContext context,
    List<_UnifiedEntry> entries,
    int index,
    bool toPrimary,
  ) {
    final reordered = List<_UnifiedEntry>.from(entries);
    final item = reordered.removeAt(index);
    final overflowIdx = _overflowHeaderIndex(reordered);

    if (toPrimary) {
      reordered.insert(overflowIdx, item);
    } else {
      reordered.insert(overflowIdx + 1, item);
    }
    _saveFromEntries(context, reordered);
  }

  void _removeItem(
    BuildContext context,
    List<_UnifiedEntry> entries,
    int index,
  ) {
    final reordered = List<_UnifiedEntry>.from(entries);
    reordered.removeAt(index);
    _saveFromEntries(context, reordered);
  }

  void _saveFromEntries(BuildContext context, List<_UnifiedEntry> entries) {
    final overflowIdx = _overflowHeaderIndex(entries);
    final primaryItems = <AppShellTab>[];
    final overflowItems = <AppShellTab>[];

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.isHeader) continue;
      if (i < overflowIdx) {
        primaryItems.add(entry.tab!);
      } else {
        overflowItems.add(entry.tab!);
      }
    }

    final homeIdx = primaryItems.indexWhere((t) => t.id == AppShellTabId.home);
    if (homeIdx >= 0 && homeIdx != 0) return;
    if (overflowItems.any((t) => t.id == AppShellTabId.home)) return;

    _persistNormalized(context, primaryItems, overflowItems);
  }

  void _addToPrimary(
    BuildContext context,
    List<AppShellTab> currentPrimary,
    List<AppShellTab> currentOverflow,
    AppShellTab tab,
  ) {
    if (currentPrimary.length >= kMaxPrimaryNavTabs) {
      _persistNormalized(context, currentPrimary, [...currentOverflow, tab]);
      return;
    }
    _persistNormalized(context, [...currentPrimary, tab], currentOverflow);
  }

  void _addToOverflow(
    BuildContext context,
    List<AppShellTab> currentPrimary,
    List<AppShellTab> currentOverflow,
    AppShellTab tab,
  ) {
    _persistNormalized(context, currentPrimary, [...currentOverflow, tab]);
  }

  void _persistNormalized(
    BuildContext context,
    List<AppShellTab> primary,
    List<AppShellTab> overflow,
  ) {
    final normalized = normalizeNavLayout(
      primaryIds: primary.map((tab) => tab.id.name).toList(),
      overflowIds: overflow.map((tab) => tab.id.name).toList(),
      flags: flags,
    );
    if (adaptSavedLayoutToDeviceWidth) {
      final adaptiveLayout = computeAdaptiveNavLayoutForCurrentDevice(
        context,
        primary: normalized.primary,
        overflow: normalized.overflow,
        terminologyPlural: terminologyPlural,
      );
      onLayoutChanged(adaptiveLayout.primaryTabs, adaptiveLayout.overflowTabs);
      return;
    }

    onLayoutChanged(normalized.primary, normalized.overflow);
  }

  bool _canAddToPrimary(BuildContext context, AppShellTab tab) {
    if (primaryTabs.length >= kMaxPrimaryNavTabs) return false;
    return _rendersInPrimaryOnCurrentDevice(
      context,
      primary: [...primaryTabs, tab],
      overflow: overflowTabs,
      candidate: tab,
    );
  }

  bool _canMoveToPrimary(BuildContext context, AppShellTab tab) {
    if (primaryTabs.length >= kMaxPrimaryNavTabs) return false;
    return _rendersInPrimaryOnCurrentDevice(
      context,
      primary: [...primaryTabs, tab],
      overflow: [
        for (final overflowTab in overflowTabs)
          if (overflowTab.id != tab.id) overflowTab,
      ],
      candidate: tab,
    );
  }

  bool _rendersInPrimaryOnCurrentDevice(
    BuildContext context, {
    required List<AppShellTab> primary,
    required List<AppShellTab> overflow,
    required AppShellTab candidate,
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

class _UnifiedEntry {
  const _UnifiedEntry.header(this.headerTitle) : tab = null;
  const _UnifiedEntry.item(this.tab) : headerTitle = null;

  final String? headerTitle;
  final AppShellTab? tab;

  bool get isHeader => headerTitle != null;
}

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
  final VoidCallback? onTap;

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
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 104),
        child: Text(
          context.l10n.navigationEnableInFeatures,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
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
    required this.adaptToDeviceWidth,
  });

  final List<AppShellTab> primaryTabs;
  final List<AppShellTab> overflowTabs;
  final String terminologyPlural;
  final bool adaptToDeviceWidth;

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
                  key: ValueKey('navigation_preview_overflow_${tab.id.name}'),
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
        final layout = adaptToDeviceWidth
            ? computeAdaptiveMobileNavLayout(
                barWidth: previewWidth,
                primaryTabs: primaryTabs,
                overflowTabs: overflowTabs,
                primaryLabels: primaryLabels,
                overflowLabels: overflowLabels,
                labelStyle: navBarLabelTextStyle(context, isSelected: true),
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: Directionality.of(context),
              )
            : _fixedPreviewLayout(primaryTabs, overflowTabs);
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
                                  key: ValueKey(
                                    'navigation_preview_primary_${tab.id.name}',
                                  ),
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

  AppShellMobileNavLayout _fixedPreviewLayout(
    List<AppShellTab> primaryTabs,
    List<AppShellTab> overflowTabs,
  ) {
    final overflowColumns = overflowTabs.isEmpty
        ? 0
        : math.min(overflowTabs.length, kMaxAdaptiveOverflowColumns);
    final overflowRows = overflowColumns == 0
        ? 0
        : (overflowTabs.length / overflowColumns).ceil();

    return AppShellMobileNavLayout(
      spec: NavBarLayoutSpec(
        collapsedPrimaryCount: primaryTabs.length,
        usesOverflowMenu: overflowTabs.isNotEmpty,
        overflowColumns: overflowColumns,
        overflowRows: overflowRows,
      ),
      primaryTabs: primaryTabs,
      overflowTabs: overflowTabs,
      rowHeight: kFloatingNavBarHeight,
      overflowRowHeight: kFloatingNavBarHeight,
    );
  }
}

class _PreviewNavBarItem extends StatelessWidget {
  const _PreviewNavBarItem({
    super.key,
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
