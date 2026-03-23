import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/sleep_session.dart';

/// Verifies that enum `.index` produces the expected int values used in
/// sync field maps. These values are written to the wire as integers and
/// must match the sync schema (which declares them as `Int`).
///
/// If enum members are reordered or inserted, these tests will catch the
/// index shift before it causes silent sync corruption.
void main() {
  group('FrontConfidence indices', () {
    test('index values match expected wire format', () {
      expect(FrontConfidence.unsure.index, 0);
      expect(FrontConfidence.strong.index, 1);
      expect(FrontConfidence.certain.index, 2);
    });

    test('.index returns int, not String', () {
      for (final value in FrontConfidence.values) {
        expect(value.index, isA<int>());
      }
    });

    test('all values round-trip through index', () {
      for (final value in FrontConfidence.values) {
        expect(FrontConfidence.values[value.index], value);
      }
    });
  });

  group('SleepQuality indices', () {
    test('index values match expected wire format', () {
      expect(SleepQuality.unknown.index, 0);
      expect(SleepQuality.veryPoor.index, 1);
      expect(SleepQuality.poor.index, 2);
      expect(SleepQuality.fair.index, 3);
      expect(SleepQuality.good.index, 4);
      expect(SleepQuality.excellent.index, 5);
    });

    test('.index returns int, not String', () {
      for (final value in SleepQuality.values) {
        expect(value.index, isA<int>());
      }
    });

    test('all values round-trip through index', () {
      for (final value in SleepQuality.values) {
        expect(SleepQuality.values[value.index], value);
      }
    });
  });

  group('sync field map format', () {
    test('confidence field produces int for sync', () {
      // Simulates what _sessionFields does:
      // 'confidence': s.confidence?.index
      const confidence = FrontConfidence.strong;
      final syncValue = confidence.index;
      expect(syncValue, isA<int>());
      expect(syncValue, 1);
    });

    test('null confidence produces null for sync', () {
      const FrontConfidence? confidence = null;
      final syncValue = confidence?.index;
      expect(syncValue, isNull);
    });

    test('quality field produces int for sync', () {
      // Simulates what _sleepSessionFields does:
      // 'quality': s.quality.index
      const quality = SleepQuality.good;
      final syncValue = quality.index;
      expect(syncValue, isA<int>());
      expect(syncValue, 4);
    });
  });
}
