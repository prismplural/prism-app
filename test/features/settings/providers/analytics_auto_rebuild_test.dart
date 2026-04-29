import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';

void main() {
  group('frontingAnalyticsProvider auto-rebuild', () {
    test(
      'a write to fronting_sessions rebuilds analytics without explicit '
      'invalidation (ticker contract)',
      () async {
        // Wires the real Drift DB through the analytics provider. After
        // the first read, we insert a row and re-read — the row's
        // duration must show up in totals without anyone calling
        // ref.invalidate. This is the contract that eliminates the
        // whack-a-mole.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final now = DateTime.now();
        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
          analyticsRangeProvider.overrideWith(
            () => _FixedRangeNotifier(
              AnalyticsDateRange(
                range: DateTimeRange(
                  start: now.subtract(const Duration(days: 7)),
                  end: now.add(const Duration(hours: 1)),
                ),
              ),
            ),
          ),
        ]);
        addTearDown(container.dispose);

        // Subscribe so the provider stays alive.
        container.listen<AsyncValue<FrontingAnalytics>>(
          frontingAnalyticsProvider,
          (_, _) {},
          fireImmediately: true,
        );

        // First emission: empty DB.
        final initial = await container
            .read(frontingAnalyticsProvider.future)
            .timeout(const Duration(seconds: 2));
        expect(initial.totalSessions, 0);
        expect(initial.totalTrackedTime, Duration.zero);

        // Insert a 1-hour fronting session WITHOUT calling invalidate.
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 's1',
              memberId: 'a',
              startTime: now.subtract(const Duration(hours: 2)),
              endTime: now.subtract(const Duration(hours: 1)),
            ),
          ),
        );

        // Wait for the ticker debounce + provider rebuild.
        // Ticker is 200ms; pad with margin for the FutureProvider
        // recompute + listener push.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final after = await container
            .read(frontingAnalyticsProvider.future)
            .timeout(const Duration(seconds: 2));
        expect(after.totalSessions, 1,
            reason: 'analytics must auto-rebuild on a fronting_sessions '
                'write — no explicit invalidation should be required');
        expect(after.totalTrackedTime, const Duration(hours: 1));
      },
    );

    test(
      'customStatement DELETE + db.notifyUpdates rebuilds analytics — '
      'truncate-path contract',
      () async {
        // Pin the analytics auto-rebuild contract for the truncate
        // path (migration, SP importer, remote-wipe). customStatement
        // bypasses Drift's typed-write notification, so call sites
        // must follow up with db.notifyUpdates. This test verifies
        // the FutureProvider rebuilds against the post-truncate state.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final now = DateTime.now();
        final container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
          analyticsRangeProvider.overrideWith(
            () => _FixedRangeNotifier(
              AnalyticsDateRange(
                range: DateTimeRange(
                  start: now.subtract(const Duration(days: 7)),
                  end: now.add(const Duration(hours: 1)),
                ),
              ),
            ),
          ),
        ]);
        addTearDown(container.dispose);

        // Seed the DB with one session before subscribing.
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 's1',
              memberId: 'a',
              startTime: now.subtract(const Duration(hours: 2)),
              endTime: now.subtract(const Duration(hours: 1)),
            ),
          ),
        );

        container.listen<AsyncValue<FrontingAnalytics>>(
          frontingAnalyticsProvider,
          (_, _) {},
          fireImmediately: true,
        );

        final initial = await container
            .read(frontingAnalyticsProvider.future)
            .timeout(const Duration(seconds: 2));
        expect(initial.totalSessions, 1);

        // Truncate via customStatement + notifyUpdates (mirrors the
        // migration / SP importer / remote-wipe code paths).
        await db.customStatement('DELETE FROM fronting_sessions');
        db.notifyUpdates({const TableUpdate('fronting_sessions')});

        // Wait for the ticker debounce + provider rebuild.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final after = await container
            .read(frontingAnalyticsProvider.future)
            .timeout(const Duration(seconds: 2));
        expect(after.totalSessions, 0,
            reason:
                'analytics must rebuild after a customStatement DELETE + '
                'notifyUpdates — proves the truncate-path contract '
                'plumbs through the ticker into FutureProviders');
        expect(after.totalTrackedTime, Duration.zero);
      },
    );
  });
}

/// Fixed-range notifier so the test doesn't rebuild over a moving target.
class _FixedRangeNotifier extends AnalyticsRangeNotifier {
  _FixedRangeNotifier(this._initial);
  final AnalyticsDateRange _initial;

  @override
  AnalyticsDateRange build() => _initial;
}
