import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/sqlite_constraint.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/core/services/secure_storage.dart'
    as storage_config;
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_import_source.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_bidirectional_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_avatar_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_fronting_switch_matcher.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_live_fronter_resolution_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_session_id.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_switch_cursor.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';
import 'package:prism_plurality/shared/utils/avatar_fetcher.dart';

final RegExp _pluralKitSwitchUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

@visibleForTesting
bool isPluralKitSwitchUuid(String? value) {
  final trimmed = value?.trim();
  return trimmed != null &&
      trimmed.isNotEmpty &&
      _pluralKitSwitchUuidPattern.hasMatch(trimmed);
}

/// Truncate a PK timestamp to whole-second precision — the precision Drift
/// persists datetime columns at.
///
/// Drift stores `dateTime()` as unix seconds while PK timestamps carry µs, so
/// untruncated values re-diff as "changed" on every reprocess. Truncate at the
/// persistence boundary only; the fetch side keeps µs because truncating would
/// break the strictly-exclusive `t < before` paging contract.
DateTime truncatePkTimestampToDriftPrecision(DateTime timestamp) {
  final utc = timestamp.toUtc();
  final micros = utc.microsecondsSinceEpoch;
  final wholeSeconds = micros - (micros % Duration.microsecondsPerSecond);
  return DateTime.fromMicrosecondsSinceEpoch(wholeSeconds, isUtc: true);
}

/// Snapshot of one local member's active PluralKit presence during a diff
/// sweep. Keeps every active member as a peg in the active map (so later
/// leavers have something to match) while distinguishing presences that own a
/// real fronting-session row from those that don't.
///
/// - [pkMemberUuid]: member's PK UUID at sweep start; nullable because a
///   DB-rebuilt presence may belong to a member whose mapping was dropped.
/// - [startedAt]: the entrant switch timestamp, or the open row's start_time
///   when reconstituted from the DB.
/// - [rowId]: the fronting-session row id, or `null` when no row was written
///   (tombstoned-row collision; the sweep skips entrant write and leaver
///   close).
/// - [isTombstonedCollision]: `true` when the entrant write was skipped
///   because the deterministic id collided with a soft-deleted row.
///
/// Equality is value-based for test comparison.
@immutable
class _PkActivePresence {
  const _PkActivePresence({
    required this.localMemberId,
    required this.pkMemberUuid,
    required this.startedAt,
    this.rowId,
    this.isTombstonedCollision = false,
  });

  final String localMemberId;
  final String? pkMemberUuid;
  final DateTime startedAt;
  final String? rowId;
  final bool isTombstonedCollision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PkActivePresence &&
          localMemberId == other.localMemberId &&
          pkMemberUuid == other.pkMemberUuid &&
          startedAt == other.startedAt &&
          rowId == other.rowId &&
          isTombstonedCollision == other.isTombstonedCollision;

  @override
  int get hashCode => Object.hash(
    localMemberId,
    pkMemberUuid,
    startedAt,
    rowId,
    isTombstonedCollision,
  );

  @override
  String toString() =>
      '_PkActivePresence(localMemberId: $localMemberId, '
      'pkMemberUuid: $pkMemberUuid, startedAt: $startedAt, '
      'rowId: $rowId, isTombstonedCollision: $isTombstonedCollision)';
}

// ---------------------------------------------------------------------------
// Sync state
// ---------------------------------------------------------------------------

/// Immutable snapshot of the current PluralKit sync state.
class PluralKitSyncState {
  final bool isSyncing;
  final double syncProgress;
  final String syncStatus;
  final String? syncError;
  final bool isConnected;

  /// True once the user has confirmed a sync direction and mode for the
  /// current PK system. Reset only when the connected systemId changes
  /// (token rotation against the same system preserves it).
  final bool directionConfirmed;

  /// True once the user has completed (or dismissed) the member mapping flow.
  /// Mirrors the DAO's `mappingAcknowledged` column directly — stored as
  /// a positive flag so the in-memory model stays in sync with the DB without
  /// a polarity inversion. See plan 08.
  final bool mappingAcknowledged;

  final DateTime? lastSyncDate;
  final DateTime? lastManualSyncDate;

  /// When the current PK connection was linked. Used to scope switch push to
  /// fronting sessions that started after linking (so we don't spam PK with
  /// historical local-only sessions).
  final DateTime? linkedAt;

  const PluralKitSyncState({
    this.isSyncing = false,
    this.syncProgress = 0.0,
    this.syncStatus = '',
    this.syncError,
    this.isConnected = false,
    this.directionConfirmed = false,
    this.mappingAcknowledged = false,
    this.lastSyncDate,
    this.lastManualSyncDate,
    this.linkedAt,
  });

  PluralKitSyncState copyWith({
    bool? isSyncing,
    double? syncProgress,
    String? syncStatus,
    String? syncError,
    bool clearError = false,
    bool? isConnected,
    bool? directionConfirmed,
    bool? mappingAcknowledged,
    DateTime? lastSyncDate,
    DateTime? lastManualSyncDate,
    DateTime? linkedAt,
    bool clearLinkedAt = false,
  }) {
    return PluralKitSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: syncProgress ?? this.syncProgress,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: clearError ? null : (syncError ?? this.syncError),
      isConnected: isConnected ?? this.isConnected,
      directionConfirmed: directionConfirmed ?? this.directionConfirmed,
      mappingAcknowledged: mappingAcknowledged ?? this.mappingAcknowledged,
      lastSyncDate: lastSyncDate ?? this.lastSyncDate,
      lastManualSyncDate: lastManualSyncDate ?? this.lastManualSyncDate,
      linkedAt: clearLinkedAt ? null : (linkedAt ?? this.linkedAt),
    );
  }

  /// True when connected but the user hasn't confirmed a sync direction yet.
  /// When this is true, [needsMapping] and [canAutoSync] are both false.
  bool get needsDirection => isConnected && !directionConfirmed;

  /// True while a connection exists and direction is confirmed but the user
  /// hasn't completed (or dismissed) the member mapping flow yet.
  /// In this state, auto-push and auto-sync are gated off to prevent
  /// duplicate members.
  bool get needsMapping =>
      isConnected && directionConfirmed && !mappingAcknowledged;

  /// True when the connection is fully usable — connected, direction
  /// confirmed, AND mapping complete. Callers gate auto-push / auto-sync on
  /// this.
  bool get canAutoSync =>
      isConnected && directionConfirmed && mappingAcknowledged;

  /// Whether a manual sync can be triggered (60-second cooldown).
  bool get canManualSync =>
      lastManualSyncDate == null ||
      DateTime.now().difference(lastManualSyncDate!) >=
          const Duration(seconds: 60);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PluralKitSyncState &&
        other.isSyncing == isSyncing &&
        other.syncProgress == syncProgress &&
        other.syncStatus == syncStatus &&
        other.syncError == syncError &&
        other.isConnected == isConnected &&
        other.directionConfirmed == directionConfirmed &&
        other.mappingAcknowledged == mappingAcknowledged &&
        other.lastSyncDate == lastSyncDate &&
        other.lastManualSyncDate == lastManualSyncDate &&
        other.linkedAt == linkedAt;
  }

  @override
  int get hashCode => Object.hash(
    isSyncing,
    syncProgress,
    syncStatus,
    syncError,
    isConnected,
    directionConfirmed,
    mappingAcknowledged,
    lastSyncDate,
    lastManualSyncDate,
    linkedAt,
  );
}

// ---------------------------------------------------------------------------
// Secure storage key
// ---------------------------------------------------------------------------

const _pkTokenKey = 'prism_pluralkit_token';

/// Cutoff for treating a fronting session with `pkImportSource == null` as
/// push-eligible.
///
/// Before per-member fronting landed, file and
/// file-API import paths didn't always tag rows with a `pkImportSource`. Those
/// legacy null-source rows are not safely classifiable as "user-created
/// locally" vs "imported from PK," so pushing them is the wrong default — it
/// risks creating duplicate PK switches for sessions that originally came from
/// PK.
///
/// Conservative gate: a null-source row is pushable only when its `startTime`
/// is at or after this cutoff. We use `startTime` as a proxy for row creation
/// time because `FrontingSession` has no dedicated `createdAt` column. This
/// has a known false-negative: a user logging a backdated session today won't
/// push it. That's an acceptable trade for not duplicating real data; the user
/// can re-push from the PK mapping screen.
///
/// The cutoff is set to the merge date of the per-member-fronting branch
/// (2026-04-30). A future PR can replace this with a one-time backfill that
/// classifies legacy null-source rows by inspecting `pluralkitUuid`/`pkFileSwitchId`,
/// at which point this gate can be relaxed.
final DateTime pkPushSourceAdoptionCutoff = DateTime.utc(2026, 4, 30);

/// Result of [PluralKitSyncService.pushPendingSwitches].
///
/// `pushed` is the count of local sessions that were successfully pushed to
/// PluralKit as switches.
///
/// `legacyNullSourceSkipped` is the count of sessions that were held back by
/// the [pkPushSourceAdoptionCutoff] gate — null `pkImportSource` rows whose
/// `startTime` predates the cutoff. Surfaced so callers / UI can show how
/// many rows were not pushed for source-classification reasons (distinct from
/// the much larger "not push-eligible at all" pool).
class PkPushSwitchesResult {
  final int pushed;
  final int legacyNullSourceSkipped;
  final int repaired;

  const PkPushSwitchesResult({
    this.pushed = 0,
    this.legacyNullSourceSkipped = 0,
    this.repaired = 0,
  });
}

// ---------------------------------------------------------------------------
// Sync service / notifier
// ---------------------------------------------------------------------------

typedef SyncStateCallback = void Function(PluralKitSyncState state);

/// Fields the user can choose to import from the PK system profile on first
/// pull. See [PluralKitSyncService.adoptSystemProfile] (plan 04).
enum PkProfileField { name, description, tag, avatar }

/// Read-only PK reference data used by local repair flows.
///
/// This is fetched via an ephemeral client and does not imply that the service
/// is connected for sync/import side effects.
class PkRepairReferenceData {
  final PKSystem system;
  final List<PKMember> members;
  final List<PKGroup> groups;

  const PkRepairReferenceData({
    required this.system,
    required this.members,
    required this.groups,
  });
}

/// Result for a full PluralKit import run.
///
/// Used both for token-backed one-shot imports (where the token is used only
/// for the import and not persisted) and for full re-imports under an
/// already-connected PluralKit configuration. The connection state is set
/// by the caller before invoking the import; this DTO only reports what
/// happened during the run.
class PkTokenImportResult {
  final PKSystem system;
  final List<PKMember> members;
  final int switchesImported;
  final int unmappedMemberReferences;

  /// Number of pre-existing tombstoned PK rows a corrective re-import left
  /// tombstoned. is_deleted is absorbing, so a tombstone is terminal:
  /// corrective import never flips it back. Covers local deletes, peer deletes
  /// arrived via CRDT merge, and pre-fix importer/migration cleanup rows.
  /// Surfaced in the post-import UI so the user understands why expected
  /// history did not reappear.
  final int tombstonePreservedCount;

  /// Number of leaver closes that matched the row's start timestamp
  /// (zero-length presence). The zero-duration row is discarded locally
  /// so it cannot linger as an open phantom fronter.
  final int zeroLengthCloseSkipped;

  /// PK-linked rows the canonicalization pass left untouched because
  /// their member fell OUTSIDE the canonical computation domain — the member
  /// was `pluralkitSyncIgnored`, had its PK link auto-cleared, or the row is a
  /// legacy `memberId == null` shape. Such a member's switches were never
  /// enumerable while `canonicalIds` was built, so absence from `canonicalIds`
  /// is no evidence of staleness; tombstoning the row would silently destroy
  /// valid fronting history on every peer via absorbing CRDT deletes. Surfaced
  /// in the post-import UI summary so the user understands those rows were
  /// deliberately preserved rather than silently dropped.
  final int unresolvableMemberRowsPreserved;

  /// Wall-clock timestamp when this import finished and persisted its
  /// cursor / last-sync state. Null when the caller asked the import to
  /// skip persistence (token-only one-shot path that doesn't update the
  /// stored sync state).
  final DateTime? completedAt;

  const PkTokenImportResult({
    required this.system,
    required this.members,
    required this.switchesImported,
    required this.unmappedMemberReferences,
    this.tombstonePreservedCount = 0,
    this.zeroLengthCloseSkipped = 0,
    this.unresolvableMemberRowsPreserved = 0,
    this.completedAt,
  });
}

/// Outcome of [PluralKitSyncService._upsertEntrantSession].
///
/// Replaces the previous nullable-string return so the entrant call site
/// can distinguish three end states without overloading "null":
///
/// - [row]: a fronting-session row was written (or re-used) and its id is
///   in [rowId]. The diff sweep records this presence with a real row id
///   so the matching leaver can close it.
/// - [tombstoneCollision]: the entrant id pointed at a soft-deleted row
///   during *incremental* sync. We deliberately do not resurrect it (a
///   user-initiated delete during routine sync must stick); the diff
///   sweep still records the member as fronting via the `_PkActivePresence`
///   `isTombstonedCollision` flag so leavers don't get out of sync.
/// - [tombstonePreserved]: the entrant id pointed at a tombstoned row
///   in *corrective* mode. is_deleted is absorbing, so a tombstone is terminal
///   regardless of its `deleteIntentEpoch` or PK-link state: in-place revival
///   is unsyncable by construction, so corrective import never flips it. The
///   diff sweep increments `tombstonePreservedCount` so the UI surfaces it.
class _PkUpsertOutcome {
  const _PkUpsertOutcome._(this.kind, this.rowId);

  const _PkUpsertOutcome.row(String id) : this._(_PkUpsertOutcomeKind.row, id);
  const _PkUpsertOutcome.tombstoneCollision()
    : this._(_PkUpsertOutcomeKind.tombstoneCollision, null);
  const _PkUpsertOutcome.tombstonePreserved()
    : this._(_PkUpsertOutcomeKind.tombstonePreserved, null);

  final _PkUpsertOutcomeKind kind;
  final String? rowId;
}

enum _PkUpsertOutcomeKind { row, tombstoneCollision, tombstonePreserved }

/// Aggregate counters returned by [_runDiffSweep] so corrective import paths
/// can surface `tombstonePreservedCount` / `zeroLengthCloseSkipped` without
/// out-parameters or debug-log scraping.
class _PkDiffSweepResult {
  const _PkDiffSweepResult({
    required this.unmappedCount,
    required this.tombstonePreservedCount,
    required this.zeroLengthCloseSkipped,
  });

  final int unmappedCount;
  final int tombstonePreservedCount;
  final int zeroLengthCloseSkipped;
}

/// Thrown by the file-import paths when the `pk;export` file's system identity
/// does not match the system the import is being applied against (2026-06 PK
/// audit H8). Carries both sides' names/ids so the UI can render a readable
/// message; `pk_file_import_provider.dart`'s generic `'Import failed: $e'`
/// catch renders this [toString] verbatim, which is intentionally
/// human-readable. Without this gate, a wrong-file-plus-valid-token import
/// merges a foreign roster irreversibly and later becomes push-eligible.
class PkFileSystemMismatchError implements Exception {
  PkFileSystemMismatchError({
    required this.fileSystemName,
    required this.fileSystemId,
    required this.targetSystemName,
    required this.targetSystemId,
  });

  /// Display name of the system in the export file (may be null).
  final String? fileSystemName;

  /// Stable identifier of the export file's system — UUID when both sides
  /// carry it, otherwise the short id.
  final String? fileSystemId;

  /// Display name of the currently linked / token system (may be null).
  final String? targetSystemName;

  /// Stable identifier of the target system (UUID or short id).
  final String? targetSystemId;

  String _label(String? name, String? id) {
    if (name != null && name.isNotEmpty) return '$name ($id)';
    return id ?? 'unknown system';
  }

  @override
  String toString() =>
      'This export is from a different PluralKit system. The file is '
      "${_label(fileSystemName, fileSystemId)}, but you're linked to "
      '${_label(targetSystemName, targetSystemId)}. Importing it would merge '
      "a different system's data into yours, so it was blocked.";
}

/// Thrown by [PluralKitSyncService.pushOverrideSwitch] when a NON-empty set of
/// chosen fronters all dropped out as unmapped or PK-sync-excluded (2026-06 PK
/// audit M8b). Posting the resulting empty list would silently clear PK's
/// current front, so we throw instead; a genuinely empty input ("nobody is
/// fronting") is a legitimate switch-out and is NOT routed here.
class PkAllChosenFrontersUnmappedException implements Exception {
  /// Display names (or local ids) of the chosen members that had no usable PK
  /// link. Non-empty by construction.
  final List<String> droppedMemberLabels;

  const PkAllChosenFrontersUnmappedException(this.droppedMemberLabels);

  @override
  String toString() {
    final names = droppedMemberLabels.join(', ');
    return 'None of the chosen fronters are linked to PluralKit yet '
        '($names), so the switch was not pushed. Link or include them via '
        'the mapping screen, then try again.';
  }
}

/// Thrown by the manual pull entry points when the 60-second manual-sync
/// cooldown has not elapsed. Enforced in-service so the cooldown is a real
/// contract rather than setup-screen button-disable advice. [remaining] lets
/// callers render an accurate countdown.
class PkManualSyncCooldownException implements Exception {
  PkManualSyncCooldownException(this.remaining);

  /// Time remaining before another manual sync is permitted. Always positive
  /// (a non-positive remaining means the cooldown elapsed and no exception is
  /// thrown).
  final Duration remaining;

  @override
  String toString() {
    final seconds = remaining.inSeconds + (remaining.inMilliseconds % 1000 > 0 ? 1 : 0);
    final clamped = seconds < 1 ? 1 : seconds;
    return 'Please wait $clamped more '
        '${clamped == 1 ? 'second' : 'seconds'} before syncing with '
        'PluralKit again.';
  }
}

/// Classified outcome of a single [PluralKitSyncService.pollFrontersOnly]
/// tick. A bare bool swallowed errors, so a revoked token kept polling at full
/// cadence and the 2-minute 429 backoff was unreachable in fullSync mode. A
/// typed outcome lets the auto-poll notifier map auth/429 without exposing the
/// raw exception.
enum PkPollOutcome {
  /// The poll completed; the live switch may or may not have been newly pulled
  /// (both "pulled a new switch" and "nothing new" are healthy `ok`s — the
  /// distinction never mattered to the caller, only success-vs-failure did).
  ok,

  /// The poll was a no-op for a benign local reason (not auto-syncable, already
  /// syncing, no client, current switch already known, unmapped fronters).
  skipped,

  /// PK rejected the token (401). The token is bad; the caller should stop
  /// reporting healthy and log an auth failure (do NOT auto-clear the token).
  authFailed,

  /// PK rate-limited (429). The caller should back off one cycle.
  rateLimited,

  /// Any other transient failure (network, 5xx, unexpected). The caller may
  /// back off but should not treat it as a permanent auth problem.
  transientError,
}

// ---------------------------------------------------------------------------
// Mass-deletion circuit breaker (2026-06 PK audit)
// ---------------------------------------------------------------------------

/// Maximum number of pending PK deletions an UNATTENDED (automatic) sync will
/// execute in a single pass before tripping the mass-deletion circuit breaker.
/// Migration residuals or a bug-enqueued batch are indistinguishable row-by-row
/// from genuine deletes, and PK deletions have high blast radius. 25 exceeds
/// any plausible manual burst; the user-confirmed destructive-push flow may
/// exceed it — the breaker only protects silent/unattended paths.
const int kPkMassDeletionAutoThreshold = 25;

const _pluralKitSyncFailedPrefix = 'PluralKit sync failed: ';

/// Return a user-facing PluralKit sync error with subsystem clarity.
/// If the message was already prefixed, return it unchanged.
@visibleForTesting
String? formatPluralKitSyncError(Object? rawError) {
  final message = rawError?.toString().trim();
  if (message == null || message.isEmpty) {
    return null;
  }
  if (message.startsWith(_pluralKitSyncFailedPrefix)) {
    return message;
  }
  return '$_pluralKitSyncFailedPrefix$message';
}

/// Core PluralKit synchronization logic.
///
/// Designed to be driven by a Riverpod notifier that passes a
/// [SyncStateCallback] so the notifier can update its state.
class PluralKitSyncService {
  /// Hard cap on incremental sweep pagination: 1000 pages × 100 switches/page
  /// = 100,000 switches, well above any realistic system. Hitting it means
  /// either the API is stuck or the cursor is so stale a full re-import is
  /// the appropriate path; we surface [PkImportTooLargeError] instead of
  /// looping.
  static const int _maxIncrementalPages = 1000;

  /// Test-only accessor for [_maxIncrementalPages]. Exposed so the
  /// page-cap guard test can build a fixture sized to the cap without
  /// hard-coding the constant in two places.
  @visibleForTesting
  static int get maxIncrementalPagesForTesting => _maxIncrementalPages;

  // Bound to the live `prismSyncHandleProvider` and deliberately MUTABLE so the
  // provider keeps ONE service instance across handle transitions, swapping
  // them via [updateVolatileDependencies]; rebuilding the whole service reset
  // `_state`/`_pushInFlight` mid-import and double-emitted state.
  MemberRepository _memberRepository;
  FrontingSessionRepository _frontingSessionRepository;
  SystemSettingsRepository? _settingsRepository;
  PkGroupsImporter? _groupsImporter;

  final PluralKitSyncDao _syncDao;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;
  final PluralKitClient Function(String token)? _clientFactory;
  final String? _tokenOverride;
  final PkAvatarCacheService _avatarCacheService;
  final PkBannerCacheService _bannerCacheService;
  final PkSyncEventBus _bus;

  PluralKitSyncState _state = const PluralKitSyncState();
  Future<PkPushSwitchesResult>? _pushInFlight;

  /// Service-level PULL gate. Every pull-side entry point claims this flag
  /// SYNCHRONOUSLY before its first `await` via [_claimPull] and releases it
  /// in a `finally`. Checking `_state.isSyncing` alone left an await gap
  /// between check and claim that let concurrent callers both enter. The PUSH
  /// machinery (`_pushInFlight`) is deliberately separate — pushes must keep
  /// interleaving with pulls.
  bool _pullInFlight = false;

  /// Test seam — lets the concurrency tests force a pull to be in flight
  /// without spinning up a real long-running import, so they can
  /// assert that every other entry point bails as busy. Production never calls
  /// this; the flag is otherwise only mutated by [_claimPull]/[_releasePull].
  @visibleForTesting
  bool get pullInFlightForTesting => _pullInFlight;

  /// Synchronously claim the pull gate. Returns `true`
  /// when the gate was free and is now held by this caller; `false` when a pull
  /// (this flag OR a legacy `_emit(isSyncing:true)` claim) is already running,
  /// in which case the caller MUST bail as busy WITHOUT stamping cooldowns or
  /// emitting a success event. There is intentionally NO `await` in this method
  /// — callers rely on the check-then-set being atomic under the event loop.
  bool _claimPull() {
    if (_pullInFlight || _state.isSyncing) return false;
    _pullInFlight = true;
    return true;
  }

  /// Release the pull gate. Idempotent; safe to call from a `finally` even when
  /// the matching [_claimPull] returned false (the caller simply never set it).
  void _releasePull() {
    _pullInFlight = false;
  }

  /// Manual-sync cooldown window (mirrors [PluralKitSyncState.canManualSync]).
  static const Duration _manualSyncCooldown = Duration(seconds: 60);

  /// Time remaining on the manual-sync cooldown, or [Duration.zero] when a
  /// manual sync is allowed right now. Computed from the stored
  /// `lastManualSyncDate` so it survives a service rebuild — the in-memory
  /// `_state` is restored from the DAO on init.
  Duration _manualSyncCooldownRemaining() {
    final last = _state.lastManualSyncDate;
    if (last == null) return Duration.zero;
    final elapsed = DateTime.now().difference(last);
    if (elapsed >= _manualSyncCooldown) return Duration.zero;
    return _manualSyncCooldown - elapsed;
  }

  /// Throw [PkManualSyncCooldownException] when a manual pull is requested
  /// inside the cooldown window. No-op for automatic syncs (the cooldown only
  /// rate-limits user-initiated taps, never the auto-poll cadence) and when the
  /// cooldown has elapsed. Called by the manual entry points BEFORE they claim
  /// the pull gate so a rejected manual sync neither holds the gate nor stamps a
  /// fresh cooldown.
  void _enforceManualCooldown({required bool isManual}) {
    if (!isManual) return;
    final remaining = _manualSyncCooldownRemaining();
    if (remaining > Duration.zero) {
      throw PkManualSyncCooldownException(remaining);
    }
  }

  /// Trailing-change dirty flag. A push arriving while one is in flight can't
  /// just return the in-flight future — it was captured before the new state
  /// existed (rapid A→B→C would drop C). Mark dirty; on completion exactly ONE
  /// follow-up fires, awaited via [_pushFollowUp].
  bool _pushDirty = false;

  /// The local fronter ORDER (short-id space) this service last pushed to, or
  /// last observed in agreement with, PluralKit.
  /// The order-only repatch fires only when the LOCAL order changed since this
  /// baseline, so a PK-side reorder (`pk;sw move`) survives intent-less
  /// triggers. Only comparable while it refers to the SAME member set; on a
  /// set change the next same-set observation re-anchors WITHOUT patching —
  /// on ambiguity PK's stored order wins.
  List<String>? _lastObservedLocalPushOrder;

  /// Completer that resolves to the result of the next follow-up run scheduled
  /// by the dirty flag. Shared by all callers that arrived mid-flight, so a
  /// burst of trailing triggers coalesces into a single follow-up.
  Completer<PkPushSwitchesResult>? _pushFollowUp;

  /// Last-used default args for [pushPendingSwitches], captured so a follow-up
  /// run uses the same shape. The follow-up runs with DEFAULT args (no
  /// `knownCurrentFronters` — that snapshot is stale by the time it fires);
  /// only the stale-link callback and refresh flag are carried so its stale
  /// messages aren't silently dropped.
  void Function(String message)? _lastPushOnStaleLink;
  bool _lastPushRefreshMembersOnStaleLink = true;

  /// Coalescing queue for member-edit pushes. All member-edit pushes funnel
  /// through ONE drain loop and one client so PK's
  /// 3/s write budget holds across bursts. [_pendingMemberPushes] keeps only
  /// the LATEST state per member id, [_memberPushWaiters] share one completer
  /// per member, and a non-null [_memberPushDrain] means a running drain will
  /// pick up new edits rather than a second loop starting.
  final Map<String, domain.Member> _pendingMemberPushes = {};
  final Map<String, Completer<bool>> _memberPushWaiters = {};
  Future<void>? _memberPushDrain;

  /// Optional override for the push service used by the member-edit drain.
  /// Set by the legacy [pushMemberUpdate] test seam; production leaves it null
  /// and the drain falls back to `const PkPushService()`.
  PkPushService? _memberPushServiceOverride;

  SyncStateCallback? onStateChanged;

  PluralKitSyncService({
    required MemberRepository memberRepository,
    required FrontingSessionRepository frontingSessionRepository,
    required PluralKitSyncDao syncDao,
    required PkSyncEventBus bus,
    SystemSettingsRepository? settingsRepository,
    FlutterSecureStorage? secureStorage,
    PluralKitClient Function(String token)? clientFactory,
    String? tokenOverride,
    PkGroupsImporter? groupsImporter,
    PkAvatarCacheService? avatarCacheService,
    PkBannerCacheService? bannerCacheService,
  }) : _memberRepository = memberRepository,
       _frontingSessionRepository = frontingSessionRepository,
       _syncDao = syncDao,
       _settingsRepository = settingsRepository,
       _secureStorage = secureStorage ?? storage_config.secureStorage,
       _uuid = const Uuid(),
       _clientFactory = clientFactory,
       _tokenOverride = tokenOverride,
       _groupsImporter = groupsImporter,
       _avatarCacheService = avatarCacheService ?? PkAvatarCacheService(),
       _bannerCacheService = bannerCacheService ?? PkBannerCacheService(),
       _bus = bus;

  PluralKitSyncState get state => _state;

