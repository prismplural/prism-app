import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

void main() {
  group('localeOverrideProvider', () {
    ProviderContainer makeContainer({SystemSettings? settings}) {
      return ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            AsyncValue.data(settings ?? const SystemSettings()),
          ),
        ],
      );
    }

    test('returns null by default (system locale)', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(container.read(localeOverrideProvider), isNull);
    });

    test('returns Locale(es) when localeOverride is es', () {
      final container = makeContainer(
        settings: const SystemSettings(localeOverride: 'es'),
      );
      addTearDown(container.dispose);
      expect(container.read(localeOverrideProvider), const Locale('es'));
    });

    test('returns Locale(en) when localeOverride is en', () {
      final container = makeContainer(
        settings: const SystemSettings(localeOverride: 'en'),
      );
      addTearDown(container.dispose);
      expect(container.read(localeOverrideProvider), const Locale('en'));
    });

    test('returns null for empty string', () {
      final container = makeContainer(
        settings: const SystemSettings(localeOverride: ''),
      );
      addTearDown(container.dispose);
      expect(container.read(localeOverrideProvider), isNull);
    });

    test('returns null for unsupported locale code', () {
      final container = makeContainer(
        settings: const SystemSettings(localeOverride: 'zh'),
      );
      addTearDown(container.dispose);
      expect(container.read(localeOverrideProvider), isNull);
    });

    test('returns null when systemSettingsProvider is loading', () {
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(const AsyncValue.loading()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(localeOverrideProvider), isNull);
    });

    test('returns null when systemSettingsProvider has error', () {
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            AsyncValue.error(Exception('db error'), StackTrace.current),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(localeOverrideProvider), isNull);
    });
  });
}
