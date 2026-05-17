import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _PickCall {
  _PickCall(this.source);
  final ImageSource source;
}

class _CropCall {
  _CropCall({
    required this.sourceBytes,
    required this.title,
    required this.doneButtonTitle,
    required this.cancelButtonTitle,
  });

  final Uint8List sourceBytes;
  final String title;
  final String doneButtonTitle;
  final String cancelButtonTitle;
}

class _FakePickedImage implements AvatarPickedImage {
  _FakePickedImage({required this.path, required this.bytes});

  @override
  final String path;

  final Uint8List bytes;
  int readCount = 0;

  @override
  Future<Uint8List> readAsBytes() async {
    readCount += 1;
    return bytes;
  }
}

void main() {
  group('AvatarImagePicker', () {
    testWidgets('returns null when image picking is cancelled', (tester) async {
      final pickCalls = <_PickCall>[];
      final cropCalls = <_CropCall>[];

      final result = await _pick(
        tester,
        pickImage: (source) async {
          pickCalls.add(_PickCall(source));
          return null;
        },
        cropImage:
            (
              sourceBytes,
              context, {
              required title,
              required doneButtonTitle,
              required cancelButtonTitle,
            }) async {
              cropCalls.add(
                _CropCall(
                  sourceBytes: sourceBytes,
                  title: title,
                  doneButtonTitle: doneButtonTitle,
                  cancelButtonTitle: cancelButtonTitle,
                ),
              );
              return null;
            },
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
      expect(pickCalls, hasLength(1));
      expect(pickCalls.single.source, ImageSource.gallery);
      expect(cropCalls, isEmpty);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('uses cropper on $platform', (tester) async {
        final pickedBytes = Uint8List.fromList([1, 2, 3]);
        final croppedBytes = Uint8List.fromList([9, 8, 7]);
        final pickedImage = _FakePickedImage(
          path: '/tmp/avatar-source.png',
          bytes: pickedBytes,
        );
        final cropCalls = <_CropCall>[];

        final result = await _pick(
          tester,
          pickImage: (_) async => pickedImage,
          cropImage:
              (
                sourceBytes,
                context, {
                required title,
                required doneButtonTitle,
                required cancelButtonTitle,
              }) async {
                cropCalls.add(
                  _CropCall(
                    sourceBytes: sourceBytes,
                    title: title,
                    doneButtonTitle: doneButtonTitle,
                    cancelButtonTitle: cancelButtonTitle,
                  ),
                );
                return croppedBytes;
              },
          platform: platform,
        );

        expect(result, croppedBytes);
        expect(cropCalls, hasLength(1));
        expect(cropCalls.single.sourceBytes, pickedBytes);
        expect(cropCalls.single.title, 'Crop avatar');
        expect(cropCalls.single.doneButtonTitle, 'Done');
        expect(cropCalls.single.cancelButtonTitle, 'Cancel');
        expect(pickedImage.readCount, 1);
      });
    }

    testWidgets('passes localized cropper strings to native cropper', (
      tester,
    ) async {
      final cropCalls = <_CropCall>[];
      await _pick(
        tester,
        pickImage: (_) async => _FakePickedImage(
          path: '/tmp/avatar-source.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        cropImage:
            (
              sourceBytes,
              context, {
              required title,
              required doneButtonTitle,
              required cancelButtonTitle,
            }) async {
              cropCalls.add(
                _CropCall(
                  sourceBytes: sourceBytes,
                  title: title,
                  doneButtonTitle: doneButtonTitle,
                  cancelButtonTitle: cancelButtonTitle,
                ),
              );
              return Uint8List.fromList([9, 8, 7]);
            },
        platform: TargetPlatform.iOS,
        locale: const Locale('es'),
      );

      expect(cropCalls.single.title, 'Recortar avatar');
      expect(cropCalls.single.doneButtonTitle, 'Listo');
      expect(cropCalls.single.cancelButtonTitle, 'Cancelar');
    });

    testWidgets('returns null when cropper is cancelled', (tester) async {
      final pickedImage = _FakePickedImage(
        path: '/tmp/avatar-source.png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      var cropCalls = 0;

      final result = await _pick(
        tester,
        pickImage: (_) async => pickedImage,
        cropImage:
            (
              sourceBytes,
              context, {
              required title,
              required doneButtonTitle,
              required cancelButtonTitle,
            }) async {
              cropCalls += 1;
              return null;
            },
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
      expect(cropCalls, 1);
      expect(pickedImage.readCount, 1);
    });

    testWidgets('falls back to picked bytes on unsupported platforms', (
      tester,
    ) async {
      final pickedBytes = Uint8List.fromList([4, 5, 6]);
      final pickedImage = _FakePickedImage(
        path: '/tmp/avatar-source.png',
        bytes: pickedBytes,
      );
      var cropCalls = 0;

      final result = await _pick(
        tester,
        pickImage: (_) async => pickedImage,
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
        platform: TargetPlatform.macOS,
      );

      expect(result, pickedBytes);
      expect(cropCalls, 0);
      expect(pickedImage.readCount, 1);
    });

    testWidgets('uses file dialog service for desktop gallery picks', (
      tester,
    ) async {
      final pickedBytes = Uint8List.fromList([7, 8, 9]);
      final fileDialogService = _FakeFileDialogService(
        pickedImage: PickedFileHandle(
          name: 'avatar.png',
          path: '/tmp/avatar.png',
          size: pickedBytes.length,
          readAsBytes: () async => pickedBytes,
          openRead: () => Stream<List<int>>.value(pickedBytes),
        ),
      );

      final result = await _pick(
        tester,
        pickImage: null,
        cropImage:
            (
              sourceBytes,
              context, {
              required title,
              required doneButtonTitle,
              required cancelButtonTitle,
            }) async {
              fail('desktop gallery picks should skip the cropper');
            },
        fileDialogService: fileDialogService,
        platform: TargetPlatform.macOS,
      );

      expect(result, pickedBytes);
      expect(fileDialogService.pickImageFileCalls, 1);
    });

    testWidgets(
      'returns null and skips cropper when picker yields empty bytes',
      (tester) async {
        final pickedImage = _FakePickedImage(
          path: '/tmp/avatar-source.jpg',
          bytes: Uint8List(0),
        );
        var cropCalls = 0;

        final result = await _pick(
          tester,
          pickImage: (_) async => pickedImage,
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
          platform: TargetPlatform.iOS,
        );

        expect(result, isNull);
        expect(cropCalls, 0);
        expect(pickedImage.readCount, 1);
        PrismToast.dismiss();
      },
    );

    testWidgets('returns null and skips cropper when normalizer yields null', (
      tester,
    ) async {
      final pickedImage = _FakePickedImage(
        path: '/tmp/avatar-source.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      var cropCalls = 0;

      final result = await _pick(
        tester,
        pickImage: (_) async => pickedImage,
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
        normalizeBytes: (bytes, {platform}) async => null,
        platform: TargetPlatform.iOS,
      );

      expect(result, isNull);
      expect(cropCalls, 0);
      PrismToast.dismiss();
    });

    // Regression: GIF avatars used to be rasterized into a single frame by
    // the cropper, killing the animation. The picker now detects GIF bytes
    // up-front, skips the cropper, and runs them through the normalizer
    // (which passes GIFs through verbatim).
    testWidgets('skips cropper and returns GIF bytes verbatim for GIF input', (
      tester,
    ) async {
      // Minimal valid GIF89a header — the picker only checks magic bytes.
      final gifBytes = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // "GIF89a"
        0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00,
        0x21, 0xF9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
      ]);
      final pickedImage = _FakePickedImage(
        path: '/tmp/avatar-source.gif',
        bytes: gifBytes,
      );
      var cropCalls = 0;
      var normalizeCalls = 0;

      final result = await _pick(
        tester,
        pickImage: (_) async => pickedImage,
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
        normalizeBytes: (bytes, {platform}) async {
          normalizeCalls += 1;
          return bytes;
        },
        platform: TargetPlatform.iOS,
      );

      expect(result, isNotNull);
      expect(
        result,
        gifBytes,
        reason: 'GIF should pass through normalizer verbatim',
      );
      expect(cropCalls, 0, reason: 'cropper would flatten animation');
      expect(
        normalizeCalls,
        0,
        reason: 'platform normalizer should be bypassed for GIFs',
      );
    });

    testWidgets('returns null if context unmounts after image picking', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final pickCompleter = Completer<AvatarPickedImage?>();
      final pickedImage = _FakePickedImage(
        path: '/tmp/avatar-source.png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      var cropCalls = 0;

      final resultFuture = AvatarImagePicker.pickCroppedAvatarBytes(
        context,
        pickImage: (_) => pickCompleter.future,
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
        platform: TargetPlatform.android,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      pickCompleter.complete(pickedImage);

      expect(await resultFuture, isNull);
      expect(cropCalls, 0);
      expect(pickedImage.readCount, 0);
    });
  });
}

Future<Uint8List?> _pick(
  WidgetTester tester, {
  required AvatarPickImageFn? pickImage,
  required AvatarCropImageFn cropImage,
  required TargetPlatform platform,
  AvatarNormalizeBytesFn? normalizeBytes,
  PrismFileDialogService? fileDialogService,
  Locale locale = const Locale('en'),
}) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (builderContext) {
          context = builderContext;
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  return AvatarImagePicker.pickCroppedAvatarBytes(
    context,
    pickImage: pickImage,
    cropImage: cropImage,
    normalizeBytes: normalizeBytes ?? _passthroughNormalize,
    fileDialogService: fileDialogService,
    platform: platform,
  );
}

Future<Uint8List?> _passthroughNormalize(
  Uint8List sourceBytes, {
  TargetPlatform? platform,
}) async => sourceBytes;

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
