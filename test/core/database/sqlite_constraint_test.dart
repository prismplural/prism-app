import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:prism_plurality/core/database/sqlite_constraint.dart';

// `DriftRemoteException` has a private constructor, so the helper's
// `error is DriftRemoteException` check has to be exercised through a
// fake that satisfies the nominal type. Dart's `is` check is nominal,
// not structural — implementing only `Exception` would silently fall
// through and the test would pass for the wrong reason.
class _FakeDriftRemoteException implements DriftRemoteException {
  _FakeDriftRemoteException(this.remoteCause);

  @override
  final Object remoteCause;

  @override
  StackTrace get remoteStackTrace => StackTrace.empty;
}

void main() {
  group('isUniqueConstraintViolation', () {
    test(
      'returns true for direct SqliteException with extended code 2067 '
      '(SQLITE_CONSTRAINT_UNIQUE)',
      () {
        final error = SqliteException(
          extendedResultCode: 2067,
          message: 'UNIQUE constraint failed: fronting_sessions.pluralkit_uuid',
        );

        expect(isUniqueConstraintViolation(error), isTrue);
      },
    );

    test(
      'returns false for direct SqliteException with base code 19 '
      '(SQLITE_CONSTRAINT but not UNIQUE)',
      () {
        final error = SqliteException(
          extendedResultCode: 19,
          message: 'constraint failed',
        );

        expect(isUniqueConstraintViolation(error), isFalse);
      },
    );

    test(
      'returns true for DriftRemoteException wrapping SqliteException '
      '(extended code 2067) — the production isolate-wrapped case the '
      'old fix never caught',
      () {
        final inner = SqliteException(
          extendedResultCode: 2067,
          message: 'UNIQUE constraint failed: fronting_sessions.pluralkit_uuid',
        );
        final wrapped = _FakeDriftRemoteException(inner);

        expect(isUniqueConstraintViolation(wrapped), isTrue);
      },
    );

    test(
      'returns false for DriftRemoteException wrapping SqliteException with '
      'extended code 787 (SQLITE_CONSTRAINT_FOREIGNKEY)',
      () {
        final inner = SqliteException(
          extendedResultCode: 787,
          message: 'FOREIGN KEY constraint failed',
        );
        final wrapped = _FakeDriftRemoteException(inner);

        expect(isUniqueConstraintViolation(wrapped), isFalse);
      },
    );

    test(
      'returns false for DriftRemoteException whose remoteCause is a '
      'plain string (not a SqliteException)',
      () {
        final wrapped = _FakeDriftRemoteException('not an exception');

        expect(isUniqueConstraintViolation(wrapped), isFalse);
      },
    );

    test('returns false for a plain Exception unrelated to SQLite', () {
      expect(isUniqueConstraintViolation(Exception('boom')), isFalse);
    });
  });

  group('asSqliteException', () {
    test('returns the same instance for a direct SqliteException', () {
      final error = SqliteException(
        extendedResultCode: 2067,
        message: 'UNIQUE constraint failed',
      );

      expect(asSqliteException(error), same(error));
    });

    test('unwraps a DriftRemoteException carrying a SqliteException', () {
      final inner = SqliteException(
        extendedResultCode: 2067,
        message: 'UNIQUE constraint failed',
      );
      final wrapped = _FakeDriftRemoteException(inner);

      expect(asSqliteException(wrapped), same(inner));
    });

    test('returns null for non-SQLite errors', () {
      expect(asSqliteException(Exception('boom')), isNull);
      expect(
        asSqliteException(_FakeDriftRemoteException('not an exception')),
        isNull,
      );
    });
  });
}
