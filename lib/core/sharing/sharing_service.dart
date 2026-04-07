import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/sharing_requests_dao.dart';
import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/pending_sharing_request.dart';
import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/friend_record.dart';
import 'package:prism_plurality/domain/repositories/friends_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';

/// App-side coordinator for the Phase 4 sharing flow.
///
/// Rust owns the cryptographic ceremony, relay I/O, and secure-store prekeys.
/// The app owns synced sharing state, friend rows, and local pending-review
/// records for mailbox items that still need a user decision.
class SharingService {
  SharingService({
    required ffi.PrismSyncHandle handle,
    required SystemSettingsRepository settingsRepository,
    required FriendsRepository friendsRepository,
    required SharingRequestsDao sharingRequestsDao,
  }) : _handle = handle,
       _settingsRepository = settingsRepository,
       _friendsRepository = friendsRepository,
       _sharingRequestsDao = sharingRequestsDao;

  final ffi.PrismSyncHandle _handle;
  final SystemSettingsRepository _settingsRepository;
  final FriendsRepository _friendsRepository;
  final SharingRequestsDao _sharingRequestsDao;

  Future<ShareInvite> createInvite({String? displayName}) async {
    final sharingId = await _ensureSharingReady();
    return ShareInvite(
      sharingId: sharingId,
      displayName: _cleanOptionalText(displayName),
      createdAt: DateTime.now(),
    );
  }

  Future<void> disableSharing() async {
    final settings = await _settingsRepository.getSettings();
    final sharingId = settings.sharingId;
    if (sharingId == null || sharingId.isEmpty) {
      return;
    }

    await ffi.sharingDisable(handle: _handle, sharingId: sharingId);
    await _settingsRepository.updateSharingId(null);
    await drainRustStore(_handle);
  }

  Future<Friend> initiateFromInvite(
    ShareInvite invite, {
    required String displayName,
    required List<ShareScope> offeredScopes,
  }) async {
    final senderSharingId = await _ensureSharingReady();
    final normalizedDisplayName = displayName.trim();
    if (normalizedDisplayName.isEmpty) {
      throw SharingException('Display name is required');
    }
    if (offeredScopes.isEmpty) {
      throw SharingException('Select at least one scope to share');
    }

    final responseJson = await ffi.sharingInitiate(
      handle: _handle,
      senderSharingId: senderSharingId,
      recipientSharingId: invite.sharingId,
      displayName: normalizedDisplayName,
      offeredScopes: jsonEncode(
        offeredScopes.map((scope) => scope.name).toList(),
      ),
    );
    final response = _asMap(
      jsonDecode(responseJson),
      context: 'sharing_initiate response',
    );
    final initId = _asString(response['init_id'], field: 'init_id');
    final pairwiseSecretB64 = _asString(
      response['pairwise_secret_b64'],
      field: 'pairwise_secret_b64',
    );
    final pairwiseSecretHex = _asString(
      response['pairwise_secret_hex'],
      field: 'pairwise_secret_hex',
    );
    final recipientIdentityB64 = _asString(
      response['recipient_identity_b64'],
      field: 'recipient_identity_b64',
    );
    final recipientIdentityHex = _asString(
      response['recipient_identity_hex'],
      field: 'recipient_identity_hex',
    );

    final pairwiseSecret = base64Decode(pairwiseSecretB64);
    final recipientIdentity = base64Decode(recipientIdentityB64);
    final existing = await _findFriendByPeerSharingId(invite.sharingId);
    final now = DateTime.now();
    final friendRecord = FriendRecord(
      id: existing?.id ?? invite.sharingId,
      displayName:
          _cleanOptionalText(invite.displayName) ??
          existing?.displayName ??
          invite.sharingId,
      peerSharingId: invite.sharingId,
      pairwiseSecret: pairwiseSecret,
      pinnedIdentity: recipientIdentity,
      offeredScopes: existing?.offeredScopes ?? const [],
      publicKeyHex: recipientIdentityHex,
      sharedSecretHex: pairwiseSecretHex,
      grantedScopes: offeredScopes.map((scope) => scope.name).toList(),
      isVerified: existing?.isVerified ?? false,
      initId: initId,
      createdAt: existing?.createdAt ?? now,
      establishedAt: now,
      lastSyncAt: now,
    );
    await _upsertFriend(friendRecord, existing: existing);
    return _recordToFriend(friendRecord);
  }

