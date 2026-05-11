import 'dart:typed_data';

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:uuid/uuid.dart';

/// Resolves an unmapped currently-live PluralKit fronter after explicit user
/// action.
///
/// This service is intentionally narrow: it only reads a targeted PK member
/// when a UUID or import field is missing, and it only writes local member
/// identity/display-name metadata needed to establish the mapping.
class PkLiveFronterResolutionService {
  final MemberRepository _members;
  final PluralKitClient _client;
  final Uuid _uuid;
  final DateTime Function() _now;

  PkLiveFronterResolutionService({
    required MemberRepository memberRepository,
    required PluralKitClient client,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _members = memberRepository,
       _client = client,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now;

  /// Link the live PK fronter to an existing local member.
  Future<domain.Member> linkCurrentFronterToLocal(
    PkUnmappedFronterRef ref,
    String localMemberId,
  ) async {
    final pk = await _resolveRef(ref, requireName: false);
    final linked = await _findExistingLinkedMember(pk);
    if (linked != null && linked.id != localMemberId) {
      throw StateError(
        'This PluralKit member is already linked to ${linked.name}.',
      );
    }

    final local = linked ?? await _members.getMemberById(localMemberId);
    if (local == null) {
      throw StateError('Local member $localMemberId not found');
    }
    return _completeIdentityIfNeeded(local, pk, clearIgnored: true);
  }

  /// Import the live PK fronter as one minimal local member.
  ///
  /// Only local name, PK short ID, PK UUID, PK display name, and optionally the
  /// avatar are written. No profile/banner/group/history data is pulled in.
  Future<domain.Member> importCurrentFronter(
    PkUnmappedFronterRef ref, {
    bool includeAvatar = false,
  }) async {
    final pk = await _resolveRef(
      ref,
      requireName: true,
      requireAvatarUrl: includeAvatar,
    );
    final linked = await _findExistingLinkedMember(pk);
    if (linked != null) {
      return _completeIdentityIfNeeded(linked, pk);
    }

    final avatarData = includeAvatar ? await _downloadAvatarBytes(pk) : null;
    final member = domain.Member(
      id: _uuid.v4(),
      name: pk.name,
      createdAt: _now(),
      pluralkitId: pk.id,
      pluralkitUuid: pk.uuid,
      pluralkitDisplayName: pk.displayName,
      avatarImageData: avatarData,
    );
    await _members.createMember(member);
    return member;
  }

  Future<PKMember> _resolveRef(
    PkUnmappedFronterRef ref, {
    required bool requireName,
    bool requireAvatarUrl = false,
  }) async {
    final pkId = ref.pkId.trim();
    if (pkId.isEmpty) {
      throw ArgumentError.value(ref.pkId, 'ref.pkId', 'Must not be blank');
    }

    final pkUuid = _blankToNull(ref.pkUuid);
    final name = _blankToNull(ref.name);
    final displayName = _blankToNull(ref.displayName);
    final avatarUrl = _blankToNull(ref.avatarUrl);
    final needsFetch =
        pkUuid == null ||
        (requireName && name == null) ||
        (requireAvatarUrl && avatarUrl == null);

    if (needsFetch) {
      return _requireUuid(await _client.getMember(pkUuid ?? pkId));
    }

    return _requireUuid(
      PKMember(
        id: pkId,
        uuid: pkUuid,
        name: name ?? displayName ?? pkId,
        displayName: displayName,
        avatarUrl: avatarUrl,
      ),
    );
  }

  PKMember _requireUuid(PKMember pk) {
    if (_blankToNull(pk.uuid) == null) {
      throw StateError(
        'PluralKit member ${pk.id} did not include a UUID; refusing to write '
        'a live-fronter mapping.',
      );
    }
    return pk;
  }

  Future<domain.Member?> _findExistingLinkedMember(PKMember pk) async {
    final existing = await _members.getAllMembersIncludingDeleted();
    domain.Member? shortIdMatch;
    for (final member in existing) {
      if (_sameText(member.pluralkitUuid, pk.uuid)) {
        if (member.isDeleted) {
          throw StateError(
            'A deleted Prism member still owns this PluralKit link. '
            'Restore that member or clear its PluralKit link before importing.',
          );
        }
        return member;
      }
      if (_sameText(member.pluralkitId, pk.id)) {
        if (member.isDeleted) {
          throw StateError(
            'A deleted Prism member still owns this PluralKit link. '
            'Restore that member or clear its PluralKit link before importing.',
          );
        }
        shortIdMatch ??= member;
      }
    }
    return shortIdMatch;
  }

  Future<domain.Member> _completeIdentityIfNeeded(
    domain.Member member,
    PKMember pk, {
    bool clearIgnored = false,
  }) async {
    final next = member.copyWith(
      pluralkitUuid: pk.uuid,
      pluralkitId: pk.id,
      pluralkitDisplayName: pk.displayName,
      pluralkitSyncIgnored: clearIgnored ? false : member.pluralkitSyncIgnored,
    );
    if (next == member) return member;
    await _members.updateMember(next);
    return next;
  }

  Future<Uint8List?> _downloadAvatarBytes(PKMember pk) async {
    final avatarUrl = _blankToNull(pk.avatarUrl);
    if (avatarUrl == null) return null;
    try {
      final bytes = await _client.downloadBytes(avatarUrl);
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  static bool _sameText(String? a, String? b) {
    final left = _blankToNull(a);
    final right = _blankToNull(b);
    return left != null && right != null && left == right;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
