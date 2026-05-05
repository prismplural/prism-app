import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_picker.dart';

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
    expect(calls.single.title, 'Crop profile header');
    expect(calls.single.doneButtonTitle, 'Done');
    expect(calls.single.cancelButtonTitle, 'Cancel');
  });

  testWidgets('normalizes real cropped bytes into decodable stored header bytes', (
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

    final pickedSource = img.Image(width: 400, height: 400);
    img.fill(pickedSource, color: img.ColorRgb8(30, 40, 50));
    final croppedSource = img.Image(width: 2400, height: 800);
    img.fill(croppedSource, color: img.ColorRgb8(220, 180, 40));

    final bytes = await ProfileHeaderImagePicker.pickCroppedHeaderBytes(
      capturedContext,
      platform: TargetPlatform.android,
      pickImage: (_) async => _BytesPickedImage(
        Uint8List.fromList(img.encodePng(pickedSource)),
      ),
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
  });
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
