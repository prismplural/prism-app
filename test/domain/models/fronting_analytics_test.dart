import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';

void main() {
  group('TimeBucket.fromHour', () {
    test('hour 0 -> night', () {
      expect(TimeBucket.fromHour(0), TimeBucket.night);
    });

    test('hour 5 -> night', () {
      expect(TimeBucket.fromHour(5), TimeBucket.night);
    });

    test('hour 6 -> morning', () {
      expect(TimeBucket.fromHour(6), TimeBucket.morning);
    });

    test('hour 11 -> morning', () {
      expect(TimeBucket.fromHour(11), TimeBucket.morning);
    });

    test('hour 12 -> afternoon', () {
      expect(TimeBucket.fromHour(12), TimeBucket.afternoon);
    });

    test('hour 17 -> afternoon', () {
      expect(TimeBucket.fromHour(17), TimeBucket.afternoon);
    });

    test('hour 18 -> evening', () {
      expect(TimeBucket.fromHour(18), TimeBucket.evening);
    });

    test('hour 23 -> evening', () {
      expect(TimeBucket.fromHour(23), TimeBucket.evening);
    });
  });

  group('TimeBucket.label', () {
    test('morning label', () {
      expect(TimeBucket.morning.label, 'Morning');
    });

    test('afternoon label', () {
      expect(TimeBucket.afternoon.label, 'Afternoon');
    });

    test('evening label', () {
      expect(TimeBucket.evening.label, 'Evening');
    });

    test('night label', () {
      expect(TimeBucket.night.label, 'Night');
    });
  });
}
