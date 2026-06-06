import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/services/desktop_camera_selection_store.dart';
import 'package:prism_plurality/shared/services/desktop_camera_session.dart';
import 'package:prism_plurality/shared/services/desktop_qr_camera.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';

import '../services/desktop_qr_decoder_stub.dart'
    if (dart.library.io) '../services/desktop_qr_decoder.dart'
    as desktop_qr;

typedef DesktopQrDecoder =
    Future<String?> Function(Uint8List rgba, int width, int height);

class DesktopQrScanner extends StatefulWidget {
  const DesktopQrScanner({
    super.key,
    required this.scanned,
    required this.error,
    required this.onBack,
    required this.isValidScan,
    required this.onScanned,
    required this.onInvalidScan,
    required this.onPasteFallback,
    this.session,
    this.selectionStore,
    this.decoder,
  });

  final bool scanned;
  final String? error;
  final VoidCallback onBack;
  final bool Function(String rawValue) isValidScan;
  final FutureOr<void> Function(String rawValue) onScanned;
  final VoidCallback onInvalidScan;
  final VoidCallback onPasteFallback;
  final DesktopCameraSession? session;
  final DesktopCameraSelectionStore? selectionStore;
  final DesktopQrDecoder? decoder;

  @override
  State<DesktopQrScanner> createState() => _DesktopQrScannerState();
}

