import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

@visibleForTesting
class AvatarPickRequest {
  const AvatarPickRequest({
    required this.source,
    required this.maxWidth,
    required this.maxHeight,
    required this.imageQuality,
  });

  final ImageSource source;
  final double maxWidth;
  final double maxHeight;
  final int imageQuality;
}

@visibleForTesting
class AvatarCropRequest {
  const AvatarCropRequest({
    required this.sourcePath,
    required this.maxWidth,
    required this.maxHeight,
    required this.compressQuality,
  });

  final String sourcePath;
  final int maxWidth;
  final int maxHeight;
  final int compressQuality;
}

@visibleForTesting
abstract interface class AvatarPickedImage {
  String get path;

  Future<Uint8List> readAsBytes();
}

@visibleForTesting
abstract interface class AvatarCroppedImage {
  Future<Uint8List> readAsBytes();
}

@visibleForTesting
abstract interface class AvatarImageSource {
  Future<AvatarPickedImage?> pickImage(AvatarPickRequest request);
}

@visibleForTesting
abstract interface class AvatarNativeCropper {
  Future<AvatarCroppedImage?> cropImage(
    AvatarCropRequest request, {
    required BuildContext context,
  });
}

/// Picks an avatar image and opens the native crop UI where the cropper plugin
/// supports the current platform.
class AvatarImagePicker {
  AvatarImagePicker._();

  static final AvatarImageSource _imageSource = _ImagePickerAvatarSource();
  static final AvatarNativeCropper _nativeCropper =
      _ImageCropperAvatarNativeCropper();

  static const double _pickerMaxDimension = 512;
  static const int _cropOutputSize = 512;
  static const int _quality = 85;

  static Future<Uint8List?> pickCroppedAvatarBytes(
    BuildContext context, {
    ImageSource source = ImageSource.gallery,
    @visibleForTesting AvatarImageSource? imageSource,
    @visibleForTesting AvatarNativeCropper? nativeCropper,
    @visibleForTesting TargetPlatform? platform,
  }) async {
    final picked = await (imageSource ?? _imageSource).pickImage(
      AvatarPickRequest(
        source: source,
        maxWidth: _pickerMaxDimension,
        maxHeight: _pickerMaxDimension,
        imageQuality: _quality,
      ),
    );
    if (picked == null) return null;
    if (!context.mounted) return null;

    if (!_cropperIsSupported(platform ?? defaultTargetPlatform)) {
      return picked.readAsBytes();
    }

    final cropped = await (nativeCropper ?? _nativeCropper).cropImage(
      AvatarCropRequest(
        sourcePath: picked.path,
        maxWidth: _cropOutputSize,
        maxHeight: _cropOutputSize,
        compressQuality: _quality,
      ),
      context: context,
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

class _ImagePickerAvatarSource implements AvatarImageSource {
  _ImagePickerAvatarSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<AvatarPickedImage?> pickImage(AvatarPickRequest request) async {
    final picked = await _picker.pickImage(
      source: request.source,
      maxWidth: request.maxWidth,
      maxHeight: request.maxHeight,
      imageQuality: request.imageQuality,
    );
    return picked == null ? null : _XFileAvatarPickedImage(picked);
  }
}

class _XFileAvatarPickedImage implements AvatarPickedImage {
  const _XFileAvatarPickedImage(this._file);

  final XFile _file;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

class _ImageCropperAvatarNativeCropper implements AvatarNativeCropper {
  _ImageCropperAvatarNativeCropper({ImageCropper? cropper})
    : _cropper = cropper ?? ImageCropper();

  final ImageCropper _cropper;

  @override
  Future<AvatarCroppedImage?> cropImage(
    AvatarCropRequest request, {
    required BuildContext context,
  }) async {
    final colors = Theme.of(context).colorScheme;
    final cropped = await _cropper.cropImage(
      sourcePath: request.sourcePath,
      maxWidth: request.maxWidth,
      maxHeight: request.maxHeight,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: request.compressQuality,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop avatar',
          toolbarColor: colors.surface,
          toolbarWidgetColor: colors.onSurface,
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
          title: 'Crop avatar',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          rotateButtonsHidden: false,
          rotateClockwiseButtonHidden: false,
          doneButtonTitle: 'Done',
          cancelButtonTitle: 'Cancel',
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
}

class _CroppedFileAvatarCroppedImage implements AvatarCroppedImage {
  const _CroppedFileAvatarCroppedImage(this._file);

  final CroppedFile _file;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}
