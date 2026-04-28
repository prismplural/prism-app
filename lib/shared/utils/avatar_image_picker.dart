import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// What a picked raw image has to expose for the cropper step to run.
///
/// Tests substitute a fake; production wraps `XFile`.
@visibleForTesting
abstract interface class AvatarPickedImage {
  String get path;

  Future<Uint8List> readAsBytes();
}

/// Bytes returned by the cropper step. Tests substitute a fake; production
/// wraps `CroppedFile`.
@visibleForTesting
abstract interface class AvatarCroppedImage {
  Future<Uint8List> readAsBytes();
}

/// Injectable image picker. Only exists so widget tests can bypass the
/// `image_picker` platform channel.
@visibleForTesting
typedef AvatarPickImageFn = Future<AvatarPickedImage?> Function(
  ImageSource source,
);

/// Injectable cropper. Only exists so widget tests can bypass the
/// `image_cropper` platform channel.
@visibleForTesting
typedef AvatarCropImageFn = Future<AvatarCroppedImage?> Function(
  String sourcePath,
  BuildContext context, {
  required String title,
  required String doneButtonTitle,
  required String cancelButtonTitle,
});

/// Picks an avatar image and opens the native crop UI where the cropper plugin
/// supports the current platform.
class AvatarImagePicker {
  AvatarImagePicker._();

  static const int _cropOutputSize = 512;
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

    if (!_cropperIsSupported(platform ?? defaultTargetPlatform)) {
      return picked.readAsBytes();
    }

    final cropped = await (cropImage ?? _defaultCropImage)(
      picked.path,
      context,
      title: context.l10n.avatarCropTitle,
      doneButtonTitle: context.l10n.done,
      cancelButtonTitle: context.l10n.cancel,
    );

    return cropped?.readAsBytes();
  }

  static bool _cropperIsSupported(TargetPlatform platform) {
    if (kIsWeb) return true;
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

Future<AvatarCroppedImage?> _defaultCropImage(
  String sourcePath,
  BuildContext context, {
  required String title,
  required String doneButtonTitle,
  required String cancelButtonTitle,
}) async {
  final colors = Theme.of(context).colorScheme;
  final isLightSurface = ThemeData.estimateBrightnessForColor(
        colors.surface,
      ) ==
      Brightness.light;
  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    maxWidth: AvatarImagePicker._cropOutputSize,
    maxHeight: AvatarImagePicker._cropOutputSize,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: AvatarImagePicker._quality,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: title,
        toolbarColor: colors.surface,
        toolbarWidgetColor: colors.onSurface,
        statusBarLight: isLightSurface,
        navBarLight: isLightSurface,
        activeControlsWidgetColor: colors.primary,
        backgroundColor: colors.surface,
        cropFrameColor: colors.primary,
        cropGridColor: colors.onSurface.withValues(alpha: 0.32),
        cropStyle: CropStyle.rectangle,
        initAspectRatio: CropAspectRatioPreset.square,
        lockAspectRatio: true,
        hideBottomControls: true,
      ),
      IOSUiSettings(
        title: title,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
        rotateButtonsHidden: false,
        rotateClockwiseButtonHidden: false,
        doneButtonTitle: doneButtonTitle,
        cancelButtonTitle: cancelButtonTitle,
        aspectRatioPresets: const [CropAspectRatioPreset.square],
      ),
      if (kIsWeb)
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 480, height: 480),
        ),
    ],
  );

  return cropped == null ? null : _CroppedFileAvatarCroppedImage(cropped);
}

class _XFileAvatarPickedImage implements AvatarPickedImage {
  const _XFileAvatarPickedImage(this._file);

  final XFile _file;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

class _CroppedFileAvatarCroppedImage implements AvatarCroppedImage {
  const _CroppedFileAvatarCroppedImage(this._file);

  final CroppedFile _file;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}
