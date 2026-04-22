import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Future<AppLocalizations> _loadL10n(String locale) {
  return AppLocalizations.delegate.load(Locale(locale));
}

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

  group('TimeBucket.localizedLabel', () {
    test('resolves English labels', () async {
      final l10n = await _loadL10n('en');
      expect(TimeBucket.morning.localizedLabel(l10n), 'Morning');
      expect(TimeBucket.afternoon.localizedLabel(l10n), 'Afternoon');
      expect(TimeBucket.evening.localizedLabel(l10n), 'Evening');
      expect(TimeBucket.night.localizedLabel(l10n), 'Night');
    });

    test('resolves Spanish labels', () async {
      final l10n = await _loadL10n('es');
      expect(TimeBucket.morning.localizedLabel(l10n), 'Mañana');
      expect(TimeBucket.afternoon.localizedLabel(l10n), 'Tarde');
      expect(TimeBucket.evening.localizedLabel(l10n), 'Noche');
      expect(TimeBucket.night.localizedLabel(l10n), 'Madrugada');
    });
  });
}
