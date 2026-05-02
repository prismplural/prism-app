import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';

void main() {
  group('AppShellTabId.sleep', () {
    test('enum value exists', () {
      expect(AppShellTabId.values, contains(AppShellTabId.sleep));
    });

    test('name is sleep', () {
      expect(AppShellTabId.sleep.name, 'sleep');
    });

    test('is in appShellTabs', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.sleep);
      expect(tab, isNotNull);
    });

    test('root location is /sleep', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.sleep);
      expect(tab.rootLocation, '/sleep');
    });

    test('branch index is 10', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.sleep);
      expect(tab.branchIndex, 10);
    });

    test('is not locked', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.sleep);
      expect(tab.isLocked, isFalse);
    });

    test('isEnabled true when flags.sleep is true', () {
      const flags = (
        chat: true,
        polls: true,
        habits: true,
        sleep: true,
        notes: true,
        reminders: true,
      );
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.sleep);
      expect(tab.isEnabled(flags), isTrue);
    });

    test('isEnabled false when flags.sleep is false', () {
      const flags = (
        chat: true,
        polls: true,
        habits: true,
        sleep: false,
        notes: true,
        reminders: true,
      );
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.sleep);
      expect(tab.isEnabled(flags), isFalse);
    });

    test('is NOT in defaultNavBarTabIds', () {
      expect(defaultNavBarTabIds, isNot(contains('sleep')));
    });

    test('is NOT in defaultNavBarOverflowTabIds', () {
      expect(defaultNavBarOverflowTabIds, isNot(contains('sleep')));
    });
  });

  group('appShellTabs with sleep', () {
    test('has 11 entries', () {
      expect(appShellTabs, hasLength(11));
    });

    test('branch indices are consecutive 0..10', () {
      final indices = appShellTabs.map((t) => t.branchIndex).toList()..sort();
      expect(indices, List.generate(11, (i) => i));
    });

    test('no duplicate branch indices', () {
      final indices = appShellTabs.map((t) => t.branchIndex).toSet();
      expect(indices, hasLength(appShellTabs.length));
    });

    test('no duplicate root locations', () {
      final locations = appShellTabs.map((t) => t.rootLocation).toSet();
      expect(locations, hasLength(appShellTabs.length));
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
}
