import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
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

class _GatedBioImageProcessor implements BioImageProcessor {
  final commitGate = Completer<void>();
  int commitCount = 0;

  @override
  final List<StagedBioImage> staged = [];

  @override
  Future<List<String>> commitStaged() async {
    commitCount += 1;
    await commitGate.future;
    staged.clear();
    return const [];
  }

  @override
  void discardStaged() {}

  @override
  Uint8List? getStagedBytes(String mediaId) => null;

  @override
  Uint8List? getStagedByTag(String tag) => null;

  @override
  Future<String> stageDeviceImage(
    Uint8List bytes,
    String tag, {
    String? altText,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> stageUrlImage(
    String url,
    String tag, {
    String? altText,
  }) async {
    throw UnimplementedError();
  }
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

  testWidgets('rapid save taps commit staged markdown images once', (
    tester,
  ) async {
    final processor = _GatedBioImageProcessor();
    String? saved;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appClipboardReaderProvider.overrideWithValue(
            const _FakeClipboardReader(),
          ),
          bioImageProcessorProvider.overrideWith((ref, sessionId) => processor),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    saved = await showFullScreenMarkdownEditor(
                      context: context,
                      title: 'Notes',
                      initialText: '',
                      hintText: 'Write something',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'saved once');
    await tester.pump();

    final saveButton = find.byTooltip('Save');
    await tester.tap(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(processor.commitCount, 1);

    processor.commitGate.complete();
    await tester.pumpAndSettle();

    expect(saved, 'saved once');
    expect(find.text('Open'), findsOneWidget);
  });

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
