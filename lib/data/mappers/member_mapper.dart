import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;

class MemberMapper {
  MemberMapper._();

  static domain.MemberProfileHeaderSource _headerSourceFromDb(int value) {
    const values = domain.MemberProfileHeaderSource.values;
    if (value < 0 || value >= values.length) {
      return domain.MemberProfileHeaderSource.prism;
    }
    return values[value];
  }

  static domain.MemberProfileHeaderLayout _headerLayoutFromDb(int value) {
    const values = domain.MemberProfileHeaderLayout.values;
    if (value < 0 || value >= values.length) {
      return domain.MemberProfileHeaderLayout.compactBackground;
    }
    return values[value];
  }

  static domain.Member toDomain(Member row) {
    return domain.Member(
      id: row.id,
      name: row.name,
      pronouns: row.pronouns,
      emoji: row.emoji,
      age: row.age,
      bio: row.bio,
      avatarImageData: row.avatarImageData != null
          ? Uint8List.fromList(row.avatarImageData!)
          : null,
      isActive: row.isActive,
      createdAt: row.createdAt,
      displayOrder: row.displayOrder,
      isAdmin: row.isAdmin,
      customColorEnabled: row.customColorEnabled,
      customColorHex: row.customColorHex,
      parentSystemId: row.parentSystemId,
      pluralkitUuid: row.pluralkitUuid,
      pluralkitId: row.pluralkitId,
      markdownEnabled: row.markdownEnabled,
      displayName: row.displayName,
      birthday: row.birthday,
      proxyTagsJson: row.proxyTagsJson,
      pkBannerUrl: row.pkBannerUrl,
      profileHeaderSource: _headerSourceFromDb(row.profileHeaderSource),
      profileHeaderLayout: _headerLayoutFromDb(row.profileHeaderLayout),
      profileHeaderVisible: row.profileHeaderVisible,
      profileHeaderImageData: row.profileHeaderImageData != null
          ? Uint8List.fromList(row.profileHeaderImageData!)
          : null,
      pkBannerImageData: row.pkBannerImageData != null
          ? Uint8List.fromList(row.pkBannerImageData!)
          : null,
      pkBannerCachedUrl: row.pkBannerCachedUrl,
      pluralkitSyncIgnored: row.pluralkitSyncIgnored,
      isDeleted: row.isDeleted,
      deleteIntentEpoch: row.deleteIntentEpoch,
      deletePushStartedAt: row.deletePushStartedAt,
      isAlwaysFronting: row.isAlwaysFronting,
    );
  }

  static MembersCompanion toCompanion(domain.Member model) {
    return MembersCompanion(
      id: Value(model.id),
      name: Value(model.name),
      pronouns: Value(model.pronouns),
      emoji: Value(model.emoji),
      age: Value(model.age),
      bio: Value(model.bio),
      avatarImageData: Value(model.avatarImageData),
      isActive: Value(model.isActive),
      createdAt: Value(model.createdAt),
      displayOrder: Value(model.displayOrder),
      isAdmin: Value(model.isAdmin),
      customColorEnabled: Value(model.customColorEnabled),
      customColorHex: Value(model.customColorHex),
      parentSystemId: Value(model.parentSystemId),
      pluralkitUuid: Value(model.pluralkitUuid),
      pluralkitId: Value(model.pluralkitId),
      markdownEnabled: Value(model.markdownEnabled),
      displayName: Value(model.displayName),
      birthday: Value(model.birthday),
      proxyTagsJson: Value(model.proxyTagsJson),
      pkBannerUrl: Value(model.pkBannerUrl),
      profileHeaderSource: Value(model.profileHeaderSource.index),
      profileHeaderLayout: Value(model.profileHeaderLayout.index),
      profileHeaderVisible: Value(model.profileHeaderVisible),
      profileHeaderImageData: Value(model.profileHeaderImageData),
      pkBannerImageData: Value(model.pkBannerImageData),
      pkBannerCachedUrl: Value(model.pkBannerCachedUrl),
      pluralkitSyncIgnored: Value(model.pluralkitSyncIgnored),
      isDeleted: Value(model.isDeleted),
      deleteIntentEpoch: Value(model.deleteIntentEpoch),
      deletePushStartedAt: Value(model.deletePushStartedAt),
      isAlwaysFronting: Value(model.isAlwaysFronting),
    );
  }
}
