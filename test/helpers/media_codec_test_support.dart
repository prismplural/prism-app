import 'dart:io';

String? missingMediaCodecFfiLibReason(
  String? ffiLibPath,
  String testDescription,
) => ffiLibPath == null
    ? 'Media codec FFI lib not built for $testDescription'
    : null;

String? resolveMediaCodecFfiLibPath() {
  final name = Platform.isWindows
      ? 'prism_media_codec_ffi.dll'
      : Platform.isMacOS
      ? 'libprism_media_codec_ffi.dylib'
      : 'libprism_media_codec_ffi.so';
  final nativeAssetsDir = Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.isWindows
      ? 'windows'
      : Platform.operatingSystem;
  final cwd = Directory.current.path;
  final candidates = [
    '$cwd/build/native_assets/$nativeAssetsDir/$name',
    '$cwd/packages/prism_media_codec/rust/target/debug/$name',
    '$cwd/packages/prism_media_codec/rust/target/debug/deps/$name',
    '$cwd/packages/prism_media_codec/rust/target/release/$name',
    '$cwd/packages/prism_media_codec/rust/target/release/deps/$name',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
