import 'package:prism_plurality/core/mutations/field_patch.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';

class UpdateFrontingSessionPatch {
  const UpdateFrontingSessionPatch({
    this.startTime = const FieldPatch.absent(),
    this.endTime = const FieldPatch.absent(),
    this.memberId = const FieldPatch.absent(),
    this.coFronterIds = const FieldPatch.absent(),
    this.confidence = const FieldPatch.absent(),
    this.quality = const FieldPatch.absent(),
    this.notes = const FieldPatch.absent(),
  });

  final FieldPatch<DateTime> startTime;
  final FieldPatch<DateTime> endTime;
  final FieldPatch<String> memberId;
  final FieldPatch<List<String>> coFronterIds;
  final FieldPatch<FrontConfidence> confidence;
  final FieldPatch<SleepQuality> quality;
  final FieldPatch<String> notes;

  bool get isEmpty =>
      startTime.isAbsent &&
      endTime.isAbsent &&
      memberId.isAbsent &&
      coFronterIds.isAbsent &&
      confidence.isAbsent &&
      quality.isAbsent &&
      notes.isAbsent;

  FrontingSession applyTo(FrontingSession session) {
    return session.copyWith(
      startTime: startTime.applyTo(session.startTime) ?? session.startTime,
      endTime: endTime.applyTo(session.endTime),
      memberId: memberId.applyTo(session.memberId),
      coFronterIds:
          coFronterIds.applyTo(session.coFronterIds) ?? session.coFronterIds,
      confidence: confidence.applyTo(session.confidence),
      quality: quality.applyTo(session.quality),
      notes: notes.applyTo(session.notes),
    );
  }
}
