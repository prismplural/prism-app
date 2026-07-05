import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;
import 'package:prism_sync/generated/api.dart' as sync_api;
import 'package:prism_sync/generated/frb_generated.dart' as sync_generated;

const _mediaCodecAssetId =
    'package:prism_media_codec/generated/frb_generated.dart';
const _syncAssetId = 'package:prism_sync/generated/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads Prism sync and media codec native assets together',
    () async {
      final manifestFile = _nativeAssetManifestFile();
      if (!manifestFile.existsSync()) {
        final message =
            'Native asset manifest was not built: ${manifestFile.path}';
        if (_requiresNativeAssets) {
          fail(message);
        }
        markTestSkipped(message);
        return;
      }

      await sync_generated.RustLib.init(
        externalLibrary: _nativeAssetLibraryForTest(manifestFile, _syncAssetId),
      );
      addTearDown(sync_generated.RustLib.dispose);

      await media_codec.MediaCodecRustLib.init(
        externalLibrary: _nativeAssetLibraryForTest(
          manifestFile,
          _mediaCodecAssetId,
        ),
      );
      addTearDown(media_codec.MediaCodecRustLib.dispose);

      final secretKey = await sync_api.generateSecretKey();
      expect(secretKey.trim().split(RegExp(r'\s+')), hasLength(12));
      expect(await media_codec.codecHealthCheck(), 'prism_media_codec_ffi');

      final source = img.Image(width: 2, height: 1);
      img.fill(source, color: img.ColorRgb8(20, 80, 140));
      final (encodedBytes, mimeType) = await media_codec.encodeImage(
        imageBytes: img.encodePng(source),
        maxWidth: 8,
        maxHeight: 8,
        quality: 85,
      );

      expect(mimeType, 'image/jpeg');
      final decoded = img.decodeImage(encodedBytes);
      expect(decoded, isNotNull);
      expect((decoded!.width, decoded.height), (2, 1));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

File _nativeAssetManifestFile() =>
    File('build/native_assets/${Platform.operatingSystem}/native_assets.json');

ExternalLibrary _nativeAssetLibraryForTest(File manifestFile, String assetId) {
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
  final nativeAssets = manifest['native-assets'] as Map;
  final targetKey = _nativeAssetTargetKey();
  final assetsForTarget = nativeAssets[targetKey] as Map?;

  if (assetsForTarget == null) {
    throw StateError(
      'Native asset target $targetKey was not found in $manifestFile',
    );
  }

  final entry = assetsForTarget[assetId] as List?;
  if (entry != null && entry.length == 2 && entry.first == 'absolute') {
    return ExternalLibrary.open(entry.last as String);
  }

  throw StateError('Native asset $assetId was not found in $manifestFile');
}

String _nativeAssetTargetKey() {
  switch (Abi.current()) {
    case Abi.androidArm:
      return 'android_arm';
    case Abi.androidArm64:
      return 'android_arm64';
    case Abi.androidIA32:
      return 'android_ia32';
    case Abi.androidX64:
      return 'android_x64';
    case Abi.iosArm:
      return 'ios_arm';
    case Abi.iosArm64:
      return 'ios_arm64';
    case Abi.iosX64:
      return 'ios_x64';
    case Abi.linuxArm:
      return 'linux_arm';
    case Abi.linuxArm64:
      return 'linux_arm64';
    case Abi.linuxIA32:
      return 'linux_ia32';
    case Abi.linuxX64:
      return 'linux_x64';
    case Abi.macosArm64:
      return 'macos_arm64';
    case Abi.macosX64:
      return 'macos_x64';
    case Abi.windowsArm64:
      return 'windows_arm64';
    case Abi.windowsIA32:
      return 'windows_ia32';
    case Abi.windowsX64:
      return 'windows_x64';
    case Abi.fuchsiaArm64:
      return 'fuchsia_arm64';
    case Abi.fuchsiaX64:
      return 'fuchsia_x64';
  }

  throw StateError(
    'Unsupported host ABI for native asset smoke test: ${Abi.current()}',
  );
}

bool get _requiresNativeAssets {
  final env = Platform.environment;
  return env['CI'] == 'true' || env['PRISM_REQUIRE_NATIVE_ASSETS'] == '1';
}
