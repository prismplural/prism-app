import 'dart:async';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/database/daos/pk_group_sync_aliases_dao.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

typedef HasRepairTokenCallback = Future<bool> Function({String? token});
typedef FetchRepairReferenceDataCallback =
    Future<PkRepairReferenceData> Function({String? token});

class PkGroupReviewItem {
  const PkGroupReviewItem({
    required this.groupId,
    required this.name,
    this.description,
    this.colorHex,
    required this.suspectedPkGroupUuid,
    required this.syncSuppressed,
    this.candidateName,
    this.candidateDescription,
    this.candidateColorHex,
    this.sharedPkMemberUuids = const <String>{},
    this.extraLocalMemberIds = const <String>{},
    this.onlyInCandidateMemberUuids = const <String>{},
  });

  final String groupId;
  final String name;
  final String? description;
  final String? colorHex;
  final String suspectedPkGroupUuid;
  final bool syncSuppressed;
  final String? candidateName;
  final String? candidateDescription;
  final String? candidateColorHex;
  final Set<String> sharedPkMemberUuids;
  final Set<String> extraLocalMemberIds;
  final Set<String> onlyInCandidateMemberUuids;

  bool get hasCandidateComparison => candidateName != null;
}

enum PkGroupRepairReferenceMode { none, storedToken, providedToken }

class PkGroupRepairReport {
  const PkGroupRepairReport({
    required this.referenceMode,
    required this.backfilledEntries,
    required this.canonicalizedEntryIds,
    required this.revivedTombstonesDuringCanonicalization,
    required this.legacyEntriesSoftDeletedDuringCanonicalization,
    required this.duplicateSetsMerged,
    required this.duplicateGroupsSoftDeleted,
    required this.parentReferencesRehomed,
    required this.entriesRehomed,
    required this.entryConflictsSoftDeleted,
    required this.aliasesRecorded,
    required this.ambiguousGroupsSuppressed,
    required this.pendingReviewCount,
    this.referenceError,
    this.requiresReconnectForMissingPkGroupIdentity = false,
  });

  final PkGroupRepairReferenceMode referenceMode;
  final int backfilledEntries;
  final int canonicalizedEntryIds;
  final int revivedTombstonesDuringCanonicalization;
  final int legacyEntriesSoftDeletedDuringCanonicalization;
  final int duplicateSetsMerged;
  final int duplicateGroupsSoftDeleted;
  final int parentReferencesRehomed;
  final int entriesRehomed;
  final int entryConflictsSoftDeleted;
  final int aliasesRecorded;
  final int ambiguousGroupsSuppressed;
  final int pendingReviewCount;
  final String? referenceError;
  final bool requiresReconnectForMissingPkGroupIdentity;
}

class PkGroupRepairService {
  PkGroupRepairService({
    required MemberGroupsDao memberGroupsDao,
    required PkGroupSyncAliasesDao aliasesDao,
    required HasRepairTokenCallback hasRepairToken,
    required FetchRepairReferenceDataCallback fetchRepairReferenceData,
  }) : _memberGroupsDao = memberGroupsDao,
       _aliasesDao = aliasesDao,
       _hasRepairToken = hasRepairToken,
       _fetchRepairReferenceData = fetchRepairReferenceData;

  final MemberGroupsDao _memberGroupsDao;
  final PkGroupSyncAliasesDao _aliasesDao;
  final HasRepairTokenCallback _hasRepairToken;
  final FetchRepairReferenceDataCallback _fetchRepairReferenceData;

  Future<PkGroupRepairReport>? _inFlight;
  PkRepairReferenceData? _lastReferenceData;

  Future<int> getPendingReviewCount() async {
    final groups = await _memberGroupsDao.getGroupsPendingPkReview();
    return groups.length;
  }

