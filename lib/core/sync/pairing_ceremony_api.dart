import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

abstract class PairingCeremonyApi {
  const PairingCeremonyApi();

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
  });
}

class FrbPairingCeremonyApi extends PairingCeremonyApi {
  const FrbPairingCeremonyApi();

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
  }) {
    return ffi.completeInitiatorCeremony(handle: handle, password: password);
  }
}

final pairingCeremonyApiProvider = Provider<PairingCeremonyApi>(
  (ref) => const FrbPairingCeremonyApi(),
);
