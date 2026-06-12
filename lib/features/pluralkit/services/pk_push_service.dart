import 'dart:convert';

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/members/utils/birthday.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
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

/// Thrown when PK rejects a DELETE with 403 — the token does not
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

/// PluralKit API field caps, live-verified 2026-06-10 against
/// api.pluralkit.me (2026-06 PK audit M10b — wave 4).
///
/// Server behavior on violation: 400 with body code `40001` and a per-field
/// `errors` map carrying `max_length` / `actual_length`. Validating here
/// keeps an over-cap local value from 400-ing every sync run (the M10
/// "bricked sync" class) — the offending FIELD is dropped from the payload
/// and surfaced instead.
abstract final class PkFieldLimits {
  /// `name`, `display_name`, and `pronouns` cap (characters).
  static const int nameMaxLength = 100;
  static const int displayNameMaxLength = 100;
  static const int pronounsMaxLength = 100;

  /// `description` cap (characters).
  static const int descriptionMaxLength = 1000;

  /// `color` must be exactly 6 hex digits with no leading `#`.
  static final RegExp colorPattern = RegExp(r'^[0-9a-fA-F]{6}$');

  /// Returns `null` when [value] is a valid wire value for [pkField], or a
  /// short human-readable reason when PK would reject it with 40001.
  ///
  /// Only string-valued payload fields are validated; unknown fields pass.
  static String? validate(String pkField, String value) {
    switch (pkField) {
      case 'name':
        return _capReason(value, nameMaxLength);
      case 'display_name':
        return _capReason(value, displayNameMaxLength);
      case 'pronouns':
        return _capReason(value, pronounsMaxLength);
      case 'description':
        return _capReason(value, descriptionMaxLength);
      case 'color':
        // The payload builder has already stripped a leading '#'.
        return colorPattern.hasMatch(value)
            ? null
            : "isn't a 6-digit hex color";
      case 'birthday':
        // Strict yyyy-MM-dd shape AND a real calendar date — the raw-string
        // birthday column can carry legacy junk from old imports.
        // [parseBirthday] enforces both (incl. the 02-30 overflow reject).
        return parseBirthday(value) == null
            ? "isn't a valid yyyy-MM-dd date"
            : null;
      default:
        return null;
    }
  }

  static String? _capReason(String value, int max) => value.length > max
      ? 'is ${value.length} characters (PluralKit max $max)'
      : null;
}

/// Pushes local Prism data to PluralKit.
///
/// Rate limiting and 429 retry are handled inside [PluralKitClient] via its
/// internal request queue, so this service just calls client methods.
class PkPushService {
  const PkPushService();

  /// Push a local member to PluralKit.
  ///
  /// If the member has a [pluralkitId], performs a PATCH (update).
  /// Otherwise performs a POST (create) and returns the new PK member ID.
  ///
  /// On the PATCH path, callers that hold the PK member and per-field
  /// direction config (the bidirectional service) MUST pass [allowedFields]
  /// to gate the payload: only listed keys are serialized. Keys absent from
  /// the set are omitted entirely so PK preserves its value. This prevents
  /// H1 — a single triggering edit null-clearing unrelated PK-only fields.
  /// When [allowedFields] is null (legacy PATCH callers with no PK snapshot),
  /// the payload falls back to "every local non-null field," which never
  /// emits explicit nulls because there is no remote to clear against.
  ///
  /// Returns the PK 5-character member ID (existing or newly created).
  ///
  /// [onFieldSkipped] (2026-06 PK audit M10b) is invoked once per payload
  /// field that client-side cap validation dropped (PATCH) or truncated
  /// (POST `name`), with the PK field key and a human-readable reason.
  Future<String> pushMember(
    domain.Member member,
    PluralKitClient client, {
    PKMember? pkMember,
    bool includeProxyTags = true,
    Set<String>? allowedFields,
    void Function(String pkField, String reason)? onFieldSkipped,
  }) async => (await pushMemberFull(
    member,
    client,
    pkMember: pkMember,
    includeProxyTags: includeProxyTags,
    allowedFields: allowedFields,
    onFieldSkipped: onFieldSkipped,
  )).id;

