import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// Picks an avatar image and opens the native crop UI where the cropper plugin
/// supports the current platform.
class AvatarImagePicker {
  AvatarImagePicker._();

  static final ImagePicker _picker = ImagePicker();
  static final ImageCropper _cropper = ImageCropper();

  static const double _pickerMaxDimension = 512;
  static const int _cropOutputSize = 512;
  static const int _quality = 85;

  static Future<Uint8List?> pickCroppedAvatarBytes(
    BuildContext context, {
    ImageSource source = ImageSource.gallery,
  }) async {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: _pickerMaxDimension,
      maxHeight: _pickerMaxDimension,
      imageQuality: _quality,
    );
    if (picked == null) return null;
    if (!context.mounted) return null;

    if (!_cropperIsSupported) {
      return picked.readAsBytes();
    }

    final cropped = await _cropper.cropImage(
      sourcePath: picked.path,
      maxWidth: _cropOutputSize,
      maxHeight: _cropOutputSize,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: _quality,
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

    return cropped?.readAsBytes();
  }

  static bool get _cropperIsSupported {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }
}
