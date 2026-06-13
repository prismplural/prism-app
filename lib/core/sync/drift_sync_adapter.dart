import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/pk_alias_guards.dart';
import 'package:prism_plurality/core/sync/pk_incarnation_ids.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart'
    show sanitizeSortStateForEmission, tryDecodeSortState;
import 'package:prism_plurality/domain/preferences/preference_entity_id.dart';

/// Applies remote CRDT changes from the Rust sync engine to the local Drift DB.
///
/// Type mismatches from newer schema versions are handled gracefully (null-coerced
/// via _asString/_asInt/_asBool helpers, anomalies quarantined) rather than
/// failing the sync cycle. If you add a new synced entity, add a corresponding
/// _fooEntity() builder below and register it in buildSyncAdapterWithCompletion.
///
/// Wraps [DriftSyncAdapter] with a [Completer]-based batch completion signal
/// so callers can await the end of a remote-change batch instead of relying
/// on a hardcoded delay.
class SyncAdapterWithCompletion {
  SyncAdapterWithCompletion(
    this.adapter,
    this._pendingQuarantineWrites,
    this._deferredPkEntryReplay,
  );

  final DriftSyncAdapter adapter;
  final List<Future<void>> _pendingQuarantineWrites;
  final DeferredPkEntryReplayController _deferredPkEntryReplay;

  Completer<void>? _batchCompleter;

  /// Call before starting a sync to create a new completion signal.
  void beginSyncBatch() {
    _batchCompleter = Completer<void>();
    _deferredPkEntryReplay.beginBatch();
  }

  /// Completes when all pending writes from the current batch are committed.
  Future<void> get syncBatchComplete =>
      _batchCompleter?.future ?? Future.value();

  /// Resolve once tracked quarantine writes for the current batch finish.
  Future<void> completeSyncBatch() async {
    final completer = _batchCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }

    final pendingWrites = List<Future<void>>.from(_pendingQuarantineWrites);
    _pendingQuarantineWrites.clear();

    for (final write in pendingWrites) {
      try {
        await write;
      } catch (_) {
        // Quarantine is diagnostic-only; sync application already succeeded.
      }
    }

    await _deferredPkEntryReplay.completeBatch();

    if (!completer.isCompleted) {
      completer.complete();
    }
    _batchCompleter = null;
  }
}

class DeferredPkEntryReplayController {
  DeferredPkEntryReplayController(this._run);

  final Future<void> Function() _run;
  bool _batchActive = false;

  void beginBatch() {
    _batchActive = true;
  }

  Future<void> requestReplay() {
    if (_batchActive) {
      return Future.value();
    }
    return _run();
  }

  Future<void> completeBatch() async {
    try {
      await _run();
    } finally {
      _batchActive = false;
    }
  }
}

/// Reasons the adapter may refuse to apply a remote payload to a local
/// row. Callers can match on these values at logging or telemetry sites
/// without inspecting magic strings.
enum DriftSyncApplyRefusal {
  /// Per-member fronting migration is blocked or in-progress; the
  /// fronting tables are in a transitional shape and apply for
  /// `fronting_sessions` / `front_session_comments` is hard read-only.
  frontingMigrationGate,
}

/// Predicate used by per-table apply paths to gate writes. Returning
/// `null` means "apply normally"; returning a non-null reason short-
/// circuits the apply call and causes the engine to leave the local
/// row untouched.
///
/// The predicate is synchronous because it's read on every apply call;
/// today the only consumer is the fronting migration gate, which
/// resolves a Riverpod-backed boolean stamped at startup and updated by
/// the Drift settings stream. Make this async only if a future gate
/// truly needs an awaited check.
typedef DriftSyncApplyGate = DriftSyncApplyRefusal? Function(String tableName);

/// Records a "this remote payload was deferred because the per-member
/// fronting migration is blocked/inProgress" entry in the quarantine
/// table. The user can see deferred apply attempts in sync diagnostics
/// rather than the data silently disappearing.
///
/// Returns immediately when [quarantine] is null (most production code
/// paths supply one; some tests don't).
void _trackMigrationGatedQuarantine({
  required SyncQuarantineService? quarantine,
  required void Function(Future<void> write) trackQuarantineWrite,
  required String tableName,
  required String entityId,
  required DriftSyncApplyRefusal refusal,
}) {
  final q = quarantine;
  if (q == null) return;
  final write = q.quarantineField(
    entityType: tableName,
    entityId: entityId,
    fieldName: null,
    expectedType: 'apply',
    receivedType: 'deferred',
    errorMessage:
        'fronting migration gate (${refusal.name}): apply deferred '
        'until the per-member fronting migration completes',
  );
  trackQuarantineWrite(write);
}

void _trackInvalidFrontSessionCommentSessionId({
  required SyncQuarantineService? quarantine,
  required void Function(Future<void> write) trackQuarantineWrite,
  required String entityId,
  required Map<String, dynamic> fields,
  required bool missing,
}) {
  final q = quarantine;
  if (q == null) return;
  final raw = fields['session_id'];
  final write = q.quarantineField(
    entityType: 'front_session_comments',
    entityId: entityId,
    fieldName: 'session_id',
    expectedType: 'non-empty String',
    receivedType: missing ? 'missing' : raw?.runtimeType.toString() ?? 'null',
    receivedValue: raw?.toString(),
    errorMessage: missing
        ? 'Missing required session_id for front session comment'
        : 'Blank session_id is not a valid front session comment parent',
  );
  trackQuarantineWrite(write);
}

SyncAdapterWithCompletion buildSyncAdapterWithCompletion(
  AppDatabase db, {
  SyncQuarantineService? quarantine,
  DriftSyncApplyGate? applyGate,
}) {
  final pendingQuarantineWrites = <Future<void>>[];
  final gate = applyGate ?? ((_) => null);
  late final DeferredPkEntryReplayController deferredPkEntryReplay;
  deferredPkEntryReplay = DeferredPkEntryReplayController(
    () => _retryDeferredPkBackedMemberGroupEntryOps(
      db,
      quarantine: quarantine,
      trackQuarantineWrite: pendingQuarantineWrites.add,
    ),
  );
  final adapter = DriftSyncAdapter(
    entities: [
      _membersEntity(
        db,
        quarantine,
        pendingQuarantineWrites.add,
        deferredPkEntryReplay.requestReplay,
      ),
      _frontingSessionsEntity(
        db,
        quarantine,
        pendingQuarantineWrites.add,
        gate,
      ),
      _conversationsEntity(db, quarantine, pendingQuarantineWrites.add),
      _chatMessagesEntity(db, quarantine, pendingQuarantineWrites.add),
      _systemSettingsEntity(db, quarantine, pendingQuarantineWrites.add),
      _appPreferenceValuesEntity(db, quarantine, pendingQuarantineWrites.add),
      _memberProfilePreferenceValuesEntity(
        db,
        quarantine,
        pendingQuarantineWrites.add,
      ),
      _pollsEntity(db, quarantine, pendingQuarantineWrites.add),
      _pollOptionsEntity(db, quarantine, pendingQuarantineWrites.add),
      _pollVotesEntity(db, quarantine, pendingQuarantineWrites.add),
      _habitsEntity(db, quarantine, pendingQuarantineWrites.add),
      _habitCompletionsEntity(db, quarantine, pendingQuarantineWrites.add),
      _conversationCategoriesEntity(
        db,
        quarantine,
        pendingQuarantineWrites.add,
      ),
      _remindersEntity(db, quarantine, pendingQuarantineWrites.add),
      _memberGroupsEntity(
        db,
        quarantine,
        pendingQuarantineWrites.add,
        deferredPkEntryReplay.requestReplay,
      ),
      _memberGroupEntriesEntity(db, quarantine, pendingQuarantineWrites.add),
      _customFieldsEntity(db, quarantine, pendingQuarantineWrites.add),
      _customFieldValuesEntity(db, quarantine, pendingQuarantineWrites.add),
      _notesEntity(db, quarantine, pendingQuarantineWrites.add),
      _frontSessionCommentsEntity(
        db,
        quarantine,
        pendingQuarantineWrites.add,
        gate,
      ),
      _friendsEntity(db, quarantine, pendingQuarantineWrites.add),
      _mediaAttachmentsEntity(db, quarantine, pendingQuarantineWrites.add),
      _memberBoardPostsEntity(db, quarantine, pendingQuarantineWrites.add),
    ],
  );
  return SyncAdapterWithCompletion(
    adapter,
    pendingQuarantineWrites,
    deferredPkEntryReplay,
  );
}

// ---------------------------------------------------------------------------
// Safe type-cast helpers
// ---------------------------------------------------------------------------
// Remote changes may have unexpected types if a peer runs a newer app version
// with different schema, or if data was corrupted. Strategy: return null on
// mismatch so the field is skipped (Value.absent()), not the whole entity.
// Never throw — let the sync cycle continue.

String? _asString(dynamic value) => value is String ? value : null;

// Age-only coercion. `age` migrated from Int → String (schema v31); an old
// client still emits a bare integer on the wire. Accept that numeric form and
// stringify it so old→new sync preserves numeric ages. Scoped to the age
// decode site ONLY — `_asString` stays strict for the ~133 other string
// fields, which must still quarantine non-string payloads. NaN/Infinity are
// rejected (return null) so they surface as a type mismatch rather than the
// literal strings "NaN"/"Infinity".
String? _asAgeString(dynamic value) {
  if (value is String) return value;
  if (value is num && !value.isNaN && value.isFinite) return value.toString();
  return null;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  // `double.toInt()` throws `UnsupportedError` for NaN/Infinity. The
  // wire format can carry those (see `_asDouble`) — reject them here so
  // a misencoded Int field surfaces as a quarantined type mismatch
  // instead of aborting the whole strict-apply batch.
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _asBool(dynamic value) => value is bool ? value : null;

double? _asDouble(dynamic value) {
  // Drift writes non-finite doubles (NaN, +/-Infinity) into a NOT NULL Real
  // column by coercing them to NULL at the SQLite layer — which then trips
  // the column's NOT NULL constraint and aborts strict-apply pairing for
  // the whole row. Reject non-finite here so the column falls back to its
  // declared default instead.
  if (value is double) return value.isFinite ? value : null;
  if (value is int) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }
  return null;
}

