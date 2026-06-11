/// Structured events emitted by the PluralKit sync layer for the
/// session-scoped sync log.
///
/// Each subclass represents one operation-level event (token set, sync
/// started, rate limit hit, etc.). Events are one-way: they're emitted by
/// services, collected by [PkSyncEventLogNotifier], and surfaced in the PK
/// sync debug screen. They are never deserialized back into Dart objects, so
/// no `fromJson` is defined.
///
/// Token redaction is the responsibility of the emit site, which must route
/// any free-form error string through [PkSyncEvent.redact] before
/// constructing an event. No subclass carries a `token` field.
sealed class PkSyncEvent {
  const PkSyncEvent();

  /// English one-liner describing the event for the log's tile title.
  String get summary;

  /// JSON-serializable payload for the expandable JSON drawer.
  Map<String, dynamic> toJson();

  /// Whether the event should render with the error-color leading icon.
  /// Defaults to false; overridden by the error-bearing subclasses.
  bool get isError => false;

  /// Replaces every occurrence of [token] in [message] with `[REDACTED]`.
  /// Returns [message] unchanged when [token] is null or empty.
  static String redact(String message, String? token) {
    if (token == null || token.isEmpty) return message;
    return message.replaceAll(token, '[REDACTED]');
  }
}

class PkTokenSet extends PkSyncEvent {
  const PkTokenSet({required this.systemName, required this.systemId});

  final String systemName;
  final String systemId;

  @override
  String get summary => 'PluralKit token set ($systemName)';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkTokenSet',
        'system_name': systemName,
        'system_id': systemId,
      };
}

class PkTokenCleared extends PkSyncEvent {
  const PkTokenCleared();

  @override
  String get summary => 'PluralKit token cleared';

  @override
  Map<String, dynamic> toJson() => {'kind': 'pkTokenCleared'};
}

class PkTokenAuthFailed extends PkSyncEvent {
  const PkTokenAuthFailed();

  @override
  String get summary => 'PluralKit token rejected (auth)';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkTokenAuthFailed',
        'error_kind': 'auth',
      };

  @override
  bool get isError => true;
}

class PkSyncStarted extends PkSyncEvent {
  const PkSyncStarted({
    required this.trigger,
    required this.direction,
    required this.mode,
  });

  final String trigger;
  final String direction;
  final String mode;

  @override
  String get summary => 'Sync started ($trigger, $direction, $mode)';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkSyncStarted',
        'trigger': trigger,
        'direction': direction,
        'mode': mode,
      };
}

class PkSyncCompleted extends PkSyncEvent {
  const PkSyncCompleted({
    required this.durationMs,
    required this.pulled,
    required this.pushed,
    this.error,
  });

  final int durationMs;
  final int pulled;
  final int pushed;
  final String? error;

  @override
  String get summary {
    final err = error;
    if (err != null && err.isNotEmpty) {
      return 'Sync failed: $err';
    }
    return 'Sync completed in ${durationMs}ms (pulled $pulled, pushed $pushed)';
  }

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkSyncCompleted',
        'duration_ms': durationMs,
        'pulled': pulled,
        'pushed': pushed,
        if (error != null) 'error': error,
      };

  @override
  bool get isError => error != null && error!.isNotEmpty;
}

class PkMembersImported extends PkSyncEvent {
  const PkMembersImported({required this.count});

  final int count;

  @override
  String get summary => 'Imported $count members';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkMembersImported',
        'count': count,
      };
}

class PkSyncPullCompleted extends PkSyncEvent {
  const PkSyncPullCompleted({
    required this.pages,
    required this.fetched,
    required this.applied,
    required this.durationMs,
  });

  final int pages;
  final int fetched;
  final int applied;
  final int durationMs;

  @override
  String get summary =>
      'Pull completed: $fetched fetched, $applied applied ($pages pages, ${durationMs}ms)';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkSyncPullCompleted',
        'pages': pages,
        'fetched': fetched,
        'applied': applied,
        'duration_ms': durationMs,
      };
}

class PkSwitchPushed extends PkSyncEvent {
  const PkSwitchPushed({required this.pushed, required this.deleted});

  final int pushed;
  final int deleted;

  @override
  String get summary {
    if (pushed > 0 && deleted > 0) {
      return 'Pushed $pushed switches, $deleted deletions';
    }
    if (deleted > 0) {
      return 'Pushed $deleted switch deletions';
    }
    return 'Pushed $pushed switches';
  }

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkSwitchPushed',
        'pushed': pushed,
        'deleted': deleted,
      };
}

class PkLiveFronterApplied extends PkSyncEvent {
  const PkLiveFronterApplied({required this.memberCount});

  final int memberCount;

  @override
  String get summary => 'Live fronter updated ($memberCount member)';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkLiveFronterApplied',
        'member_count': memberCount,
      };
}

