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
      // Part 1.5 guard: importCurrentFronter is the passive "show me the
      // current PK fronter, link as needed" path. If the user has
      // explicitly excluded this local from PK sync, don't resume sync —
      // just return the existing row. The explicit user action
      // (`linkCurrentFronterToLocal`) is the only path here that resumes.
      if (linked.pluralkitSyncIgnored) return linked;
      return _completeIdentityIfNeeded(linked, pk);
    }

    final avatarData = includeAvatar ? await _downloadAvatarBytes(pk) : null;
    final avatarUrl = _blankToNull(pk.avatarUrl);
    final member = domain.Member(
      id: _uuid.v4(),
      name: pk.name,
      createdAt: pk.created ?? _now(),
      pluralkitId: pk.id,
      pluralkitUuid: pk.uuid,
      pluralkitDisplayName: pk.displayName,
      avatarImageData: avatarData,
      pkAvatarCachedUrl: avatarData != null ? avatarUrl : null,
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
    // Always include pluralkit_uuid even if it already matches — this
    // ensures: (1) the patch is never empty (no silent no-op when all
    // fields already match; sync still resumes via the force-injected
    // sync_ignored=false), and (2) applyPluralKitLink's "requires uuid
    // or id" assert always passes. diffSyncFields strips the no-op key
    // before the actual DB write so we don't bump an HLC on an
    // unchanged value.
    final patch = <String, dynamic>{
      'pluralkit_uuid': pk.uuid,
      if (member.pluralkitId != pk.id) 'pluralkit_id': pk.id,
      if (member.pluralkitDisplayName != pk.displayName)
        'pluralkit_display_name': pk.displayName,
    };
    if (clearIgnored) {
      await _members.applyPluralKitLink(member.id, patch);
    } else {
      await _members.recordPluralKitIdentity(member.id, patch);
    }
    return member.copyWith(
      pluralkitUuid: pk.uuid,
      pluralkitId: pk.id,
      pluralkitDisplayName: pk.displayName,
      pluralkitSyncIgnored: clearIgnored ? false : member.pluralkitSyncIgnored,
    );
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
