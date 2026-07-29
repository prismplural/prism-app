import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/notes_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
import 'package:prism_plurality/features/members/widgets/image_size_field.dart';
import 'package:prism_plurality/features/members/widgets/note_editor.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

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

class _FakeBioImageProcessor implements BioImageProcessor {
  _FakeBioImageProcessor({this.failTags = const {}});

  final Set<String> failTags;
  final stagedPayloads = <Uint8List>[];
  var commitCount = 0;

  @override
  final List<StagedBioImage> staged = [];

  @override
  Future<String> stageDeviceImage(
    Uint8List bytes,
    String tag, {
    String? altText,
  }) async {
    if (failTags.contains(tag)) {
      throw StateError('failed $tag');
    }
    stagedPayloads.add(bytes);
    staged.add(_fakeStagedImage(tag));
    return tag;
  }

  @override
  Future<String> stageUrlImage(
    String url,
    String tag, {
    String? altText,
  }) async {
    final normalized = BioImageProcessor.normalizeTag(tag);
    if (failTags.contains(normalized)) {
      throw StateError('failed $normalized');
    }
    staged.add(_fakeStagedImage(normalized));
    return normalized;
  }

  @override
  Future<List<String>> commitStaged() async {
    commitCount += 1;
    staged.clear();
    return const [];
  }

  @override
  void discardStaged() {}

  @override
  Uint8List? getStagedBytes(String mediaId) => null;

  @override
  Uint8List? getStagedByTag(String tag) => null;
}

StagedBioImage _fakeStagedImage(String tag) {
  const bytes = <int>[1, 2, 3];
  return StagedBioImage(
    mediaId: 'media-$tag',
    tag: tag,
    prepared: MediaAttachmentData(
      mediaId: 'media-$tag',
      thumbnailMediaId: '',
      encryptedImage: Uint8List.fromList(bytes),
      encryptedThumbnail: Uint8List(0),
      encryptionKey: Uint8List.fromList(bytes),
      contentHash: 'content-$tag',
      plaintextHash: 'plain-$tag',
      thumbnailContentHash: '',
      thumbnailPlaintextHash: '',
      width: 1,
      height: 1,
      sizeBytes: bytes.length,
      blurhash: '',
      mimeType: 'image/png',
    ),
    decryptedBytes: Uint8List.fromList(bytes),
  );
}

class _FakeNotesRepository implements NotesRepository {
  final created = <Note>[];
  final updated = <Note>[];

  @override
  Future<void> createNote(Note note) async {
    created.add(note);
  }

  @override
  Future<void> deleteNote(String id) async {}

  @override
  Future<List<Note>> getAllNotes() async => List.of(created);

  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<void> updateNote(Note note) async {
    updated.add(note);
  }

  @override
  Stream<List<Note>> watchAllNotes() => Stream.value(created);

  @override
  Stream<Note?> watchNoteById(String id) => Stream.value(null);

  @override
  Stream<List<Note>> watchNotesForMember(String memberId) =>
      Stream.value(created.where((note) => note.memberId == memberId).toList());

  @override
  Stream<List<Note>> watchRecentNotesForMember(
    String memberId, {
    int limit = 5,
  }) => Stream.value(
    created.where((note) => note.memberId == memberId).take(limit).toList(),
  );
}

