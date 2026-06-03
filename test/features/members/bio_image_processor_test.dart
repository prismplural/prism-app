import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';

void main() {
  group('BioImageProcessor.normalizeTag', () {
    test('sanitizes markdown-unsafe characters while preserving case', () {
      expect(
        BioImageProcessor.normalizeTag('  My Cool_Image #1!  '),
        'My-Cool_Image-1',
      );
    });

    test('keeps tags distinct by case', () {
      expect(BioImageProcessor.normalizeTag('Flag'), 'Flag');
      expect(BioImageProcessor.normalizeTag('flag'), 'flag');
    });

    test('returns empty when the tag has no usable characters', () {
      expect(BioImageProcessor.normalizeTag(' )#?! '), isEmpty);
    });
  });
}
