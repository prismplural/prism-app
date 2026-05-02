import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_picker.dart';

class _PickedImage implements ProfileHeaderPickedImage {
  const _PickedImage();

  @override
  String get path => '/tmp/header.jpg';

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3]);
}

class _CroppedImage implements ProfileHeaderCroppedImage {
  const _CroppedImage();

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([4, 5, 6]);
}

void main() {
  testWidgets('passes profile header cropper title and button labels', (
    tester,
  ) async {
    final calls =
        <
          ({
            String sourcePath,
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
            sourcePath,
            context, {
            required title,
            required doneButtonTitle,
            required cancelButtonTitle,
          }) async {
            calls.add((
              sourcePath: sourcePath,
              title: title,
              doneButtonTitle: doneButtonTitle,
              cancelButtonTitle: cancelButtonTitle,
            ));
            return const _CroppedImage();
          },
      normalizeImage: (value) async => value,
    );

    expect(bytes, Uint8List.fromList([4, 5, 6]));
    expect(calls, hasLength(1));
    expect(calls.single.sourcePath, '/tmp/header.jpg');
    expect(calls.single.title, 'Crop profile header');
    expect(calls.single.doneButtonTitle, 'Done');
    expect(calls.single.cancelButtonTitle, 'Cancel');
  });
}
