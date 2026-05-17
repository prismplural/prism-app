import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/picked_image_normalizer.dart';
import 'package:prism_plurality/shared/utils/prism_cropped_bitmap_encoder.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';
import 'package:prism_plurality/shared/widgets/prism_image_crop_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

@visibleForTesting
abstract interface class ProfileHeaderPickedImage {
  String get path;

  Future<Uint8List> readAsBytes();
}

@visibleForTesting
typedef ProfileHeaderPickImageFn =
    Future<ProfileHeaderPickedImage?> Function(ImageSource source);

@visibleForTesting
typedef ProfileHeaderCropImageFn =
    Future<Uint8List?> Function(
      Uint8List sourceBytes,
      BuildContext context, {
      required String title,
      required String doneButtonTitle,
      required String cancelButtonTitle,
    });

@visibleForTesting
typedef ProfileHeaderNormalizeImageFn =
    Future<Uint8List> Function(Uint8List bytes);

/// Injectable picker-bytes normalizer. Production runs picker output through
/// `platform_image_converter` on iOS to dodge oversized JPEG / wide-gamut
/// decode failures inside the cropper.
@visibleForTesting
typedef ProfileHeaderNormalizePickedBytesFn =
    Future<Uint8List?> Function(
      Uint8List sourceBytes, {
      TargetPlatform? platform,
    });

class ProfileHeaderImagePicker {
  ProfileHeaderImagePicker._();

  static Future<Uint8List?> pickCroppedHeaderBytes(
    BuildContext context, {
    ImageSource source = ImageSource.gallery,
    @visibleForTesting ProfileHeaderPickImageFn? pickImage,
    @visibleForTesting ProfileHeaderCropImageFn? cropImage,
    @visibleForTesting ProfileHeaderNormalizeImageFn? normalizeImage,
    @visibleForTesting
    ProfileHeaderNormalizePickedBytesFn? normalizePickedBytes,
    @visibleForTesting PrismFileDialogService? fileDialogService,
    @visibleForTesting TargetPlatform? platform,
  }) async {
    final resolvedPlatform = platform ?? defaultTargetPlatform;
    final picked =
        await (pickImage ??
            (source) => _defaultPickImage(
              source,
              platform: resolvedPlatform,
              fileDialogService: fileDialogService,
            ))(source);
    if (picked == null) return null;
    if (!context.mounted) return null;
    final l10n = context.l10n;

    Future<Uint8List> normalize(Uint8List bytes) =>
        (normalizeImage ?? normalizeProfileHeaderImage)(bytes);

    if (!_cropperIsSupported(resolvedPlatform)) {
      return normalize(await picked.readAsBytes());
    }

    final pickedBytes = await picked.readAsBytes();
    if (!context.mounted) return null;

    if (pickedBytes.isEmpty) {
      PrismToast.error(
        context,
        message: l10n.memberProfileHeaderProcessingError,
      );
      return null;
    }

    final normalizedBytes =
        await (normalizePickedBytes ?? normalizePickedImageBytes)(
          pickedBytes,
          platform: resolvedPlatform,
        );
    if (!context.mounted) return null;
    if (normalizedBytes == null || normalizedBytes.isEmpty) {
      PrismToast.error(
        context,
        message: l10n.memberProfileHeaderProcessingError,
      );
      return null;
    }

    final cropped = await (cropImage ?? _defaultCropImage)(
      normalizedBytes,
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

Future<ProfileHeaderPickedImage?> _defaultPickImage(
  ImageSource source, {
  required TargetPlatform platform,
  PrismFileDialogService? fileDialogService,
}) async {
  if (source == ImageSource.gallery && _isDesktopPlatform(platform)) {
    final picked = await (fileDialogService ?? PlatformPrismFileDialogService())
        .pickImageFile();
    return picked == null ? null : _FileDialogProfileHeaderPickedImage(picked);
  }

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
  return croppedBitmap == null ? null : encodeCroppedBitmapPng(croppedBitmap);
}

class _XFileProfileHeaderPickedImage implements ProfileHeaderPickedImage {
  const _XFileProfileHeaderPickedImage(this._file);

  final XFile _file;

  @override
  String get path => _file.path;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

class _FileDialogProfileHeaderPickedImage implements ProfileHeaderPickedImage {
  const _FileDialogProfileHeaderPickedImage(this._file);

  final PickedFileHandle _file;

  @override
  String get path => _file.path ?? _file.name;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

bool _isDesktopPlatform(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => false,
  };
}