void main() {
  Widget buildSubject(AppClipboardReader reader) {
    return ProviderScope(
      overrides: [
        appClipboardReaderProvider.overrideWithValue(reader),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        currentFronterProvider.overrideWith(
          (ref) => Stream<Member?>.value(null),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(body: NoteEditor(scrollController: ScrollController())),
      ),
    );
  }

  Widget buildSaveSubject({
    required _FakeBioImageProcessor processor,
    required _FakeNotesRepository notes,
    ValueChanged<Note>? onSaved,
  }) {
    return ProviderScope(
      overrides: [
        notesRepositoryProvider.overrideWithValue(notes),
        bioImageProcessorProvider.overrideWith((ref, sessionId) => processor),
        imageLibraryProvider.overrideWith(
          (ref) => Stream<List<MediaAttachment>>.value(const []),
        ),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(const SystemSettings()),
        ),
        currentFronterProvider.overrideWith(
          (ref) => Stream<Member?>.value(null),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: NoteEditor(
            scrollController: ScrollController(),
            onSaved: onSaved,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'pasting an image into the note body opens the add-image dialog',
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

      expect(find.byType(ImageSizeField), findsNothing);

      // The body field is the last TextField (title is first). Invoking paste
      // through it exercises the GlobalKey → MarkdownImageButton wiring.
      final bodyField = find.byType(TextField).last;
      await tester.tap(bodyField);
      await tester.pump();
      Actions.invoke(
        tester.element(bodyField),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ImageSizeField), findsOneWidget);
    },
  );

  testWidgets('rewrites embedded data images before saving note body', (
    tester,
  ) async {
    final processor = _FakeBioImageProcessor();
    final notes = _FakeNotesRepository();
    Note? saved;

    await tester.pumpWidget(
      buildSaveSubject(
        processor: processor,
        notes: notes,
        onSaved: (note) => saved = note,
      ),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(TextField).last;
    await tester.enterText(
      bodyField,
      'Before ![Flag](data:image/png;base64,aGVsbG8=) after.',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();

    expect(utf8.decode(processor.stagedPayloads.single), 'hello');
    expect(processor.commitCount, 1);
    expect(
      notes.created.single.body,
      'Before ![Flag](embedded-image-1) after.',
    );
    expect(notes.created.single.body, isNot(contains('data:image')));
    expect(saved?.body, notes.created.single.body);
  });

  testWidgets('dedupes repeated embedded data images before saving note body', (
    tester,
  ) async {
    final processor = _FakeBioImageProcessor();
    final notes = _FakeNotesRepository();
    const embedded = '![Flag](data:image/png;base64,aGVsbG8=)';

    await tester.pumpWidget(
      buildSaveSubject(processor: processor, notes: notes),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(TextField).last;
    await tester.enterText(bodyField, '$embedded then $embedded');
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();

    expect(processor.stagedPayloads, hasLength(1));
    expect(utf8.decode(processor.stagedPayloads.single), 'hello');
    expect(processor.commitCount, 1);
    expect(
      notes.created.single.body,
      '![Flag](embedded-image-1) then ![Flag](embedded-image-1)',
    );
    expect(notes.created.single.body, isNot(contains('data:image')));
  });

  testWidgets('restores embedded data images when remote import is cancelled', (
    tester,
  ) async {
    final processor = _FakeBioImageProcessor()
      ..staged.add(_fakeStagedImage('already-staged'));
    final notes = _FakeNotesRepository();
    const embedded = '![Flag](data:image/png;base64,aGVsbG8=)';
    const body = '$embedded ![Remote](https://example.com/remote.png)';

    await tester.pumpWidget(
      buildSaveSubject(processor: processor, notes: notes),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(TextField).last;
    await tester.enterText(bodyField, body);
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    // The save button keeps its loading spinner animating while the prompt
    // awaits an answer, so pumpAndSettle would never settle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Save web images to Prism?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, body);
    expect(notes.created, isEmpty);
    expect(processor.commitCount, 0);
    expect(processor.stagedPayloads, hasLength(1));
    expect(processor.staged.map((image) => image.tag), ['already-staged']);
  });

  testWidgets('restores embedded data images when remote import fails', (
    tester,
  ) async {
    final processor = _FakeBioImageProcessor(failTags: const {'remote'})
      ..staged.add(_fakeStagedImage('already-staged'));
    final notes = _FakeNotesRepository();
    const embedded = '![Flag](data:image/png;base64,aGVsbG8=)';
    const body = '$embedded ![Remote](https://example.com/remote.png)';

    await tester.pumpWidget(
      buildSaveSubject(processor: processor, notes: notes),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(TextField).last;
    await tester.enterText(bodyField, body);
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    // The save button keeps its loading spinner animating while the prompt
    // awaits an answer, so pumpAndSettle would never settle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Save web images to Prism?'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, body);
    expect(notes.created, isEmpty);
    expect(processor.commitCount, 0);
    expect(processor.stagedPayloads, hasLength(1));
    expect(processor.staged.map((image) => image.tag), ['already-staged']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('keeps saving when one embedded image fails to stage', (
    tester,
  ) async {
    final processor = _FakeBioImageProcessor(
      failTags: const {'embedded-image-2'},
    )..staged.add(_fakeStagedImage('already-staged'));
    final notes = _FakeNotesRepository();

    await tester.pumpWidget(
      buildSaveSubject(processor: processor, notes: notes),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(TextField).last;
    await tester.enterText(
      bodyField,
      '![One](data:image/png;base64,aGVsbG8=) '
      '![Two](data:image/png;base64,AQ==)',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();

    expect(notes.created, hasLength(1));
    expect(
      notes.created.single.body,
      '![One](embedded-image-1) ![Two](data:image/png;base64,AQ==)',
    );
    expect(processor.commitCount, 1);
    expect(processor.stagedPayloads, hasLength(1));
    expect(processor.staged, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('keeps saving when an embedded data image is malformed', (
    tester,
  ) async {
    final processor = _FakeBioImageProcessor();
    final notes = _FakeNotesRepository();
    const body = 'Before ![Bad](data:image/png;base64,AA=A) after.';

    await tester.pumpWidget(
      buildSaveSubject(processor: processor, notes: notes),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(TextField).last;
    await tester.enterText(bodyField, body);
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();

    expect(notes.created, hasLength(1));
    expect(notes.created.single.body, body);
    expect(processor.commitCount, 1);
    expect(processor.stagedPayloads, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}

final Uint8List _kTransparentPngBytes = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
