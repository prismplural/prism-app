import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // activeNavBarTabsProvider
  // ════════════════════════════════════════════════════════════════════════════

  group('activeNavBarTabsProvider', () {
    ProviderContainer makeContainer({SystemSettings? settings}) {
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider
              .overrideWithValue(AsyncValue.data(settings ?? const SystemSettings())),
        ],
      );
      return container;
    }

    List<AppShellTabId> tabIds(List<AppShellTab> tabs) =>
        tabs.map((t) => t.id).toList();

    test('empty navBarItems returns default 5 tabs', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.settings,
      ]);
    });

    test('custom order is respected', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: ['home', 'polls', 'chat', 'settings'],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      // Home is forced first; settings order is whatever the user configured.
      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.polls,
        AppShellTabId.chat,
        AppShellTabId.settings,
      ]);
    });

    test('unknown/invalid tab IDs are silently ignored', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: ['home', 'nonexistent', 'chat', 'bogus', 'settings'],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.settings,
      ]);
    });

    test('disabled features are excluded', () {
      final container = makeContainer(
        settings: const SystemSettings(
          chatEnabled: false,
          navBarItems: ['home', 'chat', 'habits', 'polls', 'settings'],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.settings,
      ]);
    });

    test('home is always first, settings position follows config', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: ['settings', 'polls', 'home', 'chat'],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabs.first.id, AppShellTabId.home);
      // Settings is movable — its relative order among non-Home tabs is
      // preserved from the config.
      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.settings,
        AppShellTabId.polls,
        AppShellTabId.chat,
      ]);
    });

    test('primary is capped at 5 and excess spills to overflow', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: [
            'home',
            'chat',
            'habits',
            'polls',
            'members',
            'notes',
            'reminders',
            'settings',
          ],
        ),
      );
      addTearDown(container.dispose);

      final primary = container.read(activeNavBarTabsProvider);
      final overflow = container.read(navBarOverflowTabsProvider);

      expect(primary, hasLength(5));
      expect(tabIds(primary), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.members,
      ]);
      expect(tabIds(overflow), [
        AppShellTabId.notes,
        AppShellTabId.reminders,
        AppShellTabId.settings,
      ]);
    });

    test(
        'regression: 6 primary ids + non-empty overflow still clamps to 5 '
        '(user moved a tab to overflow; the old render-time auto-split only '
        'fired when overflow was empty, so >5 primary would have rendered)',
        () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: [
            'home',
            'chat',
            'habits',
            'polls',
            'members',
            'settings',
          ],
          navBarOverflowItems: ['notes'],
        ),
      );
      addTearDown(container.dispose);

      final primary = container.read(activeNavBarTabsProvider);
      final overflow = container.read(navBarOverflowTabsProvider);

      expect(primary, hasLength(5));
      expect(tabIds(primary), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.members,
      ]);
      // Excess primary (settings) spills to the front of overflow,
      // preserving order relative to the existing overflow items.
      expect(tabIds(overflow), [AppShellTabId.settings, AppShellTabId.notes]);
    });

    test('tabs in configured overflow do not duplicate into primary', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: ['home', 'chat', 'settings'],
          navBarOverflowItems: ['polls', 'habits'],
        ),
      );
      addTearDown(container.dispose);

      final primary = container.read(activeNavBarTabsProvider);
      final overflow = container.read(navBarOverflowTabsProvider);

      expect(tabIds(primary), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.settings,
      ]);
      expect(tabIds(overflow), [AppShellTabId.polls, AppShellTabId.habits]);
    });

    test('duplicate IDs in config are deduplicated', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: [
            'home',
            'chat',
            'chat',
            'polls',
            'polls',
            'settings',
          ],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.polls,
        AppShellTabId.settings,
      ]);
    });

    test('adding members/reminders/notes tabs works', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: [
            'home',
            'members',
            'reminders',
            'notes',
            'settings',
          ],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.members,
        AppShellTabId.reminders,
        AppShellTabId.notes,
        AppShellTabId.settings,
      ]);
    });

    test('disabled notes feature excludes notes tab even if in config', () {
      final container = makeContainer(
        settings: const SystemSettings(
          notesEnabled: false,
          navBarItems: ['home', 'notes', 'chat', 'settings'],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabIds(tabs), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.settings,
      ]);
    });

    test('timeline not shown with default nav config', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);
      expect(tabIds(tabs), isNot(contains(AppShellTabId.timeline)));
    });

    test('timeline shown when added to navBarItems', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: ['home', 'timeline', 'settings'],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);
      expect(tabIds(tabs), contains(AppShellTabId.timeline));
    });
  });
}