  Future<List<PkGroupReviewItem>> getPendingReviewItems() async {
    final groups = await _memberGroupsDao.getGroupsPendingPkReview();
    if (groups.isEmpty) return const <PkGroupReviewItem>[];

    final groupIds = groups.map((group) => group.id).toSet();
    final pkMemberUuidsByGroupId = await _memberGroupsDao
        .activePkMemberUuidsByGroupIds(groupIds);
    final extraLocalMemberIdsByGroupId = await _memberGroupsDao
        .activeLocalOnlyMemberIdsByGroupIds(groupIds);

    final referenceGroupsByUuid = <String, PKGroup>{};
    final referenceData = _lastReferenceData;
    if (referenceData != null) {
      for (final group in referenceData.groups) {
        if (group.uuid.isNotEmpty) {
          referenceGroupsByUuid[group.uuid] = group;
        }
      }
    }

    return groups
        .map((group) {
          final suspectedPkGroupUuid = group.suspectedPkGroupUuid ?? '';
          final referenceGroup = referenceGroupsByUuid[suspectedPkGroupUuid];
          final localPkMembers =
              pkMemberUuidsByGroupId[group.id] ?? const <String>{};
          final candidateMembers = referenceGroup?.memberIds?.toSet();
          final sharedPkMemberUuids = candidateMembers == null
              ? const <String>{}
              : localPkMembers.where(candidateMembers.contains).toSet();
          final onlyInCandidateMemberUuids = candidateMembers == null
              ? const <String>{}
              : candidateMembers
                    .where((uuid) => !localPkMembers.contains(uuid))
                    .toSet();

          return PkGroupReviewItem(
            groupId: group.id,
            name: group.name,
            description: group.description,
            colorHex: group.colorHex,
            suspectedPkGroupUuid: suspectedPkGroupUuid,
            syncSuppressed: group.syncSuppressed,
            candidateName: referenceGroup?.displayName ?? referenceGroup?.name,
            candidateDescription: referenceGroup?.description,
            candidateColorHex: referenceGroup?.color == null
                ? null
                : '#${referenceGroup!.color}',
            sharedPkMemberUuids: sharedPkMemberUuids,
            extraLocalMemberIds:
                extraLocalMemberIdsByGroupId[group.id] ?? const <String>{},
            onlyInCandidateMemberUuids: onlyInCandidateMemberUuids,
          );
        })
        .toList(growable: false);
  }

