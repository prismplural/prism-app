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
  /// Returns the PK 5-character member ID (existing or newly created).
  Future<String> pushMember(
    domain.Member member,
    PluralKitClient client,
  ) async {
    final data = _memberToPayload(member);

    if (member.pluralkitId != null && member.pluralkitId!.isNotEmpty) {
      // Update existing PK member
      final updated = await _queue.enqueue(
        () => client.updateMember(member.pluralkitId!, data),
      );
      return updated.id;
    } else {
      // Create new PK member
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
  Map<String, dynamic> _memberToPayload(domain.Member member) {
    final data = <String, dynamic>{
      'name': member.name,
    };

    if (member.pronouns != null) {
      data['pronouns'] = member.pronouns;
    }
    if (member.bio != null) {
      data['description'] = member.bio;
    }
    if (member.customColorHex != null && member.customColorEnabled) {
      // PK expects color without '#' prefix
      var color = member.customColorHex!;
      if (color.startsWith('#')) {
        color = color.substring(1);
      }
      data['color'] = color;
    }

    return data;
  }
}
