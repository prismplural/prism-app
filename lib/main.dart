import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
// import 'package:workmanager/workmanager.dart';

import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/core/reset/full_reset_service.dart';
import 'package:prism_plurality/core/reset/reset_recovery_app.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/domain/models/models.dart' hide CornerStyle;
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
// import 'package:prism_plurality/features/pluralkit/services/pluralkit_background_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BootTimings.mark('binding');

  // Flip the PK sync-log bus's main-isolate guard ON before runApp so any
  // PkSyncEventBus.emit call from this isolate is delivered. The
  // workmanager background isolate never calls this, so emits there
  // silently no-op (see pluralkit_background_service.dart).
  markPkBusMainIsolate();

  // Global error boundaries — install immediately so startup failures are reported.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorReportingService.instance.report(
      details.exceptionAsString(),
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReportingService.instance.report(error.toString(), stackTrace: stack);
    return kReleaseMode; // In debug, let the error propagate to show the error overlay
  };

  tz.initializeTimeZones();
  if (!kIsWeb) {
    final localTz = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(localTz));
  }

  final prefs = await SharedPreferences.getInstance();
  await _applyStartupScreenPrivacy(prefs);

  // iOS Keychain and platform key stores can survive app uninstall/reinstall.
  // Before any providers or databases hydrate release app state, make a fresh
  // install clear secure residue when the app-private SharedPreferences
  // sentinel is missing. If app files still exist, boot a DB-free recovery
  // shell instead of silently deleting data.
  if (kReleaseMode) {
    final resetStartup = await runFreshInstallResidueGuard();
    switch (resetStartup.mode) {
      case ResetStartupMode.normal:
        break;
      case ResetStartupMode.freshInstallRecoveryRequired:
        runApp(
          const ResetRecoveryApp(
            mode: ResetRecoveryScreenMode.freshInstallAnomaly,
          ),
        );
        return;
    }
  }
  await migrateRelayUrl();

  // On iOS/macOS, the Rust library is statically linked via -force_load in the
  // podspec. Use ExternalLibrary.process() to find symbols in the current process
  // rather than trying to dlopen a .framework bundle.
  if (Platform.isIOS || Platform.isMacOS) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  } else {
    await RustLib.init();
  }

  // Show a plain error message instead of the red/yellow error screen in
  // release builds. Cannot use Theme.of or l10n here — runs outside the widget tree.
  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Something went wrong. Please restart the app.',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    };
  }

  // Read cached theme prefs so the first frame uses the correct colors,
  // avoiding a white flash while the Drift DB loads.
  final cachedBrightness =
      ThemeBrightness.values.firstWhereOrNull(
        (b) => b.name == prefs.getString('prism.cache.theme_brightness'),
      ) ??
      ThemeBrightness.system;
  final cachedStyle =
      ThemeStyle.values.firstWhereOrNull(
        (s) => s.name == prefs.getString('prism.cache.theme_style'),
      ) ??
      ThemeStyle.standard;
  final cachedPaletteSourceName = prefs.getString('prism.cache.palette_source');
  final cachedPaletteSource =
      PaletteSource.values.firstWhereOrNull(
        (s) => s.name == cachedPaletteSourceName,
      ) ??
      (cachedStyle == ThemeStyle.materialYou
          ? PaletteSource.device
          : PaletteSource.custom);
  final cachedAccentColorHex = prefs.getString('prism.cache.accent_color_hex');
  final cachedPaletteSeedColorHex =
      prefs.getString('prism.cache.palette_seed_color_hex') ?? '#9070A0';
  final cachedPaletteMood =
      PaletteMood.values.firstWhereOrNull(
        (m) => m.name == prefs.getString('prism.cache.palette_mood'),
      ) ??
      PaletteMood.tonal;
  final cachedPaletteContrast =
      PaletteContrast.values.firstWhereOrNull(
        (c) => c.name == prefs.getString('prism.cache.palette_contrast'),
      ) ??
      PaletteContrast.standard;
  final cornerIndex = prefs.getInt('prism.cache.theme_corner_style') ?? 0;
  final cachedCornerStyle = CornerStyle.values[cornerIndex];

  BootTimings.mark('runApp');
  runApp(
    ProviderScope(
      overrides: [
        cachedThemeBrightnessProvider.overrideWith(
          () => CachedThemeBrightnessNotifier(cachedBrightness),
        ),
        cachedThemeStyleProvider.overrideWith(
          () => CachedThemeStyleNotifier(cachedStyle),
        ),
        cachedPaletteSourceProvider.overrideWith(
          () => CachedPaletteSourceNotifier(cachedPaletteSource),
        ),
        cachedAccentColorHexProvider.overrideWith(
          () => CachedAccentColorHexNotifier(cachedAccentColorHex),
        ),
        cachedPaletteSeedColorHexProvider.overrideWith(
          () => CachedPaletteSeedColorHexNotifier(cachedPaletteSeedColorHex),
        ),
        cachedPaletteMoodProvider.overrideWith(
          () => CachedPaletteMoodNotifier(cachedPaletteMood),
        ),
        cachedPaletteContrastProvider.overrideWith(
          () => CachedPaletteContrastNotifier(cachedPaletteContrast),
        ),
        cachedCornerStyleProvider.overrideWith(
          () => CachedCornerStyleNotifier(cachedCornerStyle),
        ),
      ],
      // Explicit retry filter — prevent infinite retry on programmer bugs.
      retry: (retryCount, error) {
        // Don't retry format/type errors (programmer bugs)
        if (error is FormatException || error is TypeError) return null;
        // Max 3 retries with exponential backoff
        if (retryCount >= 3) return null;
        return Duration(seconds: 1 << retryCount); // 1s, 2s, 4s
      },
      observers: [if (kDebugMode) _DebugProviderObserver()],
      child: const PrismApp(),
    ),
  );

  _scheduleLinuxEmojiFontLoad();

  // TODO(background-sync): workmanager initialization is intentionally disabled.
  // callbackDispatcher in pluralkit_background_service.dart is a no-op stub.
  // Before enabling, a lightweight background entry point is needed that can
  // bootstrap the Rust sync engine in a background isolate without the full
  // Riverpod provider graph. Design and track this in a docs/plans/ file before
  // implementing.
  // if (Platform.isIOS || Platform.isAndroid) {
  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     Workmanager().initialize(callbackDispatcher);
  //   });
  // }
}

