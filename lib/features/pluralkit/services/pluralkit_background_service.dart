import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// Known workmanager task names.
const kBackgroundSyncTaskName = 'com.prism.backgroundSync';
const kRescheduleRemindersTaskName = 'com.prism.rescheduleReminders';

/// Entry-point for workmanager background execution.
///
/// Must be a top-level or static function annotated with
/// `@pragma('vm:entry-point')` so the Dart AOT compiler retains it.
///
/// Background tasks run in a separate isolate without access to the app's
/// Riverpod container, Flutter widget tree, or existing Rust FFI handle.
/// Full background sync would require initializing RustLib, creating a new
/// PrismSyncHandle, seeding the secure store, and running a sync cycle —
/// all without the main isolate's dependency graph. This needs dedicated
/// architectural work (e.g. a lightweight bootstrap path that reads
/// credentials from the keychain and calls the Rust FFI directly).
///
/// For now, we return true for known task names to avoid workmanager marking
/// them as permanently failed, and log the invocation for diagnostics.
///
/// **PkSyncEventBus note (pk-sync-log feature):** this dispatcher CANNOT emit
/// PkSyncEvent values to the in-app log. The bus is a `StreamController`
/// owned by the main isolate; the workmanager background isolate has its
/// own heap and would need a `SendPort` to reach it. The bus's
/// `markPkBusMainIsolate()` flag is only set on the main isolate, so any
/// `PkSyncEventBus.emit()` call from here would silently no-op anyway. When
/// background sync ships for real, route events back via SendPort and emit
/// them from the main isolate. Until then, debugPrint is the only signal.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case kBackgroundSyncTaskName:
        debugPrint('[Background] Sync task triggered (not yet implemented)');
        return true;
      case kRescheduleRemindersTaskName:
        debugPrint(
          '[Background] Reschedule reminders task triggered (not yet implemented)',
        );
        return true;
      default:
        debugPrint('[Background] Unknown task: $taskName');
        return false;
    }
  });
}
