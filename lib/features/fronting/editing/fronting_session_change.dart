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

  /// Lineage marker for period-delete splits. When set, the executor
  /// reparents comments timestamped in this draft's range from the
  /// source session — same shape FrontingMutationService.splitSession
  /// uses for its split-half.
  final String? splitFromSessionId;

  /// Pre-assigned UUID instead of executor-generated. Lets later
  /// changes in the same batch reference this Create's session before
  /// it's applied (e.g. routing comments to a not-yet-created Unknown).
  final String? presetId;

  /// Partner to [splitFromSessionId]: when set, comments timestamped in
  /// the slice between the trimmed source's new end and this draft's
  /// start move to this target instead of being deleted. Used by
  /// `convertToUnknown` to keep slice comments under the Unknown row.
  final String? sliceReparentToSessionId;

  const FrontingSessionDraft({
    required this.memberId,
    required this.start,
    this.end,
    this.notes,
    this.confidenceIndex,
    this.sessionType = SessionType.normal,
    this.quality,
    this.isHealthKitImport = false,
    this.splitFromSessionId,
    this.presetId,
    this.sliceReparentToSessionId,
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

  /// After the patch applies, delete comments on this session whose
  /// timestamps fall outside the new range. Used by period-delete trim
  /// paths where the shrunken session no longer covers the slice.
  ///
  /// Don't combine with a paired `CreateSessionChange.splitFromSessionId`
  /// targeting this session — the create's own slice cleanup expects
  /// the pre-trim comments still attached to the source. Mutually
  /// exclusive with [reparentOrphansToSessionId].
  final bool dropOrphanedComments;

  /// Like [dropOrphanedComments] but reparents to the given session
  /// instead of deleting. Used by `convertToUnknown` so slice comments
  /// follow the time onto the Unknown row. The target must already
  /// exist in the repository at apply time.
  final String? reparentOrphansToSessionId;

  const FrontingSessionPatch({
    this.start,
    this.end,
    this.clearEnd = false,
    this.memberId,
    this.clearMemberId = false,
    this.notes,
    this.confidenceIndex,
    this.dropOrphanedComments = false,
    this.reparentOrphansToSessionId,
  });

  bool get isEmpty =>
      start == null &&
      end == null &&
      !clearEnd &&
      memberId == null &&
      !clearMemberId &&
      notes == null &&
      confidenceIndex == null &&
      !dropOrphanedComments &&
      reparentOrphansToSessionId == null;
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
