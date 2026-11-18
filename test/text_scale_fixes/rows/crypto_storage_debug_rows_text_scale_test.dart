// The crypto-storage debug screen's engine-state label/value rows at large text sizes.
//
// `_EngineStateCard` builds each row as
// `Row(spaceBetween, [Text(label), Text(value, monospace)])` with neither side
// flexible, inside `PrismSurface`'s `ClipRRect`, so at 3.375x the pair exceeds the
// card and the value is cut off at the card edge.
//
// HERMETIC GUARDS - every external read on this screen is explicitly taken over,
// none of them is left to "it throws in tests":
//   1. secure storage: `FlutterSecureStorage.setMockInitialValues` swaps in the
//      plugin's own in-memory `TestFlutterSecureStoragePlatform`. No keychain, no
//      real key material; the entries are placeholders.
//   2. filesystem: the `plugins.flutter.io/path_provider` channel is answered with
//      `null`, so `getApplicationDocumentsDirectory()` fails before any `File` is
//      constructed (that is the exact path `CryptoBootLog._file()` takes:
//      documents dir -> `File.readAsString`). Nothing under the real home is read
//      or written; `CryptoBootLog.readAll()` turns the failure into an empty log.
//      The call is counted so the test can assert the denial was really used.
//   3. runtime DEK wrapper: the `com.prism.prism_plurality/runtime_dek_wrap` channel
//      answers `getRuntimeDekDiagnostics` with a synthetic map, so
//      `DeviceBoundRuntimeDekStore().getDiagnostics()` never reaches native code.
//   4. FFI: `prismSyncHandleProvider` is overridden with a notifier that has no
//      handle, so `ffi.isUnlocked` is not called at all.
//   5. the database: `databaseProvider` throws, so an accidental DB read fails.
// All mocks are torn down in `tearDown`, and the tests do not use `runAsync`.
//
// The rows must stay inside their card at 3.375x, where the pair used to overflow and the
// value was clipped at the card edge, and must keep their inline geometry wherever they
// fit.
//
// This screen's top bar has a title and a subtitle, so its constant-height bar can
// overflow at large text (`prism_top_bar.dart`). Those errors can be ignored by cause only
// through the opt-in switch in the harness, and this test then proves nothing about the
// bar.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/views/crypto_storage_debug_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

import 'rows_text_scale_harness.dart';

/// `path_provider`'s channel: denying it keeps every file read inside the test.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// The app's runtime-DEK wrapper channel (native key wrapping + diagnostics).
const _runtimeDekChannel = MethodChannel(
  'com.prism.prism_plurality/runtime_dek_wrap',
);

/// No engine handle at all: the screen then skips every FFI call.
class _NoHandleNotifier extends PrismSyncHandleNotifier {
  @override
  Future<ffi.PrismSyncHandle?> build() async => null;
}

Widget _cryptoScreen({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        throw StateError('crypto debug row tests must not open a database');
      }),
      prismSyncHandleProvider.overrideWith(_NoHandleNotifier.new),
    ],
    child: rowsApp(
      const CryptoStorageDebugScreen(),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
    ),
  );
}

