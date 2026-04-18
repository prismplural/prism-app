import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// Thrown when a PATCH/DELETE/PUSH targets a PK resource that no longer
/// exists on PK (404). Callers should treat this as "the local link is
/// stale" — clear the relevant `pluralkitId` / `pluralkitUuid` columns and
/// surface a user-visible warning so the user can re-link via the mapping
/// screen.
class PkStaleLinkException implements Exception {
  /// The local-side identifier (member.id or fronting session id) that had
  /// the stale link, so callers can route the cleanup without another lookup.
  final String localId;

  /// The PK-side identifier that returned 404, included for logging only.
  final String pkId;

  /// Which kind of link went stale — drives which local column to clear.
  final PkStaleLinkKind kind;

  final PluralKitApiError cause;

  const PkStaleLinkException({
    required this.localId,
    required this.pkId,
    required this.kind,
    required this.cause,
  });

  @override
  String toString() =>
      'PkStaleLinkException(kind=$kind, localId=$localId, pkId=$pkId, '
      'cause=$cause)';
}

enum PkStaleLinkKind { member, switchRecord }

/// Plan 02: thrown when PK rejects a DELETE with 403 — the token does not
/// own the target resource. The caller must NOT clear the local link so the
/// user can retry after fixing their token.
class PkDeletionForbiddenException implements Exception {
  final String localId;
  final String pkId;
  final PkStaleLinkKind kind;
  final PluralKitApiError cause;

  const PkDeletionForbiddenException({
    required this.localId,
    required this.pkId,
    required this.kind,
    required this.cause,
  });

  @override
  String toString() =>
      'PkDeletionForbiddenException(kind=$kind, localId=$localId, '
      'pkId=$pkId, cause=$cause)';
}

/// Pushes local Prism data to PluralKit.
class PkPushService {
  final PkRequestQueue _queue;

  PkPushService({PkRequestQueue? queue}) : _queue = queue ?? PkRequestQueue();

  /// Push a local member to PluralKit.
  ///
  /// If the member has a [pluralkitId], performs a PATCH (update).
  /// Otherwise performs a POST (create) and returns the new PK member ID.
  ///
  /// When [pkMember] is supplied (PATCH path), fields that are null locally
  /// but non-null on PK are sent as explicit `null` in the PATCH body so PK
  /// clears them. This matters because PK treats omitted keys as "preserve."
  ///
  /// Returns the PK 5-character member ID (existing or newly created).
  Future<String> pushMember(
    domain.Member member,
    PluralKitClient client, {
    PKMember? pkMember,
  }) async {
    if (member.pluralkitId != null && member.pluralkitId!.isNotEmpty) {
      // PATCH — include explicit nulls to clear fields on PK.
      final data = _memberToPayload(member, pkMember: pkMember, isPatch: true);
      try {
        final updated = await _queue.enqueue(
          () => client.updateMember(member.pluralkitId!, data),
        );
        return updated.id;
      } on PluralKitApiError catch (e) {
        if (e.statusCode == 404) {
          throw PkStaleLinkException(
            localId: member.id,
            pkId: member.pluralkitId!,
            kind: PkStaleLinkKind.member,
            cause: e,
          );
        }
        rethrow;
      }
    } else {
      // POST — create new PK member. Omit nulls (PK's POST treats omit = clear).
      final data = _memberToPayload(member, isPatch: false);
      final created = await _queue.enqueue(
        () => client.createMember(data),
      );
      return created.id;
    }
  }

  /// Push a new switch to PluralKit.
  ///
  /// [pkMemberIds] should be the PK 5-character member IDs of the fronters.
  /// [timestamp] is optional; PK defaults to the current time if omitted.
  ///
  /// A 404 from PK is wrapped as [PkStaleLinkException] with
  /// [PkStaleLinkKind.switchRecord] so callers can distinguish "this switch
  /// no longer exists on PK" from other API errors. For a create call, 404
  /// typically means one of the referenced member IDs is stale — but the
  /// caller still routes cleanup by skipping the session; it doesn't know
  /// which member is to blame, so we do not pass a [localId] that maps to
  /// a member. [localId] is set to an empty string since the switch hasn't
  /// been persisted yet.
  Future<PKSwitch> pushSwitch(
    List<String> pkMemberIds,
    PluralKitClient client, {
    DateTime? timestamp,
  }) async {
    try {
      return await _queue.enqueue(
        () => client.createSwitch(pkMemberIds, timestamp: timestamp),
      );
    } on PluralKitApiError catch (e) {
      if (e.statusCode == 404) {
        throw PkStaleLinkException(
          localId: '',
          pkId: pkMemberIds.isEmpty ? '' : pkMemberIds.first,
          kind: PkStaleLinkKind.switchRecord,
          cause: e,
        );
      }
      rethrow;
    }
  }

