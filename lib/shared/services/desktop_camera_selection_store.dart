import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_qr_camera.dart';

class DesktopCameraSelectionStore {
  DesktopCameraSelectionStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const _selectionKey = 'desktop_qr_camera.selection';
  static const _nameKey = 'desktop_qr_camera.name';
  static const _indexKey = 'desktop_qr_camera.index';

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _resolvePrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  Future<DesktopCameraDevice?> preferredDevice(
    List<DesktopCameraDevice> devices,
  ) async {
    if (devices.isEmpty) return null;

    final prefs = await _resolvePrefs();
    final saved = _readSelection(prefs);
    final savedName = saved?.name;
    final savedIndex = saved?.index;

    if (savedName != null && savedIndex != null) {
      for (final device in devices) {
        if (device.index == savedIndex && device.name == savedName) {
          return device;
        }
      }
    }

    if (savedName != null) {
      for (final device in devices) {
        if (device.name == savedName) return device;
      }
    }

    return devices.first;
  }

  Future<void> save(DesktopCameraDevice device) async {
    final prefs = await _resolvePrefs();
    await prefs.setString(
      _selectionKey,
      jsonEncode({'name': device.name, 'index': device.index}),
    );
    await prefs.remove(_nameKey);
    await prefs.remove(_indexKey);
  }

  _StoredDesktopCameraSelection? _readSelection(SharedPreferences prefs) {
    final raw = prefs.getString(_selectionKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, Object?>) {
          final name = json['name'];
          final index = json['index'];
          if (name is String && index is int) {
            return _StoredDesktopCameraSelection(name: name, index: index);
          }
        }
      } catch (_) {}
    }

    final legacyName = prefs.getString(_nameKey);
    final legacyIndex = prefs.getInt(_indexKey);
    if (legacyName != null || legacyIndex != null) {
      return _StoredDesktopCameraSelection(
        name: legacyName,
        index: legacyIndex,
      );
    }
    return null;
  }
}

class _StoredDesktopCameraSelection {
  const _StoredDesktopCameraSelection({this.name, this.index});

  final String? name;
  final int? index;
}
