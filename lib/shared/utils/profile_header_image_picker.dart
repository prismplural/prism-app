import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/prism_cropped_bitmap_encoder.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';
import 'package:prism_plurality/shared/widgets/prism_image_crop_screen.dart';

@visibleForTesting
abstract interface class ProfileHeaderPickedImage {
  String get path;

  Future<Uint8List> readAsBytes();
}

@visibleForTesting
typedef ProfileHeaderPickImageFn =
    Future<ProfileHeaderPickedImage?> Function(ImageSource source);

@visibleForTesting
typedef ProfileHeaderCropImageFn = Future<Uint8List?> Function(
      Uint8List sourceBytes,
      BuildContext context, {
      required String title,
      required String doneButtonTitle,
      required String cancelButtonTitle,
    });

@visibleForTesting
typedef ProfileHeaderNormalizeImageFn =
    Future<Uint8List> Function(Uint8List bytes);

class ProfileHeaderImagePicker {
  ProfileHeaderImagePicker._();

  static Future<Uint8List?> pickCroppedHeaderBytes(
    BuildContext context, {
    ImageSource source = ImageSource.gallery,
    @visibleForTesting ProfileHeaderPickImageFn? pickImage,
    @visibleForTesting ProfileHeaderCropImageFn? cropImage,
    @visibleForTesting ProfileHeaderNormalizeImageFn? normalizeImage,
    @visibleForTesting TargetPlatform? platform,
  }) async {
    final picked = await (pickImage ?? _defaultPickImage)(source);
    if (picked == null) return null;
    if (!context.mounted) return null;
    final l10n = context.l10n;

    Future<Uint8List> normalize(Uint8List bytes) =>
        (normalizeImage ?? normalizeProfileHeaderImage)(bytes);

    if (!_cropperIsSupported(platform ?? defaultTargetPlatform)) {
      return normalize(await picked.readAsBytes());
    }

    final pickedBytes = await picked.readAsBytes();
    if (!context.mounted) return null;
    final cropped = await (cropImage ?? _defaultCropImage)(
      pickedBytes,
      context,
      title: l10n.memberProfileHeaderCropTitle,
      doneButtonTitle: l10n.done,
      cancelButtonTitle: l10n.cancel,
    );

    return cropped == null ? null : normalize(cropped);
  }

  static bool _cropperIsSupported(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }
}

Future<ProfileHeaderPickedImage?> _defaultPickImage(ImageSource source) async {
  final picked = await ImagePicker().pickImage(source: source);
  return picked == null ? null : _XFileProfileHeaderPickedImage(picked);
}

Future<Uint8List?> _defaultCropImage(
  Uint8List sourceBytes,
  BuildContext context, {
  required String title,
  required String doneButtonTitle,
  required String cancelButtonTitle,
}) async {
  final croppedBitmap = await showPrismImageCropper(
    context,
    PrismImageCropRequest(
      sourceBytes: sourceBytes,
      title: title,
      doneButtonTitle: doneButtonTitle,
      cancelButtonTitle: cancelButtonTitle,
      aspectRatio: 3,
    ),
  );
  return croppedBitmap == null
      ? null
      : encodeCroppedBitmapPng(croppedBitmap);
}

class _XFileProfileHeaderPickedImage implements ProfileHeaderPickedImage {
  const _XFileProfileHeaderPickedImage(this._file);

  final XFile _file;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}
