import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

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
    this._runDeferredPkEntryReplay,
  );

  final DriftSyncAdapter adapter;
  final List<Future<void>> _pendingQuarantineWrites;
  final Future<void> Function() _runDeferredPkEntryReplay;

  Completer<void>? _batchCompleter;

  /// Call before starting a sync to create a new completion signal.
  void beginSyncBatch() {
    _batchCompleter = Completer<void>();
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

    await _runDeferredPkEntryReplay();

    if (!completer.isCompleted) {
      completer.complete();
    }
    _batchCompleter = null;
  }
}

SyncAdapterWithCompletion buildSyncAdapterWithCompletion(
  AppDatabase db, {
  SyncQuarantineService? quarantine,
}) {
  final pendingQuarantineWrites = <Future<void>>[];
  final adapter = DriftSyncAdapter(
    entities: [
      _membersEntity(db, quarantine, pendingQuarantineWrites.add),
      _frontingSessionsEntity(db, quarantine, pendingQuarantineWrites.add),
      _conversationsEntity(db, quarantine, pendingQuarantineWrites.add),
      _chatMessagesEntity(db, quarantine, pendingQuarantineWrites.add),
      _systemSettingsEntity(db, quarantine, pendingQuarantineWrites.add),
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
      _memberGroupsEntity(db, quarantine, pendingQuarantineWrites.add),
      _memberGroupEntriesEntity(db, quarantine, pendingQuarantineWrites.add),
      _customFieldsEntity(db, quarantine, pendingQuarantineWrites.add),
      _customFieldValuesEntity(db, quarantine, pendingQuarantineWrites.add),
      _notesEntity(db, quarantine, pendingQuarantineWrites.add),
      _frontSessionCommentsEntity(db, quarantine, pendingQuarantineWrites.add),
      _friendsEntity(db, quarantine, pendingQuarantineWrites.add),
      _mediaAttachmentsEntity(db, quarantine, pendingQuarantineWrites.add),
    ],
  );
  return SyncAdapterWithCompletion(
    adapter,
    pendingQuarantineWrites,
    () => _retryDeferredPkBackedMemberGroupEntryOps(
      db,
      quarantine: quarantine,
      trackQuarantineWrite: pendingQuarantineWrites.add,
    ),
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

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _asBool(dynamic value) => value is bool ? value : null;

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
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

String? _pkGroupUuidFromEntityId(String entityId) =>
    entityId.startsWith(_pkGroupSyncEntityIdPrefix)
    ? entityId.substring(_pkGroupSyncEntityIdPrefix.length)
    : null;

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
      _pkGroupUuidFromEntityId(entityId) == null) {
    alias = await _pkGroupAliasForLegacyEntityId(db, entityId);
  }

  final pkGroupUuid =
      payloadPkGroupUuid ??
      _pkGroupUuidFromEntityId(entityId) ??
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
  if (_pkGroupUuidFromEntityId(entityId) != null) {
    return _resolveMemberGroupRowForSyncId(db, entityId);
  }

  final alias = await _pkGroupAliasForLegacyEntityId(db, entityId);
  if (alias != null) {
    return _memberGroupRowById(db, entityId);
  }

  return _memberGroupRowById(db, entityId);
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
  try {
    final decoded = jsonDecode(fieldsJson);
    if (decoded is Map<String, dynamic>) {
      return _pkMemberGroupEntryLogicalEdgeFromFields(decoded);
    }
    if (decoded is Map) {
      return _pkMemberGroupEntryLogicalEdgeFromFields(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
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

  final companion = MemberGroupEntriesCompanion(
    id: Value(id),
    groupId: Value(resolvedGroupId),
    memberId: Value(resolvedMemberId),
    isDeleted: f.boolField('is_deleted'),
  );
  await _insertOrUpdateById(
    db,
    db.memberGroupEntries,
    companion,
    (t) => t.id.equals(id),
  );
  await _writeMemberGroupEntryPkFields(
    db,
    id: id,
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
    final decodedFields = (() {
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
    })();

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
      if (nextRetryCount >= _maxDeferredPkEntryReplayRetries) {
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
        'is_active': r.isActive,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'display_order': r.displayOrder,
        'is_admin': r.isAdmin,
        'custom_color_enabled': r.customColorEnabled,
        'custom_color_hex': r.customColorHex,
        'parent_system_id': r.parentSystemId,
        'pluralkit_uuid': r.pluralkitUuid,
        'pluralkit_id': r.pluralkitId,
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
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final shouldCheckPkUuidChange = fields.containsKey('pluralkit_uuid');
      final priorPkUuid = shouldCheckPkUuidChange
          ? (await (db.select(
              db.members,
            )..where((t) => t.id.equals(id))).getSingleOrNull())?.pluralkitUuid
          : null;
      final nextPkUuid = shouldCheckPkUuidChange
          ? _asString(fields['pluralkit_uuid'])
          : null;
      final f = _FieldContext(
        entityType: 'members',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = MembersCompanion(
        id: Value(id),
        name: f.stringField('name'),
        pronouns: f.stringFieldNullable('pronouns'),
        emoji: f.stringField('emoji'),
        age: f.intFieldNullable('age'),
        bio: f.stringFieldNullable('bio'),
        avatarImageData: f.blobFieldNullable('avatar_image_data'),
        isActive: f.boolField('is_active'),
        createdAt: f.dateTimeField('created_at'),
        displayOrder: f.intField('display_order'),
        isAdmin: f.boolField('is_admin'),
        customColorEnabled: f.boolField('custom_color_enabled'),
        customColorHex: f.stringFieldNullable('custom_color_hex'),
        parentSystemId: f.stringFieldNullable('parent_system_id'),
        pluralkitUuid: f.stringFieldNullable('pluralkit_uuid'),
        pluralkitId: f.stringFieldNullable('pluralkit_id'),
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
      );
      await _insertOrUpdateById(
        db,
        db.members,
        companion,
        (t) => t.id.equals(id),
      );
      if (shouldCheckPkUuidChange && priorPkUuid != nextPkUuid) {
        await _retryDeferredPkBackedMemberGroupEntryOps(
          db,
          quarantine: quarantine,
          trackQuarantineWrite: trackQuarantineWrite,
        );
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
      await (db.delete(db.members)..where((t) => t.id.equals(id))).go();
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
        'is_active': row.isActive,
        'created_at': _dateTimeToSyncString(row.createdAt),
        'display_order': row.displayOrder,
        'is_admin': row.isAdmin,
        'custom_color_enabled': row.customColorEnabled,
        'custom_color_hex': row.customColorHex,
        'parent_system_id': row.parentSystemId,
        'pluralkit_uuid': row.pluralkitUuid,
        'pluralkit_id': row.pluralkitId,
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
        'delete_push_started_at': r.deletePushStartedAt,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'fronting_sessions',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = FrontingSessionsCompanion(
        id: Value(id),
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
        deletePushStartedAt: f.intFieldNullable('delete_push_started_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.frontingSessions,
        companion,
        (t) => t.id.equals(id),
      );
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.frontingSessions,
      )..where((t) => t.id.equals(id))).go();
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
      final companion = ConversationsCompanion(
        id: Value(id),
        createdAt: f.dateTimeField('created_at'),
        lastActivityAt: f.dateTimeField('last_activity_at'),
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
      await (db.delete(db.chatMessages)..where((t) => t.id.equals(id))).go();
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
        'chat_badge_preferences': r.chatBadgePreferences,
        'habits_badge_enabled': r.habitsBadgeEnabled,
        'fronting_list_view_mode': r.frontingListViewMode,
        'add_front_default_behavior': r.addFrontDefaultBehavior,
        'quick_front_default_behavior': r.quickFrontDefaultBehavior,
        'is_deleted': r.isDeleted,
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
        chatBadgePreferences: f.stringField('chat_badge_preferences'),
        habitsBadgeEnabled: f.boolField('habits_badge_enabled'),
        frontingListViewMode: f.intField('fronting_list_view_mode'),
        addFrontDefaultBehavior: f.intField('add_front_default_behavior'),
        quickFrontDefaultBehavior: f.intField('quick_front_default_behavior'),
        // Device-local fields (font*, pin*, biometric*, autoLock*) are
        // intentionally excluded from sync.
        isDeleted: f.boolField('is_deleted'),
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
        'chat_badge_preferences': row.chatBadgePreferences,
        'habits_badge_enabled': row.habitsBadgeEnabled,
        'fronting_list_view_mode': row.frontingListViewMode,
        'add_front_default_behavior': row.addFrontDefaultBehavior,
        'quick_front_default_behavior': row.quickFrontDefaultBehavior,
        'is_deleted': row.isDeleted,
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
) {
  return DriftSyncEntity(
    tableName: 'member_groups',
    entityIdFor: (dynamic row) {
      final r = row as MemberGroupRow;
      final pkUuid = r.pluralkitUuid;
      if (pkUuid != null && pkUuid.isNotEmpty) {
        return _canonicalPkGroupEntityId(pkUuid);
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
        'display_order': r.displayOrder,
        'parent_group_id': r.parentGroupId,
        'group_type': r.groupType,
        'filter_rules': r.filterRules,
        'created_at': _dateTimeToSyncString(r.createdAt),
        'pluralkit_id': r.pluralkitId,
        'pluralkit_uuid': r.pluralkitUuid,
        'last_seen_from_pk_at': _dateTimeToSyncStringOrNull(r.lastSeenFromPkAt),
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
          _pkGroupUuidFromEntityId(id) ??
          (await _pkGroupAliasForLegacyEntityId(db, id))?.pkGroupUuid;
      final existingRow = await _resolveMemberGroupRowForSyncId(
        db,
        id,
        payloadPkGroupUuid: resolvedPkGroupUuid,
      );
      final localRowId = existingRow?.id ?? id;
      final companion = MemberGroupsCompanion(
        id: Value(localRowId),
        name: f.stringField('name'),
        description: f.stringFieldNullable('description'),
        colorHex: f.stringFieldNullable('color_hex'),
        emoji: f.stringFieldNullable('emoji'),
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
        isDeleted: f.boolField('is_deleted'),
      );
      await _insertOrUpdateById(
        db,
        db.memberGroups,
        companion,
        (t) => t.id.equals(localRowId),
      );
      if (resolvedPkGroupUuid != null && resolvedPkGroupUuid.isNotEmpty) {
        // C1: only record an alias for the *incoming* entity id when it
        // is a genuinely-legacy id (the helper filters out canonical).
        // Do NOT auto-record an alias for the receiving device's own
        // local row id: both peers end up with `pk-group-<uuid>` after
        // import, and aliasing that id makes later alias-delete emits
        // hard-delete the peer's active PK-group row.
        await _recordPkGroupAliasIfNeeded(
          db,
          legacyEntityId: id,
          pkGroupUuid: resolvedPkGroupUuid,
        );
      }
      await _retryDeferredPkBackedMemberGroupEntryOps(
        db,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
    },
    hardDelete: (String id) async {
      final row = await _resolveMemberGroupRowForSyncDelete(db, id);
      if (row == null) return;
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
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await _resolveMemberGroupRowForSyncId(db, id);
      return row?.isDeleted ?? true;
    },
  );
}

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
      return _canonicalPkMemberGroupEntryEntityId(g, m);
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
      await (db.delete(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(id))).go();
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
      final companion = CustomFieldsCompanion(
        id: Value(id),
        name: f.stringField('name'),
        fieldType: f.intField('field_type'),
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
      await _insertOrUpdateById(
        db,
        db.customFieldValues,
        companion,
        (t) => t.id.equals(id),
      );
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
) {
  return DriftSyncEntity(
    tableName: 'front_session_comments',
    toSyncFields: (dynamic row) {
      final r = row as FrontSessionCommentRow;
      return {
        'target_time': _dateTimeToSyncStringOrNull(r.targetTime),
        'author_member_id': r.authorMemberId,
        'body': r.body,
        'timestamp': _dateTimeToSyncString(r.timestamp),
        'created_at': _dateTimeToSyncString(r.createdAt),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'front_session_comments',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = FrontSessionCommentsCompanion(
        id: Value(id),
        // `session_id` is a NOT NULL legacy column that still exists on disk
        // until the cleanup rebuild removes it. Remote sync payloads only
        // carry the new timestamp-based shape, so inserts on a newly paired
        // device must write the same inert sentinel the local mapper uses.
        sessionId: const Value(''),
        targetTime: f.dateTimeFieldNullable('target_time'),
        authorMemberId: f.stringFieldNullable('author_member_id'),
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
        'target_time': _dateTimeToSyncStringOrNull(row.targetTime),
        'author_member_id': row.authorMemberId,
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
