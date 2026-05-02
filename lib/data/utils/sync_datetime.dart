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