void _scheduleLinuxEmojiFontLoad() {
  if (kIsWeb || !Platform.isLinux) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_loadLinuxEmojiFont());
  });
}

Future<void> _loadLinuxEmojiFont() async {
  // The .ttf is platform-gated in pubspec.yaml (`platforms: [linux]`) so it
  // only ships in Linux builds. AppTheme's Linux text theme names this family
  // as a fallback; loading it after the first frame keeps startup responsive.
  final loader = FontLoader('NotoColorEmoji')
    ..addFont(rootBundle.load('assets/fonts/NotoColorEmoji.ttf'));
  await loader.load();
}

/// Logs Riverpod provider errors in debug builds.
///
/// Only logs [AsyncError] state transitions and [providerDidFail] events to
/// avoid flooding the console with every state change.
final class _DebugProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (newValue is AsyncError) {
      debugPrint(
        '[Riverpod] ${context.provider.name ?? context.provider.runtimeType}: '
        'ERROR ${newValue.error}',
      );
    }
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[Riverpod] ${context.provider.name ?? context.provider.runtimeType}: '
      'FAILED $error',
    );
  }
}

Future<void> _applyStartupScreenPrivacy(SharedPreferences prefs) async {
  // Apply the Screen Privacy preference BEFORE any first frame, including the
  // reset recovery shell, so an app-switcher snapshot is protected when the
  // user already enabled the toggle.
  final screenPrivacyEnabled =
      prefs.getBool('prism.pref.screen_privacy_enabled') ?? false;
  if (screenPrivacyEnabled && (Platform.isAndroid || Platform.isIOS)) {
    await ScreenSecurityService.setGlobalEnabled(true);
  }
}
