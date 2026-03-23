import 'package:freezed_annotation/freezed_annotation.dart';

part 'fronting_session.freezed.dart';
part 'fronting_session.g.dart';

enum FrontConfidence {
  unsure,
  strong,
  certain,
}

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
  }) = _FrontingSession;

  bool get isActive => endTime == null;

  Duration get duration =>
      (endTime ?? DateTime.now()).difference(startTime);

  bool get isCoFronting => coFronterIds.isNotEmpty;

  factory FrontingSession.fromJson(Map<String, dynamic> json) =>
      _$FrontingSessionFromJson(json);
}
