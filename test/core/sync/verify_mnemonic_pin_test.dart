// Note: this file covers wrapper-level Riverpod state invariance.
// The cryptographic no-side-effects invariant on the Rust engine is
// enforced by prism-sync/crates/prism-sync-core/tests/verify_credentials.rs
// (DEK export bytes unchanged pre/post). Don't remove either.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake implementation of [SyncVerifyMnemonicPinFns] with stub behaviours
/// controlled by constructor arguments. The real [SyncHealthNotifier] body
/// calls through this interface during tests.
class _FakeVerifyFns implements SyncVerifyMnemonicPinFns {
  _FakeVerifyFns({
    Future<List<int>> Function(Uint8List mnemonic)? mnemonicToBytes,
    Future<bool> Function({
      required ffi.PrismSyncHandle handle,
      required Uint8List password,
      required List<int> secretKey,
    })? verifyMnemonicPin,
  })  : _mnemonicToBytes =
            mnemonicToBytes ?? ((_) async => List<int>.filled(16, 0)),
        _verifyMnemonicPin = verifyMnemonicPin ??
            (({required handle, required password, required secretKey}) async =>
                true);

  final Future<List<int>> Function(Uint8List mnemonic) _mnemonicToBytes;
  final Future<bool> Function({
    required ffi.PrismSyncHandle handle,
    required Uint8List password,
    required List<int> secretKey,
  }) _verifyMnemonicPin;

  @override
  Future<List<int>> mnemonicToBytes(Uint8List mnemonic) =>
      _mnemonicToBytes(mnemonic);

  @override
  Future<bool> verifyMnemonicPin({
    required ffi.PrismSyncHandle handle,
    required Uint8List password,
    required List<int> secretKey,
  }) =>
      _verifyMnemonicPin(
        handle: handle,
        password: password,
        secretKey: secretKey,
      );
}

/// A handle notifier that resolves synchronously. This ensures
/// `ref.read(prismSyncHandleProvider).value` returns the handle immediately
/// (not AsyncLoading) when verifyMnemonicPin reads it.
class _SyncHandleNotifier extends PrismSyncHandleNotifier {
  _SyncHandleNotifier(this._handle);
  final ffi.PrismSyncHandle? _handle;

  @override
  Future<ffi.PrismSyncHandle?> build() async {
    // Set state synchronously before the first await so callers that use
    // `ref.read(...).value` see the data value immediately.
    state = AsyncValue.data(_handle);
    return _handle;
  }

  @override
  Future<ffi.PrismSyncHandle> createHandle({required String relayUrl}) =>
      throw UnimplementedError();
}

/// Builds a [ProviderContainer] wired with the given overrides and injects
/// [fakeVerifyFns] into the real [SyncHealthNotifier] so the production method
/// body runs under test without requiring a linked Rust dylib.
ProviderContainer _buildContainer({
  ffi.PrismSyncHandle? handle,
  bool wrappedDekPresent = true,
  required _FakeVerifyFns fakeVerifyFns,
  SyncHealthState initialState = SyncHealthState.healthy,
}) {
  final container = ProviderContainer(
    overrides: [
      prismSyncHandleProvider.overrideWith(
        () => _SyncHandleNotifier(handle),
      ),
      syncWrappedDekPresentProvider.overrideWithValue(
        AsyncValue.data(wrappedDekPresent),
      ),
    ],
  );
  // Trigger provider initialisation so the notifier exists, then inject the
  // fake seam. The real production method body will call through verifyFns.
  final notifier = container.read(syncHealthProvider.notifier);
  if (initialState != SyncHealthState.healthy) {
    notifier.setState(initialState);
  }
  notifier.verifyFns = fakeVerifyFns;
  return container;
}

PinBuffer _makePin(String digits) {
  final buf = PinBuffer(length: 6);
  for (final ch in digits.split('')) {
    buf.appendDigit(ch);
  }
  return buf;
}

const _fakeHandle = _FakePrismSyncHandle();
const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

