import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Returns the directory the app should store its persistent data in.
///
/// On iOS / macOS / Android, `getApplicationDocumentsDirectory()` is a
/// sandboxed per-app path, which is the right place for the Drift and sync
/// databases.
///
/// On Linux and Windows, `getApplicationDocumentsDirectory()` returns the
/// user's shared `~/Documents` folder — dropping sqlite files there would
/// clutter the user's personal Documents and confuse file managers, cloud-sync
/// tools, and backup software. Use the XDG data dir instead
/// (`~/.local/share/<app>/` on Linux).
Future<Directory> getAppDataDir() {
  if (Platform.isLinux || Platform.isWindows) {
    return getApplicationSupportDirectory();
  }
  return getApplicationDocumentsDirectory();
}