class _DesktopQrScannerState extends State<DesktopQrScanner>
    with WidgetsBindingObserver {
  static const _captureInterval = Duration(milliseconds: 125);
  static const _decodeInterval = Duration(milliseconds: 350);

  late final DesktopCameraSession _session =
      widget.session ?? DesktopCameraSession.shared();
  late final DesktopCameraSelectionStore _selectionStore =
      widget.selectionStore ?? DesktopCameraSelectionStore();
  late final DesktopQrDecoder _decoder =
      widget.decoder ?? desktop_qr.decodeDesktopQr;
  final Object _ownerToken = Object();

  Timer? _captureTimer;
  List<DesktopCameraDevice> _devices = const [];
  DesktopCameraDevice? _selectedDevice;
  ui.Image? _latestFrame;
  DateTime _nextDecodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _generation = 0;
  int _previewSequence = 0;
  int _latestPreviewSequence = 0;
  bool _loadingDevices = true;
  bool _openingCamera = false;
  bool _captureInFlight = false;
  bool _cameraRunning = false;
  bool _decoding = false;
  bool _handlingScan = false;
  bool _reportedScan = false;
  String? _cameraError;
  DateTime? _lastInvalidScanAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshDevices(openPreferred: true));
  }

  @override
  void didUpdateWidget(DesktopQrScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanned && !oldWidget.scanned) {
      _reportedScan = true;
      unawaited(_stopCamera());
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    unawaited(_stopCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final selected = _selectedDevice;
        if (!_reportedScan &&
            selected != null &&
            !_cameraRunning &&
            !_openingCamera) {
          unawaited(_openDevice(selected));
        }
      case AppLifecycleState.inactive:
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_stopCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _captureTimer?.cancel();
    _captureTimer = null;
    _cameraRunning = false;
    unawaited(_session.release(owner: _ownerToken));
    _latestFrame?.dispose();
    _latestFrame = null;
    super.dispose();
  }

  Future<void> _refreshDevices({bool openPreferred = false}) async {
    final generation = ++_generation;
    _captureTimer?.cancel();
    _captureTimer = null;
    _cameraRunning = false;
    setState(() {
      _loadingDevices = true;
      _openingCamera = false;
      _captureInFlight = false;
      _cameraError = null;
    });
    _clearPreview();

    await _session.release(owner: _ownerToken);
    if (!mounted || generation != _generation) return;

    try {
      final devices = await _session.listDevices();
      final preferred = await _selectionStore.preferredDevice(devices);
      if (!mounted || generation != _generation) return;

      setState(() {
        _devices = devices;
        _selectedDevice = preferred;
        _loadingDevices = false;
        _cameraError = devices.isEmpty
            ? context.l10n.syncSetupDesktopCameraNoCameras
            : null;
      });

      if (openPreferred && preferred != null) {
        await _openDevice(preferred);
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _devices = const [];
        _selectedDevice = null;
        _loadingDevices = false;
        _cameraError = error.toString();
      });
    }
  }

  Future<void> _openDevice(DesktopCameraDevice device) async {
    final generation = ++_generation;
    _captureTimer?.cancel();
    _captureTimer = null;
    _cameraRunning = false;
    setState(() {
      _selectedDevice = device;
      _openingCamera = true;
      _captureInFlight = false;
      _cameraError = null;
    });
    _clearPreview();

    await _session.release(owner: _ownerToken);
    if (!mounted || generation != _generation) return;

    try {
      final opened = await _session.open(device, owner: _ownerToken);
      if (!mounted || generation != _generation) return;
      if (!opened) {
        setState(() {
          _openingCamera = false;
          _cameraRunning = false;
          _cameraError = context.l10n.syncSetupDesktopCameraOpenFailed;
        });
        return;
      }

      await _selectionStore.save(device);
      if (!mounted || generation != _generation) return;
      setState(() {
        _openingCamera = false;
        _cameraRunning = true;
        _cameraError = null;
      });
      _startCaptureLoop(generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _openingCamera = false;
        _cameraRunning = false;
        _cameraError = error.toString();
      });
    }
  }

  void _startCaptureLoop(int generation) {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(_captureInterval, (_) {
      unawaited(_captureTick(generation));
    });
    unawaited(_captureTick(generation));
  }

  Future<void> _stopCamera() async {
    _generation++;
    _captureTimer?.cancel();
    _captureTimer = null;
    _captureInFlight = false;
    _openingCamera = false;
    _cameraRunning = false;
    await _session.release(owner: _ownerToken);
  }

  void _clearPreview() {
    final previous = _latestFrame;
    _latestFrame = null;
    _latestPreviewSequence = 0;
    previous?.dispose();
  }

  Future<void> _stopThen(VoidCallback callback) async {
    await _stopCamera();
    if (!mounted) return;
    callback();
  }

  Future<void> _captureTick(int generation) async {
    if (!mounted ||
        generation != _generation ||
        _captureInFlight ||
        _reportedScan ||
        _openingCamera) {
      return;
    }

    _captureInFlight = true;
    try {
      final frame = await _session.captureFrame(owner: _ownerToken);
      if (!mounted || generation != _generation || frame == null) return;

      final rgba = _rgb888ToRgba8888(frame.rgb, frame.width, frame.height);
      final previewSequence = ++_previewSequence;
      final now = DateTime.now();
      if (!_decoding && now.isAfter(_nextDecodeAt)) {
        _nextDecodeAt = now.add(_decodeInterval);
        unawaited(_decodeFrame(rgba, frame.width, frame.height, generation));
      }

      unawaited(
        _showPreview(
          rgba,
          frame.width,
          frame.height,
          generation,
          previewSequence,
        ).catchError((Object error) {
          debugPrint('[SYNC] Desktop QR preview failed: $error');
        }),
      );
    } catch (error) {
      debugPrint('[SYNC] Desktop QR camera frame failed: $error');
    } finally {
      _captureInFlight = false;
    }
  }

  Future<void> _showPreview(
    Uint8List rgba,
    int width,
    int height,
    int generation,
    int previewSequence,
  ) async {
    final image = await _decodeRgbaImage(rgba, width, height);
    if (!mounted ||
        generation != _generation ||
        previewSequence < _latestPreviewSequence) {
      image.dispose();
      return;
    }

    final previous = _latestFrame;
    setState(() {
      _latestPreviewSequence = previewSequence;
      _latestFrame = image;
    });
    previous?.dispose();
  }

  Future<void> _decodeFrame(
    Uint8List rgba,
    int width,
    int height,
    int generation,
  ) async {
    _decoding = true;
    try {
      final raw = await _decoder(rgba, width, height);
      if (!mounted || generation != _generation || raw == null || raw.isEmpty) {
        return;
      }
      await _handleRawQr(raw);
    } catch (error) {
      debugPrint('[SYNC] Desktop QR decode failed: $error');
    } finally {
      _decoding = false;
    }
  }

  Future<void> _handleRawQr(String raw) async {
    if (_handlingScan || _reportedScan) return;
    if (!widget.isValidScan(raw)) {
      _notifyInvalidScan();
      return;
    }

    _handlingScan = true;
    _reportedScan = true;
    try {
      await _stopCamera();
      if (!mounted) return;
      await widget.onScanned(raw);
    } finally {
      _handlingScan = false;
    }
  }

  void _notifyInvalidScan() {
    final now = DateTime.now();
    final last = _lastInvalidScanAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalidScanAt = now;
    widget.onInvalidScan();
  }

  Uint8List _rgb888ToRgba8888(Uint8List rgb, int width, int height) {
    final pixelCount = width * height;
    final rgba = Uint8List(pixelCount * 4);
    final availablePixels = (rgb.length ~/ 3).clamp(0, pixelCount).toInt();
    for (var pixel = 0; pixel < availablePixels; pixel++) {
      final src = pixel * 3;
      final dst = pixel * 4;
      rgba[dst] = rgb[src];
      rgba[dst + 1] = rgb[src + 1];
      rgba[dst + 2] = rgb[src + 2];
      rgba[dst + 3] = 0xff;
    }
    return rgba;
  }

  Future<ui.Image> _decodeRgbaImage(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Widget _buildPreview(BuildContext context) {
    final theme = Theme.of(context);
    final message =
        _cameraError ??
        (_loadingDevices
            ? context.l10n.loading
            : _openingCamera
            ? context.l10n.syncSetupDesktopCameraOpening
            : context.l10n.loading);

    return ClipRRect(
      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(16)),
      child: SizedBox(
        height: 280,
        child: ColoredBox(
          color: Colors.black,
          child: _latestFrame != null && _cameraError == null
              ? RawImage(image: _latestFrame, fit: BoxFit.cover)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  List<PrismSelectItem<int>> _cameraItems() {
    return [
      for (final device in _devices)
        PrismSelectItem<int>(
          value: device.index,
          label: device.label,
          subtitle: 'Camera ${device.index + 1}',
          fieldSubtitle: 'Camera ${device.index + 1}',
          leading: Icon(AppIcons.cameraAlt, size: 18),
        ),
    ];
  }

  Future<void> _onCameraChanged(int? index) async {
    if (index == null) return;
    final device = _devices
        .where((device) => device.index == index)
        .firstOrNull;
    if (device == null) return;
    await _openDevice(device);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canChooseCamera = !_loadingDevices && _devices.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrismButton(
            label: context.l10n.back,
            onPressed: () => unawaited(_stopThen(widget.onBack)),
            icon: AppIcons.arrowBackIosNew,
            tone: PrismButtonTone.subtle,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.syncSetupScanJoinerDescription,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PrismSelect<int>(
                items: _cameraItems(),
                value: _selectedDevice?.index,
                labelText: context.l10n.syncSetupDesktopCameraLabel,
                hintText: context.l10n.syncSetupDesktopCameraLabel,
                enabled: canChooseCamera && !_openingCamera,
                onChanged: (index) => unawaited(_onCameraChanged(index)),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: PrismInlineIconButton(
                icon: AppIcons.refresh,
                onPressed: () =>
                    unawaited(_refreshDevices(openPreferred: true)),
                tooltip: context.l10n.syncSetupDesktopCameraRefresh,
                semanticLabel: context.l10n.syncSetupDesktopCameraRefresh,
                enabled: !_loadingDevices && !_openingCamera,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildPreview(context),
        const SizedBox(height: 12),
        Center(
          child: PrismButton(
            label: context.l10n.syncSetupPasteCodeLink,
            onPressed: () => unawaited(_stopThen(widget.onPasteFallback)),
            density: PrismControlDensity.compact,
            tone: PrismButtonTone.subtle,
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
