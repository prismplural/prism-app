import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/app.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/router/app_router.dart';
import 'package:prism_plurality/core/services/notification_providers.dart';
import 'package:prism_plurality/core/services/reminder_scheduler_service.dart';
import 'package:prism_plurality/core/services/screen_privacy_controller.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_session_repair_provider.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

void main() {
  testWidgets('blocks routes and shows migration status for old schemas', (
    tester,
  ) async {
    final harness = _StartupGateHarness(
      databaseReady: Completer<DatabaseReadyReport>(),
      schemaVersionBeforeOpen: AppDatabase.currentSchemaVersion - 1,
    );

    await tester.pumpWidget(harness.buildApp());

    await tester.pump();

    expect(harness.routerWasRead, isFalse);
    expect(find.text('Updating Prism data'), findsOneWidget);
    expect(
      find.textContaining(
        'schema v${AppDatabase.currentSchemaVersion - 1} '
        'to v${AppDatabase.currentSchemaVersion}',
      ),
      findsOneWidget,
    );
    expect(find.text('Home route'), findsNothing);
  });

  testWidgets('does not show startup status for current schemas before grace', (
    tester,
  ) async {
    final harness = _StartupGateHarness(
      databaseReady: Completer<DatabaseReadyReport>(),
      schemaVersionBeforeOpen: AppDatabase.currentSchemaVersion,
    );

    await tester.pumpWidget(harness.buildApp());

    await tester.pump();

    expect(harness.routerWasRead, isFalse);
    expect(find.text('Updating Prism data'), findsNothing);
    expect(find.text('Opening Prism'), findsNothing);
    expect(find.text('Home route'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Opening Prism'), findsOneWidget);
  });

  testWidgets(
    'normal current-schema startup can reach the app without status',
    (tester) async {
      final databaseReady = Completer<DatabaseReadyReport>();
      final harness = _StartupGateHarness(
        databaseReady: databaseReady,
        schemaVersionBeforeOpen: AppDatabase.currentSchemaVersion,
      );

      await tester.pumpWidget(harness.buildApp());
      await tester.pump();

      expect(find.text('Opening Prism'), findsNothing);

      databaseReady.complete(
        const DatabaseReadyReport(
          schemaVersionBeforeOpen: AppDatabase.currentSchemaVersion,
          schemaVersionAfterOpen: AppDatabase.currentSchemaVersion,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(harness.routerWasRead, isTrue);
      expect(find.text('Home route'), findsOneWidget);
      expect(find.text('Opening Prism'), findsNothing);
      expect(find.text('Updating Prism data'), findsNothing);
    },
  );

  testWidgets('continues into the app when the status probe fails', (
    tester,
  ) async {
    final harness = _StartupGateHarness(
      databaseReady: Completer<DatabaseReadyReport>(),
      schemaProbeError: StateError('version probe failed'),
    );

    await tester.pumpWidget(harness.buildApp());

    await tester.pump();

    expect(harness.routerWasRead, isFalse);
    expect(find.text('Updating Prism data'), findsNothing);
    expect(find.text('Setting up Prism'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Setting up Prism'), findsOneWidget);

    harness.databaseReady!.complete(
      const DatabaseReadyReport(
        schemaVersionBeforeOpen: null,
        schemaVersionAfterOpen: AppDatabase.currentSchemaVersion,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(harness.routerWasRead, isTrue);
    expect(find.text('Home route'), findsOneWidget);
    expect(find.text('Setting up Prism'), findsNothing);
  });

  testWidgets('retry recreates the database before trying to open again', (
    tester,
  ) async {
    var databaseCreateCount = 0;
    final harness = _StartupGateHarness(
      schemaVersionBeforeOpen: AppDatabase.currentSchemaVersion,
      databaseOverride: (ref) {
        databaseCreateCount += 1;
        final executor = databaseCreateCount == 1
            ? NativeDatabase.memory().interceptWith(_FailOpenInterceptor())
            : NativeDatabase.memory();
        final db = AppDatabase(executor);
        ref.onDispose(db.close);
        return db;
      },
    );

    await tester.pumpWidget(harness.buildApp());
    await _pumpUntilFound(
      tester,
      find.text('Prism could not finish opening its database.'),
    );

    expect(databaseCreateCount, 1);
    expect(harness.routerWasRead, isFalse);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('Home route'));

    expect(databaseCreateCount, 2);
    expect(harness.routerWasRead, isTrue);
    expect(
      find.text('Prism could not finish opening its database.'),
      findsNothing,
    );
  });

  testWidgets('real database-ready path tolerates schema probe failure', (
    tester,
  ) async {
    final harness = _StartupGateHarness(
      schemaProbeError: StateError('version probe failed'),
      databaseOverride: (ref) {
        final db = AppDatabase(NativeDatabase.memory());
        ref.onDispose(db.close);
        return db;
      },
    );

    await tester.pumpWidget(harness.buildApp());
    await _pumpUntilFound(tester, find.text('Home route'));

    expect(harness.routerWasRead, isTrue);
    expect(
      find.text('Prism could not finish opening its database.'),
      findsNothing,
    );
  });

  testWidgets('primary key repair waits for database readiness and runs once', (
    tester,
  ) async {
    final databaseReady = Completer<DatabaseReadyReport>();
    final repairedKeys = <String?>[];
    final harness = _StartupGateHarness(
      databaseReady: databaseReady,
      schemaVersionBeforeOpen: AppDatabase.currentSchemaVersion,
      verifiedStartupKey: 'aa' * 32,
      repairOverride: (key) async {
        repairedKeys.add(key);
        return PrimaryDatabaseKeyRepairOutcome.repaired;
      },
    );

    await tester.pumpWidget(harness.buildApp());
    await tester.pump();

    expect(repairedKeys, isEmpty);

    databaseReady.complete(
      const DatabaseReadyReport(
        schemaVersionBeforeOpen: AppDatabase.currentSchemaVersion,
        schemaVersionAfterOpen: AppDatabase.currentSchemaVersion,
      ),
    );
    await _pumpUntilFound(tester, find.text('Home route'));
    await tester.pump();

    expect(repairedKeys, ['aa' * 32]);

    await tester.pump();
    await tester.pump();

    expect(repairedKeys, ['aa' * 32]);
  });
}

class _StartupGateHarness {
  _StartupGateHarness({
    this.databaseReady,
    this.schemaVersionBeforeOpen,
    this.schemaProbeError,
    this.databaseOverride,
    this.verifiedStartupKey,
    this.repairOverride,
  });

  final Completer<DatabaseReadyReport>? databaseReady;
  final int? schemaVersionBeforeOpen;
  final Object? schemaProbeError;
  final AppDatabase Function(Ref ref)? databaseOverride;
  final String? verifiedStartupKey;
  final Future<PrimaryDatabaseKeyRepairOutcome> Function(String?)?
  repairOverride;
  bool routerWasRead = false;

  Widget buildApp() => ProviderScope(
    overrides: [
      if (databaseReady != null)
        databaseReadyProvider.overrideWith((ref) => databaseReady!.future),
      databaseSchemaVersionBeforeOpenProvider.overrideWith((ref) async {
        final error = schemaProbeError;
        if (error != null) throw error;
        return schemaVersionBeforeOpen;
      }),
      if (databaseOverride != null)
        databaseProvider.overrideWith((ref) => databaseOverride!(ref)),
      if (verifiedStartupKey != null)
        verifiedStartupKeyProvider.overrideWithValue(verifiedStartupKey),
      if (repairOverride != null)
        primaryDatabaseKeyRepairProvider.overrideWithValue(repairOverride!),
      routerProvider.overrideWith((ref) {
        routerWasRead = true;
        return GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Text('Home route'),
            ),
          ],
        );
      }),
      prismSyncHandleProvider.overrideWithBuild((ref, notifier) => null),
      syncEventStreamProvider.overrideWith((ref) => const Stream.empty()),
      syncHealthProvider.overrideWith(_HealthySyncHealthNotifier.new),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      frontingMigrationModeProvider.overrideWith(
        (ref) => Stream.value(FrontingMigrationService.modeComplete),
      ),
      reminderSchedulerListenerProvider.overrideWithValue(null),
      habitNotificationListenerProvider.overrideWithValue(null),
      frontingReminderListenerProvider.overrideWithValue(null),
      frontingOpenSessionRepairBootstrapProvider.overrideWithValue(null),
      spBoardsBackfillProvider.overrideWith((ref) async => null),
      spReplyQuoteBackfillProvider.overrideWith((ref) async => null),
      screenPrivacyControllerProvider.overrideWithValue(null),
    ],
    child: const PrismApp(),
  );
}

class _HealthySyncHealthNotifier extends SyncHealthNotifier {
  @override
  SyncHealthState build() => SyncHealthState.unpaired;
}

class _FailOpenInterceptor extends QueryInterceptor {
  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) {
    throw StateError('simulated database open failure');
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}