DateTime? _asDateTime(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Serializes a [DateTime] for inclusion in a sync field map.
///
/// Drift reads `DateTime` columns with `isUtc=false` (local time). Calling
/// `toIso8601String()` on a local DateTime emits a string with no offset and
/// no `Z` suffix, e.g. `"2024-01-01T12:00:00.000"`. A peer in a different
/// timezone parses that as their own local time, so the absolute moment
/// shifts by the timezone delta on every cross-device sync.
///
/// Funnel every DateTime emission to the sync layer through this helper so
/// the wire format is unambiguously UTC (`Z`-suffixed) and round-trips
/// across timezones cleanly. Reviewers grepping for `.toIso8601String()` in
/// `drift_sync_adapter.dart` should find only this helper.
String _dateTimeToSyncString(DateTime dt) => dt.toUtc().toIso8601String();

/// Nullable variant of [_dateTimeToSyncString].
String? _dateTimeToSyncStringOrNull(DateTime? dt) =>
    dt?.toUtc().toIso8601String();

/// Nullable blob from base64 string.
Uint8List? _blob(dynamic v) {
  if (v is String) {
    try {
      return base64Decode(v);
    } catch (_) {
      return null;
    }
  }
  return null;
}

const String _pkGroupSyncEntityIdPrefix = 'pk-group:';
const String _pkGroupSyncAliasesTableName = 'pk_group_sync_aliases';
const String _pkGroupEntryDeferredOpsTableName =
    'pk_group_entry_deferred_sync_ops';
const int _maxDeferredPkEntryReplayRetries = 10;
// Retry count is driven by sync batch completions, which can happen in a
// burst before the matching PK member/group op arrives. Require real elapsed
// time too before turning a recoverable deferred edge into a user-visible issue.
const Duration _deferredPkEntryReplayTerminalGrace = Duration(minutes: 10);

final Expando<Map<String, Set<String>>> _tableColumnsCache = Expando();
final Expando<Map<String, bool>> _tableExistsCache = Expando();

class _OptionalDynamicValue<T> {
  const _OptionalDynamicValue._({required this.present, this.value});
  const _OptionalDynamicValue.absent() : this._(present: false);
  const _OptionalDynamicValue.present(T? value)
    : this._(present: true, value: value);

  final bool present;
  final T? value;
}

class _PkGroupAliasResolution {
  const _PkGroupAliasResolution({
    required this.pkGroupUuid,
    required this.canonicalEntityId,
  });

  final String pkGroupUuid;
  final String canonicalEntityId;
}

class _PkMemberGroupEntryLogicalEdge {
  const _PkMemberGroupEntryLogicalEdge({
    required this.pkGroupUuid,
    required this.pkMemberUuid,
  });

  final String pkGroupUuid;
  final String pkMemberUuid;

  String get key => '$pkGroupUuid\u0000$pkMemberUuid';
}

class _PreferredDeferredPkEntryOp {
  const _PreferredDeferredPkEntryOp({
    required this.deferredId,
    required this.isCanonical,
  });

  final String deferredId;
  final bool isCanonical;
}

String _canonicalPkGroupEntityId(String pkGroupUuid) =>
    '$_pkGroupSyncEntityIdPrefix$pkGroupUuid';

/// Recover the pk group uuid from EITHER the bare canonical prefix
/// (`pk-group:<uuid>`) or a group incarnation id (`pk-group-g<N>:<uuid>`).
/// [parseGroupIncarnationEntityId] handles both forms; the resolve-for-id and
/// resolve-for-delete paths use this so a gen-N tombstone or sparse patch that
/// arrives before its create/alias still resolves to the real row by pk uuid
/// instead of inserting a stub keyed by the wire id.
String? _pkGroupUuidFromAnyEntityId(String entityId) =>
    parseGroupIncarnationEntityId(entityId)?.pkGroupUuid;

_OptionalDynamicValue<String?> _readOptionalStringProperty(
  dynamic Function() getter,
) {
  try {
    final value = getter();
    return _OptionalDynamicValue<String?>.present(value as String?);
  } catch (_) {
    return const _OptionalDynamicValue<String?>.absent();
  }
}

Future<bool> _tableExists(AppDatabase db, String tableName) async {
  final cache = _tableExistsCache[db] ??= <String, bool>{};
  final cached = cache[tableName];
  if (cached != null) return cached;

  final rows = await db
      .customSelect(
        '''
        SELECT 1 AS present
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        LIMIT 1
        ''',
        variables: [Variable<String>(tableName)],
      )
      .get();
  final exists = rows.isNotEmpty;
  cache[tableName] = exists;
  return exists;
}

Future<Set<String>> _tableColumns(AppDatabase db, String tableName) async {
  final cache = _tableColumnsCache[db] ??= <String, Set<String>>{};
  final cached = cache[tableName];
  if (cached != null) return cached;

  if (!await _tableExists(db, tableName)) {
    const empty = <String>{};
    cache[tableName] = empty;
    return empty;
  }

  final rows = await db.customSelect('PRAGMA table_info($tableName)').get();
  final columns = rows
      .map((row) => row.data['name'])
      .whereType<String>()
      .toSet();
  cache[tableName] = columns;
  return columns;
}

Future<bool> _tableHasColumn(
  AppDatabase db,
  String tableName,
  String columnName,
) async => (await _tableColumns(db, tableName)).contains(columnName);

Future<void> _insertOrUpdateById<T extends Table, D>(
  AppDatabase db,
  TableInfo<T, D> table,
  Insertable<D> companion,
  Expression<bool> Function(T table) matchesId,
) async {
  final existing = await (db.select(table)..where(matchesId)).getSingleOrNull();
  if (existing == null) {
    await db.into(table).insertOnConflictUpdate(companion);
    return;
  }

  await (db.update(table)..where(matchesId)).write(companion);
}

Future<void> _insertOrUpdateCustomFieldValueForApply(
  AppDatabase db,
  String id,
  CustomFieldValuesCompanion companion,
  Map<String, dynamic> fields,
) async {
  final customFieldId = _asString(fields['custom_field_id']);
  final memberId = _asString(fields['member_id']);
  var targetId = id;
  CustomFieldValueRow? existingLogical;
  if (customFieldId != null && memberId != null) {
    final deterministicId = deriveCustomFieldValueId(
      customFieldId: customFieldId,
      memberId: memberId,
    );
    existingLogical =
        await (db.select(db.customFieldValues)..where(
              (t) =>
                  t.customFieldId.equals(customFieldId) &
                  t.memberId.equals(memberId) &
                  t.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (existingLogical != null) {
      targetId = id == deterministicId || existingLogical.id == deterministicId
          ? deterministicId
          : existingLogical.id;
    }
  }
  final targetCompanion = targetId == id
      ? companion
      : companion.copyWith(id: Value(targetId));

  final existingByTarget = await (db.select(
    db.customFieldValues,
  )..where((t) => t.id.equals(targetId))).getSingleOrNull();
  if (existingLogical != null && existingLogical.id != targetId) {
    if (existingByTarget != null) {
      await (db.update(db.customFieldValues)
            ..where((t) => t.id.equals(existingLogical!.id)))
          .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));
      await (db.update(
        db.customFieldValues,
      )..where((t) => t.id.equals(targetId))).write(targetCompanion);
    } else {
      await (db.update(
        db.customFieldValues,
      )..where((t) => t.id.equals(existingLogical!.id))).write(targetCompanion);
    }
    return;
  }

  if (existingByTarget != null) {
    await (db.update(
      db.customFieldValues,
    )..where((t) => t.id.equals(targetId))).write(targetCompanion);
    return;
  }

  await db.into(db.customFieldValues).insertOnConflictUpdate(targetCompanion);
}

Future<void> _insertOrUpdateMemberProfilePreferenceValueForApply(
  AppDatabase db,
  String id,
  MemberProfilePreferenceValuesCompanion companion,
  Map<String, dynamic> fields,
) async {
  final memberId = _asString(fields['member_id']);
  final key = _asString(fields['key']);
  var targetId = id;
  MemberProfilePreferenceValueRow? existingLogical;
  if (memberId != null && key != null) {
    final deterministicId = isValidPreferenceKey(key)
        ? PreferenceEntityId.memberProfile(memberId, key)
        : null;
    existingLogical =
        await (db.select(db.memberProfilePreferenceValues)
              ..where((t) => t.memberId.equals(memberId) & t.key.equals(key)))
            .getSingleOrNull();
    if (existingLogical != null) {
      if (existingLogical.id == id) {
        targetId = id;
      } else if (deterministicId != null &&
          existingLogical.id == deterministicId) {
        targetId = deterministicId;
      } else if (deterministicId != null && id == deterministicId) {
        final existingDeterministic = await (db.select(
          db.memberProfilePreferenceValues,
        )..where((t) => t.id.equals(deterministicId))).getSingleOrNull();
        targetId =
            existingDeterministic == null ||
                existingDeterministic.id == existingLogical.id
            ? deterministicId
            : existingLogical.id;
      } else {
        targetId = existingLogical.id;
      }
    }
  }
  final targetCompanion = targetId == id
      ? companion
      : companion.copyWith(id: Value(targetId));

  final existingByTarget = await (db.select(
    db.memberProfilePreferenceValues,
  )..where((t) => t.id.equals(targetId))).getSingleOrNull();
  if (existingByTarget != null) {
    await (db.update(
      db.memberProfilePreferenceValues,
    )..where((t) => t.id.equals(targetId))).write(targetCompanion);
    return;
  }

  if (existingLogical != null) {
    await (db.update(
      db.memberProfilePreferenceValues,
    )..where((t) => t.id.equals(existingLogical!.id))).write(targetCompanion);
    return;
  }

  await db
      .into(db.memberProfilePreferenceValues)
      .insertOnConflictUpdate(targetCompanion);
}

/// Sync-inbound normalization for a `custom_fields.parent_field_id` value.
///
/// Returns [Value.absent] when [rawParent] is also absent so an existing
/// row's column is left untouched. Returns [Value]`(null)` when the
/// inbound parent reference is invalid (self-cycle or depth-2 nesting)
/// so a buggy or malicious peer can't plant grandchildren or cycles
/// into local storage and re-emit them to other peers via per-field
/// LWW. Otherwise passes the raw value through verbatim — including
/// missing-parent and non-group-parent references, which sync apply
/// ordering may resolve later and which render-time promotion
/// (`lib/features/custom_fields/orphan_promotion.dart`) handles
/// gracefully in the meantime.
Future<Value<String?>> _normalizeCustomFieldParentForApply(
  AppDatabase db, {
  required String childId,
  required Value<String?> rawParent,
}) async {
  if (!rawParent.present) return rawParent;
  final parentId = rawParent.value;
  if (parentId == null) return rawParent;
  // Self-cycle: a peer asserting parent == self_id would otherwise
  // render as the field's own child. Always normalize to null.
  if (parentId == childId) return const Value(null);
  // Depth-2: parent has its own non-null parent_field_id on disk. The
  // write-side `moveFieldToParent` rejects this with
  // DepthLimitExceededException; sync apply mirrors that here.
  final parentRow = await (db.select(
    db.customFields,
  )..where((t) => t.id.equals(parentId))).getSingleOrNull();
  if (parentRow != null && parentRow.parentFieldId != null) {
    return const Value(null);
  }
  return rawParent;
}

bool _isRemoteTombstone(Map<String, dynamic> fields) =>
    _asBool(fields['is_deleted']) == true;

Future<void> _releaseDeletedPkIdentityHoldersForMemberApply(
  AppDatabase db, {
  required String incomingId,
  required String? pkUuid,
  required String? pkId,
}) async {
  final normalizedPkUuid = _nonEmptySyncString(pkUuid);
  final normalizedPkId = _nonEmptySyncString(pkId);
  if (normalizedPkUuid == null && normalizedPkId == null) return;

  await (db.update(db.members)..where((t) {
        final matchingUuid = normalizedPkUuid == null
            ? const Constant<bool>(false)
            : t.pluralkitUuid.equals(normalizedPkUuid);
        final matchingId = normalizedPkId == null
            ? const Constant<bool>(false)
            : t.pluralkitId.equals(normalizedPkId);

        return t.id.equals(incomingId).not() &
            t.isDeleted.equals(true) &
            (matchingUuid | matchingId);
      }))
      .write(
        const MembersCompanion(
          pluralkitUuid: Value(null),
          pluralkitId: Value(null),
        ),
      );
}

Future<bool> _memberPkIdentityHeldByOtherRow(
  AppDatabase db, {
  required String incomingId,
  required String? pkUuid,
  required String? pkId,
}) async {
  final normalizedPkUuid = _nonEmptySyncString(pkUuid);
  final normalizedPkId = _nonEmptySyncString(pkId);
  if (normalizedPkUuid == null && normalizedPkId == null) return false;

  final row =
      await (db.select(db.members)
            ..where((t) {
              final matchingUuid = normalizedPkUuid == null
                  ? const Constant<bool>(false)
                  : t.pluralkitUuid.equals(normalizedPkUuid);
              final matchingId = normalizedPkId == null
                  ? const Constant<bool>(false)
                  : t.pluralkitId.equals(normalizedPkId);

              return t.id.equals(incomingId).not() &
                  (matchingUuid | matchingId);
            })
            ..limit(1))
          .getSingleOrNull();
  return row != null;
}

Future<List<Member>> _activeMemberRowsByPkIdentityForApply(
  AppDatabase db, {
  required String? pkUuid,
  required String? pkId,
}) async {
  final normalizedPkUuid = _nonEmptySyncString(pkUuid);
  final normalizedPkId = _nonEmptySyncString(pkId);
  if (normalizedPkUuid == null && normalizedPkId == null) {
    return const <Member>[];
  }

  final rows =
      await (db.select(db.members)..where((t) {
            final matchingUuid = normalizedPkUuid == null
                ? const Constant<bool>(false)
                : t.pluralkitUuid.equals(normalizedPkUuid);
            final matchingId = normalizedPkId == null
                ? const Constant<bool>(false)
                : t.pluralkitId.equals(normalizedPkId);

            return t.isDeleted.equals(false) & (matchingUuid | matchingId);
          }))
          .get();

  int matchScore(Member row) {
    if (normalizedPkUuid != null && row.pluralkitUuid == normalizedPkUuid) {
      return 0;
    }
    if (normalizedPkId != null && row.pluralkitId == normalizedPkId) {
      return 1;
    }
    return 2;
  }

  rows.sort((left, right) {
    final scoreCompare = matchScore(left).compareTo(matchScore(right));
    if (scoreCompare != 0) return scoreCompare;

    final createdCompare = left.createdAt.compareTo(right.createdAt);
    if (createdCompare != 0) return createdCompare;

    return left.id.compareTo(right.id);
  });
  return rows;
}

Future<void> _releaseDeletedPkIdentityHoldersForFrontingSessionApply(
  AppDatabase db, {
  required String incomingId,
  required String? pkUuid,
  required String? memberId,
}) async {
  final normalizedPkUuid = _nonEmptySyncString(pkUuid);
  if (normalizedPkUuid == null) return;

  await (db.update(db.frontingSessions)..where((t) {
        final matchingMember = memberId == null
            ? t.memberId.isNull()
            : t.memberId.equals(memberId);
        return t.id.equals(incomingId).not() &
            t.isDeleted.equals(true) &
            t.pluralkitUuid.equals(normalizedPkUuid) &
            matchingMember;
      }))
      .write(const FrontingSessionsCompanion(pluralkitUuid: Value(null)));
}

Future<List<FrontingSession>> _activeFrontingSessionRowsByPkIdentityForApply(
  AppDatabase db, {
  required String? pkUuid,
  required String? memberId,
}) async {
  final normalizedPkUuid = _nonEmptySyncString(pkUuid);
  if (normalizedPkUuid == null) return const <FrontingSession>[];

  final rows =
      await (db.select(db.frontingSessions)..where((t) {
            final matchingMember = memberId == null
                ? t.memberId.isNull()
                : t.memberId.equals(memberId);
            return t.isDeleted.equals(false) &
                t.pluralkitUuid.equals(normalizedPkUuid) &
                matchingMember;
          }))
          .get();

  rows.sort((left, right) {
    final startCompare = left.startTime.compareTo(right.startTime);
    if (startCompare != 0) return startCompare;

    return left.id.compareTo(right.id);
  });
  return rows;
}

String? _nonEmptySyncString(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Future<MemberGroupRow?> _memberGroupRowById(AppDatabase db, String id) {
  return (db.select(
    db.memberGroups,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
}

Future<MemberGroupRow?> _memberGroupRowByPkGroupUuid(
  AppDatabase db,
  String pkGroupUuid, {
  Iterable<String> preferredLocalRowIds = const <String>[],
}) async {
  final rows = await (db.select(
    db.memberGroups,
  )..where((t) => t.pluralkitUuid.equals(pkGroupUuid))).get();
  if (rows.isEmpty) return null;

  final preferredIds = preferredLocalRowIds
      .where((id) => id.isNotEmpty)
      .toSet();
  final sorted = [...rows]
    ..sort((left, right) {
      if (left.isDeleted != right.isDeleted) {
        return left.isDeleted ? 1 : -1;
      }

      final leftPreferred = preferredIds.contains(left.id);
      final rightPreferred = preferredIds.contains(right.id);
      if (leftPreferred != rightPreferred) {
        return leftPreferred ? -1 : 1;
      }

      if (left.syncSuppressed != right.syncSuppressed) {
        return left.syncSuppressed ? 1 : -1;
      }

      if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt == null) {
        return -1;
      }
      if (left.lastSeenFromPkAt == null && right.lastSeenFromPkAt != null) {
        return 1;
      }
      if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt != null) {
        final seenCompare = right.lastSeenFromPkAt!.compareTo(
          left.lastSeenFromPkAt!,
        );
        if (seenCompare != 0) return seenCompare;
      }

      final createdCompare = left.createdAt.compareTo(right.createdAt);
      if (createdCompare != 0) return createdCompare;

      return left.id.compareTo(right.id);
    });

  return sorted.first;
}

Future<_PkGroupAliasResolution?> _pkGroupAliasForLegacyEntityId(
  AppDatabase db,
  String legacyEntityId,
) async {
  if (!await _tableExists(db, _pkGroupSyncAliasesTableName)) {
    return null;
  }

  final row = await db
      .customSelect(
        '''
        SELECT pk_group_uuid, canonical_entity_id
        FROM $_pkGroupSyncAliasesTableName
        WHERE legacy_entity_id = ?
        LIMIT 1
        ''',
        variables: [Variable<String>(legacyEntityId)],
      )
      .getSingleOrNull();
  if (row == null) return null;

  final pkGroupUuid = _asString(row.data['pk_group_uuid']);
  final canonicalEntityId = _asString(row.data['canonical_entity_id']);
  if (pkGroupUuid == null || canonicalEntityId == null) {
    return null;
  }

  return _PkGroupAliasResolution(
    pkGroupUuid: pkGroupUuid,
    canonicalEntityId: canonicalEntityId,
  );
}

Future<MemberGroupRow?> _resolveMemberGroupRowForSyncId(
  AppDatabase db,
  String entityId, {
  String? payloadPkGroupUuid,
}) async {
  _PkGroupAliasResolution? alias;
  if (payloadPkGroupUuid == null &&
      _pkGroupUuidFromAnyEntityId(entityId) == null) {
    alias = await _pkGroupAliasForLegacyEntityId(db, entityId);
  }

  final pkGroupUuid =
      payloadPkGroupUuid ??
      _pkGroupUuidFromAnyEntityId(entityId) ??
      alias?.pkGroupUuid;
  if (pkGroupUuid != null) {
    final byPkUuid = await _memberGroupRowByPkGroupUuid(
      db,
      pkGroupUuid,
      preferredLocalRowIds: {
        entityId,
        if (alias != null) alias.canonicalEntityId,
      },
    );
    if (byPkUuid != null) return byPkUuid;

    final byCanonicalId = await _memberGroupRowById(
      db,
      alias?.canonicalEntityId ?? _canonicalPkGroupEntityId(pkGroupUuid),
    );
    if (byCanonicalId != null) return byCanonicalId;
  }

  return _memberGroupRowById(db, entityId);
}

Future<MemberGroupRow?> _resolveMemberGroupRowForSyncDelete(
  AppDatabase db,
  String entityId,
) async {
  // Incarnation-aware: a gen-N group tombstone (`pk-group-g<N>:<uuid>`) resolves
  // to the live row by pk uuid even though the row is keyed by its own local id,
  // so the hardDelete's generation guard can compare stored vs incoming gen and
  // find the row to delete. The bare canonical id resolves the same way.
  if (_pkGroupUuidFromAnyEntityId(entityId) != null) {
    return _resolveMemberGroupRowForSyncId(db, entityId);
  }

  // Non-canonical (legacy-form) entity id. Resolve to the exact-id row only.
  final row = await _memberGroupRowById(db, entityId);
  if (row == null) return null;

  // Receive-side hardening: a legacy-id delete arriving at an ACTIVE PK-linked
  // row is always a stale-alias kill, never a genuine delete. Genuine deletes of
  // PK-linked groups always travel under the canonical 'pk-group:<uuid>' id
  // (handled above) — deleteGroup captures the uuid and computes the
  // canonical/incarnation entity id BEFORE the DAO NULLs pluralkit_uuid. So skip
  // the delete here, including poison from un-upgraded peers (the Rust store
  // still records the legacy-id tombstone, harmless: logical PK-group state lives
  // under the canonical id).
  if (!row.isDeleted && (row.pluralkitUuid?.isNotEmpty ?? false)) {
    return null;
  }

  return row;
}

Future<String?> _resolveLocalMemberIdByPkUuid(
  AppDatabase db,
  String pkMemberUuid,
) async {
  final row = await (db.select(
    db.members,
  )..where((t) => t.pluralkitUuid.equals(pkMemberUuid))).getSingleOrNull();
  return row?.id;
}

_PkMemberGroupEntryLogicalEdge? _pkMemberGroupEntryLogicalEdge({
  required String? pkGroupUuid,
  required String? pkMemberUuid,
}) {
  if (pkGroupUuid == null ||
      pkMemberUuid == null ||
      pkGroupUuid.isEmpty ||
      pkMemberUuid.isEmpty) {
    return null;
  }
  return _PkMemberGroupEntryLogicalEdge(
    pkGroupUuid: pkGroupUuid,
    pkMemberUuid: pkMemberUuid,
  );
}

_PkMemberGroupEntryLogicalEdge? _pkMemberGroupEntryLogicalEdgeFromFields(
  Map<String, dynamic> fields,
) {
  return _pkMemberGroupEntryLogicalEdge(
    pkGroupUuid: _asString(fields['pk_group_uuid']),
    pkMemberUuid: _asString(fields['pk_member_uuid']),
  );
}

_PkMemberGroupEntryLogicalEdge? _pkMemberGroupEntryLogicalEdgeFromFieldsJson(
  String fieldsJson,
) {
  final decoded = _decodeDeferredPkEntryFieldsJson(fieldsJson);
  return decoded == null
      ? null
      : _pkMemberGroupEntryLogicalEdgeFromFields(decoded);
}

Map<String, dynamic>? _decodeDeferredPkEntryFieldsJson(String fieldsJson) {
  try {
    final decoded = jsonDecode(fieldsJson);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return null;
  }
  return null;
}

String _canonicalPkMemberGroupEntryEntityId(
  String pkGroupUuid,
  String pkMemberUuid,
) {
  final digest = sha256.convert(utf8.encode('$pkGroupUuid\u0000$pkMemberUuid'));
  return digest.toString().substring(0, 16);
}

bool _isCanonicalPkMemberGroupEntryEntityId(
  String entityId,
  _PkMemberGroupEntryLogicalEdge edge,
) {
  return entityId ==
      _canonicalPkMemberGroupEntryEntityId(edge.pkGroupUuid, edge.pkMemberUuid);
}

Future<_PkMemberGroupEntryLogicalEdge?> _memberGroupEntryPkEdgeById(
  AppDatabase db,
  String id,
) async {
  final selectColumns = <String>[];
  if (await _tableHasColumn(db, 'member_group_entries', 'pk_group_uuid')) {
    selectColumns.add('pk_group_uuid');
  }
  if (await _tableHasColumn(db, 'member_group_entries', 'pk_member_uuid')) {
    selectColumns.add('pk_member_uuid');
  }
  if (selectColumns.length < 2) return null;

  final row = await db
      .customSelect(
        'SELECT ${selectColumns.join(', ')} '
        'FROM member_group_entries '
        'WHERE id = ?',
        variables: [Variable<String>(id)],
      )
      .getSingleOrNull();
  if (row == null) return null;

  return _pkMemberGroupEntryLogicalEdge(
    pkGroupUuid: _asString(row.data['pk_group_uuid']),
    pkMemberUuid: _asString(row.data['pk_member_uuid']),
  );
}

/// Resolve the `(edge, incomingGeneration)` an incoming entry tombstone [id]
/// addresses, even when NO row sits at that exact id. Entry incarnation ids are
/// opaque shas, so the only way to recover the edge of a gen-N tombstone that
/// has no local row is to reverse-derive: for every distinct PK edge currently
/// in the table, walk its generations and see which one derives to [id]. Used by
/// the entry hardDelete so a legitimate gen-N delete resolves the live row of
/// that edge even when it collapsed onto an older-keyed Drift PK (the canonical
/// gen-0 sha carrying sync_generation=N). Falls back to the exact-id row's edge
/// (gen-0 self-match) when no reverse-derivation hits. Returns null for non-PK
/// or unresolvable ids.
Future<_PkEntryTombstoneTarget?> _resolveEntryTombstoneTarget(
  AppDatabase db,
  String id,
) async {
  if (!await _tableHasColumn(db, 'member_group_entries', 'pk_group_uuid') ||
      !await _tableHasColumn(db, 'member_group_entries', 'pk_member_uuid')) {
    return null;
  }

  // Exact-id row first: covers the common case (a tombstone keyed by the same
  // id as a live or soft-deleted row) without a table scan.
  final exact = await _memberGroupEntryPkEdgeById(db, id);
  if (exact != null) {
    final gen =
        parseEntryIncarnationGeneration(
          id,
          pkGroupUuid: exact.pkGroupUuid,
          pkMemberUuid: exact.pkMemberUuid,
        ) ??
        0;
    return _PkEntryTombstoneTarget(edge: exact, incomingGeneration: gen);
  }

  // Collapse case: no row at this id. Reverse-derive across the table's edges.
  final rows = await db
      .customSelect(
        'SELECT DISTINCT pk_group_uuid, pk_member_uuid '
        'FROM member_group_entries '
        'WHERE pk_group_uuid IS NOT NULL AND pk_group_uuid != \'\' '
        'AND pk_member_uuid IS NOT NULL AND pk_member_uuid != \'\'',
      )
      .get();
  for (final row in rows) {
    final edge = _pkMemberGroupEntryLogicalEdge(
      pkGroupUuid: _asString(row.data['pk_group_uuid']),
      pkMemberUuid: _asString(row.data['pk_member_uuid']),
    );
    if (edge == null) continue;
    final gen = parseEntryIncarnationGeneration(
      id,
      pkGroupUuid: edge.pkGroupUuid,
      pkMemberUuid: edge.pkMemberUuid,
    );
    if (gen != null) {
      return _PkEntryTombstoneTarget(edge: edge, incomingGeneration: gen);
    }
  }
  return null;
}

class _PkEntryTombstoneTarget {
  const _PkEntryTombstoneTarget({
    required this.edge,
    required this.incomingGeneration,
  });

  final _PkMemberGroupEntryLogicalEdge edge;
  final int incomingGeneration;
}

/// The single row for a PK logical edge whose stored `sync_generation` equals
/// [generation], live or soft-deleted (returns the live row if present). Used by
/// the entry hardDelete to find the row the incoming gen-N tombstone actually
/// targets — which may be keyed by a DIFFERENT Drift PK than the wire id after a
/// canonical-collapse redirect (the live edge re-rooted onto the canonical sha
/// while carrying sync_generation=N).
Future<MemberGroupEntryRow?> _memberGroupEntryByPkRefsAndGeneration(
  AppDatabase db, {
  required String pkGroupUuid,
  required String pkMemberUuid,
  required int generation,
}) async {
  final rows =
      await (db.select(db.memberGroupEntries)..where(
            (t) =>
                t.pkGroupUuid.equals(pkGroupUuid) &
                t.pkMemberUuid.equals(pkMemberUuid) &
                t.syncGeneration.equals(generation),
          ))
          .get();
  if (rows.isEmpty) return null;
  // Prefer the live row if the edge has both a live and a stale tombstone at
  // this generation.
  return rows.firstWhere((r) => !r.isDeleted, orElse: () => rows.first);
}

Future<Set<String>> _deleteDeferredPkBackedMemberGroupEntryOpsForLogicalEdge(
  AppDatabase db, {
  required _PkMemberGroupEntryLogicalEdge edge,
}) async {
  if (!await _tableExists(db, _pkGroupEntryDeferredOpsTableName)) {
    return const <String>{};
  }

  final deletedIds = <String>{};
  final deferredRows = await db.pkGroupEntryDeferredSyncOpsDao.getAll();
  for (final row in deferredRows) {
    if (row.entityType != 'member_group_entries') continue;
    final deferredEdge = _pkMemberGroupEntryLogicalEdgeFromFieldsJson(
      row.fieldsJson,
    );
    if (deferredEdge?.key != edge.key) continue;
    await db.pkGroupEntryDeferredSyncOpsDao.deleteById(row.id);
    deletedIds.add(row.id);
  }
  return deletedIds;
}

Future<Set<String>> _deleteDeferredPkBackedMemberGroupEntryOpsForPkRefs(
  AppDatabase db, {
  String? pkGroupUuid,
  String? pkMemberUuid,
}) async {
  if (pkGroupUuid == null && pkMemberUuid == null) {
    return const <String>{};
  }
  if (!await _tableExists(db, _pkGroupEntryDeferredOpsTableName)) {
    return const <String>{};
  }

  final deletedIds = <String>{};
  final deferredRows = await db.pkGroupEntryDeferredSyncOpsDao.getAll();
  for (final row in deferredRows) {
    if (row.entityType != 'member_group_entries') continue;
    final deferredEdge = _pkMemberGroupEntryLogicalEdgeFromFieldsJson(
      row.fieldsJson,
    );
    if (deferredEdge == null) continue;
    final matchesGroup =
        pkGroupUuid != null && deferredEdge.pkGroupUuid == pkGroupUuid;
    final matchesMember =
        pkMemberUuid != null && deferredEdge.pkMemberUuid == pkMemberUuid;
    if (!matchesGroup && !matchesMember) continue;
    await db.pkGroupEntryDeferredSyncOpsDao.deleteById(row.id);
    deletedIds.add(row.id);
  }
  return deletedIds;
}

Future<Set<String>>
_deleteDeferredPkBackedMemberGroupEntryOpsForCanonicalEntityId(
  AppDatabase db, {
  required String entityId,
}) async {
  if (!await _tableExists(db, _pkGroupEntryDeferredOpsTableName)) {
    return const <String>{};
  }

  final matchingEdgeKeys = <String>{};
  final deferredRows = await db.pkGroupEntryDeferredSyncOpsDao.getAll();
  for (final row in deferredRows) {
    if (row.entityType != 'member_group_entries') continue;
    final deferredEdge = _pkMemberGroupEntryLogicalEdgeFromFieldsJson(
      row.fieldsJson,
    );
    if (deferredEdge == null) continue;
    if (_isCanonicalPkMemberGroupEntryEntityId(entityId, deferredEdge)) {
      matchingEdgeKeys.add(deferredEdge.key);
    }
  }

  if (matchingEdgeKeys.isEmpty) {
    return const <String>{};
  }

  final deletedIds = <String>{};
  for (final row in deferredRows) {
    if (row.entityType != 'member_group_entries') continue;
    final deferredEdge = _pkMemberGroupEntryLogicalEdgeFromFieldsJson(
      row.fieldsJson,
    );
    if (deferredEdge == null || !matchingEdgeKeys.contains(deferredEdge.key)) {
      continue;
    }
    await db.pkGroupEntryDeferredSyncOpsDao.deleteById(row.id);
    deletedIds.add(row.id);
  }
  return deletedIds;
}

Future<void> _deleteDeferredPkBackedMemberGroupEntryOpsForTombstone(
  AppDatabase db, {
  required String entityId,
  required Map<String, dynamic> fields,
}) async {
  if (!await _tableExists(db, _pkGroupEntryDeferredOpsTableName)) {
    return;
  }

  await db.pkGroupEntryDeferredSyncOpsDao.deleteById(
    'member_group_entries:$entityId',
  );
  await _deleteDeferredPkBackedMemberGroupEntryOpsForCanonicalEntityId(
    db,
    entityId: entityId,
  );
  final logicalEdge = _pkMemberGroupEntryLogicalEdgeFromFields(fields);
  if (logicalEdge != null) {
    await _deleteDeferredPkBackedMemberGroupEntryOpsForLogicalEdge(
      db,
      edge: logicalEdge,
    );
  }
}

Future<void> _writeMemberGroupEntryPkFields(
  AppDatabase db, {
  required String id,
  String? pkGroupUuid,
  String? pkMemberUuid,
}) async {
  final assignments = <String>[];
  final variables = <Object?>[];

  if (await _tableHasColumn(db, 'member_group_entries', 'pk_group_uuid')) {
    assignments.add('pk_group_uuid = ?');
    variables.add(pkGroupUuid);
  }
  if (await _tableHasColumn(db, 'member_group_entries', 'pk_member_uuid')) {
    assignments.add('pk_member_uuid = ?');
    variables.add(pkMemberUuid);
  }

  if (assignments.isEmpty) return;

  variables.add(id);
  await db.customStatement(
    'UPDATE member_group_entries '
    'SET ${assignments.join(', ')} '
    'WHERE id = ?',
    variables,
  );
}

Future<void> _appendMemberGroupEntryPkFields(
  AppDatabase db,
  String id,
  Map<String, dynamic> fields,
) async {
  final selectColumns = <String>[];
  if (await _tableHasColumn(db, 'member_group_entries', 'pk_group_uuid')) {
    selectColumns.add('pk_group_uuid');
  }
  if (await _tableHasColumn(db, 'member_group_entries', 'pk_member_uuid')) {
    selectColumns.add('pk_member_uuid');
  }

  if (selectColumns.isEmpty) return;

  final row = await db
      .customSelect(
        'SELECT ${selectColumns.join(', ')} '
        'FROM member_group_entries '
        'WHERE id = ?',
        variables: [Variable<String>(id)],
      )
      .getSingleOrNull();
  if (row == null) return;

  if (selectColumns.contains('pk_group_uuid')) {
    fields['pk_group_uuid'] = _asString(row.data['pk_group_uuid']);
  }
  if (selectColumns.contains('pk_member_uuid')) {
    fields['pk_member_uuid'] = _asString(row.data['pk_member_uuid']);
  }
}

Future<MemberGroupEntryRow?> _activeMemberGroupEntryByResolvedRefs(
  AppDatabase db, {
  required String groupId,
  required String memberId,
}) {
  return (db.select(db.memberGroupEntries)..where(
        (t) =>
            t.groupId.equals(groupId) &
            t.memberId.equals(memberId) &
            t.isDeleted.equals(false),
      ))
      .getSingleOrNull();
}

/// The active row for a PK logical edge `(pkGroupUuid, pkMemberUuid)`, keyed by
/// the PK uuids rather than resolved local ids. Used by the entry hardDelete
/// generation guard, which only knows the wire id's pk refs.
Future<MemberGroupEntryRow?> _activeMemberGroupEntryByPkRefs(
  AppDatabase db, {
  required String pkGroupUuid,
  required String pkMemberUuid,
}) {
  return (db.select(db.memberGroupEntries)..where(
        (t) =>
            t.pkGroupUuid.equals(pkGroupUuid) &
            t.pkMemberUuid.equals(pkMemberUuid) &
            t.isDeleted.equals(false),
      ))
      .getSingleOrNull();
}

Future<bool> _deferPkBackedMemberGroupEntryOp(
  AppDatabase db, {
  required String entityId,
  required Map<String, dynamic> fields,
  required String reason,
}) async {
  if (!await _tableExists(db, _pkGroupEntryDeferredOpsTableName)) {
    return false;
  }

  // Route through the DAO upsert so Drift encodes `created_at` as
  // seconds-since-epoch. The DAO uses `insertOnConflictUpdate` which preserves
  // the ON CONFLICT(id) DO UPDATE semantics of the previous raw insert.
  final deferredId = 'member_group_entries:$entityId';
  final existing = await db.pkGroupEntryDeferredSyncOpsDao.getById(deferredId);
  await db.pkGroupEntryDeferredSyncOpsDao.upsert(
    PkGroupEntryDeferredSyncOpsCompanion.insert(
      id: deferredId,
      entityType: 'member_group_entries',
      entityId: entityId,
      fieldsJson: jsonEncode(fields),
      reason: reason,
      createdAt: existing?.createdAt ?? DateTime.now(),
    ),
  );
  return true;
}

Future<bool> _applyMemberGroupEntryFields(
  AppDatabase db, {
  required String id,
  required Map<String, dynamic> fields,
  required SyncQuarantineService? quarantine,
  required void Function(Future<void> write) trackQuarantineWrite,
  required bool allowDeferral,
  bool throwOnUnresolved = true,
}) async {
  final existingRow = await (db.select(
    db.memberGroupEntries,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (existingRow == null && _isRemoteTombstone(fields)) {
    await _deleteDeferredPkBackedMemberGroupEntryOpsForTombstone(
      db,
      entityId: id,
      fields: fields,
    );
    return false;
  }
  final f = _FieldContext(
    entityType: 'member_group_entries',
    entityId: id,
    fields: fields,
    quarantine: quarantine,
    trackQuarantineWrite: trackQuarantineWrite,
  );
  final pkGroupUuid = fields.containsKey('pk_group_uuid')
      ? _asString(fields['pk_group_uuid'])
      : existingRow?.pkGroupUuid;
  final pkMemberUuid = fields.containsKey('pk_member_uuid')
      ? _asString(fields['pk_member_uuid'])
      : existingRow?.pkMemberUuid;
  final legacyGroupId = fields.containsKey('group_id')
      ? _asString(fields['group_id'])
      : existingRow?.groupId;
  final legacyMemberId = fields.containsKey('member_id')
      ? _asString(fields['member_id'])
      : existingRow?.memberId;

  // When a PK UUID field is present on the payload, sender-local
  // `group_id` / `member_id` become compatibility hints only.
  // Resolve PK UUIDs independently and defer if they miss — never fall
  // back to the sender's local ids for PK-present payloads.
  final pkGroupResolvedId = pkGroupUuid == null
      ? null
      : (await _resolveMemberGroupRowForSyncId(
          db,
          _canonicalPkGroupEntityId(pkGroupUuid),
          payloadPkGroupUuid: pkGroupUuid,
        ))?.id;
  final pkMemberResolvedId = pkMemberUuid == null
      ? null
      : await _resolveLocalMemberIdByPkUuid(db, pkMemberUuid);

  final groupNeedsPkResolution = pkGroupUuid != null;
  final memberNeedsPkResolution = pkMemberUuid != null;

  final pkResolutionMissed =
      (groupNeedsPkResolution && pkGroupResolvedId == null) ||
      (memberNeedsPkResolution && pkMemberResolvedId == null);

  if (pkResolutionMissed) {
    if (allowDeferral) {
      final missingRefs = [
        if (groupNeedsPkResolution && pkGroupResolvedId == null)
          'group:$pkGroupUuid',
        if (memberNeedsPkResolution && pkMemberResolvedId == null)
          'member:$pkMemberUuid',
      ].join(', ');
      final deferred = await _deferPkBackedMemberGroupEntryOp(
        db,
        entityId: id,
        fields: fields,
        reason: 'unresolved_pk_refs:$missingRefs',
      );
      if (deferred) return false;
    }
    if (!throwOnUnresolved) return false;
  }

  final resolvedGroupId =
      pkGroupResolvedId ?? (groupNeedsPkResolution ? null : legacyGroupId);
  final resolvedMemberId =
      pkMemberResolvedId ?? (memberNeedsPkResolution ? null : legacyMemberId);

  if (resolvedGroupId == null || resolvedMemberId == null) {
    if (!throwOnUnresolved) return false;
    throw StateError(
      'member_group_entries sync op $id is missing resolvable '
      'group/member identity',
    );
  }

  final logicalEdge = _pkMemberGroupEntryLogicalEdge(
    pkGroupUuid: pkGroupUuid,
    pkMemberUuid: pkMemberUuid,
  );
  var targetId = id;
  // The row we are about to write may already carry a stored incarnation. Track
  // its current generation so a strictly-newer incoming incarnation advances it
  // (sanctioned revive) while a stale/equal one leaves it intact.
  var targetRowGeneration = existingRow?.syncGeneration ?? 0;

  // Parse the incoming incarnation generation off the wire id BEFORE the
  // canonical-collapse redirect below: the redirect must never displace or
  // soft-delete a row that lives at a strictly-NEWER incarnation than the
  // incoming op carries, else collapsing a live gen-N edge onto a stale
  // gen-(<N) op re-roots it at a fresh gen-0 row and lets the eventual gen-0
  // hardDelete kill the edge. Opaque sha, so re-derive-and-compare against this
  // edge; a non-incarnation id parses null and is treated as gen 0 (legacy).
  final incomingEntryGen = logicalEdge == null
      ? 0
      : (parseEntryIncarnationGeneration(
              id,
              pkGroupUuid: logicalEdge.pkGroupUuid,
              pkMemberUuid: logicalEdge.pkMemberUuid,
            ) ??
            0);

  if (logicalEdge != null) {
    final canonicalId = _canonicalPkMemberGroupEntryEntityId(
      logicalEdge.pkGroupUuid,
      logicalEdge.pkMemberUuid,
    );
    final activeLogicalRow = await _activeMemberGroupEntryByResolvedRefs(
      db,
      groupId: resolvedGroupId,
      memberId: resolvedMemberId,
    );
    // Family invariant: an older-incarnation op never displaces a newer-
    // incarnation row. When the live edge is strictly newer than the incoming
    // id, redirect the write onto the live row (so a stale duplicate-keyed op
    // doesn't fork the edge) but leave its generation, liveness, and id intact
    // — the generation guards below keep is_deleted/sync_generation from
    // regressing. Only when the incoming op is at-or-newer do we collapse onto
    // the canonical id and retire the divergent active row.
    final incomingIsNewerOrEqual =
        activeLogicalRow == null ||
        incomingEntryGen >= activeLogicalRow.syncGeneration;
    if (activeLogicalRow != null && activeLogicalRow.id != targetId) {
      if (incomingIsNewerOrEqual) {
        targetId = id == canonicalId || activeLogicalRow.id == canonicalId
            ? canonicalId
            : activeLogicalRow.id;
      } else {
        // Incoming is older: write onto the live row in place, never re-root to
        // a burned older id.
        targetId = activeLogicalRow.id;
      }
    }
    if (incomingIsNewerOrEqual &&
        activeLogicalRow != null &&
        activeLogicalRow.id != targetId) {
      await (db.update(db.memberGroupEntries)
            ..where((t) => t.id.equals(activeLogicalRow.id)))
          .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));
    }
    if (activeLogicalRow != null) {
      targetRowGeneration = activeLogicalRow.syncGeneration;
    }
  }

  // Advance the local row only on a strictly-newer incarnation. Value.absent
  // leaves sync_generation untouched (a stale/equal op never demotes it).
  final entrySyncGenerationValue = incomingEntryGen > targetRowGeneration
      ? Value(incomingEntryGen)
      : const Value<int>.absent();

  // Family invariant (per-entity absorbing, generation-aware): an older-
  // incarnation op — including a fields-borne is_deleted=true — must never
  // delete or mutate the live state of a strictly-newer incarnation row. When
  // the row we are about to write already lives at a newer generation, leave
  // is_deleted untouched (Value.absent) so a stale gen-(<N) tombstone or edit
  // can't tombstone the gen-N edge. An at-or-newer op applies is_deleted as
  // sent (sanctioned revive carries is_deleted=false; a same-or-newer delete
  // tombstones normally).
  final isDeletedValue = incomingEntryGen < targetRowGeneration
      ? const Value<bool>.absent()
      : f.boolField('is_deleted');

  final companion = MemberGroupEntriesCompanion(
    id: Value(targetId),
    groupId: Value(resolvedGroupId),
    memberId: Value(resolvedMemberId),
    isDeleted: isDeletedValue,
    syncGeneration: entrySyncGenerationValue,
    // LOCAL-ONLY recency stamp — never read from or written to wire field maps
    // (not in prismSyncSchema; toSyncFields below omits it). Stamped on EVERY
    // apply that touches this row: drift's `clientDefault` fires only on a true
    // INSERT, so an apply that revives an existing tombstone would otherwise keep
    // the ORIGINAL stamp — and a peer's fresh re-add landing on an old local
    // tombstone would look "old" to the importer's removal-recency grace, letting
    // the next PK pull reconcile-delete the just-revived entry and destroy the
    // originating device's unpushed push_add. Refreshing here makes every inbound
    // touch count as "recent" on THIS device — the fail-safe direction.
    createdAt: Value(DateTime.now()),
  );
  await _insertOrUpdateById(
    db,
    db.memberGroupEntries,
    companion,
    (t) => t.id.equals(targetId),
  );
  await _writeMemberGroupEntryPkFields(
    db,
    id: targetId,
    pkGroupUuid: pkGroupUuid,
    pkMemberUuid: pkMemberUuid,
  );
  return true;
}

Future<void> _retryDeferredPkBackedMemberGroupEntryOps(
  AppDatabase db, {
  required SyncQuarantineService? quarantine,
  required void Function(Future<void> write) trackQuarantineWrite,
}) async {
  if (!await _tableExists(db, _pkGroupEntryDeferredOpsTableName)) {
    return;
  }

  final rows = await db.pkGroupEntryDeferredSyncOpsDao.getAll()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final preferredDeferredIdByEdge = <String, _PreferredDeferredPkEntryOp>{};
  for (final row in rows) {
    if (row.entityType != 'member_group_entries') continue;
    final edge = _pkMemberGroupEntryLogicalEdgeFromFieldsJson(row.fieldsJson);
    if (edge == null) continue;
    final isCanonical = _isCanonicalPkMemberGroupEntryEntityId(
      row.entityId,
      edge,
    );
    final currentPreferred = preferredDeferredIdByEdge[edge.key];
    if (currentPreferred == null ||
        (!currentPreferred.isCanonical && isCanonical)) {
      preferredDeferredIdByEdge[edge.key] = _PreferredDeferredPkEntryOp(
        deferredId: row.id,
        isCanonical: isCanonical,
      );
    }
  }
  final deletedDeferredIds = <String>{};

  for (final row in rows) {
    if (deletedDeferredIds.contains(row.id)) {
      continue;
    }

    final logicalEdge = _pkMemberGroupEntryLogicalEdgeFromFieldsJson(
      row.fieldsJson,
    );
    final preferredDeferred = logicalEdge == null
        ? null
        : preferredDeferredIdByEdge[logicalEdge.key];
    if (preferredDeferred != null && preferredDeferred.deferredId != row.id) {
      await db.pkGroupEntryDeferredSyncOpsDao.deleteById(row.id);
      deletedDeferredIds.add(row.id);
      continue;
    }

    final deferredId = row.id;
    final entityId = row.entityId;
    final fieldsJson = row.fieldsJson;
    final reason = row.reason;
    final retryCount = row.retryCount;
    final decodedFields = _decodeDeferredPkEntryFieldsJson(fieldsJson);

    if (decodedFields == null) {
      await db.pkGroupEntryDeferredSyncOpsDao.deleteById(deferredId);
      deletedDeferredIds.add(deferredId);
      continue;
    }

    final applied = await _applyMemberGroupEntryFields(
      db,
      id: entityId,
      fields: decodedFields,
      quarantine: quarantine,
      trackQuarantineWrite: trackQuarantineWrite,
      allowDeferral: false,
      throwOnUnresolved: false,
    );

    if (applied) {
      await db.pkGroupEntryDeferredSyncOpsDao.deleteById(deferredId);
      deletedDeferredIds.add(deferredId);
      if (logicalEdge != null &&
          _isCanonicalPkMemberGroupEntryEntityId(entityId, logicalEdge)) {
        deletedDeferredIds.addAll(
          await _deleteDeferredPkBackedMemberGroupEntryOpsForLogicalEdge(
            db,
            edge: logicalEdge,
          ),
        );
      }
    } else {
      final nextRetryCount = retryCount + 1;
      final now = DateTime.now();
      final terminalGraceElapsed =
          row.createdAt.isAfter(now) ||
          now.difference(row.createdAt) >= _deferredPkEntryReplayTerminalGrace;
      if (nextRetryCount >= _maxDeferredPkEntryReplayRetries &&
          terminalGraceElapsed) {
        if (quarantine != null) {
          await quarantine.quarantineField(
            entityType: 'member_group_entries',
            entityId: entityId,
            expectedType: 'Resolvable PK group/member references',
            receivedType: 'DeferredPkEntryUnresolved',
            receivedValue: fieldsJson,
            errorMessage:
                'Deferred PK-backed entry exceeded max retries '
                '($_maxDeferredPkEntryReplayRetries): $reason',
          );
        }
        await db.pkGroupEntryDeferredSyncOpsDao.deleteById(deferredId);
        deletedDeferredIds.add(deferredId);
      } else {
        await db.pkGroupEntryDeferredSyncOpsDao.markRetried(deferredId);
      }
    }
  }

  await _retryQuarantinedPkBackedMemberGroupEntryOps(
    db,
    quarantine: quarantine,
    trackQuarantineWrite: trackQuarantineWrite,
  );
}

Future<void> _retryQuarantinedPkBackedMemberGroupEntryOps(
  AppDatabase db, {
  required SyncQuarantineService? quarantine,
  required void Function(Future<void> write) trackQuarantineWrite,
}) async {
  if (!await _tableExists(db, 'sync_quarantine')) {
    return;
  }

  final rows = await db.syncQuarantineDao.getDeferredPkEntryUnresolved();
  for (final row in rows) {
    final fieldsJson = row.receivedValue;
    if (fieldsJson == null) continue;

    final decodedFields = _decodeDeferredPkEntryFieldsJson(fieldsJson);
    if (decodedFields == null ||
        _pkMemberGroupEntryLogicalEdgeFromFields(decodedFields) == null) {
      continue;
    }

    final applied = await _applyMemberGroupEntryFields(
      db,
      id: row.entityId,
      fields: decodedFields,
      quarantine: quarantine,
      trackQuarantineWrite: trackQuarantineWrite,
      allowDeferral: false,
      throwOnUnresolved: false,
    );
    if (applied) {
      await db.syncQuarantineDao.deleteById(row.id);
    }
  }
}

Future<void> _recordPkGroupAliasIfNeeded(
  AppDatabase db, {
  required String legacyEntityId,
  required String pkGroupUuid,
}) async {
  if (legacyEntityId.isEmpty ||
      legacyEntityId == _canonicalPkGroupEntityId(pkGroupUuid)) {
    return;
  }
  // Record-time guard: never alias the deterministic hyphen-form self-id
  // ('pk-group-<uuid>'). The importer mints every device's local group row
  // under this id, so it is by construction someone's active row across the
  // fleet. The _isActiveMemberGroupIdForPkUuid check below requires
  // is_deleted=0 and therefore MISSES the device's own TOMBSTONED self row —
  // exactly the state the tombstone-apply branch re-creates the row in, which
  // is how stale self-aliases get re-recorded and poison the alias-delete
  // emitters into re-killing peers' active rows.
  if (legacyEntityId == 'pk-group-$pkGroupUuid') {
    return;
  }
  if (await _isActiveMemberGroupIdForPkUuid(db, legacyEntityId, pkGroupUuid)) {
    return;
  }
  if (!await _tableExists(db, _pkGroupSyncAliasesTableName)) {
    return;
  }

  // Route through the DAO upsert so Drift encodes `created_at` as
  // seconds-since-epoch. The DAO's insertOnConflictUpdate preserves the
  // original ON CONFLICT(legacy_entity_id) DO UPDATE semantics.
  await db.pkGroupSyncAliasesDao.upsertAlias(
    legacyEntityId: legacyEntityId,
    pkGroupUuid: pkGroupUuid,
    canonicalEntityId: _canonicalPkGroupEntityId(pkGroupUuid),
  );
}

/// Persist a PK-identity redirect alias for `members`/`fronting_sessions`.
///
/// When applyFields redirects an incoming op for [legacyEntityId] onto the
/// different local winner row [targetRowId] (same PK identity), the legacy id is
/// never materialized locally, so a later delete for it would no-op. Recording
/// the mapping here lets the delete paths resolve the redirect and the
/// repository delete emitters fan tombstones out to every legacy id the fleet
/// knows the entity by. Guarded by [isForbiddenAliasTarget] so an id that is
/// itself an active local row is never aliased. Local-only write inside the
/// existing apply transaction; no emission.
Future<void> _recordPkIdentityAliasIfNeeded(
  AppDatabase db, {
  required String entityTable,
  required String legacyEntityId,
  required String? pkUuid,
  String? pkId,
  String? memberId,
  required String targetRowId,
}) async {
  if (legacyEntityId.isEmpty || legacyEntityId == targetRowId) return;
  // members/fronting_sessions have no deterministic self-id form, so this
  // reduces to the active-local-row check; pkUuid is passed through for the
  // shared predicate's signature.
  if (await isForbiddenAliasTarget(db, entityTable, legacyEntityId, pkUuid)) {
    return;
  }
  await db.pkIdentitySyncAliasesDao.upsertAlias(
    entityTable: entityTable,
    legacyEntityId: legacyEntityId,
    pkUuid: pkUuid,
    pkId: pkId,
    memberId: memberId,
    targetRowId: targetRowId,
  );
}

/// Resolve a recorded `members` redirect alias for [legacyEntityId] to the
/// id of the CURRENT active holder row. Re-resolves by stored PK identity
/// (uuid/id) so a holder that has itself since been re-keyed is still found;
/// falls back to the recorded `target_row_id` when it still names an active row.
/// Returns null when no alias is recorded or no active holder resolves.
///
/// What closes the dominant post-delete PK re-import vector is the alias being
/// GONE by the time a delayed legacy-id delete reaches this resolver, NOT the
/// temporal bound below. Every terminal resolution path purges the inbound
/// aliases of the dying holder, so once the recorded holder is deleted/
/// tombstoned this resolver returns null and the delayed delete no-ops — a
/// fresh re-import of the same PK identity is never selected. Two purge shapes,
/// because a holder can die by its OWN id or as a re-resolved identity:
///   - holder dies by its own id (exact-id hardDelete, existing-row fields-
///     tombstone): purge aliases whose recorded `target_row_id` is that row
///     (`deleteByTargetRowId`).
///   - holder is found by re-resolving the identity (this resolver, on the
///     resolved-holder hardDelete path): purge aliases by IDENTITY
///     (`deleteByIdentity`), since a sibling alias may record a different
///     already-dead row as its target while still naming the same identity.
/// This matters because a re-import sets `created_at = pk.created` (written
/// through verbatim), so it shares the ORIGINAL incarnation's historical
/// timestamp and the temporal bound below cannot discriminate it.
///
/// The temporal bound (`createdAt <= alias.createdAt`) is the remaining
/// belt-and-suspenders for the pre-purge race window: it excludes a same-
/// identity row materialized AFTER the alias was recorded with a LATER local
/// timestamp (the merge-time/now() shape), so an older op never displaces a
/// strictly-newer-timestamped same-identity row. It does NOT — and is not
/// relied on to — exclude a historical-timestamp re-import; that case is owned
/// entirely by the target-row purge. The `target_row_id` fallback covers
/// identity-drift onto a still-active recorded target (loser-nulling merge
/// winner, manual relink — rows that predate the alias).
Future<String?> _resolveMemberIdentityAliasHolder(
  AppDatabase db,
  String legacyEntityId,
) async {
  final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
    'members',
    legacyEntityId,
  );
  if (alias == null) return null;
  final holders = await _activeMemberRowsByPkIdentityForApply(
    db,
    pkUuid: alias.pkUuid,
    pkId: alias.pkId,
  );
  for (final holder in holders) {
    if (!holder.createdAt.isAfter(alias.createdAt)) return holder.id;
  }
  final fallback = await (db.select(db.members)
        ..where((t) => t.id.equals(alias.targetRowId) & t.isDeleted.equals(false)))
      .getSingleOrNull();
  return fallback?.id;
}

/// `fronting_sessions` analogue of [_resolveMemberIdentityAliasHolder],
/// keyed on (pluralkit_uuid, member_id). The dominant post-delete re-import
/// vector is closed by the same mechanism: every terminal resolution path
/// purges the dying holder's inbound aliases — by recorded `target_row_id` when
/// the holder dies by its own id (`deleteByTargetRowId`), by IDENTITY when the
/// holder is found via this resolver on the resolved-holder hardDelete path
/// (`deleteByIdentity`, so a sibling alias recording a different already-dead
/// session is not left behind). Once the recorded holder is gone this resolver
/// returns null and a delayed legacy-id delete no-ops — a re-imported session
/// of the same identity is never selected. This is necessary because a switch
/// re-import sets `start_time = switchEntry.timestamp`, identical across
/// incarnations, so the temporal bound below cannot tell a re-import apart.
///
/// The temporal bound (`startTime <= alias.createdAt`) is the belt-and-
/// suspenders for the pre-purge race window only: `fronting_sessions` has no
/// row-creation timestamp, so it compares the session's `startTime` and
/// excludes a session that STARTED after the alias was recorded with a later
/// time. The `target_row_id` fallback covers identity-drift onto a still-active
/// recorded target (a re-import gets a fresh id, never the recorded target).
Future<String?> _resolveFrontingIdentityAliasHolder(
  AppDatabase db,
  String legacyEntityId,
) async {
  final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
    'fronting_sessions',
    legacyEntityId,
  );
  if (alias == null) return null;
  final holders = await _activeFrontingSessionRowsByPkIdentityForApply(
    db,
    pkUuid: alias.pkUuid,
    memberId: alias.memberId,
  );
  for (final holder in holders) {
    if (!holder.startTime.isAfter(alias.createdAt)) return holder.id;
  }
  final fallback = await (db.select(db.frontingSessions)
        ..where((t) => t.id.equals(alias.targetRowId) & t.isDeleted.equals(false)))
      .getSingleOrNull();
  return fallback?.id;
}

