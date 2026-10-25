import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';
import 'package:prism_plurality/shared/utils/picked_image_normalizer.dart';
import 'package:prism_plurality/shared/utils/prism_cropped_bitmap_encoder.dart';
import 'package:prism_plurality/shared/widgets/prism_image_crop_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

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

/// Injectable byte normalizer. Production runs picker output through
/// `platform_image_converter` on iOS to dodge oversized JPEG / wide-gamut
/// decode failures inside the cropper.
@visibleForTesting
typedef AvatarNormalizeBytesFn =
    Future<Uint8List?> Function(
      Uint8List sourceBytes, {
      TargetPlatform? platform,
    });

/// Picks an avatar image and opens Prism's crop UI before storage.
class AvatarImagePicker {
  AvatarImagePicker._();

  static const int _cropOutputSize = AvatarNormalizer.maxDimension;

  static Future<Uint8List?> pickCroppedAvatarBytes(
    BuildContext context, {
    ImageSource source = ImageSource.gallery,
    @visibleForTesting AvatarPickImageFn? pickImage,
    @visibleForTesting AvatarCropImageFn? cropImage,
    @visibleForTesting AvatarNormalizeBytesFn? normalizeBytes,
    @visibleForTesting PrismFileDialogService? fileDialogService,
    @visibleForTesting TargetPlatform? platform,
  }) async {
    // Skip maxWidth/maxHeight/imageQuality here so image_picker passes the
    // raw image through. The cropper performs a single resize + re-encode.
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

    final pickedBytes = await picked.readAsBytes();
    if (!context.mounted) return null;

    // image_picker_ios silently writes a 0-byte .jpg when UIImage initWithData:
    // fails (HDR / depth / certain iOS-26 HEIC variants). Bail before the
    // cropper opens to a blank canvas.
    if (pickedBytes.isEmpty) {
      PrismToast.error(context, message: l10n.imageCropProcessingError);
      return null;
    }

    // iOS's general picker converter intentionally emits JPEG. Avatars need
    // an alpha-preserving PNG path, with the same pre-crop detail ceiling.
    final normalizedBytes =
        resolvedPlatform == TargetPlatform.iOS && _hasPngSignature(pickedBytes)
        ? await compute(_prepareAvatarPngForCrop, pickedBytes)
        : await (normalizeBytes ?? normalizePickedImageBytes)(
            pickedBytes,
            platform: resolvedPlatform,
          );
    if (!context.mounted) return null;
    if (normalizedBytes == null || normalizedBytes.isEmpty) {
      PrismToast.error(context, message: l10n.imageCropProcessingError);
      return null;
    }

    final cropped = await (cropImage ?? _defaultCropImage)(
      normalizedBytes,
      context,
      title: l10n.avatarCropTitle,
      doneButtonTitle: l10n.done,
      cancelButtonTitle: l10n.cancel,
    );

    return cropped;
  }
}

Future<AvatarPickedImage?> _defaultPickImage(
  ImageSource source, {
  required TargetPlatform platform,
  PrismFileDialogService? fileDialogService,
}) async {
  if (source == ImageSource.gallery && _isDesktopPlatform(platform)) {
    final picked = await (fileDialogService ?? PlatformPrismFileDialogService())
        .pickImageFile();
    return picked == null ? null : _FileDialogAvatarPickedImage(picked);
  }

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
  return compute(encodeAvatarOutputForStorage, croppedBytes);
}

@visibleForTesting
Uint8List encodeAvatarOutputForStorage(Uint8List bytes) {
  img.Image? decoded;
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) throw StateError('Invalid cropped avatar header');
    AvatarNormalizer.validateSourceDimensions(info.width, info.height);
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw StateError('Unable to decode cropped avatar image');
  }
  if (decoded == null) {
    throw StateError('Unable to decode cropped avatar image');
  }

  // Average, not cubic — see AvatarNormalizer._resize.
  final resized =
      decoded.width <= AvatarImagePicker._cropOutputSize &&
          decoded.height <= AvatarImagePicker._cropOutputSize
      ? decoded
      : img.copyResize(
          decoded,
          width: AvatarImagePicker._cropOutputSize,
          height: AvatarImagePicker._cropOutputSize,
          interpolation: img.Interpolation.average,
        );

  // The crop result must use the same alpha/byte-budget policy as subsequent
  // repository writes. This work stays inside the crop encoder's compute call.
  return AvatarNormalizer.normalize(
    Uint8List.fromList(img.encodePng(resized)),
  )!;
}

bool _hasPngSignature(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

// Called only through compute: header probing, pixel decoding and resizing must
// not block the UI isolate. Do not use storage normalization here: the user
// still needs up to 4096px of detail to select and zoom their crop.
Uint8List? _prepareAvatarPngForCrop(Uint8List bytes) {
  const maxCropDimension = 4096;
  try {
    final info = img.PngDecoder().startDecode(bytes);
    if (info == null) return null;
    AvatarNormalizer.validateSourceDimensions(info.width, info.height);
    if (info.width <= maxCropDimension && info.height <= maxCropDimension) {
      return bytes;
    }
    final decoded = img.decodePng(bytes);
    if (decoded == null) return null;
    final longEdge = decoded.width >= decoded.height
        ? decoded.width
        : decoded.height;
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * maxCropDimension / longEdge).round().clamp(
        1,
        maxCropDimension,
      ),
      height: (decoded.height * maxCropDimension / longEdge).round().clamp(
        1,
        maxCropDimension,
      ),
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodePng(resized));
  } catch (_) {
    // Never fall back to JPEG for an invalid or oversized alpha image.
    return null;
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

class _FileDialogAvatarPickedImage implements AvatarPickedImage {
  const _FileDialogAvatarPickedImage(this._file);

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
