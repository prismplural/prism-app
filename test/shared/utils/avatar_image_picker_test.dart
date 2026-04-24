import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';

void main() {
  group('AvatarImagePicker', () {
    testWidgets('returns null when image picking is cancelled', (tester) async {
      final imageSource = _FakeAvatarImageSource();
      final cropper = _FakeAvatarNativeCropper();

      final result = await _pick(
        tester,
        imageSource: imageSource,
        cropper: cropper,
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
      expect(imageSource.requests, hasLength(1));
      expect(imageSource.requests.single.source, ImageSource.gallery);
      expect(imageSource.requests.single.maxWidth, 512);
      expect(imageSource.requests.single.maxHeight, 512);
      expect(imageSource.requests.single.imageQuality, 85);
      expect(cropper.requests, isEmpty);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('uses native cropper on $platform', (tester) async {
        final pickedBytes = Uint8List.fromList([1, 2, 3]);
        final croppedBytes = Uint8List.fromList([9, 8, 7]);
        final imageSource = _FakeAvatarImageSource(
          pickedImage: _FakeAvatarPickedImage(
            path: '/tmp/avatar-source.png',
            bytes: pickedBytes,
          ),
        );
        final cropper = _FakeAvatarNativeCropper(
          croppedImage: _FakeAvatarCroppedImage(croppedBytes),
        );

        final result = await _pick(
          tester,
          imageSource: imageSource,
          cropper: cropper,
          platform: platform,
        );

        expect(result, croppedBytes);
        expect(cropper.requests, hasLength(1));

        final request = cropper.requests.single;
        expect(request.sourcePath, '/tmp/avatar-source.png');
        expect(request.maxWidth, 512);
        expect(request.maxHeight, 512);
        expect(request.compressQuality, 85);
        expect(request.title, 'Crop avatar');
        expect(request.doneButtonTitle, 'Done');
        expect(request.cancelButtonTitle, 'Cancel');
        expect(imageSource.pickedImage!.readCount, 0);
      });
    }

    testWidgets('passes localized cropper strings to native cropper', (
      tester,
    ) async {
      final imageSource = _FakeAvatarImageSource(
        pickedImage: _FakeAvatarPickedImage(
          path: '/tmp/avatar-source.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      final cropper = _FakeAvatarNativeCropper(
        croppedImage: _FakeAvatarCroppedImage(Uint8List.fromList([9, 8, 7])),
      );

      await _pick(
        tester,
        imageSource: imageSource,
        cropper: cropper,
        platform: TargetPlatform.iOS,
        locale: const Locale('es'),
      );

      final request = cropper.requests.single;
      expect(request.title, 'Recortar avatar');
      expect(request.doneButtonTitle, 'Listo');
      expect(request.cancelButtonTitle, 'Cancelar');
    });

    testWidgets('returns null when native cropper is cancelled', (
      tester,
    ) async {
      final imageSource = _FakeAvatarImageSource(
        pickedImage: _FakeAvatarPickedImage(
          path: '/tmp/avatar-source.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      final cropper = _FakeAvatarNativeCropper();

      final result = await _pick(
        tester,
        imageSource: imageSource,
        cropper: cropper,
        platform: TargetPlatform.android,
      );

      expect(result, isNull);
      expect(cropper.requests, hasLength(1));
      expect(imageSource.pickedImage!.readCount, 0);
    });

    testWidgets('falls back to picked bytes on unsupported platforms', (
      tester,
    ) async {
      final pickedBytes = Uint8List.fromList([4, 5, 6]);
      final imageSource = _FakeAvatarImageSource(
        pickedImage: _FakeAvatarPickedImage(
          path: '/tmp/avatar-source.png',
          bytes: pickedBytes,
        ),
      );
      final cropper = _FakeAvatarNativeCropper(
        croppedImage: _FakeAvatarCroppedImage(Uint8List.fromList([9, 8, 7])),
      );

      final result = await _pick(
        tester,
        imageSource: imageSource,
        cropper: cropper,
        platform: TargetPlatform.macOS,
      );

      expect(result, pickedBytes);
      expect(cropper.requests, isEmpty);
      expect(imageSource.pickedImage!.readCount, 1);
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
      final imageSource = _FakeAvatarImageSource(completer: pickCompleter);
      final pickedImage = _FakeAvatarPickedImage(
        path: '/tmp/avatar-source.png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      final cropper = _FakeAvatarNativeCropper(
        croppedImage: _FakeAvatarCroppedImage(Uint8List.fromList([9, 8, 7])),
      );

      final resultFuture = AvatarImagePicker.pickCroppedAvatarBytes(
        context,
        imageSource: imageSource,
        nativeCropper: cropper,
        platform: TargetPlatform.android,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      pickCompleter.complete(pickedImage);

      expect(await resultFuture, isNull);
      expect(cropper.requests, isEmpty);
      expect(pickedImage.readCount, 0);
    });
  });
}

Future<Uint8List?> _pick(
  WidgetTester tester, {
  required AvatarImageSource imageSource,
  required AvatarNativeCropper cropper,
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
    imageSource: imageSource,
    nativeCropper: cropper,
    platform: platform,
  );
}

class _FakeAvatarImageSource implements AvatarImageSource {
  _FakeAvatarImageSource({this.pickedImage, this.completer});

  final _FakeAvatarPickedImage? pickedImage;
  final Completer<AvatarPickedImage?>? completer;
  final requests = <AvatarPickRequest>[];

  @override
  Future<AvatarPickedImage?> pickImage(AvatarPickRequest request) {
    requests.add(request);
    if (completer != null) {
      return completer!.future;
    }
    return Future.value(pickedImage);
  }
}

class _FakeAvatarPickedImage implements AvatarPickedImage {
  _FakeAvatarPickedImage({required this.path, required this.bytes});

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

class _FakeAvatarNativeCropper implements AvatarNativeCropper {
  _FakeAvatarNativeCropper({this.croppedImage});

  final AvatarCroppedImage? croppedImage;
  final requests = <AvatarCropRequest>[];

  @override
  Future<AvatarCroppedImage?> cropImage(
    AvatarCropRequest request, {
    required BuildContext context,
  }) async {
    requests.add(request);
    return croppedImage;
  }
}

class _FakeAvatarCroppedImage implements AvatarCroppedImage {
  _FakeAvatarCroppedImage(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;
}
