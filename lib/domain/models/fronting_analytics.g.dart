// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fronting_analytics.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FrontingAnalytics _$FrontingAnalyticsFromJson(Map<String, dynamic> json) =>
    _FrontingAnalytics(
      rangeStart: DateTime.parse(json['rangeStart'] as String),
      rangeEnd: DateTime.parse(json['rangeEnd'] as String),
      totalTrackedTime: Duration(
        microseconds: (json['totalTrackedTime'] as num).toInt(),
      ),
      totalGapTime: Duration(
        microseconds: (json['totalGapTime'] as num).toInt(),
      ),
      totalSessions: (json['totalSessions'] as num).toInt(),
      uniqueFronters: (json['uniqueFronters'] as num).toInt(),
      switchesPerDay: (json['switchesPerDay'] as num).toDouble(),
      memberStats: (json['memberStats'] as List<dynamic>)
          .map((e) => MemberAnalytics.fromJson(e as Map<String, dynamic>))
          .toList(),
      dailyActivity:
          (json['dailyActivity'] as List<dynamic>?)
              ?.map((e) => DailyActivity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      topCoFrontingPairs:
          (json['topCoFrontingPairs'] as List<dynamic>?)
              ?.map((e) => CoFrontingPair.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$FrontingAnalyticsToJson(_FrontingAnalytics instance) =>
    <String, dynamic>{
      'rangeStart': instance.rangeStart.toIso8601String(),
      'rangeEnd': instance.rangeEnd.toIso8601String(),
      'totalTrackedTime': instance.totalTrackedTime.inMicroseconds,
      'totalGapTime': instance.totalGapTime.inMicroseconds,
      'totalSessions': instance.totalSessions,
      'uniqueFronters': instance.uniqueFronters,
      'switchesPerDay': instance.switchesPerDay,
      'memberStats': instance.memberStats,
      'dailyActivity': instance.dailyActivity,
      'topCoFrontingPairs': instance.topCoFrontingPairs,
    };

_MemberAnalytics _$MemberAnalyticsFromJson(Map<String, dynamic> json) =>
    _MemberAnalytics(
      memberId: json['memberId'] as String,
      totalTime: Duration(microseconds: (json['totalTime'] as num).toInt()),
      percentageOfTotal: (json['percentageOfTotal'] as num).toDouble(),
      sessionCount: (json['sessionCount'] as num).toInt(),
      averageDuration: Duration(
        microseconds: (json['averageDuration'] as num).toInt(),
      ),
      medianDuration: Duration(
        microseconds: (json['medianDuration'] as num).toInt(),
      ),
      shortestSession: Duration(
        microseconds: (json['shortestSession'] as num).toInt(),
      ),
      longestSession: Duration(
        microseconds: (json['longestSession'] as num).toInt(),
      ),
      timeOfDayBreakdown: Map<String, int>.from(
        json['timeOfDayBreakdown'] as Map,
      ),
    );

Map<String, dynamic> _$MemberAnalyticsToJson(_MemberAnalytics instance) =>
    <String, dynamic>{
      'memberId': instance.memberId,
      'totalTime': instance.totalTime.inMicroseconds,
      'percentageOfTotal': instance.percentageOfTotal,
      'sessionCount': instance.sessionCount,
      'averageDuration': instance.averageDuration.inMicroseconds,
      'medianDuration': instance.medianDuration.inMicroseconds,
      'shortestSession': instance.shortestSession.inMicroseconds,
      'longestSession': instance.longestSession.inMicroseconds,
      'timeOfDayBreakdown': instance.timeOfDayBreakdown,
    };

_DailyActivity _$DailyActivityFromJson(Map<String, dynamic> json) =>
    _DailyActivity(
      date: DateTime.parse(json['date'] as String),
      totalMinutes: (json['totalMinutes'] as num).toInt(),
      sessionCount: (json['sessionCount'] as num).toInt(),
    );

Map<String, dynamic> _$DailyActivityToJson(_DailyActivity instance) =>
    <String, dynamic>{
      'date': instance.date.toIso8601String(),
      'totalMinutes': instance.totalMinutes,
      'sessionCount': instance.sessionCount,
    };

_CoFrontingPair _$CoFrontingPairFromJson(Map<String, dynamic> json) =>
    _CoFrontingPair(
      memberIdA: json['memberIdA'] as String,
      memberIdB: json['memberIdB'] as String,
      totalTime: Duration(microseconds: (json['totalTime'] as num).toInt()),
    );

Map<String, dynamic> _$CoFrontingPairToJson(_CoFrontingPair instance) =>
    <String, dynamic>{
      'memberIdA': instance.memberIdA,
      'memberIdB': instance.memberIdB,
      'totalTime': instance.totalTime.inMicroseconds,
    };
