import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';

/// A fetched PK member that declares a `system`
/// (only `GET /members/{ref}` does) different from the connected system is a
/// FOREIGN member resolved through the global short-id namespace
/// (2026-06 PK audit H12a). Treat it as
/// a stale link rather than reusing/refreshing it. Thrown by the one-shot push
/// service's already-linked-refresh and crash-recovery-reuse paths; the UI
/// surfaces it like any other push failure (re-link via the mapping screen).
class PkForeignMemberException implements Exception {
  final String pkRef;
  final String ownerSystem;
  final String connectedSystem;
  const PkForeignMemberException({
    required this.pkRef,
    required this.ownerSystem,
    required this.connectedSystem,
  });

  @override
  String toString() =>
      'PkForeignMemberException: PK member $pkRef belongs to system '
      '$ownerSystem, not the connected system $connectedSystem; its short id '
      'is stale. Re-link via the mapping screen.';
}

/// Thrown when a one-shot push is requested for a member that already has
/// a push in-flight from this app instance. UI surfaces (banner row +
/// dialog confirm + retry tap) can race; the second caller should treat
/// this as "another path is handling it, do nothing" — typically a no-op
/// snackbar.
class PkOneShotPushBusyException implements Exception {
  const PkOneShotPushBusyException();

  @override
  String toString() =>
      'PkOneShotPushBusyException: another one-shot push for this member is '
      'already in flight.';
}

/// Deterministic state-row key for this flow's crash-recovery state.
///
/// Intentionally NOT shared with `PkMappingApplier`'s `PkPushNewDecision.id`
/// (`'push:$memberId'`). If we shared the key and marked it `applied`, the
/// mapping applier's `_applyOne` would later short-circuit on the same row
/// (`alreadyApplied`) even when the local PK link has since been cleared and
/// the user wants the mapping screen to re-POST. Keep the namespaces separate
/// so each flow owns its own state-row lifecycle.
String _pushStateId(String memberId) => 'one_shot_push:$memberId';

/// One-shot push of a single local member to PluralKit, decoupled from
/// the global sync settings (`PkSyncDirection`, `PkSyncMode`).
///
/// Invariants (per plan rev 4 §"One-time push wiring"):
/// - Does NOT mutate `pkSyncDirectionProvider`, `pkSyncModeProvider`, or
///   the `pluralkit_sync_state` row. Push remains "disabled" globally
///   after this runs.
/// - Writes a `pk_mapping_state` row (id = `'push:$memberId'`,
///   decisionType `'push'`) so a crash between the PK POST and the
///   local writeback doesn't yield a duplicate POST on retry — the
///   mapping-applier short-circuits in `_applyPushNew` reuse the row,
///   and so do we via [_runPush].
/// - Aborts the local writeback (PK row stays orphaned — acceptable
///   v1 hazard) if the local member was deleted, marked Keep-local, or
///   linked by another path between the POST and the writeback.
/// - Does NOT touch `pluralkitSyncIgnored` — writing `false` would
///   clobber a concurrent Keep-local set, and we already validated it
///   was false before POSTing.
/// - Per-member [_inFlight] lock prevents two concurrent pushes for the
///   same member from racing into duplicate POSTs.
///
/// All Riverpod dependencies are read in the method body (`ref.read`),
/// never `ref.watch` at construction — keeps the provider stable so
/// [_inFlight] survives unrelated rebuilds.
class PkOneShotPushService {
  final Ref _ref;
  final PkPushService _pushService;
  final Set<String> _inFlight = <String>{};

  PkOneShotPushService(this._ref, {PkPushService? pushService})
      : _pushService = pushService ?? const PkPushService();

  /// Push [memberId] to PluralKit, returning the resulting [PKMember].
  ///
  /// Throws:
  /// - [PkOneShotPushBusyException] if another push is in-flight for the
  ///   same member.
  /// - [PkSyncMigrationGatedException] if the per-member fronting
  ///   migration is in progress.
  /// - [StateError] if PluralKit is not connected, or the member is
  ///   missing/deleted/Keep-local at entry.
  /// - Any [PluralKitClient] / [PkPushService] error (including
  ///   `PkStaleLinkException`, PK 401/403/429) verbatim.
  Future<PKMember> pushSingleMember(String memberId) async {
    if (_inFlight.contains(memberId)) {
      throw const PkOneShotPushBusyException();
    }
    if (_ref.read(frontingMigrationWritesBlockedProvider)) {
      throw const PkSyncMigrationGatedException();
    }
    _inFlight.add(memberId);
    try {
      final syncSvc = _ref.read(pluralKitSyncServiceProvider);
      final client = await syncSvc.buildClientIfConnected();
      if (client == null) {
        throw StateError('PluralKit is not connected');
      }
      try {
        return await _runPush(memberId, client);
      } finally {
        client.dispose();
      }
    } finally {
      _inFlight.remove(memberId);
    }
  }

  /// Reject a fetched member whose owning `system`
  /// (present only on `GET /members/{ref}`) differs from the connected system.
  /// Reads the connected system id lazily from the sync DAO — when it's unknown
  /// (no row, blank) we keep current behavior, exactly like the resolver.
  Future<void> _requireOwnership(PKMember fetched, String ref) async {
    final owner = fetched.system?.trim();
    if (owner == null || owner.isEmpty) return;
    final syncRow = await _ref.read(pluralKitSyncDaoProvider).getSyncState();
    final connected = syncRow.systemId?.trim();
    if (connected == null || connected.isEmpty) return;
    // PK hids are case-insensitive — compare lowercased (H2 convention).
    if (owner.toLowerCase() != connected.toLowerCase()) {
      throw PkForeignMemberException(
        pkRef: ref,
        ownerSystem: owner,
        connectedSystem: connected,
      );
    }
  }