class PkLiveFronterSkipped extends PkSyncEvent {
  const PkLiveFronterSkipped({required this.reason});

  final String reason;

  @override
  String get summary => 'Live fronter skipped: $reason';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkLiveFronterSkipped',
        'reason': reason,
      };
}

class PkMappingDecisionApplied extends PkSyncEvent {
  const PkMappingDecisionApplied({
    required this.decisionId,
    required this.decisionKind,
  });

  final String decisionId;
  final String decisionKind;

  @override
  String get summary =>
      'Mapping decision applied: $decisionKind ($decisionId)';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkMappingDecisionApplied',
        'decision_id': decisionId,
        'decision_kind': decisionKind,
      };
}

class PkMappingDecisionFailed extends PkSyncEvent {
  const PkMappingDecisionFailed({
    required this.decisionId,
    required this.decisionKind,
    required this.error,
  });

  final String decisionId;
  final String decisionKind;
  final String error;

  @override
  String get summary =>
      'Mapping decision failed: $decisionKind ($decisionId) — $error';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkMappingDecisionFailed',
        'decision_id': decisionId,
        'decision_kind': decisionKind,
        'error': error,
      };

  @override
  bool get isError => true;
}

/// 2026-06 PK audit wave-3 mass-deletion breaker: emitted when an UNATTENDED
/// sync declined to execute a batch of pending PK deletions because the
/// candidate count exceeded the safety threshold. The user-confirmed manual
/// destructive-push path is unaffected; this only fires on automatic paths.
class PkMassDeletionBlocked extends PkSyncEvent {
  const PkMassDeletionBlocked({
    required this.kind,
    required this.candidateCount,
    required this.threshold,
  });

  /// `'switches'` or `'members'` — which deletion pusher tripped.
  final String kind;

  /// How many eligible deletion candidates were queued.
  final int candidateCount;

  /// The threshold that was exceeded.
  final int threshold;

  @override
  String get summary =>
      'Blocked auto-deletion of $candidateCount $kind on PluralKit '
      '(over the $threshold safety limit) — confirm a manual sync to proceed';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkMassDeletionBlocked',
        'deletion_kind': kind,
        'candidate_count': candidateCount,
        'threshold': threshold,
      };

  @override
  bool get isError => true;
}

class PkRateLimitHit extends PkSyncEvent {
  const PkRateLimitHit({required this.attempt, required this.backoffSeconds});

  final int attempt;
  final int backoffSeconds;

  @override
  String get summary =>
      'Rate limit hit (attempt $attempt, backoff ${backoffSeconds}s)';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkRateLimitHit',
        'attempt': attempt,
        'backoff_secs': backoffSeconds,
      };

  @override
  bool get isError => true;
}

class PkRequestFailed extends PkSyncEvent {
  const PkRequestFailed({
    required this.stage,
    required this.errorKind,
    required this.message,
  });

  final String stage;
  final String errorKind;
  final String message;

  @override
  String get summary => 'Request failed: $stage — $message';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkRequestFailed',
        'stage': stage,
        'error_kind': errorKind,
        'message': message,
      };

  @override
  bool get isError => true;
}

class PkAutoPollTick extends PkSyncEvent {
  const PkAutoPollTick({
    required this.outcome,
    this.reason,
    this.error,
    this.gate,
  });

  /// One of `'ok'`, `'failed'`, or `'skipped'`.
  final String outcome;

  /// Set when [outcome] is `'skipped'`.
  final String? reason;

  /// Set when [outcome] is `'failed'`. Already redacted by the emit site.
  final String? error;

  /// Diagnostic gate state for skipped auto-poll attempts. Never includes the
  /// token itself, only whether a usable local token was present.
  final Map<String, Object?>? gate;

  @override
  String get summary {
    switch (outcome) {
      case 'failed':
        return 'Auto-poll tick failed: ${error ?? ''}';
      case 'skipped':
        return 'Auto-poll tick skipped: ${reason ?? ''}';
      default:
        return 'Auto-poll tick: $outcome';
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkAutoPollTick',
        'outcome': outcome,
        if (reason != null) 'reason': reason,
        if (error != null) 'error': error,
        if (gate != null) 'gate': gate,
      };

  @override
  bool get isError => outcome == 'failed';
}

/// Reserved event type for the workmanager background task.
///
/// The event type exists so future background-isolate code can construct it,
/// but v1 does NOT emit it: `callbackDispatcher` runs in a separate isolate
/// that cannot reach the main-isolate [PkSyncEventBus]. See the sync-log spec
/// for the cross-isolate constraint.
class PkBackgroundSyncTick extends PkSyncEvent {
  const PkBackgroundSyncTick({required this.taskName});

  final String taskName;

  @override
  String get summary => 'Background sync tick: $taskName';

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'pkBackgroundSyncTick',
        'task_name': taskName,
      };
}
