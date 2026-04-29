import 'dart:async';

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
  });
}
