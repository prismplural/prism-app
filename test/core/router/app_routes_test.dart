import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';

void main() {
  group('AppShellTabId', () {
    test('enum names match expected string values', () {
      expect(AppShellTabId.home.name, 'home');
      expect(AppShellTabId.chat.name, 'chat');
      expect(AppShellTabId.habits.name, 'habits');
      expect(AppShellTabId.polls.name, 'polls');
      expect(AppShellTabId.settings.name, 'settings');
      expect(AppShellTabId.members.name, 'members');
      expect(AppShellTabId.reminders.name, 'reminders');
      expect(AppShellTabId.notes.name, 'notes');
      expect(AppShellTabId.statistics.name, 'statistics');
    });
  });

  group('AppShellTab.isLocked', () {
    test('home is locked', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.home);
      expect(tab.isLocked, isTrue);
    });

    test('settings is locked', () {
      final tab =
          appShellTabs.firstWhere((t) => t.id == AppShellTabId.settings);
      expect(tab.isLocked, isTrue);
    });

    test('all other tabs are not locked', () {
      const unlockedIds = [
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.members,
        AppShellTabId.reminders,
        AppShellTabId.notes,
        AppShellTabId.statistics,
      ];
      for (final id in unlockedIds) {
        final tab = appShellTabs.firstWhere((t) => t.id == id);
        expect(tab.isLocked, isFalse, reason: '${id.name} should not be locked');
      }
    });
  });

  group('AppShellTab.isEnabled', () {
    // Default SystemSettings has all features enabled.
    const allEnabled = SystemSettings();

    test('home is always enabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.home);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(null), isTrue);
    });

    test('settings is always enabled', () {
      final tab =
          appShellTabs.firstWhere((t) => t.id == AppShellTabId.settings);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(null), isTrue);
    });

    test('members is always enabled', () {
      final tab =
          appShellTabs.firstWhere((t) => t.id == AppShellTabId.members);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(null), isTrue);
      expect(
        tab.isEnabled(const SystemSettings(chatEnabled: false)),
        isTrue,
      );
    });

    test('chat is gated by chatEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.chat);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(
        tab.isEnabled(const SystemSettings(chatEnabled: false)),
        isFalse,
      );
    });

    test('habits is gated by habitsEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.habits);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(
        tab.isEnabled(const SystemSettings(habitsEnabled: false)),
        isFalse,
      );
    });

    test('polls is gated by pollsEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.polls);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(
        tab.isEnabled(const SystemSettings(pollsEnabled: false)),
        isFalse,
      );
    });

    test('reminders is gated by remindersEnabled', () {
      final tab =
          appShellTabs.firstWhere((t) => t.id == AppShellTabId.reminders);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(
        tab.isEnabled(const SystemSettings(remindersEnabled: false)),
        isFalse,
      );
    });

    test('notes is gated by notesEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.notes);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(
        tab.isEnabled(const SystemSettings(notesEnabled: false)),
        isFalse,
      );
    });

    test('statistics is always enabled', () {
      final tab =
          appShellTabs.firstWhere((t) => t.id == AppShellTabId.statistics);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(null), isTrue);
    });

    test('all feature-gated tabs default to enabled when settings is null', () {
      const gatedIds = [
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.reminders,
        AppShellTabId.notes,
      ];
      for (final id in gatedIds) {
        final tab = appShellTabs.firstWhere((t) => t.id == id);
        expect(tab.isEnabled(null), isTrue,
            reason: '${id.name} should default to enabled when settings is null');
      }
    });
  });

  group('appShellTabs', () {
    test('has 9 entries', () {
      expect(appShellTabs, hasLength(9));
    });

    test('branch indices are 0 through 8', () {
      final indices = appShellTabs.map((t) => t.branchIndex).toList();
      expect(indices, [0, 1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('no duplicate branch indices', () {
      final indices = appShellTabs.map((t) => t.branchIndex).toSet();
      expect(indices, hasLength(appShellTabs.length));
    });

    test('no duplicate root locations', () {
      final locations = appShellTabs.map((t) => t.rootLocation).toSet();
      expect(locations, hasLength(appShellTabs.length));
    });

    test('no duplicate tab IDs', () {
      final ids = appShellTabs.map((t) => t.id).toSet();
      expect(ids, hasLength(appShellTabs.length));
    });

    test('every AppShellTabId is represented', () {
      final ids = appShellTabs.map((t) => t.id).toSet();
      for (final value in AppShellTabId.values) {
        expect(ids, contains(value),
            reason: '${value.name} should be in appShellTabs');
      }
    });
  });

  group('defaultNavBarTabIds', () {
    test('contains exactly the expected 5 tab IDs in order', () {
      expect(
        defaultNavBarTabIds,
        ['home', 'chat', 'habits', 'polls', 'settings'],
      );
    });

    test('has 5 entries', () {
      expect(defaultNavBarTabIds, hasLength(5));
    });
  });
}
