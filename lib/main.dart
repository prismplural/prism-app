import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:workmanager/workmanager.dart';

import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_background_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // iOS Keychain survives app uninstall — clear stale data on fresh install.
  await clearKeychainIfFreshInstall();

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

  runApp(
    const ProviderScope(
      child: PrismApp(),
    ),
  );

  // Defer non-critical native init until after first frame.
  if (Platform.isIOS || Platform.isAndroid) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Workmanager().initialize(callbackDispatcher);
    });
  }
}
