import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

/// Fake entity that fails on a configurable set of entity ids. Used to
/// simulate per-row apply failures without needing the real Drift mapping
/// to be configured for every table under test.
DriftSyncEntity _fakeEntity({
  required String tableName,
  required bool Function(String entityId) shouldFail,
  required List<String> appliedIds,
}) {
  return DriftSyncEntity(
    tableName: tableName,
    toSyncFields: (_) => <String, dynamic>{},
    applyFields: (id, fields) async {
      if (shouldFail(id)) {
        throw StateError('applyFields failed for $tableName/$id');
      }
      appliedIds.add('$tableName/$id');
    },
    hardDelete: (id) async {
      appliedIds.add('delete $tableName/$id');
    },
    readRow: (_) async => null,
    isDeleted: (_) async => false,
  );
}

SyncEvent _eventFromChanges(List<Map<String, dynamic>> changes) {
  return SyncEvent.fromJson({
    'type': 'RemoteChanges',
    'changes': changes,
  });
}

void main() {
  late database.AppDatabase db;

  setUp(() {
    db = database.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('applyRemoteChanges — non-strict mode', () {
    test('per-row failure is swallowed and subsequent rows apply', () async {
      final applied = <String>[];
      final adapter = DriftSyncAdapter(
        entities: [
          _fakeEntity(
            tableName: 'members',
            shouldFail: (id) => id == 'bad',
            appliedIds: applied,
          ),
        ],
      );

      final event = _eventFromChanges([
        {
          'table': 'members',
          'entity_id': 'ok-1',
          'is_delete': false,
          'fields': {'name': 'A'},
        },
        {
          'table': 'members',
          'entity_id': 'bad',
          'is_delete': false,
          'fields': {'name': 'B'},
        },
        {
          'table': 'members',
          'entity_id': 'ok-2',
          'is_delete': false,
          'fields': {'name': 'C'},
        },
      ]);

      final result = await applyRemoteChanges(db, adapter, event);
      expect(result.rowsApplied, 2);
      expect(result.failedTables, isEmpty);
      expect(applied, containsAll(['members/ok-1', 'members/ok-2']));
      expect(applied, isNot(contains('members/bad')));
    });
  });

  group('applyRemoteChanges — strict mode', () {
    test('first-row failure rethrows; subsequent rows not applied', () async {
      final applied = <String>[];
      final adapter = DriftSyncAdapter(
        entities: [
          _fakeEntity(
            tableName: 'members',
            shouldFail: (id) => id == 'bad',
            appliedIds: applied,
          ),
        ],
      );

      final event = _eventFromChanges([
        {
          'table': 'members',
          'entity_id': 'ok-1',
          'is_delete': false,
          'fields': {'name': 'A'},
        },
        {
          'table': 'members',
          'entity_id': 'bad',
          'is_delete': false,
          'fields': {'name': 'B'},
        },
        {
          'table': 'members',
          'entity_id': 'ok-2',
          'is_delete': false,
          'fields': {'name': 'C'},
        },
      ]);

      await expectLater(
        applyRemoteChanges(db, adapter, event, strict: true),
        throwsA(
          isA<StrictApplyFailure>()
              .having((e) => e.table, 'table', 'members')
              .having((e) => e.entityId, 'entityId', 'bad')
              .having((e) => e.failedTables, 'failedTables', ['members']),
        ),
      );

      expect(applied, contains('members/ok-1'));
      // The row after the failure must NOT have been applied — strict mode
      // aborts immediately.
      expect(applied, isNot(contains('members/ok-2')));
    });

    test('all rows succeeding returns success ApplyResult', () async {
      final applied = <String>[];
      final adapter = DriftSyncAdapter(
        entities: [
          _fakeEntity(
            tableName: 'members',
            shouldFail: (_) => false,
            appliedIds: applied,
          ),
        ],
      );

      final event = _eventFromChanges([
        {
          'table': 'members',
          'entity_id': 'a',
          'is_delete': false,
          'fields': <String, dynamic>{},
        },
        {
          'table': 'members',
          'entity_id': 'b',
          'is_delete': false,
          'fields': <String, dynamic>{},
        },
      ]);

      final result = await applyRemoteChanges(
        db,
        adapter,
        event,
        strict: true,
      );
      expect(result.rowsApplied, 2);
      expect(result.failedTables, isEmpty);
      expect(applied, ['members/a', 'members/b']);
    });
  });

  group('StrictApplyCoordinator', () {
    test('enter/exit toggles isStrict', () {
      final c = StrictApplyCoordinator();
      expect(c.isStrict, isFalse);
      c.enterStrictMode();
      expect(c.isStrict, isTrue);
      c.exitStrictMode();
      expect(c.isStrict, isFalse);
    });

    test('signalFailure resolves outcome with ApplyOutcomeFailure', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalFailure(const StrictApplyFailure(message: 'boom'));
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeFailure>());
      expect(
        (outcome as ApplyOutcomeFailure).failure.message,
        'boom',
      );
      c.exitStrictMode();
    });

    test('signalBatchComplete resolves outcome with success', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalBatchComplete();
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeSuccess>());
      c.exitStrictMode();
    });

    test('exitStrictMode completes a still-pending outcome as success',
        () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.exitStrictMode();
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeSuccess>());
    });

    // Regression: reproduces the Future.any race the latch pattern fixes.
    // If the failure signal is recorded BEFORE the awaiter is registered
    // (as happens when bootstrap's synchronous prologue emits failing
    // RemoteChanges before the joiner reaches its `await outcome`),
    // the outcome must still observe the failure — no lost signals.
    test('signalFailure before first await still observed', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalFailure(
        const StrictApplyFailure(message: 'early', table: 'members'),
      );
      // Force a microtask hop to mimic the real caller awaiting something
      // else first, then finally awaiting outcome.
      await Future<void>.value();
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeFailure>());
      expect((outcome as ApplyOutcomeFailure).failure.table, 'members');
      c.exitStrictMode();
    });

    // Regression: first writer wins. Once signalFailure has resolved the
    // latch, a later signalBatchComplete must not flip the outcome to
    // success (or throw).
    test('first signal wins — later signals are ignored', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalFailure(const StrictApplyFailure(message: 'first'));
      c.signalBatchComplete(); // must be a no-op
      c.signalFailure(const StrictApplyFailure(message: 'second'));
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeFailure>());
      expect((outcome as ApplyOutcomeFailure).failure.message, 'first');
      c.exitStrictMode();
    });

    test('outcome getter returns null when not in strict mode', () {
      final c = StrictApplyCoordinator();
      expect(c.outcome, isNull);
      c.enterStrictMode();
      expect(c.outcome, isNotNull);
      c.exitStrictMode();
      expect(c.outcome, isNull);
    });

    test('enterStrictMode resets the completer between attempts', () async {
      final c = StrictApplyCoordinator();
      // First attempt: signalled a failure, caller observed it.
      final first = c.enterStrictMode();
      c.signalFailure(const StrictApplyFailure(message: 'attempt-1'));
      expect(await first, isA<ApplyOutcomeFailure>());
      c.exitStrictMode();

      // Second attempt: fresh completer — a new signalBatchComplete must
      // resolve this completer, not the prior one.
      final second = c.enterStrictMode();
      expect(identical(first, second), isFalse);
      c.signalBatchComplete();
      expect(await second, isA<ApplyOutcomeSuccess>());
      c.exitStrictMode();
    });
  });
}
