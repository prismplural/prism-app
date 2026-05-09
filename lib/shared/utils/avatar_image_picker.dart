import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';
import 'package:prism_plurality/shared/utils/prism_cropped_bitmap_encoder.dart';
import 'package:prism_plurality/shared/widgets/prism_image_crop_screen.dart';

/// What a picked raw image has to expose for the cropper step to run.
///
/// Tests substitute a fake; production wraps `XFile`.
@visibleForTesting
abstract interface class AvatarPickedImage {
  String get path;

  Future<Uint8List> readAsBytes();
}

/// Injectable image picker. Only exists so widget tests can bypass the
/// `image_picker` platform channel.
@visibleForTesting
typedef AvatarPickImageFn =
    Future<AvatarPickedImage?> Function(ImageSource source);

/// Injectable cropper. Only exists so widget tests can bypass the crop route.
@visibleForTesting
typedef AvatarCropImageFn =
    Future<Uint8List?> Function(
      Uint8List sourceBytes,
      BuildContext context, {
      required String title,
      required String doneButtonTitle,
      required String cancelButtonTitle,
    });

/// Picks an avatar image and opens the native crop UI where the cropper plugin
/// supports the current platform.
class AvatarImagePicker {
  AvatarImagePicker._();

  static const int _cropOutputSize = AvatarNormalizer.maxDimension;
  static const int _quality = 85;

  static Future<Uint8List?> pickCroppedAvatarBytes(
    BuildContext context, {
    ImageSource source = ImageSource.gallery,
    @visibleForTesting AvatarPickImageFn? pickImage,
    @visibleForTesting AvatarCropImageFn? cropImage,
    @visibleForTesting TargetPlatform? platform,
  }) async {
    // Skip maxWidth/maxHeight/imageQuality here so image_picker passes the
    // raw image through. The cropper performs a single resize + re-encode.
    final picked = await (pickImage ?? _defaultPickImage)(source);
    if (picked == null) return null;
    if (!context.mounted) return null;
    final l10n = context.l10n;

    if (!_cropperIsSupported(platform ?? defaultTargetPlatform)) {
      return picked.readAsBytes();
    }

    final pickedBytes = await picked.readAsBytes();
    if (!context.mounted) return null;
    final cropped = await (cropImage ?? _defaultCropImage)(
      pickedBytes,
      context,
      title: l10n.avatarCropTitle,
      doneButtonTitle: l10n.done,
      cancelButtonTitle: l10n.cancel,
    );

    return cropped;
  }

  static bool _cropperIsSupported(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }
}

Future<AvatarPickedImage?> _defaultPickImage(ImageSource source) async {
  final picked = await ImagePicker().pickImage(source: source);
  return picked == null ? null : _XFileAvatarPickedImage(picked);
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
      aspectRatio: 1,
    ),
  );
  if (croppedBitmap == null) return null;
  final croppedBytes = await encodeCroppedBitmapPng(croppedBitmap);
  return encodeAvatarOutputForStorage(croppedBytes);
}

@visibleForTesting
Uint8List encodeAvatarOutputForStorage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw StateError('Unable to decode cropped avatar image');
  }
  if (decoded == null) {
    throw StateError('Unable to decode cropped avatar image');
  }

  final resized =
      decoded.width <= AvatarImagePicker._cropOutputSize &&
          decoded.height <= AvatarImagePicker._cropOutputSize
      ? decoded
      : img.copyResize(
          decoded,
          width: AvatarImagePicker._cropOutputSize,
          height: AvatarImagePicker._cropOutputSize,
          interpolation: img.Interpolation.cubic,
        );

  return Uint8List.fromList(
    img.encodeJpg(resized, quality: AvatarImagePicker._quality),
  );
}

class _XFileAvatarPickedImage implements AvatarPickedImage {
  const _XFileAvatarPickedImage(this._file);

  final XFile _file;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}
