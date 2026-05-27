import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/core/sharing/sharing_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/friend_record.dart';
import 'package:prism_plurality/domain/repositories/friends_repository.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/widgets/change_pin_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/secure_scope.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import '../../../helpers/fake_repositories.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFriendsRepository implements FriendsRepository {
  @override
  Future<void> createFriend(FriendRecord friend) async {}

  @override
  Future<void> deleteFriend(String id) async {}

  @override
  Future<FriendRecord?> getById(String id) async => null;

  @override
  Future<void> updateFriend(FriendRecord friend) async {}

  @override
  Stream<List<FriendRecord>> watchAll() => Stream.value(const []);
}

class _ZeroingSharingService extends SharingService {
  _ZeroingSharingService(AppDatabase db)
    : super(
        handle: const _FakePrismSyncHandle(),
        settingsRepository: FakeSystemSettingsRepository(),
        friendsRepository: _FakeFriendsRepository(),
        sharingRequestsDao: db.sharingRequestsDao,
      );

  List<int>? syncPinBytes;

  @override
  Future<int> changePassword({
    required Uint8List newPassword,
    required List<int> secretKey,
    required AppDatabase db,
  }) async {
    syncPinBytes = List<int>.from(newPassword);
    newPassword.fillRange(0, newPassword.length, 0);
    return 1;
  }
}

class _RecordingPinLockService extends PinLockService {
  List<int>? storedPinBytes;

  @override
  Future<void> storePinBytes(List<int> pinBytes) async {
    storedPinBytes = List<int>.from(pinBytes);
  }
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
    child: _sheetHost(),
  );
}

Widget _buildSheetWithServices({
  required AppDatabase db,
  required SharingService sharingService,
  required PinLockService pinLockService,
}) {
  return ProviderScope(
    overrides: [
      prismSyncHandleProvider.overrideWithBuild(
        (ref, notifier) => const _FakePrismSyncHandle(),
      ),
      databaseProvider.overrideWithValue(db),
      sharingServiceProvider.overrideWithValue(sharingService),
      pinLockServiceProvider.overrideWithValue(pinLockService),
    ],
    child: _sheetHost(),
  );
}

Widget _sheetHost() {
  return const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ChangePinSheet()),
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

  testWidgets('stores original new PIN for app lock after sync change', (
    tester,
  ) async {
    _useTallViewport(tester);
    _installFfiOverrides(unlockSucceeds: true);
    final db = AppDatabase(NativeDatabase.memory());
    final sharingService = _ZeroingSharingService(db);
    final pinLockService = _RecordingPinLockService();
    addTearDown(db.close);

    await tester.pumpWidget(
      _buildSheetWithServices(
        db: db,
        sharingService: sharingService,
        pinLockService: pinLockService,
      ),
    );
    await tester.pumpAndSettle();
    await _advancePastMnemonicStep(tester);
    await _tapPin(tester, '123456');

    await tester.tap(find.widgetWithText(PrismButton, 'Change PIN'));
    await tester.pumpAndSettle();
    await _tapPin(tester, '222222');
    await _tapPin(tester, '222222');

    expect(sharingService.syncPinBytes, utf8.encode('222222'));
    expect(pinLockService.storedPinBytes, utf8.encode('222222'));
  });
}
