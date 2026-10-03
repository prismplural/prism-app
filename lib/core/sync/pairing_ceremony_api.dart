import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

abstract class PairingCeremonyApi {
  const PairingCeremonyApi();

  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle});

  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle});

  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle});

  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
  });

  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  });

  /// Pre-split, single-call initiator completion.
  ///
  /// The app's initiator flow now uses the split ceremony
  /// ([verifyInitiatorConfirmationResumable] →
  /// [uploadPairingSnapshotResumable] → [completeInitiatorResumableCeremony]).
  /// This remains the direct-FFI entry point for tooling and e2e fixtures.
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  });

  /// Step 1 of the split initiator ceremony: wait for the joiner's protected
  /// confirmation, verify it, and retain the ceremony (plus its pairing lease)
  /// for the upload and credential-release halves.
  ///
  /// Returns whether the ceremony negotiated the opaque pairing lease. No
  /// credentials are released here — that needs
  /// [completeInitiatorResumableCeremony], which core refuses until the
  /// snapshot is durably published.
  ///
  /// Never wrap this in a Dart deadline: core owns the wait (a lease-aware
  /// ceremony can run to its four-hour cap), and any shorter wrapper would
  /// preempt it.
  Future<bool> verifyInitiatorConfirmationResumable({
    required ffi.PrismSyncHandle handle,
  });

  /// Step 2: produce and upload the pair-time snapshot for a verified ceremony.
  ///
  /// Progress is reported through the app's existing sync event stream
  /// (`SnapshotUploadProgress`), not through this future, so callers surface
  /// progress from the same place they already poll events.
  ///
  /// Core owns the transport and the downgrade: a relay without the chunked
  /// routes (or without a usable capability) falls back to the unchanged single
  /// `PUT` and reports it via
  /// [ffi.ResumableSnapshotUploadResult.transport]. Callers must not guess the
  /// protocol from the result.
  ///
  /// Never wrap this in a Dart deadline: the legacy single-`PUT` budget runs to
  /// 300s and a lease-aware transfer can run far longer.
  Future<ffi.ResumableSnapshotUploadResult> uploadPairingSnapshotResumable({
    required ffi.PrismSyncHandle handle,
    BigInt? ttlSecs,
  });

  /// Step 3, and the only credential-release path for the split ceremony.
  ///
  /// Core refuses unless step 2 published the snapshot durably, so callers must
  /// not issue this after a cancelled or failed upload.
  ///
  /// Never wrap this in a Dart deadline: the wait for the joiner's terminal
  /// bundle is core-owned and can run to the four-hour cap.
  Future<ffi.ResumableCeremonyCompletion> completeInitiatorResumableCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  });

  /// Resumable snapshot capability as this device sees it.
  ///
  /// UX only. Core decides the transport and falls back on its own, so this
  /// never changes which call the app makes.
  Future<ffi.SnapshotUploadCapabilityInfo> snapshotUploadCapability({
    required ffi.PrismSyncHandle handle,
  });
}

class FrbPairingCeremonyApi extends PairingCeremonyApi {
  const FrbPairingCeremonyApi();

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) {
    return ffi.startJoinerCeremony(handle: handle);
  }

  @override
  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle}) {
    return ffi.cancelPairingCeremony(handle: handle);
  }

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) {
    return ffi.getJoinerSas(handle: handle);
  }

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
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
    required List<int> password,
    required List<int> mnemonic,
  }) {
    return ffi.completeInitiatorCeremony(
      handle: handle,
      password: password,
      mnemonic: mnemonic,
    );
  }

  @override
  Future<bool> verifyInitiatorConfirmationResumable({
    required ffi.PrismSyncHandle handle,
  }) {
    return ffi.verifyInitiatorConfirmationResumable(handle: handle);
  }

  @override
  Future<ffi.ResumableSnapshotUploadResult> uploadPairingSnapshotResumable({
    required ffi.PrismSyncHandle handle,
    BigInt? ttlSecs,
  }) {
    return ffi.uploadPairingSnapshotResumable(
      handle: handle,
      ttlSecs: ttlSecs,
    );
  }

  @override
  Future<ffi.ResumableCeremonyCompletion> completeInitiatorResumableCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) {
    return ffi.completeInitiatorResumableCeremony(
      handle: handle,
      password: password,
      mnemonic: mnemonic,
    );
  }

  @override
  Future<ffi.SnapshotUploadCapabilityInfo> snapshotUploadCapability({
    required ffi.PrismSyncHandle handle,
  }) {
    return ffi.snapshotUploadCapability(handle: handle);
  }
}

final pairingCeremonyApiProvider = Provider<PairingCeremonyApi>(
  (ref) => const FrbPairingCeremonyApi(),
);
