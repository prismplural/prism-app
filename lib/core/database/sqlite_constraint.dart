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
