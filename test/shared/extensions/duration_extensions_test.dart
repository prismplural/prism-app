import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';

void main() {
  group('toVoiceFormat', () {
    test('zero duration', () {
      expect(Duration.zero.toVoiceFormat(), '0:00');
    });

    test('sub-minute', () {
      expect(const Duration(seconds: 5).toVoiceFormat(), '0:05');
    });

    test('exactly one minute', () {
      expect(const Duration(minutes: 1).toVoiceFormat(), '1:00');
    });

    test('mixed minutes and seconds', () {
      expect(const Duration(minutes: 12, seconds: 7).toVoiceFormat(), '12:07');
    });

    test('large value', () {
      expect(const Duration(minutes: 90).toVoiceFormat(), '90:00');
    });
  });

  group('toShortString', () {
    test('seconds only', () {
      expect(const Duration(seconds: 45).toShortString(), '45s');
    });

    test('minutes only', () {
      expect(const Duration(minutes: 23).toShortString(), '23m');
    });

    test('minutes and seconds', () {
      expect(const Duration(minutes: 5, seconds: 30).toShortString(), '5m 30s');
    });

    test('hours only', () {
      expect(const Duration(hours: 2).toShortString(), '2h');
    });

    test('hours and minutes', () {
      expect(const Duration(hours: 1, minutes: 45).toShortString(), '1h 45m');
    });
  });

  group('toRoundedString days', () {
    test('one day zero hours', () {
      expect(const Duration(days: 1).toRoundedString(), '1d 0h');
    });

    test('days with hours', () {
      expect(const Duration(days: 2, hours: 3).toRoundedString(), '2d 3h');
    });

    test('exactly 24 hours', () {
      expect(const Duration(hours: 24).toRoundedString(), '1d 0h');
    });
  });

  group('toRoundedString sub-day', () {
    test('hours and minutes', () {
      expect(const Duration(hours: 2, minutes: 15).toRoundedString(), '2h 15m');
    });

    test('hours without minutes', () {
      expect(const Duration(hours: 3).toRoundedString(), '3h');
    });

    test('minutes only', () {
      expect(const Duration(minutes: 45).toRoundedString(), '45m');
    });

    test('seconds only', () {
      expect(const Duration(seconds: 30).toRoundedString(), '30s');
    });
  });

  group('toLongString', () {
    test('zero duration', () {
      expect(Duration.zero.toLongString(), '0 seconds');
    });

    test('one hour one minute', () {
      expect(
        const Duration(hours: 1, minutes: 1).toLongString(),
        '1 hour, 1 minute',
      );
    });

    test('plural hours and minutes', () {
      expect(
        const Duration(hours: 2, minutes: 30).toLongString(),
        '2 hours, 30 minutes',
      );
    });

    test('seconds when under one minute', () {
      expect(const Duration(seconds: 15).toLongString(), '15 seconds');
    });

    test('one second', () {
      expect(const Duration(seconds: 1).toLongString(), '1 second');
    });
  });
}
