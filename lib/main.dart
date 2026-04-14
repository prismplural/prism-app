import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
// import 'package:workmanager/workmanager.dart';

import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
// import 'package:prism_plurality/features/pluralkit/services/pluralkit_background_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // F1: Global error boundaries — install immediately so startup failures are reported.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorReportingService.instance.report(
      details.exceptionAsString(),
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReportingService.instance.report(
      error.toString(),
      stackTrace: stack,
    );
    return kReleaseMode; // In debug, let the error propagate to show the error overlay
  };

  tz.initializeTimeZones();
  if (!kIsWeb) {
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));
  }

  // iOS Keychain survives app uninstall — clear stale data on fresh install.
  await clearKeychainIfFreshInstall();
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

  // F5: Show a plain error message instead of the red/yellow error screen in
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

  runApp(
    ProviderScope(
      // F7: Explicit retry filter — prevent infinite retry on programmer bugs.
      retry: (retryCount, error) {
        // Don't retry format/type errors (programmer bugs)
        if (error is FormatException || error is TypeError) return null;
        // Max 3 retries with exponential backoff
        if (retryCount >= 3) return null;
        return Duration(seconds: 1 << retryCount); // 1s, 2s, 4s
      },
      // F24: Log provider errors in debug builds.
      observers: [if (kDebugMode) _DebugProviderObserver()],
      child: const PrismApp(),
    ),
  );

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

/// F24: Logs Riverpod provider errors in debug builds.
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
