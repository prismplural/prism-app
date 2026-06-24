import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

const _macBackgroundIcon =
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png';
const _transparentIcon = 'assets/icon_layers/Prism-Logo-Foreground.png';
const _linuxBackgroundIcon =
    'packaging/linux/icons/hicolor/1024x1024/apps/com.prismplural.prism.png';
const _windowsIcon = 'windows/runner/resources/app_icon.ico';
const _windowsIconSizes = <int>[16, 20, 24, 32, 40, 48, 64, 128, 256];

void main(List<String> args) {
  final command = args.isEmpty ? 'check' : args.single;
  switch (command) {
    case 'check':
      _check();
    case 'generate-icons':
      _generateIcons();
    default:
      stderr.writeln(
        'Usage: dart run tool/desktop_branding.dart [check|generate-icons]',
      );
      exitCode = 64;
  }
}

void _check() {
  final failures = <String>[];

  void expect(bool condition, String message) {
    if (!condition) {
      failures.add(message);
    }
  }

  expect(
    _fileContains(
      'macos/Runner/Configs/AppInfo.xcconfig',
      RegExp(r'^PRODUCT_NAME\s*=\s*Prism$', multiLine: true),
    ),
    'macOS PRODUCT_NAME must be Prism.',
  );
  expect(
    _fileContains('macos/Runner/Info.plist', '<string>Prism</string>') ||
        _fileContains(
          'macos/Runner/Info.plist',
          r'<string>$(PRODUCT_NAME)</string>',
        ),
    'macOS CFBundleName must resolve to Prism.',
  );
  expect(
    _fileContains(
      'macos/Runner/MainFlutterWindow.swift',
      'self.title = "Prism"',
    ),
    'macOS window title must be explicitly set to Prism.',
  );
  expect(
    _fileContains('windows/runner/main.cpp', 'window.Create(L"Prism"'),
    'Windows titlebar must be Prism.',
  );
  expect(
    _fileContains(
      'windows/runner/main.cpp',
      'kPrismWindowClassName[] = L"PRISM_RUNNER_WIN32_WINDOW"',
    ),
    'Windows runner must use a Prism-specific native window class.',
  );
  expect(
    _fileContains(
      'windows/runner/win32_window.cpp',
      'kWindowClassName[] = L"PRISM_RUNNER_WIN32_WINDOW"',
    ),
    'Windows native window class must match the singleton focus lookup.',
  );
  expect(
    _fileContains(
      'windows/runner/main.cpp',
      'CreateMutex(nullptr, TRUE, kPrismAppMutexName)',
    ),
    'Windows runner must create the Prism app mutex for installer updates.',
  );
  expect(
    _fileContains(
      'windows/runner/main.cpp',
      'FindWindow(kPrismWindowClassName, nullptr)',
    ),
    'Windows runner must focus by class instead of mutable window title.',
  );
  expect(
    _fileContains('windows/runner/main.cpp', 'kFocusRetryAttempts = 100'),
    'Windows runner must briefly wait for first-instance window creation.',
  );
  expect(
    _fileContains('windows/runner/main.cpp', 'CloseHandleIfPresent(app_mutex)'),
    'Windows runner must focus the existing Prism window on a second launch.',
  );
  expect(
    _fileContains('windows/runner/flutter_window.cpp', 'startup work cannot') &&
        _fileContains(
          'windows/runner/flutter_window.cpp',
          'leave an invisible process holding plugin DLLs',
        ),
    'Windows runner must show the host window before Dart startup can block.',
  );
  expect(
    _fileContains(
      'windows/runner/Runner.rc',
      'VALUE "FileDescription", "Prism"',
    ),
    'Windows FileDescription metadata must be Prism.',
  );
  expect(
    _fileContains('windows/runner/Runner.rc', 'VALUE "ProductName", "Prism"'),
    'Windows ProductName metadata must be Prism.',
  );
  expect(
    _bytesEqual(File(_windowsIcon).readAsBytesSync(), _buildWindowsIconBytes()),
    'Windows app_icon.ico must be generated from the backgrounded Prism icon. '
    'Run `dart run tool/desktop_branding.dart generate-icons`.',
  );
  expect(
    _fileContains(
      'linux/runner/my_application.cc',
      'gtk_window_set_icon_name(window, APPLICATION_ID)',
    ),
    'Linux GTK window must set the Prism application icon name.',
  );
  expect(
    _fileContains(
      'packaging/linux/com.prismplural.prism.desktop',
      'Name=Prism',
    ),
    'Linux desktop entry name must be Prism.',
  );
  expect(
    _fileContains(
      'packaging/linux/com.prismplural.prism.desktop',
      'Icon=com.prismplural.prism',
    ),
    'Linux desktop entry icon must use the Prism app id.',
  );
  expect(
    _bytesEqual(
      File(_macBackgroundIcon).readAsBytesSync(),
      File(_linuxBackgroundIcon).readAsBytesSync(),
    ),
    'macOS and Linux 1024px app icons must share the backgrounded Prism icon.',
  );
  expect(
    !_bytesEqual(
      File(_macBackgroundIcon).readAsBytesSync(),
      File(_transparentIcon).readAsBytesSync(),
    ),
    'Desktop app icons must use the backgrounded icon, not the transparent logo.',
  );
  expect(
    _fileContains(
      '.github/workflows/desktop.yaml',
      'dart tool/desktop_branding.dart check',
    ),
    'Desktop CI must run the branding check.',
  );
  expect(
    _fileContains(
      '.github/workflows/desktop.yaml',
      r'XDG_DATA_DIRS="$DIR/share',
    ),
    'Linux CI wrapper must expose bundled desktop icons through XDG_DATA_DIRS.',
  );
  expect(
    _fileContains('.github/workflows/desktop.yaml', 'packaging/linux/icons'),
    'Linux CI tarball must include packaged Prism icon assets.',
  );
  expect(
    _fileContains('.github/workflows/desktop.yaml', 'innosetup'),
    'Windows CI must install Inno Setup for the installer artifact.',
  );
  expect(
    _fileContains(
      '.github/workflows/desktop.yaml',
      'scripts\\package_windows_installer.ps1',
    ),
    'Windows CI must package the Inno Setup installer.',
  );
  expect(
    _fileContains('packaging/windows/prism.iss', 'AppName={#AppName}'),
    'Windows installer metadata must use the Prism app name.',
  );
  expect(
    _fileContains(
      'packaging/windows/prism.iss',
      'AppPublisher={#AppPublisher}',
    ),
    'Windows installer metadata must use the Prism publisher.',
  );
  expect(
    _fileContains(
      'packaging/windows/prism.iss',
      r'SetupIconFile=..\..\windows\runner\resources\app_icon.ico',
    ),
    'Windows installer must use the Prism icon.',
  );
  expect(
    _fileContains(
      'packaging/windows/prism.iss',
      'AppMutex=PrismPluralityAppMutex',
    ),
    'Windows installer must check the Prism app mutex before updating files.',
  );

  if (failures.isNotEmpty) {
    stderr.writeln('Desktop branding check failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Desktop branding check passed.');
}

void _generateIcons() {
  File(_windowsIcon).writeAsBytesSync(_buildWindowsIconBytes());
  stdout.writeln('Generated $_windowsIcon from $_macBackgroundIcon.');
}

Uint8List _buildWindowsIconBytes() {
  final source = image.decodePng(File(_macBackgroundIcon).readAsBytesSync());
  if (source == null) {
    throw StateError('Could not decode $_macBackgroundIcon');
  }

  final pngs = <_IconPng>[];
  for (final size in _windowsIconSizes) {
    final resized = image.copyResize(
      source,
      width: size,
      height: size,
      interpolation: image.Interpolation.cubic,
    );
    pngs.add(_IconPng(size, Uint8List.fromList(image.encodePng(resized))));
  }

  final out = BytesBuilder();
  _writeUint16(out, 0); // reserved
  _writeUint16(out, 1); // ICO
  _writeUint16(out, pngs.length);

  var offset = 6 + (pngs.length * 16);
  for (final png in pngs) {
    out.addByte(png.size == 256 ? 0 : png.size);
    out.addByte(png.size == 256 ? 0 : png.size);
    out.addByte(0); // true color
    out.addByte(0); // reserved
    _writeUint16(out, 1); // color planes
    _writeUint16(out, 32); // bits per pixel
    _writeUint32(out, png.bytes.length);
    _writeUint32(out, offset);
    offset += png.bytes.length;
  }

  for (final png in pngs) {
    out.add(png.bytes);
  }
  return out.toBytes();
}

bool _fileContains(String path, Object expected) {
  final text = File(path).readAsStringSync();
  return switch (expected) {
    final RegExp pattern => pattern.hasMatch(text),
    final String literal => text.contains(literal),
    _ => throw ArgumentError.value(expected, 'expected'),
  };
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

void _writeUint16(BytesBuilder out, int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  out.add(data.buffer.asUint8List());
}

void _writeUint32(BytesBuilder out, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  out.add(data.buffer.asUint8List());
}

final class _IconPng {
  const _IconPng(this.size, this.bytes);

  final int size;
  final Uint8List bytes;
}
