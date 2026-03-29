import 'package:freezed_annotation/freezed_annotation.dart';

part 'fronting_session.freezed.dart';
part 'fronting_session.g.dart';

enum FrontConfidence { unsure, strong, certain }

enum SleepQuality {
  unknown,
  veryPoor,
  poor,
  fair,
  good,
  excellent;

  String get label => switch (this) {
    SleepQuality.unknown => 'Not rated',
    SleepQuality.veryPoor => 'Very Poor',
    SleepQuality.poor => 'Poor',
    SleepQuality.fair => 'Fair',
    SleepQuality.good => 'Good',
    SleepQuality.excellent => 'Excellent',
  };
}

enum SessionType { normal, sleep }

@freezed
abstract class FrontingSession with _$FrontingSession {
  const FrontingSession._();

  const factory FrontingSession({
    required String id,
    required DateTime startTime,
    DateTime? endTime,
    String? memberId,
    @Default([]) List<String> coFronterIds,
    String? notes,
    FrontConfidence? confidence,
    String? pluralkitUuid,
    @Default(SessionType.normal) SessionType sessionType,
    SleepQuality? quality,
    @Default(false) bool isHealthKitImport,
  }) = _FrontingSession;

  bool get isActive => endTime == null;

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  bool get isCoFronting => coFronterIds.isNotEmpty;

  bool get isSleep => sessionType == SessionType.sleep;

  factory FrontingSession.fromJson(Map<String, dynamic> json) =>
      _$FrontingSessionFromJson(json);
}
