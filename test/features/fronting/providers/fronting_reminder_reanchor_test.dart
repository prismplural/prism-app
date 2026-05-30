import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/fronting_notification_service.dart';
import 'package:prism_plurality/core/services/fronting_reminder_reanchor.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/core/services/notification_providers.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

import '../../../helpers/fake_repositories.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

/// Captures `scheduleFrontingReminder` calls without touching the
/// flutter_local_notifications plugin. Web/headless tests have no plugin.
class _FakeFrontingNotificationService extends FrontingNotificationService {
  _FakeFrontingNotificationService() : super(LocalNotificationService());

  final List<Duration> scheduleCalls = [];
  final List<void> cancelCalls = [];

  @override
  Future<void> scheduleFrontingReminder({required Duration interval}) async {
    scheduleCalls.add(interval);
  }

  @override
  Future<void> cancelFrontingReminder() async {
    cancelCalls.add(null);
  }
}

class _FakeStartFrontingMutationService extends FrontingMutationService {
  _FakeStartFrontingMutationService()
    : super(
        repository: FakeFrontingSessionRepository(),
        mutationRunner: MutationRunner(
          transactionRunner: <T>(action) => action(),
        ),
      );

  @override
  Future<MutationResult<FrontingMutationResult>> startFronting(
    List<String> memberIds, {
    DateTime? startTime,
    FrontConfidence? confidence,
    String? notes,
  }) async {
    return MutationResult.success(
      FrontingMutationResult(
        sessions: [
          for (final id in memberIds)
            FrontingSession(
              id: 'session-$id',
              startTime: startTime ?? DateTime(2026, 5, 25, 10),
              memberId: id,
            ),
        ],
        previousMemberIds: const [],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

ProviderContainer _buildContainer({
  required _FakeFrontingNotificationService fakeNotif,
  required FakeAppPreferenceRepository prefRepo,
  required bool remindersEnabled,
  required int reminderIntervalMinutes,
}) {
  return ProviderContainer(
    overrides: [
      frontingMutationServiceProvider.overrideWithValue(
        _FakeStartFrontingMutationService(),
      ),
      frontingNotificationServiceProvider.overrideWithValue(fakeNotif),
      appPreferenceRepositoryProvider.overrideWithValue(prefRepo),
      frontingRemindersEnabledProvider.overrideWith((_) => remindersEnabled),
      frontingReminderIntervalProvider.overrideWith(
        (_) => reminderIntervalMinutes,
      ),
    ],
  );
}

/// Lets the unawaited best-effort `_reanchorFrontingReminderIfNeeded`
/// future inside FrontingNotifier complete. The repo read is async, so
/// a single microtask isn't enough.
Future<void> _settleReanchor() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('FrontingNotifier.startFronting — reminder re-anchor', () {
    // Regression for Codex P1 #2: the helper used to read
    // `ref.read(frontingReminderSuppressMinutesProvider).value`, which
    // is null until the AsyncNotifier's first build() resolves. A user
    // who logs a front immediately after app start would silently skip
    // the re-anchor. The helper now reads the repo directly, so this
    // test deliberately does NOT prime the AsyncNotifier first.
    test(
      're-anchors on the very first call without priming the notifier '
      '(AsyncNotifier first-load race)',
      () async {
        final prefRepo = FakeAppPreferenceRepository()
          ..seed(frontingReminderSuppressMinutesPreference, 5);
        final fakeNotif = _FakeFrontingNotificationService();
        final container = _buildContainer(
          fakeNotif: fakeNotif,
          prefRepo: prefRepo,
          remindersEnabled: true,
          reminderIntervalMinutes: 30,
        );
        addTearDown(container.dispose);

        // No prior read of frontingReminderSuppressMinutesProvider.
        await container
            .read(frontingNotifierProvider.notifier)
            .startFronting(['m1']);
        await _settleReanchor();

        expect(fakeNotif.scheduleCalls, hasLength(1));
        expect(fakeNotif.scheduleCalls.single, const Duration(minutes: 30));
      },
    );

    test('does NOT re-anchor when suppress == 0', () async {
      final prefRepo = FakeAppPreferenceRepository()
        ..seed(frontingReminderSuppressMinutesPreference, 0);
      final fakeNotif = _FakeFrontingNotificationService();
      final container = _buildContainer(
        fakeNotif: fakeNotif,
        prefRepo: prefRepo,
        remindersEnabled: true,
        reminderIntervalMinutes: 30,
      );
      addTearDown(container.dispose);

      await container
          .read(frontingNotifierProvider.notifier)
          .startFronting(['m1']);
      await _settleReanchor();

      expect(fakeNotif.scheduleCalls, isEmpty);
    });

    test('does NOT re-anchor when fronting reminders are disabled', () async {
      final prefRepo = FakeAppPreferenceRepository()
        ..seed(frontingReminderSuppressMinutesPreference, 10);
      final fakeNotif = _FakeFrontingNotificationService();
      final container = _buildContainer(
        fakeNotif: fakeNotif,
        prefRepo: prefRepo,
        remindersEnabled: false,
        reminderIntervalMinutes: 30,
      );
      addTearDown(container.dispose);

      await container
          .read(frontingNotifierProvider.notifier)
          .startFronting(['m1']);
      await _settleReanchor();

      expect(fakeNotif.scheduleCalls, isEmpty);
    });

    test('re-anchors with whatever reminder interval is configured', () async {
      final prefRepo = FakeAppPreferenceRepository()
        ..seed(frontingReminderSuppressMinutesPreference, 10);
      final fakeNotif = _FakeFrontingNotificationService();
      final container = _buildContainer(
        fakeNotif: fakeNotif,
        prefRepo: prefRepo,
        remindersEnabled: true,
        reminderIntervalMinutes: 60, // 1h
      );
      addTearDown(container.dispose);

      await container
          .read(frontingNotifierProvider.notifier)
          .startFronting(['m1']);
      await _settleReanchor();

      expect(fakeNotif.scheduleCalls, hasLength(1));
      expect(fakeNotif.scheduleCalls.single, const Duration(minutes: 60));
    });

    test(
      'uses the suppress window when it is longer than the reminder interval',
      () async {
        final prefRepo = FakeAppPreferenceRepository()
          ..seed(frontingReminderSuppressMinutesPreference, 30);
        final fakeNotif = _FakeFrontingNotificationService();
        final container = _buildContainer(
          fakeNotif: fakeNotif,
          prefRepo: prefRepo,
          remindersEnabled: true,
          reminderIntervalMinutes: 15,
        );
        addTearDown(container.dispose);

        await container.read(frontingNotifierProvider.notifier).startFronting([
          'm1',
        ]);
        await _settleReanchor();

        expect(fakeNotif.scheduleCalls, hasLength(1));
        expect(fakeNotif.scheduleCalls.single, const Duration(minutes: 30));
      },
    );
  });

  // Direct invocation tests for callers that bypass FrontingNotifier
  // (e.g., PkMappingController.apply, which writes via the mutation
  // service inside its own transaction). Proves the free function is
  // self-sufficient — same control-flow gates, no notifier required.
  group('maybeReanchorFrontingReminder — direct invocation', () {
    test(
      'PkMappingController-style call re-anchors when conditions are met',
      () async {
        final prefRepo = FakeAppPreferenceRepository()
          ..seed(frontingReminderSuppressMinutesPreference, 10);
        final fakeNotif = _FakeFrontingNotificationService();
        final container = ProviderContainer(
          overrides: [
            frontingNotificationServiceProvider.overrideWithValue(fakeNotif),
            appPreferenceRepositoryProvider.overrideWithValue(prefRepo),
            frontingRemindersEnabledProvider.overrideWith((_) => true),
            frontingReminderIntervalProvider.overrideWith((_) => 45),
          ],
        );
        addTearDown(container.dispose);

        // Read the helper through a provider that exposes Ref — same
        // shape any AsyncNotifier (FrontingNotifier, PkMappingController)
        // would call from.
        await container.read(
          Provider<Future<void>>(maybeReanchorFrontingReminder),
        );

        expect(fakeNotif.scheduleCalls, hasLength(1));
        expect(fakeNotif.scheduleCalls.single, const Duration(minutes: 45));
      },
    );

    test('no-op when suppress preference is 0', () async {
      final prefRepo = FakeAppPreferenceRepository()
        ..seed(frontingReminderSuppressMinutesPreference, 0);
      final fakeNotif = _FakeFrontingNotificationService();
      final container = ProviderContainer(
        overrides: [
          frontingNotificationServiceProvider.overrideWithValue(fakeNotif),
          appPreferenceRepositoryProvider.overrideWithValue(prefRepo),
          frontingRemindersEnabledProvider.overrideWith((_) => true),
          frontingReminderIntervalProvider.overrideWith((_) => 45),
        ],
      );
      addTearDown(container.dispose);

      await container.read(
        Provider<Future<void>>(maybeReanchorFrontingReminder),
      );

      expect(fakeNotif.scheduleCalls, isEmpty);
    });

    test('no-op when fronting reminders are disabled', () async {
      final prefRepo = FakeAppPreferenceRepository()
        ..seed(frontingReminderSuppressMinutesPreference, 10);
      final fakeNotif = _FakeFrontingNotificationService();
      final container = ProviderContainer(
        overrides: [
          frontingNotificationServiceProvider.overrideWithValue(fakeNotif),
          appPreferenceRepositoryProvider.overrideWithValue(prefRepo),
          frontingRemindersEnabledProvider.overrideWith((_) => false),
          frontingReminderIntervalProvider.overrideWith((_) => 45),
        ],
      );
      addTearDown(container.dispose);

      await container.read(
        Provider<Future<void>>(maybeReanchorFrontingReminder),
      );

      expect(fakeNotif.scheduleCalls, isEmpty);
    });
  });
}
