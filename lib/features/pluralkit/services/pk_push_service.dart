import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_request_queue.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

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
      final updated = await _queue.enqueue(
        () => client.updateMember(member.pluralkitId!, data),
      );
      return updated.id;
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
  Future<PKSwitch> pushSwitch(
    List<String> pkMemberIds,
    PluralKitClient client, {
    DateTime? timestamp,
  }) async {
    return _queue.enqueue(
      () => client.createSwitch(pkMemberIds, timestamp: timestamp),
    );
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
}