  Future<SharingInboxRefreshResult> refreshPendingRequests() async {
    final settings = await _settingsRepository.getSettings();
    final sharingId = settings.sharingId;
    if (sharingId == null || sharingId.isEmpty) {
      return const SharingInboxRefreshResult();
    }

    await ffi.sharingEnsurePrekey(handle: _handle, sharingId: sharingId);
    await drainRustStore(_handle);

    final friends = await _friendsRepository.watchAll().first;
    final requests = await _sharingRequestsDao.getAll();
    final existingRelationships = <String>{
      for (final friend in friends)
        if ((friend.peerSharingId ?? '').isNotEmpty) friend.peerSharingId!,
    };
    final pinnedIdentities = <String, String>{
      for (final friend in friends)
        if ((friend.peerSharingId ?? '').isNotEmpty &&
            friend.pinnedIdentity != null)
          friend.peerSharingId!: base64Encode(friend.pinnedIdentity!),
    };
    final verifiedPeers = <String, bool>{
      for (final friend in friends)
        if ((friend.peerSharingId ?? '').isNotEmpty)
          friend.peerSharingId!: friend.isVerified,
    };
    final seenInitIds = <String>{
      for (final friend in friends)
        if ((friend.initId ?? '').isNotEmpty) friend.initId!,
      for (final request in requests) request.initId,
    };

    final existingRelationshipsJson = jsonEncode({
      'existing_relationships': existingRelationships.toList(),
      'pinned_identities': pinnedIdentities,
      'verified_peers': verifiedPeers,
    });
    final resultsJson = await ffi.sharingProcessPending(
      handle: _handle,
      recipientSharingId: sharingId,
      existingRelationshipsJson: existingRelationshipsJson,
      seenInitIdsJson: jsonEncode(seenInitIds.toList()),
    );
    final decoded = jsonDecode(resultsJson);
    if (decoded is! List) {
      throw SharingException('Invalid pending-init response');
    }

    var accepted = 0;
    var warned = 0;
    var blocked = 0;
    var errored = 0;
    final now = DateTime.now();
    for (final item in decoded) {
      final result = _SharingPendingResult.fromJson(item);
      switch (result.status) {
        case PendingSharingTrustDecision.accept:
          {
            accepted += 1;
            final existing = await _findFriendByPeerSharingId(
              result.senderSharingId,
            );
            final friendRecord = FriendRecord(
              id: existing?.id ?? result.senderSharingId,
              displayName:
                  result.displayName ??
                  existing?.displayName ??
                  result.senderSharingId,
              peerSharingId: result.senderSharingId,
              pairwiseSecret: result.pairwiseSecret,
              pinnedIdentity: result.senderIdentity,
              offeredScopes: result.offeredScopes
                  .map((scope) => scope.name)
                  .toList(),
              publicKeyHex:
                  result.senderIdentityHex ?? existing?.publicKeyHex ?? '',
              sharedSecretHex:
                  result.pairwiseSecretHex ?? existing?.sharedSecretHex,
              grantedScopes: existing?.grantedScopes ?? const [],
              isVerified: existing?.isVerified ?? false,
              initId: result.initId,
              createdAt: existing?.createdAt ?? now,
              establishedAt: now,
              lastSyncAt: now,
            );
            await _upsertFriend(friendRecord, existing: existing);
            await _sharingRequestsDao.markResolved(result.initId);
            break;
          }
        case PendingSharingTrustDecision.warnKeyChange:
          {
            warned += 1;
            await _storePendingRequest(result, now);
            break;
          }
        case PendingSharingTrustDecision.blockKeyChange:
          {
            blocked += 1;
            await _storePendingRequest(result, now);
            break;
          }
        case PendingSharingTrustDecision.error:
          {
            errored += 1;
            await _storePendingRequest(result, now);
            break;
          }
      }
    }

    return SharingInboxRefreshResult(
      accepted: accepted,
      warned: warned,
      blocked: blocked,
      errored: errored,
    );
  }