Future<bool> _isActiveMemberGroupIdForPkUuid(
  AppDatabase db,
  String id,
  String pkGroupUuid,
) async {
  final row = await db
      .customSelect(
        'SELECT 1 FROM member_groups '
        'WHERE id = ? AND pluralkit_uuid = ? AND is_deleted = 0 LIMIT 1',
        variables: [Variable<String>(id), Variable<String>(pkGroupUuid)],
      )
      .getSingleOrNull();
  return row != null;
}

// ---------------------------------------------------------------------------
// _FieldContext — wraps entity metadata + quarantine for field-level reporting
// ---------------------------------------------------------------------------

/// Scoped context for a single applyFields invocation. Methods mirror the
/// top-level `_*Field` helpers but additionally quarantine type mismatches
/// when a [SyncQuarantineService] is provided.
class _FieldContext {
  _FieldContext({
    required this.entityType,
    required this.entityId,
    required this.fields,
    this.quarantine,
    this.trackQuarantineWrite,
  });

  final String entityType;
  final String entityId;
  final Map<String, dynamic> fields;
  final SyncQuarantineService? quarantine;
  final void Function(Future<void> write)? trackQuarantineWrite;

  // -- Non-nullable String ---------------------------------------------------

  Value<String> stringField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asString(raw);
    if (v != null) return Value(v);
    _report(key, 'String', raw);
    return const Value.absent();
  }

  // -- Nullable String -------------------------------------------------------

  Value<String?> stringFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _asString(raw);
    if (v != null) return Value(v);
    _report(key, 'String?', raw);
    return const Value.absent();
  }

  // -- Nullable age (String, with old-client numeric back-compat) ------------

  // Like [stringFieldNullable] but also accepts a bare numeric wire value and
  // stringifies it (see [_asAgeString]). Used ONLY for the `age` field, which
  // migrated Int → String in schema v31; an old peer still emits a bare Int.
  Value<String?> ageFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _asAgeString(raw);
    if (v != null) return Value(v);
    _report(key, 'String?', raw);
    return const Value.absent();
  }

  // -- Non-nullable int ------------------------------------------------------

  Value<int> intField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asInt(raw);
    if (v != null) return Value(v);
    _report(key, 'int', raw);
    return const Value.absent();
  }

  // -- Nullable int ----------------------------------------------------------

  Value<int?> intFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _asInt(raw);
    if (v != null) return Value(v);
    _report(key, 'int?', raw);
    return const Value.absent();
  }

  // -- Non-nullable bool -----------------------------------------------------

  Value<bool> boolField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asBool(raw);
    if (v != null) return Value(v);
    _report(key, 'bool', raw);
    return const Value.absent();
  }

  // -- Non-nullable double ---------------------------------------------------

  Value<double> realField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asDouble(raw);
    if (v != null) return Value(v);
    _report(key, 'double', raw);
    return const Value.absent();
  }

  // -- Non-nullable DateTime -------------------------------------------------

  Value<DateTime> dateTimeField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asDateTime(raw);
    if (v != null) return Value(v);
    _report(key, 'DateTime', raw);
    return const Value.absent();
  }

  // -- Nullable DateTime -----------------------------------------------------

  Value<DateTime?> dateTimeFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _asDateTime(raw);
    if (v != null) return Value(v);
    _report(key, 'DateTime?', raw);
    return const Value.absent();
  }

  // -- Nullable blob ---------------------------------------------------------

  Value<Uint8List?> blobFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _blob(raw);
    if (v != null) return Value(v);
    _report(key, 'Uint8List?', raw);
    return const Value.absent();
  }

  // -- Internal reporting ----------------------------------------------------

  void _report(String fieldName, String expectedType, dynamic received) {
    final q = quarantine;
    if (q == null) return;
    final write = q.quarantineField(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
      expectedType: expectedType,
      receivedType: received?.runtimeType.toString() ?? 'null',
      receivedValue: _safeValuePreview(received),
      errorMessage:
          'Type mismatch: expected $expectedType, '
          'got ${received?.runtimeType ?? "null"}',
    );
    trackQuarantineWrite?.call(write);
  }

  /// Truncated string representation for diagnostics (avoid storing huge blobs).
  static String? _safeValuePreview(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    return s.length > 200 ? '${s.substring(0, 200)}...' : s;
  }
}

