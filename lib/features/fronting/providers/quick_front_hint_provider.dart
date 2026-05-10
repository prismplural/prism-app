import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const quickFrontHoldInstructionSeenPrefsKey =
    'prism.local.quick_front_hold_instruction_seen';

final quickFrontHoldInstructionVisibleProvider =
    NotifierProvider<QuickFrontHoldInstructionVisibleNotifier, bool>(
      QuickFrontHoldInstructionVisibleNotifier.new,
    );

class QuickFrontHoldInstructionVisibleNotifier extends Notifier<bool> {
  bool _markedSeenThisRun = false;

  @override
  bool build() {
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_markedSeenThisRun) return;
    if (prefs.getBool(quickFrontHoldInstructionSeenPrefsKey) == true) {
      state = false;
    }
  }

  Future<void> markSeen() async {
    _markedSeenThisRun = true;
    state = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(quickFrontHoldInstructionSeenPrefsKey, true);
    } catch (_) {
      // This hint is device-local polish; logging front should not fail because
      // the local preference write failed.
    }
  }
}