  Future<void> acceptPendingRequest(String initId) async {
    final row = await _sharingRequestsDao.getByInitId(initId);
    if (row == null) {
      throw SharingException('Pending request not found');
    }
    final request = PendingSharingRequest.fromRow(row);
    if (!request.canAccept) {
      throw SharingException('This request cannot be accepted');
    }

    final existing = await _findFriendByPeerSharingId(request.senderSharingId);
    final now = DateTime.now();
    final senderIdentity = request.senderIdentity!;
    final pairwiseSecret = request.pairwiseSecret!;
    final friendRecord = FriendRecord(
      id: existing?.id ?? request.senderSharingId,
      displayName: request.displayName,
      peerSharingId: request.senderSharingId,
      pairwiseSecret: pairwiseSecret,
      pinnedIdentity: senderIdentity,
      offeredScopes: request.offeredScopes.map((scope) => scope.name).toList(),
      publicKeyHex: await ffi.hexEncode(bytes: senderIdentity),
      sharedSecretHex: await ffi.hexEncode(bytes: pairwiseSecret),
      grantedScopes: existing?.grantedScopes ?? const [],
      isVerified: false,
      initId: request.initId,
      createdAt: existing?.createdAt ?? now,
      establishedAt: now,
      lastSyncAt: now,
    );
    await _upsertFriend(friendRecord, existing: existing);
    await _sharingRequestsDao.markResolved(initId);
  }

  Future<void> rejectPendingRequest(String initId) =>
      _sharingRequestsDao.markResolved(initId);

  Future<String> fingerprintForFriend(Friend friend) async {
    final identityBytes = friend.pinnedIdentity;
    if (identityBytes != null) {
      return ffi.sharingFingerprint(
        identityBundleB64: base64Encode(identityBytes),
      );
    }
    return ffi.sharingFingerprint(identityBundleB64: friend.publicKeyHex);
  }

  Future<String> fingerprintForPendingRequest(
    PendingSharingRequest request,
  ) async {
    final identityBytes = request.senderIdentity;
    if (identityBytes == null) {
      throw SharingException('Pending request has no identity bundle');
    }
    return ffi.sharingFingerprint(
      identityBundleB64: base64Encode(identityBytes),
    );
  }

  Future<Map<ShareScope, Uint8List>> wrapResourceKeys(
    Friend friend,
    Map<ShareScope, Uint8List> resourceKeys,
  ) async {
    final pairwiseSecret = await _pairwiseSecretBytes(friend);
    final encodedKeys = <String, String>{
      for (final entry in resourceKeys.entries)
        entry.key.name: base64Encode(entry.value),
    };
    final wrappedJson = await ffi.sharingWrapKeys(
      pairwiseSecretB64: base64Encode(pairwiseSecret),
      scopeKeys: jsonEncode(encodedKeys),
    );
    final wrapped = _asMap(
      jsonDecode(wrappedJson),
      context: 'sharing_wrap_keys response',
    );
    final wrappedKeys = _asMap(
      wrapped['wrapped_keys'],
      context: 'wrapped_keys',
    );
    return {
      for (final entry in wrappedKeys.entries)
        _parseScope(entry.key): base64Decode(
          _asString(entry.value, field: entry.key),
        ),
    };
  }

  Future<Map<ShareScope, Uint8List>> unwrapResourceKeys(
    Friend friend,
    Map<ShareScope, Uint8List> wrappedKeys,
  ) async {
    final pairwiseSecret = await _pairwiseSecretBytes(friend);
    final encodedKeys = <String, String>{
      for (final entry in wrappedKeys.entries)
        entry.key.name: base64Encode(entry.value),
    };
    final unwrappedJson = await ffi.sharingUnwrapKeys(
      pairwiseSecretB64: base64Encode(pairwiseSecret),
      wrappedKeys: jsonEncode(encodedKeys),
    );
    final unwrapped = _asMap(
      jsonDecode(unwrappedJson),
      context: 'sharing_unwrap_keys response',
    );
    final unwrappedKeys = _asMap(
      unwrapped['unwrapped_keys'],
      context: 'unwrapped_keys',
    );
    return {
      for (final entry in unwrappedKeys.entries)
        _parseScope(entry.key): base64Decode(
          _asString(entry.value, field: entry.key),
        ),
    };
  }

