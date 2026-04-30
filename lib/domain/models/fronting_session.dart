import 'package:freezed_annotation/freezed_annotation.dart';

part 'fronting_session.freezed.dart';
part 'fronting_session.g.dart';

enum FrontConfidence { unsure, strong, certain }

enum SleepQuality { unknown, veryPoor, poor, fair, good, excellent }

enum SessionType { normal, sleep }

@freezed
abstract class FrontingSession with _$FrontingSession {
  const FrontingSession._();

  const factory FrontingSession({
    required String id,
    required DateTime startTime,
    DateTime? endTime,
    String? memberId,
    String? notes,
    FrontConfidence? confidence,
    String? pluralkitUuid,
    String? pkImportSource,
    String? pkFileSwitchId,
    @Default(SessionType.normal) SessionType sessionType,
    SleepQuality? quality,
    @Default(false) bool isHealthKitImport,
    // Plan 02 (PK deletion push). See Member for rationale.
    @Default(false) bool isDeleted,
    int? deleteIntentEpoch,
    int? deletePushStartedAt,
  }) = _FrontingSession;

  bool get isActive => endTime == null;

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  bool get isSleep => sessionType == SessionType.sleep;

  /// Deprecated: in the per-member shape, "is this row part of a co-front?"
  /// is computed from overlapping sessions rather than carried on the row
  /// itself. Use `sessionsCoFront` in
  /// `features/fronting/services/co_front_detector.dart`.
  @Deprecated(
    'Use sessionsCoFront from features/fronting/services/co_front_detector.dart.',
  )
  bool get isCoFronting => false;

  factory FrontingSession.fromJson(Map<String, dynamic> json) =>
      _$FrontingSessionFromJson(json);
}
