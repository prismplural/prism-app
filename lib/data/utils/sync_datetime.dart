/// Shared helpers for serializing DateTimes onto the sync wire.
///
/// Local DateTimes serialize with no offset/Z, so a peer in a different
/// timezone would parse the value as their own local time and shift the
/// absolute moment by the timezone delta on every sync. Routing every
/// DateTime through [toSyncUtc] / [toSyncUtcOrNull] mirrors the
/// `_dateTimeToSyncString` helper in `core/sync/drift_sync_adapter.dart`
/// so all repository emissions stay UTC-normalized at the boundary.
String toSyncUtc(DateTime dt) => dt.toUtc().toIso8601String();

String? toSyncUtcOrNull(DateTime? dt) => dt?.toUtc().toIso8601String();

/// Parse a sync-format DateTime back into a Dart [DateTime].
///
/// Patch maps fed to `_partial<Entity>Companion(...)` in the patch-style
/// update flow carry timestamps as ISO-8601 strings (the same shape
/// [toSyncUtc] emits). When a keyed `update<Entity>Fields(id, Map)`
/// caller hands us a raw [DateTime] directly, accept that too — it
/// happens in tests and in repositories that share the keyed path with
/// internal Dart code (see habit's `updateHabitFields`). Anything else
/// is a bug and throws via the `as String` cast.
DateTime parseSyncDateTime(Object? value) {
  if (value is DateTime) return value;
  return DateTime.parse(value as String);
}
