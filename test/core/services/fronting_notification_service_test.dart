import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/fronting_notification_service.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';

class _FakeLocalNotificationService extends LocalNotificationService {
  final List<
    ({
      int id,
      String title,
      String body,
      Duration interval,
      NotificationDetails details,
    })
  >
  scheduleRepeatingWithDurationCalls = [];
  final List<int> cancelCalls = [];
  Completer<void>? cancellation;

  @override
  Future<void> scheduleRepeatingWithDuration({
    required int id,
    required String title,
    required String body,
    required Duration interval,
    required NotificationDetails details,
  }) async {
    scheduleRepeatingWithDurationCalls.add((
      id: id,
      title: title,
      body: body,
      interval: interval,
      details: details,
    ));
  }

  @override
  Future<void> cancel(int id) async {
    cancelCalls.add(id);
    await cancellation?.future;
  }
}

void main() {
  group('FrontingNotificationService.scheduleFrontingReminder', () {
    test('disable during cancellation prevents a late schedule', () async {
      final fake = _FakeLocalNotificationService()
        ..cancellation = Completer<void>();
      final service = FrontingNotificationService(fake);
      final scheduling = service.scheduleFrontingReminder(
        interval: const Duration(minutes: 15),
      );
      final disabling = service.cancelFrontingReminder();
      fake.cancellation!.complete();
      await Future.wait([scheduling, disabling]);
      expect(fake.scheduleRepeatingWithDurationCalls, isEmpty);
    });

    test('provider disposal prevents its unfinished schedule', () async {
      final fake = _FakeLocalNotificationService()
        ..cancellation = Completer<void>();
      final service = FrontingNotificationService(fake);
      final scheduling = service.scheduleFrontingReminder(
        interval: const Duration(minutes: 15),
      );
      service.dispose();
      fake.cancellation!.complete();
      await scheduling;
      expect(fake.scheduleRepeatingWithDurationCalls, isEmpty);
    });
    test(
      'preserves a 15-minute interval instead of collapsing to hourly',
      () async {
        final fake = _FakeLocalNotificationService();
        final service = FrontingNotificationService(fake);

        await service.scheduleFrontingReminder(
          interval: const Duration(minutes: 15),
        );

        expect(fake.cancelCalls, [1000]);
        expect(fake.scheduleRepeatingWithDurationCalls, hasLength(1));
        final call = fake.scheduleRepeatingWithDurationCalls.single;
        expect(call.id, 1000);
        expect(call.interval, const Duration(minutes: 15));
        expect(call.title, 'Fronting Reminder');
        expect(call.body, 'Consider logging who\'s fronting right now.');
      },
    );

    test('preserves longer custom intervals too', () async {
      final fake = _FakeLocalNotificationService();
      final service = FrontingNotificationService(fake);

      await service.scheduleFrontingReminder(
        interval: const Duration(hours: 8),
      );

      expect(fake.scheduleRepeatingWithDurationCalls, hasLength(1));
      expect(
        fake.scheduleRepeatingWithDurationCalls.single.interval,
        const Duration(hours: 8),
      );
    });

    test('uses localized terminology supplied by the provider', () async {
      final fake = _FakeLocalNotificationService();
      final service = FrontingNotificationService(
        fake,
        reminderTitle: 'Recordatorio de presencia',
        reminderBody: 'Abre Prism para comprobar: ¿Quién está presente ahora?',
        reminderChannelName: 'Recordatorios de actividad de Prism',
        reminderChannelDescription:
            'Recordatorios periódicos de actividad de Prism.',
      );

      await service.scheduleFrontingReminder(
        interval: const Duration(hours: 1),
      );

      final call = fake.scheduleRepeatingWithDurationCalls.single;
      expect(call.title, 'Recordatorio de presencia');
      expect(
        call.body,
        'Abre Prism para comprobar: ¿Quién está presente ahora?',
      );
      expect(
        call.details.android?.channelName,
        'Recordatorios de actividad de Prism',
      );
      expect(
        call.details.android?.channelDescription,
        'Recordatorios periódicos de actividad de Prism.',
      );
    });
  });
}
