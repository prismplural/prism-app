import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';

class _PickCall {
  _PickCall(this.source);
  final ImageSource source;
}

class _CropCall {
  _CropCall({
    required this.sourcePath,
    required this.title,
    required this.doneButtonTitle,
    required this.cancelButtonTitle,
  });

  final String sourcePath;
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

class _FakeCroppedImage implements AvatarCroppedImage {
  _FakeCroppedImage(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;
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
        cropImage: (
          sourcePath,
          context, {
          required title,
          required doneButtonTitle,
          required cancelButtonTitle,
        }) async {
          cropCalls.add(
            _CropCall(
              sourcePath: sourcePath,
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
      testWidgets('uses native cropper on $platform', (tester) async {
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
          cropImage: (
            sourcePath,
            context, {
            required title,
            required doneButtonTitle,
            required cancelButtonTitle,
          }) async {
            cropCalls.add(
              _CropCall(
                sourcePath: sourcePath,
                title: title,
                doneButtonTitle: doneButtonTitle,
                cancelButtonTitle: cancelButtonTitle,
              ),
            );
            return _FakeCroppedImage(croppedBytes);
          },
          platform: platform,
        );

        expect(result, croppedBytes);
        expect(cropCalls, hasLength(1));
        expect(cropCalls.single.sourcePath, '/tmp/avatar-source.png');
        expect(cropCalls.single.title, 'Crop avatar');
        expect(cropCalls.single.doneButtonTitle, 'Done');
        expect(cropCalls.single.cancelButtonTitle, 'Cancel');
        expect(pickedImage.readCount, 0);
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
        cropImage: (
          sourcePath,
          context, {
          required title,
          required doneButtonTitle,
          required cancelButtonTitle,
        }) async {
          cropCalls.add(
            _CropCall(
              sourcePath: sourcePath,
              title: title,
              doneButtonTitle: doneButtonTitle,
              cancelButtonTitle: cancelButtonTitle,
            ),
          );
          return _FakeCroppedImage(Uint8List.fromList([9, 8, 7]));
        },
        platform: TargetPlatform.iOS,
        locale: const Locale('es'),
      );

      expect(cropCalls.single.title, 'Recortar avatar');
      expect(cropCalls.single.doneButtonTitle, 'Listo');
      expect(cropCalls.single.cancelButtonTitle, 'Cancelar');
    });

    testWidgets('returns null when native cropper is cancelled', (
      tester,
    ) async {
      final pickedImage = _FakePickedImage(
        path: '/tmp/avatar-source.png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      var cropCalls = 0;

      final result = await _pick(
        tester,
        pickImage: (_) async => pickedImage,
        cropImage: (
          sourcePath,
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
      expect(pickedImage.readCount, 0);
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
        cropImage: (
          sourcePath,
          context, {
          required title,
          required doneButtonTitle,
          required cancelButtonTitle,
        }) async {
          cropCalls += 1;
          return _FakeCroppedImage(Uint8List.fromList([9, 8, 7]));
        },
        platform: TargetPlatform.macOS,
      );

      expect(result, pickedBytes);
      expect(cropCalls, 0);
      expect(pickedImage.readCount, 1);
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
        cropImage: (
          sourcePath,
          context, {
          required title,
          required doneButtonTitle,
          required cancelButtonTitle,
        }) async {
          cropCalls += 1;
          return _FakeCroppedImage(Uint8List.fromList([9, 8, 7]));
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
  required AvatarPickImageFn pickImage,
  required AvatarCropImageFn cropImage,
  required TargetPlatform platform,
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
    platform: platform,
  );
}
