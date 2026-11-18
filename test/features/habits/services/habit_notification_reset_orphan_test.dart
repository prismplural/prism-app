// Regression: resetting habit data must retract that habit's pending reminders.
//
// The reset path deletes habit rows (`_resetHabits` in
// lib/features/settings/providers/reset_data_provider.dart) without telling the
// notification scheduler, and `HabitNotificationService.rescheduleAll` only
// visits habits that still exist. So the deleted habit's pending one-shots stay
// scheduled and fire later; tapping one opens an empty habits screen.
//
// This test drives the real reset provider, the real HabitNotificationService
// and the real LocalNotificationService. Only the platform notification channel
// (`dexterous.com/flutter/local_notifications`) is faked, so cancellation must
// come from the production code path rather than a stubbed `cancelRange`.
// Fixtures are synthetic: no member, message, token or user data is involved.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' hide Habit;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/features/habits/services/habit_notification_service.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Habit scheduling namespace, mirroring `HabitNotificationService`:
/// `3_000_000 + id.hashCode.abs() % 100_000`.
///
/// Owned IDs are not the bare base: the service schedules and cancels
/// `base..base + _habitSeriesWidth - 1`, so the top base (3_099_999) owns IDs
/// through 3_100_028. Attribution must therefore use a habit's owned series,
/// never a 3_000_000..3_099_999 hard bound.
const _habitIdBase = 3000000;
const _habitIdMod = 100000;
const _habitSeriesWidth = LocalNotificationService.maxIntervalOccurrences;

int _habitBaseId(String habitId) =>
    _habitIdBase + (habitId.hashCode.abs() % _habitIdMod);

/// Every notification ID the service may use for one habit base.
Set<int> _ownedSeries(int baseId) => {
  for (var i = 0; i < _habitSeriesWidth; i++) baseId + i,
};

/// Every notification ID the service may use for [habitId].
Set<int> _habitSeriesIds(String habitId) => _ownedSeries(_habitBaseId(habitId));

/// Notification ID ranges owned by other subsystems. A habit reset must leave
/// them alone: fronting notifications use 1000-1999, reminders 20_000_000+.
const _frontingId = 1500;
const _reminderId = 20000005;

/// Bounded waits for the interleaving gate: how long to wait for the batch to
/// reach the gated one-shot, and how long to drain it after release.
const _gateHoldTimeout = Duration(seconds: 10);
const _batchDrainTimeout = Duration(seconds: 10);

/// Stateful fake of the flutter_local_notifications platform channel: it holds
/// the pending-request table the OS would hold, so `cancel`/`zonedSchedule`
/// effects are observable through [LocalNotificationService].
class _FakeNotificationPlatform {
  final Map<int, Map<String, Object?>> pending = {};
  final List<MethodCall> calls = [];

  /// One-shot gate for interleaving tests: the fake records the pending entry
  /// for [gatedScheduleId], then holds that `zonedSchedule` until
  /// [gateReleased] completes, so a test can act while a scheduling pass is
  /// suspended at a chosen one-shot. Only scheduling is gated — cancellation is
  /// never held, so work run inside the gate cannot deadlock.
  int? gatedScheduleId;
  Completer<void>? gateEntered;
  Completer<void>? gateReleased;

  /// IDs whose cancellation is attempted, recorded, and then fails — the
  /// pending entry survives, standing for a reminder that may still fire.
  Set<int> failCancelIds = {};

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'initialize':
        return true;
      case 'zonedSchedule':
        final args = (call.arguments as Map).cast<String, Object?>();
        final id = args['id']! as int;
        pending[id] = {
          'id': id,
          'title': args['title'] ?? '',
          'body': args['body'] ?? '',
          'payload': args['payload'] ?? '',
        };
        if (id == gatedScheduleId) {
          if (gateEntered != null && !gateEntered!.isCompleted) {
            gateEntered!.complete();
          }
          await gateReleased!.future;
        }
        return null;
      case 'cancel':
        // The iOS implementation passes the raw ID as the argument.
        final id = call.arguments as int;
        if (failCancelIds.contains(id)) {
          throw PlatformException(
            code: 'cancel_failed',
            message: 'synthetic cancel failure',
          );
        }
        pending.remove(id);
        return null;
      case 'pendingNotificationRequests':
        return pending.values.toList();
      default:
        return null;
    }
  }

  List<int> get pendingIds => pending.keys.toList()..sort();

  List<int> get cancelledIds => [
    for (final call in calls)
      if (call.method == 'cancel') call.arguments as int,
  ];

  List<String> get methods => [for (final call in calls) call.method];

  /// Seeds a pending notification owned by another subsystem, as the OS would
  /// already hold after that subsystem scheduled it.
  void seedForeignPending(int id, String payload) {
    pending[id] = {
      'id': id,
      'title': 'fixture',
      'body': 'fixture',
      'payload': payload,
    };
  }
}

