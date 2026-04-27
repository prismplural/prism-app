import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' show SqlExtendedError, SqliteException;

/// Returns the underlying [SqliteException] for [error], unwrapping a
/// [DriftRemoteException] when the database runs in a background isolate
/// (the default for `NativeDatabase.createInBackground`). Returns null for
/// anything that isn't a SQLite error in either form.
SqliteException? asSqliteException(Object error) {
  if (error is SqliteException) return error;
  if (error is DriftRemoteException) {
    final cause = error.remoteCause;
    if (cause is SqliteException) return cause;
  }
  return null;
}

/// True when [error] represents a SQLITE_CONSTRAINT_UNIQUE (extended code
/// 2067) violation, including the isolate-wrapped form.
bool isUniqueConstraintViolation(Object error) {
  final sqlite = asSqliteException(error);
  return sqlite != null &&
      sqlite.extendedResultCode == SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE;
}

/// True when [error] represents either a SQLITE_CONSTRAINT_UNIQUE (2067)
/// or a SQLITE_CONSTRAINT_PRIMARYKEY (1555) violation, including the
/// isolate-wrapped form.
///
/// Used by check-then-insert helpers that race with another caller on the
/// same row id: a UNIQUE-indexed column collision surfaces as 2067, but
/// a clash on the table's primary key column surfaces as 1555 instead.
/// Both indicate "row already exists; refetch and continue."
bool isUniqueOrPrimaryKeyConstraintViolation(Object error) {
  final sqlite = asSqliteException(error);
  if (sqlite == null) return false;
  return sqlite.extendedResultCode ==
          SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE ||
      sqlite.extendedResultCode ==
          SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY;
}