  /// Convert a local Member to a PK-compatible JSON payload.
  ///
  /// Skips avatar (blob-to-URL conversion not supported by PK API).
  ///
  /// For PATCH ([isPatch] = true), fields that are null locally but non-null
  /// on [pkMember] are serialized as explicit `null` so PK clears them.
  /// Fields that are null on both sides are omitted. For POST, nulls are
  /// always omitted (PK treats omit = clear on POST).
  Map<String, dynamic> _memberToPayload(
    domain.Member member, {
    PKMember? pkMember,
    required bool isPatch,
  }) {
    final data = <String, dynamic>{
      'name': member.name,
    };

    _setOrClear(
      data,
      'display_name',
      local: member.displayName,
      remote: pkMember?.displayName,
      isPatch: isPatch,
    );
    _setOrClear(
      data,
      'pronouns',
      local: member.pronouns,
      remote: pkMember?.pronouns,
      isPatch: isPatch,
    );
    _setOrClear(
      data,
      'description',
      local: member.bio,
      remote: pkMember?.description,
      isPatch: isPatch,
    );
    _setOrClear(
      data,
      'birthday',
      local: member.birthday,
      remote: pkMember?.birthday,
      isPatch: isPatch,
    );

    // proxy_tags intentionally omitted — pull-only today.
    // See docs/plans/pk-sp-gaps/01-pk-proxy-tags.md before adding a push path.

    // Color — PK expects 6-char hex with no '#'. When local color is
    // disabled, skip color entirely. Toggling local color off must not
    // silently clear PK's color as a side effect; an explicit "clear PK
    // color" path would need dedicated UI.
    if (member.customColorEnabled && member.customColorHex != null) {
      data['color'] = _stripHash(member.customColorHex!);
    }

    return data;
  }

  /// Helper: write [key] to [data] using null-clearing semantics.
  ///
  /// - Local non-null: always set.
  /// - Local null, remote non-null, PATCH: set to explicit `null` to clear PK.
  /// - Otherwise: omit.
  void _setOrClear(
    Map<String, dynamic> data,
    String key, {
    required String? local,
    required String? remote,
    required bool isPatch,
  }) {
    if (local != null) {
      data[key] = local;
      return;
    }
    if (isPatch && remote != null) {
      data[key] = null;
    }
  }

  String _stripHash(String color) =>
      color.startsWith('#') ? color.substring(1) : color;

  // -- Plan 02: deletions -----------------------------------------------------

  /// Push a member deletion to PluralKit. Returns normally on 204 and 404
  /// (both treated as "gone on PK" — caller clears the local link). Throws
  /// [PkDeletionForbiddenException] on 403 so the caller can skip the link
  /// clear and surface a message. Other errors propagate.
  ///
  /// [localId] is the Prism-side member id; [pkId] is PK's 5-char short id.
  /// Callers MUST apply the R2 re-read guard immediately before invoking
  /// this; the service intentionally has no DB access.
  Future<void> pushMemberDeletion(
    String localId,
    String pkId,
    PluralKitClient client,
  ) async {
    try {
      await _queue.enqueue(() => client.deleteMember(pkId));
    } on PluralKitApiError catch (e) {
      if (e.statusCode == 404) {
        // Treat as success — caller's guard already confirmed the epoch is
        // current, so this 404 is "already deleted" rather than "wrong
        // account". R4 is enforced at the orchestration layer (caller only
        // invokes this after the R1 guard passes).
        return;
      }
      if (e.statusCode == 403) {
        throw PkDeletionForbiddenException(
          localId: localId,
          pkId: pkId,
          kind: PkStaleLinkKind.member,
          cause: e,
        );
      }
      rethrow;
    }
  }

  /// Push a switch deletion. Same 204/404/403 semantics as
  /// [pushMemberDeletion].
  Future<void> pushSwitchDeletion(
    String localId,
    String pkUuid,
    PluralKitClient client,
  ) async {
    try {
      await _queue.enqueue(() => client.deleteSwitch(pkUuid));
    } on PluralKitApiError catch (e) {
      if (e.statusCode == 404) {
        return;
      }
      if (e.statusCode == 403) {
        throw PkDeletionForbiddenException(
          localId: localId,
          pkId: pkUuid,
          kind: PkStaleLinkKind.switchRecord,
          cause: e,
        );
      }
      rethrow;
    }
  }
}
