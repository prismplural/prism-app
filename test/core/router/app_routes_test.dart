import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';

/// Helper to create a feature flags record with all features enabled.
({
  bool chat,
  bool polls,
  bool habits,
  bool sleep,
  bool notes,
  bool reminders,
  bool boards,
})
_allEnabled() => (
  chat: true,
  polls: true,
  habits: true,
  sleep: true,
  notes: true,
  reminders: true,
  boards: true,
);

/// Helper to create a feature flags record with one feature disabled.
({
  bool chat,
  bool polls,
  bool habits,
  bool sleep,
  bool notes,
  bool reminders,
  bool boards,
})
_withDisabled({
  bool chat = true,
  bool polls = true,
  bool habits = true,
  bool sleep = true,
  bool notes = true,
  bool reminders = true,
  bool boards = true,
}) => (
  chat: chat,
  polls: polls,
  habits: habits,
  sleep: sleep,
  notes: notes,
  reminders: reminders,
  boards: boards,
);

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
      expect(AppShellTabId.timeline.name, 'timeline');
      expect(AppShellTabId.sleep.name, 'sleep');
      expect(AppShellTabId.boards.name, 'boards');
    });
  });

  group('AppShellTab.isLocked', () {
    test('home is locked', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.home);
      expect(tab.isLocked, isTrue);
    });

    test('settings is not locked (user may move it)', () {
      final tab = appShellTabs.firstWhere(
        (t) => t.id == AppShellTabId.settings,
      );
      expect(tab.isLocked, isFalse);
    });

    test('all other tabs are not locked', () {
      const unlockedIds = [
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.settings,
        AppShellTabId.members,
        AppShellTabId.reminders,
        AppShellTabId.notes,
        AppShellTabId.statistics,
        AppShellTabId.timeline,
        AppShellTabId.sleep,
        AppShellTabId.boards,
      ];
      for (final id in unlockedIds) {
        final tab = appShellTabs.firstWhere((t) => t.id == id);
        expect(
          tab.isLocked,
          isFalse,
          reason: '${id.name} should not be locked',
        );
      }
    });
  });

  group('AppShellTab.isEnabled', () {
    final allEnabled = _allEnabled();

    test('home is always enabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.home);
      expect(tab.isEnabled(allEnabled), isTrue);
    });

    test('settings is always enabled', () {
      final tab = appShellTabs.firstWhere(
        (t) => t.id == AppShellTabId.settings,
      );
      expect(tab.isEnabled(allEnabled), isTrue);
    });

    test('members is always enabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.members);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(_withDisabled(chat: false)), isTrue);
    });

    test('chat is gated by chatEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.chat);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(_withDisabled(chat: false)), isFalse);
    });

    test('habits is gated by habitsEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.habits);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(_withDisabled(habits: false)), isFalse);
    });

    test('polls is gated by pollsEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.polls);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(_withDisabled(polls: false)), isFalse);
    });

    test('reminders is gated by remindersEnabled', () {
      final tab = appShellTabs.firstWhere(
        (t) => t.id == AppShellTabId.reminders,
      );
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(_withDisabled(reminders: false)), isFalse);
    });

    test('notes is gated by notesEnabled', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.notes);
      expect(tab.isEnabled(allEnabled), isTrue);
      expect(tab.isEnabled(_withDisabled(notes: false)), isFalse);
    });

    test('statistics is always enabled', () {
      final tab = appShellTabs.firstWhere(
        (t) => t.id == AppShellTabId.statistics,
      );
      expect(tab.isEnabled(allEnabled), isTrue);
    });

    test('all feature-gated tabs are enabled with all-enabled flags', () {
      const gatedIds = [
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.reminders,
        AppShellTabId.notes,
        AppShellTabId.sleep,
        AppShellTabId.boards,
      ];
      for (final id in gatedIds) {
        final tab = appShellTabs.firstWhere((t) => t.id == id);
        expect(
          tab.isEnabled(allEnabled),
          isTrue,
          reason: '${id.name} should be enabled with all-enabled flags',
        );
      }
    });
  });

  group('appShellTabs', () {
    test('has 12 entries', () {
      expect(appShellTabs, hasLength(12));
    });

    test('branch indices are 0 through 11', () {
      final indices = appShellTabs.map((t) => t.branchIndex).toList();
      expect(indices, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
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
        expect(
          ids,
          contains(value),
          reason: '${value.name} should be in appShellTabs',
        );
      }
    });
  });

  group('AppShellTabId.timeline', () {
    test('timeline is not in defaultNavBarTabIds', () {
      expect(defaultNavBarTabIds, isNot(contains('timeline')));
    });

    test('timeline tab isLocked = false', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.timeline);
      expect(tab.isLocked, isFalse);
    });

    test('timeline tab isEnabled regardless of feature flags', () {
      const allOff = (chat: false, polls: false, habits: false, sleep: false, notes: false, reminders: false, boards: false);
      const allOn  = (chat: true,  polls: true,  habits: true,  sleep: true,  notes: true,  reminders: true,  boards: true);
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.timeline);
      expect(tab.isEnabled(allOff), isTrue);
      expect(tab.isEnabled(allOn),  isTrue);
    });

    test('branch indices are consecutive 0..n-1', () {
      final indices = appShellTabs.map((t) => t.branchIndex).toList()..sort();
      expect(indices, List.generate(appShellTabs.length, (i) => i));
    });
  });

  group('defaultNavBarTabIds', () {
    test('contains exactly the expected 5 tab IDs in order', () {
      expect(defaultNavBarTabIds, [
        'home',
        'chat',
        'habits',
        'polls',
        'settings',
      ]);
    });

    test('has 5 entries', () {
      expect(defaultNavBarTabIds, hasLength(5));
    });
  });
}
