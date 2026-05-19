import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FontLoader, SystemNavigator, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
// import 'package:workmanager/workmanager.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/core/reset/full_reset_service.dart';
import 'package:prism_plurality/core/reset/reset_recovery_app.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/build_info.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';
import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/models.dart' hide CornerStyle;
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
// import 'package:prism_plurality/features/pluralkit/services/pluralkit_background_service.dart';
import 'app.dart';

// TODO(banner-widget): an in-app "Sync paused — re-pair to resume" banner
// should be inserted at the top-level scaffold (the home shell — see
// `lib/app.dart` / the main `Scaffold` it builds) and driven by
// `keychainDegradedStateProvider`. The state plumbing is already in place
// via §8 (`KeychainDegradedStateService.updateSlot('syncKey', unreadable)`
// gets called by `probeSyncDatabaseStartup` on the sync-only unrecoverable
// branch). All that's missing is the visible banner widget that watches
// `keychainDegradedStateProvider` and renders the string returned by
// `deriveDegradedBannerMessage`.

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
      case ResetStartupMode.keychainUnreadable:
        // The fresh-install guard never returns this mode itself — it's
        // produced downstream by the §6 probe branch below. Defensive switch
        // arm for type completeness.
        break;
    }
  }

  // ── §6 boot probes ──────────────────────────────────────────────────────
  //
  // App DB probe first; sync DB probe consumes the in-memory app key for
  // cross-DB recovery candidates (§5).
  //
  // §10 captures a per-boot diagnostic threaded into the recovery UI via
  // [bootSecureStorageDiagnosticProvider]. Snapshot the keychain-repair
  // pending flag BEFORE the write-back attempt so the diagnostic records
  // both "was set when boot started" and "was the write-back attempted".
  final keychainRepairPendingBeforeBoot = await _safeIsKeychainRepairPending();

  final appProbe = await _safeProbeAppDb();
  final syncProbe = await _safeProbeSyncDb(
    verifiedAppDbKey: appProbe.keyInMemory,
  );

  // Opportunistic keychain repair write-back. If the app DB probe recovered
  // via a sync slot, the `keychain_repair_pending` flag is set; this attempt
  // tries to rewrite the verified key into the primary slot. Never throws,
  // never blocks boot. Capture whether we attempted and the result for the
  // diagnostic.
  var writebackAttempted = false;
  KeychainRepairWritebackResult? writebackResult;
  if (appProbe.keyInMemory != null && keychainRepairPendingBeforeBoot == true) {
    writebackAttempted = true;
    final pendingAfter =
        await _safeAttemptKeychainRepairWriteback(appProbe.keyInMemory!);
    if (pendingAfter == false) {
      writebackResult = KeychainRepairWritebackResult.ok;
    } else if (pendingAfter == null) {
      // Couldn't read SharedPrefs — best-effort classify as cipher_failure
      // since the underlying write must have thrown.
      writebackResult = KeychainRepairWritebackResult.cipherFailure;
    } else {
      writebackResult = KeychainRepairWritebackResult.cipherFailure;
    }
  } else if (appProbe.keyInMemory != null) {
    // Call through anyway so the no-op fast path is exercised on every
    // boot (the function early-returns when the flag is unset). Tracked
    // as `noop` in the diagnostic.
    await _safeAttemptKeychainRepairWriteback(appProbe.keyInMemory!);
    writebackResult = KeychainRepairWritebackResult.noop;
  }

  // Build the §10 combined diagnostic. The app and sync probes each
  // returned a diagnostic populated with their own slot outcomes and
  // states; we merge them and attach the boot-level fields (write-back
  // result, runtime DEK device state, app build metadata).
  final combinedDiagnostic = await _buildBootDiagnostic(
    appProbe: appProbe,
    syncProbe: syncProbe,
    keychainRepairPendingBeforeBoot: keychainRepairPendingBeforeBoot,
    writebackAttempted: writebackAttempted,
    writebackResult: writebackResult,
  );

  // App DB unrecoverable → full-screen keychain-unreadable recovery. The
  // sync probe state doesn't matter at this point. ResetRecoveryApp
  // injects [bootSecureStorageDiagnosticProvider] internally so children
  // can read the diagnostic via Riverpod when they don't have a direct
  // reference.
  if (appProbe.state == DbStartupState.unrecoverable) {
    runApp(
      ResetRecoveryApp(
        mode: ResetRecoveryScreenMode.keychainUnreadable,
        diagnostic: combinedDiagnostic,
      ),
    );
    return;
  }

  // Sync DB only unrecoverable → continue boot in degraded mode. The §8
  // KeychainDegradedStateService transitions were already written by
  // `probeSyncDatabaseStartup` itself (syncKey + syncCredentials →
  // unreadable). The in-app banner picks this up — see top-of-file TODO.
  // The combined diagnostic is still threaded into the riverpod tree so
  // the in-app banner / settings entry can read it.

  // ── Migrations and platform init (moved post-probe per §6) ──────────────

  final windowsDataMigration =
      await migrateWindowsLegacyAppSupportDirIfNeeded();
  if (windowsDataMigration.shouldBlockStartup) {
    runApp(
      _WindowsDataMigrationBlockedApp(reason: windowsDataMigration.reason),
    );
    return;
  }

  await migrateRelayUrl();

  try {
    tz.initializeTimeZones();
    if (!kIsWeb) {
      final localTz = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(localTz));
    }
  } catch (e) {
    debugPrint('[BOOT] Timezone init failed (non-fatal): $e');
  }

  final prefs = await SharedPreferences.getInstance();
  try {
    await _applyStartupScreenPrivacy(prefs);
  } catch (e) {
    debugPrint('[BOOT] Screen privacy init failed (non-fatal): $e');
  }

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
        // §6 probe results threaded into the riverpod tree. These overrides
        // satisfy the throw-by-default providers declared in §3/§5.
        verifiedStartupKeyProvider.overrideWithValue(appProbe.keyInMemory),
        syncDatabaseStartupProvider.overrideWithValue(syncProbe),
        // §10 — make the captured per-boot diagnostic reachable by the
        // in-app banner / settings entry / recovery UI.
        bootSecureStorageDiagnosticProvider
            .overrideWithValue(combinedDiagnostic),
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

