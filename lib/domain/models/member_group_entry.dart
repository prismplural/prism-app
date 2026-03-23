import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_group_entry.freezed.dart';
part 'member_group_entry.g.dart';

@freezed
abstract class MemberGroupEntry with _$MemberGroupEntry {
  const factory MemberGroupEntry({
    required String id,
    required String groupId,
    required String memberId,
  }) = _MemberGroupEntry;

  factory MemberGroupEntry.fromJson(Map<String, dynamic> json) =>
      _$MemberGroupEntryFromJson(json);
}
