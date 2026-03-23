import 'dart:typed_data';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';

/// Service for friend management, invite creation, ECDH key agreement,
/// SAS verification, and scope-based resource key wrapping.
///
/// Uses Rust FFI crypto primitives via [ffi.PrismSyncHandle].
class SharingService {
  SharingService({required ffi.PrismSyncHandle handle}) : _handle = handle;

  final ffi.PrismSyncHandle _handle;
  static const _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // Invite creation
  // ---------------------------------------------------------------------------

  /// Generate an invite containing our X25519 public key.
  ///
  /// The invite is valid for 24 hours.
  Future<ShareInvite> createInvite(String displayName) async {
    final pubKeyBytes = await ffi.getIdentityPublicKey(handle: _handle);
    final pubKeyHex = await ffi.hexEncode(bytes: pubKeyBytes);
    final now = DateTime.now();

    return ShareInvite(
      linkId: generateLinkId(),
      publicKeyHex: pubKeyHex,
      displayName: displayName,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
  }

  // ---------------------------------------------------------------------------
  // Invite acceptance + ECDH
  // ---------------------------------------------------------------------------

  /// Accept an invite by performing X25519 ECDH key agreement.
  Future<(Friend friend, String sasCode)> acceptInvite(
    ShareInvite invite,
  ) async {
    final peerPubKeyBytes = await ffi.hexDecode(hexStr: invite.publicKeyHex);
    final sharedSecret = await ffi.performEcdh(
      handle: _handle,
      peerPublicKey: peerPubKeyBytes,
    );
    final sharedSecretHex = await ffi.hexEncode(bytes: sharedSecret);
    final sasCode = generateSasCode(sharedSecret);

    final friend = Friend(
      id: _uuid.v4(),
      displayName: invite.displayName,
      publicKeyHex: invite.publicKeyHex,
      grantedScopes: const [],
      addedAt: DateTime.now(),
      sharedSecretHex: sharedSecretHex,
    );

    return (friend, sasCode);
  }

  // ---------------------------------------------------------------------------
  // SAS verification
  // ---------------------------------------------------------------------------

  /// Generate a 6-digit SAS verification code from a shared secret.
  String generateSasCode(Uint8List sharedSecret) {
    final bytes = sharedSecret.sublist(0, 3);
    final number = (bytes[0] << 16 | bytes[1] << 8 | bytes[2]) % 1000000;
    return number.toString().padLeft(6, '0');
  }

  /// Compute the SAS code for an existing friend (from stored shared secret).
  Future<String> getSasCodeForFriend(Friend friend) async {
    if (friend.sharedSecretHex == null) {
      throw SharingException('No shared secret for friend ${friend.id}');
    }
    final secretBytes = await ffi.hexDecode(hexStr: friend.sharedSecretHex!);
    return generateSasCode(secretBytes);
  }

  // ---------------------------------------------------------------------------
  // Resource key wrapping (per-scope encryption)
  // ---------------------------------------------------------------------------

  /// Wrap per-scope resource keys with a friend's shared secret.
  Future<Map<ShareScope, Uint8List>> wrapResourceKeys(
    Friend friend,
    Map<ShareScope, Uint8List> resourceKeys,
  ) async {
    if (friend.sharedSecretHex == null) {
      throw SharingException('No shared secret for friend ${friend.id}');
    }
    final secretBytes = await ffi.hexDecode(hexStr: friend.sharedSecretHex!);
    final wrapped = <ShareScope, Uint8List>{};
    for (final entry in resourceKeys.entries) {
      wrapped[entry.key] = await ffi.encryptXchacha(
        key: secretBytes,
        plaintext: entry.value,
      );
    }
    return wrapped;
  }

  /// Unwrap resource keys received from a friend.
  Future<Map<ShareScope, Uint8List>> unwrapResourceKeys(
    Friend friend,
    Map<ShareScope, Uint8List> wrappedKeys,
  ) async {
    if (friend.sharedSecretHex == null) {
      throw SharingException('No shared secret for friend ${friend.id}');
    }
    final secretBytes = await ffi.hexDecode(hexStr: friend.sharedSecretHex!);
    final unwrapped = <ShareScope, Uint8List>{};
    for (final entry in wrappedKeys.entries) {
      unwrapped[entry.key] = await ffi.decryptXchacha(
        key: secretBytes,
        ciphertext: entry.value,
      );
    }
    return unwrapped;
  }

  // ---------------------------------------------------------------------------
  // Revocation
  // ---------------------------------------------------------------------------

  /// Revoke a friend's access by rotating resource keys.
  Future<RevocationResult> revokeFriend(
    String friendId,
    List<Friend> allFriends,
    Map<ShareScope, Uint8List> currentResourceKeys,
  ) async {
    // Generate new random resource keys for each scope.
    final newResourceKeys = <ShareScope, Uint8List>{};
    for (final scope in currentResourceKeys.keys) {
      newResourceKeys[scope] = await ffi.randomBytes(len: 32);
    }

    // Re-wrap the new keys for every remaining friend.
    final remainingFriends =
        allFriends.where((f) => f.id != friendId).toList();
    final rewrappedPerFriend = <String, Map<ShareScope, Uint8List>>{};
    for (final friend in remainingFriends) {
      // Only wrap scopes this friend is granted.
      final friendKeys = <ShareScope, Uint8List>{};
      for (final scope in friend.grantedScopes) {
        if (newResourceKeys.containsKey(scope)) {
          friendKeys[scope] = newResourceKeys[scope]!;
        }
      }
      if (friendKeys.isNotEmpty) {
        rewrappedPerFriend[friend.id] =
            await wrapResourceKeys(friend, friendKeys);
      }
    }

    return RevocationResult(
      newResourceKeys: newResourceKeys,
      rewrappedKeysPerFriend: rewrappedPerFriend,
    );
  }

  /// Update granted scopes for a friend and re-wrap resource keys.
  Future<Map<ShareScope, Uint8List>> updateScopes(
    Friend friend,
    List<ShareScope> newScopes,
    Map<ShareScope, Uint8List> resourceKeys,
  ) async {
    final scopeKeys = <ShareScope, Uint8List>{};
    for (final scope in newScopes) {
      if (resourceKeys.containsKey(scope)) {
        scopeKeys[scope] = resourceKeys[scope]!;
      }
    }
    return wrapResourceKeys(friend, scopeKeys);
  }

  /// Generate a new unique invite link ID.
  String generateLinkId() => _uuid.v4().replaceAll('-', '');
}

/// Result of revoking a friend's access.
class RevocationResult {
  final Map<ShareScope, Uint8List> newResourceKeys;
  final Map<String, Map<ShareScope, Uint8List>> rewrappedKeysPerFriend;

  const RevocationResult({
    required this.newResourceKeys,
    required this.rewrappedKeysPerFriend,
  });
}

/// Exception thrown when sharing operations fail.
class SharingException implements Exception {
  final String message;

  SharingException(this.message);

  @override
  String toString() => 'SharingException: $message';
}
