import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/core/sharing/field_template_png.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/settings/widgets/branded_template_card.dart';
import 'package:prism_plurality/features/settings/widgets/import_template_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/services/template_image_code_reader.dart';

void main() {
  final now = DateTime.now();

  CustomField makeField({
    required String id,
    required String name,
    required String fieldTypeId,
    required CustomFieldType fieldType,
    String? parentFieldId,
    CustomFieldTypeConfig? typeConfig,
  }) => CustomField(
    id: id,
    name: name,
    fieldType: fieldType,
    createdAt: now,
    fieldTypeId: fieldTypeId,
    parentFieldId: parentFieldId,
    typeConfig: typeConfig,
  );

  String validCode() {
    final group = makeField(
      id: 'g',
      name: 'Stats',
      fieldTypeId: 'group',
      fieldType: CustomFieldType.text,
      typeConfig: const GroupConfig(),
    );
    final scale = makeField(
      id: 's',
      name: 'Power',
      fieldTypeId: 'scale',
      fieldType: CustomFieldType.text,
      parentFieldId: 'g',
      typeConfig: const ScaleConfig(emoji: '⭐', steps: 5),
    );
    return const FieldTemplateCodec().encode(
      FieldTemplate.fromDomain([group, scale]),
    );
  }

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    ),
  );

  testWidgets('offers paste, choose-image, and scan entry points', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('Scan QR code'), findsOneWidget);
  });

  testWidgets('a valid pasted template opens the preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, validCode());
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Import fields'), findsOneWidget);
  });

  testWidgets('garbage paste shows the "doesn\'t look right" error', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'not-a-template');
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(find.textContaining("doesn't look right"), findsOneWidget);
  });

  testWidgets('a newer PF version shows the update message', (tester) async {
    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'PF2:abcdef');
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(find.textContaining('newer version of Prism'), findsOneWidget);
  });

  testWidgets('a malformed-config code shows the error without crashing', (
    tester,
  ) async {
    // A choice entry whose options aren't a List passes structural validation
    // but throws when inflated — must surface as a friendly error, not a crash.
    final bad = FieldTemplate(
      version: 1,
      entries: const [
        FieldTemplateEntry(
          name: 'Mood',
          fieldTypeId: 'choice',
          compactConfig: {'runtimeType': 'choice', 'options': 'notalist'},
        ),
      ],
    );
    final code = const FieldTemplateCodec().encode(bad);

    await tester.pumpWidget(
      host(ImportTemplateSheetContent(scrollController: ScrollController())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, code);
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(find.textContaining("doesn't look right"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('template image import', () {
    /// A picker that records the requested extensions and returns [bytes].
    _RecordingFileDialogService picker(Uint8List bytes) =>
        _RecordingFileDialogService(bytes: bytes);

    /// Pins the reader to a desktop platform and runs the real pure-Dart QR
    /// decoder on the current isolate. Production defaults to the isolate-
    /// scheduled [decodeTemplateVisibleQr], but the widget tester's fake-async
    /// clock never resolves an isolate result.
    TemplateImageCodeReader desktopReader() => TemplateImageCodeReader(
      platform: TargetPlatform.linux,
      decodeVisibleQr: decodeTemplateVisibleQrOnCurrentIsolate,
    );

    Future<void> pumpSheet(
      WidgetTester tester,
      _RecordingFileDialogService dialog,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          // Distinct key: this scope replaces the 0-override scope used to
          // render the card fixture above, and riverpod asserts when a live
          // ProviderScope's override list changes length in place.
          key: const ValueKey('import-sheet-scope'),
          overrides: [
            prismFileDialogServiceProvider.overrideWithValue(dialog),
            templateImageCodeReaderProvider.overrideWithValue(desktopReader()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: ImportTemplateSheetContent(
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('chooser accepts png, jpg, and jpeg', (tester) async {
      // A shared card is recompressed to JPEG by chat apps, which drops the PNG
      // tEXt chunk — the picker has to let those files through at all.
      final dialog = picker(Uint8List(0));
      await pumpSheet(tester, dialog);

      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();

      expect(dialog.requestedExtensions, kTemplateImageExtensions);
      expect(dialog.requestedExtensions, containsAll(['png', 'jpg', 'jpeg']));
    });

    testWidgets('imports a JPEG-recompressed card through its visible QR', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Render the real share card, then re-encode it as an opaque JPEG: the
      // metadata is gone, leaving only the visible QR to recover the template.
      final key = GlobalKey();
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: BrandedTemplateCard(
              boundaryKey: key,
              name: 'Stats',
              code: validCode(),
              fieldCount: 1,
              typeLabels: const ['Rating'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Uint8List? png;
      await tester.runAsync(() async {
        png = await captureBrandedTemplateCardPng(
          key,
          code: validCode(),
          pixelRatio: 2,
        );
      });
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.decodePng(png!)!, quality: 85),
      );
      expect(readTemplateFromPng(jpeg), isNull);

      final dialog = picker(jpeg);
      await pumpSheet(tester, dialog);
      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();

      // The recovered code opens the preview sheet, which names the template
      // (headline + summary row).
      expect(find.text('Review template'), findsOneWidget);
      expect(find.text('Stats'), findsWidgets);
      expect(
        find.textContaining("Couldn't find a template in that image"),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-image pick reports a friendly error, not a crash', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final dialog = picker(
        Uint8List.fromList(List.generate(256, (i) => i % 251)),
      );
      await pumpSheet(tester, dialog);

      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining("Couldn't find a template in that image"),
        findsOneWidget,
      );
      expect(find.text('Review template'), findsNothing);
    });

    testWidgets('an oversized handle is rejected without reading its bytes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // The handle reports a size over the cap while carrying tiny bytes, so a
      // reader that ignored `size` would succeed and open the preview. The
      // pre-read rejection is what keeps a huge file off the heap entirely.
      final dialog = _RecordingFileDialogService(
        bytes: Uint8List.fromList(List.generate(64, (i) => i)),
        reportedSize: kMaxTemplateImageBytes + 1,
      );
      await pumpSheet(tester, dialog);

      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();

      expect(dialog.readAsBytesCalls, 0, reason: 'never read the file');
      expect(
        find.textContaining("Couldn't find a template in that image"),
        findsOneWidget,
      );
      expect(find.text('Review template'), findsNothing);
    });

    testWidgets('a handle with a misreported small size still hits the cap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // `size` lies low, so the widget-level gate cannot catch it: the reader's
      // own byte cap must. The bytes are an over-cap buffer whose head looks
      // like a JPEG.
      final oversized = Uint8List(kMaxTemplateImageBytes + 1)
        ..setRange(0, 3, [0xFF, 0xD8, 0xFF]);
      final dialog = _RecordingFileDialogService(
        bytes: oversized,
        reportedSize: 1024,
      );
      await pumpSheet(tester, dialog);

      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();

      expect(dialog.readAsBytesCalls, 1, reason: 'size looked harmless');
      expect(
        find.textContaining("Couldn't find a template in that image"),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Returns canned bytes for any pick and records what was requested.
class _RecordingFileDialogService implements PrismFileDialogService {
  _RecordingFileDialogService({required this.bytes, this.reportedSize});

  final Uint8List bytes;

  /// Size the picker claims for the handle. Defaults to the real byte length;
  /// set it higher to simulate a handle that reports an oversized file.
  final int? reportedSize;
  List<String>? requestedExtensions;
  int readAsBytesCalls = 0;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    requestedExtensions = allowedExtensions;
    return PickedFileHandle(
      name: 'template.jpg',
      size: reportedSize ?? bytes.length,
      readAsBytes: () async {
        readAsBytesCalls++;
        return bytes;
      },
      openRead: () => Stream<List<int>>.value(bytes),
    );
  }

  @override
  Future<PickedFileHandle?> pickImageFile({String? dialogTitle}) async => null;

  @override
  Future<SaveFileOutcome> saveBytes({
    required Uint8List bytes,
    required String suggestedName,
    required List<String> allowedExtensions,
    String? dialogTitle,
    String? mimeType,
  }) async => const SaveFileOutcome(status: SaveFileStatus.saved);

  @override
  Future<SaveFileOutcome> saveExistingFile(
    ExistingFileSaveRequest request,
  ) async => const SaveFileOutcome(status: SaveFileStatus.saved);
}
