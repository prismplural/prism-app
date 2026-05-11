import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';
import 'package:uuid/uuid.dart';

/// Friendly error text persisted to `pk_mapping_state.errorMessage` when the
/// applier hits a network-layer failure. Top-level public (not `_kPk…`) so a
/// future Change 4 in the screen can compare against it across the library
/// boundary to collapse identical failures.
const kPkApplierNetworkErrorMessage = "Couldn't reach PluralKit";

/// One user decision made in the mapping screen.
sealed class PkMappingDecision {
  const PkMappingDecision();

  /// Deterministic, stable ID so the applier can resume on retry without
  /// duplicating work.
  String get id;
}

/// Link an existing local member to an existing PK member.
class PkLinkDecision extends PkMappingDecision {
  final String localMemberId;
  final PKMember pkMember;
  const PkLinkDecision({required this.localMemberId, required this.pkMember});
  @override
  String get id => 'link:${pkMember.uuid}';
}

/// Import a PK member as a brand new local member.
class PkImportDecision extends PkMappingDecision {
  final PKMember pkMember;
  const PkImportDecision({required this.pkMember});
  @override
  String get id => 'import:${pkMember.uuid}';
}

/// Push an existing local member to PK as a new PK member.
class PkPushNewDecision extends PkMappingDecision {
  final String localMemberId;
  const PkPushNewDecision({required this.localMemberId});
  @override
  String get id => 'push:$localMemberId';
}

/// Mark a local or PK member as permanently ignored by the mapping flow.
class PkSkipDecision extends PkMappingDecision {
  final String? localMemberId;
  final String? pkMemberUuid;
  const PkSkipDecision({this.localMemberId, this.pkMemberUuid})
    : assert(localMemberId != null || pkMemberUuid != null);
  @override
  String get id => localMemberId != null
      ? 'skip:local:$localMemberId'
      : 'skip:pk:$pkMemberUuid';
}

enum PkApplyOutcome { applied, alreadyApplied, failed }

class PkApplyResult {
  final PkMappingDecision decision;
  final PkApplyOutcome outcome;
  final String? error;
  const PkApplyResult({
    required this.decision,
    required this.outcome,
    this.error,
  });
}

/// Applies a batch of [PkMappingDecision] items idempotently.
///
/// For each decision:
/// 1. If already recorded as `applied`, skip (resumable).
/// 2. Otherwise upsert a `pending` state row *before* doing remote work.
/// 3. Execute the decision's side-effect (local write, POST to PK, etc).
/// 4. Mark `applied` (or `failed` with message) in the state table.
///
/// Failures don't abort the batch — they're recorded per-item so the UI can
/// surface them and the user can retry.
class PkMappingApplier {
  final MemberRepository _members;
  final PkMappingStateDao _state;
  final PkPushService _pushService;
  final PluralKitClient _client;
  final PkBannerCacheService _bannerCacheService;
  final Uuid _uuid;
  final DateTime Function() _now;

