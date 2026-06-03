import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/features/members/services/bio_image_size.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

/// Captures the `src` attribute each `img` element resolves to, mirroring what
/// BioImageElementBuilder receives.
class _Capture extends MarkdownElementBuilder {
  final List<String> srcs = [];
  @override
  bool isBlockElement() => false;
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    srcs.add(element.attributes['src'] ?? '');
    return const SizedBox.shrink();
  }
}

/// Mirrors BioImageElementBuilder's fragment extraction + decode.
BioImageSize _sizeFromSrc(String src) {
  final hashIdx = src.indexOf('#');
  var fragment = hashIdx >= 0 ? src.substring(hashIdx + 1) : null;
  if (fragment != null) {
    try {
      fragment = Uri.decodeComponent(fragment);
    } catch (_) {}
  }
  return BioImageSize.parse(fragment);
}

void main() {
  testWidgets(
    'percent image fragments survive markdown URL encoding (#50% -> 50%25)',
    (tester) async {
      final cap = _Capture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              data: 'a ![](flag#25%) b ![](flag#50%) c ![](flag#200) '
                  'd ![](flag#120x40)',
              imgElementBuilder: cap,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(cap.srcs, hasLength(4));
      // Documents the quirk: the markdown layer percent-encodes `%` -> `%25`.
      expect(cap.srcs[0], 'flag#25%25');
      expect(cap.srcs[1], 'flag#50%25');
      expect(cap.srcs[2], 'flag#200'); // px untouched
      expect(cap.srcs[3], 'flag#120x40');

      // The decode step recovers real percentage sizing.
      expect(_sizeFromSrc(cap.srcs[0]).widthFraction, 0.25);
      expect(_sizeFromSrc(cap.srcs[1]).widthFraction, 0.5);
      // Px / WxH still parse correctly through the same path.
      expect(_sizeFromSrc(cap.srcs[2]).width, 200);
      expect(_sizeFromSrc(cap.srcs[3]).width, 120);
      expect(_sizeFromSrc(cap.srcs[3]).height, 40);
    },
  );

  testWidgets('em fragments pass through markdown URL encoding untouched', (
    tester,
  ) async {
    final cap = _Capture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownText(
            data: 'a ![](flag#10em) b',
            imgElementBuilder: cap,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(cap.srcs, hasLength(1));
    // No `%` in the fragment → the markdown layer leaves it untouched.
    expect(cap.srcs[0], 'flag#10em');
    expect(_sizeFromSrc(cap.srcs[0]).widthEm, 10);
  });
}
