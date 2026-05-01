import 'dart:typed_data';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// Narrow app-side wrapper around sharing FFI entrypoints.
///
/// The app threads `identityGeneration` through this boundary now so the
/// lifecycle is explicit at call sites.
abstract class SharingSyncApi {
  const SharingSyncApi();

  Future<String> sharingEnable({
    required ffi.PrismSyncHandle handle,
    String? currentSharingId,
    required int identityGeneration,
  });

  Future<void> sharingDisable({
    required ffi.PrismSyncHandle handle,
    required String sharingId,
  });

  Future<void> sharingEnsurePrekey({
    required ffi.PrismSyncHandle handle,
    required String sharingId,
    required int identityGeneration,
  });

  Future<String> sharingInitiate({
    required ffi.PrismSyncHandle handle,
    required String senderSharingId,
    required String recipientSharingId,
    required String displayName,
    required String offeredScopes,
    required int identityGeneration,
  });

  Future<String> sharingProcessPending({
    required ffi.PrismSyncHandle handle,
    required String recipientSharingId,
    required String existingRelationshipsJson,
    required String seenInitIdsJson,
    required int identityGeneration,
  });

  Future<int> changePassword({
    required ffi.PrismSyncHandle handle,
    required Uint8List newPassword,
    required List<int> secretKey,
    String? sharingId,
    required int currentIdentityGeneration,
  });

  Future<void> persistPasswordChangeState({
    required ffi.PrismSyncHandle handle,
    required AppDatabase db,
  });

  Future<void> persistState({required ffi.PrismSyncHandle handle});
}

class PrismSyncSharingApi extends SharingSyncApi {
  const PrismSyncSharingApi();

  @override
  Future<String> sharingEnable({
    required ffi.PrismSyncHandle handle,
    String? currentSharingId,
    required int identityGeneration,
  }) => ffi.sharingEnable(
    handle: handle,
    currentSharingId: currentSharingId,
    identityGeneration: identityGeneration,
  );

  @override
  Future<void> sharingDisable({
    required ffi.PrismSyncHandle handle,
    required String sharingId,
  }) => ffi.sharingDisable(handle: handle, sharingId: sharingId);

  @override
  Future<void> sharingEnsurePrekey({
    required ffi.PrismSyncHandle handle,
    required String sharingId,
    required int identityGeneration,
  }) => ffi.sharingEnsurePrekey(
    handle: handle,
    sharingId: sharingId,
    identityGeneration: identityGeneration,
  );

  @override
  Future<String> sharingInitiate({
    required ffi.PrismSyncHandle handle,
    required String senderSharingId,
    required String recipientSharingId,
    required String displayName,
    required String offeredScopes,
    required int identityGeneration,
  }) => ffi.sharingInitiate(
    handle: handle,
    senderSharingId: senderSharingId,
    identityGeneration: identityGeneration,
    recipientSharingId: recipientSharingId,
    displayName: displayName,
    offeredScopes: offeredScopes,
  );

  @override
  Future<String> sharingProcessPending({
    required ffi.PrismSyncHandle handle,
    required String recipientSharingId,
    required String existingRelationshipsJson,
    required String seenInitIdsJson,
    required int identityGeneration,
  }) => ffi.sharingProcessPending(
    handle: handle,
    recipientSharingId: recipientSharingId,
    identityGeneration: identityGeneration,
    existingRelationshipsJson: existingRelationshipsJson,
    seenInitIdsJson: seenInitIdsJson,
  );

  @override
  Future<int> changePassword({
    required ffi.PrismSyncHandle handle,
    required Uint8List newPassword,
    required List<int> secretKey,
    String? sharingId,
    required int currentIdentityGeneration,
  }) async {
    try {
      final nextGeneration = await ffi.changePassword(
        handle: handle,
        newPassword: newPassword,
        secretKey: secretKey,
        sharingId: sharingId,
        currentIdentityGeneration: currentIdentityGeneration,
      );
      return nextGeneration;
    } finally {
      newPassword.fillRange(0, newPassword.length, 0);
    }
  }

  @override
  Future<void> persistPasswordChangeState({
    required ffi.PrismSyncHandle handle,
    required AppDatabase db,
  }) async {
    await cacheRuntimeKeys(handle, db);
    await drainRustStore(handle);
  }

  @override
  Future<void> persistState({required ffi.PrismSyncHandle handle}) =>
      drainRustStore(handle);
}