// ---------------------------------------------------------------------------
// members
// ---------------------------------------------------------------------------

DriftSyncEntity _membersEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
  Future<void> Function() requestDeferredPkEntryReplay,
) {
  return DriftSyncEntity(
    tableName: 'members',
    toSyncFields: (dynamic row) {
      final r = row as Member;
      return {
        'name': r.name,
        'pronouns': r.pronouns,
        'emoji': r.emoji,
        'age': r.age,
        'bio': r.bio,
        'avatar_image_data': r.avatarImageData != null
            ? base64Encode(r.avatarImageData!)
            : null,
        'pk_avatar_cached_url': r.pkAvatarCachedUrl,
        'is_active': r.isActive,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'display_order': r.displayOrder,
        'is_admin': r.isAdmin,
        'custom_color_enabled': r.customColorEnabled,
        'custom_color_hex': r.customColorHex,
        'parent_system_id': r.parentSystemId,
        'pluralkit_uuid': r.pluralkitUuid,
        'pluralkit_id': r.pluralkitId,
        'pluralkit_display_name': r.pluralkitDisplayName,
        'markdown_enabled': r.markdownEnabled,
        'display_name': r.displayName,
        'birthday': r.birthday,
        'proxy_tags_json': r.proxyTagsJson,
        'pk_banner_url': r.pkBannerUrl,
        'profile_header_source': r.profileHeaderSource,
        'profile_header_layout': r.profileHeaderLayout,
        'profile_header_visible': r.profileHeaderVisible,
        'name_style_font': r.nameStyleFont,
        'name_style_bold': r.nameStyleBold,
        'name_style_italic': r.nameStyleItalic,
        'name_style_color_mode': r.nameStyleColorMode,
        'name_style_color_hex': r.nameStyleColorHex,
        'profile_header_image_data': r.profileHeaderImageData != null
            ? base64Encode(r.profileHeaderImageData!)
            : null,
        'pk_banner_image_data': r.pkBannerImageData != null
            ? base64Encode(r.pkBannerImageData!)
            : null,
        'pk_banner_cached_url': r.pkBannerCachedUrl,
        'pluralkit_sync_ignored': r.pluralkitSyncIgnored,
        'delete_push_started_at': r.deletePushStartedAt,
        'is_always_fronting': r.isAlwaysFronting,
        'is_deleted': r.isDeleted,
        'board_last_read_at': _dateTimeToSyncStringOrNull(r.boardLastReadAt),
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final remoteTombstone = _isRemoteTombstone(fields);
      final shouldCheckPkUuidChange = fields.containsKey('pluralkit_uuid');
      final existing = (shouldCheckPkUuidChange || remoteTombstone)
          ? await (db.select(
              db.members,
            )..where((t) => t.id.equals(id))).getSingleOrNull()
          : null;
      var priorPkUuid = shouldCheckPkUuidChange
          ? existing?.pluralkitUuid
          : null;
      final nextPkUuid = shouldCheckPkUuidChange
          ? _asString(fields['pluralkit_uuid'])
          : null;
      final nextPkId = fields.containsKey('pluralkit_id')
          ? _asString(fields['pluralkit_id'])
          : null;
      final f = _FieldContext(
        entityType: 'members',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final tombstonePkMemberUuid = nextPkUuid ?? existing?.pluralkitUuid;
      var targetId = id;
      // The alias recorded for this legacy id, read up front so the
      // resolved-holder tombstone purge below keys on the RECORDED identity
      // rather than the incoming fields' identity (a sparse tombstone payload
      // can omit the pk identity fields → nextPkUuid/nextPkId null → the
      // identity purge would silently no-op). Null when no redirect was
      // recorded.
      PkIdentitySyncAliasRow? tombstoneAlias;
      if (existing == null && remoteTombstone) {
        // Resolve-on-fields-tombstone: a fields-borne is_deleted=true for an id
        // we never materialized may be a delete of an entity whose ops we
        // redirected onto a different local row. Resolve the recorded alias to
        // the CURRENT active holder and tombstone it (fall through to the normal
        // companion write below) instead of inserting a dead stub under the
        // original id. NO alias -> keep the test-pinned stale-bootstrap stub
        // insert exactly. Redirects that predate this machinery recorded no
        // alias, so a delete already lost stays lost — delete again on the
        // surviving device.
        tombstoneAlias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
          'members',
          id,
        );
        final holderId = await _resolveMemberIdentityAliasHolder(db, id);
        if (holderId != null && holderId != id) {
          targetId = holderId;
          // Fall through to the shared companion write with the holder as the
          // target so its is_deleted flips to true, then purge the alias below
          // (after the write) so a redelivered tombstone for this legacy id —
          // re-pair snapshot, quarantine replay, full-row re-emission of the
          // soft-deleted row — does not re-resolve onto whatever row currently
          // holds the identity and kill it again. Accepted field-clobber: the
          // tombstone payload (name/created_at/avatar) is written onto the
          // holder; since soft-deleted members are user-recoverable a later
          // restore carries the dup-twin's field values. This matches
          // member_groups' resolve-and-tombstone shape and is preferred over a
          // narrower is_deleted-only write, which would diverge from the
          // test-pinned companion semantics.
        } else {
          final createdAt = f.dateTimeField('created_at');
          final fallbackTimestamp = DateTime.fromMillisecondsSinceEpoch(
            0,
            isUtc: true,
          );
          await _deleteDeferredPkBackedMemberGroupEntryOpsForPkRefs(
            db,
            pkMemberUuid: tombstonePkMemberUuid,
          );
          final hasPkIdentityConflict = await _memberPkIdentityHeldByOtherRow(
            db,
            incomingId: id,
            pkUuid: nextPkUuid,
            pkId: nextPkId,
          );
          await _insertOrUpdateById(
            db,
            db.members,
            MembersCompanion(
              id: Value(id),
              name: fields.containsKey('name')
                  ? f.stringField('name')
                  : const Value(''),
              createdAt: createdAt.present
                  ? createdAt
                  : Value(fallbackTimestamp),
              pluralkitUuid: fields.containsKey('pluralkit_uuid')
                  ? hasPkIdentityConflict
                        ? const Value(null)
                        : f.stringFieldNullable('pluralkit_uuid')
                  : const Value.absent(),
              isDeleted: const Value(true),
            ),
            (t) => t.id.equals(id),
          );
          return;
        }
      }
      if (!remoteTombstone) {
        await _releaseDeletedPkIdentityHoldersForMemberApply(
          db,
          incomingId: id,
          pkUuid: nextPkUuid,
          pkId: nextPkId,
        );
        final activeIdentityRows = await _activeMemberRowsByPkIdentityForApply(
          db,
          pkUuid: nextPkUuid,
          pkId: nextPkId,
        );
        Member? targetRow;
        for (final row in activeIdentityRows) {
          if (row.id == id) {
            targetRow = row;
            break;
          }
        }
        if (targetRow == null && activeIdentityRows.isNotEmpty) {
          targetRow = activeIdentityRows.first;
        }
        if (targetRow != null) {
          targetId = targetRow.id;
          if (shouldCheckPkUuidChange) {
            priorPkUuid = targetRow.pluralkitUuid;
          }
          for (final row in activeIdentityRows) {
            if (row.id == targetId) continue;
            await (db.update(
              db.members,
            )..where((t) => t.id.equals(row.id))).write(
              const MembersCompanion(
                pluralkitUuid: Value(null),
                pluralkitId: Value(null),
              ),
            );
          }
          // Record: the incoming entity id was redirected onto a different local
          // winner row and is never materialized locally, so a later delete for
          // it would no-op. Persist (members, id -> targetId) so the
          // delete paths resolve the redirect and the repository delete emitter
          // can fan tombstones out to every legacy id the fleet knows the
          // entity by. Local-only write inside the apply transaction; no
          // emission.
          if (targetId != id) {
            await _recordPkIdentityAliasIfNeeded(
              db,
              entityTable: 'members',
              legacyEntityId: id,
              pkUuid: nextPkUuid,
              pkId: nextPkId,
              targetRowId: targetId,
            );
          }
        }
      }
      final companion = MembersCompanion(
        id: Value(targetId),
        name: f.stringField('name'),
        pronouns: f.stringFieldNullable('pronouns'),
        emoji: f.stringField('emoji'),
        age: f.ageFieldNullable('age'),
        bio: f.stringFieldNullable('bio'),
        avatarImageData: f.blobFieldNullable('avatar_image_data'),
        pkAvatarCachedUrl: f.stringFieldNullable('pk_avatar_cached_url'),
        isActive: f.boolField('is_active'),
        createdAt: f.dateTimeField('created_at'),
        displayOrder: f.intField('display_order'),
        isAdmin: f.boolField('is_admin'),
        customColorEnabled: f.boolField('custom_color_enabled'),
        customColorHex: f.stringFieldNullable('custom_color_hex'),
        parentSystemId: f.stringFieldNullable('parent_system_id'),
        pluralkitUuid: f.stringFieldNullable('pluralkit_uuid'),
        pluralkitId: f.stringFieldNullable('pluralkit_id'),
        pluralkitDisplayName: f.stringFieldNullable('pluralkit_display_name'),
        markdownEnabled: f.boolField('markdown_enabled'),
        displayName: f.stringFieldNullable('display_name'),
        birthday: f.stringFieldNullable('birthday'),
        proxyTagsJson: f.stringFieldNullable('proxy_tags_json'),
        pkBannerUrl: f.stringFieldNullable('pk_banner_url'),
        profileHeaderSource: f.intField('profile_header_source'),
        profileHeaderLayout: f.intField('profile_header_layout'),
        profileHeaderVisible: f.boolField('profile_header_visible'),
        nameStyleFont: f.intField('name_style_font'),
        nameStyleBold: f.boolField('name_style_bold'),
        nameStyleItalic: f.boolField('name_style_italic'),
        nameStyleColorMode: f.intField('name_style_color_mode'),
        nameStyleColorHex: f.stringFieldNullable('name_style_color_hex'),
        profileHeaderImageData: f.blobFieldNullable(
          'profile_header_image_data',
        ),
        pkBannerImageData: f.blobFieldNullable('pk_banner_image_data'),
        pkBannerCachedUrl: f.stringFieldNullable('pk_banner_cached_url'),
        pluralkitSyncIgnored: f.boolField('pluralkit_sync_ignored'),
        deletePushStartedAt: f.intFieldNullable('delete_push_started_at'),
        isAlwaysFronting: f.boolField('is_always_fronting'),
        isDeleted: f.boolField('is_deleted'),
        boardLastReadAt: f.dateTimeFieldNullable('board_last_read_at'),
      );
      await _insertOrUpdateById(
        db,
        db.members,
        companion,
        (t) => t.id.equals(targetId),
      );
      if (remoteTombstone) {
        if (targetId != id) {
          // The tombstone for this legacy id resolved a redirect alias onto
          // the holder. Purge the alias now that the holder is tombstoned so a
          // later redelivery of this same legacy-id op finds no alias and cannot
          // re-resolve onto a NEWER same-identity row (post-delete re-import).
          await db.pkIdentitySyncAliasesDao.deleteByLegacyEntityId(
            'members',
            id,
          );
          // The holder here was found by re-resolving the identity
          // (resolve-on-fields-tombstone), so — like the resolved-holder
          // hardDelete branch — purge by IDENTITY, not just target == targetId. A
          // sibling alias recording a different already-dead row of the same
          // identity would otherwise survive and let a delayed legacy-id delete
          // re-resolve onto a fresh re-import.
          //
          // Key on the RECORDED alias's identity, not the incoming fields'
          // (nextPkUuid/nextPkId): a sparse tombstone payload can omit the pk
          // identity fields, which would null both and silently no-op this purge.
          // The resolver already matched on the recorded alias, so its stored
          // identity is the authoritative discriminator. Fall back to the
          // incoming fields only when the alias somehow lacks them.
          await db.pkIdentitySyncAliasesDao.deleteByIdentity(
            'members',
            pkUuid: tombstoneAlias?.pkUuid ?? nextPkUuid,
            pkId: tombstoneAlias?.pkId ?? nextPkId,
          );
        }
        // Row [targetId] is now tombstoned, so it is a dead holder. Purge
        // every alias that REDIRECTS onto it (legacyX -> targetId). Owns the
        // existing-row-by-own-id case (targetId == id); the resolved-holder case
        // (targetId != id) is additionally covered by the identity purge above.
        // This closes the dominant post-delete re-import vector: a delayed
        // legacy-id delete arriving after the holder is gone finds no alias and
        // no-ops, instead of re-resolving the stale PK identity onto a fresh
        // re-import that shares the same historical pk.created timestamp the
        // temporal bound cannot distinguish.
        //
        // Conservative-direction tradeoff (documented, accepted): this fires on
        // a REMOTE soft-delete tombstone, which is user-recoverable. If such a
        // member is later restored, its inbound aliases are already gone, so a
        // subsequent legacy-id-only delete will no-op on this device and the
        // entity survives until re-deleted. This is the codebase's stated
        // direction — "a missed delete is recoverable by deleting again" — and
        // is preferred over keeping aliases that could re-kill a re-import.
        await db.pkIdentitySyncAliasesDao.deleteByTargetRowId(
          'members',
          targetId,
        );
        await _deleteDeferredPkBackedMemberGroupEntryOpsForPkRefs(
          db,
          pkMemberUuid: tombstonePkMemberUuid,
        );
      } else if (shouldCheckPkUuidChange && priorPkUuid != nextPkUuid) {
        await requestDeferredPkEntryReplay();
      }
    },
    hardDelete: (String id) async {
      // Refuse remote deletes of the Unknown sentinel — it backs orphan-
      // classified fronting rows ("Front as Unknown" + importer/migration
      // fallbacks). The repository-level deleteMember guard covers local
      // deletes; this branch covers the sync apply path where an op from
      // an older or buggy peer could otherwise remove the sentinel locally
      // and break attributed fronting rows. Skip silently (don't throw —
      // throwing here would break the sync loop) and log so a future
      // debugger can see what happened.
      if (id == unknownSentinelMemberId) {
        developer.log(
          'refusing remote delete of Unknown sentinel ($id)',
          name: 'sync',
        );
        return;
      }
      // Resolve-on-hard-delete: if the exact-id row exists, delete it. Otherwise
      // this id may have been redirected onto a different local winner row at
      // apply time — resolve the recorded alias to the CURRENT active holder and
      // delete THAT row, then purge the alias. Without this, a delete for a
      // redirected id no-ops and the entity stays alive, permanent split-brain.
      // Redirects that predate this machinery recorded no alias, so an
      // already-lost delete stays lost — delete again on the surviving device.
      final exact = await (db.select(
        db.members,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (exact != null) {
        await (db.delete(db.members)..where((t) => t.id.equals(id))).go();
        // Purge any alias recorded for this legacy id: the legacy id has now
        // materialized as a real row and been deleted, so a stale alias would
        // otherwise let a redelivered delete re-resolve onto a NEWER same-
        // identity row (post-delete re-import) and kill it. Terminal path.
        await db.pkIdentitySyncAliasesDao.deleteByLegacyEntityId('members', id);
        // AND purge every alias whose TARGET is this now-dead row: when this id
        // was the recorded holder of a redirect (alias legacyX -> id), a later
        // delete for legacyX must NOT re-resolve the still-recorded identity
        // onto a fresh re-import of the same PK identity. The temporal bound
        // can't discriminate that case — a post-delete PK re-import keeps the
        // identical historical pk.created timestamp — so the holder dying is
        // what kills the alias; the delayed legacyX delete then no-ops.
        await db.pkIdentitySyncAliasesDao.deleteByTargetRowId('members', id);
        return;
      }
      // No exact-id row: this legacy id may have been redirected onto a holder
      // at apply time. Read the recorded alias FIRST so we keep its PK identity
      // for the purge below, then resolve it to the current active holder.
      final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
        'members',
        id,
      );
      final holderId = await _resolveMemberIdentityAliasHolder(db, id);
      if (holderId != null &&
          holderId != id &&
          holderId != unknownSentinelMemberId) {
        await (db.delete(
          db.members,
        )..where((t) => t.id.equals(holderId))).go();
        // The holder was found by re-resolving the alias identity, not
        // necessarily by its recorded target_row_id. Purge EVERY alias of this
        // identity (not just target == holderId): a sibling alias
        // whose recorded target is a DIFFERENT already-dead row of the same
        // identity would otherwise survive the holder's death and let a delayed
        // legacy-id delete re-resolve the stale identity onto a fresh re-import
        // (the historical pk.created shape the temporal bound can't exclude).
        // Identity-keyed purge mirrors the emitter's GC: the logical entity is
        // gone, so every alias of it is dead weight.
        if (alias != null) {
          await db.pkIdentitySyncAliasesDao.deleteByIdentity(
            'members',
            pkUuid: alias.pkUuid,
            pkId: alias.pkId,
          );
        }
        // GC the recorded-target aliases too: an alias recorded under an OLDER
        // identity (e.g. its uuid/pk_id since cleared by a loser-nulling merge)
        // that still targets this killed holder is dead weight by the same "the
        // logical entity is gone" argument, and the identity purge above would
        // miss it (no identity fields to match on).
        await db.pkIdentitySyncAliasesDao.deleteByTargetRowId(
          'members',
          holderId,
        );
      }
      await db.pkIdentitySyncAliasesDao.deleteByLegacyEntityId('members', id);
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.members,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'pronouns': row.pronouns,
        'emoji': row.emoji,
        'age': row.age,
        'bio': row.bio,
        'avatar_image_data': row.avatarImageData != null
            ? base64Encode(row.avatarImageData!)
            : null,
        'pk_avatar_cached_url': row.pkAvatarCachedUrl,
        'is_active': row.isActive,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'display_order': row.displayOrder,
        'is_admin': row.isAdmin,
        'custom_color_enabled': row.customColorEnabled,
        'custom_color_hex': row.customColorHex,
        'parent_system_id': row.parentSystemId,
        'pluralkit_uuid': row.pluralkitUuid,
        'pluralkit_id': row.pluralkitId,
        'pluralkit_display_name': row.pluralkitDisplayName,
        'markdown_enabled': row.markdownEnabled,
        'display_name': row.displayName,
        'birthday': row.birthday,
        'proxy_tags_json': row.proxyTagsJson,
        'pk_banner_url': row.pkBannerUrl,
        'profile_header_source': row.profileHeaderSource,
        'profile_header_layout': row.profileHeaderLayout,
        'profile_header_visible': row.profileHeaderVisible,
        'name_style_font': row.nameStyleFont,
        'name_style_bold': row.nameStyleBold,
        'name_style_italic': row.nameStyleItalic,
        'name_style_color_mode': row.nameStyleColorMode,
        'name_style_color_hex': row.nameStyleColorHex,
        'profile_header_image_data': row.profileHeaderImageData != null
            ? base64Encode(row.profileHeaderImageData!)
            : null,
        'pk_banner_image_data': row.pkBannerImageData != null
            ? base64Encode(row.pkBannerImageData!)
            : null,
        'pk_banner_cached_url': row.pkBannerCachedUrl,
        'pluralkit_sync_ignored': row.pluralkitSyncIgnored,
        'delete_push_started_at': row.deletePushStartedAt,
        'is_always_fronting': row.isAlwaysFronting,
        'is_deleted': row.isDeleted,
        'board_last_read_at': _dateTimeToSyncStringOrNull(row.boardLastReadAt),
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.members,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// fronting_sessions
// ---------------------------------------------------------------------------

DriftSyncEntity _frontingSessionsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
  DriftSyncApplyGate gate,
) {
  return DriftSyncEntity(
    tableName: 'fronting_sessions',
    toSyncFields: (dynamic row) {
      final r = row as FrontingSession;
      return {
        'start_time': _dateTimeToSyncString(r.startTime),
        'end_time': _dateTimeToSyncStringOrNull(r.endTime),
        'member_id': r.memberId,
        'notes': r.notes,
        'confidence': r.confidence,
        'session_type': r.sessionType,
        'quality': r.quality,
        'is_health_kit_import': r.isHealthKitImport,
        'pluralkit_uuid': r.pluralkitUuid,
        'pk_import_source': r.pkImportSource,
        'pk_file_switch_id': r.pkFileSwitchId,
        // Transitional. Removed in 0.8.0 with v8 cleanup. See sync_schema.dart.
        'pk_member_ids_json': r.pkMemberIdsJson,
        'delete_push_started_at': r.deletePushStartedAt,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final remoteTombstone = _isRemoteTombstone(fields);
      final shouldCheckPkIdentity =
          fields.containsKey('pluralkit_uuid') ||
          fields.containsKey('member_id');
      // Migration gate (WS1 step 4 + 5): if the per-member fronting
      // migration is `blocked` or `inProgress`, the local schema is in
      // a transitional shape (single-column unique index still in
      // place, or new-shape rows pending the post-tx sync state cutover)
      // and applying remote new-shape rows would race with the
      // in-flight migration. Surface the deferred apply through the
      // quarantine channel so the user can see what was held back —
      // silently skipping would make the deferral invisible. The
      // post-cleanup re-pair flow snapshots the converged state from
      // the migrated primary, so the deferred row reaches us through
      // bootstrap rather than the apply path.
      final refusal = gate('fronting_sessions');
      if (refusal != null && !remoteTombstone) {
        _trackMigrationGatedQuarantine(
          quarantine: quarantine,
          trackQuarantineWrite: trackQuarantineWrite,
          tableName: 'fronting_sessions',
          entityId: id,
          refusal: refusal,
        );
        return;
      }
      final existing = (remoteTombstone || shouldCheckPkIdentity)
          ? await (db.select(
              db.frontingSessions,
            )..where((t) => t.id.equals(id))).getSingleOrNull()
          : null;
      var targetId = id;
      // The alias recorded for this legacy id, read up front so the
      // resolved-holder tombstone purge below keys on the RECORDED identity
      // rather than the incoming fields' identity (a sparse tombstone payload
      // can omit pluralkit_uuid → nextPkUuid null → the identity purge would
      // silently no-op). Null when no redirect was recorded.
      PkIdentitySyncAliasRow? tombstoneAlias;
      if (remoteTombstone) {
        if (existing == null) {
          // Resolve-on-fields-tombstone: a tombstone for an id we never
          // materialized may delete a session whose ops we redirected onto a
          // different local holder row. Resolve the recorded alias to the
          // CURRENT active holder keyed on (pluralkit_uuid, member_id) and
          // tombstone it (fall through to the companion write). NO alias ->
          // keep the existing early-return exactly. Redirects that predate this
          // machinery recorded no alias — delete again on the surviving device.
          tombstoneAlias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
            'fronting_sessions',
            id,
          );
          final holderId = await _resolveFrontingIdentityAliasHolder(db, id);
          if (holderId == null || holderId == id) return;
          targetId = holderId;
        }
      }
      final nextPkUuid = fields.containsKey('pluralkit_uuid')
          ? _asString(fields['pluralkit_uuid'])
          : existing?.pluralkitUuid;
      final nextMemberId = fields.containsKey('member_id')
          ? _asString(fields['member_id'])
          : existing?.memberId;
      if (!remoteTombstone) {
        await _releaseDeletedPkIdentityHoldersForFrontingSessionApply(
          db,
          incomingId: id,
          pkUuid: nextPkUuid,
          memberId: nextMemberId,
        );
        final activeIdentityRows =
            await _activeFrontingSessionRowsByPkIdentityForApply(
              db,
              pkUuid: nextPkUuid,
              memberId: nextMemberId,
            );
        FrontingSession? targetRow;
        for (final row in activeIdentityRows) {
          if (row.id == id) {
            targetRow = row;
            break;
          }
        }
        if (targetRow == null && activeIdentityRows.isNotEmpty) {
          targetRow = activeIdentityRows.first;
        }
        if (targetRow != null) {
          targetId = targetRow.id;
          for (final row in activeIdentityRows) {
            if (row.id == targetId) continue;
            await (db.update(
              db.frontingSessions,
            )..where((t) => t.id.equals(row.id))).write(
              const FrontingSessionsCompanion(pluralkitUuid: Value(null)),
            );
          }
          // Record: persist the redirect (fronting_sessions, id ->
          // targetId) keyed on (pluralkit_uuid, member_id) so deletes resolve it
          // and the repository delete emitter fans tombstones out. Local-only;
          // no emission.
          if (targetId != id) {
            await _recordPkIdentityAliasIfNeeded(
              db,
              entityTable: 'fronting_sessions',
              legacyEntityId: id,
              pkUuid: nextPkUuid,
              memberId: nextMemberId,
              targetRowId: targetId,
            );
          }
        }
      }
      final f = _FieldContext(
        entityType: 'fronting_sessions',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = FrontingSessionsCompanion(
        id: Value(targetId),
        startTime: f.dateTimeField('start_time'),
        endTime: f.dateTimeFieldNullable('end_time'),
        memberId: f.stringFieldNullable('member_id'),
        notes: f.stringFieldNullable('notes'),
        confidence: f.intFieldNullable('confidence'),
        sessionType: f.intField('session_type'),
        quality: f.intFieldNullable('quality'),
        isHealthKitImport: f.boolField('is_health_kit_import'),
        pluralkitUuid: f.stringFieldNullable('pluralkit_uuid'),
        pkImportSource: f.stringFieldNullable('pk_import_source'),
        pkFileSwitchId: f.stringFieldNullable('pk_file_switch_id'),
        // Transitional. `stringFieldNullable` returns `Value.absent()` when
        // the payload omits the key, so a v7 peer's apply does not clobber a
        // legacy peer's value, and a legacy peer's apply still writes through.
        pkMemberIdsJson: f.stringFieldNullable('pk_member_ids_json'),
        deletePushStartedAt: f.intFieldNullable('delete_push_started_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.frontingSessions,
        companion,
        (t) => t.id.equals(targetId),
      );
      if (remoteTombstone) {
        if (targetId != id) {
          // This tombstone resolved a redirect alias onto the holder. Purge
          // the alias now that the holder is tombstoned so a redelivery of this
          // legacy-id op (re-pair snapshot, quarantine replay, full-row re-
          // emission) finds no alias and cannot re-resolve onto a NEWER same-
          // identity session (post-delete re-import) and kill it.
          await db.pkIdentitySyncAliasesDao.deleteByLegacyEntityId(
            'fronting_sessions',
            id,
          );
          // The holder was found by re-resolving the (uuid, member_id) identity,
          // so — like the resolved-holder hardDelete branch — purge by IDENTITY,
          // not just target == targetId. A sibling
          // alias recording a different already-dead session of the same
          // identity would otherwise survive and re-kill a re-import.
          //
          // Purge by pk_uuid ONLY, NOT (uuid, member_id): deleteByIdentity ORs
          // its predicates, so an extra member_id arm would sweep the redirect
          // aliases of EVERY OTHER switch sharing this member (a different
          // pluralkit_uuid) — over-purging sibling switches' aliases and dropping
          // their later legitimate resolved-holder deletes. pk_uuid alone is
          // exactly scoped: fronting aliases always carry a non-empty pk_uuid
          // (redirect recording is uuid-gated) and the resolver requires a uuid
          // match (`_activeFrontingSessionRowsByPkIdentityForApply` returns []
          // for a null uuid), so any sibling alias resolvable onto the killed
          // holder necessarily shares its uuid. Mirrors the emitter's fan-out,
          // which keys on pk_uuid only for the same reason
          // (drift_fronting_session_repository.dart:276-279).
          //
          // Key on the RECORDED alias's pk_uuid, not the incoming fields'
          // (nextPkUuid): a sparse tombstone payload can omit pluralkit_uuid,
          // which would null it and silently no-op this purge. The resolver
          // already matched on the recorded alias, so its stored uuid is the
          // authoritative discriminator. Fall back to the incoming fields only
          // when the alias somehow lacks it.
          await db.pkIdentitySyncAliasesDao.deleteByIdentity(
            'fronting_sessions',
            pkUuid: tombstoneAlias?.pkUuid ?? nextPkUuid,
          );
        }
        // Session [targetId] is now tombstoned, a dead holder. Purge every
        // alias redirecting onto it (legacyX -> targetId). Owns the existing-
        // row-by-own-id case (targetId == id); the resolved-holder case is
        // additionally covered by the identity purge above. A delayed legacyX
        // delete then finds no alias and no-ops instead of re-resolving onto a
        // fresh re-imported session of the same identity (whose historical
        // switch start time the temporal bound can't exclude). Same conservative
        // tradeoff as the members path: fires on a remote (recoverable) soft-
        // delete, so a restore-then-legacy-delete no-ops until re-deleted.
        await db.pkIdentitySyncAliasesDao.deleteByTargetRowId(
          'fronting_sessions',
          targetId,
        );
      }
    },
    hardDelete: (String id) async {
      // Resolve-on-hard-delete: delete the exact-id row when present; otherwise
      // resolve the recorded redirect alias to the current active holder keyed on
      // (pluralkit_uuid, member_id) and delete THAT row, then purge the alias.
      // Redirects that predate this machinery recorded no alias — delete again on
      // the surviving device.
      final exact = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (exact != null) {
        await (db.delete(
          db.frontingSessions,
        )..where((t) => t.id.equals(id))).go();
        // Purge any alias recorded for this legacy id: it has materialized as a
        // real row and been deleted, so a stale alias would let a redelivered
        // delete re-resolve onto a NEWER same-identity session and kill it.
        await db.pkIdentitySyncAliasesDao.deleteByLegacyEntityId(
          'fronting_sessions',
          id,
        );
        // AND purge every alias whose TARGET is this now-dead row (legacyX ->
        // id): once the recorded holder session is gone, a delayed legacyX
        // delete must no-op rather than re-resolve the stale (uuid, member_id)
        // identity onto a fresh re-imported session sharing the same historical
        // switch start time the temporal bound cannot tell apart.
        await db.pkIdentitySyncAliasesDao.deleteByTargetRowId(
          'fronting_sessions',
          id,
        );
        return;
      }
      // No exact-id row: read the recorded alias FIRST (we need its identity for
      // the purge below), then resolve it to the current active holder.
      final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
        'fronting_sessions',
        id,
      );
      final holderId = await _resolveFrontingIdentityAliasHolder(db, id);
      if (holderId != null && holderId != id) {
        await (db.delete(
          db.frontingSessions,
        )..where((t) => t.id.equals(holderId))).go();
        // Identity-keyed purge on the resolved-holder path. The holder was found
        // by re-resolving the (uuid, member_id) identity, so a sibling alias
        // whose recorded target is a different
        // already-dead session of the same identity would survive killing the
        // holder and let a delayed legacy-id delete re-resolve onto a fresh
        // re-imported session (the historical switch-start shape the temporal
        // bound can't exclude). Purge every alias of this identity, mirroring
        // the emitter's GC.
        //
        // Purge by pk_uuid ONLY, NOT (uuid, member_id): deleteByIdentity ORs its
        // predicates, so an extra member_id arm would sweep the redirect aliases
        // of EVERY OTHER switch sharing this member (a different pluralkit_uuid).
        // That regresses this very machinery — killing one switch's holder would
        // drop a SIBLING switch's alias, so that switch's later legitimate
        // resolved-holder delete permanently no-ops and its holder survives.
        // pk_uuid alone is exactly scoped: fronting aliases always carry a
        // non-empty pk_uuid (redirect recording is uuid-gated) and the resolver
        // requires a uuid match, so any sibling alias resolvable onto the killed
        // holder shares its uuid. Mirrors the emitter's pk_uuid-only fan-out
        // (drift_fronting_session_repository.dart:276-279).
        if (alias != null) {
          await db.pkIdentitySyncAliasesDao.deleteByIdentity(
            'fronting_sessions',
            pkUuid: alias.pkUuid,
          );
        }
        // GC the recorded-target aliases too: an alias recorded under an OLDER
        // identity (e.g. its uuid since cleared) that still targets this killed
        // holder is dead weight by the same "the logical entity is gone"
        // argument, and the identity purge above (uuid-only) would miss it.
        await db.pkIdentitySyncAliasesDao.deleteByTargetRowId(
          'fronting_sessions',
          holderId,
        );
      }
      await db.pkIdentitySyncAliasesDao.deleteByLegacyEntityId(
        'fronting_sessions',
        id,
      );
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'start_time': _dateTimeToSyncString(row.startTime),
        'end_time': _dateTimeToSyncStringOrNull(row.endTime),
        'member_id': row.memberId,
        'notes': row.notes,
        'confidence': row.confidence,
        'session_type': row.sessionType,
        'quality': row.quality,
        'is_health_kit_import': row.isHealthKitImport,
        'pluralkit_uuid': row.pluralkitUuid,
        'pk_import_source': row.pkImportSource,
        'pk_file_switch_id': row.pkFileSwitchId,
        // Transitional. Removed in 0.8.0 with v8 cleanup.
        'pk_member_ids_json': row.pkMemberIdsJson,
        'delete_push_started_at': row.deletePushStartedAt,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// conversations
// ---------------------------------------------------------------------------

DriftSyncEntity _conversationsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'conversations',
    toSyncFields: (dynamic row) {
      final r = row as Conversation;
      // Sparse-emit includes_all_members so pre-v25 peers don't quarantine
      // every ordinary conversation write. Older peers default to false on
      // their end since they don't know the field exists.
      return {
        'created_at': _dateTimeToSyncString(r.createdAt),
        'last_activity_at': _dateTimeToSyncString(r.lastActivityAt),
        'title': r.title,
        'emoji': r.emoji,
        'is_direct_message': r.isDirectMessage,
        'creator_id': r.creatorId,
        'participant_ids': r.participantIds,
        'archived_by_member_ids': r.archivedByMemberIds,
        'muted_by_member_ids': r.mutedByMemberIds,
        'last_read_timestamps': r.lastReadTimestamps,
        'description': r.description,
        'category_id': r.categoryId,
        'display_order': r.displayOrder,
        'is_deleted': r.isDeleted,
        if (r.includesAllMembers) 'includes_all_members': true,
        if (r.archivedForEveryone) 'archived_for_everyone': true,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'conversations',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final existing = await (db.select(
        db.conversations,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final createdAt = f.dateTimeField('created_at');
      final lastActivityAt = f.dateTimeField('last_activity_at');
      final fallbackTimestamp = DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      );
      final insertCreatedAt = createdAt.present
          ? createdAt
          : Value(fallbackTimestamp);
      final insertLastActivityAt = lastActivityAt.present
          ? lastActivityAt
          : createdAt.present
          ? Value(createdAt.value)
          : Value(fallbackTimestamp);
      if (existing == null && _isRemoteTombstone(fields)) {
        await _insertOrUpdateById(
          db,
          db.conversations,
          ConversationsCompanion(
            id: Value(id),
            createdAt: insertCreatedAt,
            lastActivityAt: insertLastActivityAt,
            isDeleted: const Value(true),
          ),
          (t) => t.id.equals(id),
        );
        return;
      }
      final companion = ConversationsCompanion(
        id: Value(id),
        createdAt: existing == null && !createdAt.present
            ? insertCreatedAt
            : createdAt,
        lastActivityAt: existing == null && !lastActivityAt.present
            ? insertLastActivityAt
            : lastActivityAt,
        title: f.stringFieldNullable('title'),
        emoji: f.stringFieldNullable('emoji'),
        isDirectMessage: f.boolField('is_direct_message'),
        creatorId: f.stringFieldNullable('creator_id'),
        participantIds: f.stringField('participant_ids'),
        archivedByMemberIds: f.stringField('archived_by_member_ids'),
        mutedByMemberIds: f.stringField('muted_by_member_ids'),
        lastReadTimestamps: f.stringField('last_read_timestamps'),
        description: f.stringFieldNullable('description'),
        categoryId: f.stringFieldNullable('category_id'),
        displayOrder: f.intField('display_order'),
        isDeleted: f.boolField('is_deleted'),
        includesAllMembers: f.boolField('includes_all_members'),
        archivedForEveryone: f.boolField('archived_for_everyone'),
      );
      await _insertOrUpdateById(
        db,
        db.conversations,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.conversations)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.conversations,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'created_at': _dateTimeToSyncString(row.createdAt),
        'last_activity_at': _dateTimeToSyncString(row.lastActivityAt),
        'title': row.title,
        'emoji': row.emoji,
        'is_direct_message': row.isDirectMessage,
        'creator_id': row.creatorId,
        'participant_ids': row.participantIds,
        'archived_by_member_ids': row.archivedByMemberIds,
        'muted_by_member_ids': row.mutedByMemberIds,
        'last_read_timestamps': row.lastReadTimestamps,
        'description': row.description,
        'category_id': row.categoryId,
        'display_order': row.displayOrder,
        'is_deleted': row.isDeleted,
        if (row.includesAllMembers) 'includes_all_members': true,
        if (row.archivedForEveryone) 'archived_for_everyone': true,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.conversations,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// chat_messages
// ---------------------------------------------------------------------------

DriftSyncEntity _chatMessagesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'chat_messages',
    toSyncFields: (dynamic row) {
      final r = row as ChatMessage;
      return {
        'content': r.content,
        'timestamp': _dateTimeToSyncString(r.timestamp),
        'is_system_message': r.isSystemMessage,
        'edited_at': _dateTimeToSyncStringOrNull(r.editedAt),
        'author_id': r.authorId,
        'conversation_id': r.conversationId,
        'reactions': r.reactions,
        'reply_to_id': r.replyToId,
        'reply_to_author_id': r.replyToAuthorId,
        'reply_to_content': r.replyToContent,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'chat_messages',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = ChatMessagesCompanion(
        id: Value(id),
        content: f.stringField('content'),
        timestamp: f.dateTimeField('timestamp'),
        isSystemMessage: f.boolField('is_system_message'),
        editedAt: f.dateTimeFieldNullable('edited_at'),
        authorId: f.stringFieldNullable('author_id'),
        conversationId: f.stringField('conversation_id'),
        reactions: f.stringField('reactions'),
        replyToId: f.stringFieldNullable('reply_to_id'),
        replyToAuthorId: f.stringFieldNullable('reply_to_author_id'),
        replyToContent: f.stringFieldNullable('reply_to_content'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.chatMessages,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      if (id.isEmpty) return;

      await db.transaction(() async {
        await (db.delete(
          db.mediaAttachments,
        )..where((t) => t.messageId.equals(id))).go();
        await (db.delete(db.chatMessages)..where((t) => t.id.equals(id))).go();
      });
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.chatMessages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'content': row.content,
        'timestamp': _dateTimeToSyncString(row.timestamp),
        'is_system_message': row.isSystemMessage,
        'edited_at': _dateTimeToSyncStringOrNull(row.editedAt),
        'author_id': row.authorId,
        'conversation_id': row.conversationId,
        'reactions': row.reactions,
        'reply_to_id': row.replyToId,
        'reply_to_author_id': row.replyToAuthorId,
        'reply_to_content': row.replyToContent,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.chatMessages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// system_settings
// ---------------------------------------------------------------------------

DriftSyncEntity _systemSettingsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'system_settings',
    toSyncFields: (dynamic row) {
      final r = row as SystemSettingsData;
      return {
        'system_name': r.systemName,
        'sharing_id': r.sharingId,
        'show_quick_front': r.showQuickFront,
        'accent_color_hex': r.accentColorHex,
        'per_member_accent_colors': r.perMemberAccentColors,
        'terminology': r.terminology,
        'custom_terminology': r.customTerminology,
        'custom_plural_terminology': r.customPluralTerminology,
        'terminology_use_english': r.terminologyUseEnglish,
        'fronting_reminders_enabled': r.frontingRemindersEnabled,
        'fronting_reminder_interval_minutes': r.frontingReminderIntervalMinutes,
        'theme_mode': r.themeMode,
        'theme_brightness': r.themeBrightness,
        'theme_style': r.themeStyle,
        'theme_corner_style': r.themeCornerStyle,
        'palette_source': r.paletteSource,
        'palette_seed_color_hex': r.paletteSeedColorHex,
        'palette_mood': r.paletteMood,
        'palette_contrast': r.paletteContrast,
        'chat_enabled': r.chatEnabled,
        'polls_enabled': r.pollsEnabled,
        'habits_enabled': r.habitsEnabled,
        'sleep_tracking_enabled': r.sleepTrackingEnabled,
        'gif_search_enabled': r.gifSearchEnabled,
        'voice_notes_enabled': r.voiceNotesEnabled,
        'sleep_suggestion_enabled': r.sleepSuggestionEnabled,
        'sleep_suggestion_hour': r.sleepSuggestionHour,
        'sleep_suggestion_minute': r.sleepSuggestionMinute,
        'wake_suggestion_enabled': r.wakeSuggestionEnabled,
        'wake_suggestion_after_hours': r.wakeSuggestionAfterHours,
        'locale_override': r.localeOverride,
        'quick_switch_threshold_seconds': r.quickSwitchThresholdSeconds,
        'identity_generation': r.identityGeneration,
        // has_completed_onboarding excluded — local-only (see applyFields)
        'chat_logs_front': r.chatLogsFront,
        'sync_theme_enabled': r.syncThemeEnabled,
        'timing_mode': r.timingMode,
        'notes_enabled': r.notesEnabled,
        'pk_group_sync_v2_enabled': r.pkGroupSyncV2Enabled,
        'system_description': r.systemDescription,
        'system_color': r.systemColor,
        'system_tag': r.systemTag,
        'system_avatar_data': r.systemAvatarData != null
            ? base64Encode(r.systemAvatarData!)
            : null,
        'reminders_enabled': r.remindersEnabled,
        'sync_navigation_enabled': r.syncNavigationEnabled,
        'nav_bar_items': r.navBarItems,
        'nav_bar_overflow_items': r.navBarOverflowItems,
        'nav_bar_label_display_mode': r.navBarLabelDisplayMode,
        'nav_bar_reveal_labels_when_expanded': r.navBarRevealLabelsWhenExpanded,
        'chat_badge_preferences': r.chatBadgePreferences,
        'habits_badge_enabled': r.habitsBadgeEnabled,
        'fronting_list_view_mode': r.frontingListViewMode,
        'add_front_default_behavior': r.addFrontDefaultBehavior,
        'quick_front_default_behavior': r.quickFrontDefaultBehavior,
        'auto_promote_long_fronting_sessions':
            r.autoPromoteLongFrontingSessions,
        'is_deleted': r.isDeleted,
        'boards_enabled': r.boardsEnabled,
        'sp_boards_backfilled_at': _dateTimeToSyncStringOrNull(
          r.spBoardsBackfilledAt,
        ),
        'bio_markdown_enabled': r.bioMarkdownEnabled,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'system_settings',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = SystemSettingsTableCompanion(
        id: Value(id),
        systemName: f.stringFieldNullable('system_name'),
        sharingId: f.stringFieldNullable('sharing_id'),
        showQuickFront: f.boolField('show_quick_front'),
        accentColorHex: f.stringField('accent_color_hex'),
        perMemberAccentColors: f.boolField('per_member_accent_colors'),
        terminology: f.intField('terminology'),
        customTerminology: f.stringFieldNullable('custom_terminology'),
        customPluralTerminology: f.stringFieldNullable(
          'custom_plural_terminology',
        ),
        terminologyUseEnglish: f.boolField('terminology_use_english'),
        frontingRemindersEnabled: f.boolField('fronting_reminders_enabled'),
        frontingReminderIntervalMinutes: f.intField(
          'fronting_reminder_interval_minutes',
        ),
        themeMode: f.intField('theme_mode'),
        themeBrightness: f.intField('theme_brightness'),
        themeStyle: f.intField('theme_style'),
        themeCornerStyle: f.intField('theme_corner_style'),
        paletteSource: f.intField('palette_source'),
        paletteSeedColorHex: f.stringField('palette_seed_color_hex'),
        paletteMood: f.intField('palette_mood'),
        paletteContrast: f.intField('palette_contrast'),
        chatEnabled: f.boolField('chat_enabled'),
        pollsEnabled: f.boolField('polls_enabled'),
        habitsEnabled: f.boolField('habits_enabled'),
        sleepTrackingEnabled: f.boolField('sleep_tracking_enabled'),
        gifSearchEnabled: f.boolField('gif_search_enabled'),
        voiceNotesEnabled: f.boolField('voice_notes_enabled'),
        sleepSuggestionEnabled: f.boolField('sleep_suggestion_enabled'),
        sleepSuggestionHour: f.intField('sleep_suggestion_hour'),
        sleepSuggestionMinute: f.intField('sleep_suggestion_minute'),
        wakeSuggestionEnabled: f.boolField('wake_suggestion_enabled'),
        wakeSuggestionAfterHours: f.realField('wake_suggestion_after_hours'),
        localeOverride: f.stringFieldNullable('locale_override'),
        quickSwitchThresholdSeconds: f.intField(
          'quick_switch_threshold_seconds',
        ),
        identityGeneration: f.intField('identity_generation'),
        // has_completed_onboarding is intentionally excluded — it must remain
        // local-only so that a remote `true` value cannot skip onboarding on a
        // new device via CRDT sync.
        chatLogsFront: f.boolField('chat_logs_front'),
        syncThemeEnabled: f.boolField('sync_theme_enabled'),
        timingMode: f.intField('timing_mode'),
        notesEnabled: f.boolField('notes_enabled'),
        pkGroupSyncV2Enabled: f.boolField('pk_group_sync_v2_enabled'),
        systemDescription: f.stringFieldNullable('system_description'),
        systemColor: f.stringFieldNullable('system_color'),
        systemTag: f.stringFieldNullable('system_tag'),
        systemAvatarData: f.blobFieldNullable('system_avatar_data'),
        remindersEnabled: f.boolField('reminders_enabled'),
        syncNavigationEnabled: f.boolField('sync_navigation_enabled'),
        navBarItems: f.stringField('nav_bar_items'),
        navBarOverflowItems: f.stringField('nav_bar_overflow_items'),
        navBarLabelDisplayMode: f.intField('nav_bar_label_display_mode'),
        navBarRevealLabelsWhenExpanded: f.boolField(
          'nav_bar_reveal_labels_when_expanded',
        ),
        chatBadgePreferences: f.stringField('chat_badge_preferences'),
        habitsBadgeEnabled: f.boolField('habits_badge_enabled'),
        frontingListViewMode: f.intField('fronting_list_view_mode'),
        addFrontDefaultBehavior: f.intField('add_front_default_behavior'),
        quickFrontDefaultBehavior: f.intField('quick_front_default_behavior'),
        autoPromoteLongFrontingSessions: f.boolField(
          'auto_promote_long_fronting_sessions',
        ),
        // Device-local fields (font*, pin*, biometric*, autoLock*) are
        // intentionally excluded from sync.
        isDeleted: f.boolField('is_deleted'),
        boardsEnabled: f.boolField('boards_enabled'),
        spBoardsBackfilledAt: f.dateTimeFieldNullable(
          'sp_boards_backfilled_at',
        ),
        bioMarkdownEnabled: f.boolField('bio_markdown_enabled'),
      );
      await _insertOrUpdateById(
        db,
        db.systemSettingsTable,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.systemSettingsTable,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.systemSettingsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'system_name': row.systemName,
        'sharing_id': row.sharingId,
        'show_quick_front': row.showQuickFront,
        'accent_color_hex': row.accentColorHex,
        'per_member_accent_colors': row.perMemberAccentColors,
        'terminology': row.terminology,
        'custom_terminology': row.customTerminology,
        'custom_plural_terminology': row.customPluralTerminology,
        'terminology_use_english': row.terminologyUseEnglish,
        'fronting_reminders_enabled': row.frontingRemindersEnabled,
        'fronting_reminder_interval_minutes':
            row.frontingReminderIntervalMinutes,
        'theme_mode': row.themeMode,
        'theme_brightness': row.themeBrightness,
        'theme_style': row.themeStyle,
        'theme_corner_style': row.themeCornerStyle,
        'palette_source': row.paletteSource,
        'palette_seed_color_hex': row.paletteSeedColorHex,
        'palette_mood': row.paletteMood,
        'palette_contrast': row.paletteContrast,
        'chat_enabled': row.chatEnabled,
        'polls_enabled': row.pollsEnabled,
        'habits_enabled': row.habitsEnabled,
        'sleep_tracking_enabled': row.sleepTrackingEnabled,
        'gif_search_enabled': row.gifSearchEnabled,
        'voice_notes_enabled': row.voiceNotesEnabled,
        'sleep_suggestion_enabled': row.sleepSuggestionEnabled,
        'sleep_suggestion_hour': row.sleepSuggestionHour,
        'sleep_suggestion_minute': row.sleepSuggestionMinute,
        'wake_suggestion_enabled': row.wakeSuggestionEnabled,
        'wake_suggestion_after_hours': row.wakeSuggestionAfterHours,
        'locale_override': row.localeOverride,
        'quick_switch_threshold_seconds': row.quickSwitchThresholdSeconds,
        'identity_generation': row.identityGeneration,
        // has_completed_onboarding excluded — local-only (see applyFields)
        'chat_logs_front': row.chatLogsFront,
        'sync_theme_enabled': row.syncThemeEnabled,
        'timing_mode': row.timingMode,
        'notes_enabled': row.notesEnabled,
        'pk_group_sync_v2_enabled': row.pkGroupSyncV2Enabled,
        'system_description': row.systemDescription,
        'system_color': row.systemColor,
        'system_tag': row.systemTag,
        'system_avatar_data': row.systemAvatarData != null
            ? base64Encode(row.systemAvatarData!)
            : null,
        'reminders_enabled': row.remindersEnabled,
        'sync_navigation_enabled': row.syncNavigationEnabled,
        'nav_bar_items': row.navBarItems,
        'nav_bar_overflow_items': row.navBarOverflowItems,
        'nav_bar_label_display_mode': row.navBarLabelDisplayMode,
        'nav_bar_reveal_labels_when_expanded':
            row.navBarRevealLabelsWhenExpanded,
        'chat_badge_preferences': row.chatBadgePreferences,
        'habits_badge_enabled': row.habitsBadgeEnabled,
        'fronting_list_view_mode': row.frontingListViewMode,
        'add_front_default_behavior': row.addFrontDefaultBehavior,
        'quick_front_default_behavior': row.quickFrontDefaultBehavior,
        'auto_promote_long_fronting_sessions':
            row.autoPromoteLongFrontingSessions,
        'is_deleted': row.isDeleted,
        'boards_enabled': row.boardsEnabled,
        'sp_boards_backfilled_at': _dateTimeToSyncStringOrNull(
          row.spBoardsBackfilledAt,
        ),
        'bio_markdown_enabled': row.bioMarkdownEnabled,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.systemSettingsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// app_preference_values
// ---------------------------------------------------------------------------

DriftSyncEntity _appPreferenceValuesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'app_preference_values',
    entityIdFor: (dynamic row) => (row as AppPreferenceValueRow).key,
    toSyncFields: (dynamic row) {
      final r = row as AppPreferenceValueRow;
      return {
        'value_type': r.valueType,
        'value_json': r.valueJson,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'app_preference_values',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = AppPreferenceValuesCompanion(
        key: Value(id),
        valueType: f.stringField('value_type'),
        valueJson: f.stringFieldNullable('value_json'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.appPreferenceValues,
        companion,
        (t) => t.key.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.appPreferenceValues,
      )..where((t) => t.key.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.appPreferenceValues,
      )..where((t) => t.key.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'value_type': row.valueType,
        'value_json': row.valueJson,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.appPreferenceValues,
      )..where((t) => t.key.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// member_profile_preference_values
// ---------------------------------------------------------------------------

DriftSyncEntity _memberProfilePreferenceValuesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'member_profile_preference_values',
    toSyncFields: (dynamic row) {
      final r = row as MemberProfilePreferenceValueRow;
      return {
        'member_id': r.memberId,
        'key': r.key,
        'value_type': r.valueType,
        'value_json': r.valueJson,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'member_profile_preference_values',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = MemberProfilePreferenceValuesCompanion(
        id: Value(id),
        memberId: f.stringField('member_id'),
        key: f.stringField('key'),
        valueType: f.stringField('value_type'),
        valueJson: f.stringFieldNullable('value_json'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateMemberProfilePreferenceValueForApply(
        db,
        id,
        companion,
        fields,
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.memberProfilePreferenceValues,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.memberProfilePreferenceValues,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'member_id': row.memberId,
        'key': row.key,
        'value_type': row.valueType,
        'value_json': row.valueJson,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.memberProfilePreferenceValues,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// polls
// ---------------------------------------------------------------------------

DriftSyncEntity _pollsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'polls',
    toSyncFields: (dynamic row) {
      final r = row as Poll;
      return {
        'question': r.question,
        'description': r.description,
        'is_anonymous': r.isAnonymous,
        'allows_multiple_votes': r.allowsMultipleVotes,
        'is_closed': r.isClosed,
        'expires_at': _dateTimeToSyncStringOrNull(r.expiresAt),
        'created_at': _dateTimeToSyncString(r.createdAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'polls',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = PollsCompanion(
        id: Value(id),
        question: f.stringField('question'),
        description: f.stringFieldNullable('description'),
        isAnonymous: f.boolField('is_anonymous'),
        allowsMultipleVotes: f.boolField('allows_multiple_votes'),
        isClosed: f.boolField('is_closed'),
        expiresAt: f.dateTimeFieldNullable('expires_at'),
        createdAt: f.dateTimeField('created_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.polls,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.polls)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.polls,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'question': row.question,
        'description': row.description,
        'is_anonymous': row.isAnonymous,
        'allows_multiple_votes': row.allowsMultipleVotes,
        'is_closed': row.isClosed,
        'expires_at': _dateTimeToSyncStringOrNull(row.expiresAt),
        'created_at': _dateTimeToSyncString(row.createdAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.polls,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// poll_options
// ---------------------------------------------------------------------------

DriftSyncEntity _pollOptionsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'poll_options',
    toSyncFields: (dynamic row) {
      final r = row as PollOption;
      return {
        'poll_id': r.pollId,
        'option_text': r.optionText,
        'sort_order': r.sortOrder,
        'is_other_option': r.isOtherOption,
        'color_hex': r.colorHex,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'poll_options',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = PollOptionsCompanion(
        id: Value(id),
        pollId: f.stringField('poll_id'),
        optionText: f.stringField('option_text'),
        sortOrder: f.intField('sort_order'),
        isOtherOption: f.boolField('is_other_option'),
        colorHex: f.stringFieldNullable('color_hex'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.pollOptions,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.pollOptions)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.pollOptions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'poll_id': row.pollId,
        'option_text': row.optionText,
        'sort_order': row.sortOrder,
        'is_other_option': row.isOtherOption,
        'color_hex': row.colorHex,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.pollOptions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// poll_votes
// ---------------------------------------------------------------------------

DriftSyncEntity _pollVotesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'poll_votes',
    toSyncFields: (dynamic row) {
      final r = row as PollVote;
      return {
        'poll_option_id': r.pollOptionId,
        'member_id': r.memberId,
        'voted_at': _dateTimeToSyncString(r.votedAt),
        'response_text': r.responseText,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'poll_votes',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = PollVotesCompanion(
        id: Value(id),
        pollOptionId: f.stringField('poll_option_id'),
        memberId: f.stringField('member_id'),
        votedAt: f.dateTimeField('voted_at'),
        responseText: f.stringFieldNullable('response_text'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.pollVotes,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.pollVotes)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.pollVotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'poll_option_id': row.pollOptionId,
        'member_id': row.memberId,
        'voted_at': _dateTimeToSyncString(row.votedAt),
        'response_text': row.responseText,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.pollVotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// habits
// ---------------------------------------------------------------------------

DriftSyncEntity _habitsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'habits',
    toSyncFields: (dynamic row) {
      final r = row as Habit;
      return {
        'name': r.name,
        'description': r.description,
        'icon': r.icon,
        'color_hex': r.colorHex,
        'is_active': r.isActive,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'modified_at': _dateTimeToSyncString(r.modifiedAt),
        'frequency': r.frequency,
        'weekly_days': r.weeklyDays,
        'interval_days': r.intervalDays,
        'reminder_time': r.reminderTime,
        'notifications_enabled': r.notificationsEnabled,
        'notification_message': r.notificationMessage,
        'assigned_member_id': r.assignedMemberId,
        'only_notify_when_fronting': r.onlyNotifyWhenFronting,
        'is_private': r.isPrivate,
        'current_streak': r.currentStreak,
        'best_streak': r.bestStreak,
        'total_completions': r.totalCompletions,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'habits',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = HabitsCompanion(
        id: Value(id),
        name: f.stringField('name'),
        description: f.stringFieldNullable('description'),
        icon: f.stringFieldNullable('icon'),
        colorHex: f.stringFieldNullable('color_hex'),
        isActive: f.boolField('is_active'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        frequency: f.stringField('frequency'),
        weeklyDays: f.stringFieldNullable('weekly_days'),
        intervalDays: f.intFieldNullable('interval_days'),
        reminderTime: f.stringFieldNullable('reminder_time'),
        notificationsEnabled: f.boolField('notifications_enabled'),
        notificationMessage: f.stringFieldNullable('notification_message'),
        assignedMemberId: f.stringFieldNullable('assigned_member_id'),
        onlyNotifyWhenFronting: f.boolField('only_notify_when_fronting'),
        isPrivate: f.boolField('is_private'),
        currentStreak: f.intField('current_streak'),
        bestStreak: f.intField('best_streak'),
        totalCompletions: f.intField('total_completions'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.habits,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.habits)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.habits,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'description': row.description,
        'icon': row.icon,
        'color_hex': row.colorHex,
        'is_active': row.isActive,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'modified_at': _dateTimeToSyncString(row.modifiedAt),
        'frequency': row.frequency,
        'weekly_days': row.weeklyDays,
        'interval_days': row.intervalDays,
        'reminder_time': row.reminderTime,
        'notifications_enabled': row.notificationsEnabled,
        'notification_message': row.notificationMessage,
        'assigned_member_id': row.assignedMemberId,
        'only_notify_when_fronting': row.onlyNotifyWhenFronting,
        'is_private': row.isPrivate,
        'current_streak': row.currentStreak,
        'best_streak': row.bestStreak,
        'total_completions': row.totalCompletions,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.habits,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// habit_completions
// ---------------------------------------------------------------------------

DriftSyncEntity _habitCompletionsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'habit_completions',
    toSyncFields: (dynamic row) {
      final r = row as HabitCompletion;
      return {
        'habit_id': r.habitId,
        'completed_at': _dateTimeToSyncString(r.completedAt),
        'completed_by_member_id': r.completedByMemberId,
        'notes': r.notes,
        'was_fronting': r.wasFronting,
        'rating': r.rating,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'modified_at': _dateTimeToSyncString(r.modifiedAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'habit_completions',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = HabitCompletionsCompanion(
        id: Value(id),
        habitId: f.stringField('habit_id'),
        completedAt: f.dateTimeField('completed_at'),
        completedByMemberId: f.stringFieldNullable('completed_by_member_id'),
        notes: f.stringFieldNullable('notes'),
        wasFronting: f.boolField('was_fronting'),
        rating: f.intFieldNullable('rating'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.habitCompletions,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.habitCompletions,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.habitCompletions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'habit_id': row.habitId,
        'completed_at': _dateTimeToSyncString(row.completedAt),
        'completed_by_member_id': row.completedByMemberId,
        'notes': row.notes,
        'was_fronting': row.wasFronting,
        'rating': row.rating,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'modified_at': _dateTimeToSyncString(row.modifiedAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.habitCompletions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// conversation_categories
// ---------------------------------------------------------------------------

DriftSyncEntity _conversationCategoriesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'conversation_categories',
    toSyncFields: (dynamic row) {
      final r = row as ConversationCategoryRow;
      return {
        'name': r.name,
        'display_order': r.displayOrder,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'modified_at': _dateTimeToSyncString(r.modifiedAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'conversation_categories',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = ConversationCategoriesCompanion(
        id: Value(id),
        name: f.stringField('name'),
        displayOrder: f.intField('display_order'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.conversationCategories,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.conversationCategories,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.conversationCategories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'display_order': row.displayOrder,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'modified_at': _dateTimeToSyncString(row.modifiedAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.conversationCategories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// reminders
// ---------------------------------------------------------------------------

DriftSyncEntity _remindersEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'reminders',
    toSyncFields: (dynamic row) {
      final r = row as ReminderRow;
      return {
        'name': r.name,
        'message': r.message,
        'trigger': r.trigger,
        'frequency': r.frequency,
        'interval_days': r.intervalDays,
        'weekly_days': r.weeklyDays,
        'time_of_day': r.timeOfDay,
        'delay_hours': r.delayHours,
        'target_member_id': r.targetMemberId,
        'is_active': r.isActive,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'modified_at': _dateTimeToSyncString(r.modifiedAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'reminders',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = RemindersCompanion(
        id: Value(id),
        name: f.stringField('name'),
        message: f.stringField('message'),
        trigger: f.intField('trigger'),
        frequency: f.stringFieldNullable('frequency'),
        intervalDays: f.intFieldNullable('interval_days'),
        weeklyDays: f.stringFieldNullable('weekly_days'),
        timeOfDay: f.stringFieldNullable('time_of_day'),
        delayHours: f.intFieldNullable('delay_hours'),
        targetMemberId: f.stringFieldNullable('target_member_id'),
        isActive: f.boolField('is_active'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.reminders,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.reminders)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.reminders,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'message': row.message,
        'trigger': row.trigger,
        'frequency': row.frequency,
        'interval_days': row.intervalDays,
        'weekly_days': row.weeklyDays,
        'time_of_day': row.timeOfDay,
        'delay_hours': row.delayHours,
        'target_member_id': row.targetMemberId,
        'is_active': row.isActive,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'modified_at': _dateTimeToSyncString(row.modifiedAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.reminders,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// member_groups
// ---------------------------------------------------------------------------

DriftSyncEntity _memberGroupsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
  Future<void> Function() requestDeferredPkEntryReplay,
) {
  return DriftSyncEntity(
    tableName: 'member_groups',
    entityIdFor: (dynamic row) {
      final r = row as MemberGroupRow;
      final pkUuid = r.pluralkitUuid;
      if (pkUuid != null && pkUuid.isNotEmpty) {
        // Generation-aware: a revived group (sync_generation>=1) is keyed by
        // its `pk-group-g<N>:<uuid>` incarnation, not the burned legacy id.
        return deriveGroupIncarnationEntityId(pkUuid, r.syncGeneration);
      }
      return r.id;
    },
    toSyncFields: (dynamic row) {
      final r = row as MemberGroupRow;
      return {
        'name': r.name,
        'description': r.description,
        'color_hex': r.colorHex,
        'emoji': r.emoji,
        'avatar_image_data': r.avatarImageData != null
            ? base64Encode(r.avatarImageData!)
            : null,
        'display_order': r.displayOrder,
        'parent_group_id': r.parentGroupId,
        'group_type': r.groupType,
        'filter_rules': r.filterRules,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'pluralkit_id': r.pluralkitId,
        'pluralkit_uuid': r.pluralkitUuid,
        'last_seen_from_pk_at': _dateTimeToSyncStringOrNull(r.lastSeenFromPkAt),
        // Sanitized so locally-corrupt rows can't propagate to peers.
        // See [sanitizeSortStateForEmission] for the full rationale.
        'sort_state': sanitizeSortStateForEmission(
          r.sortState,
          contextId: r.id,
        ),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'member_groups',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final resolvedPkGroupUuid =
          _asString(fields['pluralkit_uuid']) ??
          _pkGroupUuidFromAnyEntityId(id) ??
          (await _pkGroupAliasForLegacyEntityId(db, id))?.pkGroupUuid;
      final existingRow = await _resolveMemberGroupRowForSyncId(
        db,
        id,
        payloadPkGroupUuid: resolvedPkGroupUuid,
      );
      final localRowId = existingRow?.id ?? id;
      final tombstonePkGroupUuid =
          resolvedPkGroupUuid ?? existingRow?.pluralkitUuid;
      if (existingRow == null && _isRemoteTombstone(fields)) {
        final createdAt = f.dateTimeField('created_at');
        final fallbackTimestamp = DateTime.fromMillisecondsSinceEpoch(
          0,
          isUtc: true,
        );
        await _deleteDeferredPkBackedMemberGroupEntryOpsForPkRefs(
          db,
          pkGroupUuid: tombstonePkGroupUuid,
        );
        await _insertOrUpdateById(
          db,
          db.memberGroups,
          MemberGroupsCompanion(
            id: Value(localRowId),
            name: fields.containsKey('name')
                ? f.stringField('name')
                : const Value(''),
            createdAt: createdAt.present ? createdAt : Value(fallbackTimestamp),
            pluralkitUuid: fields.containsKey('pluralkit_uuid')
                ? f.stringFieldNullable('pluralkit_uuid')
                : resolvedPkGroupUuid != null
                ? Value(resolvedPkGroupUuid)
                : const Value.absent(),
            sortState: _validatedSortStateValue(id, fields),
            isDeleted: const Value(true),
          ),
          (t) => t.id.equals(localRowId),
        );
        if (tombstonePkGroupUuid != null && tombstonePkGroupUuid.isNotEmpty) {
          await _recordPkGroupAliasIfNeeded(
            db,
            legacyEntityId: id,
            pkGroupUuid: tombstonePkGroupUuid,
          );
        }
        return;
      }
      // Sanctioned revive: parse the incoming group incarnation generation
      // and, when it is strictly newer than the matched local row's stored
      // generation, advance the local row to that incarnation so its own
      // future emits target the live id (and the now-explicit is_deleted=false
      // payload revives it). A lower/equal incoming generation never demotes
      // the row — Value.absent leaves sync_generation unchanged.
      final incomingGroupGen =
          parseGroupIncarnationEntityId(id)?.generation ?? 0;
      final localGroupGen = existingRow?.syncGeneration ?? 0;
      final syncGenerationValue = incomingGroupGen > localGroupGen
          ? Value(incomingGroupGen)
          : const Value<int>.absent();
      // Family invariant (generation-aware): an older-incarnation op —
      // including a fields-borne is_deleted=true tombstone re-pushed by
      // sync_bootstrap or replayed from quarantine — must never delete or mutate
      // the live state of a strictly-newer incarnation row. When the matched
      // local row already lives at a newer generation, leave is_deleted
      // untouched so a stale gen-(<N) tombstone can't tombstone the gen-N group.
      // An at-or-newer op applies is_deleted as sent (the sanctioned revive
      // carries is_deleted=false; a same/newer delete tombstones normally).
      final groupIsDeletedValue = incomingGroupGen < localGroupGen
          ? const Value<bool>.absent()
          : f.boolField('is_deleted');
      final companion = MemberGroupsCompanion(
        id: Value(localRowId),
        name: f.stringField('name'),
        description: f.stringFieldNullable('description'),
        colorHex: f.stringFieldNullable('color_hex'),
        emoji: f.stringFieldNullable('emoji'),
        avatarImageData: fields.containsKey('avatar_image_data')
            ? f.blobFieldNullable('avatar_image_data')
            : const Value.absent(),
        displayOrder: f.intField('display_order'),
        parentGroupId: f.stringFieldNullable('parent_group_id'),
        groupType: f.intField('group_type'),
        filterRules: f.stringFieldNullable('filter_rules'),
        createdAt: f.dateTimeField('created_at'),
        pluralkitId: f.stringFieldNullable('pluralkit_id'),
        pluralkitUuid: fields.containsKey('pluralkit_uuid')
            ? f.stringFieldNullable('pluralkit_uuid')
            : resolvedPkGroupUuid != null
            ? Value(resolvedPkGroupUuid)
            : const Value.absent(),
        lastSeenFromPkAt: f.dateTimeFieldNullable('last_seen_from_pk_at'),
        sortState: _validatedSortStateValue(id, fields),
        isDeleted: groupIsDeletedValue,
        syncGeneration: syncGenerationValue,
      );
      await _insertOrUpdateById(
        db,
        db.memberGroups,
        companion,
        (t) => t.id.equals(localRowId),
      );
      if (resolvedPkGroupUuid != null && resolvedPkGroupUuid.isNotEmpty) {
        // Only record an alias for the *incoming* entity id when it is a
        // genuinely-legacy id (the helper filters out canonical). Do NOT
        // auto-record an alias for the receiving device's own local row id:
        // both peers end up with `pk-group-<uuid>` after import, and aliasing
        // that id makes later alias-delete emits hard-delete the peer's active
        // PK-group row. The helper also covers the incarnation id
        // (`pk-group-g<N>:<uuid>`): aliasing it so a later sparse patch under
        // that id resolves back to this local row.
        await _recordPkGroupAliasIfNeeded(
          db,
          legacyEntityId: id,
          pkGroupUuid: resolvedPkGroupUuid,
        );
      }
      if (_isRemoteTombstone(fields)) {
        await _deleteDeferredPkBackedMemberGroupEntryOpsForPkRefs(
          db,
          pkGroupUuid: tombstonePkGroupUuid,
        );
      } else {
        await requestDeferredPkEntryReplay();
      }
    },
    hardDelete: (String id) async {
      final row = await _resolveMemberGroupRowForSyncDelete(db, id);
      if (row == null) return;
      // Generation guard: a tombstone for an OLDER incarnation must not delete
      // a row that already lives at a newer incarnation — that is the
      // tombstone-then-revive flap (e.g. the burned gen-0 'pk-group:<uuid>'
      // tombstone re-delivered after the row was revived to gen 1). Skip when
      // the resolved row's stored generation is strictly newer than the
      // incoming tombstone's. A non-incarnation id parses to gen 0, matching a
      // gen-0 row, so legacy deletes are unaffected.
      final incomingGen = parseGroupIncarnationEntityId(id)?.generation ?? 0;
      if (row.syncGeneration > incomingGen) return;
      await (db.delete(
        db.memberGroups,
      )..where((t) => t.id.equals(row.id))).go();
    },
    readRow: (String id) async {
      final row = await _resolveMemberGroupRowForSyncId(db, id);
      if (row == null) return null;
      return {
        'name': row.name,
        'description': row.description,
        'color_hex': row.colorHex,
        'emoji': row.emoji,
        'avatar_image_data': row.avatarImageData != null
            ? base64Encode(row.avatarImageData!)
            : null,
        'display_order': row.displayOrder,
        'parent_group_id': row.parentGroupId,
        'group_type': row.groupType,
        'filter_rules': row.filterRules,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'pluralkit_id': row.pluralkitId,
        'pluralkit_uuid': row.pluralkitUuid,
        'last_seen_from_pk_at': _dateTimeToSyncStringOrNull(
          row.lastSeenFromPkAt,
        ),
        'sort_state': sanitizeSortStateForEmission(
          row.sortState,
          contextId: row.id,
        ),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await _resolveMemberGroupRowForSyncId(db, id);
      return row?.isDeleted ?? true;
    },
  );
}

/// Apply-time validator for the incoming `sort_state` field on
/// `member_groups`. This is the primary defense against garbage `sort_state`
/// payloads from peers — invalid strings are rejected here so they never
/// reach the local column, which means a subsequent local write
/// (`_groupFields(row)`) can never round-trip the garbage back to peers.
///
/// Rules (matching the shared decoder [tryDecodeSortState]):
///   - absent from the incoming map → [Value.absent] (older peer that does
///     not know the field; local column keeps its previous valid value).
///   - present and decodes successfully → write through the *original*
///     string byte-for-byte (no re-encode). Keeping the wire string
///     identical avoids spurious peer-vs-peer merge churn.
///   - present and decode fails → [Value.absent] and a warn log entry.
///     Unknown enum modes are NOT failures (forward-compatible).
Value<String> _validatedSortStateValue(
  String entityId,
  Map<String, dynamic> fields,
) {
  if (!fields.containsKey('sort_state')) return const Value.absent();
  final raw = fields['sort_state'];
  if (raw is! String) {
    ErrorReportingService.instance.report(
      'member_groups sort_state decode failed: '
      'expected String, got ${raw?.runtimeType ?? 'null'} '
      '(entityId=$entityId)',
      severity: ErrorSeverity.warning,
    );
    return const Value.absent();
  }
  final decoded = tryDecodeSortState(raw);
  if (decoded == null) {
    ErrorReportingService.instance.report(
      'member_groups sort_state decode failed: invalid JSON shape '
      '(entityId=$entityId, raw=${_truncateSortState(raw)})',
      severity: ErrorSeverity.warning,
    );
    return const Value.absent();
  }
  // Pass the original string through unchanged. Decoded successfully → its
  // bytes are already valid, so other-device-vs-other-device merges stay
  // stable.
  return Value(raw);
}

String _truncateSortState(String s) =>
    s.length > 120 ? '${s.substring(0, 120)}...' : s;

// ---------------------------------------------------------------------------
// member_group_entries
// ---------------------------------------------------------------------------

DriftSyncEntity _memberGroupEntriesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'member_group_entries',
    entityIdFor: (dynamic row) {
      final r = row as MemberGroupEntryRow;
      final g = r.pkGroupUuid?.trim() ?? '';
      final m = r.pkMemberUuid?.trim() ?? '';
      if (g.isEmpty || m.isEmpty) return r.id;
      // Generation-aware: a revived entry (sync_generation>=1) is keyed by
      // its salted incarnation sha, not the burned gen-0 sha.
      return deriveEntryIncarnationEntityId(g, m, r.syncGeneration) ?? r.id;
    },
    toSyncFields: (dynamic row) {
      final dynamic r = row;
      final fields = <String, dynamic>{
        'group_id': r.groupId,
        'member_id': r.memberId,
        'is_deleted': r.isDeleted,
      };
      final pkGroupUuid = _readOptionalStringProperty(() => r.pkGroupUuid);
      if (pkGroupUuid.present) {
        fields['pk_group_uuid'] = pkGroupUuid.value;
      }
      final pkMemberUuid = _readOptionalStringProperty(() => r.pkMemberUuid);
      if (pkMemberUuid.present) {
        fields['pk_member_uuid'] = pkMemberUuid.value;
      }
      return fields;
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final applied = await _applyMemberGroupEntryFields(
        db,
        id: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
        allowDeferral: true,
      );
      final logicalEdge = _pkMemberGroupEntryLogicalEdgeFromFields(fields);
      if (applied &&
          logicalEdge != null &&
          _isCanonicalPkMemberGroupEntryEntityId(id, logicalEdge)) {
        await _deleteDeferredPkBackedMemberGroupEntryOpsForLogicalEdge(
          db,
          edge: logicalEdge,
        );
      }
    },
    hardDelete: (String id) async {
      if (await _tableExists(db, _pkGroupEntryDeferredOpsTableName)) {
        await db.pkGroupEntryDeferredSyncOpsDao.deleteById(
          'member_group_entries:$id',
        );
        await _deleteDeferredPkBackedMemberGroupEntryOpsForCanonicalEntityId(
          db,
          entityId: id,
        );
        final logicalEdge = await _memberGroupEntryPkEdgeById(db, id);
        if (logicalEdge != null &&
            _isCanonicalPkMemberGroupEntryEntityId(id, logicalEdge)) {
          await _deleteDeferredPkBackedMemberGroupEntryOpsForLogicalEdge(
            db,
            edge: logicalEdge,
          );
        }
      }
      // Generation-aware logical delete. Resolve the edge + generation the
      // incoming tombstone addresses even when no row sits at the wire id (the
      // canonical-collapse case: the live edge re-rooted onto the gen-0 sha
      // while carrying sync_generation=N, so a legitimate gen-N tombstone keyed
      // by the gen-N sha would otherwise find nothing and the edge would live
      // forever on this device).
      final target = await _resolveEntryTombstoneTarget(db, id);
      if (target == null) {
        // Non-PK / unresolvable id: legacy delete-by-exact-id (random v4 ids
        // never collide, so this is exact and correct).
        await (db.delete(
          db.memberGroupEntries,
        )..where((t) => t.id.equals(id))).go();
        return;
      }
      // Generation guard: a tombstone for an OLDER incarnation must not delete a
      // row living at a newer incarnation — the tombstone-then-revive flap (a
      // burned gen-N entry tombstone re-delivered after the edge was revived to
      // gen N+1). Skip when the live row for the edge is strictly newer.
      final liveRow = await _activeMemberGroupEntryByPkRefs(
        db,
        pkGroupUuid: target.edge.pkGroupUuid,
        pkMemberUuid: target.edge.pkMemberUuid,
      );
      if (liveRow != null &&
          liveRow.syncGeneration > target.incomingGeneration) {
        return;
      }
      // Delete the row that carries the tombstone's exact generation, resolved
      // by logical edge regardless of its Drift PK. Fall back to delete-by-id
      // when no edge row matches the generation (e.g. the row was keyed by the
      // wire id directly).
      final targetRow = await _memberGroupEntryByPkRefsAndGeneration(
        db,
        pkGroupUuid: target.edge.pkGroupUuid,
        pkMemberUuid: target.edge.pkMemberUuid,
        generation: target.incomingGeneration,
      );
      final deleteId = targetRow?.id ?? id;
      await (db.delete(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(deleteId))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      final fields = <String, dynamic>{
        'group_id': row.groupId,
        'member_id': row.memberId,
        'is_deleted': row.isDeleted,
      };
      await _appendMemberGroupEntryPkFields(db, id, fields);
      return fields;
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// custom_fields
// ---------------------------------------------------------------------------

DriftSyncEntity _customFieldsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'custom_fields',
    toSyncFields: (dynamic row) {
      final r = row as CustomFieldRow;
      return {
        'name': r.name,
        'field_type': r.fieldType,
        'field_type_id': r.fieldTypeId,
        'parent_field_id': r.parentFieldId,
        'type_config_json': r.typeConfigJson,
        'date_precision': r.datePrecision,
        'display_order': r.displayOrder,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'custom_fields',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      // Sync-inbound parent_field_id validation. The write-side
      // `createField` / `moveFieldToParent` paths enforce depth-1 and
      // reject self-loops; the sync apply path historically wrote the
      // value verbatim, letting a buggy or malicious peer plant a
      // self-cycle or a depth-2 (grandchild) row into local storage and
      // re-emit it to every other peer. Render-time promotion in
      // `lib/features/custom_fields/orphan_promotion.dart` hid the
      // corruption from the UI but the rows still propagated.
      //
      // Normalize-to-null over reject to keep peers from wedging each
      // other: a malformed parent reference becomes a top-level row
      // (recoverable via a normal move) rather than a stuck apply.
      // Missing-parent / non-group-parent are tolerated verbatim
      // because sync apply order is non-deterministic — the parent may
      // arrive in a later event, and render-time promotion handles the
      // gap gracefully until then.
      final parentValue = await _normalizeCustomFieldParentForApply(
        db,
        childId: id,
        rawParent: f.stringFieldNullable('parent_field_id'),
      );
      final companion = CustomFieldsCompanion(
        id: Value(id),
        name: f.stringField('name'),
        fieldType: f.intField('field_type'),
        fieldTypeId: f.stringFieldNullable('field_type_id'),
        parentFieldId: parentValue,
        typeConfigJson: f.stringFieldNullable('type_config_json'),
        datePrecision: f.intFieldNullable('date_precision'),
        displayOrder: f.intField('display_order'),
        createdAt: f.dateTimeField('created_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.customFields,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.customFields)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.customFields,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'field_type': row.fieldType,
        'field_type_id': row.fieldTypeId,
        'parent_field_id': row.parentFieldId,
        'type_config_json': row.typeConfigJson,
        'date_precision': row.datePrecision,
        'display_order': row.displayOrder,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.customFields,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// custom_field_values
// ---------------------------------------------------------------------------

DriftSyncEntity _customFieldValuesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'custom_field_values',
    toSyncFields: (dynamic row) {
      final r = row as CustomFieldValueRow;
      return {
        'custom_field_id': r.customFieldId,
        'member_id': r.memberId,
        'value': r.value,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'custom_field_values',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = CustomFieldValuesCompanion(
        id: Value(id),
        customFieldId: f.stringField('custom_field_id'),
        memberId: f.stringField('member_id'),
        value: f.stringField('value'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateCustomFieldValueForApply(db, id, companion, fields);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.customFieldValues,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.customFieldValues,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'custom_field_id': row.customFieldId,
        'member_id': row.memberId,
        'value': row.value,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.customFieldValues,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// notes
// ---------------------------------------------------------------------------

DriftSyncEntity _notesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'notes',
    toSyncFields: (dynamic row) {
      final r = row as NoteRow;
      return {
        'title': r.title,
        'body': r.body,
        'color_hex': r.colorHex,
        'member_id': r.memberId,
        'date': _dateTimeToSyncString(r.date),
        'created_at': _dateTimeToSyncString(r.createdAt),
        'modified_at': _dateTimeToSyncString(r.modifiedAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'notes',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = NotesCompanion(
        id: Value(id),
        title: f.stringField('title'),
        body: f.stringField('body'),
        colorHex: f.stringFieldNullable('color_hex'),
        memberId: f.stringFieldNullable('member_id'),
        date: f.dateTimeField('date'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.notes,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.notes)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.notes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'title': row.title,
        'body': row.body,
        'color_hex': row.colorHex,
        'member_id': row.memberId,
        'date': _dateTimeToSyncString(row.date),
        'created_at': _dateTimeToSyncString(row.createdAt),
        'modified_at': _dateTimeToSyncString(row.modifiedAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.notes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// front_session_comments
// ---------------------------------------------------------------------------

DriftSyncEntity _frontSessionCommentsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
  DriftSyncApplyGate gate,
) {
  return DriftSyncEntity(
    tableName: 'front_session_comments',
    toSyncFields: (dynamic row) {
      final r = row as FrontSessionCommentRow;
      return {
        'session_id': r.sessionId,
        'body': r.body,
        'timestamp': _dateTimeToSyncString(r.timestamp),
        'created_at': _dateTimeToSyncString(r.createdAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final remoteTombstone = _isRemoteTombstone(fields);
      // Migration gate — same rationale as fronting_sessions above.
      // Comments live on the same migration boundary; new-shape comment
      // rows depend on the new fronting_sessions shape being in place.
      // Surface deferred applies through quarantine instead of silent
      // skip so the user can audit what was held back.
      final refusal = gate('front_session_comments');
      if (refusal != null && !remoteTombstone) {
        _trackMigrationGatedQuarantine(
          quarantine: quarantine,
          trackQuarantineWrite: trackQuarantineWrite,
          tableName: 'front_session_comments',
          entityId: id,
          refusal: refusal,
        );
        return;
      }
      final f = _FieldContext(
        entityType: 'front_session_comments',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final existing = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (remoteTombstone && existing == null) {
        return;
      }
      final sessionId = f.stringField('session_id');
      if (sessionId.present && sessionId.value.trim().isEmpty) {
        _trackInvalidFrontSessionCommentSessionId(
          quarantine: quarantine,
          trackQuarantineWrite: trackQuarantineWrite,
          entityId: id,
          fields: fields,
          missing: false,
        );
        return;
      }
      if (!sessionId.present && existing == null) {
        _trackInvalidFrontSessionCommentSessionId(
          quarantine: quarantine,
          trackQuarantineWrite: trackQuarantineWrite,
          entityId: id,
          fields: fields,
          missing: true,
        );
        return;
      }
      final companion = FrontSessionCommentsCompanion(
        id: Value(id),
        sessionId: sessionId,
        body: f.stringField('body'),
        timestamp: f.dateTimeField('timestamp'),
        createdAt: f.dateTimeField('created_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.frontSessionComments,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.frontSessionComments,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'session_id': row.sessionId,
        'body': row.body,
        'timestamp': _dateTimeToSyncString(row.timestamp),
        'created_at': _dateTimeToSyncString(row.createdAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// friends
// ---------------------------------------------------------------------------

DriftSyncEntity _friendsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'friends',
    toSyncFields: (dynamic row) {
      final r = row as FriendRow;
      return {
        'display_name': r.displayName,
        'peer_sharing_id': r.peerSharingId,
        'pairwise_secret': r.pairwiseSecret != null
            ? base64Encode(r.pairwiseSecret!)
            : null,
        'pinned_identity': r.pinnedIdentity != null
            ? base64Encode(r.pinnedIdentity!)
            : null,
        'offered_scopes': r.offeredScopes,
        'public_key_hex': r.publicKeyHex,
        'shared_secret_hex': r.sharedSecretHex,
        'granted_scopes': r.grantedScopes,
        'is_verified': r.isVerified,
        'init_id': r.initId,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'established_at': _dateTimeToSyncStringOrNull(r.establishedAt),
        'last_sync_at': _dateTimeToSyncStringOrNull(r.lastSyncAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'friends',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = FriendsCompanion(
        id: Value(id),
        displayName: f.stringField('display_name'),
        peerSharingId: f.stringFieldNullable('peer_sharing_id'),
        pairwiseSecret: f.blobFieldNullable('pairwise_secret'),
        pinnedIdentity: f.blobFieldNullable('pinned_identity'),
        offeredScopes: f.stringField('offered_scopes'),
        publicKeyHex: f.stringField('public_key_hex'),
        sharedSecretHex: f.stringFieldNullable('shared_secret_hex'),
        grantedScopes: f.stringField('granted_scopes'),
        isVerified: f.boolField('is_verified'),
        initId: f.stringFieldNullable('init_id'),
        createdAt: f.dateTimeField('created_at'),
        establishedAt: f.dateTimeFieldNullable('established_at'),
        lastSyncAt: f.dateTimeFieldNullable('last_sync_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.friends,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(db.friends)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.friends,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'display_name': row.displayName,
        'peer_sharing_id': row.peerSharingId,
        'pairwise_secret': row.pairwiseSecret != null
            ? base64Encode(row.pairwiseSecret!)
            : null,
        'pinned_identity': row.pinnedIdentity != null
            ? base64Encode(row.pinnedIdentity!)
            : null,
        'offered_scopes': row.offeredScopes,
        'public_key_hex': row.publicKeyHex,
        'shared_secret_hex': row.sharedSecretHex,
        'granted_scopes': row.grantedScopes,
        'is_verified': row.isVerified,
        'init_id': row.initId,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'established_at': _dateTimeToSyncStringOrNull(row.establishedAt),
        'last_sync_at': _dateTimeToSyncStringOrNull(row.lastSyncAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.friends,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// media_attachments
// ---------------------------------------------------------------------------

DriftSyncEntity _mediaAttachmentsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'media_attachments',
    toSyncFields: (dynamic row) {
      final r = row as MediaAttachment;
      return {
        'message_id': r.messageId,
        'member_id': r.memberId,
        'tag': r.tag,
        'media_id': r.mediaId,
        'media_type': r.mediaType,
        'encryption_key_b64': r.encryptionKeyB64,
        'content_hash': r.contentHash,
        'plaintext_hash': r.plaintextHash,
        'mime_type': r.mimeType,
        'size_bytes': r.sizeBytes,
        'width': r.width,
        'height': r.height,
        'duration_ms': r.durationMs,
        'blurhash': r.blurhash,
        'waveform_b64': r.waveformB64,
        'thumbnail_media_id': r.thumbnailMediaId,
        'thumbnail_content_hash': r.thumbnailContentHash,
        'thumbnail_plaintext_hash': r.thumbnailPlaintextHash,
        'source_url': r.sourceUrl,
        'preview_url': r.previewUrl,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'media_attachments',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = MediaAttachmentsCompanion(
        id: Value(id),
        messageId: f.stringField('message_id'),
        memberId: f.stringField('member_id'),
        tag: f.stringField('tag'),
        mediaId: f.stringField('media_id'),
        mediaType: f.stringField('media_type'),
        encryptionKeyB64: f.stringField('encryption_key_b64'),
        contentHash: f.stringField('content_hash'),
        plaintextHash: f.stringField('plaintext_hash'),
        mimeType: f.stringField('mime_type'),
        sizeBytes: f.intField('size_bytes'),
        width: f.intField('width'),
        height: f.intField('height'),
        durationMs: f.intField('duration_ms'),
        blurhash: f.stringField('blurhash'),
        waveformB64: f.stringField('waveform_b64'),
        thumbnailMediaId: f.stringField('thumbnail_media_id'),
        thumbnailContentHash: f.stringField('thumbnail_content_hash'),
        thumbnailPlaintextHash: f.stringField('thumbnail_plaintext_hash'),
        sourceUrl: f.stringField('source_url'),
        previewUrl: f.stringField('preview_url'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.mediaAttachments,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.mediaAttachments,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.mediaAttachments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'message_id': row.messageId,
        'member_id': row.memberId,
        'tag': row.tag,
        'media_id': row.mediaId,
        'media_type': row.mediaType,
        'encryption_key_b64': row.encryptionKeyB64,
        'content_hash': row.contentHash,
        'plaintext_hash': row.plaintextHash,
        'mime_type': row.mimeType,
        'size_bytes': row.sizeBytes,
        'width': row.width,
        'height': row.height,
        'duration_ms': row.durationMs,
        'blurhash': row.blurhash,
        'waveform_b64': row.waveformB64,
        'thumbnail_media_id': row.thumbnailMediaId,
        'thumbnail_content_hash': row.thumbnailContentHash,
        'thumbnail_plaintext_hash': row.thumbnailPlaintextHash,
        'source_url': row.sourceUrl,
        'preview_url': row.previewUrl,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.mediaAttachments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// member_board_posts
// ---------------------------------------------------------------------------

DriftSyncEntity _memberBoardPostsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'member_board_posts',
    toSyncFields: (dynamic row) {
      final r = row as MemberBoardPostRow;
      return {
        'target_member_id': r.targetMemberId,
        'author_id': r.authorId,
        'audience': r.audience,
        'title': r.title,
        'body': r.body,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'written_at': _dateTimeToSyncString(r.writtenAt),
        'edited_at': _dateTimeToSyncStringOrNull(r.editedAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'member_board_posts',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );

      // Forward-compat audience fallback: if a future-version peer sends a
      // value we don't recognise (neither 'public' nor 'private'), treat it
      // as 'public'. Public is the more visible default — content is less
      // likely to be silently hidden than if we defaulted to 'private'.
      final rawAudience = _asString(fields['audience']);
      final audience = (rawAudience == 'public' || rawAudience == 'private')
          ? rawAudience
          : (rawAudience != null ? 'public' : null);

      final companion = MemberBoardPostsCompanion(
        id: Value(id),
        targetMemberId: f.stringFieldNullable('target_member_id'),
        authorId: f.stringFieldNullable('author_id'),
        audience: audience != null ? Value(audience) : const Value.absent(),
        title: f.stringFieldNullable('title'),
        body: f.stringField('body'),
        createdAt: f.dateTimeField('created_at'),
        writtenAt: f.dateTimeField('written_at'),
        editedAt: f.dateTimeFieldNullable('edited_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.memberBoardPosts,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.memberBoardPosts,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.memberBoardPosts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'target_member_id': row.targetMemberId,
        'author_id': row.authorId,
        'audience': row.audience,
        'title': row.title,
        'body': row.body,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'written_at': _dateTimeToSyncString(row.writtenAt),
        'edited_at': _dateTimeToSyncStringOrNull(row.editedAt),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.memberBoardPosts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}
