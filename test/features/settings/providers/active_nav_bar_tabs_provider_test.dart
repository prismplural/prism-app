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

      // Home is forced first, settings forced last, but polls before chat
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

    test('home is always first and settings always last', () {
      final container = makeContainer(
        settings: const SystemSettings(
          navBarItems: ['settings', 'polls', 'home', 'chat'],
        ),
      );
      addTearDown(container.dispose);

      final tabs = container.read(activeNavBarTabsProvider);

      expect(tabs.first.id, AppShellTabId.home);
      expect(tabs.last.id, AppShellTabId.settings);
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
  });
}