  void _emit(PluralKitSyncState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  /// Rebind the handle-dependent dependencies in place, keeping the service
  /// IDENTITY (`_state`, in-flight push, `onStateChanged` wiring) stable
  /// across `prismSyncHandleProvider` transitions while the next write uses
  /// the CURRENT handle. Only non-null arguments are applied; in-flight work
  /// that captured the old importer is not interrupted. PRODUCTION API, not a
  /// test seam — do not mark it `@visibleForTesting`.
  void updateVolatileDependencies({
    MemberRepository? memberRepository,
    FrontingSessionRepository? frontingSessionRepository,
    SystemSettingsRepository? settingsRepository,
    PkGroupsImporter? groupsImporter,
    bool clearGroupsImporter = false,
  }) {
    if (memberRepository != null) _memberRepository = memberRepository;
    if (frontingSessionRepository != null) {
      _frontingSessionRepository = frontingSessionRepository;
    }
    if (settingsRepository != null) _settingsRepository = settingsRepository;
    if (clearGroupsImporter) {
      _groupsImporter = null;
    } else if (groupsImporter != null) {
      _groupsImporter = groupsImporter;
    }
  }

  /// Current groups-importer binding. Test-only: lets the provider tests
  /// assert that a handle transition rebinds the importer (fresh instance, new
  /// `syncHandle`) WITHOUT rebuilding the service. Never use from production —
  /// resolve `_groupsImporter` directly inside the service instead.
  @visibleForTesting
  PkGroupsImporter? get groupsImporterForTesting => _groupsImporter;

  // -- helpers --------------------------------------------------------------

  String? _normalizeToken(String? token) {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<String?> _getToken() async {
    if (_tokenOverride != null) return _tokenOverride;
    // Classified read — cipher / transient / unknown failures resolve to
    // null. The PK token is reconstructable (user re-enters it), so a
    // cipher failure on this slot is treated as "no token" and surfaces
    // the disconnected UI rather than crashing the service.
    return (await storage_config.safeSecureRead(
      _pkTokenKey,
      storage: _secureStorage,
    )).value;
  }

  PluralKitClient _makeClient(String token) => _clientFactory != null
      ? _clientFactory(token)
      // Forward the service's PkSyncEventBus so the client's internal request
      // queue can emit PkRateLimitHit events on real 429 backoffs. Without
      // this, rate-limit telemetry only fires in tests that inject a queue or
      // client factory of their own — production builds were dropping the
      // signal entirely.
      : PluralKitClient(token: token, bus: _bus);

  PluralKitClient? _buildClientFromToken(String? token) {
    final normalized = _normalizeToken(token);
    if (normalized == null) return null;
    return _makeClient(normalized);
  }

  Future<PluralKitClient?> _buildClient() async =>
      _buildClientFromToken(await _getToken());

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  Future<String?> _getRepairToken({String? token}) async {
    if (token != null) return _normalizeToken(token);
    return _normalizeToken(await _getToken());
  }

  Future<PluralKitClient?> _buildRepairClient({String? token}) async =>
      _buildClientFromToken(await _getRepairToken(token: token));

  /// Whether two PluralKit systems are the same identity (2026-06 PK audit
  /// H8). Prefers UUID comparison when BOTH sides carry one — UUIDs are the
  /// only stable key, and PK Premium (~Feb 2026) makes short ids
  /// user-changeable. Falls back to short id when a uuid is missing on either
  /// side (e.g. an older export root, or a linked-system row that only stored
  /// the short id). Returns false only on a genuine mismatch; a missing id on
  /// both sides (shouldn't happen — `id` is required) compares equal.
  static bool _systemIdentitiesMatch(PKSystem a, PKSystem b) {
    final aUuid = a.uuid?.trim();
    final bUuid = b.uuid?.trim();
    if (aUuid != null &&
        aUuid.isNotEmpty &&
        bUuid != null &&
        bUuid.isNotEmpty) {
      return aUuid == bUuid;
    }
    return a.id.trim() == b.id.trim();
  }

  Future<PkRepairReferenceData> _fetchReferenceData(
    PluralKitClient client, {
    bool includeGroups = true,
  }) async {
    final system = await client.getSystem();
    final members = await client.getMembers();
    final groups = includeGroups
        ? await client.getGroups(withMembers: true)
        : const <PKGroup>[];
    return PkRepairReferenceData(
      system: system,
      members: members,
      groups: groups,
    );
  }

  // -- public API -----------------------------------------------------------

  /// Build a PK client if connected. Exposed for use by auto-push.
  ///
  /// Returns null while the connection is in `connected_pending_map` —
  /// auto-push must not run until the mapping flow completes. Callers that
  /// explicitly need the client regardless (e.g. the mapping screen itself)
  /// should use [buildClientIgnoringMappingGate].
  Future<PluralKitClient?> buildClientIfConnected() async {
    if (!_state.canAutoSync) return null;
    return _buildClient();
  }

  /// Build a PK client even while mapping is pending — used by the mapping
  /// applier and the mapping screen itself.
  Future<PluralKitClient?> buildClientIgnoringMappingGate() async {
    if (!_state.isConnected) return null;
    return _buildClient();
  }

  /// Whether repair can use a stored or explicitly-provided PK token.
  ///
  /// This is read-only: it does not validate the token, persist it, or change
  /// sync state.
  Future<bool> hasRepairToken({String? token}) async =>
      (await _getRepairToken(token: token)) != null;

  /// Whether this device currently has a local PluralKit token.
  ///
  /// This is separate from [PluralKitSyncState.isConnected]: the DB may still
  /// remember a completed setup while platform secure storage has lost or
  /// cleared the token.
  Future<bool> hasStoredToken() async => (await _getToken()) != null;

  /// Read-only PK fetch for repair reference data.
  ///
  /// This intentionally does not call [setToken], write secure storage, update
  /// the sync DAO, or emit connected/syncing state changes. A future repair
  /// coordinator can pass a one-off [token] or fall back to the stored token.
  Future<PkRepairReferenceData> fetchRepairReferenceData({
    String? token,
  }) async {
    final client = await _buildRepairClient(token: token);
    if (client == null) {
      throw StateError('No PluralKit token available for repair');
    }

    try {
      return await _fetchReferenceData(client);
    } finally {
      client.dispose();
    }
  }

  /// Load persisted sync state from the database.
  Future<void> loadState() async {
    final row = await _syncDao.getSyncState();
    _emit(
      _state.copyWith(
        isConnected: row.isConnected,
        directionConfirmed: row.directionConfirmed,
        mappingAcknowledged: row.mappingAcknowledged,
        lastSyncDate: row.lastSyncDate,
        lastManualSyncDate: row.lastManualSyncDate,
        linkedAt: row.linkedAt,
      ),
    );
  }

  /// Confirm that the user has chosen a sync direction for the current PK
  /// system. Clears [PluralKitSyncState.needsDirection] and unblocks the
  /// mapping step. Only written once per PK system; same-system token
  /// rotation preserves this flag via [setToken]'s isSameSystem branch.
  Future<void> confirmDirection() async {
    await _syncDao.upsertSyncState(
      const PluralKitSyncStateCompanion(
        id: Value('pk_config'),
        directionConfirmed: Value(true),
      ),
    );
    _emit(_state.copyWith(directionConfirmed: true));
  }

  /// Flip the connection out of `connected_pending_map` — called after the
  /// mapping screen finishes Apply, or when the user explicitly dismisses it.
  /// Auto-push / auto-sync unlock after this is called.
  Future<void> acknowledgeMapping() async {
    await _syncDao.upsertSyncState(
      const PluralKitSyncStateCompanion(
        id: Value('pk_config'),
        mappingAcknowledged: Value(true),
      ),
    );
    _emit(_state.copyWith(mappingAcknowledged: true));
  }

  // ---------------------------------------------------------------------------
  // Override-switch helpers (T9 — "Who's fronting?" resolution)
  // ---------------------------------------------------------------------------

  /// POST /switches with the chosen local members at [at].
  ///
  /// Resolves local member IDs → PK short IDs via the persisted mapping table
  /// (the [domain.Member.pluralkitId] column). Returns the new [PKSwitch]
  /// (full server-side record, including PK's stored timestamp), or null on
  /// network failure. Used by [PkMappingController.applyFronterResolution]
  /// to record the user's authoritative fronter choice in PluralKit.
  ///
  /// The full switch is returned (not just the ID) so the caller can advance
  /// the import cursor using PK's stored timestamp rather than the local
  /// clock — clock skew or PK truncation could otherwise leapfrog real PK
  /// switches. See bug media heal.
  ///
  /// IMPORTANT: the 1ms [linkedAt] nudge in [setToken] means switches written
  /// at `startTime = now` have `startTime > linkedAt`, so the regular push
  /// pipeline would pick these up too. By POSTing directly here and then
  /// calling [advanceImportCursorPast], we avoid the duplicate and capture the
  /// exact switch ID needed for cursor advancement. Do NOT remove the 1ms
  /// nudge in [setToken] — this helper's correctness depends on it.
  Future<PKSwitch?> pushOverrideSwitch(
    List<String> localMemberIds,
    DateTime at,
  ) async {
    try {
      final client = await _buildClient();
      if (client == null) return null;
      try {
        // An EMPTY input is a legitimate switch-out; a NON-empty input whose
        // members ALL dropped out (unmapped/excluded) throws instead of
        // silently clearing PK's front, and partial drops proceed with the
        // mapped subset. Wire refs prefer uuid, but INCLUSION requires a
        // non-empty `pluralkitId` in lockstep with `_doPushPendingSwitches` —
        // widening to uuid-only members here would let a pending push un-front
        // them.
        final wireRefs = <String>[];
        final droppedLabels = <String>[];
        if (localMemberIds.isNotEmpty) {
          final members = await _memberRepository.getMembersByIds(
            localMemberIds,
          );
          final byId = {for (final m in members) m.id: m};
          for (final localId in localMemberIds) {
            final m = byId[localId];
            final pkId = m?.pluralkitId?.trim();
            final pkUuid = m?.pluralkitUuid?.trim();
            final hasShortId = pkId != null && pkId.isNotEmpty;
            final includable =
                m != null && !m.pluralkitSyncIgnored && hasShortId;
            if (!includable) {
              if (m != null &&
                  !m.pluralkitSyncIgnored &&
                  pkUuid != null &&
                  pkUuid.isNotEmpty) {
                // uuid-only link: deliberately dropped for pending-push parity
                // (see the inclusion-filter comment above).
                debugPrint(
                  '[PK_SVC] pushOverrideSwitch: dropped ${m.name} — has a PK '
                  'uuid but no short id; the pending-push pipeline keys on '
                  'short ids, so including it here would desync the next '
                  'push.',
                );
              }
              droppedLabels.add(m?.name.trim().isNotEmpty == true
                  ? m!.name
                  : localId);
              continue;
            }
            // uuid-first wire ref — short id required above, uuid preferred
            // on the wire when both are present.
            wireRefs.add(
              (pkUuid != null && pkUuid.isNotEmpty) ? pkUuid : pkId,
            );
          }

          if (wireRefs.isEmpty) {
            // Every chosen member dropped — refuse to clear PK's front.
            throw PkAllChosenFrontersUnmappedException(droppedLabels);
          }
          if (droppedLabels.isNotEmpty) {
            debugPrint(
              '[PK_SVC] pushOverrideSwitch: ${droppedLabels.length} chosen '
              'member(s) had no usable PK link and were dropped from the '
              'override switch: ${droppedLabels.join(', ')} (2026-06 PK audit '
              'M8b partial drop).',
            );
          }
        }

        try {
          return await client.createSwitch(wireRefs, timestamp: at);
        } on PluralKitApiError catch (e) {
          // 40004 (identical-to-current-front) is benign success (2026-06 PK
          // audit M8a): PK's front already matches. The caller advances its
          // cursor off the returned switch, so fetch and return the current
          // fronters instead of null; a null fetch here (never-switched) is
          // contradictory per the API and surfaces as a retryable hard error.
          if (e.statusCode == 400 &&
              (e.code == 40004 || e.message.contains('40004'))) {
            debugPrint(
              '[PK_SVC] pushOverrideSwitch: PK reports the chosen front is '
              'already current (40004); fetching current fronters instead of '
              'failing (2026-06 PK audit M8a).',
            );
            return await client.getCurrentFronters();
          }
          rethrow;
        }
      } finally {
        client.dispose();
      }
    } on Object catch (e) {
      // Only swallow network failures — they're retry-friendly and the
      // caller treats `null` as "skip cursor advance, let the next sync
      // reconcile." Auth errors, 4xx/5xx, the M8b unmapped-all error, etc.
      // must propagate so the caller sees them instead of silently succeeding.
      // See bug I2.
      if (isPluralKitNetworkException(e)) {
        debugPrint('[PK_SVC] pushOverrideSwitch network failure: $e');
        return null;
      }
      rethrow;
    }
  }

  /// Advance the import cursor past a known switch so the next diff sweep
  /// won't re-import it as a duplicate session.
  ///
  /// Called after [pushOverrideSwitch] to prevent the post-apply bootstrap
  /// from re-importing the just-created override switch.
  Future<void> advanceImportCursorPast({
    required String switchId,
    required DateTime timestamp,
  }) async {
    // F19: route through advanceImportCursorIfNewer so a stale/out-of-order
    // caller can't regress the monotonic cursor into redundant re-fetches.
    await _syncDao.advanceImportCursorIfNewer(
      switchId: switchId,
      timestamp: timestamp,
    );
  }

  /// Store the token, test the connection, and persist connected state.
  ///
  /// Failed token rotation must NOT destroy a working token (2026-06 PK audit
  /// H9): validate FIRST against an ephemeral client, write to storage only on
  /// success (and check the write result), and on ANY validation failure (401
  /// or transport) leave the stored token and DB connection state untouched.
  Future<void> setToken(String token) async {
    final trimmed = token.trim();
    debugPrint('[PK_SVC] setToken: trimmed length=${trimmed.length}');
    if (trimmed.isEmpty) {
      _emit(
        _state.copyWith(
          syncError: formatPluralKitSyncError('Token cannot be empty'),
        ),
      );
      return;
    }

    // -- Step 1: validate against an EPHEMERAL client. No storage write yet,
    // so a 401 / network failure here cannot overwrite or delete the working
    // token.
    final PKSystem system;
    final validationClient = _makeClient(trimmed);
    try {
      debugPrint('[PK_SVC] setToken: calling client.getSystem()...');
      system = await validationClient.getSystem();
      debugPrint(
        '[PK_SVC] setToken: getSystem ok — id=${system.id} name=${system.name}',
      );
    } on PluralKitAuthError catch (e) {
      // 401: the supplied token is invalid. Leave the previously stored token
      // and the DB connection state untouched — only surface the error. A
      // device that was already connected on a good token stays connected.
      debugPrint('[PK_SVC] setToken: PluralKitAuthError (token unchanged): $e');
      _emit(
        _state.copyWith(
          syncError: formatPluralKitSyncError(
            'Invalid token — please check and try again.',
          ),
        ),
      );
      _bus.emit(const PkTokenAuthFailed());
      return;
    } catch (e, st) {
      // Transport / 5xx / anything else: a transient failure must NOT touch
      // the stored token or the connection state.
      debugPrint('[PK_SVC] setToken: validation failed (token unchanged): $e\n$st');
      _emit(
        _state.copyWith(
          syncError: formatPluralKitSyncError('Connection failed: $e'),
        ),
      );
      _bus.emit(
        PkRequestFailed(
          stage: 'setToken',
          errorKind: 'unknown',
          message: PkSyncEvent.redact(e.toString(), trimmed),
        ),
      );
      return;
    } finally {
      validationClient.dispose();
    }

    // -- Step 2: validation succeeded. Persist the token and CHECK the write
    // result. A classified write failure leaves the
    // prior token alone (the write threw, nothing was overwritten) and must
    // NOT mark the DB connected.
    final writeResult = await storage_config.safeSecureWrite(
      _pkTokenKey,
      trimmed,
      storage: _secureStorage,
    );
    if (!writeResult.ok) {
      debugPrint(
        '[PK_SVC] setToken: secure write FAILED '
        '(failure=${writeResult.failure?.name}, code=${writeResult.code}) — '
        'not marking connected; prior token left intact.',
      );
      _emit(
        _state.copyWith(
          syncError: formatPluralKitSyncError(
            "Couldn't save the token to secure storage — please try again.",
          ),
        ),
      );
      _bus.emit(
        PkRequestFailed(
          stage: 'setToken',
          errorKind: 'storage',
          message: 'secure write failed (${writeResult.failure?.name})',
        ),
      );
      return;
    }
    debugPrint('[PK_SVC] setToken: wrote to secureStorage');

    // -- Step 3: token persisted. Wire up connection + setup state. (Success
    // path semantics unchanged from before H9: same-system flag preservation,
    // epoch bump on system change, mapping-state clear, linkedAt logic.)
    // Preserve existing linkedAt on re-connect with the same system (user
    // rotated their token without re-linking). For a truly fresh link we
    // stamp `now` so the scoped switch push has a stable cutoff.
    final existing = await _syncDao.getSyncState();
    final DateTime linkedAt;
    if (existing.systemId == system.id && existing.linkedAt != null) {
      linkedAt = existing.linkedAt!;
    } else {
      // Subtract 1ms so that a fronting session created in the same tick as
      // linking (startTime == now) still clears the `isAfter(linkedAt)`
      // boundary in [pushPendingSwitches]. Without this nudge, any switch
      // whose startTime equals linkedAt would be dropped forever.
      linkedAt = DateTime.now().subtract(const Duration(milliseconds: 1));
    }

    // Plan 02 R1: bump the local link epoch whenever the connected system
    // changes identity. Tombstones stamped under the prior epoch will be
    // skipped at push time on this device.
    final isSameSystem = existing.systemId == system.id;
    final bumpEpoch = !isSameSystem;

    // On a different-system swap, clear pk_mapping_state. Stale Skip/Push
    // decisions keyed by the previous session's PK identifiers would
    // otherwise return PkApplyOutcome.alreadyApplied on re-attempt and the
    // user's new mapping would silently no-op. `clearToken` already does
    // this; bring `setToken`'s system-swap path to parity.
    if (!isSameSystem) {
      await PkMappingStateDao(_syncDao.attachedDatabase).clearAll();
    }

    // Preserve setup state (directionConfirmed + mappingAcknowledged) on a
    // same-system token rotation; a different system resets both flags. A
    // different-system swap also nulls the switch cursor and lastSyncDate
    // (parity with clearToken) — the old cursor would `covers()` the new
    // system's history and block its import.
    await _syncDao.upsertSyncState(
      PluralKitSyncStateCompanion(
        id: const Value('pk_config'),
        systemId: Value(system.id),
        isConnected: const Value(true),
        mappingAcknowledged: isSameSystem
            ? Value(existing.mappingAcknowledged)
            : const Value(false),
        directionConfirmed: isSameSystem
            ? Value(existing.directionConfirmed)
            : const Value(false),
        linkedAt: Value(linkedAt),
        switchCursorTimestamp: isSameSystem
            ? const Value.absent()
            : const Value(null),
        switchCursorId: isSameSystem ? const Value.absent() : const Value(null),
        lastSyncDate: isSameSystem ? const Value.absent() : const Value(null),
      ),
    );
    if (bumpEpoch) {
      await _syncDao.bumpLinkEpoch();
    }

    _emit(
      _state.copyWith(
        isConnected: true,
        mappingAcknowledged: isSameSystem
            ? existing.mappingAcknowledged
            : false,
        directionConfirmed: isSameSystem
            ? existing.directionConfirmed
            : false,
        linkedAt: linkedAt,
        clearError: true,
      ),
    );
    _bus.emit(
      PkTokenSet(systemName: system.name ?? system.id, systemId: system.id),
    );
  }

  /// Remove the token and reset connected state.
  ///
  /// Also truncates the PK mapping-state table and resets
  /// [PluralKitSyncState.needsMapping] so a future reconnect (potentially
  /// against a different PK system) starts with a fresh mapping flow — stale
  /// Skip/Link decisions keyed by the previous session's local member IDs
  /// would otherwise silently skip or link members the user never saw.
  Future<void> clearToken() async {
    await storage_config.safeSecureDelete(_pkTokenKey, storage: _secureStorage);
    await _syncDao.upsertSyncState(
      const PluralKitSyncStateCompanion(
        id: Value('pk_config'),
        systemId: Value(null),
        isConnected: Value(false),
        mappingAcknowledged: Value(false),
        lastSyncDate: Value(null),
        lastManualSyncDate: Value(null),
        linkedAt: Value(null),
        switchCursorTimestamp: Value(null),
        switchCursorId: Value(null),
      ),
    );
    // Plan 02 R1: bump on disconnect so tombstones made while linked become
    // stale immediately. A later reconnect will bump again (new systemId
    // path).
    await _syncDao.bumpLinkEpoch();
    // Wipe prior Skip/Link/Import decisions — they're keyed by local member
    // IDs that may not even exist in the next connected system.
    await PkMappingStateDao(_syncDao.attachedDatabase).clearAll();
    _emit(const PluralKitSyncState());
    _bus.emit(const PkTokenCleared());
  }

  /// Test the connection without modifying stored state.
  Future<bool> testConnection() async {
    try {
      final client = await _buildClient();
      if (client == null) return false;
      await client.getSystem();
      client.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Read-only fetch: returns PK system name and members without writing
  /// anything to the local members table. Used by the mapping screen so we
  /// don't auto-create clones before the user makes mapping decisions.
  ///
  /// Unlike [importMembersOnly], this path does NOT download avatars or
  /// call [_importMembers]. Avatar downloads and row writes happen later,
  /// per-decision, via the mapping applier.
  Future<(String? systemName, List<PKMember> pkMembers)>
  fetchPkMembersWithoutImport() async {
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');

    try {
      final data = await _fetchReferenceData(client, includeGroups: false);
      return (data.system.name, data.members);
    } finally {
      client.dispose();
    }
  }

  /// Fast member-only import. Returns system name and PK members for UI.
  Future<(String? systemName, List<PKMember> pkMembers)>
  importMembersOnly() async {
    // Claim the shared pull gate synchronously BEFORE the `_buildClient()`
    // await — previously this method emitted `isSyncing:true` only AFTER
    // building the client, leaving a window where it could run concurrently
    // with another pull. A busy caller throws (the mapping flow that drives
    // this can retry); an explicit error beats returning a partial roster
    // mid-sweep.
    if (!_claimPull()) {
      throw StateError('PluralKit sync is already running');
    }
    // The client build lives INSIDE the try so any throw out of
    // the token read (not just classified PlatformExceptions) hits the
    // `finally` and releases the gate — a leak here would lock out every pull
    // until the service is rebuilt.
    PluralKitClient? client;
    try {
      debugPrint('[PK_SVC] importMembersOnly: building client...');
      client = await _buildClient();
      if (client == null) {
        debugPrint(
          '[PK_SVC] importMembersOnly: _buildClient returned null '
          '(token missing from secure storage?)',
        );
        throw StateError('Not connected');
      }
      _emit(
        _state.copyWith(
          isSyncing: true,
          syncProgress: 0.0,
          syncStatus: 'Fetching system info...',
          clearError: true,
        ),
      );

      debugPrint('[PK_SVC] importMembersOnly: calling getSystem...');
      final system = await client.getSystem();
      debugPrint('[PK_SVC] importMembersOnly: system.name=${system.name}');
      _emit(
        _state.copyWith(syncProgress: 0.3, syncStatus: 'Fetching members...'),
      );

      debugPrint('[PK_SVC] importMembersOnly: calling getMembers...');
      final pkMembers = await client.getMembers();
      debugPrint(
        '[PK_SVC] importMembersOnly: getMembers returned ${pkMembers.length} '
        '(first 3 names=${pkMembers.take(3).map((m) => m.name).toList()})',
      );
      _emit(
        _state.copyWith(
          syncProgress: 0.5,
          syncStatus: 'Importing ${pkMembers.length} members...',
        ),
      );

      debugPrint('[PK_SVC] importMembersOnly: calling _importMembers...');
      await _importMembers(
        client,
        pkMembers,
        onProgress: (current, total, name) {
          // Member import phase occupies 0.50 → 0.95 of the overall progress
          // bar in importMembersOnly. current=1 (i=0) maps to 0.50;
          // current=total (i=last) maps to 0.95.
          final fraction = total <= 1 ? 1.0 : (current - 1) / (total - 1);
          _emit(
            _state.copyWith(
              syncProgress: 0.50 + 0.45 * fraction,
              syncStatus: 'Importing member $current/$total: $name',
            ),
          );
        },
      );
      debugPrint('[PK_SVC] importMembersOnly: _importMembers done');

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: 'Imported ${pkMembers.length} members.',
        ),
      );
      _bus.emit(PkMembersImported(count: pkMembers.length));

      return (system.name, pkMembers);
    } catch (e, st) {
      debugPrint('[PK_SVC] importMembersOnly: caught $e\n$st');
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError('Member import failed: $e'),
        ),
      );
      _bus.emit(
        PkRequestFailed(
          stage: 'importMembersOnly',
          errorKind: 'unknown',
          // Redact against the client's actual token (not a separately-captured
          // value) so a clearToken/setToken race between read-and-build can't
          // leave us redacting against a stale or null token while the
          // exception text still embeds the live one. Null when the client
          // build itself failed — redact tolerates that.
          message: PkSyncEvent.redact(e.toString(), client?.currentToken),
        ),
      );
      rethrow;
    } finally {
      client?.dispose();
      _releasePull();
    }
  }

  /// Corrective full re-import: members + groups + complete PK switch history.
  ///
  /// This is the explicit "Re-import all from PluralKit" user action. It
  /// differs from [syncRecentData] in setup:
  ///   1. Seeds active state from PK-linked DB rows open before the first
  ///      fetched switch, bounded to the replay window so current rows from
  ///      later in history are not closed against old switches.
  ///   2. Resets the diff-sweep cursor so the sweep runs from the beginning
  ///      of PK history.
  ///   3. Canonicalizes: tombstones API-linked rows whose deterministic id
  ///      isn't in the API entrant set (rescue-import fan-out artifacts). The
  ///      detect+tombstone loop runs in one Drift transaction so a mid-loop
  ///      crash leaves it atomically un-done rather than half-applied.
  ///   4. Runs the diff sweep from oldest switch to newest.
  ///
  /// Tombstones are *preserved*: is_deleted is absorbing, so any deleted row
  /// stays deleted and is never resurrected by re-import. The preserved count
  /// is reported in the import result UI.
  ///
  /// Deterministic IDs: rows created by a previous import keep the same id
  /// when the sweep re-derives them (v5 UUIDs from entry-switch + member uuid).
  /// CRDT field-LWW handles boundary correction on collision.
  Future<void> performFullImport() async {
    // Preserve this wrapper's historical silent-no-op
    // busy contract (the setup screen calls it bare). The check below and
    // `_performFullImport`'s own synchronous `_claimPull()` run with NO await
    // between them, so the pair is atomic under the event loop — the check is
    // a contract adapter, not the mutual exclusion itself (that lives inside).
    if (_pullInFlight || _state.isSyncing) return;
    await _performFullImport();
  }

  /// One-time full import using a stored or caller-provided token without
  /// changing PluralKit connection state.
  ///
  /// This is for migration recovery flows: it imports members, groups, and
  /// switch history from PK, but does not call [setToken], does not persist a
  /// provided token, and does not mark ongoing PK sync as connected.
  Future<PkTokenImportResult> performOneTimeFullImport({String? token}) =>
      _performFullImport(useRepairToken: true, token: token);

