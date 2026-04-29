import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_table_ticker_provider.dart';

void main() {
  group('frontingTableTickerProvider', () {
    test('emits initial 0 immediately on subscribe', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
      ]);
      addTearDown(container.dispose);

      final values = <int>[];
      final completer = Completer<void>();
      container.listen<AsyncValue<int>>(
        frontingTableTickerProvider,
        (_, next) {
          next.whenData((v) {
            values.add(v);
            if (!completer.isCompleted) completer.complete();
          });
        },
        fireImmediately: true,
      );

      await completer.future.timeout(const Duration(seconds: 2));
      expect(values, contains(0),
          reason: 'first emission must be the initial counter value 0');
    });

    test('increments on a fronting_sessions write (after debounce)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
      ]);
      addTearDown(container.dispose);

      final values = <int>[];
      final completer = Completer<void>();
      final sub = container.listen<AsyncValue<int>>(
        frontingTableTickerProvider,
        (_, next) {
          next.whenData((v) {
            values.add(v);
            if (v >= 1 && !completer.isCompleted) completer.complete();
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Wait for initial emission.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Write a row.
      await db.frontingSessionsDao.insertSession(
        FrontingSessionMapper.toCompanion(
          FrontingSession(
            id: 's1',
            memberId: 'a',
            startTime: DateTime.now(),
            endTime: null,
          ),
        ),
      );

      // Debounce is 200ms; allow a comfortable margin.
      await completer.future.timeout(const Duration(seconds: 2));
      expect(values, contains(0));
      expect(values, contains(1),
          reason: 'a single write must produce one tick after debounce');
    });

    test(
      'debounces a burst of writes — N writes in a tight loop produce '
      '≤2 ticks, not N',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
        ]);
        addTearDown(container.dispose);

        final values = <int>[];
        final sub = container.listen<AsyncValue<int>>(
          frontingTableTickerProvider,
          (_, next) {
            next.whenData(values.add);
          },
          fireImmediately: true,
        );
        addTearDown(sub.close);

        // Wait for the initial 0.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Burst: 20 untransacted writes back-to-back.
        for (var i = 0; i < 20; i++) {
          await db.frontingSessionsDao.insertSession(
            FrontingSessionMapper.toCompanion(
              FrontingSession(
                id: 'burst-$i',
                memberId: 'a',
                startTime: DateTime.now(),
                endTime: null,
              ),
            ),
          );
        }

        // Wait long enough for the debounce trail to fire (200ms +
        // generous margin).
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Initial 0 + at most a couple of trailing ticks. The whole
        // 20-write burst should NOT produce 20 emissions — that's the
        // contract for analytics rebuild count.
        final ticks = values.where((v) => v > 0).toList();
        expect(ticks.length, lessThanOrEqualTo(3),
            reason:
                'burst of 20 writes coalesced — got ticks=$ticks. '
                'Expected ≤3 (debounce should collapse the burst).');
        expect(ticks, isNotEmpty,
            reason: 'must emit at least one tick for the burst');
      },
    );

    test(
      'transactional bulk import (1000 rows) produces exactly ONE tick',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
        ]);
        addTearDown(container.dispose);

        final values = <int>[];
        final sub = container.listen<AsyncValue<int>>(
          frontingTableTickerProvider,
          (_, next) {
            next.whenData(values.add);
          },
          fireImmediately: true,
        );
        addTearDown(sub.close);

        // Wait for the initial 0.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Transactional bulk: 1000 inserts in a single transaction.
        // Drift coalesces these into one update notification.
        final stopwatch = Stopwatch()..start();
        await db.transaction(() async {
          for (var i = 0; i < 1000; i++) {
            await db.frontingSessionsDao.insertSession(
              FrontingSessionMapper.toCompanion(
                FrontingSession(
                  id: 'bulk-$i',
                  memberId: 'a',
                  startTime: DateTime.now()
                      .subtract(Duration(seconds: i)),
                  endTime: DateTime.now()
                      .subtract(Duration(seconds: i - 1)),
                ),
              ),
            );
          }
        });
        stopwatch.stop();

        // Allow the debounce trail.
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final ticks = values.where((v) => v > 0).toList();
        expect(ticks.length, equals(1),
            reason: '1000-row transactional import must coalesce to 1 '
                'tick via Drift transaction notification + debounce '
                '(got: $ticks)');

        // Soft sanity bound: the whole insert + tick chain shouldn't
        // jank a frame budget (16ms). 1000 rows in well under 1 sec.
        expect(stopwatch.elapsed.inSeconds, lessThan(5),
            reason: '1000-row insert took ${stopwatch.elapsed} — '
                'should be well under 5 seconds');
      },
    );

    test(
      'untransacted bulk loop (1000 rows) coalesces into a small number '
      'of ticks, NOT 1000',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
        ]);
        addTearDown(container.dispose);

        final values = <int>[];
        final sub = container.listen<AsyncValue<int>>(
          frontingTableTickerProvider,
          (_, next) {
            next.whenData(values.add);
          },
          fireImmediately: true,
        );
        addTearDown(sub.close);

        await Future<void>.delayed(const Duration(milliseconds: 10));

        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < 1000; i++) {
          await db.frontingSessionsDao.insertSession(
            FrontingSessionMapper.toCompanion(
              FrontingSession(
                id: 'untx-$i',
                memberId: 'a',
                startTime: DateTime.now()
                    .subtract(Duration(seconds: i)),
                endTime: DateTime.now()
                    .subtract(Duration(seconds: i - 1)),
              ),
            ),
          );
        }
        stopwatch.stop();

        // Allow trailing debounce window.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final ticks = values.where((v) => v > 0).toList();
        // Loose ceiling: 1000 inserts at <1ms each is <1s of activity.
        // With 200ms debounce that's ≤6 ticks max. Real-world: likely 1.
        expect(ticks.length, lessThan(20),
            reason: '1000-row untransacted loop coalesced — got '
                '${ticks.length} ticks. Must be far less than 1000.');
        expect(ticks, isNotEmpty,
            reason: 'untransacted bulk must still tick at least once');
      },
    );

    test(
      'customStatement truncate followed by db.notifyUpdates fires the '
      'ticker (regression guard for the truncate-path fix)',
      () async {
        // The migration, SP truncate, and remote-wipe paths all use
        // `db.customStatement('DELETE FROM fronting_sessions')`, which
        // bypasses Drift's typed-write notification. They follow up
        // with `db.notifyUpdates({TableUpdate('fronting_sessions')})`
        // to force the ticker (and any active stream queries) to
        // refresh. This test pins that contract.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        // Seed a row so the truncate has something to delete (and so
        // the initial-state has data — no tick fires for that yet).
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'seed',
              memberId: 'a',
              startTime: DateTime.now(),
              endTime: null,
            ),
          ),
        );

        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
        ]);
        addTearDown(container.dispose);

        final values = <int>[];
        final completer = Completer<void>();
        final sub = container.listen<AsyncValue<int>>(
          frontingTableTickerProvider,
          (_, next) {
            next.whenData((v) {
              values.add(v);
              // Wait for the SECOND tick (initial 0 + truncate tick).
              if (values.length >= 2 && !completer.isCompleted) {
                completer.complete();
              }
            });
          },
          fireImmediately: true,
        );
        addTearDown(sub.close);

        // Wait for the seed-write tick + initial 0 to land. The
        // ticker counts each table-update emission; we drain a
        // generous window to coalesce the seed insert before
        // truncating.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final ticksBeforeTruncate = values.length;

        // Truncate via customStatement (mirrors what the migration,
        // SP importer, and remote-wipe code paths do).
        await db.customStatement('DELETE FROM fronting_sessions');
        // Without notifyUpdates the ticker would NOT fire here.
        db.notifyUpdates({const TableUpdate('fronting_sessions')});

        // Wait for the debounce to flush.
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(values.length, greaterThan(ticksBeforeTruncate),
            reason:
                'customStatement + notifyUpdates must produce a ticker '
                'emission; got values=$values');
      },
    );

    test(
      'customStatement truncate WITHOUT notifyUpdates does NOT fire the '
      'ticker — proves notifyUpdates is load-bearing',
      () async {
        // Negative control for the truncate-path test: customStatement
        // alone does not propagate. This is the latent bug the
        // migration / SP / remote-wipe call sites had to plug
        // explicitly.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'seed',
              memberId: 'a',
              startTime: DateTime.now(),
              endTime: null,
            ),
          ),
        );

        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
        ]);
        addTearDown(container.dispose);

        final values = <int>[];
        final sub = container.listen<AsyncValue<int>>(
          frontingTableTickerProvider,
          (_, next) {
            next.whenData(values.add);
          },
          fireImmediately: true,
        );
        addTearDown(sub.close);

        // Drain the initial seed-write tick.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final ticksBeforeTruncate = values.length;

        // Truncate via customStatement WITHOUT notifyUpdates.
        await db.customStatement('DELETE FROM fronting_sessions');
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(values.length, equals(ticksBeforeTruncate),
            reason:
                'customStatement alone must NOT produce a ticker '
                'emission — this is why call sites need notifyUpdates');
      },
    );

    test(
      'truncate with multi-table notifyUpdates fires once on the '
      'fronting_sessions ticker even when other tables are also notified',
      () async {
        // Migration + SP importer + remote-wipe notify every truncated
        // table at once. Verify the fronting_sessions ticker still
        // fires when the notify set includes companion tables like
        // `front_session_comments`.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'seed',
              memberId: 'a',
              startTime: DateTime.now(),
              endTime: null,
            ),
          ),
        );

        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
        ]);
        addTearDown(container.dispose);

        final values = <int>[];
        final sub = container.listen<AsyncValue<int>>(
          frontingTableTickerProvider,
          (_, next) {
            next.whenData(values.add);
          },
          fireImmediately: true,
        );
        addTearDown(sub.close);

        await Future<void>.delayed(const Duration(milliseconds: 400));
        final ticksBeforeTruncate = values.length;

        // Truncate both fronting_sessions and front_session_comments
        // (mirrors migration + SP importer truncate path).
        await db.transaction(() async {
          await db.customStatement('DELETE FROM front_session_comments');
          await db.customStatement('DELETE FROM fronting_sessions');
        });
        db.notifyUpdates({
          const TableUpdate('fronting_sessions'),
          const TableUpdate('front_session_comments'),
        });

        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(values.length, greaterThan(ticksBeforeTruncate),
            reason:
                'multi-table notifyUpdates including fronting_sessions '
                'must still fire the ticker (got values=$values)');
      },
    );
  });
}
