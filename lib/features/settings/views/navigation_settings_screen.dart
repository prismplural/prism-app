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
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

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

    // Build the unified flat list: primary header + primary items + overflow header + overflow items
    final List<_UnifiedEntry> entries = [
      _UnifiedEntry.header(context.l10n.navigationNavBar),
      for (final tab in primaryTabs) _UnifiedEntry.item(tab),
      _UnifiedEntry.header(context.l10n.navigationMoreMenu),
      for (final tab in overflowTabs) _UnifiedEntry.item(tab),
    ];

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.navigationSettingsTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
        children: [
          // Sync toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                title: context.l10n.syncNavigationLayoutTitle,
                subtitle: context.l10n.syncNavigationLayoutSubtitle,
                value: syncNavigationEnabled,
                onChanged: (v) => ref
                    .read(settingsNotifierProvider.notifier)
                    .updateSyncNavigationEnabled(v),
              ),
            ),
          ),

          // Home view toggle preference
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                title: context.l10n.navigationShowViewToggleTitle,
                subtitle: context.l10n.navigationShowViewToggleSubtitle,
                value: ref.watch(showFrontingViewToggleProvider).whenOrNull(data: (v) => v) ?? true,
                onChanged: (v) => ref
                    .read(showFrontingViewToggleProvider.notifier)
                    .setEnabled(v),
              ),
            ),
          ),

          // Unified reorderable list with section headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: PrismSectionCard(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                onReorder: (oldIndex, newIndex) {
                  _onReorder(ref, entries, oldIndex, newIndex);
                },
                proxyDecorator: (child, index, animation) {
                  return Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
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

                  return _NavItem(
                    key: ValueKey(tab.id),
                    tab: tab,
                    terminologyPlural: terms.plural,
                    isLocked: tab.isLocked,
                    reorderIndex: index,
                    onRemove: tab.isLocked
                        ? null
                        : () => _removeItem(ref, entries, index),
                    onMoveToOverflow: tab.isLocked || !isInPrimary
                        ? null
                        : () => _moveToOtherSection(ref, entries, index, false),
                    onMoveToPrimary: tab.isLocked || isInPrimary
                        ? null
                        : () => _moveToOtherSection(ref, entries, index, true),
                  );
                },
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
                        onAddToBar: () =>
                            _addToPrimary(ref, primaryTabs, availableTabs[i]),
                        onAddToOverflow: () =>
                            _addToOverflow(ref, overflowTabs, availableTabs[i]),
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

  /// Handle reorder within the unified list. Headers cannot move, and locked
  /// items (Home at index 1, Settings at the end) stay put.
  void _onReorder(
    WidgetRef ref,
    List<_UnifiedEntry> entries,
    int oldIndex,
    int newIndex,
  ) {
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
    _saveFromEntries(ref, reordered);
  }

  /// Move an item to the other section using the arrow buttons.
  void _moveToOtherSection(
    WidgetRef ref,
    List<_UnifiedEntry> entries,
    int index,
    bool toPrimary,
  ) {
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
    _saveFromEntries(ref, reordered);
  }

  /// Remove an item from the unified list entirely.
  void _removeItem(WidgetRef ref, List<_UnifiedEntry> entries, int index) {
    final reordered = List<_UnifiedEntry>.from(entries);
    reordered.removeAt(index);
    _saveFromEntries(ref, reordered);
  }

  /// Derive primary and overflow tab lists from the unified entries and persist.
  void _saveFromEntries(WidgetRef ref, List<_UnifiedEntry> entries) {
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

    // Validate locked positions: Home must be first in primary, Settings last
    final homeIdx = primaryItems.indexWhere((t) => t.id == AppShellTabId.home);
    final settingsIdx = primaryItems.indexWhere(
      (t) => t.id == AppShellTabId.settings,
    );

    // If Home is not at position 0 in primary, or Settings is somewhere wrong,
    // reject the reorder silently (same behavior as the old code).
    if (homeIdx >= 0 && homeIdx != 0) return;
    if (settingsIdx >= 0 && settingsIdx != primaryItems.length - 1) return;

    // Also check if Settings ended up in overflow -- not allowed
    if (overflowItems.any((t) => t.id == AppShellTabId.settings)) return;
    // And Home in overflow -- not allowed
    if (overflowItems.any((t) => t.id == AppShellTabId.home)) return;

    _savePrimary(ref, primaryItems);
    _saveOverflow(ref, overflowItems);
  }

  // --- Add operations (from Available section) ---

  void _addToPrimary(
    WidgetRef ref,
    List<AppShellTab> current,
    AppShellTab tab,
  ) {
    final updated = List<AppShellTab>.from(current);
    final settingsIdx = updated.indexWhere(
      (t) => t.id == AppShellTabId.settings,
    );
    if (settingsIdx >= 0) {
      updated.insert(settingsIdx, tab);
    } else {
      updated.add(tab);
    }
    _savePrimary(ref, updated);
  }

  void _addToOverflow(
    WidgetRef ref,
    List<AppShellTab> current,
    AppShellTab tab,
  ) {
    _saveOverflow(ref, [...current, tab]);
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
      title: Text(tab.localizedLabel(context, terminologyPlural: terminologyPlural)),
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
    required this.onAddToBar,
    required this.onAddToOverflow,
  });

  final AppShellTab tab;
  final String terminologyPlural;
  final VoidCallback onAddToBar;
  final VoidCallback onAddToOverflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismListRow(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(tab.icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(tab.localizedLabel(context, terminologyPlural: terminologyPlural)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrismInlineIconButton(
            icon: AppIcons.addCircleOutline,
            color: theme.colorScheme.primary,
            tooltip: context.l10n.navigationAddToNavBar,
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
