import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/widgets/image_library_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'waits for a cold image library stream before deciding it is empty',
    (tester) async {
      final libraryController = StreamController<List<MediaAttachment>>();
      addTearDown(libraryController.close);

      String? selectedTag;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageLibraryProvider.overrideWith(
              (ref) => libraryController.stream,
            ),
            mediaFileProvider.overrideWith((ref, params) async => _kOnePxPng),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    selectedTag = await showImageLibraryPicker(context, ref);
                  },
                  child: const Text('Pick image'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.widget<TextButton>(find.byType(TextButton)).onPressed!();
      await tester.pump();

      expect(find.text('No images in library yet'), findsNothing);
      expect(find.text('Image library'), findsNothing);

      libraryController.add([_libraryAttachment()]);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Image library'), findsOneWidget);
      expect(find.text('note-art'), findsOneWidget);

      await tester.tap(find.text('note-art'));
      await tester.pumpAndSettle();

      expect(selectedTag, 'note-art');
    },
  );
}

final Uint8List _kOnePxPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

MediaAttachment _libraryAttachment() => MediaAttachment(
  id: 'att-note-art',
  messageId: '',
  tag: 'note-art',
  mediaId: 'media-note-art',
  mediaType: 'image',
  encryptionKeyB64: base64Encode(List<int>.filled(32, 0)),
  contentHash: 'chash',
  plaintextHash: 'phash',
  mimeType: 'image/png',
  sizeBytes: 1,
  width: 1,
  height: 1,
  durationMs: 0,
  blurhash: '',
  waveformB64: '',
  thumbnailMediaId: '',
  sourceUrl: '',
  previewUrl: '',
);
