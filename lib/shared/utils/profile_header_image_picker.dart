import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';

@visibleForTesting
abstract interface class ProfileHeaderPickedImage {
  String get path;

  Future<Uint8List> readAsBytes();
}

@visibleForTesting
abstract interface class ProfileHeaderCroppedImage {
  Future<Uint8List> readAsBytes();
}

@visibleForTesting
typedef ProfileHeaderPickImageFn =
    Future<ProfileHeaderPickedImage?> Function(ImageSource source);

@visibleForTesting
typedef ProfileHeaderCropImageFn =
    Future<ProfileHeaderCroppedImage?> Function(
      String sourcePath,
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

  static const int _maxWidth = 1800;
  static const int _maxHeight = 600;
  static const int _quality = 86;

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

    Future<Uint8List> normalize(Uint8List bytes) =>
        (normalizeImage ?? normalizeProfileHeaderImage)(bytes);

    if (!_cropperIsSupported(platform ?? defaultTargetPlatform)) {
      return normalize(await picked.readAsBytes());
    }

    final cropped = await (cropImage ?? _defaultCropImage)(
      picked.path,
      context,
      title: context.l10n.memberProfileHeaderCropTitle,
      doneButtonTitle: context.l10n.done,
      cancelButtonTitle: context.l10n.cancel,
    );

    final croppedBytes = await cropped?.readAsBytes();
    return croppedBytes == null ? null : normalize(croppedBytes);
  }

  static bool _cropperIsSupported(TargetPlatform platform) {
    if (kIsWeb) return true;
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

Future<ProfileHeaderCroppedImage?> _defaultCropImage(
  String sourcePath,
  BuildContext context, {
  required String title,
  required String doneButtonTitle,
  required String cancelButtonTitle,
}) async {
  final colors = Theme.of(context).colorScheme;
  final isLightSurface =
      ThemeData.estimateBrightnessForColor(colors.surface) == Brightness.light;
  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    maxWidth: ProfileHeaderImagePicker._maxWidth,
    maxHeight: ProfileHeaderImagePicker._maxHeight,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: ProfileHeaderImagePicker._quality,
    aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 1),
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
        initAspectRatio: CropAspectRatioPreset.ratio3x2,
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
        aspectRatioPresets: const [CropAspectRatioPreset.ratio3x2],
      ),
      if (kIsWeb)
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 540, height: 360),
        ),
    ],
  );

  return cropped == null
      ? null
      : _CroppedFileProfileHeaderCroppedImage(cropped);
}

class _XFileProfileHeaderPickedImage implements ProfileHeaderPickedImage {
  const _XFileProfileHeaderPickedImage(this._file);

  final XFile _file;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

class _CroppedFileProfileHeaderCroppedImage
    implements ProfileHeaderCroppedImage {
  const _CroppedFileProfileHeaderCroppedImage(this._file);

  final CroppedFile _file;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}
