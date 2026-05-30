import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/services/bio_image_size.dart';
import 'package:prism_plurality/features/members/widgets/bio_image_widget.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// A minimal 1×1 gray PNG that is known to decode in the Flutter test
/// environment. (Same fixture used in member_profile_header_test.dart and
/// group_avatar_picker_test.dart.)
final Uint8List _kOnePxPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

/// Builds a [BioImageWidget] on the `overrideBytes` rendering path so the test
/// exercises pure layout without any provider/media setup. Intrinsic image
/// dimensions are 800×400 → a 2.0 aspect ratio.
BioImageWidget _bioImage({
  required BioImageSize size,
  double? maxContentWidth,
}) =>
    BioImageWidget(
      mediaId: '',
      encryptionKeyB64: '',
      ciphertextHash: '',
      plaintextHash: '',
      blurhash: '',
      width: 800,
      height: 400,
      memberName: 'Robin',
      size: size,
      overrideBytes: _kOnePxPng,
      maxContentWidth: maxContentWidth,
    );

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(body: Center(child: child)),
      ),
    );

/// The [SizedBox] produced by `_sized()` — the one that directly wraps the
/// image content. There may be other SizedBoxes deeper in the tree (e.g.
/// `SizedBox.expand` placeholders), so match on the one carrying both a finite
/// width and height that we set.
Finder _sizedBoxWith({required double width, required double height}) {
  return find.byWidgetPredicate(
    (w) => w is SizedBox && w.width == width && w.height == height,
  );
}

Image _renderedImage(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image));

void main() {
  group('BioImageWidget sizing', () {
    testWidgets('explicit #WxH renders a 200x150 box at BoxFit.contain', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_bioImage(size: BioImageSize.parse('200x150'))),
      );
      await tester.pump();

      final box = _sizedBoxWith(width: 200, height: 150);
      expect(box, findsOneWidget);
      expect(tester.getSize(box), const Size(200, 150));

      // Guard against a regression to BoxFit.fill, which would distort.
      expect(_renderedImage(tester).fit, BoxFit.contain);
    });

    testWidgets('width-only derives height from aspect ratio', (tester) async {
      // width 200, aspectRatio 2.0 → height 100.
      await tester.pumpWidget(
        _wrap(_bioImage(size: BioImageSize.parse('200'))),
      );
      await tester.pump();

      final box = _sizedBoxWith(width: 200, height: 100);
      expect(box, findsOneWidget);
      expect(tester.getSize(box), const Size(200, 100));
      expect(_renderedImage(tester).fit, BoxFit.contain);
    });

    testWidgets('height-only derives width from aspect ratio', (tester) async {
      // height 150, aspectRatio 2.0 → width 300.
      await tester.pumpWidget(
        _wrap(_bioImage(size: BioImageSize.parse('x150'))),
      );
      await tester.pump();

      final box = _sizedBoxWith(width: 300, height: 150);
      expect(box, findsOneWidget);
      expect(tester.getSize(box), const Size(300, 150));
      expect(_renderedImage(tester).fit, BoxFit.contain);
    });

    testWidgets('percent width is a fraction of the available width', (
      tester,
    ) async {
      // 50% of a 400px-wide parent → width 200, height 200/2.0 = 100.
      // Use a LOOSE max-width (ConstrainedBox, not SizedBox): the widget reads
      // constraints.maxWidth in a LayoutBuilder, and a tight 400 width would
      // propagate through and force the inner box to 400. In the real app the
      // width constraint (markdown content width) is loose, like this.
      await tester.pumpWidget(
        _wrap(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _bioImage(size: BioImageSize.parse('50%')),
          ),
        ),
      );
      await tester.pump();

      final box = _sizedBoxWith(width: 200, height: 100);
      expect(box, findsOneWidget);
      expect(tester.getSize(box).width, 200);
      expect(_renderedImage(tester).fit, BoxFit.contain);
    });

    testWidgets('percent honors maxContentWidth even when width is unbounded', (
      tester,
    ) async {
      // Inline images render in an unbounded-width context (WidgetSpan), where
      // the widget's own LayoutBuilder reads infinity and falls back to 280.
      // The host-supplied maxContentWidth (from PrismMarkdownText) is what makes
      // percent actually work — 50% of 300 = 150 (height 150/2.0 = 75).
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _bioImage(
              size: BioImageSize.parse('50%'),
              maxContentWidth: 300,
            ),
          ),
        ),
      );
      await tester.pump();

      final box = _sizedBoxWith(width: 150, height: 75);
      expect(box, findsOneWidget);
      expect(tester.getSize(box).width, 150);
      expect(_renderedImage(tester).fit, BoxFit.contain);
    });

    testWidgets('unset uses ConstrainedBox + AspectRatio, capped to maxHeight', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_bioImage(size: BioImageSize.unset)),
      );
      await tester.pump();

      // Default path wraps in ConstrainedBox(maxHeight: 280) + AspectRatio(2.0),
      // not a fixed SizedBox from _sized().
      final constrained = find.byType(ConstrainedBox);
      expect(constrained, findsWidgets);

      final aspect = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(aspect.aspectRatio, 2.0);

      // Rendered height must respect the 280 max-height cap.
      expect(
        tester.getSize(find.byType(AspectRatio)).height,
        lessThanOrEqualTo(280.0),
      );
      expect(_renderedImage(tester).fit, BoxFit.contain);
    });
  });
}