void main() {
  test('returns HandleUnavailable when handle is null', () async {
    final fakeVerifyFns = _FakeVerifyFns();
    final container = _buildContainer(
      handle: null,
      fakeVerifyFns: fakeVerifyFns,
    );
    addTearDown(container.dispose);

    final stateBefore = container.read(syncHealthProvider);
    final result = await container
        .read(syncHealthProvider.notifier)
        .verifyMnemonicPin(pin: _makePin('123456'), mnemonic: _validMnemonic);
    final stateAfter = container.read(syncHealthProvider);

    expect(result, isA<VerifyMnemonicPinHandleUnavailable>());
    expect(stateAfter, equals(stateBefore), reason: 'state must not change');
  });

  test('returns NeedsRewrap when wrapped_dek is absent', () async {
    final fakeVerifyFns = _FakeVerifyFns();
    final container = _buildContainer(
      handle: _fakeHandle,
      wrappedDekPresent: false,
      fakeVerifyFns: fakeVerifyFns,
    );
    addTearDown(container.dispose);

    final stateBefore = container.read(syncHealthProvider);
    final result = await container
        .read(syncHealthProvider.notifier)
        .verifyMnemonicPin(pin: _makePin('123456'), mnemonic: _validMnemonic);
    final stateAfter = container.read(syncHealthProvider);

    expect(result, isA<VerifyMnemonicPinNeedsRewrap>());
    expect(stateAfter, equals(stateBefore), reason: 'state must not change');
  });

  test('returns Match when FFI confirms credentials', () async {
    bool verifyCalled = false;
    final fakeVerifyFns = _FakeVerifyFns(
      verifyMnemonicPin: ({required handle, required password, required secretKey}) async {
        verifyCalled = true;
        expect(handle, same(_fakeHandle));
        expect(password, isNotEmpty);
        expect(secretKey, isNotEmpty);
        return true;
      },
    );
    final container = _buildContainer(
      handle: _fakeHandle,
      fakeVerifyFns: fakeVerifyFns,
    );
    addTearDown(container.dispose);

    final stateBefore = container.read(syncHealthProvider);
    final result = await container
        .read(syncHealthProvider.notifier)
        .verifyMnemonicPin(pin: _makePin('123456'), mnemonic: _validMnemonic);
    final stateAfter = container.read(syncHealthProvider);

    expect(result, isA<VerifyMnemonicPinMatch>());
    expect(verifyCalled, isTrue);
    expect(stateAfter, equals(stateBefore), reason: 'state must not change');
  });

  test('returns NoMatch when FFI rejects credentials', () async {
    final fakeVerifyFns = _FakeVerifyFns(
      verifyMnemonicPin:
          ({required handle, required password, required secretKey}) async =>
              false,
    );
    final container = _buildContainer(
      handle: _fakeHandle,
      fakeVerifyFns: fakeVerifyFns,
    );
    addTearDown(container.dispose);

    final stateBefore = container.read(syncHealthProvider);
    final result = await container
        .read(syncHealthProvider.notifier)
        .verifyMnemonicPin(pin: _makePin('654321'), mnemonic: _validMnemonic);
    final stateAfter = container.read(syncHealthProvider);

    expect(result, isA<VerifyMnemonicPinNoMatch>());
    expect(stateAfter, equals(stateBefore), reason: 'state must not change');
  });

  test('returns Error when FFI throws Exception (infrastructure failure, not wrong cred)', () async {
    final fakeVerifyFns = _FakeVerifyFns(
      verifyMnemonicPin:
          ({required handle, required password, required secretKey}) async =>
              throw Exception('simulated Rust error'),
    );
    final container = _buildContainer(
      handle: _fakeHandle,
      fakeVerifyFns: fakeVerifyFns,
    );
    addTearDown(container.dispose);

    final stateBefore = container.read(syncHealthProvider);
    final result = await container
        .read(syncHealthProvider.notifier)
        .verifyMnemonicPin(pin: _makePin('123456'), mnemonic: _validMnemonic);
    final stateAfter = container.read(syncHealthProvider);

    expect(result, isA<VerifyMnemonicPinError>(),
        reason: 'FFI throws should return Error not NoMatch to prevent false lockout');
    expect(stateAfter, equals(stateBefore), reason: 'state must not change');
  });

  test('returns NoMatch when mnemonicToBytes throws (bad mnemonic)', () async {
    bool verifyPinCalled = false;
    final fakeVerifyFns = _FakeVerifyFns(
      mnemonicToBytes: (_) async => throw Exception('invalid BIP39'),
      verifyMnemonicPin: ({required handle, required password, required secretKey}) async {
        verifyPinCalled = true;
        return true;
      },
    );
    final container = _buildContainer(
      handle: _fakeHandle,
      fakeVerifyFns: fakeVerifyFns,
    );
    addTearDown(container.dispose);

    final stateBefore = container.read(syncHealthProvider);
    final result = await container
        .read(syncHealthProvider.notifier)
        .verifyMnemonicPin(
          pin: _makePin('123456'),
          mnemonic: 'not valid bip39 words at all invalid',
        );
    final stateAfter = container.read(syncHealthProvider);

    expect(result, isA<VerifyMnemonicPinNoMatch>());
    expect(
      verifyPinCalled,
      isFalse,
      reason: 'FFI verify must not be called after bad mnemonic',
    );
    expect(stateAfter, equals(stateBefore), reason: 'state must not change');
  });

  group('state is never mutated across all result branches', () {
    void runCase(
      String label, {
      ffi.PrismSyncHandle? handle = _fakeHandle,
      bool wrappedDekPresent = true,
      bool mnemonicThrows = false,
      bool ffiThrows = false,
      bool ffiReturnsTrue = true,
    }) {
      test(label, () async {
        final fakeVerifyFns = _FakeVerifyFns(
          mnemonicToBytes: mnemonicThrows
              ? (_) async => throw Exception('bad mnemonic')
              : (_) async => List<int>.filled(16, 0),
          verifyMnemonicPin: ffiThrows
              ? ({required handle, required password, required secretKey}) async =>
                    throw Exception('ffi error')
              : ({required handle, required password, required secretKey}) async =>
                    ffiReturnsTrue,
        );

        final container = _buildContainer(
          handle: handle,
          wrappedDekPresent: wrappedDekPresent,
          fakeVerifyFns: fakeVerifyFns,
          initialState: SyncHealthState.healthy,
        );
        addTearDown(container.dispose);

        expect(
          container.read(syncHealthProvider),
          SyncHealthState.healthy,
          reason: 'precondition: starts healthy',
        );

        await container
            .read(syncHealthProvider.notifier)
            .verifyMnemonicPin(
              pin: _makePin('123456'),
              mnemonic: _validMnemonic,
            );

        expect(
          container.read(syncHealthProvider),
          SyncHealthState.healthy,
          reason: '$label — state must remain healthy after verifyMnemonicPin',
        );
      });
    }

    runCase('handle null → HandleUnavailable', handle: null);
    runCase(
      'no wrapped_dek → NeedsRewrap',
      wrappedDekPresent: false,
    );
    runCase('ffi true → Match', ffiReturnsTrue: true);
    runCase('ffi false → NoMatch', ffiReturnsTrue: false);
    runCase('ffi throws → Error (infra failure)', ffiThrows: true);
    runCase('mnemonic throws → NoMatch', mnemonicThrows: true);
  });
}