  Future<RevocationResult> revokeFriend(
    String friendId,
    List<Friend> allFriends,
    Map<ShareScope, Uint8List> currentResourceKeys,
  ) async {
    final newResourceKeys = <ShareScope, Uint8List>{};
    for (final scope in currentResourceKeys.keys) {
      newResourceKeys[scope] = await ffi.randomBytes(len: 32);
    }

    final remainingFriends = allFriends.where((f) => f.id != friendId).toList();
    final rewrappedPerFriend = <String, Map<ShareScope, Uint8List>>{};
    for (final friend in remainingFriends) {
      final friendKeys = <ShareScope, Uint8List>{};
      for (final scope in friend.grantedScopes) {
        final resourceKey = newResourceKeys[scope];
        if (resourceKey != null) {
          friendKeys[scope] = resourceKey;
        }
      }
      if (friendKeys.isNotEmpty) {
        rewrappedPerFriend[friend.id] = await wrapResourceKeys(
          friend,
          friendKeys,
        );
      }
    }

    return RevocationResult(
      newResourceKeys: newResourceKeys,
      rewrappedKeysPerFriend: rewrappedPerFriend,
    );
  }

  Future<Map<ShareScope, Uint8List>> updateScopes(
    Friend friend,
    List<ShareScope> newScopes,
    Map<ShareScope, Uint8List> resourceKeys,
  ) async {
    final scopeKeys = <ShareScope, Uint8List>{};
    for (final scope in newScopes) {
      final key = resourceKeys[scope];
      if (key != null) {
        scopeKeys[scope] = key;
      }
    }
    return wrapResourceKeys(friend, scopeKeys);
  }

  Future<String?> currentSharingId() async {
    final settings = await _settingsRepository.getSettings();
    return settings.sharingId;
  }

  Future<String> _ensureSharingReady() async {
    final settings = await _settingsRepository.getSettings();
    final sharingId = await ffi.sharingEnable(
      handle: _handle,
      currentSharingId: settings.sharingId,
    );
    if (settings.sharingId != sharingId) {
      await _settingsRepository.updateSharingId(sharingId);
    }
    await ffi.sharingEnsurePrekey(handle: _handle, sharingId: sharingId);
    await drainRustStore(_handle);
    return sharingId;
  }

  Future<Uint8List> _pairwiseSecretBytes(Friend friend) async {
    if (friend.pairwiseSecret != null) {
      return friend.pairwiseSecret!;
    }
    final legacySecret = friend.sharedSecretHex;
    if (legacySecret != null && legacySecret.isNotEmpty) {
      return ffi.hexDecode(hexStr: legacySecret);
    }
    throw SharingException('No pairwise secret for friend ${friend.id}');
  }

  Future<void> _storePendingRequest(
    _SharingPendingResult result,
    DateTime now,
  ) async {
    await _sharingRequestsDao.upsertRequest(
      SharingRequestsCompanion(
        initId: Value(result.initId),
        senderSharingId: Value(result.senderSharingId),
        displayName: Value(result.displayName ?? result.senderSharingId),
        offeredScopes: Value(
          jsonEncode(result.offeredScopes.map((scope) => scope.name).toList()),
        ),
        senderIdentity: Value(result.senderIdentity),
        pairwiseSecret: Value(result.pairwiseSecret),
        fingerprint: Value(result.fingerprint),
        trustDecision: Value(result.status.storageValue),
        errorMessage: Value(result.error),
        receivedAt: Value(now),
        isResolved: const Value(false),
        resolvedAt: const Value.absent(),
      ),
    );
  }

  Future<FriendRecord?> _findFriendByPeerSharingId(String peerSharingId) async {
    final friends = await _friendsRepository.watchAll().first;
    for (final friend in friends) {
      if (friend.peerSharingId == peerSharingId || friend.id == peerSharingId) {
        return friend;
      }
    }
    return null;
  }

  Future<void> _upsertFriend(
    FriendRecord friend, {
    required FriendRecord? existing,
  }) async {
    if (existing == null) {
      await _friendsRepository.createFriend(friend);
    } else {
      await _friendsRepository.updateFriend(friend);
    }
  }

