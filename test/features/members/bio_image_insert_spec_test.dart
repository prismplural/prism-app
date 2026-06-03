import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/bio_image_insert_spec.dart';
import 'package:prism_plurality/features/members/services/bio_image_size.dart';

void main() {
  group('ImageSizeSpec.fragment', () {
    test('default → empty', () {
      expect(const ImageSizeSpec().fragment, '');
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.defaultSize, value: 99).fragment,
        '',
      );
    });

    test('px / percent / em forms', () {
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.widthPx, value: 200).fragment,
        '200',
      );
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.percent, value: 50).fragment,
        '50%',
      );
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.em, value: 10).fragment,
        '10em',
      );
      // Whole em values lose the trailing .0; fractional ones keep it.
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.em, value: 1.5).fragment,
        '1.5em',
      );
    });

    test('fractional px / percent survive (parser supports them)', () {
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.percent, value: 12.5).fragment,
        '12.5%',
      );
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.widthPx, value: 200.5).fragment,
        '200.5',
      );
    });

    test('missing / non-positive value → empty (no sizing)', () {
      expect(const ImageSizeSpec(mode: ImageSizeMode.widthPx).fragment, '');
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.percent, value: 0).fragment,
        '',
      );
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.em, value: -4).fragment,
        '',
      );
    });

    test('clamps to BioImageSize-accepted ranges', () {
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.widthPx, value: 99999).fragment,
        '4096',
      );
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.percent, value: 250).fragment,
        '100%',
      );
      expect(
        const ImageSizeSpec(mode: ImageSizeMode.em, value: 9999).fragment,
        '256em',
      );
    });

    test('every emitted fragment round-trips through BioImageSize.parse', () {
      const px = ImageSizeSpec(mode: ImageSizeMode.widthPx, value: 200);
      expect(BioImageSize.parse(px.fragment).width, 200);

      const pct = ImageSizeSpec(mode: ImageSizeMode.percent, value: 50);
      expect(BioImageSize.parse(pct.fragment).widthFraction, 0.5);

      const em = ImageSizeSpec(mode: ImageSizeMode.em, value: 10);
      expect(BioImageSize.parse(em.fragment).widthEm, 10);

      // Fractional percent must survive the round-trip, not get rounded away.
      const fracPct = ImageSizeSpec(mode: ImageSizeMode.percent, value: 12.5);
      expect(BioImageSize.parse(fracPct.fragment).widthFraction, 0.125);
    });
  });

  group('buildImageRef', () {
    test('bare tag, no alt, default size', () {
      expect(buildImageRef(tag: 'nbflag'), '![](nbflag)');
    });

    test('includes alt when present', () {
      expect(
        buildImageRef(tag: 'nbflag', alt: 'NB flag'),
        '![NB flag](nbflag)',
      );
    });

    test('appends the sizing fragment', () {
      expect(
        buildImageRef(
          tag: 'nbflag',
          alt: 'NB flag',
          size: const ImageSizeSpec(mode: ImageSizeMode.percent, value: 50),
        ),
        '![NB flag](nbflag#50%)',
      );
      expect(
        buildImageRef(
          tag: 'nbflag',
          size: const ImageSizeSpec(mode: ImageSizeMode.em, value: 8),
        ),
        '![](nbflag#8em)',
      );
    });

    test('default size adds no fragment', () {
      expect(
        buildImageRef(tag: 'nbflag', size: const ImageSizeSpec()),
        '![](nbflag)',
      );
    });
  });
}
