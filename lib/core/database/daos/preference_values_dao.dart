import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/app_preference_values_table.dart';
import 'package:prism_plurality/core/database/tables/member_profile_preference_values_table.dart';
import 'package:prism_plurality/core/database/tables/members_table.dart';

part 'preference_values_dao.g.dart';

@DriftAccessor(
  tables: [AppPreferenceValues, MemberProfilePreferenceValues, Members],
)
class PreferenceValuesDao extends DatabaseAccessor<AppDatabase>
    with _$PreferenceValuesDaoMixin {
  PreferenceValuesDao(super.db);

  Future<AppPreferenceValueRow?> getAppValue(String key) => (select(
    appPreferenceValues,
  )..where((p) => p.key.equals(key))).getSingleOrNull();

  Stream<AppPreferenceValueRow?> watchAppValue(String key) => (select(
    appPreferenceValues,
  )..where((p) => p.key.equals(key))).watchSingleOrNull();

  Future<void> upsertAppValue(AppPreferenceValuesCompanion companion) =>
      into(appPreferenceValues).insertOnConflictUpdate(companion);

  Future<MemberProfilePreferenceValueRow?> getMemberProfileValue(String id) =>
      (select(
        memberProfilePreferenceValues,
      )..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<MemberProfilePreferenceValueRow?> watchMemberProfileValue(String id) =>
      (select(
        memberProfilePreferenceValues,
      )..where((p) => p.id.equals(id))).watchSingleOrNull();

  Stream<List<MemberProfilePreferenceValueRow>> watchMemberProfileValues(
    String memberId,
  ) =>
      (select(memberProfilePreferenceValues)..where(
            (p) => p.memberId.equals(memberId) & p.isDeleted.equals(false),
          ))
          .watch();

  Future<void> upsertMemberProfileValue(
    MemberProfilePreferenceValuesCompanion companion,
  ) => into(memberProfilePreferenceValues).insertOnConflictUpdate(companion);

  Future<bool> memberExists(String memberId) async {
    final row =
        await (select(members)
              ..where((m) => m.id.equals(memberId) & m.isDeleted.equals(false)))
            .getSingleOrNull();
    return row != null;
  }

  Future<List<MemberProfilePreferenceValueRow>> allMemberProfileValuesForMember(
    String memberId,
  ) => (select(
    memberProfilePreferenceValues,
  )..where((p) => p.memberId.equals(memberId))).get();

  Future<void> tombstoneAllMemberProfileValues(String memberId) =>
      (update(
        memberProfilePreferenceValues,
      )..where((p) => p.memberId.equals(memberId))).write(
        const MemberProfilePreferenceValuesCompanion(
          valueJson: Value(null),
          isDeleted: Value(true),
        ),
      );
}
