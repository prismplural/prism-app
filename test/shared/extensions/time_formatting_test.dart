import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Pumps a tiny widget tree with the given MediaQueryData and returns its
/// BuildContext so we can exercise context-aware time-format helpers.
Future<BuildContext> _contextWith(
  WidgetTester tester, {
  required bool alwaysUse24HourFormat,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(alwaysUse24HourFormat: alwaysUse24HourFormat),
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  setUpAll(() async {
    // intl's locale-aware formatters need locale data loaded for non-en_US.
    await initializeDateFormatting();
  });

  group('context.formatTime', () {
    testWidgets('alwaysUse24HourFormat=true forces 24-hour output',
        (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: true);
      // 2:30 PM = 14:30
      final dt = DateTime(2026, 1, 1, 14, 30);
      final out = context.formatTime(dt);
      expect(out, contains('14:30'));
      expect(out, isNot(contains('PM')));
      expect(out, isNot(contains('AM')));
    });

    testWidgets('alwaysUse24HourFormat=false uses 12-hour output',
        (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: false);
      final dt = DateTime(2026, 1, 1, 14, 30);
      final out = context.formatTime(dt);
      expect(out, contains('2:30'));
      // Expect AM/PM marker (or a localized equivalent containing 'M').
      expect(out.toUpperCase(), contains('PM'));
    });

    testWidgets('midnight in 24-hour mode renders as 00:00', (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: true);
      final dt = DateTime(2026, 1, 1, 0, 0);
      final out = context.formatTime(dt);
      expect(out, contains('00:00'));
    });

    testWidgets('midnight in 12-hour mode renders as 12:00 AM', (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: false);
      final dt = DateTime(2026, 1, 1, 0, 0);
      final out = context.formatTime(dt);
      expect(out, contains('12:00'));
      expect(out.toUpperCase(), contains('AM'));
    });
  });

  group('context.formatDateTime', () {
    testWidgets('24-hour mode embeds 24-hour time in date+time string',
        (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: true);
      final dt = DateTime(2026, 3, 9, 14, 30);
      final out = context.formatDateTime(dt);
      expect(out, contains('14:30'));
      expect(out, isNot(contains('PM')));
    });

    testWidgets('12-hour mode embeds 12-hour time in date+time string',
        (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: false);
      final dt = DateTime(2026, 3, 9, 14, 30);
      final out = context.formatDateTime(dt);
      expect(out, contains('2:30'));
      expect(out.toUpperCase(), contains('PM'));
    });

    testWidgets('includes year for dates outside current year', (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: false);
      final dt = DateTime(2024, 3, 9, 14, 30);
      final out = context.formatDateTime(dt);
      expect(out, contains('2024'));
    });

    testWidgets('omits year for dates in current year', (tester) async {
      final context = await _contextWith(tester, alwaysUse24HourFormat: false);
      final now = DateTime.now();
      final dt = DateTime(now.year, 3, 9, 14, 30);
      final out = context.formatDateTime(dt);
      expect(out, isNot(contains(now.year.toString())));
    });
  });

  group('context.use24HourTime', () {
    testWidgets('reflects MediaQuery value when present', (tester) async {
      final ctxOn = await _contextWith(tester, alwaysUse24HourFormat: true);
      expect(ctxOn.use24HourTime, isTrue);
      final ctxOff = await _contextWith(tester, alwaysUse24HourFormat: false);
      expect(ctxOff.use24HourTime, isFalse);
    });
  });
}
