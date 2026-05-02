import 'package:prism_plurality/domain/models/fronting_session.dart';

/// Typed draft for creating a new session.
class FrontingSessionDraft {
  final String? memberId; // null = Unknown fronter
  final DateTime start;
  final DateTime? end; // null = active session
  final String? notes;
  final int? confidenceIndex;
  final SessionType sessionType;
  final SleepQuality? quality;
  final bool isHealthKitImport;

  const FrontingSessionDraft({
    required this.memberId,
    required this.start,
    this.end,
    this.notes,
    this.confidenceIndex,
    this.sessionType = SessionType.normal,
    this.quality,
    this.isHealthKitImport = false,
  });
}

/// Typed patch for updating an existing session.
/// Only non-null fields are applied. Use clearX flags to explicitly set to null.
class FrontingSessionPatch {
  final DateTime? start;
  final DateTime? end;
  final bool clearEnd; // explicitly set end to null (make active)
  final String? memberId;
  final bool clearMemberId; // explicitly set to null (make unknown)
  final String? notes;
  final int? confidenceIndex;

  const FrontingSessionPatch({
    this.start,
    this.end,
    this.clearEnd = false,
    this.memberId,
    this.clearMemberId = false,
    this.notes,
    this.confidenceIndex,
  });

  bool get isEmpty =>
      start == null &&
      end == null &&
      !clearEnd &&
      memberId == null &&
      !clearMemberId &&
      notes == null &&
      confidenceIndex == null;
}

/// Sealed type for session mutations.
/// Used by both edit guards (Track B) and sanitization fixes (Track C).
sealed class FrontingSessionChange {
  const FrontingSessionChange();
}

class CreateSessionChange extends FrontingSessionChange {
  final FrontingSessionDraft session;
  const CreateSessionChange(this.session);
}

class UpdateSessionChange extends FrontingSessionChange {
  final String sessionId;
  final FrontingSessionPatch patch;
  const UpdateSessionChange({required this.sessionId, required this.patch});
}

class DeleteSessionChange extends FrontingSessionChange {
  final String sessionId;
  const DeleteSessionChange(this.sessionId);
}
