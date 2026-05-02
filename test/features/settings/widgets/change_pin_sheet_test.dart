import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/change_pin_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

Widget _buildSheet() {
  return ProviderScope(
    overrides: [
      prismSyncHandleProvider.overrideWithBuild(
        (ref, notifier) => const _FakePrismSyncHandle(),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ChangePinSheet()),
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _installFfiOverrides({
  required bool unlockSucceeds,
  List<String>? capturedPins,
  List<List<int>>? capturedPasswordBuffers,
  List<List<int>>? capturedMnemonicBuffers,
}) {
  ChangePinSheet.debugMnemonicToBytesOverride = ({required mnemonic}) async {
    expect(utf8.decode(mnemonic), _validMnemonic);
    capturedMnemonicBuffers?.add(mnemonic);
    return Uint8List.fromList(List<int>.generate(16, (i) => i));
  };
  ChangePinSheet.debugUnlockOverride =
      ({required handle, required password, required secretKey}) async {
        expect(handle, isA<_FakePrismSyncHandle>());
        expect(secretKey, hasLength(16));
        capturedPins?.add(utf8.decode(password));
        capturedPasswordBuffers?.add(password);
        if (!unlockSucceeds) {
          throw Exception('wrong pin');
        }
      };
}

Future<void> _advancePastMnemonicStep(WidgetTester tester) async {
  final words = _validMnemonic.split(' ');
  for (var i = 0; i < 12; i++) {
    await tester.enterText(find.byType(TextField).at(i), words[i]);
    await tester.pump();
  }
  await tester.pumpAndSettle();

  final continueButton = find.widgetWithText(PrismButton, 'Continue');
  await tester.ensureVisible(continueButton);
  await tester.pumpAndSettle();
  await tester.tap(continueButton);
  await tester.pumpAndSettle();
}

Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.widgetWithText(PinNumpadButton, digit).first);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    ChangePinSheet.debugMnemonicToBytesOverride = null;
    ChangePinSheet.debugUnlockOverride = null;
  });

  testWidgets('wraps change PIN content in SecureScope', (tester) async {
    _useTallViewport(tester);

    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();

    expect(find.byType(SecureScope), findsOneWidget);
    expect(find.text('Enter your recovery phrase'), findsOneWidget);
  });

  testWidgets('current PIN step uses the keypad instead of text fields', (
    tester,
  ) async {
    _useTallViewport(tester);
    _installFfiOverrides(unlockSucceeds: true);

    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();
    await _advancePastMnemonicStep(tester);

    expect(find.text('Current PIN'), findsOneWidget);
    expect(find.byType(PinNumpadButton), findsNWidgets(11));
    expect(find.byType(PrismTextField), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'failed current PIN attempts clear the keypad buffer and lock out',
    (tester) async {
      _useTallViewport(tester);
      final capturedPins = <String>[];
      _installFfiOverrides(unlockSucceeds: false, capturedPins: capturedPins);

      await tester.pumpWidget(_buildSheet());
      await tester.pumpAndSettle();
      await _advancePastMnemonicStep(tester);

      for (final pin in ['123456', '654321', '111111', '222222', '333333']) {
        await _tapPin(tester, pin);
      }

      expect(capturedPins, ['123456', '654321', '111111', '222222', '333333']);
      expect(find.text('PIN or recovery phrase is incorrect.'), findsOneWidget);

      await _tapPin(tester, '444444');

      expect(capturedPins, hasLength(5));
      expect(find.textContaining('Too many attempts'), findsOneWidget);
    },
  );

  testWidgets('new and confirm PIN steps use the keypad', (tester) async {
    _useTallViewport(tester);
    final capturedPins = <String>[];
    _installFfiOverrides(unlockSucceeds: true, capturedPins: capturedPins);

    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();
    await _advancePastMnemonicStep(tester);

    await _tapPin(tester, '123456');

    expect(capturedPins, ['123456']);
    expect(find.textContaining('other devices'), findsOneWidget);

    await tester.tap(find.widgetWithText(PrismButton, 'Change PIN'));
    await tester.pumpAndSettle();

    expect(find.text('New PIN'), findsOneWidget);
    expect(find.byType(PinNumpadButton), findsNWidgets(11));
    expect(find.byType(PrismTextField), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await _tapPin(tester, '222222');

    expect(find.text('Confirm new PIN'), findsOneWidget);
    expect(find.byType(PinNumpadButton), findsNWidgets(11));
    expect(find.byType(PrismTextField), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('verification FFI password and mnemonic buffers are cleared', (
    tester,
  ) async {
    _useTallViewport(tester);
    final passwordBuffers = <List<int>>[];
    final mnemonicBuffers = <List<int>>[];
    _installFfiOverrides(
      unlockSucceeds: true,
      capturedPasswordBuffers: passwordBuffers,
      capturedMnemonicBuffers: mnemonicBuffers,
    );

    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();
    await _advancePastMnemonicStep(tester);
    await _tapPin(tester, '123456');

    expect(passwordBuffers, hasLength(1));
    expect(passwordBuffers.single, everyElement(0));
    expect(mnemonicBuffers, hasLength(1));
    expect(mnemonicBuffers.single, everyElement(0));
  });
}
