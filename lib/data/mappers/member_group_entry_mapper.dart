import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart' as domain;

class MemberGroupEntryMapper {
  MemberGroupEntryMapper._();

  static domain.MemberGroupEntry toDomain(MemberGroupEntryRow row) {
    return domain.MemberGroupEntry(
      id: row.id,
      groupId: row.groupId,
      memberId: row.memberId,
    );
  }

  static MemberGroupEntriesCompanion toCompanion(
      domain.MemberGroupEntry model) {
    return MemberGroupEntriesCompanion(
      id: Value(model.id),
      groupId: Value(model.groupId),
      memberId: Value(model.memberId),
    );
  }
}