  Future<PkTokenImportResult> _performFullImport({
    bool useRepairToken = false,
    String? token,
    bool gateAlreadyHeld = false,
  }) async {
    if (!useRepairToken && !_state.canAutoSync) {
      throw StateError(
        'Setup incomplete — confirm direction and mapping before auto-syncing.',
      );
    }
    // Claim the service-level pull gate synchronously,
    // UNLESS an outer pull already holds it ([syncRecentData]'s first-sync
    // branch passes `gateAlreadyHeld: true`). A standalone busy caller throws —
    // an explicit "re-import all" is a user action where a clear error beats a
    // silent no-op (and preserves the prior `performOneTimeFullImport` contract
    // that some callers catch).
    if (!gateAlreadyHeld && !_claimPull()) {
      throw StateError('PluralKit import is already running');
    }
    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Fetching system info...',
        clearError: true,
      ),
    );

    // The build await sits between the gate claim and the main
    // try/finally, so an unexpected throw out of the token read would leak the
    // gate until service rebuild. Release-and-rethrow keeps the existing
    // null-client semantics byte-identical while closing the leak.
    final PluralKitClient? client;
    try {
      client = useRepairToken
          ? await _buildRepairClient(token: token)
          : await _buildClient();
    } catch (_) {
      _emit(_state.copyWith(isSyncing: false));
      if (!gateAlreadyHeld) _releasePull();
      rethrow;
    }
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      if (!gateAlreadyHeld) _releasePull();
      throw StateError(
        useRepairToken
            ? 'PluralKit token is required for one-time import'
            : 'Not connected',
      );
    }

    try {
      final run = await _runFullImportWithClient(
        client,
        updateSyncState: true,
        // Premium systemId refresh: only connected-token runs may
        // rewrite the stored system short id (see helper doc).
        refreshStoredSystemId: !useRepairToken,
      );
      final statusParts = [
        'Imported ${run.members.length} members and '
            '${run.switchesImported} switches.',
        if (run.unmappedMemberReferences > 0)
          '${run.unmappedMemberReferences} switches had unmapped members.',
        if (run.tombstonePreservedCount > 0)
          '${run.tombstonePreservedCount} previously deleted rows stayed '
              'deleted (deletions are permanent and were not undone).',
        if (run.zeroLengthCloseSkipped > 0)
          '${run.zeroLengthCloseSkipped} zero-length closes skipped.',
        if (run.unresolvableMemberRowsPreserved > 0)
          '${run.unresolvableMemberRowsPreserved} rows for excluded/unlinked '
              'members were left as-is.',
      ];

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: statusParts.join(' '),
          lastSyncDate: run.completedAt,
        ),
      );
      return run;
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError('Full import failed: $e'),
        ),
      );
      rethrow;
    } finally {
      client.dispose();
      // Release only the claim we made; the gate-already-held path leaves the
      // outer pull (syncRecentData) to release it in its own finally.
      if (!gateAlreadyHeld) _releasePull();
    }
  }

  /// Import a parsed `pk;export` file.
  ///
  /// Members and groups are imported from the file. The fronting/switches
  /// portion of file imports is DROPPED — fronting history requires API
  /// linking to use the diff-sweep algorithm correctly. Any switches in the
  /// file are silently skipped; the
  /// returned [PkFileImportResult] reports `switchesCreated = 0` and
  /// `switchesSkipped` = the count of switches in the file.
  Future<PkFileImportResult> importFromFile(
    PkFileExport export, {
    void Function(double progress, String status)? onProgress,
  }) async {
    void progress(double p, String s) {
      onProgress?.call(p, s);
      _emit(_state.copyWith(syncProgress: p, syncStatus: s));
    }

    // `importFromFile` previously had NO
    // re-entrancy guard at all — it went straight to `_emit(isSyncing: true)`
    // and an `await _syncDao.getSyncState()`, so it could run concurrently with
    // any other pull (or a second file import). Claim the shared pull gate
    // synchronously before the first await; a busy caller returns a benign
    // "nothing imported" result rather than racing the in-flight sweep.
    if (!_claimPull()) {
      return PkFileImportResult(
        systemName: export.system.name,
        membersImported: 0,
        groupsImported: 0,
        switchesCreated: 0,
        switchesSkipped: export.switches.length,
      );
    }
    try {
      _emit(
        _state.copyWith(
          isSyncing: true,
          syncProgress: 0.0,
          syncStatus: 'Importing from file…',
          clearError: true,
        ),
      );

      // If the app is currently LINKED to a PK system,
      // reject a foreign export before any write. The no-token path has no live
      // API system to compare against, so we compare the export's identity
      // against the linked system row. The sync DAO only persists the short id
      // (set by `setToken`), so this is a short-id comparison even though the
      // export also carries a uuid. If the app is NOT linked (`systemId` null),
      // we allow any file — a fresh import has nothing to clobber.
      final linkedSystemId = (await _syncDao.getSyncState()).systemId?.trim();
      if (linkedSystemId != null && linkedSystemId.isNotEmpty) {
        final fileId = export.system.id.trim();
        if (fileId != linkedSystemId) {
          _emit(_state.copyWith(isSyncing: false));
          throw PkFileSystemMismatchError(
            fileSystemName: export.system.name,
            fileSystemId: export.system.uuid ?? export.system.id,
            targetSystemName: null,
            targetSystemId: linkedSystemId,
          );
        }
      }

      progress(0.05, 'Importing ${export.members.length} members…');
      await _importMembers(
        null,
        export.members,
        // I1: file import skips the interactive mapping screen (the only place
        // name-matching ran), so an unlinked same-name local would otherwise be
        // duplicated. Match it here instead.
        matchUnlinkedByName: true,
        onProgress: (current, total, name) {
          // Member import phase occupies 0.05 → 0.40 of the overall progress
          // bar for file imports. current=1 (i=0) maps to 0.05; current=total
          // (i=last) maps to 0.40.
          final fraction = total <= 1 ? 1.0 : (current - 1) / (total - 1);
          _emit(
            _state.copyWith(
              syncProgress: 0.05 + 0.35 * fraction,
              syncStatus: 'Importing member $current/$total from file: $name',
            ),
          );
        },
      );

      // Local capture: `_groupsImporter` is mutable, so the null check no
      // longer type-promotes the field itself.
      final fileGroupsImporter = _groupsImporter;
      if (export.groups.isNotEmpty && fileGroupsImporter != null) {
        progress(0.40, 'Importing ${export.groups.length} groups…');
        try {
          await fileGroupsImporter.importGroups(
            export.groups,
            overwriteMetadata: true,
            // File import is structurally pull-only (FROM a file INTO local),
            // never push.
            direction: PkSyncDirection.pullOnly,
          );
        } catch (e) {
          debugPrint('[PK_FILE] group import failed (non-fatal): $e');
        }
      }

      // Fronting history from files is not imported: it requires API linking
      // to use the diff-sweep algorithm. Switches are counted and reported so
      // the UI can explain what happened.
      final switchCount = export.switches.length;
      if (switchCount > 0) {
        debugPrint(
          '[PK_FILE] Skipping $switchCount file switches — '
          'fronting history import requires API linking (§2.1).',
        );
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: 'Imported ${export.members.length} members.',
        ),
      );

      return PkFileImportResult(
        systemName: export.system.name,
        membersImported: export.members.length,
        groupsImported: export.groups.length,
        switchesCreated: 0,
        switchesSkipped: switchCount,
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError('File import failed: $e'),
        ),
      );
      rethrow;
    } finally {
      // Always release the pull gate (the claim above
      // returned true to reach this body).
      _releasePull();
    }
  }

  /// Import a `pk;export` file while using a token only to canonicalize
  /// fronting history against PluralKit API switch IDs.
  ///
  /// Members/groups still come from the file import path. Fronting rows are
  /// written only when the file/API switch matcher says canonicalization is
  /// safe; otherwise this returns a mismatch summary without persisting any
  /// fronting rows.
  Future<PkFileTokenFrontingImportResult> importFromFileWithToken(
    PkFileExport export, {
    String? token,
    void Function(double progress, String status)? onProgress,
  }) async {
    void progress(double p, String s) {
      onProgress?.call(p, s);
      _emit(_state.copyWith(syncProgress: p, syncStatus: s));
    }

    // Claim the shared pull gate synchronously (covers the
    // window where another pull holds `_pullInFlight` but has not yet emitted
    // `isSyncing:true`). A busy caller gets the benign "nothing imported"
    // result the method already returned for its old `isSyncing` check.
    if (!_claimPull()) {
      return PkFileTokenFrontingImportResult(
        systemName: export.system.name,
        membersImported: 0,
        groupsImported: 0,
        canonicalizationSafe: false,
        frontingImported: false,
        exactImportedCount: 0,
        staleFileCount: 0,
        ambiguousCount: 0,
        ambiguousKeys: const [],
        fileOnlyCount: export.switches.length,
        apiOnlyInRangeCount: 0,
        apiOnlyOutsideRangeCount: 0,
        apiSwitchesFetched: 0,
        unmappedMemberReferences: 0,
        apiSwitchIdsByFileIndex: const {},
      );
    }

    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Importing from file and PluralKit...',
        clearError: true,
      ),
    );

    // Release-and-rethrow around the build await so a throw out
    // of the token read cannot leak the pull gate (see _performFullImport).
    final PluralKitClient? client;
    try {
      client = await _buildRepairClient(token: token);
    } catch (_) {
      _emit(_state.copyWith(isSyncing: false));
      _releasePull();
      rethrow;
    }
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      _releasePull();
      throw StateError('PluralKit token is required for file + token import');
    }

    try {
      progress(0.03, 'Checking PluralKit token...');
      // Compare the export's system identity against the
      // TOKEN's system BEFORE any member/group write. The previous code called
      // `getSystem()` here and discarded the result, so a wrong file + valid
      // token merged a foreign roster irreversibly (and the rows later became
      // push-eligible). On mismatch we throw before `_importMembers`, so the
      // members table is never touched.
      final tokenSystem = await client.getSystem();
      if (!_systemIdentitiesMatch(export.system, tokenSystem)) {
        throw PkFileSystemMismatchError(
          fileSystemName: export.system.name,
          fileSystemId: export.system.uuid ?? export.system.id,
          targetSystemName: tokenSystem.name,
          targetSystemId: tokenSystem.uuid ?? tokenSystem.id,
        );
      }

      progress(0.05, 'Importing ${export.members.length} members...');
      // I1: file import path — name-match unlinked same-name locals (see the
      // importFromFile call site).
      await _importMembers(null, export.members, matchUnlinkedByName: true);

      // Local capture: `_groupsImporter` is mutable, so the null check no
      // longer type-promotes the field itself.
      final tokenGroupsImporter = _groupsImporter;
      if (export.groups.isNotEmpty && tokenGroupsImporter != null) {
        progress(0.25, 'Importing ${export.groups.length} groups...');
        try {
          await tokenGroupsImporter.importGroups(
            export.groups,
            overwriteMetadata: true,
            direction: PkSyncDirection.pullOnly,
          );
        } catch (e) {
          debugPrint('[PK_FILE_TOKEN] group import failed (non-fatal): $e');
        }
      }

      progress(0.40, 'Fetching PluralKit switches...');
      final apiSwitches = await _fetchSwitchesForFileRange(
        client,
        export.switches,
      );

      progress(0.55, 'Matching file switches to PluralKit...');
      final match = const PkFrontingSwitchMatcher().compare(
        fileSwitches: export.switches,
        apiSwitches: apiSwitches,
      );

      var frontingImported = false;
      var unmappedMemberReferences = 0;
      if (match.canonicalizationSafe) {
        final fileSwitchIdsByApiSwitchId = <String, String>{
          for (final exactMatch in match.exactMatches)
            exactMatch.apiSwitchId: _pkFileSwitchSourceId(
              exactMatch.fileSwitch,
            ),
        };
        final pkImportSourcesByApiSwitchId = <String, String>{
          for (final exactMatch in match.exactMatches)
            exactMatch.apiSwitchId: pkImportSourceFileApi,
        };

        progress(0.70, 'Importing canonical fronting history...');
        final shortIdToUuid = await _buildShortIdToUuidMap();
        if (shortIdToUuid.isEmpty && apiSwitches.isNotEmpty) {
          throw StateError(
            'No PluralKit members resolved to local members. '
            'Ensure members are imported before importing fronting history.',
          );
        }

        final sweepResult = await _runDiffSweep(
          switches: apiSwitches,
          shortIdToUuid: shortIdToUuid,
          corrective: true,
          pkImportSourceByApiSwitchId: pkImportSourcesByApiSwitchId,
          pkFileSwitchIdsByApiSwitchId: fileSwitchIdsByApiSwitchId,
        );
        unmappedMemberReferences = sweepResult.unmappedCount;
        frontingImported = true;
      } else {
        debugPrint(
          '[PK_FILE_TOKEN] switch canonicalization blocked: '
          'fileOnly=${match.fileOnlyCount}, '
          'apiOnlyInRange=${match.apiOnlyInsideFileRangeCount}, '
          'ambiguous=${match.ambiguousCount}',
        );
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: frontingImported
              ? 'Imported canonical PluralKit fronting history.'
              : 'Imported file data; fronting history needs review.',
        ),
      );

      return PkFileTokenFrontingImportResult(
        systemName: export.system.name,
        membersImported: export.members.length,
        groupsImported: export.groups.length,
        canonicalizationSafe: match.canonicalizationSafe,
        frontingImported: frontingImported,
        exactImportedCount: frontingImported ? match.exactMatchCount : 0,
        staleFileCount: match.apiOnlyOutsideFileRangeCount,
        ambiguousCount: match.ambiguousCount,
        ambiguousKeys: List.unmodifiable(
          match.ambiguousKeys.map((entry) => entry.key.toString()),
        ),
        fileOnlyCount: match.fileOnlyCount,
        apiOnlyInRangeCount: match.apiOnlyInsideFileRangeCount,
        apiOnlyOutsideRangeCount: match.apiOnlyOutsideFileRangeCount,
        apiSwitchesFetched: apiSwitches.length,
        unmappedMemberReferences: unmappedMemberReferences,
        apiSwitchIdsByFileIndex: match.apiSwitchIdsByFileIndex,
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError('File + token import failed: $e'),
        ),
      );
      rethrow;
    } finally {
      client.dispose();
      _releasePull();
    }
  }

  /// Sync recent changes since last sync.
  ///
  /// When [direction] includes member sync, local member changes are pushed to
  /// PK and/or PK member changes are pulled according to the selected
  /// direction.
  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) async {
    if (!_state.canAutoSync) {
      throw StateError(
        'Setup incomplete — confirm direction and mapping before auto-syncing.',
      );
    }
    // Enforce the manual cooldown IN-SERVICE before any
    // gate claim or side effect — the fronting-screen sync button has no
    // button-disable guard, so without this a tap could fire a full sync every
    // time. Throws a typed cooldown exception the caller surfaces as a "please
    // wait" toast; automatic syncs are never cooled down.
    _enforceManualCooldown(isManual: isManual);
    // Claim the service-level pull gate SYNCHRONOUSLY
    // (no await between check and claim) so a concurrent caller can't slip
    // through during the first-sync branch's token-read await gap. The loser
    // returns null WITHOUT stamping a cooldown or emitting a phantom
    // `PkSyncCompleted`.
    if (!_claimPull()) return null;
    try {
      return await _syncRecentDataInner(
        isManual: isManual,
        direction: direction,
      );
    } finally {
      _releasePull();
    }
  }

  /// Body of [syncRecentData]. Runs with the pull gate already held by the
  /// public entry point, so its first-sync branch can call
  /// `_performFullImport(gateAlreadyHeld: true)` without re-claiming.
  Future<PkSyncSummary?> _syncRecentDataInner({
    required bool isManual,
    required PkSyncDirection direction,
  }) async {
    final stopwatch = Stopwatch()..start();
    _bus.emit(
      PkSyncStarted(
        trigger: isManual ? 'manual' : 'auto',
        direction: direction.name,
        mode: 'incremental',
      ),
    );
    if (_state.lastSyncDate == null && direction.pullEnabled) {
      // Never synced before in a pull-capable mode — seed local state from PK.
      // Push-only must not silently fall into this branch; that would pull
      // member/group/profile data despite the user's selected direction.
      // for redaction on the error path, then re-read on failure so we redact
      // against whichever value the failing client actually used (a
      // clearToken/setToken race between the two reads could otherwise leave
      // one value stale).
      final capturedToken = await _getToken();
      try {
        // The pull gate is already held by syncRecentData,
        // so run the full import WITHOUT re-claiming. Previously this called the
        // public `performFullImport()`, whose own `isSyncing` check could pass
        // for a concurrent caller during this branch's await gap, then silently
        // no-op inside — while the code below still stamped `lastManualSyncDate`
        // and emitted a successful `PkSyncCompleted(0,0)` that never ran.
        await _performFullImport(gateAlreadyHeld: true);
      } catch (e) {
        final postFailureToken = await _getToken();
        var error = PkSyncEvent.redact(e.toString(), capturedToken);
        if (postFailureToken != null && postFailureToken != capturedToken) {
          error = PkSyncEvent.redact(error, postFailureToken);
        }
        _bus.emit(
          PkSyncCompleted(
            durationMs: stopwatch.elapsedMilliseconds,
            pulled: 0,
            pushed: 0,
            error: error,
          ),
        );
        rethrow;
      }
      if (isManual) {
        final now = DateTime.now();
        await _syncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            lastManualSyncDate: Value(now),
          ),
        );
        _emit(_state.copyWith(lastManualSyncDate: now));
      }
      _bus.emit(
        PkSyncCompleted(
          durationMs: stopwatch.elapsedMilliseconds,
          pulled: 0,
          pushed: 0,
        ),
      );
      return null;
    }

    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Syncing recent changes...',
        clearError: true,
      ),
    );

    final client = await _buildClient();
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      _bus.emit(
        PkSyncCompleted(
          durationMs: stopwatch.elapsedMilliseconds,
          pulled: 0,
          pushed: 0,
          error: 'Not connected',
        ),
      );
      throw StateError('Not connected');
    }

    try {
      // Accumulates messages for PK-side 404s we detected during this run.
      // Surfaced via `syncError` at the end so the user sees that a linked
      // member or switch was deleted on PK (otherwise the unlink would be
      // silent — see bug S3).
      final staleLinkMessages = <String>[];

      // -- Member field sync --
      PkSyncSummary? summary;
      if (direction.pullEnabled || direction.pushEnabled) {
        _emit(
          _state.copyWith(syncProgress: 0.1, syncStatus: 'Syncing members...'),
        );

        // Wave 4 Premium systemId refresh: keep the stored system short id
        // fresh on the REGULAR sync cadence, not just on rare full imports — a
        // Premium system-hid rename would otherwise false-positive every
        // stored-id ownership comparison until the next full re-import. One
        // extra GET next to the much heavier getMembers call;
        // this client is always the connected token, so the rename inference
        // is safe (see [_refreshStoredSystemIdIfChanged]).
        await _refreshStoredSystemIdIfChanged(await client.getSystem());

        final pkMembers = await client.getMembers();

        // Load per-member field configs
        final row = await _syncDao.getSyncState();
        final fieldConfigs = parseFieldSyncConfig(row.fieldSyncConfig);

        final allMembers = await _memberRepository.getAllMembers();

        // Snapshot linked-member names before the bidirectional run so we can
        // detect stale-link clears.
        final linkedBefore = <String, String>{
          for (final m in allMembers)
            if (hasPluralKitLink(m)) m.id: m.name,
        };

        // F14: the bidirectional PUSH path counts a never-seen PK member as
        // "pulled" but never creates it, so a member added on PK after setup
        // silently never appeared until a manual full import. Create the unseen
        // ones up front through the full importer, so the bidirectional pass
        // below (which still reads the pre-create snapshot) treats them as pulled.
        if (direction.pullEnabled) {
          final linkedUuids = <String>{
            for (final m in allMembers)
              if (m.pluralkitUuid != null && m.pluralkitUuid!.trim().isNotEmpty)
                m.pluralkitUuid!.trim(),
          };
          final linkedIds = <String>{
            for (final m in allMembers)
              if (m.pluralkitId != null && m.pluralkitId!.trim().isNotEmpty)
                m.pluralkitId!.trim(),
          };
          final unseen = pkMembers
              .where((pk) =>
                  !linkedUuids.contains(pk.uuid.trim()) &&
                  !linkedIds.contains(pk.id.trim()))
              .toList();
          if (unseen.isNotEmpty) {
            // matchUnlinkedByName: an after-setup PK member skips the mapping
            // screen, so dedup it against a same-name unlinked local here — so
            // this device adopts the SAME shared local the file-import path (I1)
            // adopts, instead of minting a random id that diverges cross-device.
            await _importMembers(client, unseen, matchUnlinkedByName: true);
          }
        }

        final biService = PkBidirectionalService(
          bannerCacheService: _bannerCacheService,
        );
        summary = await biService.syncMembers(
          localMembers: allMembers,
          pkMembers: pkMembers,
          fieldConfigs: fieldConfigs,
          direction: direction,
          lastSyncDate: _state.lastSyncDate,
          memberRepository: _memberRepository,
          client: client,
        );

        // Detect stale-link clears.
        final afterMembers = await _memberRepository.getAllMembers();
        final afterById = {for (final m in afterMembers) m.id: m};
        for (final entry in linkedBefore.entries) {
          final now = afterById[entry.key];
          if (now == null) continue;
          if (!hasPluralKitLink(now)) {
            staleLinkMessages.add(
              "PluralKit member '${entry.value}' was removed on the "
              'server — unlinked locally. Re-link from the mapping screen '
              'to resume syncing.',
            );
          }
        }

        _emit(
          _state.copyWith(
            syncProgress: 0.3,
            syncStatus: 'Members synced. Fetching switches...',
          ),
        );
      }

      // -- Groups (membership reconcile + bidirectional push) --
      // Pass the user's actual sync direction so:
      //   pullOnly       → reconcile only (reconcile skips push_add rows).
      //   pushOnly       → drain pending_pk_op to PK; no destructive pull.
      //   bidirectional  → reconcile then push (local adds reach PK).
      //   disabled       → noop (caller never enters this code path).
      await _importGroups(
        client,
        overwriteMetadata: false,
        direction: direction,
      );

      // -- Pull recent switches via incremental diff sweep --
      //
      // Resume cursor: read (switchCursorTimestamp, switchCursorId) from DB
      // as a `PkSwitchCursor`. PK paginates newest-first via the `before`
      // query param (max 100 switches/page). We fetch newest first, walk
      // backwards by `before = page.last.timestamp`, and accept every switch
      // strictly newer than the cursor — i.e. `(sw.ts, sw.id) > cursor`
      // lexicographically. Switches at the same timestamp as the cursor with
      // a different id are *not* skipped, because they were never processed
      // on the prior sweep.
      //
      // Pagination is bounded by [_maxIncrementalPages] and aborts on a
      // no-progress page (where `before = page.last.timestamp` doesn't
      // advance), surfacing typed errors instead of spinning forever.
      int totalNew = 0;
      int totalUnmapped = 0;
      int pullPages = 0;
      int pullFetched = 0;
      int pullApplied = 0;
      int pullDurationMs = 0;
      if (direction.pullEnabled) {
        final pullStopwatch = Stopwatch()..start();
        final cursorRow = await _syncDao.getSyncState();
        final PkSwitchCursor? cursor =
            (cursorRow.switchCursorTimestamp != null &&
                cursorRow.switchCursorId != null)
            ? PkSwitchCursor(
                timestamp: cursorRow.switchCursorTimestamp!,
                switchId: cursorRow.switchCursorId!,
              )
            : null;

        debugPrint(
          '[PK_PULL] incremental sweep cursor='
          '${cursor?.toString() ?? 'null'}',
        );


        final newSwitches = <PKSwitch>[];
        // `reachedCursor` must start false: a null cursor means "walk ALL of
        // history", terminated by a short page or the page cap. Seeding it with
        // `cursor == null` made page 1 the only page and silently gapped history
        // past the newest 100 switches.
        bool reachedCursor = false;
        final counts = await _paginateSwitchesNewestFirst(
          client,
          onPage: (fresh) {
            for (final sw in fresh) {
              // Skip any switch at or before the cursor lexicographically.
              // Crucially, switches at the same timestamp as the cursor but a
              // different id are NOT covered and must be processed.
              if (cursor != null && cursor.covers(sw.timestamp, sw.id)) {
                reachedCursor = true;
                continue;
              }
              newSwitches.add(sw);
            }
            return !reachedCursor;
          },
        );
        final int pageNum = counts.pages;
        final int totalFetched = counts.fetched;
        debugPrint('[PK_PULL] paged $pageNum page(s), fetched $totalFetched');

        // Sort oldest-first for chronological diff sweep. PluralKit can
        // return multiple switches at the same timestamp; the cursor treats a
        // larger switch id as newer, so replay must use that same ordering.
        newSwitches.sort(_compareSwitchesChronologically);

        debugPrint('[PK_PULL] ${newSwitches.length} new switches to process');

        if (newSwitches.isNotEmpty) {
          // Build after member sync so short-id-only repaired rows can resolve
          // switch member references on this same pass.
          final resolvedShortIdToUuid = await _buildShortIdToUuidMap();

          final sweepResult = await _runDiffSweep(
            switches: newSwitches,
            shortIdToUuid: resolvedShortIdToUuid,
            onProgress: (i) {
              if (i % 50 == 0 || i == newSwitches.length - 1) {
                final total = newSwitches.length;
                _emit(
                  _state.copyWith(
                    syncProgress: 0.5 + 0.4 * (total == 0 ? 1.0 : i / total),
                    syncStatus: 'Processing switch ${i + 1}/$total...',
                  ),
                );
              }
            },
          );
          totalNew = newSwitches.length;
          totalUnmapped = sweepResult.unmappedCount;
        }
        pullStopwatch.stop();
        pullPages = pageNum;
        pullFetched = totalFetched;
        pullApplied = totalNew;
        pullDurationMs = pullStopwatch.elapsedMilliseconds;
        _bus.emit(
          PkSyncPullCompleted(
            pages: pullPages,
            fetched: pullFetched,
            applied: pullApplied,
            durationMs: pullDurationMs,
          ),
        );
      } else {
        debugPrint(
          '[PK_PULL] skipped — pullEnabled=false direction=$direction',
        );
      }

      // Phase 4: scoped push.
      final pushResult = direction.pushEnabled
          ? await pushPendingSwitches(
              onStaleLink: staleLinkMessages.add,
              allowDuringSync: true,
            )
          : const PkPushSwitchesResult();
      final int switchesPushed = pushResult.pushed;

      // Push deletions with switches first.
      int switchesDeletedOnPk = 0;
      int membersDeletedOnPk = 0;
      if (direction.pushEnabled) {
        // Mass-deletion breaker: a MANUAL sync reaches
        // here only AFTER the setup screen's `_confirmPluralKitDeleteRisk`
        // consent gate (`_syncRecent` → `previewPendingDestructivePush` →
        // confirmation dialog), so a deliberate large cleanup is allowed. An
        // AUTOMATIC (background / auto-poll) sync has no such consent, so the
        // breaker can trip and skip an oversized deletion batch.
        switchesDeletedOnPk = await _pushPendingSwitchDeletions(
          client: client,
          onStaleLink: staleLinkMessages.add,
          allowMassDeletion: isManual,
        );
        membersDeletedOnPk = await _pushPendingMemberDeletions(
          client: client,
          onStaleLink: staleLinkMessages.add,
          allowMassDeletion: isManual,
        );
        // The PkSwitchPushed event emitted inside pushPendingSwitches only
        // knows about creations (it runs before this deletion pass). Emit a
        // companion event here so the sync log surfaces the deletion count.
        // The bus is an event stream — two events for one logical operation
        // is fine and matches how pull/push are already split.
        if (switchesDeletedOnPk > 0) {
          _bus.emit(PkSwitchPushed(pushed: 0, deleted: switchesDeletedOnPk));
        }
      }

      final now = DateTime.now();
      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastSyncDate: Value(now),
          lastManualSyncDate: isManual ? Value(now) : const Value.absent(),
        ),
      );

      // Build final summary
      final finalSummary = PkSyncSummary(
        membersPulled: summary?.membersPulled ?? 0,
        membersPushed: summary?.membersPushed ?? 0,
        membersSkipped: summary?.membersSkipped ?? 0,
        switchesPulled: totalNew,
        switchesPushed: switchesPushed,
        membersDeletedOnPk: membersDeletedOnPk,
        switchesDeletedOnPk: switchesDeletedOnPk,
        staleLinkMessages: List.unmodifiable(staleLinkMessages),
        // Per-member push isolation converts what used to be a
        // sync-aborting throw into a skipped member + message; the COUNT
        // already flows via `membersSkipped`, but the rebuild above dropped
        // the message list, so the UI summary card could never explain WHICH
        // members were skipped or why.
        pushSkippedMessages: List.unmodifiable(
          summary?.pushSkippedMessages ?? const <String>[],
        ),
      );

      final statusParts = <String>[];
      if (finalSummary.membersPulled > 0) {
        statusParts.add('Pulled ${finalSummary.membersPulled} members');
      }
      if (finalSummary.membersPushed > 0) {
        statusParts.add('Pushed ${finalSummary.membersPushed} members');
      }
      if (totalNew > 0) {
        statusParts.add('Pulled $totalNew switches');
      }
      if (totalUnmapped > 0) {
        statusParts.add('$totalUnmapped switches had unmapped members');
      }
      if (finalSummary.switchesDeletedOnPk > 0) {
        statusParts.add(
          'Deleted ${finalSummary.switchesDeletedOnPk} switches on PK',
        );
      }
      if (finalSummary.membersDeletedOnPk > 0) {
        statusParts.add(
          'Deleted ${finalSummary.membersDeletedOnPk} members on PK',
        );
      }

      // Surface push-skip messages through the same channel as
      // stale-link messages — a member whose PATCH was rejected/dropped is
      // user-actionable (fix the oversized field, re-sync) and must not vanish
      // into a debugPrint.
      final userFacingMessages = <String>[
        ...staleLinkMessages,
        ...finalSummary.pushSkippedMessages,
      ];
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: statusParts.isNotEmpty
              ? '${statusParts.join('. ')}.'
              : 'Everything is up to date.',
          syncError: userFacingMessages.isEmpty
              ? null
              : userFacingMessages.join('\n'),
          clearError: userFacingMessages.isEmpty,
          lastSyncDate: now,
          lastManualSyncDate: isManual ? now : _state.lastManualSyncDate,
        ),
      );

      _bus.emit(
        PkSyncCompleted(
          durationMs: stopwatch.elapsedMilliseconds,
          pulled: finalSummary.membersPulled + totalNew,
          pushed: switchesPushed,
        ),
      );

      return finalSummary;
    } on PluralKitAuthError catch (e) {
      // A 401 mid-sync (token revoked between connect and
      // now) must produce a DISTINCT, actionable user-facing error and emit the
      // dedicated auth-failed bus event — not the generic "PluralKit sync
      // failed: …" string that reads like a transient blip. We do NOT
      // auto-clear the token; the user re-links from the setup screen. Tone
      // mirrors `setToken`'s 401 copy.
      const authMessage =
          'PluralKit token was rejected — re-link your account in PluralKit '
          'settings to keep syncing.';
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError(authMessage),
        ),
      );
      final redacted = PkSyncEvent.redact(e.toString(), client.currentToken);
      _bus.emit(
        PkSyncCompleted(
          durationMs: stopwatch.elapsedMilliseconds,
          pulled: 0,
          pushed: 0,
          error: authMessage,
        ),
      );
      _bus.emit(const PkTokenAuthFailed());
      _bus.emit(
        PkRequestFailed(
          stage: 'syncRecentData',
          errorKind: 'auth',
          message: redacted,
        ),
      );
      rethrow;
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError(e),
        ),
      );
      // Redact against the live client's token rather than a separately
      // captured value — see the importMembersOnly comment for the race.
      final redacted = PkSyncEvent.redact(e.toString(), client.currentToken);
      _bus.emit(
        PkSyncCompleted(
          durationMs: stopwatch.elapsedMilliseconds,
          pulled: 0,
          pushed: 0,
          error: redacted,
        ),
      );
      _bus.emit(
        PkRequestFailed(
          stage: 'syncRecentData',
          errorKind: 'unknown',
          message: redacted,
        ),
      );
      rethrow;
    } finally {
      client.dispose();
    }
  }

  /// Sync only the currently-live PluralKit fronter snapshot.
  ///
  /// This intentionally bypasses [syncRecentData]: it does not fetch switch
  /// history, members, groups, or profile data, and it does not advance the
  /// incremental switch cursor or stamp [PluralKitSyncState.lastSyncDate].
  Future<PkSyncSummary?> syncLiveFrontersOnly({
    required PkSyncDirection direction,
    bool isManual = false,
    PKSwitch? knownCurrentFronters,
  }) async {
    if (!_state.canAutoSync) return null;
    // Enforce the manual cooldown in-service (the
    // fronting-screen / setup-screen sync buttons both route manual live-front
    // syncs here), then claim the shared pull gate synchronously so this can't
    // interleave with an incremental sweep — two passes holding independent
    // in-memory active maps would re-close rows at different timestamps.
    _enforceManualCooldown(isManual: isManual);
    if (!_claimPull()) return null;

    final stopwatch = Stopwatch()..start();
    _bus.emit(
      PkSyncStarted(
        trigger: isManual ? 'manual' : 'auto',
        direction: direction.name,
        mode: 'live',
      ),
    );

    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Syncing live fronters...',
        clearError: true,
      ),
    );

    // Track the live client's token for redaction in the failure path. We
    // capture it from `client.currentToken` after the client is built so a
    // clearToken/setToken race between read-and-build can't leave us
    // redacting against a stale or null token. Kept nullable because the
    // pushOnly direction skips the client-building branch entirely.
    String? clientToken;

    try {
      int switchesPulled = 0;
      int switchesPushed = 0;
      PKSwitch? current;
      PkUnmappedFrontersNotice? liveUnmappedFronters;
      var observedLiveFronters = false;
      String? observedLiveFrontersDismissalKey;
      var skipPush = false;
      final staleLinkMessages = <String>[];

      if (direction.pullEnabled) {
        // Use the caller-supplied switch (cache pass-through) when available to
        // avoid a redundant network round trip. Only fetch from the API when
        // no cached value was provided.
        if (knownCurrentFronters != null) {
          current = knownCurrentFronters;
          observedLiveFronters = true;
        } else {
          final client = await _buildClient();
          if (client == null) {
            _emit(_state.copyWith(isSyncing: false));
            throw StateError('Not connected');
          }
          clientToken = client.currentToken;

          try {
            current = await client.getCurrentFronters();
            observedLiveFronters = true;
          } finally {
            client.dispose();
          }
        }

        if (current != null) {
          final pullResult = await _pullLiveFronterSwitch(current);
          switchesPulled = pullResult.pulled ? 1 : 0;
          liveUnmappedFronters = pullResult.unmappedNotice;
          observedLiveFrontersDismissalKey = pullResult.observedDismissalKey;
          skipPush = pullResult.skippedForUnmapped;
          if (pullResult.pulled) {
            _bus.emit(
              PkLiveFronterApplied(memberCount: current.members.length),
            );
          } else if (pullResult.skippedForUnmapped) {
            _bus.emit(const PkLiveFronterSkipped(reason: 'unmapped'));
          }
        }
      }

      if (direction.pushEnabled && !skipPush) {
        final pushResult = await pushPendingSwitches(
          allowDuringSync: true,
          knownCurrentFronters: current,
          refreshMembersOnStaleLink: false,
          onStaleLink: staleLinkMessages.add,
        );
        switchesPushed = pushResult.pushed;
      }

      final now = DateTime.now();
      if (isManual) {
        await _syncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            lastManualSyncDate: Value(now),
          ),
        );
      }

      final statusParts = <String>[];
      if (switchesPulled > 0) statusParts.add('Pulled current fronter switch');
      if (switchesPushed > 0) statusParts.add('Pushed current fronter switch');
      if (liveUnmappedFronters != null) {
        statusParts.add(
          'Review current PluralKit fronters to finish importing this switch',
        );
      }
      if (staleLinkMessages.isNotEmpty) {
        statusParts.add('Skipped stale PluralKit switch links');
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: statusParts.isNotEmpty
              ? '${statusParts.join('. ')}.'
              : 'Live fronters are up to date.',
          clearError: true,
          lastManualSyncDate: isManual ? now : _state.lastManualSyncDate,
        ),
      );

      _bus.emit(
        PkSyncCompleted(
          durationMs: stopwatch.elapsedMilliseconds,
          pulled: switchesPulled,
          pushed: switchesPushed,
        ),
      );

      return PkSyncSummary(
        switchesPulled: switchesPulled,
        switchesPushed: switchesPushed,
        staleLinkMessages: staleLinkMessages,
        liveUnmappedFronters: liveUnmappedFronters,
        observedLiveFronters: observedLiveFronters,
        observedLiveFrontersDismissalKey: observedLiveFrontersDismissalKey,
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError('Live fronters sync failed: $e'),
        ),
      );
      // Fall back to a fresh storage read if we never got far enough to
      // capture a client token (pushOnly direction, or pre-build failure).
      final redactToken = clientToken ?? await _getToken();
      final redacted = PkSyncEvent.redact(e.toString(), redactToken);
      _bus.emit(
        PkSyncCompleted(
          durationMs: stopwatch.elapsedMilliseconds,
          pulled: 0,
          pushed: 0,
          error: redacted,
        ),
      );
      _bus.emit(
        PkRequestFailed(
          stage: 'syncLiveFrontersOnly',
          errorKind: 'unknown',
          message: redacted,
        ),
      );
      rethrow;
    } finally {
      _releasePull();
    }
  }

  Future<
    ({
      bool pulled,
      PkUnmappedFrontersNotice? unmappedNotice,
      String? observedDismissalKey,
      bool skippedForUnmapped,
    })
  >
  _pullLiveFronterSwitch(PKSwitch current) async {
    final currentSwitchId = current.id.trim();
    if (currentSwitchId.isEmpty) {
      return (
        pulled: false,
        unmappedNotice: null,
        observedDismissalKey: null,
        skippedForUnmapped: false,
      );
    }
    final systemId = (await _syncDao.getSyncState()).systemId;
    final observedDismissalKey = pkUnmappedFrontersDismissalKey(
      systemId: systemId,
      switchId: currentSwitchId,
      switchTimestamp: current.timestamp,
      sortedPkIds: current.members,
    );

    final sessions = await _frontingSessionRepository.getAllSessions();
    final seenLive = sessions.any(
      (s) => !s.isDeleted && s.pluralkitUuid?.trim() == currentSwitchId,
    );
    if (seenLive) {
      return (
        pulled: false,
        unmappedNotice: null,
        observedDismissalKey: observedDismissalKey,
        skippedForUnmapped: false,
      );
    }

    final deletedLinked = await _frontingSessionRepository
        .getDeletedLinkedSessions();
    final seenDeleted = deletedLinked.any(
      (s) => s.pluralkitUuid?.trim() == currentSwitchId,
    );
    if (seenDeleted) {
      return (
        pulled: false,
        unmappedNotice: null,
        observedDismissalKey: observedDismissalKey,
        skippedForUnmapped: false,
      );
    }

    final shortIdToUuid = await _buildShortIdToUuidMap();
    final uuidToLocalId = await _buildUuidToLocalIdMap();
    final pkUuidByLocalId = <String, String>{
      for (final entry in uuidToLocalId.entries) entry.value: entry.key,
    };

    final unmapped = <String>[];
    final currentLocalIds = <String>{};
    for (final pkId in current.members) {
      final pkUuid = shortIdToUuid[pkId];
      final localId = pkUuid == null ? null : uuidToLocalId[pkUuid];
      if (localId == null) {
        unmapped.add(pkId);
      } else {
        currentLocalIds.add(localId);
      }
    }
    if (unmapped.isNotEmpty) {
      final notice = _buildUnmappedFrontersNotice(
        current,
        unmapped,
        systemId: systemId,
      );
      debugPrint(
        '[PK_LIVE] Skipped current PluralKit switch because '
        '${unmapped.length} ${unmapped.length == 1 ? 'member is' : 'members are'} '
        'unmapped.',
      );
      return (
        pulled: false,
        unmappedNotice: notice,
        observedDismissalKey: notice.dismissalKey,
        skippedForUnmapped: true,
      );
    }

    await _adoptMatchingUnlinkedLiveRows(
      currentSwitch: current,
      currentLocalIds: currentLocalIds,
    );

    await _runDiffSweep(
      switches: [current],
      shortIdToUuid: shortIdToUuid,
      advanceCursor: false,
      uuidToLocalIdOverride: uuidToLocalId,
      pkUuidByLocalIdOverride: pkUuidByLocalId,
    );
    return (
      pulled: true,
      unmappedNotice: null,
      observedDismissalKey: observedDismissalKey,
      skippedForUnmapped: false,
    );
  }

  Future<void> _adoptMatchingUnlinkedLiveRows({
    required PKSwitch currentSwitch,
    required Set<String> currentLocalIds,
  }) async {
    if (currentLocalIds.isEmpty) return;

    final switchId = currentSwitch.id.trim();
    if (switchId.isEmpty) return;

    final activeSessions = await _frontingSessionRepository
        .getAllActiveSessionsUnfiltered();
    for (final session in activeSessions) {
      if (session.isDeleted || session.isSleep) continue;
      if (_hasText(session.pluralkitUuid)) continue;
      final memberId = session.memberId;
      if (memberId == null || !currentLocalIds.contains(memberId)) continue;
      // `session.startTime` is a persisted (whole-second) value; truncate the
      // API side so the bound compares like-for-like.
      if (session.startTime.isAfter(
        truncatePkTimestampToDriftPrecision(currentSwitch.timestamp),
      )) {
        continue;
      }

      try {
        await _frontingSessionRepository.updateSession(
          session.copyWith(pluralkitUuid: switchId),
        );
      } catch (error) {
        if (isUniqueConstraintViolation(error)) {
          debugPrint(
            '[PK_LIVE] adoption collision on ($switchId,$memberId); '
            'leaving existing rows unchanged.',
          );
          continue;
        }
        rethrow;
      }
    }
  }

  PkUnmappedFrontersNotice _buildUnmappedFrontersNotice(
    PKSwitch current,
    List<String> unmappedIds, {
    required String? systemId,
  }) {
    final detailsById = {
      for (final detail in current.memberDetails) detail.id: detail,
    };
    final sortedCurrentIds = _sortedUniqueStrings(current.members);
    return PkUnmappedFrontersNotice(
      systemId: systemId,
      switchId: current.id.trim(),
      switchTimestamp: current.timestamp,
      sortedPkIds: sortedCurrentIds,
      refs: [
        for (final pkId in unmappedIds)
          PkUnmappedFronterRef(
            pkId: pkId,
            pkUuid: detailsById[pkId]?.uuid,
            // raw-name-ok: PluralKit API details object, not a Prism member
            name: detailsById[pkId]?.name,
            displayName: detailsById[pkId]?.displayName,
            avatarUrl: detailsById[pkId]?.avatarUrl,
          ),
      ],
    );
  }

  /// Fetch the PK system-level avatar and store it on the local settings row.
  ///
  /// Returns `true` iff an avatar was fetched AND stored. Returns `false`
  /// when PK reports no system avatar, when the helper declines the download
  /// (timeout, non-image, oversize), or when no [SystemSettingsRepository]
  /// was wired into this service.
  ///
  /// Track 04 (disclosure toggle) is the expected caller; it gates the call
  /// behind a user-facing checkbox.
  Future<bool> importSystemAvatar() async {
    // Local capture: `_settingsRepository` is mutable, so the null check no
    // longer type-promotes the field itself.
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) return false;
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');
    try {
      final system = await client.getSystem();
      final url = system.avatarUrl;
      if (url == null || url.isEmpty) return false;
      final bytes = await fetchAvatarBytes(url);
      if (bytes == null) return false;
      await settingsRepository.updateSystemAvatarData(bytes);
      return true;
    } finally {
      client.dispose();
    }
  }

  Future<domain.Member> importCurrentFronter(
    PkUnmappedFronterRef ref, {
    bool includeAvatar = false,
  }) async {
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');
    try {
      // Thread the connected system id so the resolver
      // can reject a foreign member returned by a stale short-id GET.
      final connectedSystemId = (await _syncDao.getSyncState()).systemId;
      return await PkLiveFronterResolutionService(
        memberRepository: _memberRepository,
        client: client,
        connectedSystemId: connectedSystemId,
      ).importCurrentFronter(ref, includeAvatar: includeAvatar);
    } finally {
      client.dispose();
    }
  }

  Future<domain.Member> linkCurrentFronterToLocal(
    PkUnmappedFronterRef ref,
    String localMemberId,
  ) async {
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');
    try {
      // Thread the connected system id (see above).
      final connectedSystemId = (await _syncDao.getSyncState()).systemId;
      return await PkLiveFronterResolutionService(
        memberRepository: _memberRepository,
        client: client,
        connectedSystemId: connectedSystemId,
      ).linkCurrentFronterToLocal(ref, localMemberId);
    } finally {
      client.dispose();
    }
  }

  /// Fetch the PK system profile without writing anything. Callers show the
  /// first-pull disclosure and then invoke [adoptSystemProfile] for the
  /// subset of fields the user accepted.
  ///
  /// Returns `null` when the service is not connected (no token) — the setup
  /// screen can then skip the disclosure entirely.
  Future<PKSystem?> fetchSystemProfile() async {
    final client = await _buildClient();
    if (client == null) return null;
    try {
      return await client.getSystem();
    } finally {
      client.dispose();
    }
  }

  /// Write the user-selected subset of the PK system profile into Prism's
  /// `system_settings`. Each field write is isolated in its own try/catch so
  /// a single failure doesn't abort the rest of the adoption. Failures are
  /// surfaced via [PluralKitSyncState.syncError] but never raised — the
  /// connection itself is already established at this point.
  Future<void> adoptSystemProfile({
    required PKSystem pk,
    required Set<PkProfileField> accepted,
  }) async {
    // Local capture: `_settingsRepository` is mutable, so the null check no
    // longer type-promotes the field itself.
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) return;
    final failures = <String>[];

    if (accepted.contains(PkProfileField.name) &&
        pk.name != null &&
        pk.name!.isNotEmpty) {
      try {
        await settingsRepository.updateSystemName(pk.name);
      } catch (e) {
        failures.add('name ($e)');
      }
    }
    if (accepted.contains(PkProfileField.description) &&
        pk.description != null &&
        pk.description!.isNotEmpty) {
      try {
        await settingsRepository.updateSystemDescription(pk.description);
      } catch (e) {
        failures.add('description ($e)');
      }
    }
    if (accepted.contains(PkProfileField.tag) &&
        pk.tag != null &&
        pk.tag!.isNotEmpty) {
      try {
        await settingsRepository.updateSystemTag(pk.tag);
      } catch (e) {
        failures.add('tag ($e)');
      }
    }
    if (accepted.contains(PkProfileField.avatar) &&
        pk.avatarUrl != null &&
        pk.avatarUrl!.isNotEmpty) {
      try {
        await importSystemAvatar();
      } catch (e) {
        failures.add('avatar ($e)');
      }
    }

    if (failures.isNotEmpty) {
      _emit(
        _state.copyWith(
          syncError: formatPluralKitSyncError(
            'Some profile fields did not import: '
            '${failures.join(', ')}',
          ),
        ),
      );
    }
  }

  /// Phase 1 PK-groups pull.
  ///
  /// - `overwriteMetadata=false` (background `syncRecentData`): new groups are
  ///   inserted, memberships are reconciled against the authoritative PK set,
  ///   but existing row metadata (name/description/color/displayOrder) is NOT
  ///   overwritten. Local edits survive the sync.
  /// - `overwriteMetadata=true` (`performFullImport` / explicit re-import):
  ///   metadata is replaced with PK's values.
  ///
  /// Returns 0 when no importer was wired (e.g. older tests that construct
  /// the service without an AppDatabase reference) — callers can still proceed.
  Future<PkGroupsImportResult?> _importGroups(
    PluralKitClient client, {
    required bool overwriteMetadata,
    required PkSyncDirection direction,
  }) async {
    final importer = _groupsImporter;
    if (importer == null) return null;
    try {
      // Pull side: only fetch + reconcile when the direction includes pull.
      // pushOnly users skip the network round-trip entirely.
      PkGroupsImportResult? pullResult;
      if (direction.pullEnabled) {
        final pkGroups = await client.getGroups(withMembers: true);
        pullResult = await importer.importGroups(
          pkGroups,
          overwriteMetadata: overwriteMetadata,
          direction: direction,
        );
      }
      // Push side: drain pending_pk_op intents to PK after pull-reconcile so
      // the snapshot push sees the user's current state. The push result isn't
      // merged into PkGroupsImportResult yet (different shape, different
      // lifecycle); log the summary for debugging until a UI surface exists.
      if (direction.pushEnabled) {
        final pushResult = await importer.pushPendingGroupOps(
          client,
          direction,
        );
        if (pushResult.added != 0 ||
            pushResult.removed != 0 ||
            pushResult.failed != 0 ||
            pushResult.compensated != 0 ||
            pushResult.stranded != 0) {
          debugPrint(
            '[PK push] group membership: '
            'added=${pushResult.added} removed=${pushResult.removed} '
            'failed=${pushResult.failed} compensated=${pushResult.compensated} '
            'stranded=${pushResult.stranded}',
          );
        }
      }
      return pullResult;
    } catch (e) {
      // Groups are not a first-class blocker for the rest of the sync — don't
      // abort members/switches on a group-fetch failure.
      debugPrint('[PK] group import failed: $e');
      return null;
    }
  }

  // -- private helpers ------------------------------------------------------

  Future<Set<String>> _appliedPkSkipUuids() async {
    final rows = await PkMappingStateDao(_syncDao.attachedDatabase).getAll();
    return {
      for (final row in rows)
        if (row.decisionType == 'skip' &&
            row.status == 'applied' &&
            _hasText(row.pkMemberUuid))
          row.pkMemberUuid!.trim(),
    };
  }

  Future<void> _importMembers(
    PluralKitClient? client,
    List<PKMember> pkMembers, {
    void Function(int current, int total, String memberName)? onProgress,
    bool matchUnlinkedByName = false,
  }) async {
    final existing = await _memberRepository.getAllMembersIncludingDeleted();
    final skippedPkUuids = await _appliedPkSkipUuids();
    debugPrint('[PK_SVC] _importMembers: existing in DB=${existing.length}');
    final byPkUuid = <String, domain.Member>{};
    final byPkId = <String, domain.Member>{};
    // F5 (full-import adoption): unlinked local members this fleet tried to
    // create (create lease set), keyed by name. A matching PK member in the
    // import that isn't otherwise linked is very likely the orphaned create
    // from an interrupted push — adopt it rather than minting a local
    // duplicate. Mirrors the incremental adoption in PkBidirectionalService.
    final attemptedCreateByName = <String, List<domain.Member>>{};
    // I1 (file import only): unlinked, non-ignored locals with NO create lease,
    // keyed by exact and lower-cased name for unique-match adoption. The
    // `createPushStartedAt == null` filter keeps this pool DISJOINT from F5's
    // (attemptedCreateByName), so the name gate never steps on F5's lease skip.
    final unlinkedByExactName = <String, List<domain.Member>>{};
    final unlinkedByLowerName = <String, List<domain.Member>>{};
    for (final m in existing) {
      final pkUuid = m.pluralkitUuid?.trim();
      if (pkUuid != null && pkUuid.isNotEmpty) {
        byPkUuid[pkUuid] = m;
      }
      final pkId = m.pluralkitId?.trim();
      if (pkId != null && pkId.isNotEmpty) {
        byPkId[pkId] = m;
      }
      final unlinked = !m.isDeleted &&
          !m.pluralkitSyncIgnored &&
          (pkUuid == null || pkUuid.isEmpty) &&
          (pkId == null || pkId.isEmpty);
      if (unlinked && m.createPushStartedAt != null) {
        // (unlinked already excludes "keep local" members, so adopting can't
        // silently undo pluralkit_sync_ignored.) A LIST, not last-write-wins:
        // two same-name interrupted creates each deserve to adopt their orphan,
        // else one strands as a dup.
        final name = m.name.trim();
        if (name.isNotEmpty) {
          (attemptedCreateByName[name] ??= <domain.Member>[]).add(m);
        }
      }
      if (matchUnlinkedByName && unlinked && m.createPushStartedAt == null) {
        final name = m.name.trim();
        if (name.isNotEmpty) {
          (unlinkedByExactName[name] ??= <domain.Member>[]).add(m);
          (unlinkedByLowerName[name.toLowerCase()] ??= <domain.Member>[]).add(m);
        }
      }
    }
    final nowMsForCreateLease = DateTime.now().millisecondsSinceEpoch;

    var created = 0;
    var updated = 0;
    var skipped = 0;
    var failures = 0;
    for (var i = 0; i < pkMembers.length; i++) {
      final pk = pkMembers[i];
      // Emit progress BEFORE the per-member work (avatar fetch + repository
      // write) so the UI reads "now working on X" rather than "just finished
      // X". Cadence: every 10 members, plus the last iteration so the bar
      // ends at the band terminus. The `||` is safe — each i runs once, so
      // the last iteration emits exactly once even when n is a multiple of
      // 10 plus 1 (e.g. n=11, fires at i=0 and i=10; i=10 is also "last").
      if (i % 10 == 0 || i == pkMembers.length - 1) {
        onProgress?.call(i + 1, pkMembers.length, pk.name);
      }
      // Adopt by short id ONLY when the local row has no conflicting uuid:
      // short ids are user-changeable under Premium, so a stale
      // `pluralkit_id` can collide with a different member's short id. The
      // uuid is the stable key; on conflict let `pk` create a fresh row.
      final uuidMatch = byPkUuid[pk.uuid];
      domain.Member? localMember = uuidMatch;
      if (localMember == null) {
        final shortIdMatch = byPkId[pk.id];
        if (shortIdMatch != null) {
          final matchUuid = shortIdMatch.pluralkitUuid?.trim();
          final incomingUuid = pk.uuid.trim();
          if (matchUuid == null ||
              matchUuid.isEmpty ||
              matchUuid == incomingUuid) {
            localMember = shortIdMatch;
          } else {
            debugPrint(
              '[PK_SVC] _importMembers: short-id ${pk.id} collides with local '
              '${shortIdMatch.id} bound to a different uuid ($matchUuid vs '
              '$incomingUuid); NOT adopting by short id (2026-06 PK audit '
              'H12a) — creating fresh from incoming uuid.',
            );
            // The refused short id is provably stale; leaving it creates a
            // duplicate-short-id state where shortId-keyed paths can pick the
            // wrong row. Clear ONLY the short id (the uuid binding stays) via
            // a fresh read + targeted patch — `byPkId` is a load-time snapshot
            // and a full-object update from it would revert fields written
            // earlier this import. Non-fatal on failure.
            try {
              final fresh = await _memberRepository.getMemberById(
                shortIdMatch.id,
              );
              if (fresh != null &&
                  !fresh.isDeleted &&
                  fresh.pluralkitId?.trim() == pk.id) {
                await _memberRepository.updateMemberFields(fresh.id, {
                  'pluralkit_id': null,
                });
              }
              // Keep the in-memory index consistent with the DB so later
              // iterations of THIS import don't re-match the row by the
              // recycled short id (whether we just cleared it or an earlier
              // iteration already re-stamped the row's identity).
              byPkId.remove(pk.id);
            } catch (e) {
              debugPrint(
                '[PK_SVC] _importMembers: failed to clear stale collided '
                'short id ${pk.id} on ${shortIdMatch.id} (non-fatal): $e',
              );
            }
          }
        }
      }
      if (localMember == null && skippedPkUuids.contains(pk.uuid.trim())) {
        skipped++;
        debugPrint(
          '[PK_SVC] _importMembers: skipped ${pk.name} (${pk.uuid}) '
          'because mapping marked this PK member as skipped.',
        );
        continue;
      }
      // I1: with no PK-identity match, a UNIQUE same-name unlinked local is
      // almost certainly the same person under a non-PK row (Simply-Plural-then-
      // PK-file). Adopt it via the update path below rather than duplicating.
      // Ambiguous (>1) or no match falls through to create. Runs AFTER the
      // skipped-uuid guard so a user-excluded PK member never adopts. File-import
      // only; the token path name-matches via the mapping screen.
      if (localMember == null && matchUnlinkedByName) {
        final adopt = _uniqueUnlinkedNameMatch(
          pk.name,
          unlinkedByExactName,
          unlinkedByLowerName,
        );
        if (adopt != null) {
          _dropNameMatchCandidate(
            adopt,
            unlinkedByExactName,
            unlinkedByLowerName,
          );
          localMember = adopt;
          debugPrint(
            '[PK_SVC] _importMembers: I1 name-adopted local ${adopt.id} '
            '("${adopt.name}") for PK ${pk.name} (${pk.uuid}) — no duplicate.',
          );
        }
      }

      try {
        if (localMember?.isDeleted == true) {
          debugPrint(
            '[PK_SVC] _importMembers: skipped ${pk.name} (${pk.uuid}) '
            'because deleted local member ${localMember!.id} still owns '
            'its PluralKit identity.',
          );
          continue;
        }
        if (localMember != null && localMember.pluralkitSyncIgnored) {
          skipped++;
          continue;
        }
        final avatarCache = await _avatarCacheService.resolve(
          PkAvatarCacheInput(
            currentAvatarImageData: localMember?.avatarImageData,
            currentPkAvatarCachedUrl: localMember?.pkAvatarCachedUrl,
            incomingAvatarUrl: pk.avatarUrl,
          ),
        );
        final bannerCache = await _bannerCacheService.resolve(
          PkBannerCacheInput(
            currentPkBannerUrl: localMember?.pkBannerUrl,
            currentPkBannerImageData: localMember?.pkBannerImageData,
            currentPkBannerCachedUrl: localMember?.pkBannerCachedUrl,
            hasIncomingBannerField: pk.hasBannerField,
            incomingBannerUrl: pk.bannerUrl,
          ),
        );
        if (localMember != null) {
          final hasPkColor = pk.color != null && pk.color!.isNotEmpty;
          final updatedMember = localMember.copyWith(
            pronouns: pk.pronouns,
            bio: pk.description,
            birthday: pk.birthday,
            customColorHex: hasPkColor ? pk.color : localMember.customColorHex,
            customColorEnabled: hasPkColor
                ? true
                : localMember.customColorEnabled,
            proxyTagsJson: pk.proxyTagsJson ?? localMember.proxyTagsJson,
            pkBannerUrl: bannerCache.pkBannerUrl,
            pkBannerImageData: bannerCache.pkBannerImageData,
            pkBannerCachedUrl: bannerCache.pkBannerCachedUrl,
            profileHeaderSource:
                localMember.profileHeaderSource ==
                        domain.MemberProfileHeaderSource.prism &&
                    localMember.profileHeaderImageData == null &&
                    _hasText(bannerCache.pkBannerUrl)
                ? domain.MemberProfileHeaderSource.pluralKit
                : localMember.profileHeaderSource,
            pluralkitUuid: pk.uuid,
            pluralkitId: pk.id,
            pluralkitDisplayName: pk.displayName,
            avatarImageData: avatarCache.avatarImageData,
            pkAvatarCachedUrl: avatarCache.pkAvatarCachedUrl,
          );
          // Drop delete-bookkeeping keys before passing to the repo: the
          // `_memberPatchKeys` allowlist (used by applyPluralKitLink's
          // validator) deliberately excludes them — they're stamped only
          // by `stampDeletePushStartedAt` and the unlink flow.
          // `pluralkit_sync_ignored=false` stays in the patch; v8's
          // relaxed assert allows it (idempotent with the method's
          // force-injection).
          final patch =
              Map<String, dynamic>.from(
                DriftMemberRepository.memberFields(updatedMember),
              )..removeWhere(
                (k, _) => const {
                  'is_deleted',
                  'delete_intent_epoch',
                  'delete_push_started_at',
                  'create_push_started_at',
                }.contains(k),
              );
          await _memberRepository.applyPluralKitLink(localMember.id, patch);
          updated++;
        } else {
          // F5: a same-name lease-bearing local is likely the orphaned create
          // from an interrupted push — adopt it instead of duplicating (see the
          // attemptedCreateByName pool above).
          final attemptedList = attemptedCreateByName[pk.name.trim()];
          if (attemptedList != null && attemptedList.isNotEmpty) {
            // Prefer a STALE-lease candidate; a fresh lease means a peer is mid-
            // POST right now. Pop the adopted one so a second same-name orphan
            // adopts a different candidate rather than duplicating.
            final staleIdx = attemptedList.indexWhere((m) {
              final leaseMs = m.createPushStartedAt;
              return leaseMs == null ||
                  (nowMsForCreateLease - leaseMs) >=
                      _createPushTakeoverThreshold.inMilliseconds;
            });
            if (staleIdx < 0) {
              // Every candidate has a fresh lease (a peer is mid-POST). Consume
              // one before skipping so a SECOND distinct same-name PK member
              // still falls through to create rather than being skipped against
              // the same already-claimed local.
              attemptedList.removeAt(0);
              skipped++;
              continue;
            }
            final attempted = attemptedList.removeAt(staleIdx);
            await _memberRepository.applyPluralKitLink(attempted.id, {
              'pluralkit_uuid': pk.uuid,
              'pluralkit_id': pk.id,
            });
            await _memberRepository.clearCreatePushStartedAt(attempted.id);
            updated++;
            continue;
          }
          await _memberRepository.createMember(
            domain.Member(
              id: _uuid.v4(),
              name: pk.name,
              pronouns: pk.pronouns,
              bio: pk.description,
              birthday: pk.birthday,
              emoji: '❔',
              isActive: true,
              createdAt: pk.created ?? DateTime.now(),
              customColorHex: pk.color,
              customColorEnabled: pk.color != null && pk.color!.isNotEmpty,
              proxyTagsJson: pk.proxyTagsJson,
              pkBannerUrl: bannerCache.pkBannerUrl,
              profileHeaderSource: _hasText(bannerCache.pkBannerUrl)
                  ? domain.MemberProfileHeaderSource.pluralKit
                  : domain.MemberProfileHeaderSource.prism,
              pkBannerImageData: bannerCache.pkBannerImageData,
              pkBannerCachedUrl: bannerCache.pkBannerCachedUrl,
              pluralkitUuid: pk.uuid,
              pluralkitId: pk.id,
              pluralkitDisplayName: pk.displayName,
              avatarImageData: avatarCache.avatarImageData,
              pkAvatarCachedUrl: avatarCache.pkAvatarCachedUrl,
            ),
          );
          created++;
        }
      } catch (e, st) {
        failures++;
        debugPrint(
          '[PK_SVC] _importMembers: write FAILED for ${pk.name} (${pk.uuid}): '
          '$e\n$st',
        );
      }
    }
    debugPrint(
      '[PK_SVC] _importMembers: done — created=$created updated=$updated '
      'skipped=$skipped failures=$failures (input=${pkMembers.length})',
    );
  }

  /// I1: the single unlinked local uniquely matching [pkName] (unique exact
  /// name, else unique case-insensitive), or null. An ambiguous (>1 same-name)
  /// match returns null so the caller creates fresh rather than guessing — the
  /// F13 "needs a user decision" stance, applied silently (no UI on the file path).
  static domain.Member? _uniqueUnlinkedNameMatch(
    String pkName,
    Map<String, List<domain.Member>> byExactName,
    Map<String, List<domain.Member>> byLowerName,
  ) {
    final name = pkName.trim();
    if (name.isEmpty) return null;
    final exact = byExactName[name];
    if (exact != null && exact.length == 1) return exact.first;
    if (exact != null && exact.length > 1) return null;
    final lower = byLowerName[name.toLowerCase()];
    if (lower != null && lower.length == 1) return lower.first;
    return null;
  }

  /// Remove an adopted candidate from both name pools so a later same-name PK
  /// member can't adopt the (now-linked) same local twice.
  static void _dropNameMatchCandidate(
    domain.Member m,
    Map<String, List<domain.Member>> byExactName,
    Map<String, List<domain.Member>> byLowerName,
  ) {
    final name = m.name.trim();
    byExactName[name]?.remove(m);
    byLowerName[name.toLowerCase()]?.remove(m);
  }

  // -- Phase 4B: diff sweep -------------------------------------------------

  /// Build a map from PK short ID (5-char) → PK full UUID for all locally
  /// stored members. Used by [_runDiffSweep] to resolve switch member lists.
  ///
  /// The canonical key for deterministic ID derivation is the full PK UUID
  /// (pluralkitUuid on the member row), not the short 5-char ID. PK switch
  /// payloads list short IDs; we resolve through this map.
  Future<Map<String, String>> _buildShortIdToUuidMap() async {
    final members = await _memberRepository.getAllMembers();
    final map = <String, String>{};
    for (final m in members) {
      if (m.pluralkitSyncIgnored) continue;
      final pkId = m.pluralkitId?.trim();
      final pkUuid = m.pluralkitUuid?.trim();
      if (pkId != null &&
          pkId.isNotEmpty &&
          pkUuid != null &&
          pkUuid.isNotEmpty) {
        map[pkId] = pkUuid;
      }
    }
    return map;
  }

  /// Build a map from PK full UUID → local Prism member ID.
  Future<Map<String, String>> _buildUuidToLocalIdMap() async {
    final members = await _memberRepository.getAllMembers();
    final map = <String, String>{};
    for (final m in members) {
      if (m.pluralkitSyncIgnored) continue;
      final pkUuid = m.pluralkitUuid?.trim();
      if (pkUuid != null && pkUuid.isNotEmpty) {
        map[pkUuid] = m.id;
      }
    }
    return map;
  }

  /// Paginate PK switch history newest-first, de-duped and tie-safe across page
  /// boundaries (F7), with no-progress + page-cap guards (F10).
  ///
  /// PK's `before` is strictly exclusive, so paging by a page's oldest timestamp
  /// would silently DROP same-timestamp switches beyond the 100-item page cap.
  /// We page by `oldest + 1µs` (inclusive) and de-dup by switch id so ties are
  /// never skipped. [onPage] gets each page's NEW switches newest-first and
  /// returns false to stop early. When a re-served page is all-seen we step
  /// strictly below that timestamp to advance (≥100 switches at the exact same
  /// microsecond are unpageable — that overflow alone is lost); a server that
  /// ignores `before` (still all-seen after the step) throws
  /// [PkPaginationNoProgressError]. Returns page/raw-fetched counts.
  Future<({int pages, int fetched})> _paginateSwitchesNewestFirst(
    PluralKitClient client, {
    required bool Function(List<PKSwitch> freshNewestFirst) onPage,
  }) async {
    final seenIds = <String>{};
    DateTime? pageBefore;
    var pageNum = 0;
    var rawFetched = 0;
    // Set once we've stepped the cursor STRICTLY below a timestamp to get past
    // it. If the very next full page is still entirely already-seen, the server
    // isn't honoring `before` — bail rather than spin to the page cap.
    var steppedPastTimestamp = false;
    while (true) {
      final page = await client.getSwitches(before: pageBefore, limit: 100);
      pageNum++;
      if (page.isEmpty) return (pages: pageNum, fetched: rawFetched);
      rawFetched += page.length;
      final fresh = <PKSwitch>[];
      for (final sw in page) {
        if (seenIds.add(sw.id)) fresh.add(sw);
      }
      if (fresh.isEmpty) {
        // A SHORT page of already-seen switches means history is exhausted.
        if (page.length < 100) return (pages: pageNum, fetched: rawFetched);
        // A FULL page of already-seen switches: the inclusive boundary re-served
        // a fully-captured timestamp's ties. Step the cursor strictly below it to
        // advance to older history. If we ALREADY stepped and the next full page
        // is still all-seen, the server is ignoring `before` — surface it.
        if (steppedPastTimestamp) {
          throw PkPaginationNoProgressError(
            lastBefore: page.last.timestamp,
            pagesFetched: pageNum,
          );
        }
        if (pageNum >= _maxIncrementalPages) {
          throw PkImportTooLargeError(
            pagesFetched: pageNum,
            cap: _maxIncrementalPages,
          );
        }
        steppedPastTimestamp = true;
        pageBefore = page.last.timestamp; // strictly exclusive: advance past it
        continue;
      }
      steppedPastTimestamp = false;
      if (!onPage(fresh)) return (pages: pageNum, fetched: rawFetched);
      if (page.length < 100) return (pages: pageNum, fetched: rawFetched);
      if (pageNum >= _maxIncrementalPages) {
        throw PkImportTooLargeError(
          pagesFetched: pageNum,
          cap: _maxIncrementalPages,
        );
      }
      // Inclusive boundary (oldest + 1µs) re-serves the boundary timestamp's
      // ties next page; seenIds dedups the overlap. PK switch timestamps carry
      // microsecond precision (the real client sends `before` as microsecond
      // ISO8601 and PK returns/compares the same precision).
      pageBefore = page.last.timestamp.add(const Duration(microseconds: 1));
    }
  }

  /// Paginate the full PK switch history and return all switches sorted
  /// oldest-first. Used by [performFullImport].
  Future<List<PKSwitch>> _fetchAllSwitches(PluralKitClient client) async {
    final allSwitches = <PKSwitch>[];
    await _paginateSwitchesNewestFirst(
      client,
      onPage: (fresh) {
        allSwitches.addAll(fresh);
        return true;
      },
    );
    // PK returns newest-first; sort oldest-first for the diff sweep.
    allSwitches.sort(_compareSwitchesChronologically);
    return allSwitches;
  }

  /// Persist a changed `@me` system short id onto the sync DAO row. PK
  /// Premium makes short ids user-changeable, and a rename would otherwise
  /// false-positive every ownership check against the stored `systemId`
  /// forever. Same token ⇒ same system, so no uuid comparison is needed.
  /// Refreshes only when a stored id already EXISTS: callers must pass a
  /// system fetched via the CONNECTED token, never a repair/one-shot token.
  Future<void> _refreshStoredSystemIdIfChanged(PKSystem system) async {
    final fresh = system.id.trim();
    if (fresh.isEmpty) return;
    final stored = (await _syncDao.getSyncState()).systemId?.trim();
    if (stored == null || stored.isEmpty || stored == fresh) return;
    await _syncDao.upsertSyncState(
      PluralKitSyncStateCompanion(
        id: const Value('pk_config'),
        systemId: Value(fresh),
      ),
    );
    debugPrint(
      '[PK_SVC] stored PK system short id refreshed: $stored → $fresh '
      '(Premium rename; same token-bound system).',
    );
  }

  Future<PkTokenImportResult> _runFullImportWithClient(
    PluralKitClient client, {
    required bool updateSyncState,
    bool refreshStoredSystemId = false,
  }) async {
    // -- Members (0-10%) --
    final system = await client.getSystem();
    // Premium systemId refresh — only when this run uses the CONNECTED
    // token (`_performFullImport` passes `!useRepairToken`); a repair-token
    // one-shot may legitimately target a different system and must not
    // overwrite the connected row's identity.
    if (refreshStoredSystemId) {
      await _refreshStoredSystemIdIfChanged(system);
    }
    _emit(
      _state.copyWith(syncProgress: 0.02, syncStatus: 'Fetching members...'),
    );

    final pkMembers = await client.getMembers();
    _emit(
      _state.copyWith(
        syncProgress: 0.05,
        syncStatus: 'Importing ${pkMembers.length} members...',
      ),
    );
    await _importMembers(
      client,
      pkMembers,
      onProgress: (current, total, name) {
        // Member import phase occupies 0.05 → 0.10 of the overall progress
        // bar for full imports. current=1 (i=0) maps to 0.05; current=total
        // (i=last) maps to 0.10.
        final fraction = total <= 1 ? 1.0 : (current - 1) / (total - 1);
        _emit(
          _state.copyWith(
            syncProgress: 0.05 + 0.05 * fraction,
            syncStatus: 'Importing member $current/$total: $name',
          ),
        );
      },
    );
    _emit(_state.copyWith(syncProgress: 0.10));

    // -- Groups (10-15%) --
    _emit(
      _state.copyWith(syncProgress: 0.10, syncStatus: 'Importing groups...'),
    );
    // Full import is a one-shot pull-everything flow; never push from here.
    await _importGroups(
      client,
      overwriteMetadata: true,
      direction: PkSyncDirection.pullOnly,
    );
    _emit(_state.copyWith(syncProgress: 0.15));

    // -- Build member resolution maps (precomputed once for both the
    // canonicalization pass and the diff sweep).
    final shortIdToUuid = await _buildShortIdToUuidMap();
    if (shortIdToUuid.isEmpty && pkMembers.isNotEmpty) {
      throw StateError(
        'No PluralKit members resolved to local members. '
        'Ensure members are imported before importing fronting history.',
      );
    }
    final uuidToLocalId = await _buildUuidToLocalIdMap();
    final pkUuidByLocalId = <String, String>{
      for (final entry in uuidToLocalId.entries) entry.value: entry.key,
    };

    // -- Reset the sweep cursor so we fetch from the beginning of history.
    if (updateSyncState) {
      await _syncDao.upsertSyncState(
        const PluralKitSyncStateCompanion(
          id: Value('pk_config'),
          switchCursorTimestamp: Value(null),
          switchCursorId: Value(null),
        ),
      );
    }

    // -- Switches (15-95%): fetch all pages first so we know the canonical
    // PK row set the API agrees on.
    _emit(
      _state.copyWith(syncProgress: 0.15, syncStatus: 'Fetching switches...'),
    );

    final allSwitches = await _fetchAllSwitches(client);
    final totalSwitches = allSwitches.length;

    // -- Canonicalize: tombstone PK-linked rescue rows the API
    // wouldn't create. The PRISM1 rescue importer fans out every
    // legacy PK switch/member row (one row per (switch, member) pair
    // in the file), but the diff sweep only writes ENTRANT rows
    // (one per "this member became active at this switch"). For a
    // history A -> A+B -> A the rescue creates 4 rows but the diff
    // sweep would only create 2: A entering at sw-1 stays open
    // across A+B and back to A; B enters at sw-2 and leaves at sw-3.
    // The 2 stale A rows at det(sw-2, A) and det(sw-3, A) are
    // rescue artifacts the diff sweep never touches.
    //
    // On the corrective re-import the API is authoritative for API-backed
    // switch rows: any API-linked local row whose id isn't an entrant
    // (sw, member) pair is a stale rescue artifact and must be tombstoned
    // so paired devices converge. Synthetic/file-origin IDs are not API
    // switch refs and must not be canonicalized here.
    //
    // DOMAIN RESTRICTION: canonicalization is restricted to members inside the
    // canonical computation domain — those whose switches were enumerable
    // while `canonicalIds` was built below. A row is judged a stale artifact
    // ONLY when its member is in that domain; rows for members outside it
    // (`pluralkitSyncIgnored`, link-auto-cleared, or legacy `memberId == null`)
    // are preserved untouched — their absence from `canonicalIds` reflects an
    // unresolved mapping, not staleness, and tombstoning them would destroy
    // valid history on every peer (absorbing deletes).
    //
    // The entire detect+tombstone loop runs in one Drift transaction so a
    // mid-loop crash can't leave the CRDT half-canonicalized (some stale rows
    // tombstoned, others live), which would converge paired devices on an
    // inconsistent timeline.
    _emit(
      _state.copyWith(
        syncProgress: 0.40,
        syncStatus: 'Canonicalizing PK history...',
      ),
    );
    // Resolve canonical entrant ids in (switchId, localMemberId) space —
    // exactly what the diff sweep writes — via the shared
    // [deriveCanonicalPkSessionId] helper. Routing both call sites through
    // one helper guarantees the canonicalization pass and the live diff
    // sweep agree byte-for-byte on the row id, so we can never tombstone
    // a row the sweep just wrote. Reuses the precomputed `uuidToLocalId` /
    // `pkUuidByLocalId` from the top of this method — no second scan.
    // We track BOTH canonical deterministic ids and canonical
    // (switchUuid, localMemberId) PAIRS: a locally-pushed front lives under
    // a random v4 row id (never re-keyed), so only the pair set tells it
    // apart from a true rescue artifact — pair-matching rows are left for
    // the sweep's `_findSessionByPkSwitchAndMember` fallback to adopt.
    final canonicalIds = <String>{};
    final canonicalPairs = <String>{};
    final canonPrev = <String>{};
    for (final sw in allSwitches) {
      final newActive = <String>{};
      for (final shortId in sw.members) {
        final pkUuid = shortIdToUuid[shortId];
        if (pkUuid == null) continue;
        final localId = uuidToLocalId[pkUuid];
        if (localId == null) continue;
        newActive.add(localId);
      }
      for (final entrantLocalId in newActive.difference(canonPrev)) {
        canonicalIds.add(
          deriveCanonicalPkSessionId(
            switchId: sw.id,
            localMemberId: entrantLocalId,
            pkUuidByLocalId: pkUuidByLocalId,
          ),
        );
        canonicalPairs.add(_canonicalPairKey(sw.id, entrantLocalId));
      }
      canonPrev
        ..clear()
        ..addAll(newActive);
    }
    // The canonical computation domain: members whose switches were ENUMERABLE
    // while `canonicalIds` was built above. Absence from `canonicalIds` counts
    // as staleness ONLY for members in this domain — for anyone outside it the
    // loop could never reach their rows (member never resolved), so absence
    // proves nothing and tombstoning would destroy valid history on every peer
    // via absorbing CRDT deletes (and queue their shared switches for PK-side
    // deletion). Rows outside the domain — `pluralkitSyncIgnored`,
    // link-auto-cleared, or legacy `memberId == null` — are left alone and
    // counted into `unresolvableMemberRowsPreserved`.
    //
    // Built from the COMPOSED mapping (shortIdToUuid ∘ uuidToLocalId), exactly
    // the resolution chain the canonical loop uses. Using `uuidToLocalId.values`
    // alone would over-include a member with a uuid but no short id as "in
    // domain" even though the loop can never reach them, tombstoning their rows.
    final canonicalDomain = <String>{
      for (final pkUuid in shortIdToUuid.values)
        if (uuidToLocalId.containsKey(pkUuid)) uuidToLocalId[pkUuid]!,
    };
    var tombstonedStale = 0;
    var adoptedCanonicalPair = 0;
    var unresolvableMemberRowsPreserved = 0;
    // Capture CRDT emissions inside the canonicalization transaction and
    // replay them only AFTER it durably commits. Each
    // `_tombstoneImporterArtifact` emits a `pluralkit_uuid=null` update then a
    // delete; emitting those mid-transaction would leak absorbing tombstones
    // to peers if it rolled back (the engine commits to its own store, which a
    // Drift rollback can't undo).
    await _captureImportEmissions<void>(() async {
      await _syncDao.attachedDatabase.transaction(() async {
        final allSessions = await _frontingSessionRepository.getAllSessions();
        for (final s in allSessions) {
          if (!isPluralKitSwitchUuid(s.pluralkitUuid) || s.isDeleted) continue;
          // Already canonical by id — the sweep will adopt it; nothing to do.
          if (canonicalIds.contains(s.id)) continue;

          final memberId = s.memberId;
          // The row's member must be INSIDE the canonical computation domain
          // for absence-from-`canonicalIds` to count as staleness. A null
          // `memberId` or a member outside the domain (sync-ignored /
          // link-auto-cleared) was never enumerable, so the row is preserved
          // and counted — never destroyed here.
          if (memberId == null || !canonicalDomain.contains(memberId)) {
            unresolvableMemberRowsPreserved++;
            continue;
          }

          // The row's (switch, member) pair IS canonical even though its id is
          // non-canonical (a locally-pushed front under a random v4 id, or a
          // legacy row id). Leave it live — the sweep's
          // `_findSessionByPkSwitchAndMember` fallback adopts it in place.
          if (canonicalPairs.contains(
            _canonicalPairKey(s.pluralkitUuid!, memberId),
          )) {
            adoptedCanonicalPair++;
            continue;
          }

          // Survivor: resolvable member, pair NOT canonical (a genuine rescue
          // fan-out artifact, or a switch the API no longer reports). Tombstone
          // via the importer-artifact helper, which clears the PK link FIRST so
          // `_pushPendingSwitchDeletions` doesn't mistake importer cleanup for a
          // user-requested PluralKit deletion. Skipping the link-clear is
          // exactly what queued real `DELETE /switches/{uuid}` calls.
          await _tombstoneImporterArtifact(s.id);
          tombstonedStale++;
        }
      });
    });
    if (tombstonedStale > 0 ||
        adoptedCanonicalPair > 0 ||
        unresolvableMemberRowsPreserved > 0) {
      debugPrint(
        '[PK_FULL_IMPORT] canonicalization: tombstoned $tombstonedStale '
        'rescue/orphan rows (link cleared, no delete intent), left '
        '$adoptedCanonicalPair rows with canonical (switch,member) pairs '
        'for in-place adoption, preserved $unresolvableMemberRowsPreserved '
        'rows for members outside the canonical domain '
        '(F22; 2026-06 PK audit C1/H4).',
      );
    }

    _emit(
      _state.copyWith(
        syncProgress: 0.50,
        syncStatus: 'Processing $totalSwitches switches...',
      ),
    );

    // Diff sweep in corrective mode. Active state is reconstituted from open
    // PK-linked DB rows inside [_runDiffSweep]; starting blind would leave
    // existing-but-no-longer-fronting rows uncloseable. Tombstones are
    // preserved (is_deleted absorbing) and surfaced via
    // `tombstonePreservedCount`. Reuses the precomputed member maps.
    final sweepResult = await _runDiffSweep(
      switches: allSwitches,
      shortIdToUuid: shortIdToUuid,
      uuidToLocalIdOverride: uuidToLocalId,
      pkUuidByLocalIdOverride: pkUuidByLocalId,
      corrective: true,
      advanceCursor: updateSyncState,
      onProgress: (i) {
        if (i % 50 == 0 || i == allSwitches.length - 1) {
          final progress =
              0.50 + 0.45 * (totalSwitches == 0 ? 1.0 : i / totalSwitches);
          _emit(
            _state.copyWith(
              syncProgress: progress,
              syncStatus: 'Processing switch ${i + 1}/$totalSwitches...',
            ),
          );
        }
      },
    );

    DateTime? complete;
    if (updateSyncState) {
      // -- Complete (95-100%) --
      complete = DateTime.now();
      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastSyncDate: Value(complete),
        ),
      );
    }

    return PkTokenImportResult(
      system: system,
      members: pkMembers,
      switchesImported: totalSwitches,
      unmappedMemberReferences: sweepResult.unmappedCount,
      tombstonePreservedCount: sweepResult.tombstonePreservedCount,
      zeroLengthCloseSkipped: sweepResult.zeroLengthCloseSkipped,
      unresolvableMemberRowsPreserved: unresolvableMemberRowsPreserved,
      completedAt: complete,
    );
  }

  /// Fetch enough API switch pages to cover the export's timestamp range,
  /// plus any newer API switches that indicate the file is stale.
  Future<List<PKSwitch>> _fetchSwitchesForFileRange(
    PluralKitClient client,
    List<PkFileSwitch> fileSwitches,
  ) async {
    if (fileSwitches.isEmpty) return const <PKSwitch>[];

    final minFileTimestampMicros = fileSwitches
        .map((entry) => entry.timestamp.toUtc().microsecondsSinceEpoch)
        .reduce((left, right) => left < right ? left : right);

    final switches = <PKSwitch>[];
    await _paginateSwitchesNewestFirst(
      client,
      onPage: (fresh) {
        var reachedBeforeFileRange = false;
        for (final switchEntry in fresh) {
          final timestampMicros =
              switchEntry.timestamp.toUtc().microsecondsSinceEpoch;
          if (timestampMicros >= minFileTimestampMicros) {
            switches.add(switchEntry);
          } else {
            reachedBeforeFileRange = true;
          }
        }
        // Stop once a page reaches below the file range — older switches are
        // outside it.
        return !reachedBeforeFileRange;
      },
    );

    switches.sort(_compareSwitchesChronologically);
    return switches;
  }

  int _compareSwitchesChronologically(PKSwitch a, PKSwitch b) {
    final timestampComparison = a.timestamp.compareTo(b.timestamp);
    if (timestampComparison != 0) return timestampComparison;
    return a.id.compareTo(b.id);
  }

  String _pkFileSwitchSourceId(PkFileSwitch switchEntry) {
    final explicitId = switchEntry.id?.trim();
    if (explicitId != null && explicitId.isNotEmpty) return explicitId;

    final timestamp = DateTime.fromMicrosecondsSinceEpoch(
      switchEntry.timestamp.toUtc().microsecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
    final memberIds = switchEntry.memberIds.toSet().toList()..sort();
    return 'pkfile:v1:$timestamp|${memberIds.join(',')}';
  }

  /// Core diff-sweep: walks [switches] chronologically, opening a per-member
  /// row on entrants (id derived from entry-switch + member UUID) and closing
  /// it at the switch timestamp on leavers.
  ///
  /// Invariants:
  /// - Each switch's writes commit in one Drift transaction. The resume cursor
  ///   advances ONCE after the batch loop succeeds, not per switch — a
  ///   partial-batch crash re-processes safely because row ids are
  ///   deterministic and the upsert is idempotent.
  /// - `active` is seeded only from open PK-linked DB rows whose start is at or
  ///   before the first switch timestamp, so incremental resume can close a
  ///   member who was already fronting without a corrective replay closing a
  ///   current row against a switch that predates it.
  /// - Tombstones are absorbing: a deleted row is never revived in place. A
  ///   corrective re-import re-materializes the member under a FRESH det id
  ///   from the next switch (the burned tombstone is untouched).
  ///
  /// Counters in [_PkDiffSweepResult]: `unmappedCount` (member refs with no
  /// local match, plus leavers on a tombstoned-collision presence with no row
  /// to close); `tombstonePreservedCount` (corrective re-imports that left a
  /// row tombstoned, surfaced in the import UI); `zeroLengthCloseSkipped`
  /// (leaver timestamp == row start, discarded to avoid a phantom open
  /// fronter). Throws [PkSwitchOrderingError] if a leaver predates its row.
  ///
  /// [corrective] selects entrant-collision end_time policy: incremental
  /// preserves a pre-existing non-null end_time (may be a deliberate user
  /// close on a rescue row); corrective clears it to null because the API is
  /// authoritative on an explicit rebuild.
  Future<_PkDiffSweepResult> _runDiffSweep({
    required List<PKSwitch> switches,
    required Map<String, String> shortIdToUuid,
    void Function(int index)? onProgress,
    bool corrective = false,
    bool advanceCursor = true,
    String? pkImportSource,
    Map<String, String> pkImportSourceByApiSwitchId = const <String, String>{},
    Map<String, String> pkFileSwitchIdsByApiSwitchId = const <String, String>{},
    Map<String, String>? uuidToLocalIdOverride,
    Map<String, String>? pkUuidByLocalIdOverride,
  }) async {
    // Reuse caller-provided maps so the corrective full-import path doesn't
    // pay for a second member-table scan.
    final uuidToLocalId =
        uuidToLocalIdOverride ?? await _buildUuidToLocalIdMap();
    // Forward map (local id → PK UUID), built once: rebuilding mid-sweep would
    // break the determinism contract asserted below.
    final pkUuidByLocalId =
        pkUuidByLocalIdOverride ??
        <String, String>{
          for (final entry in uuidToLocalId.entries) entry.value: entry.key,
        };

    // Active PK presence by local member ID. Its keys ARE the running
    // prev-active set; entrants/leavers are recomputed off `active.keys` each
    // switch.
    final active = <String, _PkActivePresence>{};
    // Seed bound compares against PERSISTED (whole-second) row startTimes, so
    // truncate it to match. API-facing values keep µs.
    final firstSwitchTimestamp = switches.isEmpty
        ? null
        : truncatePkTimestampToDriftPrecision(switches.first.timestamp);

    // Open PK-linked rows the seed bound EXCLUDES (started after the first
    // switch), keyed by (switch uuid, member id). Live-poll artifacts: a
    // no-advance poll opens det(S3, B), then a sweep over [S2, S3] opens
    // det(S2, B) too — a phantom fronter the loop merges when it reaches S3.
    final seedExcludedOpenRowsByPair = <String, domain.FrontingSession>{};

    // Seed `active` from open DB rows unconditionally (corrective full import
    // included), so an existing-but-no-longer-fronting member is closed by the
    // sweep rather than treated as a fresh entrant.
    final currentSessions = await _frontingSessionRepository.getAllSessions();
    for (final s in currentSessions) {
      if (s.endTime == null &&
          isPluralKitSwitchUuid(s.pluralkitUuid) &&
          !s.isDeleted &&
          s.memberId != null) {
        if (firstSwitchTimestamp != null &&
            s.startTime.isAfter(firstSwitchTimestamp)) {
          // Remember the excluded open row so the loop can merge it if it
          // turns out to duplicate a continuing presence at its own switch.
          seedExcludedOpenRowsByPair[_canonicalPairKey(
            s.pluralkitUuid!.trim(),
            s.memberId!,
          )] = s;
          continue;
        }
        final localId = s.memberId!;
        active[localId] = _PkActivePresence(
          localMemberId: localId,
          // Reverse-map at rebuild time. May be null if the member's PK
          // mapping was dropped between writes — that's fine; only the
          // re-derive paths care, and they tolerate a null pkMemberUuid.
          pkMemberUuid: pkUuidByLocalId[localId],
          startedAt: s.startTime,
          rowId: s.id,
        );
      }
      // Rows with `memberId == null` can't key into `active`: the
      // pluralkit_uuid column is the *switch* id, not the member uuid, so the
      // local member id is unrecoverable from the row alone. If the mapping is
      // later restored the member reappears as an entrant on the next switch.
    }

    int unmappedCount = 0;
    int tombstonePreservedCount = 0;
    int zeroLengthCloseSkipped = 0;

    // Newest processed switch, tracked in memory; the resume cursor advances
    // once after the loop succeeds (deterministic ids make replay safe).
    DateTime? batchNewestTs;
    String? batchNewestId;

    for (var i = 0; i < switches.length; i++) {
      final sw = switches[i];
      onProgress?.call(i);

      // Every row-facing use of this timestamp goes through the truncated
      // value so in-memory state matches a DB-reconstituted pass. The RAW
      // `sw.timestamp` is kept for the batch cursor (round-trips to the API's
      // `before` param and must keep µs).
      final swRowTime = truncatePkTimestampToDriftPrecision(sw.timestamp);

      // Resolve this switch's member list to local member IDs.
      // Also track which short IDs couldn't be resolved for reporting.
      final newActive = <String>{};
      int switchUnmapped = 0;
      for (final shortId in sw.members) {
        final pkUuid = shortIdToUuid[shortId];
        if (pkUuid == null) {
          switchUnmapped++;
          continue;
        }
        final localId = uuidToLocalId[pkUuid];
        if (localId == null) {
          switchUnmapped++;
          continue;
        }
        newActive.add(localId);
      }
      unmappedCount += switchUnmapped;

      final prevActiveKeys = active.keys.toSet();
      final entrants = newActive.difference(prevActiveKeys);
      final leavers = prevActiveKeys.difference(newActive);

      // Atomic transaction: opens + closes for this switch. Capture-replay
      // discipline: entrant/leaver/zero-length writes emit CRDT ops, so we
      // hold them until commit — emitting inside the transaction would leak
      // ops (notably absorbing delete tombstones) to peers if it rolled back
      // (e.g. a mid-close PkSwitchOrderingError).
      await _captureImportEmissions<void>(() async {
        await _syncDao.attachedDatabase.transaction(() async {
          // Open rows for entrants. We branch on existing-row presence
          // (rather than catching a unique-constraint violation) because the
          // existing row may be a PRISM1 rescue import with lossy boundaries;
          // we MUST overwrite start_time/member_id/pluralkit_uuid with the API
          // truth so field-LWW carries the corrected boundary to paired
          // devices.
          for (final localId in entrants) {
            // Shared helper so this site and the canonicalization pass agree
            // on the id.
            final rowId = deriveCanonicalPkSessionId(
              switchId: sw.id,
              localMemberId: localId,
              pkUuidByLocalId: pkUuidByLocalId,
            );
            // Re-derivation against the same map must be idempotent.
            assert(
              deriveCanonicalPkSessionId(
                    switchId: sw.id,
                    localMemberId: localId,
                    pkUuidByLocalId: pkUuidByLocalId,
                  ) ==
                  rowId,
              'deriveCanonicalPkSessionId is non-deterministic for '
              '(${sw.id}, $localId) — id derivation contract broken.',
            );
            final switchImportSource =
                pkImportSourceByApiSwitchId[sw.id] ?? pkImportSource;
            final pkFileSwitchId = pkFileSwitchIdsByApiSwitchId[sw.id];
            final outcome = await _upsertEntrantSession(
              rowId: rowId,
              switchEntry: sw,
              localId: localId,
              corrective: corrective,
              switchImportSource: switchImportSource,
              pkFileSwitchId: pkFileSwitchId,
            );
            switch (outcome.kind) {
              case _PkUpsertOutcomeKind.row:
                active[localId] = _PkActivePresence(
                  localMemberId: localId,
                  pkMemberUuid: pkUuidByLocalId[localId],
                  startedAt: swRowTime,
                  rowId: outcome.rowId,
                );
              case _PkUpsertOutcomeKind.tombstoneCollision:
                // Incremental sync: entrant id pointed at a soft-deleted row.
                // We did NOT resurrect it (a user delete must stick). Record
                // the presence with no rowId so a future leaver has a peg to
                // match and the prev-active set stays accurate; the leaver
                // path skips the no-op close.
                active[localId] = _PkActivePresence(
                  localMemberId: localId,
                  pkMemberUuid: pkUuidByLocalId[localId],
                  startedAt: swRowTime, // M6 — see the `row` case above.
                  isTombstonedCollision: true,
                );
              case _PkUpsertOutcomeKind.tombstonePreserved:
                // is_deleted is absorbing: a tombstone is terminal regardless
                // of how it reached this device, since in-place revival can't
                // propagate. Count it for the UI and do NOT add to `active` so
                // the next leaver is a no-op.
                tombstonePreservedCount++;
            }
          }

          // Close rows for leavers.
          for (final localId in leavers) {
            final presence = active[localId];
            final rowId = presence?.rowId;
            if (rowId != null) {
              // Guard the close on the row's start before endSession:
              // end > start closes normally; end == start is a zero-length
              // presence (discard the row so it can't become a phantom open
              // fronter); end < start is corrupt input (bail with a typed
              // error rather than writing a negative-duration row). All
              // comparisons use the truncated time so the decision matches a
              // DB-seeded pass.
              if (swRowTime.isBefore(presence!.startedAt)) {
                throw PkSwitchOrderingError(
                  rowId: rowId,
                  startTime: presence.startedAt,
                  endTime: swRowTime,
                  switchId: sw.id,
                );
              }
              if (swRowTime.isAtSameMomentAs(presence.startedAt)) {
                zeroLengthCloseSkipped++;
                // Clear-link-before-delete so the cleanup tombstone is
                // captured/replayed and never queues a real PK delete push.
                await _tombstoneImporterArtifact(rowId);
                debugPrint(
                  '[PK_SWEEP] zero-length presence discarded on row $rowId '
                  '(start == end == ${swRowTime.toIso8601String()}); '
                  'cleared PK link before tombstoning to avoid delete push.',
                );
              } else {
                await _frontingSessionRepository.endSession(rowId, swRowTime);
              }
            } else if (presence != null && presence.isTombstonedCollision) {
              // Entrant time skipped the row (tombstoned collision), so the
              // leaver has nothing to close. Surface the member so the UI
              // flags the gap rather than silently dropping it.
              unmappedCount++;
              debugPrint(
                '[PK_SWEEP] leaver on tombstoned-collision presence for '
                'member $localId at ${sw.timestamp.toIso8601String()}: no '
                'row to close (review #33).',
              );
            }
            // Drop the presence either way: the member is no longer active.
            active.remove(localId);
          }

          // Merge live-poll duplicates for CONTINUING members: a seed-excluded
          // open row keyed (this switch, member) is a poll artifact when the
          // member neither enters nor leaves here — tombstone it via
          // clear-link-before-delete (never a PK delete push). A re-entering
          // member's duplicate is instead adopted by the entrant path.
          for (final localId in newActive.intersection(prevActiveKeys)) {
            final pairKey = _canonicalPairKey(sw.id, localId);
            final duplicate = seedExcludedOpenRowsByPair[pairKey];
            if (duplicate == null) continue;
            final presence = active[localId];
            if (presence == null || duplicate.id == presence.rowId) continue;
            await _tombstoneImporterArtifact(duplicate.id);
            seedExcludedOpenRowsByPair.remove(pairKey);
            debugPrint(
              '[PK_SWEEP] merged live-poll duplicate ${duplicate.id} for '
              'member $localId at switch ${sw.id}: presence already tracked '
              'by ${presence.rowId ?? '<tombstoned collision>'} from an '
              'earlier covered switch (2026-06 PK audit M2).',
            );
          }
        });
      });

      // Newest (timestamp, id) for the batch-end cursor. Compared
      // lexicographically in case a caller hands us an unsorted list.
      if (batchNewestTs == null ||
          sw.timestamp.isAfter(batchNewestTs) ||
          (sw.timestamp == batchNewestTs &&
              (batchNewestId == null || sw.id.compareTo(batchNewestId) > 0))) {
        batchNewestTs = sw.timestamp;
        batchNewestId = sw.id;
      }

    }

    if (advanceCursor && batchNewestTs != null && batchNewestId != null) {
      // One cursor write per batch, monotonic (F19): a file+token import over an
      // OLD export hands this an older batch-newest than the established cursor,
      // so route through advanceImportCursorIfNewer — an unconditional upsert
      // would regress the cursor into redundant re-fetches next sweep.
      await _syncDao.advanceImportCursorIfNewer(
        switchId: batchNewestId,
        timestamp: batchNewestTs,
      );
    }

    debugPrint(
      '[PK_SWEEP] done: ${switches.length} switches processed, '
      '$unmappedCount unmapped, '
      '$tombstonePreservedCount tombstones preserved, '
      '$zeroLengthCloseSkipped zero-length closes skipped',
    );
    return _PkDiffSweepResult(
      unmappedCount: unmappedCount,
      tombstonePreservedCount: tombstonePreservedCount,
      zeroLengthCloseSkipped: zeroLengthCloseSkipped,
    );
  }

  /// Outcome of upserting (or honouring) a per-member entrant row for one
  /// switch-entrant event. Three end states the entrant path distinguishes:
  /// 1. row written: [_PkUpsertOutcome.row]
  /// 2. tombstoned-row collision (incremental): [_PkUpsertOutcome.tombstoneCollision]
  /// 3. user tombstone preserved (corrective): [_PkUpsertOutcome.tombstonePreserved]
  Future<_PkUpsertOutcome> _upsertEntrantSession({
    required String rowId,
    required PKSwitch switchEntry,
    required String localId,
    required bool corrective,
    required String? switchImportSource,
    required String? pkFileSwitchId,
  }) async {
    // Persist the switch timestamp at drift's
    // whole-second precision. Writing the raw µs value here was the op-churn
    // engine: drift truncates on store, so the next reprocess compared the
    // in-memory µs timestamp against the truncated read-back, saw "changed",
    // and emitted a CRDT update op for the row — once per historical row per
    // corrective import.
    final rowStartTime = truncatePkTimestampToDriftPrecision(
      switchEntry.timestamp,
    );
    var existing =
        await _frontingSessionRepository.getSessionById(rowId) ??
        await _findSessionByPkSwitchAndMember(
          switchId: switchEntry.id,
          localId: localId,
        );

    if (existing == null) {
      try {
        await _frontingSessionRepository.createSession(
          domain.FrontingSession(
            id: rowId,
            startTime: rowStartTime,
            memberId: localId,
            pluralkitUuid: switchEntry.id,
            pkImportSource: switchImportSource,
            pkFileSwitchId: pkFileSwitchId,
          ),
        );
        return _PkUpsertOutcome.row(rowId);
      } catch (error) {
        if (!isUniqueOrPrimaryKeyConstraintViolation(error)) rethrow;
        existing =
            await _frontingSessionRepository.getSessionById(rowId) ??
            await _findSessionByPkSwitchAndMember(
              switchId: switchEntry.id,
              localId: localId,
            );
        if (existing == null) rethrow;
      }
    }

    // Collision — usually a PRISM1 rescue row, with either the new
    // deterministic id or an older pre-derivation id. Correct by the DB
    // uniqueness key `(pluralkit_uuid, member_id)` so re-import is idempotent.
    //
    // is_deleted is absorbing in the deployed CRDT merge layer, so reviving a
    // tombstone IN PLACE can never propagate — it would diverge this device's
    // live row from every peer's "deleted" field_versions. So:
    // - incremental: collision on a soft-deleted row → tombstoneCollision (a
    //   user delete during routine sync must stick).
    // - corrective: tombstonePreserved, regardless of how the tombstone
    //   reached this device. Recovery must re-create under a FRESH id, never
    //   resurrect a burned one. Do NOT key a revive on deleteIntentEpoch — it
    //   is device-local and never syncs, so it diverges by construction.
    if (existing.isDeleted) {
      if (!corrective) {
        debugPrint(
          '[PK_SWEEP] entrant collision on deleted row ${existing.id}: '
          'preserved tombstone during incremental sync.',
        );
        return const _PkUpsertOutcome.tombstoneCollision();
      }
      debugPrint(
        '[PK_SWEEP] corrective entrant on tombstoned row ${existing.id}: '
        'preserving tombstone — is_deleted is absorbing, so in-place revival '
        'is unsyncable; re-creation under a fresh id is the only sync-safe '
        'recovery (F10).',
      );
      return const _PkUpsertOutcome.tombstonePreserved();
    }

    if (!corrective && existing.endTime != null) {
      debugPrint(
        '[PK_SWEEP] entrant collision on ${existing.id}: existing '
        'end_time ${existing.endTime} preserved (API says fronting; user '
        'may have closed the rescue row).',
      );
    }

    // The row is LIVE here (the deleted branch returned above), so there is no
    // is_deleted flip and no delete-push bookkeeping to clear. end_time policy:
    // - incremental (default): preserve a non-null existing end_time.
    // - corrective: API is authoritative. Clear end_time so active API rows
    //   surface as open; a later leaver in the same sweep will close it.
    //
    // `startTime` is the drift-truncated value: writing the raw µs over the
    // truncated stored one used to diff as "changed" and emit a sync op per
    // row per run. With both sides at whole-second precision an unchanged row
    // diffs empty and `updateSession` no-ops.
    final corrected = existing.copyWith(
      startTime: rowStartTime,
      memberId: localId,
      pluralkitUuid: switchEntry.id,
      pkImportSource: switchImportSource ?? existing.pkImportSource,
      pkFileSwitchId: switchImportSource == null
          ? existing.pkFileSwitchId
          : pkFileSwitchId,
      endTime: corrective ? null : existing.endTime,
    );
    await _frontingSessionRepository.updateSession(corrected);
    return _PkUpsertOutcome.row(existing.id);
  }

  /// Stable key for a canonical (switch uuid, local member id) pair. Used by
  /// the canonicalization pass to recognize a
  /// locally-pushed front whose row id is non-canonical but whose
  /// (pluralkit_uuid, member_id) the API still agrees with — those rows are
  /// adopted in place by the sweep, never tombstoned. Switch uuids and local
  /// member ids never contain U+0000, so it is a collision-free separator.
  static String _canonicalPairKey(String switchUuid, String localMemberId) =>
      '$switchUuid\u0000$localMemberId';

  Future<domain.FrontingSession?> _findSessionByPkSwitchAndMember({
    required String switchId,
    required String localId,
  }) async {
    final db = _syncDao.attachedDatabase;
    final row =
        await (db.select(db.frontingSessions)
              ..where(
                (s) =>
                    s.pluralkitUuid.equals(switchId) &
                    s.memberId.equals(localId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : FrontingSessionMapper.toDomain(row);
  }

  /// Walk PK switch history after a mapping Apply and import every switch.
  ///
  /// This is the entry point used after the user completes the mapping flow
  /// (see [importSwitchesAfterLink]). It uses the incremental diff sweep
  /// starting from the current resume cursor, so it's safe to call multiple
  /// times (idempotent via deterministic IDs and atomic cursor advance).
  ///
  /// [onProgress] is an optional external callback that mirrors the existing
  /// internal `_emit` progress updates so callers (e.g. the mapping
  /// controller's Apply pipeline) can drive their own UI without subscribing
  /// to this service's state stream. The fraction is the diff-sweep progress
  /// in `[0.0, 1.0]`; the status string includes the current switch index
  /// (`Importing switch i/total...`). It is invoked at the same cadence as
  /// the internal emit (every 50 switches).
  Future<void> importSwitchesAfterLink({
    void Function(double fraction, String status)? onProgress,
  }) async {
    if (!_state.isConnected) {
      throw StateError('Not connected — cannot import switch history');
    }
    // Claim the shared pull gate synchronously. The
    // post-mapping bootstrap (`_runPostApplyBootstrap`) calls this sequentially
    // after `syncLiveFrontersOnly`, so each release-before-next ordering still
    // holds; a concurrent caller bails as a benign no-op (matching the prior
    // `isSyncing` early-return contract).
    if (!_claimPull()) return;
    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Fetching PK switch history...',
        clearError: true,
      ),
    );

    // Release-and-rethrow around the build await so a throw out
    // of the token read cannot leak the pull gate (see _performFullImport).
    final PluralKitClient? client;
    try {
      client = await _buildClient();
    } catch (_) {
      _emit(_state.copyWith(isSyncing: false));
      _releasePull();
      rethrow;
    }
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      _releasePull();
      throw StateError('Not connected');
    }

    try {
      final shortIdToUuid = await _buildShortIdToUuidMap();

      // Fetch all switches from the beginning (this is the post-mapping full
      // history pull). Use the corrective full-sweep path: no pre-close needed
      // since the DB was empty (or will have no PK rows yet after mapping).
      final allSwitches = await _fetchAllSwitches(client);

      _emit(
        _state.copyWith(
          syncProgress: 0.5,
          syncStatus: 'Processing ${allSwitches.length} switches...',
        ),
      );

      // Active state is reconstituted from open PK-linked DB rows inside
      // [_runDiffSweep].
      await _runDiffSweep(
        switches: allSwitches,
        shortIdToUuid: shortIdToUuid,
        onProgress: (i) {
          if (i % 50 == 0 || i == allSwitches.length - 1) {
            final frac = allSwitches.isEmpty
                ? 1.0
                : 0.5 + 0.4 * (i / allSwitches.length);
            final status = 'Importing switch ${i + 1}/${allSwitches.length}...';
            _emit(_state.copyWith(syncProgress: frac, syncStatus: status));
            onProgress?.call(frac, status);
          }
        },
      );

      // Phase 1 R3 — insert-only re-attribution pass for PK groups.
      final importer = _groupsImporter;
      if (importer != null) {
        try {
          await importer.reattribute(client);
        } catch (e) {
          debugPrint('[PK] group reattribute failed: $e');
        }
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: 'Imported ${allSwitches.length} switches.',
        ),
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: formatPluralKitSyncError(
            'Switch history import failed: $e',
          ),
        ),
      );
      _bus.emit(
        PkRequestFailed(
          stage: 'importSwitchesAfterLink',
          errorKind: 'unknown',
          // Redact against the live client's token rather than a separately
          // captured value — see the importMembersOnly comment for the race.
          message: PkSyncEvent.redact(e.toString(), client.currentToken),
        ),
      );
      rethrow;
    } finally {
      client.dispose();
      _releasePull();
    }
  }

  // -- Plan 02: PK deletion push --------------------------------------------

  /// Threshold for the R6 multi-device coordination stamp. If another device
  /// recently claimed the push (within this window), we back off; past this
  /// window we assume the other device crashed or is offline and take over.
  static const _deletePushTakeoverThreshold = Duration(minutes: 10);

  /// F4/F5: how long a create-push lease is honored before a takeover adopts an
  /// orphan or re-POSTs. Mirrors [_deletePushTakeoverThreshold] and the
  /// matching constant in PkBidirectionalService.
  static const _createPushTakeoverThreshold = Duration(minutes: 10);

  bool _deleteLeaseActive(int? startedAtMs, DateTime now) {
    if (startedAtMs == null) return false;
    final age = Duration(
      milliseconds: now.millisecondsSinceEpoch - startedAtMs,
    );
    return age < _deletePushTakeoverThreshold;
  }

  bool _deleteIntentMatchesCurrentEpoch(int? intentEpoch, int currentEpoch) =>
      intentEpoch == currentEpoch;

  bool _hasPkMemberId(domain.Member member) =>
      (member.pluralkitId ?? '').trim().isNotEmpty;

  /// Count of switch-deletion candidates that could reach a PK mutation this
  /// pass — epoch-current, lease-free, with a valid PK switch uuid. Feeds the
  /// mass-deletion breaker for unattended syncs.
  ///
  /// Unlike `previewPendingDestructivePush`, this does NOT subtract the
  /// live-referenced set: a live-referenced candidate can still reach the
  /// members-PATCH (a real mutation), so counting it errs toward TRIPPING the
  /// breaker — the safe direction for a guard.
  int _eligibleSwitchDeletionCount(
    List<domain.FrontingSession> candidates,
    int currentEpoch,
  ) {
    final now = DateTime.now();
    var count = 0;
    for (final session in candidates) {
      final pkUuid = session.pluralkitUuid?.trim();
      if (!_deleteIntentMatchesCurrentEpoch(
            session.deleteIntentEpoch,
            currentEpoch,
          ) ||
          _deleteLeaseActive(session.deletePushStartedAt, now) ||
          pkUuid == null ||
          pkUuid.isEmpty ||
          !isPluralKitSwitchUuid(pkUuid)) {
        continue;
      }
      count++;
    }
    return count;
  }

  /// Count of member-deletion candidates that would reach a PK DELETE this pass
  /// — epoch-current, lease-free, with a PK short id, and not protected by the
  /// R5 cascade guard. Mirrors `previewPendingDestructivePush`'s member filter.
  int _eligibleMemberDeletionCount(
    List<domain.Member> candidates,
    int currentEpoch,
    Set<String> membersWithLiveLinkedSessions,
  ) {
    final now = DateTime.now();
    var count = 0;
    for (final member in candidates) {
      if (!_deleteIntentMatchesCurrentEpoch(
            member.deleteIntentEpoch,
            currentEpoch,
          ) ||
          _deleteLeaseActive(member.deletePushStartedAt, now) ||
          !_hasPkMemberId(member) ||
          membersWithLiveLinkedSessions.contains(member.id)) {
        continue;
      }
      count++;
    }
    return count;
  }

  Set<String> _memberIdsWithLiveLinkedSessions(
    List<domain.FrontingSession> rows,
  ) {
    final memberIds = <String>{};
    for (final session in rows) {
      if (session.isDeleted) continue;
      if (!isPluralKitSwitchUuid(session.pluralkitUuid)) continue;
      final memberId = session.memberId;
      if (memberId != null) memberIds.add(memberId);
    }
    return memberIds;
  }

  /// The set of `pluralkit_uuid` switch refs carried by LIVE local rows, used
  /// by the switch-level cascade guard so a switch DELETE is never pushed to
  /// PluralKit while any live local row still references that switch uuid.
  /// Mirrors [_memberIdsWithLiveLinkedSessions] at the switch granularity —
  /// `_pushPendingSwitchDeletions` (and `previewPendingDestructivePush`) skip
  /// any queued deletion whose fresh switch uuid is in this set.
  ///
  /// Refs are stored lowercased (trimmed) because `isPluralKitSwitchUuid`
  /// accepts mixed-case hex and member matching lowercases PK refs; callers
  /// must lowercase the queued uuid before `contains` so a case-variant live
  /// ref cannot slip past the guard.
  Set<String> _liveLinkedSwitchUuids(List<domain.FrontingSession> rows) {
    final switchUuids = <String>{};
    for (final session in rows) {
      if (session.isDeleted) continue;
      if (!isPluralKitSwitchUuid(session.pluralkitUuid)) continue;
      switchUuids.add(session.pluralkitUuid!.trim().toLowerCase());
    }
    return switchUuids;
  }

  /// Tombstone an importer-origin fronting row WITHOUT marking it a
  /// user-requested PluralKit deletion: clear the PK link FIRST, then soft
  /// delete. The link-clear makes `deleteSession`'s `isLinked` check false
  /// (drift_fronting_session_repository.dart), so no `deleteIntentEpoch` is
  /// ever stamped and `getDeletedLinkedSessions` never selects the row — the
  /// proven zero-length-close idiom (mirrors the `clearPluralKitLink` ->
  /// `deleteSession` ordering in the diff sweep's zero-length path).
  ///
  /// This guarantees that an importer cleanup tombstone never carries a PK
  /// link or a delete-intent stamp; only an explicit user `deleteSession` on a
  /// still-linked row may ever enqueue a PluralKit API deletion.
  Future<void> _tombstoneImporterArtifact(String rowId) async {
    await _frontingSessionRepository.clearPluralKitLink(rowId);
    await _frontingSessionRepository.deleteSession(rowId);
  }

  /// Run a PK-import Drift transaction [body] with every repository sync
  /// emission captured instead of dispatched, then replay the captured ops
  /// through the live FFI path only AFTER the transaction durably commits.
  ///
  /// This is the maintainer-blessed capture-then-replay seam
  /// ([SyncRecordMixin.suppressAndCapture] + [SyncRecordMixin.replayCapturedOps],
  /// production-proven in the SP importer): it keeps the FFI off the
  /// transaction's critical path and — load-bearing for the canonicalization
  /// fix — guarantees ZERO ops reach the engine if [body] throws. The
  /// exception propagates out of `suppressAndCapture` (whose suppression zone
  /// exits) before the replay loop is reached, so the captured list is dropped
  /// and the Drift rollback leaves no leaked tombstones on peers.
  ///
  /// Replay is row-granular through the shared [SyncRecordMixin.replayCapturedOps]
  /// (no hand-rolled dispatch, no delete coalescing — the wave-4 outbox drainer
  /// owns coalescing later, per cross-family resolution C10). Gated on the
  /// repository implementing [SyncRecordMixin]; if it does not (e.g. a test
  /// double), the captured ops are reported and dropped rather than silently
  /// lost.
  Future<T> _captureImportEmissions<T>(Future<T> Function() body) async {
    final captured = <CapturedSyncOp>[];
    final result = await SyncRecordMixin.suppressAndCapture<T>(
      body,
      captured.add,
    );
    if (captured.isEmpty) return result;
    final repo = _frontingSessionRepository;
    if (repo is SyncRecordMixin) {
      await (repo as SyncRecordMixin).replayCapturedOps(
        captured,
        logLabel: 'PK import',
      );
    } else {
      ErrorReportingService.instance.report(
        'PK import sync replay skipped: FrontingSessionRepository does not '
        'implement SyncRecordMixin (${captured.length} emission(s) captured).',
        severity: ErrorSeverity.warning,
      );
    }
    return result;
  }

  int _previewPendingMemberProxyTagRemovals({
    required List<domain.Member> localMembers,
    required List<PKMember> pkMembers,
    required Map<String, PkFieldSyncConfig> fieldConfigs,
    required PkSyncDirection direction,
  }) {
    final pkByUuid = <String, PKMember>{};
    final pkById = <String, PKMember>{};
    for (final pk in pkMembers) {
      pkByUuid[pk.uuid] = pk;
      pkById[pk.id] = pk;
    }

    var count = 0;
    for (final local in localMembers) {
      final pkUuid = local.pluralkitUuid?.trim();
      final pkId = local.pluralkitId?.trim();
      final pk =
          (pkUuid != null && pkUuid.isNotEmpty ? pkByUuid[pkUuid] : null) ??
          (pkId != null && pkId.isNotEmpty ? pkById[pkId] : null);
      if (pk == null) continue;

      final config = fieldConfigs[local.id] ?? const PkFieldSyncConfig();
      if (!_pushFieldForPreview(config.proxyTags, direction)) continue;
      if (_proxyTagPushRemovesPkData(local.proxyTagsJson, pk.proxyTagsJson)) {
        count++;
      }
    }
    return count;
  }

  bool _pushFieldForPreview(PkSyncDirection field, PkSyncDirection overall) {
    if (overall == PkSyncDirection.pullOnly) return false;
    if (overall == PkSyncDirection.pushOnly) return true;
    return field.pushEnabled;
  }

  bool _proxyTagPushRemovesPkData(String? localJson, String? pkJson) {
    final localTags = _proxyTagSet(localJson);
    final pkTags = _proxyTagSet(pkJson);
    if (localTags == null || pkTags == null || pkTags.isEmpty) return false;
    return !localTags.containsAll(pkTags);
  }

  Set<String>? _proxyTagSet(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      return decoded.map(_canonicalProxyTagEntry).toSet();
    } catch (_) {
      return null;
    }
  }

  String _canonicalProxyTagEntry(Object? entry) {
    if (entry is Map) {
      final keys = entry.keys.map((key) => key.toString()).toList()..sort();
      return jsonEncode({for (final key in keys) key: entry[key]});
    }
    return jsonEncode({'__raw__': entry});
  }

  /// Read-only preview of pending destructive PluralKit push work.
  ///
  /// This mirrors the local candidate filters used by the real deletion push
  /// path without claiming leases, clearing links, mutating sync state, or
  /// emitting sync progress. It fetches PK members only to detect proxy-tag
  /// removals.
  Future<PkDeleteRiskPreview> previewPendingDestructivePush() async {
    final syncRow = await _syncDao.getSyncState();
    final currentEpoch = await _syncDao.getLinkEpoch();
    final deletedSessions = await _frontingSessionRepository
        .getDeletedLinkedSessions();
    final deletedMembers = await _memberRepository.getDeletedLinkedMembers();
    final now = DateTime.now();

    // Fetch live sessions once and derive BOTH the switch-level cascade set
    // and the member set from it, so the preview's counts match what
    // `_pushPendingSwitchDeletions` / `_pushPendingMemberDeletions` do.
    final liveSessions = await _frontingSessionRepository.getAllSessions();
    final liveSwitchUuids = _liveLinkedSwitchUuids(liveSessions);

    var switchesToDelete = 0;
    var switchMemberRemovals = 0;
    var switchesSkipped = 0;
    for (final session in deletedSessions) {
      final pkUuid = session.pluralkitUuid?.trim();
      if (!_deleteIntentMatchesCurrentEpoch(
            session.deleteIntentEpoch,
            currentEpoch,
          ) ||
          _deleteLeaseActive(session.deletePushStartedAt, now) ||
          pkUuid == null ||
          pkUuid.isEmpty ||
          !isPluralKitSwitchUuid(pkUuid)) {
        // The push cannot mutate PK for this candidate at all (stale epoch,
        // active lease, missing/non-API uuid) — genuinely skipped.
        switchesSkipped++;
        continue;
      }
      // A live local row still references this switch, so the push won't fully
      // DELETE it — but it MAY still PATCH the departing member off the switch
      // (the members-removal path runs BEFORE the sole-fronter cascade guard).
      // That is a real destructive mutation, so count it as a removal that
      // requires confirmation, NOT a skip. Case-normalized so a case-variant
      // live ref can't slip past.
      if (liveSwitchUuids.contains(pkUuid.toLowerCase())) {
        switchMemberRemovals++;
        continue;
      }
      switchesToDelete++;
    }

    final membersWithLiveLinkedSessions = deletedMembers.isEmpty
        ? <String>{}
        : _memberIdsWithLiveLinkedSessions(liveSessions);

    var membersToDelete = 0;
    var membersSkipped = 0;
    for (final member in deletedMembers) {
      if (!_deleteIntentMatchesCurrentEpoch(
            member.deleteIntentEpoch,
            currentEpoch,
          ) ||
          _deleteLeaseActive(member.deletePushStartedAt, now) ||
          !_hasPkMemberId(member) ||
          membersWithLiveLinkedSessions.contains(member.id)) {
        membersSkipped++;
        continue;
      }
      membersToDelete++;
    }

    var groupMembershipsToRemove = 0;
    var groupMembershipsSkipped = 0;
    final groupsImporter = _groupsImporter;
    if (groupsImporter != null) {
      final groupPreview = await groupsImporter
          .previewPendingGroupMembershipRemovals();
      groupMembershipsToRemove = groupPreview.toRemove;
      groupMembershipsSkipped = groupPreview.skipped;
    }

    var memberProxyTagsToRemove = 0;
    final direction = parseGlobalSyncDirection(syncRow.fieldSyncConfig);
    if (direction.pushEnabled) {
      final client = await _buildClient();
      if (client == null) {
        throw StateError('Not connected — cannot preview member push risk');
      }
      try {
        memberProxyTagsToRemove = _previewPendingMemberProxyTagRemovals(
          localMembers: await _memberRepository.getAllMembers(),
          pkMembers: await client.getMembers(),
          fieldConfigs: parseFieldSyncConfig(syncRow.fieldSyncConfig),
          direction: direction,
        );
      } finally {
        client.dispose();
      }
    }

    return PkDeleteRiskPreview(
      membersToDelete: membersToDelete,
      switchesToDelete: switchesToDelete,
      switchMemberRemovals: switchMemberRemovals,
      groupMembershipsToRemove: groupMembershipsToRemove,
      memberProxyTagsToRemove: memberProxyTagsToRemove,
      membersSkipped: membersSkipped,
      switchesSkipped: switchesSkipped,
      groupMembershipsSkipped: groupMembershipsSkipped,
    );
  }

  /// Push pending switch deletions. Returns the number that succeeded.
  ///
  /// When [allowMassDeletion] is false (unattended syncs) and eligible
  /// candidates exceed [kPkMassDeletionAutoThreshold], NONE are executed —
  /// the device emits [PkMassDeletionBlocked] and bails. The user-confirmed
  /// manual destructive-push path sets it true, so deliberate cleanups run.
  Future<int> _pushPendingSwitchDeletions({
    required PluralKitClient client,
    void Function(String message)? onStaleLink,
    PkPushService? pushServiceOverride,
    bool allowMassDeletion = false,
  }) async {
    final currentEpoch = await _syncDao.getLinkEpoch();
    final candidates = await _frontingSessionRepository
        .getDeletedLinkedSessions();
    if (candidates.isEmpty) return 0;

    if (!allowMassDeletion) {
      final eligible = _eligibleSwitchDeletionCount(candidates, currentEpoch);
      if (eligible > kPkMassDeletionAutoThreshold) {
        debugPrint(
          '[PK] Mass-deletion breaker TRIPPED: $eligible eligible switch '
          'deletions exceed the $kPkMassDeletionAutoThreshold auto-threshold; '
          'refusing to delete any on this unattended sync. Run a manual sync '
          'to confirm.',
        );
        _bus.emit(
          PkMassDeletionBlocked(
            kind: 'switches',
            candidateCount: eligible,
            threshold: kPkMassDeletionAutoThreshold,
          ),
        );
        onStaleLink?.call(
          'Skipped deleting $eligible PluralKit switches automatically — '
          "that's an unusually large batch. Open PluralKit settings and run a "
          'manual sync to review and confirm the deletions.',
        );
        return 0;
      }
    }

    // Cascade guard input: switch uuids still referenced by a LIVE local row,
    // computed once before the loop. Consumed in the sole-fronter DELETE
    // branch below.
    final liveSwitchUuids = _liveLinkedSwitchUuids(
      await _frontingSessionRepository.getAllSessions(),
    );
    // The cascade-guard message is surfaced at most ONCE per push pass — a
    // guarded candidate is retried every cycle until the user resolves the
    // divergence (or the v34 legacy-gate migration clears the stamp), so
    // re-firing it per candidate per pass would spam the stale-link channel.
    var cascadeGuardMessageSent = false;

    final push = pushServiceOverride ?? const PkPushService();
    int deleted = 0;

    for (final session in candidates) {
      // R6: cross-device coordination stamp.
      final startedAtMs = session.deletePushStartedAt;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_deleteLeaseActive(
        startedAtMs,
        DateTime.fromMillisecondsSinceEpoch(nowMs),
      )) {
        final age = Duration(milliseconds: nowMs - startedAtMs!);
        debugPrint(
          '[PK] Switch deletion for ${session.id} has an active lease '
          '(stamped ${age.inSeconds}s ago by another device or by a prior '
          'failed attempt on this one) — skipping this pass.',
        );
        continue;
      }
      if (startedAtMs == null) {
        // NB: the lease is stamped before the snapshot GET below, so a
        // transient GET/PATCH failure burns up to the full lease window
        // before this device retries. That mirrors the pre-existing
        // DELETE-failure behavior and errs toward never double-writing PK.
        await _frontingSessionRepository.stampDeletePushStartedAt(
          session.id,
          nowMs,
        );
      }

      // R2: re-read and re-check every invariant at execution time.
      final fresh = await _frontingSessionRepository.getSessionById(session.id);
      if (fresh == null) continue;
      if (!fresh.isDeleted) {
        debugPrint(
          '[PK] Session ${session.id} was resurrected by CRDT merge; '
          'aborting DELETE.',
        );
        continue;
      }
      final freshPkUuid = fresh.pluralkitUuid?.trim();
      final queuedPkUuid = session.pluralkitUuid?.trim();
      if (freshPkUuid == null ||
          freshPkUuid.isEmpty ||
          freshPkUuid != queuedPkUuid) {
        debugPrint(
          '[PK] Session ${session.id} pluralkit_uuid changed since dequeue; '
          'aborting DELETE.',
        );
        continue;
      }
      // R1: epoch gate.
      final intentEpoch = session.deleteIntentEpoch;
      if (!_deleteIntentMatchesCurrentEpoch(intentEpoch, currentEpoch)) {
        debugPrint(
          '[PK] Session ${session.id} intent epoch $intentEpoch != current '
          '$currentEpoch; aborting DELETE (stale link).',
        );
        continue;
      }

      final pkUuid = freshPkUuid;
      if (!isPluralKitSwitchUuid(pkUuid)) {
        debugPrint(
          '[PK] Session ${session.id} has non-API pluralkit_uuid=$pkUuid; '
          'clearing local link without DELETE.',
        );
        await _frontingSessionRepository.clearPluralKitLink(session.id);
        continue;
      }

      // A PK switch is a FULL snapshot shared by ALL co-fronters: DELETE
      // erases every member's entry, so removing one member must PATCH down to
      // the remaining co-fronters — and that list must come from PK itself
      // (local rows only carry ENTRANT switch uuids, so a locally-derived
      // sibling list drops continuing fronters).
      final PKSwitch pkSwitchSnapshot;
      try {
        pkSwitchSnapshot = await client.getSwitch(pkUuid.trim());
      } on PluralKitAuthError {
        rethrow;
      } on PluralKitApiError catch (e) {
        if (e.statusCode == 404 ||
            e.code == 20007 ||
            (e.statusCode == 400 && e.code == 40006)) {
          // Switch gone (or its ref is invalid) — nothing to delete or
          // remove on PK. Clear the link so we stop retrying.
          debugPrint(
            '[PK] Switch ${pkUuid.trim()} for deleted session ${session.id} '
            'is gone/invalid on PK (${e.statusCode}/${e.code}); clearing '
            'local link.',
          );
          await _frontingSessionRepository.clearPluralKitLink(session.id);
          continue;
        }
        debugPrint(
          '[PK] Failed to fetch switch ${pkUuid.trim()} before deletion '
          'push: $e — retrying next pass.',
        );
        continue;
      } catch (e) {
        debugPrint(
          '[PK] Failed to fetch switch ${pkUuid.trim()} before deletion '
          'push: $e — retrying next pass.',
        );
        continue;
      }

      // Resolve the departing member's PK refs so we can subtract them from
      // the snapshot. Hids are case-insensitive on PK, and the snapshot list
      // could in principle carry uuids — match both, trimmed + lowercased.
      final departingLocalId = fresh.memberId;
      final departingMember = departingLocalId == null
          ? null
          : await _memberRepository.getMemberById(departingLocalId);
      final departShort = departingMember?.pluralkitId?.trim().toLowerCase();
      final departUuid = departingMember?.pluralkitUuid?.trim().toLowerCase();
      final hasShort = departShort != null && departShort.isNotEmpty;
      final hasUuid = departUuid != null && departUuid.isNotEmpty;
      if (!hasShort && !hasUuid) {
        // Fail-safe: we cannot tell which snapshot entry is the departing
        // member, so we can neither PATCH nor safely DELETE (the snapshot
        // may include co-fronters). Clear the local link and leave PK alone.
        debugPrint(
          '[PK] Deleted session ${session.id} has no resolvable PK member '
          'ref (memberId=$departingLocalId); clearing local link WITHOUT '
          'touching PK (2026-06 PK audit H2 fail-safe).',
        );
        await _frontingSessionRepository.clearPluralKitLink(session.id);
        continue;
      }

      // PK's order is preserved — only the departing member is subtracted.
      final remaining = <String>[];
      var removedAny = false;
      for (final ref in pkSwitchSnapshot.members) {
        final norm = ref.trim().toLowerCase();
        if ((hasShort && norm == departShort) ||
            (hasUuid && norm == departUuid)) {
          removedAny = true;
          continue;
        }
        remaining.add(ref);
      }

      if (!removedAny) {
        // The departing member is not on the PK switch at all — the removal
        // is already effective server-side. Handled, not pushed.
        debugPrint(
          '[PK] Member $departingLocalId is not on switch ${pkUuid.trim()} '
          'per PK snapshot; nothing to remove — clearing local link.',
        );
        await _frontingSessionRepository.clearPluralKitLink(session.id);
        continue;
      }

      if (remaining.isNotEmpty) {
        try {
          // Co-fronters remain on the snapshot: patch the switch down to
          // them, removing only the departing member.
          await client.updateSwitchMembers(pkUuid.trim(), remaining);
          await _frontingSessionRepository.clearPluralKitLink(session.id);
          deleted++;
          debugPrint(
            '[PK] Removed member from shared switch ${pkUuid.trim()} via '
            'members PATCH (${remaining.length} co-fronter(s) kept, PK '
            'order preserved) instead of deleting the switch (2026-06 PK '
            'audit H2).',
          );
        } on PluralKitApiError catch (e) {
          if (e is PluralKitAuthError) {
            rethrow;
          } else if (e.statusCode == 404 || e.code == 20007) {
            // Switch vanished between GET and PATCH. Clear the link.
            debugPrint(
              '[PK] Shared switch ${pkUuid.trim()} vanished before members '
              'PATCH; clearing local link.',
            );
            await _frontingSessionRepository.clearPluralKitLink(session.id);
          } else if (e.statusCode == 400 &&
              (e.code == 40004 || e.message.contains('40004'))) {
            // PK rejected the PATCH as identical-to-current — the member
            // set already matches `remaining`, so the removal is
            // effectively done. Treat as success.
            debugPrint(
              '[PK] Members PATCH on shared switch ${pkUuid.trim()} '
              'reported 40004 (already identical); treating as success.',
            );
            await _frontingSessionRepository.clearPluralKitLink(session.id);
            deleted++;
          } else {
            debugPrint(
              '[PK] Members PATCH failed removing member from shared switch '
              '${pkUuid.trim()}: $e',
            );
          }
        } catch (e) {
          debugPrint(
            '[PK] Members PATCH failed removing member from shared switch '
            '${pkUuid.trim()}: $e',
          );
        }
        continue;
      }

      // The departing member was the snapshot's SOLE fronter on PK — under
      // full-snapshot semantics no continuing member exists on PK for this
      // switch, so the historical `DELETE /switches/{uuid}` is reachable.
      //
      // Cascade guard: but a LIVE local row may still reference this switch
      // uuid. `DELETE` erases EVERY member's entry at the switch, so it would
      // destroy that live row's PK history too (the switch vanishes, its
      // canonical row becomes non-canonical on the next import, gets
      // tombstoned, and queues more deletions). The members-PATCH above
      // handles the case where PK still lists co-fronters; this guards the
      // divergent case where only the LOCAL view does. The departure stays
      // queued — a later explicit delete of the live row re-enables the push.
      if (liveSwitchUuids.contains(pkUuid.toLowerCase())) {
        debugPrint(
          '[PK] Cascade guard: refusing DELETE of switch $pkUuid for session '
          '${session.id} — a live local row still references it (F03).',
        );
        if (!cascadeGuardMessageSent) {
          cascadeGuardMessageSent = true;
          onStaleLink?.call(
            'Skipped deleting a PluralKit switch — it is still referenced by a '
            'live fronting record on this device. Delete that record first if '
            'you really want the switch removed from PluralKit.',
          );
        }
        continue;
      }
      try {
        await push.pushSwitchDeletion(session.id, pkUuid.trim(), client);
        await _frontingSessionRepository.clearPluralKitLink(session.id);
        deleted++;
      } on PkDeletionForbiddenException catch (e) {
        onStaleLink?.call(
          'PluralKit refused switch deletion — your token may not own this '
          'switch. Check your token and retry. (pkUuid=${e.pkId})',
        );
      } on PluralKitAuthError {
        rethrow;
      } catch (e) {
        debugPrint('[PK] Switch deletion failed for ${session.id}: $e');
      }
    }
    return deleted;
  }

  /// Test-only entry point onto the switch-deletion pusher (production goes
  /// through `syncRecentData`). [allowMassDeletion] defaults to true so the
  /// snapshot/PATCH tests aren't tripped by the mass-deletion breaker; the
  /// breaker test passes false explicitly.
  @visibleForTesting
  Future<int> debugPushPendingSwitchDeletions({
    required PluralKitClient client,
    void Function(String message)? onStaleLink,
    PkPushService? pushServiceOverride,
    bool allowMassDeletion = true,
  }) => _pushPendingSwitchDeletions(
    client: client,
    onStaleLink: onStaleLink,
    pushServiceOverride: pushServiceOverride,
    allowMassDeletion: allowMassDeletion,
  );

  /// Test-only entry point onto the member-deletion pusher so the
  /// mass-deletion breaker can be exercised in isolation. [allowMassDeletion]
  /// defaults to true for the same reason as the switch seam above.
  @visibleForTesting
  Future<int> debugPushPendingMemberDeletions({
    required PluralKitClient client,
    void Function(String message)? onStaleLink,
    PkPushService? pushServiceOverride,
    bool allowMassDeletion = true,
  }) => _pushPendingMemberDeletions(
    client: client,
    onStaleLink: onStaleLink,
    pushServiceOverride: pushServiceOverride,
    allowMassDeletion: allowMassDeletion,
  );

  /// Test-only seam onto the family's shared switch-level cascade-guard input.
  @visibleForTesting
  Set<String> debugLiveLinkedSwitchUuids(
    List<domain.FrontingSession> rows,
  ) => _liveLinkedSwitchUuids(rows);

  /// Test-only seam onto the importer-artifact tombstone helper
  /// (clear PK link, then soft delete — no delete-intent stamp).
  @visibleForTesting
  Future<void> debugTombstoneImporterArtifact(String rowId) =>
      _tombstoneImporterArtifact(rowId);

  /// Test-only seam onto the capture-replay PK-import transaction wrapper.
  @visibleForTesting
  Future<T> debugCaptureImportEmissions<T>(Future<T> Function() body) =>
      _captureImportEmissions<T>(body);

  /// Push pending member deletions. Runs AFTER switch deletions (caller
  /// orders). R5 cascade guard included: skip any member that still has
  /// live local sessions linked to PK.
  Future<int> _pushPendingMemberDeletions({
    required PluralKitClient client,
    void Function(String message)? onStaleLink,
    PkPushService? pushServiceOverride,
    bool allowMassDeletion = false,
  }) async {
    final currentEpoch = await _syncDao.getLinkEpoch();
    final candidates = await _memberRepository.getDeletedLinkedMembers();
    if (candidates.isEmpty) return 0;

    // R5: fetch live sessions once and check in-memory.
    final liveSessions = await _frontingSessionRepository.getAllSessions();
    final membersWithLiveLinkedSessions = _memberIdsWithLiveLinkedSessions(
      liveSessions,
    );

    // Mass-deletion breaker (symmetric with the switch
    // pusher): on unattended syncs, refuse a batch larger than the threshold.
    if (!allowMassDeletion) {
      final eligible = _eligibleMemberDeletionCount(
        candidates,
        currentEpoch,
        membersWithLiveLinkedSessions,
      );
      if (eligible > kPkMassDeletionAutoThreshold) {
        debugPrint(
          '[PK] Mass-deletion breaker TRIPPED: $eligible eligible member '
          'deletions exceed the $kPkMassDeletionAutoThreshold auto-threshold; '
          'refusing to delete any on this unattended sync. Run a manual sync '
          'to confirm.',
        );
        _bus.emit(
          PkMassDeletionBlocked(
            kind: 'members',
            candidateCount: eligible,
            threshold: kPkMassDeletionAutoThreshold,
          ),
        );
        onStaleLink?.call(
          'Skipped deleting $eligible PluralKit members automatically — '
          "that's an unusually large batch. Open PluralKit settings and run a "
          'manual sync to review and confirm the deletions.',
        );
        return 0;
      }
    }

    final push = pushServiceOverride ?? const PkPushService();
    int deleted = 0;

    for (final member in candidates) {
      if (membersWithLiveLinkedSessions.contains(member.id)) {
        debugPrint(
          '[PK] R5 cascade guard: member ${member.id} has live linked '
          'sessions; skipping DELETE.',
        );
        onStaleLink?.call(
          // raw-name-ok: diagnostic message, not a member-name UI surface.
          "Skipped deleting PluralKit member '${member.name}' — it still "
          'has linked local switches. Delete those first, or undelete the '
          'member to keep it.',
        );
        continue;
      }

      // R6: coordination lease.
      final startedAtMs = member.deletePushStartedAt;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_deleteLeaseActive(
        startedAtMs,
        DateTime.fromMillisecondsSinceEpoch(nowMs),
      )) {
        final age = Duration(milliseconds: nowMs - startedAtMs!);
        debugPrint(
          '[PK] Member deletion for ${member.id} started by another '
          'device ${age.inSeconds}s ago — skipping.',
        );
        continue;
      }
      if (startedAtMs == null) {
        await _memberRepository.stampDeletePushStartedAt(member.id, nowMs);
      }

      // R2 re-read.
      final fresh = await _memberRepository.getMemberById(member.id);
      if (fresh == null) continue;
      if (!fresh.isDeleted) {
        debugPrint(
          '[PK] Member ${member.id} was resurrected by CRDT merge; aborting.',
        );
        continue;
      }
      final freshPkId = fresh.pluralkitId?.trim();
      final queuedPkId = member.pluralkitId?.trim();
      if (freshPkId == null || freshPkId.isEmpty || freshPkId != queuedPkId) {
        debugPrint(
          '[PK] Member ${member.id} pluralkit_id changed since dequeue; '
          'aborting DELETE.',
        );
        continue;
      }
      final intentEpoch = member.deleteIntentEpoch;
      if (!_deleteIntentMatchesCurrentEpoch(intentEpoch, currentEpoch)) {
        debugPrint(
          '[PK] Member ${member.id} intent epoch $intentEpoch != current '
          '$currentEpoch; aborting DELETE (stale link).',
        );
        continue;
      }

      final pkId = freshPkId;
      try {
        await push.pushMemberDeletion(member.id, pkId, client);
        await _memberRepository.clearPluralKitLink(member.id);
        deleted++;
      } on PkDeletionForbiddenException catch (e) {
        onStaleLink?.call(
          // raw-name-ok: diagnostic message, not a member-name UI surface.
          "PluralKit refused member deletion of '${member.name}' — your "
          'token may not own this member. Check your token and retry. '
          '(pkId=${e.pkId})',
        );
      } on PluralKitAuthError {
        rethrow;
      } catch (e) {
        debugPrint('[PK] Member deletion failed for ${member.id}: $e');
      }
    }
    return deleted;
  }

  /// Phase 4 scoped switch push.
  ///
  /// PluralKit switches are snapshots of the current fronter set. This push
  /// path reconciles the local active set against PK's current fronters and
  /// only creates a new switch when those sets differ.
  Future<PkPushSwitchesResult> pushPendingSwitches({
    PkPushService? pushService,
    void Function(String message)? onStaleLink,
    bool allowDuringSync = false,
    PKSwitch? knownCurrentFronters,
    bool refreshMembersOnStaleLink = true,
  }) async {
    if (!_state.isConnected) {
      throw StateError('Not connected — cannot push switches');
    }
    if (!_state.canAutoSync) {
      return const PkPushSwitchesResult();
    }
    final linkedAt = _state.linkedAt;
    if (linkedAt == null) {
      return const PkPushSwitchesResult();
    }
    // Bail when a pull holds EITHER the legacy emitted
    // `isSyncing` flag OR the synchronous `_pullInFlight` gate. The gate is
    // claimed before the first await at every pull entry point, so a window
    // where a pull has started but not yet emitted `isSyncing:true` (e.g.
    // syncRecentData's first-sync branch) is still treated as in-progress.
    // Pull's own phase-4 push passes `allowDuringSync: true` to bypass this.
    if ((_state.isSyncing || _pullInFlight) && !allowDuringSync) {
      return const PkPushSwitchesResult();
    }

    final existing = _pushInFlight;
    if (existing != null) {
      // A push is already running. The running future
      // captured the member/session state from BEFORE this call's trigger, so
      // simply returning it would drop the trailing change. Mark dirty and hand
      // back the follow-up future — exactly ONE follow-up runs after the
      // current push, picking up the latest state. A burst of mid-flight
      // triggers coalesces onto the same [_pushFollowUp] completer.
      _pushDirty = true;
      // Carry this caller's stale-link sink AND refresh flag onto the
      // follow-up so the follow-up behaves like the latest trigger (last
      // writer wins — the sink is an additive log channel, and the refresh
      // flag must reflect the most recent caller's sync mode rather than a
      // stale earlier capture).
      _lastPushOnStaleLink = onStaleLink ?? _lastPushOnStaleLink;
      _lastPushRefreshMembersOnStaleLink = refreshMembersOnStaleLink;
      final followUp = (_pushFollowUp ??= Completer<PkPushSwitchesResult>());
      return followUp.future;
    }

    // Remember default-arg shape for any follow-up the dirty flag schedules.
    _lastPushOnStaleLink = onStaleLink;
    _lastPushRefreshMembersOnStaleLink = refreshMembersOnStaleLink;

    return _runOnePush(
      pushService: pushService ?? const PkPushService(),
      onStaleLink: onStaleLink,
      knownCurrentFronters: knownCurrentFronters,
      refreshMembersOnStaleLink: refreshMembersOnStaleLink,
    );
  }

  /// Runs a single push and, on completion, schedules at most one follow-up if
  /// the dirty flag was raised while it ran. The follow-up resolves the
  /// shared [_pushFollowUp] completer so mid-flight callers get a result that
  /// reflects their trailing state. Terminates naturally: a follow-up that
  /// finds the state already in sync short-circuits inside
  /// [_doPushPendingSwitches] without raising the dirty flag (only EXTERNAL
  /// callers raise it), so identical-state runs don't re-trigger.
  Future<PkPushSwitchesResult> _runOnePush({
    required PkPushService pushService,
    void Function(String message)? onStaleLink,
    PKSwitch? knownCurrentFronters,
    required bool refreshMembersOnStaleLink,
  }) {
    // A fresh run starts clean — only external mid-flight callers set dirty.
    _pushDirty = false;

    // Captured via callback from inside `_doPushPendingSwitches` as soon as
    // the client is built. We redact against this rather than a separately-
    // read secure-storage value so a clearToken/setToken race between the
    // outer storage read and the client's storage read can't leave us
    // redacting against a stale or null token while the exception still
    // embeds the client's actual token.
    String? clientToken;

    late final Future<PkPushSwitchesResult> future;
    future =
        _doPushPendingSwitches(
              pushService: pushService,
              onStaleLink: onStaleLink,
              knownCurrentFronters: knownCurrentFronters,
              onClientReady: (token) => clientToken = token,
              refreshMembersOnStaleLink: refreshMembersOnStaleLink,
            )
            .then((result) {
              _bus.emit(PkSwitchPushed(pushed: result.pushed, deleted: 0));
              return result;
            })
            .catchError((Object e) async {
              // Fall back to a fresh storage read only if the client was never
              // built (e.g. the not-connected guard fired before
              // `onClientReady`). Otherwise prefer the captured client token.
              final redactToken = clientToken ?? await _getToken();
              _bus.emit(
                PkRequestFailed(
                  stage: 'pushPendingSwitches',
                  errorKind: 'unknown',
                  message: PkSyncEvent.redact(e.toString(), redactToken),
                ),
              );
              throw e;
            });

    // Settle the in-flight slot + the follow-up on BOTH success and failure,
    // but only SCHEDULE a follow-up after a SUCCESSFUL run. A failed run already
    // delivered its error to every waiter (including the dirty ones); re-running
    // on an unchanged failing state would just loop on the same error — the
    // existing "concurrent callers share one exception" contract. The follow-up
    // exists to flush a TRAILING change after a healthy push, where the in-sync
    // short-circuit terminates the chain when state is stable.
    future.then(
      (result) {
        if (identical(_pushInFlight, future)) _pushInFlight = null;
        _settlePushFollowUp(succeeded: true, completedResult: result);
      },
      onError: (Object e, StackTrace st) {
        if (identical(_pushInFlight, future)) _pushInFlight = null;
        _settlePushFollowUp(succeeded: false, error: e, stackTrace: st);
      },
    );
    _pushInFlight = future;
    return future;
  }

  /// Follow-up scheduler. Called once the current run
  /// settles. When a mid-flight caller raised the dirty flag AND the run
  /// SUCCEEDED, start exactly one follow-up (default args, NO stale
  /// `knownCurrentFronters`) and forward its outcome to the shared completer;
  /// the follow-up's in-sync short-circuit terminates the chain on stable state.
  /// On failure, or when no trailing change was flagged, resolve the waiters
  /// directly from this run's outcome — no follow-up.
  void _settlePushFollowUp({
    required bool succeeded,
    PkPushSwitchesResult? completedResult,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final waiter = _pushFollowUp;
    if (waiter == null) return; // nobody arrived mid-flight.

    if (succeeded && _pushDirty) {
      // Detach the completer so the NEXT run can collect its own waiters, then
      // run one follow-up and forward its outcome to the detached waiter.
      _pushFollowUp = null;
      _runOnePush(
        pushService: const PkPushService(),
        onStaleLink: _lastPushOnStaleLink,
        knownCurrentFronters: null,
        refreshMembersOnStaleLink: _lastPushRefreshMembersOnStaleLink,
      ).then(waiter.complete, onError: waiter.completeError);
      return;
    }

    // No trailing change (or the run failed) — resolve the waiters from this
    // run's own outcome so mid-flight callers still get an answer.
    _pushFollowUp = null;
    if (succeeded) {
      waiter.complete(completedResult);
    } else {
      waiter.completeError(error!, stackTrace);
    }
  }

  Future<PkPushSwitchesResult> _doPushPendingSwitches({
    required PkPushService pushService,
    void Function(String message)? onStaleLink,
    PKSwitch? knownCurrentFronters,
    void Function(String token)? onClientReady,
    bool refreshMembersOnStaleLink = true,
  }) async {
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');
    onClientReady?.call(client.currentToken);

    try {
      final members = await _memberRepository.getAllMembers();
      final localIdToPkId = <String, String>{};
      // Parallel short-id → uuid map. ALL comparison /
      // stamping logic stays keyed on the SHORT id (PK returns
      // `pkCurrent.members` as short ids, so the 40004/in-sync reasoning must
      // compare in short-id space). The uuid map exists SOLELY to translate the
      // ordered short-id wire list into uuids at the POST/PATCH boundary, since
      // short ids become user-changeable under PK Premium and the uuid is the
      // only stable ref. Members without a uuid fall back to their short id.
      final pkIdToPkUuid = <String, String>{};
      for (final m in members) {
        if (m.pluralkitSyncIgnored) continue;
        final pkId = m.pluralkitId?.trim();
        if (pkId != null && pkId.isNotEmpty) {
          localIdToPkId[m.id] = pkId;
          final pkUuid = m.pluralkitUuid?.trim();
          if (pkUuid != null && pkUuid.isNotEmpty) {
            pkIdToPkUuid[pkId] = pkUuid;
          }
        }
      }

      final rawActive = await _frontingSessionRepository
          .getAllActiveSessionsUnfiltered();
      final hasActiveSleep = rawActive.any(
        (session) => session.isSleep && !session.isDeleted,
      );
      final membersById = {for (final member in members) member.id: member};
      final localActive = rawActive.where((session) {
        if (session.isSleep || session.isDeleted) return false;
        final memberId = session.memberId;
        if (memberId == null) return false;
        return _hasText(localIdToPkId[memberId]);
      }).toList();

      final localPkIdsForPush = _orderedUniquePkIdsForPush(
        localActive,
        localIdToPkId,
        membersById,
      );
      // Index-aligned uuid-first wire refs. This list
      // is byte-for-byte the same ORDER as `localPkIdsForPush`; only the values
      // differ (uuid where known, else the short id). NEVER feed this into a
      // comparison against `pkCurrent.members` (those are short ids) — it is
      // ONLY for createSwitch / updateSwitchMembers payloads.
      final localWireRefsForPush = _wireRefsForPush(
        localPkIdsForPush,
        pkIdToPkUuid,
      );
      final localPkSet = _sortedUniqueStrings(localPkIdsForPush);
      final activeSleepOnly = localActive.isEmpty && hasActiveSleep;
      if (activeSleepOnly) {
        final syncState = await _syncDao.getSyncState();
        if (parsePkSleepSyncBehavior(syncState.fieldSyncConfig) ==
            PkSleepSyncBehavior.leaveUnchanged) {
          return const PkPushSwitchesResult();
        }
        // PK clears fronters through an empty switch, so fall through.
      }

      final pkCurrent =
          knownCurrentFronters ?? await client.getCurrentFronters();
      final pkPkSet = _sortedUniqueStrings(pkCurrent?.members ?? const []);

      if (_sameStringSet(localPkSet, pkPkSet)) {
        final orderDiffersFromPk = !_sameStringList(
          localPkIdsForPush,
          pkCurrent?.members ?? const [],
        );
        if (orderDiffersFromPk) {
          // Only re-PATCH the order when the LOCAL order genuinely changed
          // since the baseline (see [_lastObservedLocalPushOrder]); on a
          // null / different-set baseline, re-anchor WITHOUT patching so a
          // PK-side reorder is never clobbered by an intent-less trigger.
          final baseline = _lastObservedLocalPushOrder;
          final baselineComparable =
              baseline != null &&
              _sameStringSet(_sortedUniqueStrings(baseline), localPkSet);
          final localOrderChanged =
              baselineComparable &&
              !_sameStringList(localPkIdsForPush, baseline);
          if (!localOrderChanged) {
            debugPrint(
              '[PK_PUSH] order differs from PK but local order is '
              '${baselineComparable ? 'unchanged since last push' : 'newly observed'}; '
              'leaving the PK-side order in place (2026-06 PK audit M12).',
            );
            _lastObservedLocalPushOrder = List.unmodifiable(localPkIdsForPush);
          } else {
            final switchUuid = pkCurrent?.id.trim();
            if (switchUuid != null && switchUuid.isNotEmpty) {
              try {
                // Send uuid-first refs on the wire; the order matches the
                // short-id comparison list above exactly (same indices).
                await client.updateSwitchMembers(
                  switchUuid,
                  localWireRefsForPush,
                );
                // A successful order PATCH re-anchors the baseline.
                _lastObservedLocalPushOrder = List.unmodifiable(
                  localPkIdsForPush,
                );
                final repair = await _repairUnstampedEntrants(
                  localActive: localActive,
                  localIdToPkId: localIdToPkId,
                  pkCurrent: pkCurrent,
                  pkPkSet: pkPkSet.toSet(),
                );
                return PkPushSwitchesResult(
                  pushed: 1,
                  repaired: repair.repaired,
                );
              } on PluralKitApiError catch (e) {
                if (e.statusCode == 404) {
                  debugPrint(
                    '[PK_PUSH] Current switch vanished before order patch '
                    '(switchUuid=$switchUuid); treating as stale.',
                  );
                  onStaleLink?.call(
                    'A PluralKit switch target was removed on the server — '
                    'skipped reordering the current front. '
                    '(switchId=$switchUuid)',
                  );
                  return const PkPushSwitchesResult();
                }
                if (e.statusCode == 400 && e.message.contains('40004')) {
                  debugPrint(
                    '[PK_PUSH] PK rejected order-only switch patch as '
                    'identical (40004); treating as in sync.',
                  );
                  // PK says the order already matches — in sync.
                  _lastObservedLocalPushOrder = List.unmodifiable(
                    localPkIdsForPush,
                  );
                } else {
                  // Failed PATCH: leave the baseline as-is so the genuine
                  // local reorder retries on the next trigger.
                  rethrow;
                }
              }
            }
          }
        } else {
          // Local and PK fully agree — anchor the baseline so the NEXT
          // divergence can be classified as local-reorder vs PK-reorder.
          _lastObservedLocalPushOrder = List.unmodifiable(localPkIdsForPush);
        }
        return _repairUnstampedEntrants(
          localActive: localActive,
          localIdToPkId: localIdToPkId,
          pkCurrent: pkCurrent,
          pkPkSet: pkPkSet.toSet(),
        );
      }

      final pushTs = DateTime.now().toUtc();
      PKSwitch newSwitch;
      var pushedPkSet = localPkSet;
      // The ordered short-id list actually sent on the wire — what PK now
      // stores as the switch order, and therefore the new order baseline. The
      // stale-link retry below narrows it to the filtered list.
      var pushedOrder = localPkIdsForPush;
      try {
        // POST uuid-first wire refs. `pushedPkSet`/`localPkSet` stay in
        // SHORT-id space for entrant stamping below (PK echoes the switch with
        // short ids and our local rows key on short ids).
        newSwitch = await pushService.pushSwitch(
          localWireRefsForPush,
          client,
          timestamp: pushTs,
        );
      } on PluralKitApiError catch (e) {
        // PK rejects identical-set pushes with code 40004. This happens when
        // our local snapshot of pkPkSet was stale (e.g., another device
        // pushed concurrently). Treat as benign: PK and local are in sync.
        if (e.statusCode == 400 && e.message.contains('40004')) {
          debugPrint(
            '[PK_PUSH] PK reports member set already current (40004); '
            'skipping push and trusting PK as source of truth.',
          );
          return const PkPushSwitchesResult();
        }
        rethrow;
      } on PkStaleLinkException catch (e) {
        final retry = await _retrySwitchPushAfterStaleLink(
          client: client,
          pushService: pushService,
          localPkIdsForPush: localPkIdsForPush,
          pkIdToPkUuid: pkIdToPkUuid,
          timestamp: pushTs,
          onStaleLink: onStaleLink,
          staleError: e,
          refreshMembers: refreshMembersOnStaleLink,
        );
        if (retry == null) return const PkPushSwitchesResult();
        newSwitch = retry.$1;
        pushedPkSet = retry.$2;
        pushedOrder = retry.$2; // M12: retry list IS the ordered wire list.
      }

      // A successful set push establishes the order baseline — PK now stores
      // exactly this order, and it was derived from local state.
      _lastObservedLocalPushOrder = List.unmodifiable(pushedOrder);

      final entrantPkIds = pushedPkSet.toSet()..removeAll(pkPkSet);
      await _stampEntrants(
        localActive: localActive,
        localIdToPkId: localIdToPkId,
        entrantPkIds: entrantPkIds,
        switchUuid: newSwitch.id,
      );
      return const PkPushSwitchesResult(pushed: 1);
    } finally {
      client.dispose();
    }
  }

  /// Returns `(createdSwitch, filteredShortIds)`. The second element is in
  /// SHORT-id space so the caller's entrant stamping stays correct; the POST
  /// itself uses uuid-first wire refs.
  Future<(PKSwitch, List<String>)?> _retrySwitchPushAfterStaleLink({
    required PluralKitClient client,
    required PkPushService pushService,
    required List<String> localPkIdsForPush,
    required Map<String, String> pkIdToPkUuid,
    required DateTime timestamp,
    required PkStaleLinkException staleError,
    void Function(String message)? onStaleLink,
    required bool refreshMembers,
  }) async {
    if (!refreshMembers) {
      debugPrint(
        '[PK] Stale link on snapshot switch push (pkId=${staleError.pkId}); '
        'skipping member refresh for live-front-only sync.',
      );
      onStaleLink?.call(
        'A PluralKit switch target was removed on the server — '
        'skipped pushing the current front. (pkId=${staleError.pkId})',
      );
      return null;
    }

    debugPrint(
      '[PK] Stale link on snapshot switch push (pkId=${staleError.pkId}); '
      'refreshing PK members and retrying once.',
    );

    // Refresh from PK: keep the live short ids for filtering AND a fresh
    // short-id → uuid map so the retry POST carries current uuids even if a
    // member's short id changed (Premium) since the cached map was built.
    final liveMembers = await client.getMembers();
    final livePkIds = <String>{};
    final refreshedPkIdToUuid = <String, String>{};
    for (final m in liveMembers) {
      final id = m.id.trim();
      if (id.isEmpty) continue;
      livePkIds.add(id);
      final uuid = m.uuid.trim();
      if (uuid.isNotEmpty) refreshedPkIdToUuid[id] = uuid;
    }
    final filteredPkIdsForPush = localPkIdsForPush
        .where(livePkIds.contains)
        .toList();
    // Build the index-aligned wire list from the refreshed map first, falling
    // back to the originally-captured map then the short id.
    final filteredWireRefs = [
      for (final pkId in filteredPkIdsForPush)
        refreshedPkIdToUuid[pkId] ?? pkIdToPkUuid[pkId] ?? pkId,
    ];

    try {
      final created = await pushService.pushSwitch(
        filteredWireRefs,
        client,
        timestamp: timestamp,
      );
      return (created, filteredPkIdsForPush);
    } on PkStaleLinkException catch (retryError) {
      debugPrint(
        '[PK] Snapshot switch push failed after stale-link retry '
        '(pkId=${retryError.pkId}).',
      );
      onStaleLink?.call(
        'A PluralKit switch target was removed on the server — '
        'skipped pushing the current front. (pkId=${retryError.pkId})',
      );
      return null;
    }
  }

  Future<PkPushSwitchesResult> _repairUnstampedEntrants({
    required List<domain.FrontingSession> localActive,
    required Map<String, String> localIdToPkId,
    required PKSwitch? pkCurrent,
    required Set<String> pkPkSet,
  }) async {
    final switchUuid = pkCurrent?.id.trim();
    if (switchUuid == null || switchUuid.isEmpty) {
      return const PkPushSwitchesResult();
    }

    final unstampedPkIds = <String>{};
    var repaired = 0;
    for (final session in localActive) {
      if (_hasText(session.pluralkitUuid)) continue;
      final memberId = session.memberId;
      if (memberId == null) continue;
      final pkId = localIdToPkId[memberId];
      if (pkId == null || !pkPkSet.contains(pkId)) continue;
      unstampedPkIds.add(pkId);
      repaired++;
    }
    if (unstampedPkIds.isEmpty) return const PkPushSwitchesResult();

    await _stampEntrants(
      localActive: localActive,
      localIdToPkId: localIdToPkId,
      entrantPkIds: unstampedPkIds,
      switchUuid: switchUuid,
    );
    return PkPushSwitchesResult(repaired: repaired);
  }

  Future<void> _stampEntrants({
    required List<domain.FrontingSession> localActive,
    required Map<String, String> localIdToPkId,
    required Set<String> entrantPkIds,
    required String switchUuid,
  }) async {
    for (final pkId in entrantPkIds) {
      final candidates = localActive.where((session) {
        final memberId = session.memberId;
        return memberId != null &&
            localIdToPkId[memberId] == pkId &&
            !_hasText(session.pluralkitUuid);
      }).toList();
      if (candidates.isEmpty) continue;

      final target = candidates.first;
      try {
        await _frontingSessionRepository.updateSession(
          target.copyWith(pluralkitUuid: switchUuid),
        );
      } catch (e) {
        if (isUniqueConstraintViolation(e)) {
          debugPrint(
            '[PK_PUSH] stamp collision on ($switchUuid,${target.memberId}); '
            'duplicates exist',
          );
          continue;
        }
        rethrow;
      }
    }
  }

  List<String> _orderedUniquePkIdsForPush(
    List<domain.FrontingSession> sessions,
    Map<String, String> localIdToPkId,
    Map<String, domain.Member> membersById,
  ) {
    final sortedSessions = sessions.toList()
      ..sort((a, b) {
        final startCmp = b.startTime.compareTo(a.startTime);
        if (startCmp != 0) return startCmp;
        final aMember = a.memberId == null ? null : membersById[a.memberId!];
        final bMember = b.memberId == null ? null : membersById[b.memberId!];
        final orderCmp = (aMember?.displayOrder ?? 0).compareTo(
          bMember?.displayOrder ?? 0,
        );
        if (orderCmp != 0) return orderCmp;
        return (a.memberId ?? '').compareTo(b.memberId ?? '');
      });

    final seenPkIds = <String>{};
    final ordered = <String>[];
    for (final session in sortedSessions) {
      final memberId = session.memberId;
      if (memberId == null) continue;
      final pkId = localIdToPkId[memberId];
      if (pkId != null && pkId.isNotEmpty && seenPkIds.add(pkId)) {
        ordered.add(pkId);
      }
    }
    return ordered;
  }

  /// Translate an ordered short-id push list into index-aligned uuid-first
  /// wire refs. The output has the SAME length and
  /// order as [orderedShortIds]; each entry is the member's uuid when known,
  /// else the short id unchanged. This is the ONLY place a uuid enters a switch
  /// payload — every set/order comparison upstream keeps using the short ids.
  List<String> _wireRefsForPush(
    List<String> orderedShortIds,
    Map<String, String> pkIdToPkUuid,
  ) {
    return [
      for (final pkId in orderedShortIds) pkIdToPkUuid[pkId] ?? pkId,
    ];
  }

  List<String> _sortedUniqueStrings(Iterable<String> values) {
    final ids = values.map((value) => value.trim()).where(_hasText).toSet();
    return ids.toList()..sort();
  }

  bool _sameStringSet(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  bool _sameStringList(List<String> left, Iterable<String> rightValues) {
    final right = rightValues.map((value) => value.trim()).where(_hasText);
    final iterator = right.iterator;
    for (final value in left) {
      if (!iterator.moveNext() || iterator.current != value) return false;
    }
    return !iterator.moveNext();
  }

  /// Push a single linked member's fields to PluralKit after a local edit.
  ///
  /// Caller is responsible for gating on connection state and push-direction
  /// (see `PluralKitSyncNotifier.pushMemberUpdate`). A 404 from PK clears the
  /// local link so the user can re-link via the mapping screen.
  /// Proxy tags are omitted here so destructive removals go through manual
  /// sync's delete-risk preview.
  ///
  /// Returns true if a PATCH was actually sent, false when skipped (no link,
  /// not connected, direction config forbids every field, etc.). Errors are
  /// surfaced as a redacted [PkRequestFailed] event (so the sync log sees them)
  /// and swallowed so a failed push never breaks the user's edit flow — the
  /// next manual sync retries.
  ///
  /// The push is enqueued onto a single coalescing drain (see
  /// [_pendingMemberPushes]): same-member edits coalesce to one PATCH of the
  /// latest state, members run sequentially through one client+queue (PK's
  /// 3/s budget), and per-field direction config gates the payload.
  Future<bool> pushMemberUpdate(
    domain.Member member, {
    PkPushService? pushService,
  }) async {
    if (member.pluralkitSyncIgnored) return false;
    final pkId = member.pluralkitId?.trim();
    if (pkId == null || pkId.isEmpty) return false;
    if (!_state.canAutoSync) return false;

    // Carry the legacy test seam through to the drain. Production never sets
    // this, so concurrent callers always share the same `const PkPushService`.
    if (pushService != null) _memberPushServiceOverride = pushService;

    // Record the latest state for this member; coalesce successive edits.
    _pendingMemberPushes[member.id] = member;
    final waiter = _memberPushWaiters.putIfAbsent(
      member.id,
      Completer<bool>.new,
    );

    // Start the drain if one isn't already running; otherwise the in-flight
    // loop will pick this member up on its next iteration.
    _memberPushDrain ??= _drainMemberPushes();

    return waiter.future;
  }

  /// Drain [_pendingMemberPushes] through ONE client until empty.
  /// Members are processed one at a time so the client's request
  /// queue paces the whole burst; the latest map entry is read at dispatch
  /// time so a same-member edit that arrived after enqueue still wins.
  Future<void> _drainMemberPushes() async {
    try {
      final push = _memberPushServiceOverride ?? const PkPushService();

      // Load the field-sync config once per drain (it changes rarely; a stale
      // read retries next manual sync). Guarded: an unguarded throw (closed
      // DB at shutdown) would leave the queue non-empty and the restart
      // branch re-spawning the drain forever — fail the waiters and clear.
      final PluralKitSyncStateData syncRow;
      try {
        syncRow = await _syncDao.getSyncState();
      } catch (e) {
        debugPrint('[PK_PUSH] member-push drain setup failed: $e');
        _pendingMemberPushes.clear();
        final waiters = List.of(_memberPushWaiters.values);
        _memberPushWaiters.clear();
        for (final w in waiters) {
          w.complete(false);
        }
        return;
      }
      final globalDirection = parseGlobalSyncDirection(syncRow.fieldSyncConfig);
      final fieldConfigs = parseFieldSyncConfig(syncRow.fieldSyncConfig);

      PluralKitClient? client;
      try {
        while (_pendingMemberPushes.isNotEmpty) {
          final id = _pendingMemberPushes.keys.first;
          final member = _pendingMemberPushes.remove(id)!;
          final waiter = _memberPushWaiters.remove(id);

          bool result;
          try {
            // Build the client lazily on first dispatch so a drain with only
            // direction-skipped members never dispatches a request (the
            // object itself is cheap; its HTTP client connects lazily).
            client ??= await _buildClient();
            if (client == null) {
              result = false;
            } else {
              result = await _pushOneMember(
                member,
                client,
                push,
                globalDirection,
                fieldConfigs,
              );
            }
          } catch (e) {
            result = false;
            _bus.emit(
              PkRequestFailed(
                stage: 'pushMemberUpdate',
                errorKind: 'unknown',
                message: PkSyncEvent.redact(
                  e.toString(),
                  client?.currentToken,
                ),
              ),
            );
          }
          waiter?.complete(result);
        }
      } finally {
        client?.dispose();
      }
    } finally {
      _memberPushDrain = null;
      // A new edit may have arrived between the loop's last `isEmpty` check and
      // clearing the drain handle; restart so it isn't stranded.
      if (_pendingMemberPushes.isNotEmpty) {
        _memberPushDrain = _drainMemberPushes();
      }
    }
  }

  /// PATCH one member through [client], honoring per-field push direction.
  /// Returns true only when a PATCH was actually sent. A stale link (404)
  /// clears the local link and returns false.
  Future<bool> _pushOneMember(
    domain.Member member,
    PluralKitClient client,
    PkPushService push,
    PkSyncDirection globalDirection,
    Map<String, PkFieldSyncConfig> fieldConfigs,
  ) async {
    // Gate the payload by per-field direction. Without a
    // PK snapshot we can't do differs/would-clear gating here (that lives in
    // the bidirectional sync's `_pushableFields`), but we CAN drop fields the
    // user configured pull-only so an unrelated edit never pushes them.
    final config = fieldConfigs[member.id] ?? const PkFieldSyncConfig();
    final allowedFields = _pushAllowedPayloadKeys(config, globalDirection);

    // Every relevant field is pull-only (or sync disabled): nothing to push.
    // Skip without a network call — the gated payload would be `{}`, which PK
    // rejects with 400, and the empty-payload guard in `pushMemberFull` only
    // fires when a `pkMember` snapshot is present (which this path lacks).
    if (allowedFields.isEmpty) return false;

    // Same guard for the empty-VALUES corner: the payload
    // omits null/empty locals on this snapshot-less path, so a member whose
    // allowed fields are all unset (e.g. color toggled OFF on an otherwise
    // empty member) would also produce `{}` -> spurious PK 400.
    final hasAnyPushableValue =
        (allowedFields.contains('display_name') &&
            _hasText(member.pluralkitDisplayName)) ||
        (allowedFields.contains('pronouns') && _hasText(member.pronouns)) ||
        (allowedFields.contains('description') && _hasText(member.bio)) ||
        (allowedFields.contains('birthday') && _hasText(member.birthday)) ||
        (allowedFields.contains('color') &&
            member.customColorEnabled &&
            _hasText(member.customColorHex));
    if (!hasAnyPushableValue) return false;

    try {
      await push.pushMemberFull(
        member,
        client,
        // Proxy-tag removals route through manual sync's delete-risk preview;
        // never include them on the auto-push PATCH.
        includeProxyTags: false,
        allowedFields: allowedFields,
      );
      return true;
    } on PkStaleLinkException {
      try {
        await _memberRepository.updateMember(
          member.copyWith(pluralkitId: null, pluralkitUuid: null),
        );
      } catch (_) {}
      return false;
    }
  }

  /// The PK payload keys a member-edit auto-push MAY carry given [config] and
  /// the overall [direction]. Matches `PkBidirectionalService._pushField`'s
  /// direction semantics; keys MUST match `PkPushService._memberToPayload`.
  /// `proxy_tags` is omitted — this path always passes
  /// `includeProxyTags: false` (destructive tag changes go through manual
  /// sync's delete-risk preview).
  Set<String> _pushAllowedPayloadKeys(
    PkFieldSyncConfig config,
    PkSyncDirection direction,
  ) {
    bool pushField(PkSyncDirection field) {
      if (direction == PkSyncDirection.pullOnly) return false;
      if (direction == PkSyncDirection.pushOnly) return true;
      if (direction == PkSyncDirection.disabled) return false;
      return field.pushEnabled;
    }

    return <String>{
      if (pushField(config.displayName)) 'display_name',
      if (pushField(config.pronouns)) 'pronouns',
      if (pushField(config.description)) 'description',
      if (pushField(config.birthday)) 'birthday',
      if (pushField(config.color)) 'color',
    };
  }

  /// Lightweight poll: GET /systems/@me/fronters and pull only the current
  /// fronter snapshot when the current PK switch id isn't already stored on any
  /// local session. Designed for periodic foreground polling — honors rate
  /// limits via the client's request queue and no-ops when auto-sync isn't
  /// ready.
  ///
  /// Returns a classified [PkPollOutcome]. Previously this
  /// returned a bare bool and swallowed EVERY exception, so a revoked token
  /// (401) or a rate-limit (429) were indistinguishable from "nothing new" and
  /// the auto-poll loop logged a healthy `ok` forever. Now auth/429/transient
  /// failures are surfaced as distinct outcomes the caller can route to its
  /// existing auth-log / 429-backoff behaviors; benign no-ops are `skipped` and
  /// a successful pull (or a successful "nothing new") is `ok`. We still do NOT
  /// throw and do NOT auto-clear the token here — classification only.
  Future<PkPollOutcome> pollFrontersOnly() async {
    if (!_state.canAutoSync) return PkPollOutcome.skipped;
    // The poll used to CHECK `isSyncing` but
    // never CLAIM anything, so a poll that passed the check could still be
    // mid-flight (its own awaits: client build, fronters GET, session reads)
    // when an incremental sweep started — two interleaved sweeps holding
    // independent in-memory active maps, re-closing the same rows at different
    // timestamps. Claim the shared pull gate synchronously; a busy poll is a
    // benign `skipped` tick, identical to the old early-return contract.
    if (!_claimPull()) return PkPollOutcome.skipped;
    // Release-and-classify around the build await so a throw out
    // of the token read cannot leak the pull gate (see _performFullImport).
    // The poll's contract is never-throw, so a build failure is a transient
    // outcome rather than a rethrow.
    final PluralKitClient? client;
    try {
      client = await _buildClient();
    } catch (e) {
      _releasePull();
      debugPrint('[PK] pollFrontersOnly client build failed: $e');
      return PkPollOutcome.transientError;
    }
    if (client == null) {
      _releasePull();
      return PkPollOutcome.skipped;
    }

    try {
      final PKSwitch? current = await client.getCurrentFronters();
      if (current == null) return PkPollOutcome.skipped;

      // If we've already ingested this switch, skip the heavier path. Include
      // user tombstones: deleting the current PK-backed row is intentional
      // local state, not evidence that the PK switch is new.
      final currentSwitchId = current.id.trim();
      final sessions = await _frontingSessionRepository.getAllSessions();
      final seenLive = sessions.any(
        (s) => s.pluralkitUuid?.trim() == currentSwitchId,
      );
      if (seenLive) return PkPollOutcome.skipped;

      final deletedLinked = await _frontingSessionRepository
          .getDeletedLinkedSessions();
      final seenDeleted = deletedLinked.any(
        (s) => s.pluralkitUuid?.trim() == currentSwitchId,
      );
      if (seenDeleted) return PkPollOutcome.skipped;

      final pull = await _pullLiveFronterSwitch(current);
      final unmappedCount = pull.unmappedNotice?.refs.length ?? 0;
      if (unmappedCount > 0) {
        debugPrint(
          '[PK] pollFrontersOnly skipped current switch with '
          '$unmappedCount unmapped current '
          '${unmappedCount == 1 ? 'fronter' : 'fronters'}.',
        );
      }
      // Both a fresh pull and a "nothing new" are healthy: the loop should keep
      // its configured cadence and report `ok`.
      return PkPollOutcome.ok;
    } on PluralKitAuthError catch (e) {
      // 401 — token revoked/invalid. Surface as a distinct outcome so the loop
      // stops claiming health. Do NOT auto-clear (the user must re-link).
      debugPrint('[PK] pollFrontersOnly auth failure (token rejected): $e');
      return PkPollOutcome.authFailed;
    } on PluralKitRateLimitError catch (e) {
      debugPrint('[PK] pollFrontersOnly rate-limited: $e');
      return PkPollOutcome.rateLimited;
    } catch (e) {
      debugPrint('[PK] pollFrontersOnly failed: $e');
      return PkPollOutcome.transientError;
    } finally {
      client.dispose();
      _releasePull();
    }
  }
}
