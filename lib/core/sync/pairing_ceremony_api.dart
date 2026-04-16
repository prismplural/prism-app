import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

abstract class PairingCeremonyApi {
  const PairingCeremonyApi();

  /// Validates a BIP39 mnemonic by attempting to convert it into the
  /// underlying entropy bytes. Returns normally if valid, throws otherwise.
  ///
  /// Extracted onto the ceremony API so that UI flows (which need to
  /// validate user-typed recovery phrases before the pairing handshake)
  /// can be tested without initializing the FFI library.
  Future<void> validateMnemonic(String mnemonic);

  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle});

  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle});

  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
  });

  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  });

  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
    required String mnemonic,
  });
}

class FrbPairingCeremonyApi extends PairingCeremonyApi {
  const FrbPairingCeremonyApi();

  @override
  Future<void> validateMnemonic(String mnemonic) async {
    final bytes = await ffi.mnemonicToBytes(mnemonic: mnemonic);
    // Zero immediately — we only needed the call to confirm the phrase
    // parses. The real derivation happens later via ffi.unlock.
    bytes.fillRange(0, bytes.length, 0);
  }

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) {
    return ffi.startJoinerCeremony(handle: handle);
  }

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) {
    return ffi.getJoinerSas(handle: handle);
  }

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
  }) {
    return ffi.completeJoinerCeremony(handle: handle, password: password);
  }

  @override
  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  }) {
    return ffi.startInitiatorCeremony(handle: handle, tokenBytes: tokenBytes);
  }

  @override
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
    required String mnemonic,
  }) {
    return ffi.completeInitiatorCeremony(
      handle: handle,
      password: password,
      mnemonic: mnemonic,
    );
  }
}

final pairingCeremonyApiProvider = Provider<PairingCeremonyApi>(
  (ref) => const FrbPairingCeremonyApi(),
);