void main() {
  final channelCalls = <String>[];
  // Any channel method that is not one the screen is expected to use. Returning a
  // value for an unknown method would make a brand-new read look legitimate, so it is
  // recorded here and asserted empty instead.
  final unexpectedChannelCalls = <String>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRowsFonts();
  });

  setUp(() {
    channelCalls.clear();
    unexpectedChannelCalls.clear();

    // 1) Secure storage: the plugin's in-memory test platform. Placeholder values
    //    only - no real key, and the platform keychain is never touched.
    FlutterSecureStorage.setMockInitialValues({
      'prism_sync.db_key': 'QUJDRA==',
      'prism_sync.sync_db_key': 'RUZHSA==',
    });

    // 2) Filesystem: deny it. `path_provider` returns null, so
    //    `getApplicationDocumentsDirectory()` throws before `CryptoBootLog._file()`
    //    can build a `File`, and `readAll()` reports an empty history.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          channelCalls.add('path_provider/${call.method}');
          if (call.method != 'getApplicationDocumentsDirectory') {
            unexpectedChannelCalls.add('path_provider/${call.method}');
          }
          return null;
        });

    // 3) Runtime DEK wrapper: synthetic diagnostics, never native code.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_runtimeDekChannel, (call) async {
          channelCalls.add('runtime_dek/${call.method}');
          if (call.method != 'getRuntimeDekDiagnostics') {
            unexpectedChannelCalls.add('runtime_dek/${call.method}');
          }
          if (call.method == 'getRuntimeDekDiagnostics') {
            return <String, dynamic>{
              'provider': 'synthetic',
              'key_security': <String, dynamic>{'level': 'synthetic'},
            };
          }
          return null;
        });
  });

  tearDown(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_runtimeDekChannel, null);
  });

  /// Waits for the engine-state rows *and* for the loading indicators to clear, then
  /// proves the fixture really served data. Deliberately does not look at
  /// `hasRunningAnimations`: ambient animations on this screen (spinners, animated
  /// containers) keep that true even when every read has resolved, so it is not a
  /// read-pending signal.
  Future<void> waitForEngineRows(
    WidgetTester tester, {
    required String label,
  }) async {
    await pumpUntilFound(tester, find.text('Handle'), label: 'engine rows');
    await pumpUntilGone(
      tester,
      find.byType(PrismLoadingState),
      label: '$label: loading state',
    );
    await pumpUntilGone(
      tester,
      find.byType(PrismSpinner),
      label: '$label: spinner',
    );
    // No diagnostic channel method beyond the ones this screen is known to use: an
    // unknown call is recorded by the handlers above and fails here rather than being
    // answered with a plausible null.
    expect(
      unexpectedChannelCalls,
      isEmpty,
      reason:
          '$label: unexpected diagnostic channel call(s): '
          '${unexpectedChannelCalls.join(', ')}',
    );
    // The filesystem denial really was consulted (CryptoBootLog.readAll at mount).
    expect(
      channelCalls,
      contains('path_provider/getApplicationDocumentsDirectory'),
      reason: '$label: the filesystem guard was never exercised',
    );
    expect(
      channelCalls.any((call) => call.startsWith('path_provider/get')),
      isTrue,
    );
    // No other path_provider method may have been reached.
    expect(
      channelCalls.where(
        (call) =>
            call.startsWith('path_provider/') &&
            call != 'path_provider/getApplicationDocumentsDirectory',
      ),
      isEmpty,
      reason: '$label: an unexpected path_provider method was requested',
    );
    // (The synthetic entries are asserted separately, after scrolling to them - at a
    // wide window the keychain card sits below the fold and is built lazily.)
    // The runtime-DEK channel is only consulted off Linux; assert it was taken
    // over where the screen would reach native code.
    if (!Platform.isLinux) {
      expect(
        channelCalls,
        contains('runtime_dek/getRuntimeDekDiagnostics'),
        reason: '$label: the runtime-DEK guard was not exercised',
      );
    }
  }

  /// Scrolls to the keychain card and proves the in-memory secure-storage guard
  /// actually served synthetic entries (the card is lazy and may start off-screen).
  Future<void> expectSyntheticKeyEntries(WidgetTester tester) async {
    final entry = find.text('db_key');
    if (entry.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        entry,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.pumpAndSettle();
    expect(
      entry,
      findsWidgets,
      reason: 'the in-memory secure-storage guard was not exercised',
    );
  }

  for (final (system, app, scaleLabel) in rowsScales) {
    for (final fontFamily in rowsFontFamilies) {
      testWidgets(
        'engine-state rows stay inside their card - $scaleLabel / $fontFamily',
        (tester) async {
          useWindow(tester, tallCompactPage);
          await tester.pumpWidget(
            _cryptoScreen(system: system, app: app, fontFamily: fontFamily),
          );
          await waitForEngineRows(tester, label: 'crypto $scaleLabel');
          await expectSyntheticKeyEntries(tester);

          expectNoLayoutError(
            tester,
            label: 'crypto debug $scaleLabel',
            ignoreCauseMatching: fixedHeightBarLayoutErrors,
          );

          final handleLabel = find.text('Handle');
          expect(handleLabel, findsOneWidget);
          expectStaticLabelFullyPainted(
            tester,
            handleLabel,
            label: 'handle label ($scaleLabel)',
          );

          final cards = find.byType(PrismSectionCard);
          expect(cards, findsWidgets);
          for (var i = 0; i < cards.evaluate().length; i++) {
            expectDescendantTextInside(
              tester,
              cards.at(i),
              label: 'crypto card $i ($scaleLabel)',
            );
          }
        },
      );
    }
  }

  testWidgets('wide window where the rows fit: nothing is reflowed (control)', (
    tester,
  ) async {
    useWindow(tester, wideWindow);
    await tester.pumpWidget(_cryptoScreen(system: 2.25, app: 1.5));
    await waitForEngineRows(tester, label: 'crypto wide 3.375x');
    await expectSyntheticKeyEntries(tester);
    // Scrolling to the keychain entries culls the engine card at a wide window: bring
    // that row back into view before the inline-geometry checks below.
    await tester.scrollUntilVisible(
      find.text('Unlocked'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expectNoLayoutError(
      tester,
      label: 'crypto debug wide 3.375x',
      ignoreCauseMatching: fixedHeightBarLayoutErrors,
    );
    expectStaticLabelFullyPainted(
      tester,
      find.text('Unlocked'),
      label: 'unlocked label (wide 3.375x)',
    );
    expectOnTheSameLine(
      tester,
      find.text('Unlocked'),
      find.text('unknown'),
      label: 'label/value (wide 3.375x)',
    );
  });
}
