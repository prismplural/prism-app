import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

void main() {
  group('PrismShapes', () {
    test('rounded mode returns input radius', () {
      expect(PrismShapes.rounded.radius(16), 16);
      expect(PrismShapes.rounded.radius(0), 0);
      expect(PrismShapes.rounded.radius(24), 24);
    });

    test('angular mode zeros out radius', () {
      expect(PrismShapes.angular.radius(16), 0);
      expect(PrismShapes.angular.radius(999), 0);
    });

    test('pill() returns half-height when rounded, 0 when angular', () {
      expect(PrismShapes.rounded.pill(48), 24);
      expect(PrismShapes.angular.pill(48), 0);
    });

    test('avatarShape switches between circle and rectangle', () {
      expect(PrismShapes.rounded.avatarShape(), BoxShape.circle);
      expect(PrismShapes.angular.avatarShape(), BoxShape.rectangle);
    });

    test('avatarBorderRadius is null when rounded, zero when angular', () {
      expect(PrismShapes.rounded.avatarBorderRadius(), isNull);
      expect(PrismShapes.angular.avatarBorderRadius(), BorderRadius.zero);
    });

    test('circleOrSquareBorder returns CircleBorder when rounded', () {
      expect(PrismShapes.rounded.circleOrSquareBorder(), isA<CircleBorder>());
    });

    test('circleOrSquareBorder returns zero-radius rect when angular', () {
      final border = PrismShapes.angular.circleOrSquareBorder();
      expect(border, isA<RoundedRectangleBorder>());
      expect((border as RoundedRectangleBorder).borderRadius, BorderRadius.zero);
    });

    test('copyWith overrides cornerStyle', () {
      final copy = PrismShapes.rounded.copyWith(cornerStyle: CornerStyle.angular);
      expect(copy.cornerStyle, CornerStyle.angular);
    });

    test('copyWith without args preserves cornerStyle', () {
      final copy = PrismShapes.angular.copyWith();
      expect(copy.cornerStyle, CornerStyle.angular);
    });

    test('lerp snaps at t >= 0.5', () {
      final result1 = PrismShapes.rounded.lerp(PrismShapes.angular, 0.3);
      expect(result1.cornerStyle, CornerStyle.rounded);
      final result2 = PrismShapes.rounded.lerp(PrismShapes.angular, 0.7);
      expect(result2.cornerStyle, CornerStyle.angular);
      final result3 = PrismShapes.rounded.lerp(PrismShapes.angular, 0.5);
      expect(result3.cornerStyle, CornerStyle.angular);
    });

    test('lerp returns this when other is not PrismShapes', () {
      final result = PrismShapes.rounded.lerp(null, 0.7);
      expect(result, PrismShapes.rounded);
    });

    test('Theme.of retrieval via PrismShapes.of works and falls back when missing', () {
      // Widget test: pump a MaterialApp with and without the extension.
      // Use testWidgets for this case. Separate from the `test()` group is fine.
    });
  });

  testWidgets('PrismShapes.of returns attached extension', (tester) async {
    late PrismShapes resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [PrismShapes.angular]),
        home: Builder(
          builder: (context) {
            resolved = PrismShapes.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved.cornerStyle, CornerStyle.angular);
  });

  testWidgets('PrismShapes.of falls back to rounded when extension missing', (tester) async {
    late PrismShapes resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = PrismShapes.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved.cornerStyle, CornerStyle.rounded);
  });
}
