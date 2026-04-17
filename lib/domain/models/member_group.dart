import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_group.freezed.dart';
part 'member_group.g.dart';

@freezed
abstract class MemberGroup with _$MemberGroup {
  const factory MemberGroup({
    required String id,
    required String name,
    String? description,
    String? colorHex,
    String? emoji,
    @Default(0) int displayOrder,
    String? parentGroupId,
    @Default(0) int groupType,
    String? filterRules,
    required DateTime createdAt,
  }) = _MemberGroup;

  factory MemberGroup.fromJson(Map<String, dynamic> json) =>
      _$MemberGroupFromJson(json);
}