/// Wraps [probeAppDatabaseStartup] so any unexpected throw becomes a
/// synthetic unrecoverable report. The probe itself already catches
/// classified secure-storage failures; this is belt-and-braces.
Future<DbStartupReport> _safeProbeAppDb() async {
  try {
    return await probeAppDatabaseStartup();
  } catch (e, st) {
    debugPrint('[BOOT] probeAppDatabaseStartup threw — synthesising '
        'unrecoverable report: $e\n$st');
    return DbStartupReport(
      state: DbStartupState.unrecoverable,
      keyInMemory: null,
      usedRecoverySlot: null,
      diagnostic: SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: <String, String>{'probe': 'threw: $e'},
      ),
    );
  }
}

/// Wraps [probeSyncDatabaseStartup] so any unexpected throw becomes a
/// synthetic unrecoverable report. The probe itself already catches
/// classified secure-storage failures; this is belt-and-braces.
Future<DbStartupReport> _safeProbeSyncDb({required String? verifiedAppDbKey}) async {
  try {
    return await probeSyncDatabaseStartup(verifiedAppDbKey: verifiedAppDbKey);
  } catch (e, st) {
    debugPrint('[BOOT] probeSyncDatabaseStartup threw — synthesising '
        'unrecoverable report: $e\n$st');
    return DbStartupReport(
      state: DbStartupState.unrecoverable,
      keyInMemory: null,
      usedRecoverySlot: null,
      diagnostic: SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: <String, String>{'probe': 'threw: $e'},
      ),
    );
  }
}

/// Best-effort read of the keychain-repair pending flag for the §10
/// diagnostic. Returns null when SharedPreferences itself is unreachable
/// — the diagnostic still serializes, just with a null slot for the
/// field rather than a lie.
Future<bool?> _safeIsKeychainRepairPending() async {
  try {
    return await isKeychainRepairPending();
  } catch (e, st) {
    debugPrint('[BOOT] isKeychainRepairPending threw: $e\n$st');
    return null;
  }
}

