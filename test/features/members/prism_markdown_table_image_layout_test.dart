import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/widgets/prism_markdown_table.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';

/// A minimal 1×1 gray PNG that decodes in the Flutter test environment.
final Uint8List _kOnePxPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

/// A library attachment the bio markdown references by tag (`![](flag)`).
/// Intrinsic dimensions 800×400 → aspect ratio 2.0.
MediaAttachment _flagAttachment() => MediaAttachment(
      id: 'att-flag',
      messageId: 'msg-1',
      tag: 'flag',
      mediaId: 'media-flag',
      mediaType: 'image',
      encryptionKeyB64: base64Encode(List<int>.filled(32, 0)),
      contentHash: 'chash',
      plaintextHash: 'phash',
      mimeType: 'image/png',
      sizeBytes: 1,
      width: 800,
      height: 400,
      durationMs: 0,
      blurhash: '',
      waveformB64: '',
      thumbnailMediaId: '',
      sourceUrl: '',
      previewUrl: '',
    );

/// Renders [data] as a member bio inside a bounded-width column.
///
/// `imageLibraryProvider` resolves the `![](flag)` reference; `mediaFileProvider`
/// returns [bytes] — non-null → a loaded image, null → the "Image expired"
/// placeholder — so the test exercises real layout without a media/download
/// stack. The overrides are inlined (rather than a typed `List<...>`) so the
/// element type is inferred.
Widget _wrap(String data, {required Uint8List? bytes}) => ProviderScope(
      overrides: [
        imageLibraryProvider
            .overrideWith((ref) => Stream.value([_flagAttachment()])),
        mediaFileProvider.overrideWith((ref, params) async => bytes),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: Center(
            // A bounded width — the real member-bio column, not an unbounded box.
            child: SizedBox(
              width: 360,
              child: PrismMarkdownText(data: data, memberName: 'Robin'),
            ),
          ),
        ),
      ),
    );

// Header-only `:::plain` image-beside-text layout tables (2 cols, 1 row) — the
// exact shape that crashed: an image column sized by IntrinsicColumnWidth next
// to a flexing text column.
const _sizedImageTable = ':::plain\n'
    '| ![](flag#120) | Plenty of descriptive text that should wrap inside its '
    'own flexible column beside the image |\n'
    '| --- | --- |\n'
    ':::';

const _unsizedImageTable = ':::plain\n'
    '| ![](flag) | Plenty of descriptive text beside the image |\n'
    '| --- | --- |\n'
    ':::';

const _tinyImageTable = ':::plain\n'
    '| ![](flag#20) | Text beside a very small image |\n'
    '| --- | --- |\n'
    ':::';

void main() {
  group('PrismMarkdownText image-layout table', () {
    testWidgets('applies a visual gutter around inline bio images', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap('before | ![](flag#120) after', bytes: _kOnePxPng),
      );
      await tester.pumpAndSettle();

      final imageBox = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 120 && w.height == 60,
      );
      expect(imageBox, findsOneWidget);

      expect(
        find.ancestor(
          of: imageBox,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Padding &&
                w.padding ==
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('lays out a loaded image-beside-text table without throwing',
        (tester) async {
      await tester.pumpWidget(_wrap(_sizedImageTable, bytes: _kOnePxPng));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PrismMarkdownTable), findsOneWidget);

      // The image hugs its authored 120×60 box (IntrinsicColumnWidth) — it was
      // not stretched to a 50/50 share of the row.
      final imageBox = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 120 && w.height == 60,
      );
      expect(imageBox, findsOneWidget);

      // The whole table fits within the bounded width.
      expect(
        tester.getSize(find.byType(PrismMarkdownTable)).width,
        lessThanOrEqualTo(360.0),
      );
    });

    testWidgets('lays out an UNSIZED loaded image table without throwing',
        (tester) async {
      // The original crash: an unsized image in an IntrinsicColumnWidth column
      // reported an infinite intrinsic width → the `width.isFinite` assertion.
      await tester.pumpWidget(_wrap(_unsizedImageTable, bytes: _kOnePxPng));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PrismMarkdownTable), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.getSize(find.byType(PrismMarkdownTable)).width,
        lessThanOrEqualTo(360.0),
      );
    });

    testWidgets('lays out an expired image table without throwing',
        (tester) async {
      await tester.pumpWidget(_wrap(_unsizedImageTable, bytes: null));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PrismMarkdownTable), findsOneWidget);
      // Expired → placeholder caption, no decoded image.
      expect(find.text('Image expired'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a tiny expired image cell does not overflow', (tester) async {
      // #20 → a 20×10 cell; the expired placeholder (icon + caption) is far
      // taller than 10px and used to overflow ("RenderFlex overflowed by …").
      await tester.pumpWidget(_wrap(_tinyImageTable, bytes: null));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PrismMarkdownTable), findsOneWidget);
    });
  });
}