Habit _habitFixture(String id) {
  final now = DateTime(2026, 1, 1, 9);
  return Habit(
    id: id,
    name: 'Fixture habit $id',
    frequency: HabitFrequency.daily,
    isActive: true,
    notificationsEnabled: true,
    reminderTime: '09:00',
    createdAt: now,
    modifiedAt: now,
  );
}

/// Database whose transactions always fail, so a reset's capture/delete step
/// throws before anything is captured or cancelled.
class _FailingTransactionDatabase extends AppDatabase {
  _FailingTransactionDatabase() : super(NativeDatabase.memory());

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    throw StateError('synthetic transaction failure');
  }
}

Future<void> _insertHabitRow(
  AppDatabase db,
  String id, {
  bool softDeleted = false,
  bool active = true,
}) {
  final now = DateTime.utc(2026, 3, 18, 12);
  return db
      .into(db.habits)
      .insert(
        HabitsCompanion.insert(
          id: id,
          name: 'Fixture habit $id',
          createdAt: now,
          modifiedAt: now,
          reminderTime: const Value('09:00'),
          notificationsEnabled: const Value(true),
          isActive: Value(active),
          isDeleted: Value(softDeleted),
        ),
      );
}

Future<int> _countRows(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  late _FakeNotificationPlatform platform;
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
    // The plugin resolves its implementation through the registered platform
    // instance; each test pins defaultTargetPlatform to iOS inside setUp.
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    platform = _FakeNotificationPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, platform.handle);
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Locale only affects notification copy; pin it so the habit service
        // does not pull the settings stream into this test's provider graph.
        localeOverrideProvider.overrideWithValue(null),
      ],
    );
    // Build the reset notifier before the assertion so `reset()` reports a
    // failure through its state instead of a not-yet-built provider.
    await container.read(resetDataNotifierProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('resetting habit data leaves no pending habit reminder', () async {
    final habit = _habitFixture('habit-reset-1');
    await _insertHabitRow(db, habit.id);

    final service = container.read(habitNotificationServiceProvider);
    final local = container.read(localNotificationServiceProvider);
    await service.scheduleForHabit(habit);

    // Guard against a vacuous pass: the fixture must really be on the OS-side
    // pending table, in the habit namespace only, and visible through the
    // service's own read path.
    final seriesIds = _habitSeriesIds(habit.id);
    expect(
      platform.pendingIds.where(seriesIds.contains),
      hasLength(7),
      reason:
          'a daily habit schedules 7 one-shots (HabitNotificationService.'
          '_dailyOccurrences); pending=${platform.pendingIds}',
    );
    expect(
      (await local.pendingNotificationRequests())
          .map((request) => request.id)
          .where(seriesIds.contains),
      hasLength(7),
    );

    await container
        .read(resetDataNotifierProvider.notifier)
        .reset(ResetCategory.habits);

    expect(await _countRows(db, 'habits'), 0);
    expect(await _countRows(db, 'habit_completions'), 0);

    final orphaned = (await local.pendingNotificationRequests())
        .map((request) => request.id)
        .where(seriesIds.contains)
        .toList();
    expect(
      orphaned,
      isEmpty,
      reason:
          'resetting habit data deleted the habit rows, so its reminder IDs '
          'must be cancelled before this point; they are now orphans that fire '
          'against an empty habits screen. Still pending: $orphaned '
          '(namespace ${_habitBaseId(habit.id)}..'
          '${_habitBaseId(habit.id) + _habitSeriesWidth - 1}).',
    );
  });

  test('resetting habit data also retracts a soft-deleted habit row', () async {
    // A habit soft-deleted by a sync-inbound change keeps its already
    // scheduled reminders; the reset deletes that row too, so its IDs must be
    // retracted as well (a capture that filters `is_deleted = 0` leaks them).
    final habit = _habitFixture('habit-reset-soft-deleted');
    await _insertHabitRow(db, habit.id, softDeleted: true);

    final service = container.read(habitNotificationServiceProvider);
    await service.scheduleForHabit(habit);

    final seriesIds = _habitSeriesIds(habit.id);
    expect(platform.pendingIds.where(seriesIds.contains), isNotEmpty);

    await container
        .read(resetDataNotifierProvider.notifier)
        .reset(ResetCategory.habits);

    expect(await _countRows(db, 'habits'), 0);
    expect(
      platform.pendingIds.where(seriesIds.contains),
      isEmpty,
      reason: 'soft-deleted habit rows are deleted by the reset as well',
    );
  });

  test('resetting habit data also retracts an inactive habit row', () async {
    // A habit deactivated by a sync-inbound change keeps the reminders that were
    // scheduled while it was active; the reset deletes that row too, so a
    // capture filtering `is_active = 1` would leak those IDs.
    final habit = _habitFixture('habit-reset-inactive');
    await _insertHabitRow(db, habit.id, active: false);

    final service = container.read(habitNotificationServiceProvider);
    await service.scheduleForHabit(habit);

    final seriesIds = _habitSeriesIds(habit.id);
    expect(platform.pendingIds.where(seriesIds.contains), isNotEmpty);

    await container
        .read(resetDataNotifierProvider.notifier)
        .reset(ResetCategory.habits);

    expect(await _countRows(db, 'habits'), 0);
    expect(
      platform.pendingIds.where(seriesIds.contains),
      isEmpty,
      reason: 'inactive habit rows are deleted by the reset as well',
    );
  });

  test('a stale reschedule batch cannot re-arm a habit the reset deleted', () async {
    // Interleaving: rescheduleAll([A, B]) is already inside A when the reset
    // deletes and cancels both habits. When A finishes, the batch advances to
    // B; without a batch-epoch bump at bulk cancellation, scheduleForHabit(B)
    // starts AFTER cancel(B), takes a fresh per-habit generation, and arms
    // seven IDs for a habit that no longer exists (handoff addenda 2-3).
    //
    // B is pinned to zero pending IDs before the batch, while the batch is
    // suspended, and after release, so a failure here identifies NEWLY ARMED B
    // rather than A's already-proven reset orphan. The gate sits after the fake
    // records A's final one-shot and before that call completes, and never
    // holds a cancellation.
    final habitA = _habitFixture('batch-stale-a');
    final habitB = _habitFixture('batch-stale-b');
    await _insertHabitRow(db, habitA.id);
    await _insertHabitRow(db, habitB.id);

    final seriesA = _habitSeriesIds(habitA.id);
    final seriesB = _habitSeriesIds(habitB.id);
    expect(
      seriesA.intersection(seriesB),
      isEmpty,
      reason: 'fixture habit IDs must not share a notification series',
    );
    expect(platform.pendingIds.where(seriesA.contains), isEmpty);
    expect(platform.pendingIds.where(seriesB.contains), isEmpty);

    final service = container.read(habitNotificationServiceProvider);

    // Gate on the last of A's seven daily one-shots (_dailyOccurrences - 1).
    platform.gatedScheduleId = _habitBaseId(habitA.id) + 6;
    platform.gateEntered = Completer<void>();
    platform.gateReleased = Completer<void>();

    Object? drainFailure;
    final batch = service.rescheduleAll([habitA, habitB]);
    try {
      try {
        await platform.gateEntered!.future.timeout(_gateHoldTimeout);
      } on TimeoutException {
        fail(
          'the batch never reached the gated one-shot, so the interleaving '
          'fixture is broken (not a fix result)',
        );
      }

      // Suspended inside A: A armed, B has never been scheduled by anyone.
      expect(platform.pendingIds.where(seriesA.contains), isNotEmpty);
      expect(platform.pendingIds.where(seriesB.contains), isEmpty);

      // The real reset deletes both rows and cancels both series while the batch
      // is still suspended inside A.
      await container
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.habits);

      expect(await _countRows(db, 'habits'), 0);
      expect(
        platform.pendingIds.where(seriesB.contains),
        isEmpty,
        reason: 'reset-during-gate must leave B with no pending reminder',
      );
    } finally {
      // Always release the held platform call — even after a gate timeout, a
      // throwing reset or a failed assertion — so no scheduled call stays
      // suspended, then drain the batch under the bounded timeout. A drain
      // failure is recorded and surfaced after the assertions below instead of
      // masking an earlier one.
      final released = platform.gateReleased;
      if (released != null && !released.isCompleted) released.complete();
      try {
        await batch.timeout(_batchDrainTimeout);
      } catch (error) {
        drainFailure = error;
      }
    }

    // Released in the finally block; the stale batch has now had its chance to
    // advance into the deleted B.

    final armedB = platform.pendingIds
        .where(seriesB.contains)
        .toList()
        .toString();
    expect(
      platform.pendingIds.where(seriesB.contains),
      isEmpty,
      reason:
          'the stale batch armed B after the reset deleted and cancelled it: '
          'pending=$armedB (series ${_habitBaseId(habitB.id)}..'
          '${_habitBaseId(habitB.id) + _habitSeriesWidth - 1}). Bulk '
          'cancellation must bump the batch epoch before any await, so a stale '
          'list cannot start a later habit.',
    );
    // Only meaningful once B's assertion passes: A is cancelled too.
    expect(platform.pendingIds.where(seriesA.contains), isEmpty);
    expect(
      drainFailure,
      isNull,
      reason:
          'the stale batch did not finish cleanly within the drain timeout '
          'after the gate was released: $drainFailure',
    );
  });

  test('habit reset leaves other notification namespaces pending', () async {
    platform.seedForeignPending(_frontingId, 'prism:fronting:fixture');
    platform.seedForeignPending(_reminderId, 'prism:reminder:fixture');

    final habit = _habitFixture('habit-reset-2');
    // Created up front so the attribution guard can include its owned series;
    // the replacement is deliberately scheduled only after the reset.
    final replacement = _habitFixture('habit-after-reset');
    await _insertHabitRow(db, habit.id);
    final service = container.read(habitNotificationServiceProvider);
    await service.scheduleForHabit(habit);

    await container
        .read(resetDataNotifierProvider.notifier)
        .reset(ResetCategory.habits);

    expect(
      platform.pendingIds,
      contains(_frontingId),
      reason: 'fronting notifications are not habit-owned',
    );
    expect(
      platform.pendingIds,
      contains(_reminderId),
      reason: 'reminder notifications are not habit-owned',
    );
    // No app-wide wipe, and no hard-bounded range: every cancellation must be
    // attributable to the owned series of a habit this reset deleted (or of the
    // replacement, which is the only habit scheduled after it). A series
    // reaches base+29, so the top base legitimately owns IDs past 3_099_999.
    final ownedSeries = {
      ..._habitSeriesIds(habit.id),
      ..._habitSeriesIds(replacement.id),
    };
    for (final id in platform.cancelledIds) {
      expect(
        ownedSeries,
        contains(id),
        reason:
            'reset cancelled notification ID $id, which belongs to no habit '
            'row this reset deleted; habit cleanup must be scoped to the owned '
            'series of the captured habit IDs',
      );
    }
    expect(
      platform.methods,
      isNot(
        anyOf(contains('cancelAll'), contains('cancelAllPendingNotifications')),
      ),
    );

    // Active habits must keep scheduling normally after a habit reset.
    await _insertHabitRow(db, replacement.id);
    await service.scheduleForHabit(replacement);
    expect(
      platform.pendingIds.where(_habitSeriesIds(replacement.id).contains),
      isNotEmpty,
      reason: 'habit scheduling must still work after a reset',
    );
  });

  test('owned-ID attribution admits the real namespace upper edge', () {
    // Review finding this guards: the service owns base..base+29, so an
    // upper-edge habit is cancelled above 3_099_999. A hard
    // 3_000_000..3_099_999 bound would reject that correct cancellation (and
    // mask an over-cancel in the same 29-ID tail), so attribution is by owned
    // series. This is pure arithmetic: no hashing, no scan, no unbounded loop.
    const topBase = _habitIdBase + _habitIdMod - 1; // 3_099_999
    final owned = _ownedSeries(topBase);

    expect(owned, hasLength(_habitSeriesWidth));
    expect(owned, contains(3_100_028));
    expect(
      owned.where((id) => id > topBase),
      isNotEmpty,
      reason: 'a hard 3_099_999 bound would reject IDs this habit really owns',
    );
    // The tail still stays clear of the other subsystems' namespaces.
    expect(owned, isNot(contains(_frontingId)));
    expect(owned, isNot(contains(_reminderId)));
  });

  test('a failed reminder cancel reports the delete truthfully', () async {
    final habitA = _habitFixture('cancel-failure-a');
    final habitB = _habitFixture('cancel-failure-b');
    await _insertHabitRow(db, habitA.id);
    await _insertHabitRow(db, habitB.id);

    final service = container.read(habitNotificationServiceProvider);
    await service.scheduleForHabit(habitA);
    await service.scheduleForHabit(habitB);

    final seriesA = _habitSeriesIds(habitA.id);
    final seriesB = _habitSeriesIds(habitB.id);
    expect(
      seriesA.intersection(seriesB),
      isEmpty,
      reason: 'fixture habit IDs must not share a notification series',
    );
    expect(platform.pendingIds.where(seriesA.contains), hasLength(7));
    expect(platform.pendingIds.where(seriesB.contains), hasLength(7));

    // Observers must still be told about the committed delete, even though the
    // reminder cleanup below fails.
    final emptied = Completer<void>();
    final subscription = db.select(db.habits).watch().listen((rows) {
      if (rows.isEmpty && !emptied.isCompleted) emptied.complete();
    });
    addTearDown(subscription.cancel);

    // Every cancellation for A fails; B's succeed.
    platform.failCancelIds = seriesA;
    platform.calls.clear();

    Object? resetError;
    try {
      await container
          .read(resetDataNotifierProvider.notifier)
          .reset(ResetCategory.habits);
    } catch (error) {
      resetError = error;
    }

    // Truthful non-success, with no habit names or IDs in the message.
    expect(
      resetError,
      isNotNull,
      reason: 'a failed reminder cancel must not report a clean success',
    );
    final message = resetError.toString();
    expect(message.toLowerCase(), contains('deleted'));
    expect(message.toLowerCase(), contains('may still fire'));
    expect(message, isNot(contains(habitA.id)));
    expect(message, isNot(contains(habitB.id)));
    expect(message, isNot(contains('${_habitBaseId(habitA.id)}')));
    expect(message, isNot(contains('${_habitBaseId(habitB.id)}')));
    // The existing AsyncError route carries the failure as well.
    expect(container.read(resetDataNotifierProvider).hasError, isTrue);

    // The delete is committed and observers saw it.
    expect(await _countRows(db, 'habits'), 0);
    await emptied.future.timeout(const Duration(seconds: 5));

    // Every ID was attempted: B's series is gone, A's could not be retracted.
    expect(
      platform.cancelledIds.where(seriesA.contains).toSet(),
      hasLength(_habitSeriesWidth),
      reason: 'every ID of the failing habit must be attempted',
    );
    expect(
      platform.cancelledIds.where(seriesB.contains).toSet(),
      hasLength(_habitSeriesWidth),
      reason: 'a failure on one habit must not strand another',
    );
    expect(
      platform.pendingIds.where(seriesB.contains),
      isEmpty,
      reason: 'B was cancelled successfully and must not linger',
    );
    expect(
      platform.pendingIds.where(seriesA.contains),
      isNotEmpty,
      reason: 'A could not be cancelled, which is why the error must say so',
    );
  });

  test(
    'a failed reset transaction cancels nothing and loses no data',
    () async {
      final failingDb = _FailingTransactionDatabase();
      addTearDown(failingDb.close);
      final failingContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(failingDb),
          localeOverrideProvider.overrideWithValue(null),
        ],
      );
      addTearDown(failingContainer.dispose);
      await failingContainer.read(resetDataNotifierProvider.future);

      final habit = _habitFixture('transaction-failure');
      await _insertHabitRow(failingDb, habit.id);
      final seriesIds = _habitSeriesIds(habit.id);
      await failingContainer
          .read(habitNotificationServiceProvider)
          .scheduleForHabit(habit);
      expect(platform.pendingIds.where(seriesIds.contains), hasLength(7));

      platform.calls.clear();
      Object? resetError;
      try {
        await failingContainer
            .read(resetDataNotifierProvider.notifier)
            .reset(ResetCategory.habits);
      } catch (error) {
        resetError = error;
      }

      // The transaction failure surfaces as itself, is not masked by a cancel
      // failure, and nothing was cancelled or deleted.
      expect(resetError, isA<StateError>());
      expect(resetError.toString(), contains('synthetic transaction failure'));
      expect(
        platform.cancelledIds,
        isEmpty,
        reason: 'a transaction that never committed must cancel nothing',
      );
      expect(platform.pendingIds.where(seriesIds.contains), hasLength(7));
      expect(await _countRows(failingDb, 'habits'), 1);
    },
  );

  test(
    'ordinary per-habit cancellation leaves another habit scheduled',
    () async {
      final habitA = _habitFixture('per-habit-a');
      final habitB = _habitFixture('per-habit-b');
      await _insertHabitRow(db, habitA.id);
      await _insertHabitRow(db, habitB.id);

      final service = container.read(habitNotificationServiceProvider);
      await service.scheduleForHabit(habitA);
      await service.scheduleForHabit(habitB);
      expect(
        _habitSeriesIds(habitA.id).intersection(_habitSeriesIds(habitB.id)),
        isEmpty,
        reason: 'fixture habit IDs must not share a notification series',
      );

      // The cancellation the ordinary per-habit delete route performs before it
      // removes the row (habit_providers.dart `deleteHabit`).
      await service.cancelForHabit(habitA.id);

      expect(
        platform.pendingIds.where(_habitSeriesIds(habitA.id).contains),
        isEmpty,
      );
      expect(
        platform.pendingIds.where(_habitSeriesIds(habitB.id).contains),
        hasLength(7),
        reason: 'cancelling one habit must not touch another active habit',
      );
    },
  );

  test('habit scheduling still works after a successful reset', () async {
    final removed = _habitFixture('post-reset-removed');
    await _insertHabitRow(db, removed.id);

    final service = container.read(habitNotificationServiceProvider);
    await service.scheduleForHabit(removed);
    expect(
      platform.pendingIds.where(_habitSeriesIds(removed.id).contains),
      hasLength(7),
    );

    await container
        .read(resetDataNotifierProvider.notifier)
        .reset(ResetCategory.habits);

    expect(await _countRows(db, 'habits'), 0);
    expect(
      platform.pendingIds.where(_habitSeriesIds(removed.id).contains),
      isEmpty,
      reason: 'a successful reset retracts the removed habit reminders',
    );

    final fresh = _habitFixture('post-reset-fresh');
    expect(
      _habitSeriesIds(removed.id).intersection(_habitSeriesIds(fresh.id)),
      isEmpty,
      reason: 'fixture habit IDs must not share a notification series',
    );
    await _insertHabitRow(db, fresh.id);
    await service.scheduleForHabit(fresh);
    expect(
      platform.pendingIds.where(_habitSeriesIds(fresh.id).contains),
      hasLength(7),
      reason: 'a successful reset must not disable habit scheduling',
    );
  });
}
