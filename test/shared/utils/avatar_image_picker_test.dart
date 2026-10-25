import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('routes alpha PNG before crop on $platform', (tester) async {
        final source = img.Image(width: 24, height: 24, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(40, 100, 180, 128));
        final input = Uint8List.fromList(img.encodePng(source));
        var converterCalls = 0;
        Uint8List? cropInput;
        await tester.runAsync(
          () => _pick(
            tester,
            pickImage: (_) async =>
                _FakePickedImage(path: 'fixture.png', bytes: input),
            normalizeBytes: (bytes, {platform}) async {
              converterCalls++;
              return Uint8List.fromList(img.encodeJpg(img.decodeImage(bytes)!));
            },
            cropImage:
                (
                  bytes,
                  context, {
                  required title,
                  required doneButtonTitle,
                  required cancelButtonTitle,
                }) async {
                  cropInput = bytes;
                  return null;
                },
            platform: platform,
          ),
        );
        expect(converterCalls, platform == TargetPlatform.iOS ? 0 : 1);
        expect(cropInput, isNotNull);
        expect(
          img.decodeImage(cropInput!)!.getPixel(12, 12).a,
          platform == TargetPlatform.iOS ? 128 : 255,
        );
      });
    }

    testWidgets('iOS JPEG keeps the existing converter path', (tester) async {
      final source = img.Image(width: 24, height: 24);
      final input = Uint8List.fromList(img.encodeJpg(source));
      final converted = Uint8List.fromList(img.encodeJpg(source, quality: 80));
      var converterCalls = 0;
      Uint8List? cropInput;
      await _pick(
        tester,
        pickImage: (_) async =>
            _FakePickedImage(path: 'fixture.jpg', bytes: input),
        normalizeBytes: (bytes, {platform}) async {
          converterCalls++;
          expect(bytes, input);
          expect(platform, TargetPlatform.iOS);
          return converted;
        },
        cropImage:
            (
              bytes,
              context, {
              required title,
              required doneButtonTitle,
              required cancelButtonTitle,
            }) async {
              cropInput = bytes;
              return null;
            },
        platform: TargetPlatform.iOS,
      );
      expect(converterCalls, 1);
      expect(cropInput, converted);
    });

    testWidgets('iOS PNG preparation preserves alpha and 4096 crop detail', (
      tester,
    ) async {
      final source = img.Image(width: 4200, height: 8, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(40, 100, 180, 128));
      final input = Uint8List.fromList(img.encodePng(source));
      var converterCalls = 0;
      Uint8List? cropInput;
      await tester.runAsync(
        () => _pick(
          tester,
          pickImage: (_) async =>
              _FakePickedImage(path: 'fixture.png', bytes: input),
          normalizeBytes: (bytes, {platform}) async {
            converterCalls++;
            return bytes;
          },
          cropImage:
              (
                bytes,
                context, {
                required title,
                required doneButtonTitle,
                required cancelButtonTitle,
              }) async {
                cropInput = bytes;
                return null;
              },
          platform: TargetPlatform.iOS,
        ),
      );
      expect(converterCalls, 0);
      final decoded = img.decodeImage(cropInput!)!;
      expect(decoded.width, 4096);
      expect(decoded.height, inInclusiveRange(1, 4096));
      expect(decoded.getPixel(2000, 2).a, 128);
    });

    testWidgets('oversized declared iOS PNG never opens cropper', (
      tester,
    ) async {
      final source = img.Image(width: 2, height: 2, numChannels: 4);
      final input = Uint8List.fromList(img.encodePng(source));
      // IHDR declares 8000x8000 without allocating a corresponding bitmap.
      final header = ByteData.sublistView(input);
      header.setUint32(16, 8000);
      header.setUint32(20, 8000);
      var crc = 0xffffffff;
      for (var i = 12; i < 29; i++) {
        crc ^= input[i];
        for (var bit = 0; bit < 8; bit++) {
          crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
        }
      }
      header.setUint32(29, crc ^ 0xffffffff);
      var cropCalls = 0;
      var converterCalls = 0;
      final result = await tester.runAsync(
        () => _pick(
          tester,
          pickImage: (_) async =>
              _FakePickedImage(path: 'fixture.png', bytes: input),
          normalizeBytes: (bytes, {platform}) async {
            converterCalls++;
            return bytes;
          },
          cropImage:
              (
                bytes,
                context, {
                required title,
                required doneButtonTitle,
                required cancelButtonTitle,
              }) async {
                cropCalls++;
                return bytes;
              },
          platform: TargetPlatform.iOS,
        ),
      );
      expect(result, isNull);
      expect(cropCalls, 0);
      expect(converterCalls, 0);
      PrismToast.dismiss();
    });

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

    testWidgets('uses cropper on desktop platforms', (tester) async {
      final pickedBytes = Uint8List.fromList([4, 5, 6]);
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
        platform: TargetPlatform.windows,
      );

      expect(result, croppedBytes);
      expect(cropCalls, hasLength(1));
      expect(cropCalls.single.sourceBytes, pickedBytes);
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

      final croppedBytes = Uint8List.fromList([10, 11, 12]);
      final cropCalls = <_CropCall>[];

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
        fileDialogService: fileDialogService,
        platform: TargetPlatform.macOS,
      );

      expect(result, croppedBytes);
      expect(cropCalls, hasLength(1));
      expect(cropCalls.single.sourceBytes, pickedBytes);
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
