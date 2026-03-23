// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_group_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MemberGroupEntry _$MemberGroupEntryFromJson(Map<String, dynamic> json) =>
    _MemberGroupEntry(
      id: json['id'] as String,
      groupId: json['groupId'] as String,
      memberId: json['memberId'] as String,
    );

Map<String, dynamic> _$MemberGroupEntryToJson(_MemberGroupEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'groupId': instance.groupId,
      'memberId': instance.memberId,
    };
