import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';

void main() {
  group('AppShellTabId.media', () {
    test('enum value exists', () {
      expect(AppShellTabId.values, contains(AppShellTabId.media));
    });

    test('name is media', () {
      expect(AppShellTabId.media.name, 'media');
    });

    test('is in appShellTabs', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.media);
      expect(tab, isNotNull);
    });

    test('root location is /media', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.media);
      expect(tab.rootLocation, '/media');
      expect(tab.rootLocation, AppRoutePaths.media);
    });

    test('branch index is 13', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.media);
      expect(tab.branchIndex, 13);
    });

    test('is not locked (can be reordered/removed)', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.media);
      expect(tab.isLocked, isFalse);
    });

    test('is not required (opt-in, can be left out of the nav)', () {
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.media);
      expect(tab.isRequired, isFalse);
    });

    test('isEnabled is true regardless of feature flags (not gated)', () {
      const allOff = (
        chat: false,
        polls: false,
        habits: false,
        sleep: false,
        notes: false,
        reminders: false,
        boards: false,
      );
      const allOn = (
        chat: true,
        polls: true,
        habits: true,
        sleep: true,
        notes: true,
        reminders: true,
        boards: true,
      );
      final tab = appShellTabs.firstWhere((t) => t.id == AppShellTabId.media);
      expect(tab.isEnabled(allOff), isTrue);
      expect(tab.isEnabled(allOn), isTrue);
    });

    test('is NOT in defaultNavBarTabIds (off by default)', () {
      expect(defaultNavBarTabIds, isNot(contains('media')));
    });

    test('is NOT in defaultNavBarOverflowTabIds (off by default)', () {
      expect(defaultNavBarOverflowTabIds, isNot(contains('media')));
    });
  });
}
