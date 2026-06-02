import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// True only while startup auto-config is still trying to restore and
/// configure an existing sync session on a freshly created handle.
final syncAutoConfigureInProgress = ValueNotifier<bool>(false);

/// Current handle for repository instances built before provider rebuilds.
final syncCurrentHandle = ValueNotifier<ffi.PrismSyncHandle?>(null);