/// Wraps [attemptKeychainRepairWriteback] and returns the
/// post-write-back state of the `keychain_repair_pending` flag (or null
/// when SharedPreferences itself is unreachable).
Future<bool?> _safeAttemptKeychainRepairWriteback(String key) async {
  try {
    await attemptKeychainRepairWriteback(key);
  } catch (e, st) {
    debugPrint('[BOOT] attemptKeychainRepairWriteback threw: $e\n$st');
  }
  return _safeIsKeychainRepairPending();
}

/// Build the combined §10 diagnostic from the app + sync probe results
/// and the boot-level fields. Reaches into the Android runtime DEK
/// device state via the existing platform channel that
/// [DeviceBoundRuntimeDekStore] already exposes.
Future<SecureStorageDiagnostic> _buildBootDiagnostic({
  required DbStartupReport appProbe,
  required DbStartupReport syncProbe,
  required bool? keychainRepairPendingBeforeBoot,
  required bool writebackAttempted,
  required KeychainRepairWritebackResult? writebackResult,
}) async {
  // Pull the runtime DEK device-state map off the existing
  // `runtime_dek_wrap` channel. The full diagnostics map nests
  // `device_state` inside it (see MainActivity.kt#collectRuntimeDekDiagnostics);
  // we surface the whole map so consumers can correlate alias presence
  // with device-locked state.
  Map<String, dynamic>? runtimeDekDeviceState;
  try {
    runtimeDekDeviceState =
        await const DeviceBoundRuntimeDekStore().getDiagnostics();
  } catch (e) {
    debugPrint('[BOOT] runtime DEK diagnostics failed: $e');
  }

  // Pick the platform-version host-side; package_info_plus would round-trip
  // a bunch of plugin init we don't want on the recovery path. Build_info
  // pubspec values are baked at compile time via --dart-define.
  final appBuild = <String, String>{
    'flavor': 'production',
    'mode': _resolveBuildMode(),
    'app_version': BuildInfo.appVersion,
    'app_build_number': 'unknown',
    'platform_version': Platform.operatingSystemVersion,
  };

  final base = appProbe.diagnostic ??
      SecureStorageDiagnostic(
        recoveredVia: appProbe.usedRecoverySlot,
        slotOutcomes: const <String, String>{},
      );
  final merged = syncProbe.diagnostic == null
      ? base
      : base.mergeWith(syncProbe.diagnostic!);

  return merged.copyWith(
    keychainRepairPendingBeforeBoot: keychainRepairPendingBeforeBoot,
    keychainRepairWritebackAttemptedThisBoot: writebackAttempted,
    keychainRepairWritebackResult: writebackResult,
    runtimeDekDeviceState: runtimeDekDeviceState,
    appBuild: appBuild,
    capturedAt: DateTime.now().toUtc(),
  );
}

String _resolveBuildMode() {
  if (kDebugMode) return 'debug';
  if (kReleaseMode) return 'release';
  return 'profile';
}

class _WindowsDataMigrationBlockedApp extends StatelessWidget {
  const _WindowsDataMigrationBlockedApp({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prism',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9070A0)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Prism found Windows data that needs recovery',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _windowsDataMigrationBlockedMessage(reason),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const PrismButton(
                      label: 'Close Prism',
                      onPressed: SystemNavigator.pop,
                      tone: PrismButtonTone.filled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

String _windowsDataMigrationBlockedMessage(String reason) {
  return switch (reason) {
    'legacy-in-use' =>
      'Close every Prism window, including any older extracted copy, then reopen this build. Your existing data was left in place.',
    'current-has-user-data' =>
      'Prism found data in both the old and new Windows data folders. Your data was left in place; please contact support before continuing.',
    _ =>
      'Prism could not safely move your existing Windows data into the new folder. Your data was left in place; please close Prism and contact support.',
  };
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