  Future<PKMember> _runPush(String memberId, PluralKitClient client) async {
    final repo = _ref.read(memberRepositoryProvider);
    final mappingState = _ref.read(pkMappingStateDaoProvider);
    final stateId = _pushStateId(memberId);

    final member = await repo.getMemberById(memberId);
    if (member == null || member.isDeleted) {
      throw StateError('Member $memberId not available for push');
    }
    if (member.pluralkitSyncIgnored) {
      throw StateError('Member is marked Keep local; refuse to push');
    }
    if (hasPluralKitLink(member)) {
      // Already linked — fetch fresh PK data so callers can react (e.g.
      // refresh local cache from server-authoritative fields). UUID is
      // preferred since it's stable; fall back to short id.
      final ref =
          (member.pluralkitUuid?.isNotEmpty ?? false)
              ? member.pluralkitUuid!
              : member.pluralkitId!;
      final fetched = await client.getMember(ref);
      // If we fell back to the short id and PK returned
      // a member owned by a DIFFERENT system, the short id is stale (foreign).
      // Refuse to hand back foreign data as this member's refresh.
      await _requireOwnership(fetched, ref);
      return fetched;
    }

    // Crash-recovery: same row key as the mapping-applier's `PkPushNewDecision`
    // (`'push:$memberId'`). Only reuse rows whose previous attempt did NOT
    // finish the local writeback — those are the rows that risk a duplicate
    // POST on retry. Already-`applied` rows belong to a successful prior push
    // whose local link has since been cleared (e.g. user unlinked via the
    // mapping screen); for those, this is a fresh push, not a retry. Mirrors
    // `pk_mapping_applier.dart` `_applyPushNew` reuse branch.
    final prior = await mappingState.getById(stateId);
    if (prior != null &&
        prior.pkMemberUuid != null &&
        prior.status == 'pending') {
      final existing = await client.getMember(prior.pkMemberUuid!);
      // The recovery ref is a UUID (stable), so a
      // mismatch here is unlikely, but validate defensively — never link a
      // member owned by another system into our local row.
      await _requireOwnership(existing, prior.pkMemberUuid!);
      await _linkBackLocally(memberId, existing);
      return existing;
    }

    final created = await _pushService.pushMemberFull(member, client);

    // Persist the returned PK identifiers BEFORE the local writeback so a
    // crash between here and the member update is recoverable on retry via
    // the short-circuit above. Mirrors `pk_mapping_applier.dart`'s
    // `_applyPushNew` upsert ordering.
    final now = DateTime.now().toUtc();
    await mappingState.upsert(
      PkMappingStateCompanion(
        id: Value(stateId),
        decisionType: const Value('push'),
        pkMemberId: Value(created.id),
        pkMemberUuid: Value(created.uuid),
        localMemberId: Value(memberId),
        status: const Value('pending'),
        createdAt: Value(prior?.createdAt ?? now),
        updatedAt: Value(now),
      ),
    );

    await _linkBackLocally(memberId, created);
    return created;
  }

  /// Writes the PK identifiers back to the local member, with race +
  /// tombstone guards re-read at the last possible moment.
  ///
  /// Aborts (and marks the `pk_mapping_state` row `failed` with a
  /// descriptive message) if any of the following changed between the
  /// initial check and now:
  /// - the local member was hard-deleted (`fresh == null`)
  /// - the local member was soft-deleted (`fresh.isDeleted == true`) —
  ///   `getMemberById` does NOT filter tombstones, so this is the real case
  /// - another path linked the member in the meantime (`hasPluralKitLink`)
  ///
  /// If the user picked "Keep local" mid-push the writeback records the
  /// PK identifiers via `recordPluralKitIdentity` so a future "Resume sync"
  /// picks up the established identity without re-creating, while
  /// `pluralkitSyncIgnored` stays true.
  ///
  /// In abort cases the PK member stays created server-side (orphaned) —
  /// documented v1 hazard; cleanup is a separate ticket.
  Future<void> _linkBackLocally(String memberId, PKMember pk) async {
    final repo = _ref.read(memberRepositoryProvider);
    final mappingState = _ref.read(pkMappingStateDaoProvider);
    final stateId = _pushStateId(memberId);

    final fresh = await repo.getMemberById(memberId);
    if (fresh == null || fresh.isDeleted) {
      await mappingState.markFailed(
        stateId,
        'Local member deleted before push completed; PK member orphaned.',
      );
      return;
    }
    if (hasPluralKitLink(fresh)) {
      // Another path linked it. The link is correct from the user's
      // perspective; treat the row as applied.
      await mappingState.markApplied(stateId);
      return;
    }

    // recordPluralKitIdentity (not applyPluralKitLink): writes the PK
    // identifiers without touching `pluralkitSyncIgnored`, so a
    // concurrent Keep-local set isn't clobbered.
    final affected = await repo.recordPluralKitIdentity(fresh.id, {
      'pluralkit_uuid': pk.uuid,
      'pluralkit_id': pk.id,
    });
    if (affected == 0) {
      // Row tombstoned between getMemberById and write — PK has the
      // member, Prism doesn't. Surface as failed so cleanup notices.
      await mappingState.markFailed(
        stateId,
        'Local member ${fresh.id} disappeared during push; PK member orphaned.',
      );
      return;
    }
    await mappingState.markApplied(stateId);
  }
}