  Future<PkGroupRepairReport> run({
    String? token,
    bool allowStoredToken = true,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final future = _run(token: token, allowStoredToken: allowStoredToken);
    _inFlight = future;
    unawaited(
      future.then<void>((_) {}, onError: (_) {}).whenComplete(() {
        if (identical(_inFlight, future)) {
          _inFlight = null;
        }
      }),
    );
    return future;
  }

  Future<void> dismissReviewItems(List<String> groupIds) {
    return _memberGroupsDao.transaction(() async {
      await _memberGroupsDao.dismissGroupsFromPkReview(groupIds);
    });
  }

  Future<void> keepReviewItemsLocalOnly(List<String> groupIds) {
    return _memberGroupsDao.transaction(() async {
      await _memberGroupsDao.keepGroupsLocalOnly(groupIds);
    });
  }

  Future<void> mergeReviewItemIntoCanonical(String groupId) async {
    await _memberGroupsDao.transaction(() async {
      final group = await _memberGroupsDao.getGroupById(groupId);
      if (group == null) {
        throw StateError('Group $groupId no longer exists');
      }

      final suspectedPkGroupUuid = group.suspectedPkGroupUuid;
      if (suspectedPkGroupUuid == null || suspectedPkGroupUuid.isEmpty) {
        throw StateError('Group $groupId is no longer pending review');
      }

      final canonical = await _memberGroupsDao.findByPluralkitUuid(
        suspectedPkGroupUuid,
      );
      if (canonical != null && canonical.id != group.id) {
        final loserIds = [group.id];
        await _memberGroupsDao.rehomeParentReferencesToWinner(
          winnerGroupId: canonical.id,
          loserGroupIds: loserIds,
        );
        await _memberGroupsDao.rehomeEntriesToWinner(
          winnerGroupId: canonical.id,
          loserGroupIds: loserIds,
          canonicalPkGroupUuid: suspectedPkGroupUuid,
        );
        await _memberGroupsDao.backfillActiveEntryPkReferences();
        await _memberGroupsDao.canonicalizePkBackedEntryIds();
        await _aliasesDao.upsertAlias(
          legacyEntityId: group.id,
          pkGroupUuid: suspectedPkGroupUuid,
          canonicalEntityId: _canonicalPkGroupEntityId(suspectedPkGroupUuid),
        );
        await _memberGroupsDao.softDeleteGroupsForRepair(loserIds);
        return;
      }

      await _memberGroupsDao.linkGroupToPluralkitUuid(
        groupId: group.id,
        pluralkitUuid: suspectedPkGroupUuid,
      );
      await _memberGroupsDao.backfillActiveEntryPkReferences();
      await _memberGroupsDao.canonicalizePkBackedEntryIds();
    });
  }

  Future<PkGroupRepairReport> _run({
    String? token,
    required bool allowStoredToken,
  }) async {
    final referenceResolution = await _resolveReferenceData(
      token: token,
      allowStoredToken: allowStoredToken,
    );

    return _memberGroupsDao.transaction(() async {
      final backfilledEntries = await _memberGroupsDao
          .backfillActiveEntryPkReferences();

      // H2: canonicalize legacy PK-backed entry ids onto the deterministic
      // `sha256(pkGroupUuid || 0x00 || pkMemberUuid)[:16]` hash. Reviving
      // tombstones already occupying the canonical id keeps the partial
      // `(group_id, member_id) WHERE is_deleted = 0` unique index clean.
      final canonicalization = await _memberGroupsDao
          .canonicalizePkBackedEntryIds();

      final entryCounts = await _activeEntryCountByGroupId();
      final pkMemberUuidsByGroupId = await _memberGroupsDao
          .activePkMemberUuidsByGroupId();
      final referencePkMembersByGroupUuid = _referencePkMembersByGroupUuid(
        referenceResolution.data,
      );
      final duplicateSets = await _memberGroupsDao
          .getActiveLinkedPkGroupDuplicateSets();

      var duplicateSetsMerged = 0;
      var duplicateGroupsSoftDeleted = 0;
      var parentReferencesRehomed = 0;
      var entriesRehomed = 0;
      var entryConflictsSoftDeleted = 0;
      var aliasesRecorded = 0;

      for (final duplicateSet in duplicateSets) {
        final winner = _chooseWinner(
          duplicateSet.groups,
          entryCounts,
          pkMemberUuidsByGroupId,
          referencePkMembersByGroupUuid[duplicateSet.pkGroupUuid],
        );
        final losers = duplicateSet.groups
            .where((group) => group.id != winner.id)
            .toList(growable: false);
        if (losers.isEmpty) continue;

        final loserIds = losers
            .map((group) => group.id)
            .toList(growable: false);
        duplicateSetsMerged++;
        duplicateGroupsSoftDeleted += loserIds.length;

        parentReferencesRehomed += await _memberGroupsDao
            .rehomeParentReferencesToWinner(
              winnerGroupId: winner.id,
              loserGroupIds: loserIds,
            );

        final rehomeResult = await _memberGroupsDao.rehomeEntriesToWinner(
          winnerGroupId: winner.id,
          loserGroupIds: loserIds,
          canonicalPkGroupUuid: duplicateSet.pkGroupUuid,
        );
        entriesRehomed += rehomeResult.movedEntries;
        entryConflictsSoftDeleted += rehomeResult.softDeletedConflicts;

        for (final loser in losers) {
          await _aliasesDao.upsertAlias(
            legacyEntityId: loser.id,
            pkGroupUuid: duplicateSet.pkGroupUuid,
            canonicalEntityId: _canonicalPkGroupEntityId(
              duplicateSet.pkGroupUuid,
            ),
          );
          aliasesRecorded++;
        }

        await _memberGroupsDao.softDeleteGroupsForRepair(loserIds);
      }

      final ambiguousGroupsSuppressed = await _markAmbiguousGroupsForReview(
        referenceData: referenceResolution.data,
      );
      final pendingReviewCount = await getPendingReviewCount();
      final requiresReconnectForMissingPkGroupIdentity =
          await _requiresReconnectForMissingPkGroupIdentity(
            referenceData: referenceResolution.data,
            referenceError: referenceResolution.error,
          );

      return PkGroupRepairReport(
        referenceMode: referenceResolution.mode,
        backfilledEntries: backfilledEntries,
        canonicalizedEntryIds: canonicalization.rewritten,
        revivedTombstonesDuringCanonicalization:
            canonicalization.revivedTombstones,
        legacyEntriesSoftDeletedDuringCanonicalization:
            canonicalization.softDeletedLegacyConflicts,
        duplicateSetsMerged: duplicateSetsMerged,
        duplicateGroupsSoftDeleted: duplicateGroupsSoftDeleted,
        parentReferencesRehomed: parentReferencesRehomed,
        entriesRehomed: entriesRehomed,
        entryConflictsSoftDeleted: entryConflictsSoftDeleted,
        aliasesRecorded: aliasesRecorded,
        ambiguousGroupsSuppressed: ambiguousGroupsSuppressed,
        pendingReviewCount: pendingReviewCount,
        referenceError: referenceResolution.error,
        requiresReconnectForMissingPkGroupIdentity:
            requiresReconnectForMissingPkGroupIdentity,
      );
    });
  }

  Future<_ReferenceResolution> _resolveReferenceData({
    required String? token,
    required bool allowStoredToken,
  }) async {
    try {
      if (token != null && token.trim().isNotEmpty) {
        final data = await _fetchRepairReferenceData(token: token);
        _lastReferenceData = data;
        return _ReferenceResolution(
          mode: PkGroupRepairReferenceMode.providedToken,
          data: data,
        );
      }

      if (!allowStoredToken) {
        _lastReferenceData = null;
        return const _ReferenceResolution(
          mode: PkGroupRepairReferenceMode.none,
        );
      }

      final hasStoredToken = await _hasRepairToken();
      if (!hasStoredToken) {
        _lastReferenceData = null;
        return const _ReferenceResolution(
          mode: PkGroupRepairReferenceMode.none,
        );
      }

      final data = await _fetchRepairReferenceData();
      _lastReferenceData = data;
      return _ReferenceResolution(
        mode: PkGroupRepairReferenceMode.storedToken,
        data: data,
      );
    } catch (error) {
      _lastReferenceData = null;
      if (token != null && token.trim().isNotEmpty) rethrow;
      return _ReferenceResolution(
        mode: PkGroupRepairReferenceMode.none,
        error: error.toString(),
      );
    }
  }

  Future<Map<String, int>> _activeEntryCountByGroupId() async {
    return _memberGroupsDao.activeEntryCountsByGroupId();
  }

  MemberGroupRow _chooseWinner(
    List<MemberGroupRow> groups,
    Map<String, int> entryCounts,
    Map<String, Set<String>> localPkMembersByGroupId,
    Set<String>? candidatePkMemberUuids,
  ) {
    final sorted = [...groups]
      ..sort((left, right) {
        final leftCount = entryCounts[left.id] ?? 0;
        final rightCount = entryCounts[right.id] ?? 0;
        if (candidatePkMemberUuids != null) {
          final leftPkMembers =
              localPkMembersByGroupId[left.id] ?? const <String>{};
          final rightPkMembers =
              localPkMembersByGroupId[right.id] ?? const <String>{};
          final leftMatch = _membershipMatchScore(
            leftPkMembers,
            candidatePkMemberUuids,
            totalActiveMembershipCount: leftCount,
          );
          final rightMatch = _membershipMatchScore(
            rightPkMembers,
            candidatePkMemberUuids,
            totalActiveMembershipCount: rightCount,
          );
          final matchCompare = rightMatch.compareTo(leftMatch);
          if (matchCompare != 0) return matchCompare;
        }

        final countCompare = rightCount.compareTo(leftCount);
        if (countCompare != 0) return countCompare;

        if (left.syncSuppressed != right.syncSuppressed) {
          return left.syncSuppressed ? 1 : -1;
        }

        if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt == null) {
          return -1;
        }
        if (left.lastSeenFromPkAt == null && right.lastSeenFromPkAt != null) {
          return 1;
        }
        if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt != null) {
          final seenCompare = right.lastSeenFromPkAt!.compareTo(
            left.lastSeenFromPkAt!,
          );
          if (seenCompare != 0) return seenCompare;
        }

        final createdCompare = left.createdAt.compareTo(right.createdAt);
        if (createdCompare != 0) return createdCompare;

        return left.id.compareTo(right.id);
      });
    return sorted.first;
  }

  Future<int> _markAmbiguousGroupsForReview({
    required PkRepairReferenceData? referenceData,
  }) async {
    final activeGroups = await _memberGroupsDao.getAllActiveGroups();
    final pkMemberUuidsByGroupId = await _memberGroupsDao
        .activePkMemberUuidsByGroupId();
    final totalMembershipCountByGroupId = await _memberGroupsDao
        .activeEntryCountsByGroupId();
    final references = _buildReferenceGroups(
      activeGroups: activeGroups,
      referenceData: referenceData,
      pkMemberUuidsByGroupId: pkMemberUuidsByGroupId,
    );

    if (references.isEmpty) return 0;

    var suppressed = 0;
    for (final group in activeGroups) {
      if (group.pluralkitUuid != null && group.pluralkitUuid!.isNotEmpty) {
        continue;
      }
      if (group.syncSuppressed) {
        continue;
      }

      final normalizedName = _normalizeName(group.name);
      if (normalizedName == null) continue;

      final localPkMembers = pkMemberUuidsByGroupId[group.id];
      if (localPkMembers == null || localPkMembers.isEmpty) continue;
      final totalMembershipCount = totalMembershipCountByGroupId[group.id] ?? 0;
      if (totalMembershipCount != localPkMembers.length) continue;

      final candidates =
          references[normalizedName] ?? const <_RepairReference>[];
      final exactMatches = candidates
          .where(
            (candidate) => _setEquals(candidate.pkMemberUuids, localPkMembers),
          )
          .toList(growable: false);

      if (exactMatches.length != 1) continue;

      final updated = await _memberGroupsDao.markGroupsSuppressedForReview(
        groupIds: [group.id],
        suspectedPkGroupUuid: exactMatches.single.pkGroupUuid,
      );
      if (updated > 0) suppressed++;
    }

    return suppressed;
  }

  Future<bool> _requiresReconnectForMissingPkGroupIdentity({
    required PkRepairReferenceData? referenceData,
    required String? referenceError,
  }) async {
    if (referenceData != null) return false;
    if (referenceError != null) return false;

    final activeGroups = await _memberGroupsDao.getAllActiveGroups();
    final hasLocalPkLinkedGroups = activeGroups.any((group) {
      final pkGroupUuid = group.pluralkitUuid;
      return pkGroupUuid != null && pkGroupUuid.isNotEmpty;
    });
    if (hasLocalPkLinkedGroups) return false;

    final pkMemberUuidsByGroupId = await _memberGroupsDao
        .activePkMemberUuidsByGroupId();

    for (final group in activeGroups) {
      final pkMemberUuids = pkMemberUuidsByGroupId[group.id];
      if (pkMemberUuids == null || pkMemberUuids.isEmpty) {
        continue;
      }
      final pkGroupUuid = group.pluralkitUuid;
      if (pkGroupUuid == null || pkGroupUuid.isEmpty) {
        return true;
      }
    }

    return false;
  }

  Map<String, List<_RepairReference>> _buildReferenceGroups({
    required List<MemberGroupRow> activeGroups,
    required PkRepairReferenceData? referenceData,
    required Map<String, Set<String>> pkMemberUuidsByGroupId,
  }) {
    final grouped = <String, List<_RepairReference>>{};
    final seenPkGroupUuids = <String>{};

    void addReference(_RepairReference reference) {
      if (!seenPkGroupUuids.add(reference.pkGroupUuid)) return;
      grouped
          .putIfAbsent(reference.normalizedName, () => <_RepairReference>[])
          .add(reference);
    }

    if (referenceData != null) {
      for (final group in referenceData.groups) {
        final normalizedName = _normalizeName(group.name);
        final memberIds = group.memberIds;
        if (normalizedName == null ||
            memberIds == null ||
            memberIds.isEmpty ||
            group.uuid.isEmpty) {
          continue;
        }
        addReference(
          _RepairReference(
            pkGroupUuid: group.uuid,
            normalizedName: normalizedName,
            pkMemberUuids: memberIds.toSet(),
          ),
        );
      }
    }

    for (final group in activeGroups) {
      final pkGroupUuid = group.pluralkitUuid;
      final normalizedName = _normalizeName(group.name);
      final memberUuids = pkMemberUuidsByGroupId[group.id];
      if (pkGroupUuid == null ||
          pkGroupUuid.isEmpty ||
          normalizedName == null ||
          memberUuids == null ||
          memberUuids.isEmpty) {
        continue;
      }
      addReference(
        _RepairReference(
          pkGroupUuid: pkGroupUuid,
          normalizedName: normalizedName,
          pkMemberUuids: memberUuids,
        ),
      );
    }

    return grouped;
  }

  Map<String, Set<String>> _referencePkMembersByGroupUuid(
    PkRepairReferenceData? referenceData,
  ) {
    if (referenceData == null) return const <String, Set<String>>{};

    final grouped = <String, Set<String>>{};
    for (final group in referenceData.groups) {
      final memberIds = group.memberIds;
      if (group.uuid.isEmpty || memberIds == null) continue;
      grouped[group.uuid] = memberIds.toSet();
    }
    return grouped;
  }

  static String _canonicalPkGroupEntityId(String pkGroupUuid) =>
      'pk-group:$pkGroupUuid';

  static String? _normalizeName(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  static bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) return false;
    for (final value in left) {
      if (!right.contains(value)) return false;
    }
    return true;
  }

  static int _membershipMatchScore(
    Set<String> localPkMemberUuids,
    Set<String> candidatePkMemberUuids, {
    required int totalActiveMembershipCount,
  }) {
    var matched = 0;
    var extraPkMembers = 0;
    for (final localPkMemberUuid in localPkMemberUuids) {
      if (candidatePkMemberUuids.contains(localPkMemberUuid)) {
        matched++;
      } else {
        extraPkMembers++;
      }
    }
    final missingPkMembers = candidatePkMemberUuids.length - matched;
    final localOnlyMembers =
        totalActiveMembershipCount - localPkMemberUuids.length;
    return matched - extraPkMembers - missingPkMembers - localOnlyMembers;
  }
}

class _ReferenceResolution {
  const _ReferenceResolution({required this.mode, this.data, this.error});

  final PkGroupRepairReferenceMode mode;
  final PkRepairReferenceData? data;
  final String? error;
}

class _RepairReference {
  const _RepairReference({
    required this.pkGroupUuid,
    required this.normalizedName,
    required this.pkMemberUuids,
  });

  final String pkGroupUuid;
  final String normalizedName;
  final Set<String> pkMemberUuids;
}
