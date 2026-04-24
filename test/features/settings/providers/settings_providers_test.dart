import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart' as domain;
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

import '../../../helpers/fake_repositories.dart';

// Seed the ignore flag so that IgnoreSyncedAppearanceNotifier.build() returns
// the desired initial value without modifying any production code.
Future<ProviderContainer> makeContainerWithIgnore({
  bool ignoreSynced = false,
  domain.SystemSettings? settings,
  CornerStyle? cachedCornerStyle,
  domain.ThemeStyle? cachedThemeStyle,
}) async {
  SharedPreferences.setMockInitialValues({
    if (ignoreSynced) 'prism.pref.ignore_synced_appearance': true,
  });

  final fakeRepo = FakeSystemSettingsRepository();
  if (settings != null) fakeRepo.settings = settings;

  final container = ProviderContainer(
    overrides: [
      systemSettingsProvider.overrideWithValue(
        AsyncValue.data(fakeRepo.settings),
      ),
      systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
      if (cachedCornerStyle != null)
        cachedCornerStyleProvider.overrideWithValue(cachedCornerStyle),
      if (cachedThemeStyle != null)
        cachedThemeStyleProvider.overrideWithValue(cachedThemeStyle),
    ],
  );

  // Let the AsyncNotifier hydrate from SharedPreferences.
  await container.read(ignoreSyncedAppearanceProvider.future);
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // cornerStyleProvider
  // ---------------------------------------------------------------------------

  group('cornerStyleProvider', () {
    test('returns DB value (rounded) when ignoreSyncedAppearance is false',
        () async {
      final container = await makeContainerWithIgnore(
        ignoreSynced: false,
        settings: const domain.SystemSettings(
          cornerStyle: domain.CornerStyle.rounded,
        ),
      );
      addTearDown(container.dispose);

      expect(container.read(cornerStyleProvider), CornerStyle.rounded);
    });

    test('returns DB value (angular) when ignoreSyncedAppearance is false',
        () async {
      final container = await makeContainerWithIgnore(
        ignoreSynced: false,
        settings: const domain.SystemSettings(
          cornerStyle: domain.CornerStyle.angular,
        ),
      );
      addTearDown(container.dispose);

      expect(container.read(cornerStyleProvider), CornerStyle.angular);
    });

    test(
        'returns cached (local) value when ignoreSyncedAppearance is true',
        () async {
      // DB says angular, cached says rounded; with ignore=true we get rounded.
      final container = await makeContainerWithIgnore(
        ignoreSynced: true,
        settings: const domain.SystemSettings(
          cornerStyle: domain.CornerStyle.angular,
        ),
        cachedCornerStyle: CornerStyle.rounded,
      );
      addTearDown(container.dispose);

      expect(container.read(cornerStyleProvider), CornerStyle.rounded);
    });

    test('falls back to cached rounded when settings is loading', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeRepo = FakeSystemSettingsRepository();
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(const AsyncValue.loading()),
          systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
          cachedCornerStyleProvider.overrideWithValue(CornerStyle.angular),
        ],
      );
      addTearDown(container.dispose);

      await container.read(ignoreSyncedAppearanceProvider.future);

      expect(container.read(cornerStyleProvider), CornerStyle.angular);
    });
  });

  // ---------------------------------------------------------------------------
  // updateCornerStyle (SettingsNotifier)
  // ---------------------------------------------------------------------------

  group('updateCornerStyle (SettingsNotifier)', () {
    test('writes domain.CornerStyle.angular to repo and caches index 1',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fakeRepo = FakeSystemSettingsRepository();
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            AsyncValue.data(fakeRepo.settings),
          ),
          systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(settingsNotifierProvider.notifier)
          .updateCornerStyle(CornerStyle.angular);

      // Repo received the domain type with the correct value.
      expect(fakeRepo.settings.cornerStyle, domain.CornerStyle.angular);

      // SharedPreferences cache was written (index 1 = angular).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('prism.cache.theme_corner_style'), 1);
    });

    test('writes domain.CornerStyle.rounded to repo and caches index 0',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fakeRepo = FakeSystemSettingsRepository()
        ..settings = const domain.SystemSettings(
          cornerStyle: domain.CornerStyle.angular,
        );
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            AsyncValue.data(fakeRepo.settings),
          ),
          systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(settingsNotifierProvider.notifier)
          .updateCornerStyle(CornerStyle.rounded);

      expect(fakeRepo.settings.cornerStyle, domain.CornerStyle.rounded);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('prism.cache.theme_corner_style'), 0);
    });

    test(
        'enabling ignoreSyncedAppearance does not prevent writes — '
        'updateCornerStyle still goes through repo', () async {
      // Seed ignore=true in SharedPreferences.
      SharedPreferences.setMockInitialValues({
        'prism.pref.ignore_synced_appearance': true,
      });

      final fakeRepo = FakeSystemSettingsRepository();
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            AsyncValue.data(fakeRepo.settings),
          ),
          systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      // Hydrate so ignore=true is active.
      await container.read(ignoreSyncedAppearanceProvider.future);

      await container
          .read(settingsNotifierProvider.notifier)
          .updateCornerStyle(CornerStyle.angular);

      // Write still reached the repo.
      expect(fakeRepo.settings.cornerStyle, domain.CornerStyle.angular);
    });
  });

  // ---------------------------------------------------------------------------
  // ignoreSyncedAppearanceProvider (self-hydrating AsyncNotifier)
  // ---------------------------------------------------------------------------

  group('ignoreSyncedAppearanceProvider', () {
    test('defaults to false when no prefs entry exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(ignoreSyncedAppearanceProvider.future);
      expect(container.read(ignoreSyncedAppearanceProvider).value, isFalse);
    });

    test('reads true from SharedPreferences when pre-seeded', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.ignore_synced_appearance': true,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(ignoreSyncedAppearanceProvider.future);
      expect(container.read(ignoreSyncedAppearanceProvider).value, isTrue);
    });

    test('set(true) updates state and persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(ignoreSyncedAppearanceProvider.future);

      await container
          .read(ignoreSyncedAppearanceProvider.notifier)
          .set(true);

      expect(container.read(ignoreSyncedAppearanceProvider).value, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.ignore_synced_appearance'), isTrue);
    });

    test('set(false) updates state and persists false to SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.ignore_synced_appearance': true,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(ignoreSyncedAppearanceProvider.future);

      await container
          .read(ignoreSyncedAppearanceProvider.notifier)
          .set(false);

      expect(container.read(ignoreSyncedAppearanceProvider).value, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.ignore_synced_appearance'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // themeStyleProvider respects ignoreSyncedAppearance gate
  // ---------------------------------------------------------------------------

  group('themeStyleProvider ignoreSyncedAppearance gate', () {
    test(
        'returns cached style when ignoreSyncedAppearance is true, '
        'ignoring DB value', () async {
      // DB says OLED, cached says standard; with ignore=true we get standard.
      final container = await makeContainerWithIgnore(
        ignoreSynced: true,
        settings: const domain.SystemSettings(
          themeStyle: domain.ThemeStyle.oled,
        ),
        cachedThemeStyle: domain.ThemeStyle.standard,
      );
      addTearDown(container.dispose);

      expect(container.read(themeStyleProvider), domain.ThemeStyle.standard);
    });

    test('returns DB style when ignoreSyncedAppearance is false', () async {
      final container = await makeContainerWithIgnore(
        ignoreSynced: false,
        settings: const domain.SystemSettings(
          themeStyle: domain.ThemeStyle.oled,
        ),
        cachedThemeStyle: domain.ThemeStyle.standard,
      );
      addTearDown(container.dispose);

      expect(container.read(themeStyleProvider), domain.ThemeStyle.oled);
    });
  });

  // ---------------------------------------------------------------------------
  // useProxyTagsForAuthoringProvider (self-hydrating AsyncNotifier, local-only)
  // ---------------------------------------------------------------------------

  group('useProxyTagsForAuthoringProvider', () {
    test('defaults to true when no prefs entry exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      expect(
        container.read(useProxyTagsForAuthoringProvider).value,
        isTrue,
      );
    });

    test('reads false from SharedPreferences when pre-seeded', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      expect(
        container.read(useProxyTagsForAuthoringProvider).value,
        isFalse,
      );
    });

    test('reads true from SharedPreferences when pre-seeded', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      expect(
        container.read(useProxyTagsForAuthoringProvider).value,
        isTrue,
      );
    });

    test('set(true) flips a previously-false value and persists', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      await container
          .read(useProxyTagsForAuthoringProvider.notifier)
          .set(true);

      expect(
        container.read(useProxyTagsForAuthoringProvider).value,
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('prism.pref.use_proxy_tags_for_authoring'),
        isTrue,
      );
    });

    test('set(false) flips a previously-true value back', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      await container
          .read(useProxyTagsForAuthoringProvider.notifier)
          .set(false);

      expect(
        container.read(useProxyTagsForAuthoringProvider).value,
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('prism.pref.use_proxy_tags_for_authoring'),
        isFalse,
      );
    });
  });
}