  Friend _recordToFriend(FriendRecord record) {
    return Friend(
      id: record.id,
      displayName: record.displayName,
      peerSharingId: record.peerSharingId,
      pairwiseSecret: record.pairwiseSecret,
      pinnedIdentity: record.pinnedIdentity,
      offeredScopes: record.offeredScopes.map(_parseScope).toList(),
      publicKeyHex: record.publicKeyHex,
      grantedScopes: record.grantedScopes.map(_parseScope).toList(),
      addedAt: record.createdAt,
      establishedAt: record.establishedAt,
      lastSyncAt: record.lastSyncAt,
      sharedSecretHex: record.sharedSecretHex,
      initId: record.initId,
      isVerified: record.isVerified,
    );
  }

  ShareScope _parseScope(String name) {
    for (final scope in ShareScope.values) {
      if (scope.name == name) return scope;
    }
    return ShareScope.frontStatusOnly;
  }

  String? _cleanOptionalText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic> _asMap(dynamic value, {required String context}) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, entry) => MapEntry(key.toString(), entry));
    }
    throw SharingException('Invalid $context payload');
  }

  String _asString(dynamic value, {required String field}) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw SharingException('Invalid $field in sharing response');
  }
}

class SharingInboxRefreshResult {
  const SharingInboxRefreshResult({
    this.accepted = 0,
    this.warned = 0,
    this.blocked = 0,
    this.errored = 0,
  });

  final int accepted;
  final int warned;
  final int blocked;
  final int errored;

  bool get hasUpdates => accepted + warned + blocked + errored > 0;
}

class RevocationResult {
  const RevocationResult({
    required this.newResourceKeys,
    required this.rewrappedKeysPerFriend,
  });

  final Map<ShareScope, Uint8List> newResourceKeys;
  final Map<String, Map<ShareScope, Uint8List>> rewrappedKeysPerFriend;
}

class SharingException implements Exception {
  SharingException(this.message);

  final String message;

  @override
  String toString() => 'SharingException: $message';
}

class _SharingPendingResult {
  const _SharingPendingResult({
    required this.status,
    required this.initId,
    required this.senderSharingId,
    required this.offeredScopes,
    this.displayName,
    this.pairwiseSecret,
    this.pairwiseSecretHex,
    this.senderIdentity,
    this.senderIdentityHex,
    this.fingerprint,
    this.error,
  });

  final PendingSharingTrustDecision status;
  final String initId;
  final String senderSharingId;
  final String? displayName;
  final List<ShareScope> offeredScopes;
  final Uint8List? pairwiseSecret;
  final String? pairwiseSecretHex;
  final Uint8List? senderIdentity;
  final String? senderIdentityHex;
  final String? fingerprint;
  final String? error;

  factory _SharingPendingResult.fromJson(dynamic value) {
    if (value is! Map) {
      throw SharingException('Invalid pending request result');
    }
    final map = value.map((key, entry) => MapEntry(key.toString(), entry));
    final status = PendingSharingTrustDecision.parse(
      map['status'] as String? ?? 'error',
    );
    final offeredScopes = <ShareScope>[];
    final rawScopes = map['offered_scopes'];
    if (rawScopes is List) {
      for (final item in rawScopes) {
        if (item is! String) continue;
        for (final scope in ShareScope.values) {
          if (scope.name == item) {
            offeredScopes.add(scope);
            break;
          }
        }
      }
    }

    return _SharingPendingResult(
      status: status,
      initId: map['init_id'] as String? ?? '',
      senderSharingId: map['sender_sharing_id'] as String? ?? '',
      displayName: map['display_name'] as String?,
      offeredScopes: offeredScopes,
      pairwiseSecret: map['pairwise_secret_b64'] is String
          ? base64Decode(map['pairwise_secret_b64'] as String)
          : null,
      pairwiseSecretHex: map['pairwise_secret_hex'] as String?,
      senderIdentity: map['sender_identity_b64'] is String
          ? base64Decode(map['sender_identity_b64'] as String)
          : null,
      senderIdentityHex: map['sender_identity_hex'] as String?,
      fingerprint: map['fingerprint'] as String?,
      error: map['error'] as String?,
    );
  }
}
