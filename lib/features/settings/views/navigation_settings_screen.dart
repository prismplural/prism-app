import 'package:flutter/material.dart';
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

class NavigationSettingsScreen extends ConsumerWidget {
  const NavigationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryTabs = ref.watch(activeNavBarTabsProvider);
    final overflowTabs = ref.watch(navBarOverflowTabsProvider);
    final settings = ref.watch(systemSettingsProvider).value;
    final terms = ref.watch(terminologyProvider);
    final theme = Theme.of(context);

    // All tab IDs currently placed (primary + overflow)
    final placedIds = {
      ...primaryTabs.map((t) => t.id),
      ...overflowTabs.map((t) => t.id),
    };

    // Enabled tabs not placed anywhere
    final availableTabs = [
      for (final tab in appShellTabs)
        if (!placedIds.contains(tab.id) && tab.isEnabled(settings)) tab,
    ];

    // Disabled tabs (feature is off)
    final disabledTabs = [
      for (final tab in appShellTabs)
        if (!tab.isLocked && !tab.isEnabled(settings)) tab,
    ];

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Navigation',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: NavBarInset.of(context),
        ),
        children: [
          // Sync toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: PrismSectionCard(
              child: SwitchListTile.adaptive(
                title: const Text('Sync navigation layout'),
                subtitle: Text(
                  'Share tab arrangement across devices',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: settings?.syncNavigationEnabled ?? true,
                onChanged: (v) => ref
                    .read(settingsNotifierProvider.notifier)
                    .updateSyncNavigationEnabled(v),
              ),
            ),
          ),

          // Primary nav bar items
          PrismSection(
            title: 'Nav Bar',
            child: PrismSectionCard(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: primaryTabs.length,
                onReorder: (oldIndex, newIndex) {
                  _onReorderPrimary(ref, primaryTabs, oldIndex, newIndex);
                },
                proxyDecorator: (child, index, animation) {
                  return Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: child,
                  );
                },
                itemBuilder: (context, index) {
                  final tab = primaryTabs[index];
                  return _NavItem(
                    key: ValueKey(tab.id),
                    tab: tab,
                    terminologyPlural: terms.plural,
                    isLocked: tab.isLocked,
                    reorderIndex: index,
                    onRemove: tab.isLocked
                        ? null
                        : () => _removeFromPrimary(ref, primaryTabs, tab),
                    onMoveToOverflow: tab.isLocked
                        ? null
                        : () => _movePrimaryToOverflow(
                            ref, primaryTabs, overflowTabs, tab),
                  );
                },
              ),
            ),
          ),

          // Overflow / More menu items
          PrismSection(
            title: 'More Menu',
            child: overflowTabs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Text(
                      'Items here appear when you tap the menu button on the nav bar.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : PrismSectionCard(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: overflowTabs.length,
                      onReorder: (oldIndex, newIndex) {
                        _onReorderOverflow(
                            ref, overflowTabs, oldIndex, newIndex);
                      },
                      proxyDecorator: (child, index, animation) {
                        return Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        );
                      },
                      itemBuilder: (context, index) {
                        final tab = overflowTabs[index];
                        return _NavItem(
                          key: ValueKey(tab.id),
                          tab: tab,
                          terminologyPlural: terms.plural,
                          isLocked: false,
                          reorderIndex: index,
                          onRemove: () => _removeFromOverflow(
                              ref, overflowTabs, tab),
                          onMoveToPrimary: () => _moveOverflowToPrimary(
                              ref, primaryTabs, overflowTabs, tab),
                        );
                      },
                    ),
                  ),
          ),

          // Available tabs to add
          if (availableTabs.isNotEmpty)
            PrismSection(
              title: 'Available',
              child: PrismSectionCard(
                child: Column(
                  children: [
                    for (int i = 0; i < availableTabs.length; i++) ...[
                      _AvailableItem(
                        tab: availableTabs[i],
                        terminologyPlural: terms.plural,
                        onAddToBar: () => _addToPrimary(
                            ref, primaryTabs, availableTabs[i]),
                        onAddToOverflow: () => _addToOverflow(
                            ref, overflowTabs, availableTabs[i]),
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
              title: 'Disabled Features',
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

  // --- Primary bar operations ---

  void _onReorderPrimary(
      WidgetRef ref, List<AppShellTab> current, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<AppShellTab>.from(current);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    final homeIndex =
        reordered.indexWhere((t) => t.id == AppShellTabId.home);
    final settingsIndex =
        reordered.indexWhere((t) => t.id == AppShellTabId.settings);
    if (homeIndex != 0 || settingsIndex != reordered.length - 1) return;

    _savePrimary(ref, reordered);
  }

  void _removeFromPrimary(
      WidgetRef ref, List<AppShellTab> current, AppShellTab tab) {
    final updated = current.where((t) => t.id != tab.id).toList();
    _savePrimary(ref, updated);
  }

  void _addToPrimary(
      WidgetRef ref, List<AppShellTab> current, AppShellTab tab) {
    final updated = List<AppShellTab>.from(current);
    final settingsIdx =
        updated.indexWhere((t) => t.id == AppShellTabId.settings);
    if (settingsIdx >= 0) {
      updated.insert(settingsIdx, tab);
    } else {
      updated.add(tab);
    }
    _savePrimary(ref, updated);
  }

  void _movePrimaryToOverflow(WidgetRef ref, List<AppShellTab> primary,
      List<AppShellTab> overflow, AppShellTab tab) {
    _savePrimary(ref, primary.where((t) => t.id != tab.id).toList());
    _saveOverflow(ref, [...overflow, tab]);
  }

  // --- Overflow operations ---

  void _onReorderOverflow(
      WidgetRef ref, List<AppShellTab> current, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<AppShellTab>.from(current);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    _saveOverflow(ref, reordered);
  }

  void _removeFromOverflow(
      WidgetRef ref, List<AppShellTab> current, AppShellTab tab) {
    _saveOverflow(ref, current.where((t) => t.id != tab.id).toList());
  }

  void _addToOverflow(
      WidgetRef ref, List<AppShellTab> current, AppShellTab tab) {
    _saveOverflow(ref, [...current, tab]);
  }

  void _moveOverflowToPrimary(WidgetRef ref, List<AppShellTab> primary,
      List<AppShellTab> overflow, AppShellTab tab) {
    _saveOverflow(ref, overflow.where((t) => t.id != tab.id).toList());
    final updated = List<AppShellTab>.from(primary);
    final settingsIdx =
        updated.indexWhere((t) => t.id == AppShellTabId.settings);
    if (settingsIdx >= 0) {
      updated.insert(settingsIdx, tab);
    } else {
      updated.add(tab);
    }
    _savePrimary(ref, updated);
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(tab.icon, color: theme.colorScheme.primary),
      title: Text(tab.displayLabel(terminologyPlural: terminologyPlural)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLocked)
            Icon(
              Icons.lock_outline,
              size: 18,
              color:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            )
          else ...[
            if (onMoveToPrimary != null)
              IconButton(
                icon: Icon(
                  Icons.arrow_downward,
                  size: 18,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
                tooltip: 'Move to nav bar',
                onPressed: onMoveToPrimary,
                visualDensity: VisualDensity.compact,
              ),
            if (onMoveToOverflow != null)
              IconButton(
                icon: Icon(
                  Icons.arrow_upward,
                  size: 18,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
                tooltip: 'Move to More menu',
                onPressed: onMoveToOverflow,
                visualDensity: VisualDensity.compact,
              ),
            if (onRemove != null)
              IconButton(
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: theme.colorScheme.error.withValues(alpha: 0.7),
                ),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
              ),
          ],
          if (!isLocked)
            ReorderableDragStartListener(
              index: reorderIndex,
              child: Icon(
                Icons.drag_handle,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4),
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading:
          Icon(tab.icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(tab.displayLabel(terminologyPlural: terminologyPlural)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.add_circle_outline,
              color: theme.colorScheme.primary,
            ),
            tooltip: 'Add to nav bar',
            onPressed: onAddToBar,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(
              Icons.more_vert,
              size: 20,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            tooltip: 'Add to More menu',
            onPressed: onAddToOverflow,
            visualDensity: VisualDensity.compact,
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        tab.icon,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
      title: Text(
        tab.displayLabel(terminologyPlural: terminologyPlural),
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
      trailing: Text(
        'Enable in Features',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
      ),
      onTap: onTap,
    );
  }
}
