import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/services/desktop_camera_selection_store.dart';
import 'package:prism_plurality/shared/services/desktop_camera_session.dart';
import 'package:prism_plurality/shared/services/desktop_qr_camera.dart';
import 'package:prism_plurality/shared/widgets/desktop_qr_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDesktopQrCamera implements DesktopQrCamera {
  _FakeDesktopQrCamera(this.devices);

  List<DesktopCameraDevice> devices;
  final opened = <int>[];
  int releaseCount = 0;
  int captureCount = 0;
  bool openResult = true;

  @override
  Future<List<DesktopCameraDevice>> listDevices() async => devices;

  @override
  Future<bool> open(int index) async {
    opened.add(index);
    return openResult;
  }

  @override
  Future<DesktopQrFrame?> captureFrame() async {
    captureCount++;
    return DesktopQrFrame(
      rgb: Uint8List.fromList([0x10, 0x20, 0x30]),
      width: 1,
      height: 1,
    );
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 420, child: child)),
  );
}

Future<void> _pumpScanner(
  WidgetTester tester, {
  required _FakeDesktopQrCamera camera,
  required DesktopQrDecoder decoder,
  bool Function(String rawValue)? isValidScan,
  FutureOr<void> Function(String rawValue)? onScanned,
  VoidCallback? onBack,
  VoidCallback? onPasteFallback,
  VoidCallback? onInvalidScan,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    _wrap(
      DesktopQrScanner(
        scanned: false,
        error: null,
        session: DesktopCameraSession(camera: camera),
        selectionStore: DesktopCameraSelectionStore(prefs: prefs),
        decoder: decoder,
        isValidScan: isValidScan ?? (_) => false,
        onScanned: onScanned ?? (_) {},
        onBack: onBack ?? () {},
        onPasteFallback: onPasteFallback ?? () {},
        onInvalidScan: onInvalidScan ?? () {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _advanceCapture(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.idle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opens the persisted exact-name camera preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'desktop_qr_camera.name': 'External cam',
      'desktop_qr_camera.index': 1,
    });
    final camera = _FakeDesktopQrCamera([
      const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
      const DesktopCameraDevice(index: 1, name: 'External cam'),
    ]);

    await _pumpScanner(
      tester,
      camera: camera,
      decoder: (_, _, _) async => null,
    );

    expect(camera.opened, contains(1));
    expect(find.text('Camera'), findsWidgets);
    expect(find.text('External cam'), findsOneWidget);
    expect(find.byTooltip('Refresh cameras'), findsOneWidget);
  });

  testWidgets('persists a changed camera selection by name and index', (
    tester,
  ) async {
    final camera = _FakeDesktopQrCamera([
      const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
      const DesktopCameraDevice(index: 1, name: 'External cam'),
    ]);

    await _pumpScanner(
      tester,
      camera: camera,
      decoder: (_, _, _) async => null,
    );

    await tester.tap(find.text('Built-in cam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('External cam').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(camera.opened, containsAllInOrder([0, 1]));
    expect(
      prefs.getString('desktop_qr_camera.selection'),
      '{"name":"External cam","index":1}',
    );
    expect(prefs.getString('desktop_qr_camera.name'), isNull);
    expect(prefs.getInt('desktop_qr_camera.index'), isNull);
  });

  testWidgets('releases the camera before reporting a valid scan', (
    tester,
  ) async {
    final raw = base64Encode([1, 2, 3, 4]);
    final camera = _FakeDesktopQrCamera([
      const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
    ]);
    String? scanned;
    var releasesAtScan = 0;

    await _pumpScanner(
      tester,
      camera: camera,
      decoder: (_, _, _) async => raw,
      isValidScan: (value) => value == raw,
      onScanned: (value) {
        scanned = value;
        releasesAtScan = camera.releaseCount;
      },
    );
    await _advanceCapture(tester);

    expect(scanned, raw);
    expect(releasesAtScan, greaterThan(0));
  });

  testWidgets('releases before switching to paste fallback', (tester) async {
    final camera = _FakeDesktopQrCamera([
      const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
    ]);
    var pasted = false;
    var releasesAtPaste = 0;

    await _pumpScanner(
      tester,
      camera: camera,
      decoder: (_, _, _) async => null,
      onPasteFallback: () {
        pasted = true;
        releasesAtPaste = camera.releaseCount;
      },
    );

    await tester.tap(find.text('No camera? Paste a code instead'));
    await tester.pumpAndSettle();

    expect(pasted, isTrue);
    expect(releasesAtPaste, greaterThan(0));
  });

  testWidgets('releases before invoking back callback', (tester) async {
    final camera = _FakeDesktopQrCamera([
      const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
    ]);
    var backed = false;
    var releasesAtBack = 0;

    await _pumpScanner(
      tester,
      camera: camera,
      decoder: (_, _, _) async => null,
      onBack: () {
        backed = true;
        releasesAtBack = camera.releaseCount;
      },
    );

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(backed, isTrue);
    expect(releasesAtBack, greaterThan(0));
  });

  testWidgets('dispose releases the camera', (tester) async {
    final camera = _FakeDesktopQrCamera([
      const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
    ]);

    await _pumpScanner(
      tester,
      camera: camera,
      decoder: (_, _, _) async => null,
    );
    final releaseCount = camera.releaseCount;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.idle();

    expect(camera.releaseCount, greaterThan(releaseCount));
  });

  testWidgets(
    'inactive lifecycle does not stop and reopen the desktop camera',
    (tester) async {
      final camera = _FakeDesktopQrCamera([
        const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
      ]);

      await _pumpScanner(
        tester,
        camera: camera,
        decoder: (_, _, _) async => null,
      );
      final openCount = camera.opened.length;
      final releaseCount = camera.releaseCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      expect(camera.opened.length, openCount);
      expect(camera.releaseCount, releaseCount);
    },
  );

  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('$state lifecycle releases the desktop camera', (tester) async {
      final camera = _FakeDesktopQrCamera([
        const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
      ]);

      await _pumpScanner(
        tester,
        camera: camera,
        decoder: (_, _, _) async => null,
      );
      final releaseCount = camera.releaseCount;

      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      await tester.idle();
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      expect(camera.releaseCount, greaterThan(releaseCount));
    });
  }

  testWidgets(
    'refresh re-reads devices and opens the preferred available one',
    (tester) async {
      final camera = _FakeDesktopQrCamera([
        const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
      ]);

      await _pumpScanner(
        tester,
        camera: camera,
        decoder: (_, _, _) async => null,
      );

      camera.devices = [
        const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
        const DesktopCameraDevice(index: 1, name: 'External cam'),
      ];

      await tester.tap(find.byTooltip('Refresh cameras'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Built-in cam'));
      await tester.pumpAndSettle();

      expect(find.text('External cam'), findsOneWidget);
      expect(camera.opened.last, 0);
    },
  );

  test('owner-scoped release does not close a newer camera owner', () async {
    final camera = _FakeDesktopQrCamera([
      const DesktopCameraDevice(index: 0, name: 'Built-in cam'),
    ]);
    final session = DesktopCameraSession(camera: camera);
    final firstOwner = Object();
    final secondOwner = Object();

    await session.open(camera.devices.first, owner: firstOwner);
    await session.open(camera.devices.first, owner: secondOwner);
    final releasesAfterSecondOpen = camera.releaseCount;

    await session.release(owner: firstOwner);
    expect(camera.releaseCount, releasesAfterSecondOpen);

    await session.release(owner: secondOwner);
    expect(camera.releaseCount, releasesAfterSecondOpen + 1);
  });
}
