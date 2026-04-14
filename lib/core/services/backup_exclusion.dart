import 'dart:io';

import 'package:flutter/services.dart';

/// Exclude a file or directory from iCloud backup on iOS.
///
/// No-op on other platforms. Failures are non-fatal — the files are
/// still encrypted at rest.
Future<void> excludeFromiCloudBackup(String path) async {
  if (!Platform.isIOS) return;
  try {
    const channel = MethodChannel('com.prism.prism_plurality/file_utils');
    await channel.invokeMethod<void>('excludeFromBackup', {'path': path});
  } catch (_) {
    // Non-fatal: if the channel call fails, the file is still encrypted.
  }
}
