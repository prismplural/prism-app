import 'package:flutter/foundation.dart';

/// True only while startup auto-config is still trying to restore and
/// configure an existing sync session on a freshly created handle.
final syncAutoConfigureInProgress = ValueNotifier<bool>(false);
