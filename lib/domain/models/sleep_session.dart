import 'package:freezed_annotation/freezed_annotation.dart';

part 'sleep_session.freezed.dart';
part 'sleep_session.g.dart';

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

@freezed
abstract class SleepSession with _$SleepSession {
  const SleepSession._();

  const factory SleepSession({
    required String id,
    required DateTime startTime,
    DateTime? endTime,
    @Default(SleepQuality.unknown) SleepQuality quality,
    String? notes,
    @Default(false) bool isHealthKitImport,
  }) = _SleepSession;

  bool get isActive => endTime == null;

  Duration get duration =>
      (endTime ?? DateTime.now()).difference(startTime);

  factory SleepSession.fromJson(Map<String, dynamic> json) =>
      _$SleepSessionFromJson(json);
}
