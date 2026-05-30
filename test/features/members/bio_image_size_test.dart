import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/bio_image_size.dart';

void main() {
  group('BioImageSize.parse', () {
    test('null / empty → unset', () {
      expect(BioImageSize.parse(null).isUnset, true);
      expect(BioImageSize.parse('').isUnset, true);
    });

    test('exact WxH (SP-compatible)', () {
      final s = BioImageSize.parse('200x150');
      expect(s.width, 200);
      expect(s.height, 150);
      expect(s.widthFraction, isNull);
    });

    test('width only (200 and 200x both work)', () {
      final a = BioImageSize.parse('200');
      expect(a.width, 200);
      expect(a.height, isNull);

      final b = BioImageSize.parse('200x');
      expect(b.width, 200);
      expect(b.height, isNull);
    });

    test('height only (x150)', () {
      final s = BioImageSize.parse('x150');
      expect(s.width, isNull);
      expect(s.height, 150);
    });

    test('percentage', () {
      expect(BioImageSize.parse('100%').widthFraction, 1.0);
      expect(BioImageSize.parse('50%').widthFraction, 0.5);
      expect(BioImageSize.parse('33%').widthFraction, closeTo(0.33, 0.001));
    });

    test('clamps oversized pixel values', () {
      final s = BioImageSize.parse('99999x99999');
      expect(s.width, 4096);
      expect(s.height, 4096);
    });

    test('garbage → unset', () {
      expect(BioImageSize.parse('abc').isUnset, true);
      expect(BioImageSize.parse('xyz').isUnset, true);
      expect(BioImageSize.parse('-5%').isUnset, true);
    });
  });
}
