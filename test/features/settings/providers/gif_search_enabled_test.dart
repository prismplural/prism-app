import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

void main() {
  group('gifSearchEnabledProvider', () {
    ProviderContainer makeContainer({SystemSettings? settings}) {
      return ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            AsyncValue.data(settings ?? const SystemSettings()),
          ),
        ],
      );
    }

    test('returns true by default when settings has default values', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      expect(container.read(gifSearchEnabledProvider), isTrue);
    });

    test('returns false when gifSearchEnabled is false in settings', () {
      final container = makeContainer(
        settings: const SystemSettings(gifSearchEnabled: false),
      );
      addTearDown(container.dispose);

      expect(container.read(gifSearchEnabledProvider), isFalse);
    });

    test('returns true when gifSearchEnabled is explicitly true', () {
      final container = makeContainer(
        settings: const SystemSettings(gifSearchEnabled: true),
      );
      addTearDown(container.dispose);

      expect(container.read(gifSearchEnabledProvider), isTrue);
    });

    test('returns true when systemSettingsProvider is loading', () {
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider
              .overrideWithValue(const AsyncValue.loading()),
        ],
      );
      addTearDown(container.dispose);

      // Falls back to default true when data is not yet available.
      expect(container.read(gifSearchEnabledProvider), isTrue);
    });

    test('returns true when systemSettingsProvider has error', () {
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            AsyncValue.error(Exception('db error'), StackTrace.current),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Falls back to default true on error.
      expect(container.read(gifSearchEnabledProvider), isTrue);
    });
  });
}
