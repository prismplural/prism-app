import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';

bool hasPluralKitLink(Member member) =>
    _hasText(member.pluralkitUuid) || _hasText(member.pluralkitId);

/// True when [member]'s PK fields resolve against a PK member present in the
/// caller's snapshot. False when fields are empty OR the values don't appear
/// in the snapshot (i.e. unresolved — typically because the local was
/// previously linked to a member in a different PK system, e.g. inherited via
/// Simply Plural import).
///
/// Callers MUST pass sets derived from a freshly-fetched and COMPLETE PK
/// member list. PK currently returns all members in a single response — if
/// pagination is added in the future, this predicate's correctness depends
/// on the caller assembling the full list before invoking.
bool hasResolvablePluralKitLink(
  Member member, {
  required Set<String> fetchedPkUuids,
  required Set<String> fetchedPkIds,
}) {
  final uuid = member.pluralkitUuid?.trim();
  final id = member.pluralkitId?.trim();
  if ((uuid == null || uuid.isEmpty) && (id == null || id.isEmpty)) {
    return false;
  }
  if (uuid != null && uuid.isNotEmpty && fetchedPkUuids.contains(uuid)) {
    return true;
  }
  if (id != null && id.isNotEmpty && fetchedPkIds.contains(id)) {
    return true;
  }
  return false;
}

bool memberMatchesPkMember(Member member, PKMember pkMember) =>
    _sameText(member.pluralkitUuid, pkMember.uuid) ||
    _sameText(member.pluralkitId, pkMember.id);

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

bool _sameText(String? left, String right) =>
    left != null && left.trim().isNotEmpty && left.trim() == right;
