import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/fronting_notification_service.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';

class _FakeLocalNotificationService extends LocalNotificationService {
  final List<({int id, String title, String body, Duration interval})>
  scheduleRepeatingWithDurationCalls = [];
  final List<int> cancelCalls = [];

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
    ));
  }

  @override
  Future<void> cancel(int id) async {
    cancelCalls.add(id);
  }
}

void main() {
  group('FrontingNotificationService.scheduleFrontingReminder', () {
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
  });
}
