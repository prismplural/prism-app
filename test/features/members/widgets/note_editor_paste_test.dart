import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
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

  testWidgets('pasting an image into the note body opens the add-image dialog', (
    tester,
  ) async {
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
