import 'package:flutter/foundation.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';

@immutable
class DesktopCameraDevice {
  const DesktopCameraDevice({required this.index, required this.name});

  final int index;
  final String name;

  String get label => name.trim().isEmpty ? 'Camera ${index + 1}' : name;
}

@immutable
class DesktopQrFrame {
  const DesktopQrFrame({
    required this.rgb,
    required this.width,
    required this.height,
  });

  final Uint8List rgb;
  final int width;
  final int height;
}

abstract interface class DesktopQrCamera {
  Future<List<DesktopCameraDevice>> listDevices();
  Future<bool> open(int index);
  Future<DesktopQrFrame?> captureFrame();
  Future<void> release();
}

class FlutterLiteDesktopQrCamera implements DesktopQrCamera {
  FlutterLiteDesktopQrCamera({FlutterLiteCamera? camera})
    : _camera = camera ?? FlutterLiteCamera();

  final FlutterLiteCamera _camera;

  @override
  Future<List<DesktopCameraDevice>> listDevices() async {
    final names = await _camera.getDeviceList();
    return [
      for (var index = 0; index < names.length; index++)
        DesktopCameraDevice(index: index, name: names[index]),
    ];
  }

  @override
  Future<bool> open(int index) => _camera.open(index);

  @override
  Future<DesktopQrFrame?> captureFrame() async {
    final frame = await _camera.captureFrame();
    final data = frame['data'];
    final width = (frame['width'] as num?)?.toInt();
    final height = (frame['height'] as num?)?.toInt();
    if (data is! Uint8List || width == null || height == null) {
      return null;
    }
    return DesktopQrFrame(rgb: data, width: width, height: height);
  }

  @override
  Future<void> release() => _camera.release();
}
