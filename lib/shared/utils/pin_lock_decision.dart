/// Pure decision functions for PIN lock behavior.
///
/// Extracted from [AppShell]'s `_checkInitialLock` and `_checkLockOnResume`
/// so the fail-closed logic (`?? true`) is unit-testable without widget
/// infrastructure.

/// Determines whether the app should be locked at startup.
///
/// Returns a record with `locked` and `resolved` fields.
/// - `resolved == false` means the caller should bail out (providers still loading).
/// - `resolved == true` means the decision is final.
({bool locked, bool resolved}) initialLockDecision({
  required bool settingsLoading,
  required bool isPinSetLoading,
  required bool? pinLockEnabled,
  required bool? isPinSet,
}) {
  // Still loading — can't decide yet.
  if (settingsLoading || isPinSetLoading) {
    return (locked: false, resolved: false);
  }

  // Settings errored or empty — no lock.
  if (pinLockEnabled == null) {
    return (locked: false, resolved: true);
  }

  if (pinLockEnabled) {
    // If isPinSet errored (null), default to locked for safety.
    final pinExists = isPinSet ?? true;
    if (pinExists) {
      return (locked: true, resolved: true);
    }
  }

  return (locked: false, resolved: true);
}

/// Determines whether the app should lock when resuming from background.
///
/// Returns true if the app should be locked.
bool resumeLockDecision({
  required bool alreadyLocked,
  required bool? pinLockEnabled,
  required bool? isPinSet,
  required DateTime? backgroundedAt,
  required int autoLockDelaySeconds,
}) {
  if (alreadyLocked) return false; // Already locked, no change.
  if (pinLockEnabled == null || !pinLockEnabled) return false;

  // If isPinSet errored (null), default to locked for safety.
  final pinExists = isPinSet ?? true;
  if (!pinExists) return false;

  if (backgroundedAt == null) return true;

  final elapsed = DateTime.now().difference(backgroundedAt).inSeconds;
  return elapsed >= autoLockDelaySeconds;
}
