import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/features/members/widgets/image_size_field.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Returns a configurable image (or none) for both clipboard read paths.
class _FakeClipboardReader implements AppClipboardReader {
  const _FakeClipboardReader({this.image});

  final ClipboardImageData? image;

  @override
  Future<ClipboardImageData?> readImage({
    ClipboardPasteboard pasteboard = ClipboardPasteboard.clipboard,
  }) async => image;

  @override
  Future<ClipboardImageData?> readImageUri(String uri) async => null;
}

void main() {
  Widget buildSubject(AppClipboardReader reader) {
    return ProviderScope(
      overrides: [appClipboardReaderProvider.overrideWithValue(reader)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: FullScreenMarkdownEditorSheet(
            title: 'Notes',
            initialText: '',
            hintText: 'Write something',
            scrollController: ScrollController(),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'pasting an image into the markdown editor opens the add-image dialog',
    (tester) async {
      await tester.pumpWidget(
        buildSubject(
          _FakeClipboardReader(
            image: ClipboardImageData(
              bytes: _kTransparentPngBytes,
              mimeType: 'image/png',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No add-image dialog before pasting.
      expect(find.byType(ImageSizeField), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      Actions.invoke(
        tester.element(find.byType(TextField)),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();

      // The pasted image is routed straight into the shared add-image dialog,
      // which carries the size field — the same flow as the image button.
      expect(find.byType(ImageSizeField), findsOneWidget);
    },
  );

  testWidgets(
    'pasting with no clipboard image leaves the add-image dialog closed',
    (tester) async {
      await tester.pumpWidget(buildSubject(const _FakeClipboardReader()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      Actions.invoke(
        tester.element(find.byType(TextField)),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ImageSizeField), findsNothing);
    },
  );
}

final Uint8List _kTransparentPngBytes = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
