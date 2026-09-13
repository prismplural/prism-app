import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/inbound_fronting_duplicate_open_reconciler.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS applies a delayed distinct-id session and preserves history',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db);
      final repository = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      const memberId = 'member-01';
      final olderStart = DateTime.utc(2026, 9, 10, 10);
      final newerStart = DateTime.utc(2026, 9, 10, 11);

      await adapter.adapter.applyFields('members', memberId, {
        'name': 'Fixture-$memberId',
        'created_at': '2026-01-01T00:00:00.000Z',
        'is_active': true,
        'is_deleted': false,
      });
      await repository.createSession(
        FrontingSession(
          id: 'session-device-01',
          memberId: memberId,
          startTime: olderStart,
        ),
      );

      await reconcileInboundDuplicateOpensAfterSyncCompletedEvent(
        SyncEvent('SyncCompleted', {
          'type': 'SyncCompleted',
          'result': {'error_kind': 'Network'},
        }),
        strict: false,
        drain: () async {
          adapter.beginSyncBatch();
          await adapter.adapter
              .applyFields('fronting_sessions', 'session-device-02', {
                'member_id': memberId,
                'start_time': newerStart.toIso8601String(),
                'end_time': null,
                'session_type': 0,
                'is_health_kit_import': false,
                'is_deleted': false,
              });
          await adapter.completeSyncBatch();
          return const DrainResult(
            rowsApplied: 1,
            rowsSpilled: 0,
            chunksAcked: 1,
            aborted: false,
            touchedTables: {'fronting_sessions'},
          );
        },
        reconciler: InboundFrontingDuplicateOpenReconciler(db, repository),
      );

      final active = await repository.getActiveSessions();
      final history = await repository.getFrontingSessions();
      expect(active.map((session) => session.id), ['session-device-02']);
      expect(history, hasLength(2));
      expect(
        history
            .singleWhere((session) => session.id == 'session-device-01')
            .endTime,
        newerStart.toLocal(),
      );
    },
  );
}
