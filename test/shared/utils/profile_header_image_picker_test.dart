import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _PickedImage implements ProfileHeaderPickedImage {
  const _PickedImage();

  @override
  String get path => '/tmp/header.jpg';

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3]);
}

void main() {
  testWidgets('passes profile header cropper title and button labels', (
    tester,
  ) async {
    final calls =
        <
          ({
            Uint8List sourceBytes,
            String title,
            String doneButtonTitle,
            String cancelButtonTitle,
          })
        >[];
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final bytes = await ProfileHeaderImagePicker.pickCroppedHeaderBytes(
      capturedContext,
      platform: TargetPlatform.android,
      pickImage: (source) async {
        expect(source, ImageSource.gallery);
        return const _PickedImage();
      },
      cropImage:
          (
            sourceBytes,
            context, {
            required title,
            required doneButtonTitle,
            required cancelButtonTitle,
          }) async {
            calls.add((
              sourceBytes: sourceBytes,
              title: title,
              doneButtonTitle: doneButtonTitle,
              cancelButtonTitle: cancelButtonTitle,
            ));
            return Uint8List.fromList([4, 5, 6]);
          },
      normalizeImage: (value) async => value,
    );

    expect(bytes, Uint8List.fromList([4, 5, 6]));
    expect(calls, hasLength(1));
    expect(calls.single.sourceBytes, Uint8List.fromList([1, 2, 3]));
    expect(calls.single.title, 'Crop profile banner');
    expect(calls.single.doneButtonTitle, 'Done');
    expect(calls.single.cancelButtonTitle, 'Cancel');
  });

  testWidgets(
    'normalizes real cropped bytes into decodable stored header bytes',
    (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final pickedSource = img.Image(width: 400, height: 400);
      img.fill(pickedSource, color: img.ColorRgb8(30, 40, 50));
      final croppedSource = img.Image(width: 2400, height: 800);
      img.fill(croppedSource, color: img.ColorRgb8(220, 180, 40));

      final bytes = await ProfileHeaderImagePicker.pickCroppedHeaderBytes(
        capturedContext,
        platform: TargetPlatform.android,
        pickImage: (_) async =>
            _BytesPickedImage(Uint8List.fromList(img.encodePng(pickedSource))),
        cropImage:
            (
              sourceBytes,
              context, {
              required title,
              required doneButtonTitle,
              required cancelButtonTitle,
            }) async => Uint8List.fromList(img.encodePng(croppedSource)),
        normalizeImage: (value) => normalizeProfileHeaderImage(
          value,
          encoder: const _PngProfileHeaderEncoder(),
        ),
      );

      expect(bytes, isNotNull);
      expect(
        bytes!.length,
        lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
      );

      final decoded = img.decodeImage(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, ProfileHeaderImageNormalizer.maxWidth);
      expect(decoded.height, ProfileHeaderImageNormalizer.maxHeight);
    },
  );

  testWidgets('returns null and skips cropper when picker yields empty bytes', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    var cropCalls = 0;
    final result = await ProfileHeaderImagePicker.pickCroppedHeaderBytes(
      capturedContext,
      platform: TargetPlatform.iOS,
      pickImage: (_) async => _BytesPickedImage(Uint8List(0)),
      cropImage:
          (
            sourceBytes,
            context, {
            required title,
            required doneButtonTitle,
            required cancelButtonTitle,
          }) async {
            cropCalls += 1;
            return Uint8List.fromList([9, 8, 7]);
          },
      normalizeImage: (value) async => value,
      normalizePickedBytes: (bytes, {platform}) async => bytes,
    );

    expect(result, isNull);
    expect(cropCalls, 0);
    PrismToast.dismiss();
  });

  testWidgets('returns null and skips cropper when normalizer yields null', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    var cropCalls = 0;
    final result = await ProfileHeaderImagePicker.pickCroppedHeaderBytes(
      capturedContext,
      platform: TargetPlatform.iOS,
      pickImage: (_) async => _BytesPickedImage(Uint8List.fromList([1, 2, 3])),
      cropImage:
          (
            sourceBytes,
            context, {
            required title,
            required doneButtonTitle,
            required cancelButtonTitle,
          }) async {
            cropCalls += 1;
            return Uint8List.fromList([9, 8, 7]);
          },
      normalizeImage: (value) async => value,
      normalizePickedBytes: (bytes, {platform}) async => null,
    );

    expect(result, isNull);
    expect(cropCalls, 0);
    PrismToast.dismiss();
  });

  testWidgets(
    'uses file dialog service and cropper for desktop gallery picks',
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final pickedSource = img.Image(width: 40, height: 40);
      img.fill(pickedSource, color: img.ColorRgb8(7, 8, 9));
      final pickedBytes = Uint8List.fromList(img.encodePng(pickedSource));
      final fileDialogService = _FakeFileDialogService(
        pickedImage: PickedFileHandle(
          name: 'header.png',
          path: '/tmp/header.png',
          size: pickedBytes.length,
          readAsBytes: () async => pickedBytes,
          openRead: () => Stream<List<int>>.value(pickedBytes),
        ),
      );

      final croppedBytes = Uint8List.fromList([10, 11, 12]);
      final cropCalls =
          <
            ({
              Uint8List sourceBytes,
              String title,
              String doneButtonTitle,
              String cancelButtonTitle,
            })
          >[];

      final bytes = await tester.runAsync(
        () => ProfileHeaderImagePicker.pickCroppedHeaderBytes(
          capturedContext,
          platform: TargetPlatform.windows,
          fileDialogService: fileDialogService,
          cropImage:
              (
                sourceBytes,
                context, {
                required title,
                required doneButtonTitle,
                required cancelButtonTitle,
              }) async {
                cropCalls.add((
                  sourceBytes: sourceBytes,
                  title: title,
                  doneButtonTitle: doneButtonTitle,
                  cancelButtonTitle: cancelButtonTitle,
                ));
                return croppedBytes;
              },
          normalizeImage: (value) async => value,
        ),
      );

      expect(bytes, croppedBytes);
      expect(cropCalls, hasLength(1));
      expect(identical(cropCalls.single.sourceBytes, pickedBytes), isFalse);
      final normalized = img.decodePng(cropCalls.single.sourceBytes);
      expect(normalized, isNotNull);
      expect(normalized!.width, 40);
      expect(normalized.height, 40);
      expect(fileDialogService.pickImageFileCalls, 1);
    },
  );
}

class _BytesPickedImage implements ProfileHeaderPickedImage {
  const _BytesPickedImage(this._bytes);

  final Uint8List _bytes;

  @override
  String get path => '/tmp/header-real.png';

  @override
  Future<Uint8List> readAsBytes() async => _bytes;
}

class _PngProfileHeaderEncoder implements ProfileHeaderWebpEncoder {
  const _PngProfileHeaderEncoder();

  @override
  Future<Uint8List> encode(img.Image image, {required int quality}) async {
    return Uint8List.fromList(img.encodePng(image));
  }
}

class _FakeFileDialogService implements PrismFileDialogService {
  _FakeFileDialogService({this.pickedImage});

  final PickedFileHandle? pickedImage;
  int pickImageFileCalls = 0;

  @override
  Future<PickedFileHandle?> pickImageFile({String? dialogTitle}) async {
    pickImageFileCalls += 1;
    return pickedImage;
  }

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async => pickedImage;

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