  PkMappingApplier({
    required MemberRepository members,
    required PkMappingStateDao state,
    required PkPushService pushService,
    required PluralKitClient client,
    PkBannerCacheService? bannerCacheService,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _members = members,
       _state = state,
       _pushService = pushService,
       _client = client,
       _bannerCacheService = bannerCacheService ?? PkBannerCacheService(),
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now;

  Future<List<PkApplyResult>> apply(List<PkMappingDecision> decisions) async {
    final results = <PkApplyResult>[];
    for (final decision in decisions) {
      results.add(await _applyOne(decision));
    }
    return results;
  }

  Future<PkApplyResult> _applyOne(PkMappingDecision decision) async {
    final existing = await _state.getById(decision.id);
    if (existing != null && existing.status == 'applied') {
      return PkApplyResult(
        decision: decision,
        outcome: PkApplyOutcome.alreadyApplied,
      );
    }

    await _recordPending(decision);

    try {
      switch (decision) {
        case PkLinkDecision():
          await _applyLink(decision);
        case PkImportDecision():
          await _applyImport(decision);
        case PkPushNewDecision():
          await _applyPushNew(decision, existing);
        case PkSkipDecision():
          await _applySkip(decision);
      }
      await _state.markApplied(decision.id);
      return PkApplyResult(decision: decision, outcome: PkApplyOutcome.applied);
    } catch (e) {
      final raw = e.toString();
      if (isPluralKitNetworkException(e)) {
        debugPrint('[PK_APPLIER] network failure on ${decision.id}: $raw');
      }
      final msg = _formatApplierError(e, raw);
      await _state.markFailed(decision.id, msg);
      return PkApplyResult(
        decision: decision,
        outcome: PkApplyOutcome.failed,
        error: msg,
      );
    }
  }

  String _formatApplierError(Object e, String raw) {
    if (isPluralKitNetworkException(e)) {
      return kPkApplierNetworkErrorMessage;
    }
    return raw;
  }

  Future<void> _recordPending(PkMappingDecision decision) async {
    final now = _now();
    String? pkMemberId;
    String? pkMemberUuid;
    String? localId;
    String type;
    switch (decision) {
      case PkLinkDecision():
        type = 'link';
        pkMemberId = decision.pkMember.id;
        pkMemberUuid = decision.pkMember.uuid;
        localId = decision.localMemberId;
      case PkImportDecision():
        type = 'import';
        pkMemberId = decision.pkMember.id;
        pkMemberUuid = decision.pkMember.uuid;
      case PkPushNewDecision():
        type = 'push';
        localId = decision.localMemberId;
      case PkSkipDecision():
        type = 'skip';
        pkMemberUuid = decision.pkMemberUuid;
        localId = decision.localMemberId;
    }
    await _state.upsert(
      PkMappingStateCompanion(
        id: Value(decision.id),
        decisionType: Value(type),
        pkMemberId: Value(pkMemberId),
        pkMemberUuid: Value(pkMemberUuid),
        localMemberId: Value(localId),
        status: const Value('pending'),
        errorMessage: const Value(null),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _applyLink(PkLinkDecision d) async {
    final local = await _members.getMemberById(d.localMemberId);
    if (local == null) {
      throw StateError('Local member ${d.localMemberId} not found');
    }
    final pk = d.pkMember;
    final linkedElsewhere = await _findExistingLinkedMember(
      pk,
      exceptLocalId: local.id,
    );
    if (linkedElsewhere != null) {
      throw StateError(
        'PluralKit member ${pk.name} is already linked to '
        '${linkedElsewhere.name}',
      );
    }
    final deletedHolder = await _findDeletedPkIdentityHolder(
      pk,
      exceptLocalId: local.id,
    );
    if (deletedHolder != null) {
      throw _pkIdentityHeldByDeletedMember(pk, deletedHolder);
    }
    // Idempotent: if already linked to this PK member, no-op.
    if (local.pluralkitUuid == pk.uuid &&
        local.pluralkitId == pk.id &&
        !local.pluralkitSyncIgnored) {
      return;
    }

    // Plan 08 "Conflict semantics on link": on first link, if the local field
    // is the Prism default (empty/null/placeholder), accept PK's value —
    // effectively a pull-on-link for defaults. Otherwise keep local, and the
    // per-field push direction will reconcile on the next sync.
    //
    // We also download PK's avatar if local has none, so the linked member
    // gets its picture without waiting for a full re-import.
    var updated = local.copyWith(
      pluralkitUuid: pk.uuid,
      pluralkitId: pk.id,
      pluralkitDisplayName: pk.displayName,
      pluralkitSyncIgnored: false,
    );

    if (_isDefaultName(local.name)) {
      updated = updated.copyWith(name: pk.name);
    }
    if (_isNullOrEmpty(local.pronouns) && !_isNullOrEmpty(pk.pronouns)) {
      updated = updated.copyWith(pronouns: pk.pronouns);
    }
    if (_isNullOrEmpty(local.bio) && !_isNullOrEmpty(pk.description)) {
      updated = updated.copyWith(bio: pk.description);
    }
    if (_isNullOrEmpty(local.birthday) && !_isNullOrEmpty(pk.birthday)) {
      updated = updated.copyWith(birthday: pk.birthday);
    }
    if ((!local.customColorEnabled || _isNullOrEmpty(local.customColorHex)) &&
        !_isNullOrEmpty(pk.color)) {
      updated = updated.copyWith(
        customColorHex: '#${pk.color}',
        customColorEnabled: true,
      );
    }
    if (local.proxyTagsJson == null && pk.proxyTagsJson != null) {
      updated = updated.copyWith(proxyTagsJson: pk.proxyTagsJson);
    }
    if (local.avatarImageData == null && pk.avatarUrl != null) {
      final bytes = await _downloadAvatarBytes(pk.avatarUrl!);
      if (bytes != null) {
        updated = updated.copyWith(avatarImageData: bytes);
      }
    }

    final bannerCache = await _bannerCacheService.resolve(
      PkBannerCacheInput(
        currentPkBannerUrl: local.pkBannerUrl,
        currentPkBannerImageData: local.pkBannerImageData,
        currentPkBannerCachedUrl: local.pkBannerCachedUrl,
        hasIncomingBannerField: pk.hasBannerField,
        incomingBannerUrl: pk.bannerUrl,
      ),
    );
    updated = updated.copyWith(
      pkBannerUrl: bannerCache.pkBannerUrl,
      pkBannerImageData: bannerCache.pkBannerImageData,
      pkBannerCachedUrl: bannerCache.pkBannerCachedUrl,
      profileHeaderSource:
          updated.profileHeaderSource ==
                  domain.MemberProfileHeaderSource.prism &&
              updated.profileHeaderImageData == null &&
              _hasText(bannerCache.pkBannerUrl)
          ? domain.MemberProfileHeaderSource.pluralKit
          : updated.profileHeaderSource,
    );

    await _members.updateMember(updated);
  }

  static bool _isNullOrEmpty(String? s) => s == null || s.isEmpty;

  static bool _hasText(String? s) => s != null && s.trim().isNotEmpty;

  /// Conservative "is the local name a default placeholder?" check. We only
  /// treat literally empty names as defaults — real user-typed names (even
  /// "New Member") are kept, per the plan's guidance to be conservative.
  static bool _isDefaultName(String name) => name.isEmpty;

  Future<void> _applyImport(PkImportDecision d) async {
    // Idempotent: if a local with this UUID or short ID already exists, no-op.
    // Older push paths persisted only the short ID; complete the UUID here so
    // the mapping screen no longer treats that member as unlinked.
    final existing = await _findExistingLinkedMember(d.pkMember);
    if (existing != null) {
      if (existing.pluralkitUuid != d.pkMember.uuid ||
          existing.pluralkitId != d.pkMember.id) {
        await _members.updateMember(
          existing.copyWith(
            pluralkitUuid: d.pkMember.uuid,
            pluralkitId: d.pkMember.id,
          ),
        );
      }
      return;
    }
    final deletedHolder = await _findDeletedPkIdentityHolder(d.pkMember);
    if (deletedHolder != null) {
      throw _pkIdentityHeldByDeletedMember(d.pkMember, deletedHolder);
    }

    // Download avatar when PK has one, matching the PluralKitSyncService
    // _importMembers behavior so mapping-UI Imports don't produce avatar-less
    // members. Failure is non-fatal.
    final avatarBytes = d.pkMember.avatarUrl != null
        ? await _downloadAvatarBytes(d.pkMember.avatarUrl!)
        : null;
    final bannerCache = await _bannerCacheService.resolve(
      PkBannerCacheInput(
        currentPkBannerUrl: null,
        currentPkBannerImageData: null,
        currentPkBannerCachedUrl: null,
        hasIncomingBannerField: d.pkMember.hasBannerField,
        incomingBannerUrl: d.pkMember.bannerUrl,
      ),
    );

    final member = domain.Member(
      id: _uuid.v4(),
      name: d.pkMember.name,
      pronouns: d.pkMember.pronouns,
      bio: d.pkMember.description,
      customColorHex: d.pkMember.color != null ? '#${d.pkMember.color}' : null,
      customColorEnabled: d.pkMember.color != null,
      pluralkitDisplayName: d.pkMember.displayName,
      birthday: d.pkMember.birthday,
      proxyTagsJson: d.pkMember.proxyTagsJson,
      avatarImageData: avatarBytes,
      pkBannerUrl: bannerCache.pkBannerUrl,
      profileHeaderSource: _hasText(bannerCache.pkBannerUrl)
          ? domain.MemberProfileHeaderSource.pluralKit
          : domain.MemberProfileHeaderSource.prism,
      pkBannerImageData: bannerCache.pkBannerImageData,
      pkBannerCachedUrl: bannerCache.pkBannerCachedUrl,
      pluralkitUuid: d.pkMember.uuid,
      pluralkitId: d.pkMember.id,
      createdAt: _now(),
    );
    await _members.createMember(member);
  }

  /// Avatar download helper. Mirrors the inline logic in
  /// PluralKitSyncService._importMembers — duplicated here to respect the
  /// file-ownership split between this applier and pluralkit_sync_service.dart.
  // TODO(pk): consolidate with PluralKitSyncService._importMembers avatar
  // download into a shared util once the two files can be touched together.
  Future<Uint8List?> _downloadAvatarBytes(String url) async {
    try {
      final bytes = await _client.downloadBytes(url);
      return Uint8List.fromList(bytes);
    } catch (_) {
      // Avatar download failure is non-fatal — proceed without the picture.
      return null;
    }
  }

  Future<void> _applyPushNew(
    PkPushNewDecision d,
    PkMappingStateData? priorState,
  ) async {
    final local = await _members.getMemberById(d.localMemberId);
    if (local == null) {
      throw StateError('Local member ${d.localMemberId} not found');
    }
    // Idempotent: if already has a PK ID, no-op.
    if (_hasText(local.pluralkitId) && _hasText(local.pluralkitUuid)) return;

    // Crash-recovery: prior run POSTed but never wrote the local member.
    // pk_mapping_state has the PK id/uuid — reuse them instead of re-POSTing.
    if (priorState?.pkMemberId != null && priorState?.pkMemberUuid != null) {
      await _members.updateMember(
        local.copyWith(
          pluralkitId: priorState!.pkMemberId,
          pluralkitUuid: priorState.pkMemberUuid,
        ),
      );
      return;
    }

    // If pluralkitId exists but uuid missing, fetch to complete the pairing.
    final existingPkId = local.pluralkitId?.trim();
    if (existingPkId != null &&
        existingPkId.isNotEmpty &&
        !_hasText(local.pluralkitUuid)) {
      final members = await _client.getMembers();
      final match = members.firstWhere(
        (m) => m.id == existingPkId,
        orElse: () => _pkSentinel,
      );
      if (!identical(match, _pkSentinel)) {
        await _members.updateMember(
          local.copyWith(pluralkitUuid: match.uuid, pluralkitId: match.id),
        );
        return;
      }
    }

    // Push through PkPushService (handles queue + rate limits) to get the ID,
    // then fetch the full PKMember object for the UUID.
    final created = await _pushService.pushMemberFull(local, _client);
    final createdId = created.id;
    final createdUuid = created.uuid;

    // Persist the returned PK identifiers to pk_mapping_state BEFORE writing
    // the member, so a crash between here and the member update doesn't cause
    // a duplicate POST on retry.
    final now = _now();
    await _state.upsert(
      PkMappingStateCompanion(
        id: Value(d.id),
        decisionType: const Value('push'),
        pkMemberId: Value(createdId),
        pkMemberUuid: Value(createdUuid),
        localMemberId: Value(d.localMemberId),
        status: const Value('pending'),
        createdAt: Value(priorState?.createdAt ?? now),
        updatedAt: Value(now),
      ),
    );

    await _members.updateMember(
      local.copyWith(pluralkitId: createdId, pluralkitUuid: createdUuid),
    );
  }

  Future<void> _applySkip(PkSkipDecision d) async {
    if (d.localMemberId != null) {
      final local = await _members.getMemberById(d.localMemberId!);
      if (local == null) return;
      if (local.pluralkitSyncIgnored) return;
      await _members.updateMember(local.copyWith(pluralkitSyncIgnored: true));
    }
    // PK-side skip is recorded purely in pk_mapping_state; no local write.
  }

  Future<domain.Member?> _findExistingLinkedMember(
    PKMember pk, {
    String? exceptLocalId,
  }) async {
    final existing = await _members.getAllMembers();
    for (final member in existing) {
      if (member.id == exceptLocalId) continue;
      if (memberMatchesPkMember(member, pk)) return member;
    }
    return null;
  }

  Future<domain.Member?> _findDeletedPkIdentityHolder(
    PKMember pk, {
    String? exceptLocalId,
  }) async {
    final existing = await _members.getAllMembersIncludingDeleted();
    for (final member in existing) {
      if (member.id == exceptLocalId || !member.isDeleted) continue;
      if (memberMatchesPkMember(member, pk)) return member;
    }
    return null;
  }

  StateError _pkIdentityHeldByDeletedMember(PKMember pk, domain.Member member) {
    final localName = member.name.isEmpty ? member.id : member.name;
    return StateError(
      'PluralKit member ${pk.name} cannot be linked or imported because a '
      'deleted local member still owns this PluralKit link '
      '($localName, id=${member.id}).',
    );
  }

  // Sentinel for "not found" without nullable casts.
  static const PKMember _pkSentinel = PKMember(
    id: '__sentinel__',
    uuid: '__sentinel__',
    name: '',
  );
}
