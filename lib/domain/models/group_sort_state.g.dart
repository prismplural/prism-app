// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_sort_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_GroupSortState _$GroupSortStateFromJson(Map<String, dynamic> json) =>
    _GroupSortState(
      mode:
          $enumDecodeNullable(_$GroupSortModeEnumMap, json['mode']) ??
          GroupSortMode.manual,
      manualOrder:
          (json['manualOrder'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );

Map<String, dynamic> _$GroupSortStateToJson(_GroupSortState instance) =>
    <String, dynamic>{
      'mode': _$GroupSortModeEnumMap[instance.mode]!,
      'manualOrder': instance.manualOrder,
    };

const _$GroupSortModeEnumMap = {
  GroupSortMode.manual: 'manual',
  GroupSortMode.nameAsc: 'nameAsc',
  GroupSortMode.nameDesc: 'nameDesc',
  GroupSortMode.recentDesc: 'recentDesc',
};
