import 'package:flutter/foundation.dart' show TargetPlatform;
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
  domain.PaletteSource? cachedPaletteSource,
  String? cachedPaletteSeedColorHex,
  domain.PaletteMood? cachedPaletteMood,
  domain.PaletteContrast? cachedPaletteContrast,
  TargetPlatform? targetPlatform,
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
        cachedCornerStyleProvider.overrideWith(
          () => CachedCornerStyleNotifier(cachedCornerStyle),
        ),
      if (cachedThemeStyle != null)
        cachedThemeStyleProvider.overrideWith(
          () => CachedThemeStyleNotifier(cachedThemeStyle),
        ),
      if (cachedPaletteSource != null)
        cachedPaletteSourceProvider.overrideWith(
          () => CachedPaletteSourceNotifier(cachedPaletteSource),
        ),
      if (cachedPaletteSeedColorHex != null)
        cachedPaletteSeedColorHexProvider.overrideWith(
          () => CachedPaletteSeedColorHexNotifier(cachedPaletteSeedColorHex),
        ),
      if (cachedPaletteMood != null)
        cachedPaletteMoodProvider.overrideWith(
          () => CachedPaletteMoodNotifier(cachedPaletteMood),
        ),
      if (cachedPaletteContrast != null)
        cachedPaletteContrastProvider.overrideWith(
          () => CachedPaletteContrastNotifier(cachedPaletteContrast),
        ),
      if (targetPlatform != null)
        targetPlatformProvider.overrideWithValue(targetPlatform),
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
    test(
      'returns DB value (rounded) when ignoreSyncedAppearance is false',
      () async {
        final container = await makeContainerWithIgnore(
          ignoreSynced: false,
          settings: const domain.SystemSettings(
            cornerStyle: domain.CornerStyle.rounded,
          ),
        );
        addTearDown(container.dispose);

        expect(container.read(cornerStyleProvider), CornerStyle.rounded);
      },
    );

    test(
      'returns DB value (angular) when ignoreSyncedAppearance is false',
      () async {
        final container = await makeContainerWithIgnore(
          ignoreSynced: false,
          settings: const domain.SystemSettings(
            cornerStyle: domain.CornerStyle.angular,
          ),
        );
        addTearDown(container.dispose);

        expect(container.read(cornerStyleProvider), CornerStyle.angular);
      },
    );

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
      },
    );

    test('falls back to cached rounded when settings is loading', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeRepo = FakeSystemSettingsRepository();
      final container = ProviderContainer(
        overrides: [
          systemSettingsProvider.overrideWithValue(const AsyncValue.loading()),
          systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
          cachedCornerStyleProvider.overrideWith(
            () => CachedCornerStyleNotifier(CornerStyle.angular),
          ),
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
    test(
      'writes domain.CornerStyle.angular to repo and caches index 1',
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
      },
    );

    test(
      'writes domain.CornerStyle.rounded to repo and caches index 0',
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
      },
    );

    test('enabling ignoreSyncedAppearance does not prevent writes — '
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
      expect(container.read(cornerStyleProvider), CornerStyle.angular);
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

      await container.read(ignoreSyncedAppearanceProvider.notifier).set(true);

      expect(container.read(ignoreSyncedAppearanceProvider).value, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.ignore_synced_appearance'), isTrue);
    });

    test(
      'set(false) updates state and persists false to SharedPreferences',
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
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Appearance providers respect ignoreSyncedAppearance gate
  // ---------------------------------------------------------------------------

  group('appearance providers ignoreSyncedAppearance gate', () {
    test('returns cached style when ignoreSyncedAppearance is true, '
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

    test(
      'theme style writes update local appearance state while ignoring sync',
      () async {
        SharedPreferences.setMockInitialValues({
          'prism.pref.ignore_synced_appearance': true,
        });
        final fakeRepo = FakeSystemSettingsRepository()
          ..settings = const domain.SystemSettings(
            themeStyle: domain.ThemeStyle.standard,
          );
        final container = ProviderContainer(
          overrides: [
            systemSettingsProvider.overrideWithValue(
              AsyncValue.data(fakeRepo.settings),
            ),
            systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
            cachedThemeStyleProvider.overrideWith(
              () => CachedThemeStyleNotifier(domain.ThemeStyle.standard),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(ignoreSyncedAppearanceProvider.future);
        expect(container.read(themeStyleProvider), domain.ThemeStyle.standard);

        await container
            .read(settingsNotifierProvider.notifier)
            .updateThemeStyle(domain.ThemeStyle.oled);

        expect(fakeRepo.settings.themeStyle, domain.ThemeStyle.oled);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('prism.cache.theme_style'), 'oled');
        expect(container.read(themeStyleProvider), domain.ThemeStyle.oled);
      },
    );

    test(
      'theme brightness writes update local appearance state while ignoring sync',
      () async {
        SharedPreferences.setMockInitialValues({
          'prism.pref.ignore_synced_appearance': true,
        });
        final fakeRepo = FakeSystemSettingsRepository()
          ..settings = const domain.SystemSettings(
            themeBrightness: domain.ThemeBrightness.system,
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

        await container.read(ignoreSyncedAppearanceProvider.future);
        expect(
          container.read(themeBrightnessProvider),
          domain.ThemeBrightness.system,
        );

        await container
            .read(settingsNotifierProvider.notifier)
            .updateThemeBrightness(domain.ThemeBrightness.dark);

        expect(fakeRepo.settings.themeBrightness, domain.ThemeBrightness.dark);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('prism.cache.theme_brightness'), 'dark');
        expect(
          container.read(themeBrightnessProvider),
          domain.ThemeBrightness.dark,
        );
      },
    );

    test(
      'accent color writes update local appearance state while ignoring sync',
      () async {
        SharedPreferences.setMockInitialValues({
          'prism.pref.ignore_synced_appearance': true,
        });
        final fakeRepo = FakeSystemSettingsRepository()
          ..settings = const domain.SystemSettings(accentColorHex: '#9070A0');
        final container = ProviderContainer(
          overrides: [
            systemSettingsProvider.overrideWithValue(
              AsyncValue.data(fakeRepo.settings),
            ),
            systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(ignoreSyncedAppearanceProvider.future);
        expect(container.read(accentColorHexProvider), isNull);

        await container
            .read(settingsNotifierProvider.notifier)
            .updateAccentColor('#123456');

        expect(fakeRepo.settings.accentColorHex, '#123456');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('prism.cache.accent_color_hex'), '#123456');
        expect(container.read(accentColorHexProvider), '#123456');
      },
    );
  });

  group('effectiveThemeStyleProvider', () {
    test('keeps materialYou on Android', () async {
      final container = await makeContainerWithIgnore(
        settings: const domain.SystemSettings(
          themeStyle: domain.ThemeStyle.materialYou,
        ),
        targetPlatform: TargetPlatform.android,
      );
      addTearDown(container.dispose);

      expect(
        container.read(effectiveThemeStyleProvider),
        domain.ThemeStyle.materialYou,
      );
    });

    test('keeps synced materialYou on iOS', () async {
      final container = await makeContainerWithIgnore(
        settings: const domain.SystemSettings(
          themeStyle: domain.ThemeStyle.materialYou,
        ),
        targetPlatform: TargetPlatform.iOS,
      );
      addTearDown(container.dispose);

      expect(
        container.read(effectiveThemeStyleProvider),
        domain.ThemeStyle.materialYou,
      );
    });

    test('keeps cached materialYou on iOS when ignore=true', () async {
      final container = await makeContainerWithIgnore(
        ignoreSynced: true,
        settings: const domain.SystemSettings(
          themeStyle: domain.ThemeStyle.oled,
        ),
        cachedThemeStyle: domain.ThemeStyle.materialYou,
        targetPlatform: TargetPlatform.iOS,
      );
      addTearDown(container.dispose);

      expect(container.read(themeStyleProvider), domain.ThemeStyle.materialYou);
      expect(
        container.read(effectiveThemeStyleProvider),
        domain.ThemeStyle.materialYou,
      );
    });
  });

  group('palette providers', () {
    test(
      'returns DB palette values when ignoreSyncedAppearance is false',
      () async {
        final container = await makeContainerWithIgnore(
          settings: const domain.SystemSettings(
            paletteSource: domain.PaletteSource.custom,
            paletteSeedColorHex: '#123456',
            paletteMood: domain.PaletteMood.vibrant,
            paletteContrast: domain.PaletteContrast.high,
          ),
          cachedPaletteSource: domain.PaletteSource.device,
          cachedPaletteSeedColorHex: '#654321',
          cachedPaletteMood: domain.PaletteMood.tonal,
          cachedPaletteContrast: domain.PaletteContrast.soft,
          targetPlatform: TargetPlatform.android,
        );
        addTearDown(container.dispose);

        expect(
          container.read(paletteSourceProvider),
          domain.PaletteSource.custom,
        );
        expect(container.read(paletteSeedColorHexProvider), '#123456');
        expect(container.read(paletteMoodProvider), domain.PaletteMood.vibrant);
        expect(
          container.read(paletteContrastProvider),
          domain.PaletteContrast.high,
        );
      },
    );

    test(
      'returns cached palette values when ignoreSyncedAppearance is true',
      () async {
        final container = await makeContainerWithIgnore(
          ignoreSynced: true,
          settings: const domain.SystemSettings(
            paletteSource: domain.PaletteSource.custom,
            paletteSeedColorHex: '#123456',
            paletteMood: domain.PaletteMood.vibrant,
            paletteContrast: domain.PaletteContrast.high,
          ),
          cachedPaletteSource: domain.PaletteSource.device,
          cachedPaletteSeedColorHex: '#654321',
          cachedPaletteMood: domain.PaletteMood.monochrome,
          cachedPaletteContrast: domain.PaletteContrast.soft,
          targetPlatform: TargetPlatform.android,
        );
        addTearDown(container.dispose);

        expect(
          container.read(paletteSourceProvider),
          domain.PaletteSource.device,
        );
        expect(container.read(paletteSeedColorHexProvider), '#654321');
        expect(
          container.read(paletteMoodProvider),
          domain.PaletteMood.monochrome,
        );
        expect(
          container.read(paletteContrastProvider),
          domain.PaletteContrast.soft,
        );
      },
    );

    test('gates device palette source to custom off Android', () async {
      final container = await makeContainerWithIgnore(
        settings: const domain.SystemSettings(
          paletteSource: domain.PaletteSource.device,
        ),
        targetPlatform: TargetPlatform.iOS,
      );
      addTearDown(container.dispose);

      expect(
        container.read(paletteSourcePreferenceProvider),
        domain.PaletteSource.device,
      );
      expect(
        container.read(paletteSourceProvider),
        domain.PaletteSource.custom,
      );
    });
  });

  group('palette updates (SettingsNotifier)', () {
    test('writes palette fields to repo and SharedPreferences cache', () async {
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

      final notifier = container.read(settingsNotifierProvider.notifier);
      await notifier.updatePaletteSource(domain.PaletteSource.device);
      await notifier.updatePaletteSeedColorHex('#ABCDEF');
      await notifier.updatePaletteMood(domain.PaletteMood.expressive);
      await notifier.updatePaletteContrast(domain.PaletteContrast.high);

      expect(fakeRepo.settings.paletteSource, domain.PaletteSource.device);
      expect(fakeRepo.settings.paletteSeedColorHex, '#ABCDEF');
      expect(fakeRepo.settings.paletteMood, domain.PaletteMood.expressive);
      expect(fakeRepo.settings.paletteContrast, domain.PaletteContrast.high);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('prism.cache.palette_source'), 'device');
      expect(prefs.getString('prism.cache.palette_seed_color_hex'), '#ABCDEF');
      expect(prefs.getString('prism.cache.palette_mood'), 'expressive');
      expect(prefs.getString('prism.cache.palette_contrast'), 'high');
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
      expect(container.read(useProxyTagsForAuthoringProvider).value, isTrue);
    });

    test('reads false from SharedPreferences when pre-seeded', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      expect(container.read(useProxyTagsForAuthoringProvider).value, isFalse);
    });

    test('reads true from SharedPreferences when pre-seeded', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      expect(container.read(useProxyTagsForAuthoringProvider).value, isTrue);
    });

    test('set(true) flips a previously-false value and persists', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(useProxyTagsForAuthoringProvider.future);
      await container.read(useProxyTagsForAuthoringProvider.notifier).set(true);

      expect(container.read(useProxyTagsForAuthoringProvider).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.use_proxy_tags_for_authoring'), isTrue);
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

      expect(container.read(useProxyTagsForAuthoringProvider).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.use_proxy_tags_for_authoring'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // hardLockSyncOnAppLockProvider (self-hydrating AsyncNotifier, local-only)
  // ---------------------------------------------------------------------------

  group('hardLockSyncOnAppLockProvider', () {
    test('defaults to false when no prefs entry exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(hardLockSyncOnAppLockProvider.future);
      expect(container.read(hardLockSyncOnAppLockProvider).value, isFalse);
    });

    test('reads true from SharedPreferences when pre-seeded', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.hard_lock_sync_on_app_lock': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(hardLockSyncOnAppLockProvider.future);
      expect(container.read(hardLockSyncOnAppLockProvider).value, isTrue);
    });

    test('set(true) flips a previously-false value and persists', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.hard_lock_sync_on_app_lock': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(hardLockSyncOnAppLockProvider.future);
      await container.read(hardLockSyncOnAppLockProvider.notifier).set(true);

      expect(container.read(hardLockSyncOnAppLockProvider).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.hard_lock_sync_on_app_lock'), isTrue);
    });

    test('set(false) flips a previously-true value back', () async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.hard_lock_sync_on_app_lock': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(hardLockSyncOnAppLockProvider.future);
      await container.read(hardLockSyncOnAppLockProvider.notifier).set(false);

      expect(container.read(hardLockSyncOnAppLockProvider).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.hard_lock_sync_on_app_lock'), isFalse);
    });
  });
}
