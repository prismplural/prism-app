/// Disposition for an SP custom front during import.
///
/// SP's "custom fronts" are status-like pseudo-members ("Co-fronting",
/// "Asleep", "Blurry", etc.) that Prism has no native concept for. The user
/// picks one of these options per CF during import, and the mapper uses the
/// per-CF choice to decide whether to create a member, preserve it as a note,
/// convert it to a sleep session, or drop it entirely.
enum CfDisposition {
  /// Create a tagged member for the CF (current legacy behavior).
  importAsMember,

  /// Drop the member; append the CF name to affected session notes.
  mergeAsNote,

  /// Emit front-history entries with this CF as primary as
  /// [SessionType.sleep] sessions.
  convertToSleep,

  /// Drop the CF entirely: no member, no note, and sessions whose primary
  /// is this CF with no promotable co-fronters are dropped.
  skip,
}

/// Per-CF usage statistics counted across a parsed SP export.
class CfUsageStats {
  /// Times the CF appears as primary fronter in front history.
  final int asPrimary;

  /// Times the CF appears in a co-fronter list in front history.
  final int asCoFronter;

  /// Times the CF is the target of an automated timer (type == 1).
  final int asTimerTarget;

  const CfUsageStats({
    this.asPrimary = 0,
    this.asCoFronter = 0,
    this.asTimerTarget = 0,
  });

  int get total => asPrimary + asCoFronter + asTimerTarget;
}

/// Default disposition suggestion paired with a short English reason the UI
/// can display verbatim.
class CfSuggestion {
  final CfDisposition disposition;
  final String reason;

  const CfSuggestion({
    required this.disposition,
    required this.reason,
  });
}

/// Resolved per-CF state built once at mapper init, before any mapping
/// happens. [prismMemberId] is non-null iff [disposition] is
/// [CfDisposition.importAsMember].
class CfResolved {
  final String spId;
  final String name;
  final CfDisposition disposition;
  final String? prismMemberId;

  const CfResolved({
    required this.spId,
    required this.name,
    required this.disposition,
    this.prismMemberId,
  });
}
