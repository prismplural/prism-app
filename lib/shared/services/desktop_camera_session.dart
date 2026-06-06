import 'dart:async';

import 'package:flutter/foundation.dart';

import 'desktop_qr_camera.dart';

class DesktopCameraSession {
  DesktopCameraSession({DesktopQrCamera? camera})
    : _camera = camera ?? FlutterLiteDesktopQrCamera();

  static final DesktopCameraSession _shared = DesktopCameraSession();

  factory DesktopCameraSession.shared() => _shared;

  static const _captureTimeout = Duration(seconds: 2);

  final DesktopQrCamera _camera;
  Future<void> _queue = Future<void>.value();
  bool _opened = false;
  Object? _owner;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<List<DesktopCameraDevice>> listDevices() {
    return _enqueue(_camera.listDevices);
  }

  Future<bool> open(DesktopCameraDevice device, {Object? owner}) {
    return _enqueue(() async {
      await _releaseUnlocked();
      final opened = await _camera.open(device.index);
      _opened = opened;
      _owner = opened ? owner : null;
      return opened;
    });
  }

  Future<DesktopQrFrame?> captureFrame({Object? owner}) {
    return _enqueue(() async {
      if (!_opened) return null;
      if (owner != null && _owner != owner) return null;
      return _camera.captureFrame().timeout(
        _captureTimeout,
        onTimeout: () {
          debugPrint('[SYNC] Desktop camera capture timed out');
          return null;
        },
      );
    });
  }

  Future<void> release({Object? owner}) {
    return _enqueue(() async {
      if (owner != null && _owner != owner) return;
      await _releaseUnlocked();
    });
  }

  Future<void> _releaseUnlocked() async {
    try {
      await _camera.release();
    } catch (error) {
      debugPrint('[SYNC] Desktop camera release failed: $error');
    } finally {
      _opened = false;
      _owner = null;
    }
  }
}