  /// Same as [pushMember], but returns PluralKit's full member payload so
  /// callers can persist both the short ID and UUID after creating a member.
  Future<PKMember> pushMemberFull(
    domain.Member member,
    PluralKitClient client, {
    PKMember? pkMember,
    bool includeProxyTags = true,
    Set<String>? allowedFields,
    void Function(String pkField, String reason)? onFieldSkipped,
  }) async {
    final pkId = member.pluralkitId?.trim();
    if (pkId != null && pkId.isNotEmpty) {
      // PATCH — only the gated fields are serialized (see [allowedFields]).
      final data = _memberToPayload(
        member,
        pkMember: pkMember,
        isPatch: true,
        includeProxyTags: includeProxyTags,
        allowedFields: allowedFields,
        onFieldSkipped: onFieldSkipped,
      );
      // PK rejects an empty PATCH body with 400. With a PK snapshot in hand
      // an empty payload is a no-op by definition — skip the call instead of
      // surfacing a spurious error mid-sync.
      if (data.isEmpty && pkMember != null) {
        return pkMember;
      }
      try {
        final updated = await client.updateMember(pkId, data);
        return updated;
      } on PluralKitApiError catch (e) {
        if (e.statusCode == 404) {
          throw PkStaleLinkException(
            localId: member.id,
            pkId: pkId,
            kind: PkStaleLinkKind.member,
            cause: e,
          );
        }
        rethrow;
      }
    } else {
      // POST — create new PK member. Omit nulls (PK's POST treats omit = clear).
      final data = _memberToPayload(
        member,
        isPatch: false,
        includeProxyTags: includeProxyTags,
        onFieldSkipped: onFieldSkipped,
      );
      final created = await client.createMember(data);
      return created;
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
      return await client.createSwitch(pkMemberIds, timestamp: timestamp);
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
  /// Field gating (PATCH only):
  /// - When [allowedFields] is supplied, a field appears in the payload ONLY
  ///   when its PK key is in the set. The caller (bidirectional service) has
  ///   already decided per-field that the value differs, push is allowed by
  ///   direction config, and it is not a would-clear; so each allowed field
  ///   is written from its local value and explicit nulls are NEVER emitted.
  ///   Field clears do not propagate from this path — see plan 08.
  /// - When [allowedFields] is null (legacy PATCH callers with no PK
  ///   snapshot), every local non-null field is included via [_setOrClear].
  ///   Explicit nulls only ever appear when a [pkMember] remote value is
  ///   present, which legacy callers don't pass, so this stays non-destructive.
  ///
  /// For POST ([isPatch] = false), nulls are always omitted (PK treats
  /// omit = clear on POST) and [allowedFields] is ignored — creates always
  /// send the member's full local non-null shape.
  ///
  /// Cap validation (2026-06 PK audit M10b): every string-valued payload
  /// entry is checked against [PkFieldLimits] before the map is returned.
  /// - PATCH: an invalid field is DROPPED from the payload (PK keeps its
  ///   value) and surfaced via [onFieldSkipped] — never silently truncated.
  /// - POST: same skip rule, EXCEPT the required `name`, which is truncated
  ///   to [PkFieldLimits.nameMaxLength] (a create must not fail forever) and
  ///   surfaced.
  /// Explicit-null clears and the `proxy_tags` list are exempt (non-string).
  Map<String, dynamic> _memberToPayload(
    domain.Member member, {
    PKMember? pkMember,
    required bool isPatch,
    required bool includeProxyTags,
    Set<String>? allowedFields,
    void Function(String pkField, String reason)? onFieldSkipped,
  }) {
    final data = <String, dynamic>{};

    // [allowedFields] gating only applies to PATCH. POST always sends the
    // full local non-null shape (gating is a no-op there).
    final gated = isPatch && allowedFields != null;
    bool include(String key) => !gated || allowedFields.contains(key);

    // Prism Name and Full Name are local-only after the PK display-name split.
    // PluralKit still requires an internal `name` for creates, so seed it
    // from Prism Name.
    if (!isPatch) {
      data['name'] = member.name;
    }

    if (include('display_name')) {
      _setOrClear(
        data,
        'display_name',
        local: member.pluralkitDisplayName,
        remote: pkMember?.displayName,
        isPatch: isPatch,
        gated: gated,
      );
    }
    if (include('pronouns')) {
      _setOrClear(
        data,
        'pronouns',
        local: member.pronouns,
        remote: pkMember?.pronouns,
        isPatch: isPatch,
        gated: gated,
      );
    }
    if (include('description')) {
      _setOrClear(
        data,
        'description',
        local: member.bio,
        remote: pkMember?.description,
        isPatch: isPatch,
        gated: gated,
      );
    }
    if (include('birthday')) {
      _setOrClear(
        data,
        'birthday',
        local: member.birthday,
        remote: pkMember?.birthday,
        isPatch: isPatch,
        gated: gated,
      );
    }

    if (includeProxyTags && include('proxy_tags')) {
      final proxyTags = _decodeProxyTags(member.proxyTagsJson);
      if (proxyTags != null) {
        data['proxy_tags'] = proxyTags;
      }
    }

    // Color — PK expects 6-char hex with no '#'. When local color is
    // disabled, skip color entirely. Toggling local color off must not
    // silently clear PK's color as a side effect; an explicit "clear PK
    // color" path would need dedicated UI.
    if (include('color') &&
        member.customColorEnabled &&
        member.customColorHex != null) {
      data['color'] = _stripHash(member.customColorHex!);
    }

    // 2026-06 PK audit M10b: validate the assembled payload against the
    // live-verified PK caps so an over-cap/garbage local value can't 400
    // (code 40001) every sync run. See the method doc for the skip-vs-
    // truncate rules per method.
    for (final key in data.keys.toList()) {
      final value = data[key];
      if (value is! String) continue; // explicit-null clears, proxy_tags list
      final reason = PkFieldLimits.validate(key, value);
      if (reason == null) continue;
      if (key == 'name' && !isPatch) {
        // `name` is required on POST — truncate instead of skipping so the
        // create can succeed; surfaced so the user knows.
        data[key] = _truncateUtf16(value, PkFieldLimits.nameMaxLength);
        onFieldSkipped?.call(
          key,
          '$reason — truncated to ${PkFieldLimits.nameMaxLength} characters '
          'for the PluralKit create',
        );
        continue;
      }
      data.remove(key);
      onFieldSkipped?.call(
        key,
        '$reason — left unchanged on PluralKit this sync',
      );
    }

    return data;
  }

  /// Truncate [value] to at most [max] UTF-16 code units (PK's server is
  /// .NET, whose string length counts the same units as Dart's). Backs off
  /// one unit when the cut would split a surrogate pair.
  String _truncateUtf16(String value, int max) {
    if (value.length <= max) return value;
    var cut = value.substring(0, max);
    final last = cut.codeUnitAt(cut.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      cut = cut.substring(0, cut.length - 1);
    }
    return cut;
  }

  /// Helper: write [key] to [data] using null-clearing semantics.
  ///
  /// - Local non-null: always set.
  /// - Local null, remote non-null, PATCH, NOT gated: set to explicit `null`
  ///   to clear PK.
  /// - Otherwise: omit.
  ///
  /// When [gated] is true the caller (bidirectional service via
  /// [allowedFields]) has pre-decided this field is includable and not a
  /// would-clear, so we never emit an explicit `null`: a null local here just
  /// omits the key rather than destroying the PK value (H1 guard).
  void _setOrClear(
    Map<String, dynamic> data,
    String key, {
    required String? local,
    required String? remote,
    required bool isPatch,
    bool gated = false,
  }) {
    if (local != null) {
      data[key] = local;
      return;
    }
    if (isPatch && !gated && remote != null) {
      data[key] = null;
    }
  }

  List<dynamic>? _decodeProxyTags(String? proxyTagsJson) {
    if (proxyTagsJson == null) return null;
    try {
      final decoded = jsonDecode(proxyTagsJson);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
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
    final trimmedPkId = pkId.trim();
    if (trimmedPkId.isEmpty) return;
    try {
      await client.deleteMember(trimmedPkId);
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
          pkId: trimmedPkId,
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
      await client.deleteSwitch(pkUuid);
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
