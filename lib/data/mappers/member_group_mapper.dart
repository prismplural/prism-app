import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;

class MemberGroupMapper {
  MemberGroupMapper._();

  static domain.MemberGroup toDomain(MemberGroupRow row) {
    return domain.MemberGroup(
      id: row.id,
      name: row.name,
      description: row.description,
      colorHex: row.colorHex,
      emoji: row.emoji,
      displayOrder: row.displayOrder,
      parentGroupId: row.parentGroupId,
      groupType: row.groupType,
      filterRules: row.filterRules,
      createdAt: row.createdAt,
    );
  }

  static MemberGroupsCompanion toCompanion(domain.MemberGroup model) {
    return MemberGroupsCompanion(
      id: Value(model.id),
      name: Value(model.name),
      description: Value(model.description),
      colorHex: Value(model.colorHex),
      emoji: Value(model.emoji),
      displayOrder: Value(model.displayOrder),
      parentGroupId: Value(model.parentGroupId),
      groupType: Value(model.groupType),
      filterRules: Value(model.filterRules),
      createdAt: Value(model.createdAt),
    );
  }
}
