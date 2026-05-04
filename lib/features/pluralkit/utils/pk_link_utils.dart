import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';

bool hasPluralKitLink(Member member) =>
    _hasText(member.pluralkitUuid) || _hasText(member.pluralkitId);

bool memberMatchesPkMember(Member member, PKMember pkMember) =>
    _sameText(member.pluralkitUuid, pkMember.uuid) ||
    _sameText(member.pluralkitId, pkMember.id);

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

bool _sameText(String? left, String right) =>
    left != null && left.trim().isNotEmpty && left.trim() == right;
