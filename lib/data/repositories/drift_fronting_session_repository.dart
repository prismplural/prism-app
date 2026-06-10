import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/front_session_comments_dao.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';

class DriftFrontingSessionRepository
    with SyncRecordMixin
    implements FrontingSessionRepository {
  final FrontingSessionsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;
  // Plan 02 R1: optional link-epoch stamper (same pattern as the member repo).
  final PluralKitSyncDao? _pkSyncDao;
  final FrontSessionCommentsDao? _commentsDao;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'fronting_sessions';
  static const _commentsTable = 'front_session_comments';

  DriftFrontingSessionRepository(
    this._dao,
    this._syncHandle, {
    PluralKitSyncDao? pkSyncDao,
    FrontSessionCommentsDao? commentsDao,
  }) : _pkSyncDao = pkSyncDao,
       _commentsDao = commentsDao;

  @override
  Future<List<domain.FrontingSession>> getAllSessions() async {
    final rows = await _dao.getAllSessions();
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Future<List<domain.FrontingSession>> getFrontingSessions() async {
    final rows = await _dao.getFrontingSessions();
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.FrontingSession>> watchAllSessions() {
    return _dao.watchAllSessions().map(
      (rows) => rows.map(FrontingSessionMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.FrontingSession>> getActiveSessions() async {
    final rows = await _dao.getActiveSessions();
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered() async {
    final rows = await _dao.getAllActiveSessionsUnfiltered();
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.FrontingSession>> watchActiveSessions() {
    return _dao.watchActiveSessions().map(
      (rows) => rows.map(FrontingSessionMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.FrontingSession?> getActiveSession() async {
    final rows = await _dao.getActiveSessions();
    if (rows.isEmpty) return null;
    return FrontingSessionMapper.toDomain(rows.first);
  }

  @override
  Stream<domain.FrontingSession?> watchActiveSession() {
    return _dao.watchActiveSessions().map(
      (rows) =>
          rows.isEmpty ? null : FrontingSessionMapper.toDomain(rows.first),
    );
  }

  @override
  Stream<domain.FrontingSession?> watchActiveSleepSession() {
    return _dao.watchActiveSleepSession().map(
      (row) => row != null ? FrontingSessionMapper.toDomain(row) : null,
    );
  }

  @override
  Stream<List<domain.FrontingSession>> watchAllSleepSessions() {
    return _dao.watchAllSleepSessions().map(
      (rows) => rows.map(FrontingSessionMapper.toDomain).toList(),
    );
  }

  @override
  Future<domain.FrontingSession?> getSessionById(String id) async {
    final row = await _dao.getSessionById(id);
    return row != null ? FrontingSessionMapper.toDomain(row) : null;
  }

  @override
  Stream<domain.FrontingSession?> watchSessionById(String id) {
    return _dao
        .watchSessionById(id)
        .map((row) => row != null ? FrontingSessionMapper.toDomain(row) : null);
  }

  @override
  Future<List<domain.FrontingSession>> getSessionsForMember(
    String memberId,
  ) async {
    final rows = await _dao.getSessionsForMember(memberId);
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Future<List<domain.FrontingSession>> getRecentSessions({
    int limit = 20,
  }) async {
    final rows = await _dao.getRecentSessions(limit: limit);
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Future<List<domain.FrontingSession>> getRecentSleepSessions({
    int limit = 10,
  }) async {
    final rows = await _dao.getRecentSleepSessions(limit);
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Stream<List<domain.FrontingSession>> watchRecentSessions({int limit = 20}) {
    return _dao
        .watchRecentSessions(limit: limit)
        .map((rows) => rows.map(FrontingSessionMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({
    int limit = 30,
  }) {
    return _dao
        .watchRecentAllSessions(limit: limit)
        .map((rows) => rows.map(FrontingSessionMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.FrontingSession>> watchSessionsOverlappingRange(
    DateTime start,
    DateTime end,
  ) {
    return _dao
        .watchSessionsOverlappingRange(start, end)
        .map((rows) => rows.map(FrontingSessionMapper.toDomain).toList());
  }

  @override
  Future<void> createSession(domain.FrontingSession session) async {
    final companion = FrontingSessionMapper.toCompanion(session);
    await _dao.insertSession(companion);
    await syncRecordCreate(_table, session.id, _sessionFields(session));
  }

  @override
  Future<void> updateSession(domain.FrontingSession session) async {
    final existingRow = await _dao.getSessionById(session.id);
    if (existingRow == null) return;
    final canRevivePkRescueTombstone =
        existingRow.isDeleted &&
        !session.isDeleted &&
        existingRow.pluralkitUuid != null &&
        existingRow.pluralkitUuid!.isNotEmpty &&
        existingRow.deleteIntentEpoch == null;
    if (existingRow.isDeleted && !canRevivePkRescueTombstone) return;

    final changedFields = diffSyncFields(
      _sessionFieldsFromRow(existingRow),
      _sessionFields(session),
    );
    if (canRevivePkRescueTombstone) {
      changedFields['is_deleted'] = false;
      if (existingRow.deletePushStartedAt != null) {
        changedFields['delete_push_started_at'] = null;
      }
    }
    if (changedFields.isEmpty) return;

    final companion = _partialSessionCompanion(changedFields);
    await _dao.updateSessionById(session.id, companion);
    await syncRecordUpdate(_table, session.id, changedFields);
  }

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    // Read BEFORE the DAO write so the diff sees the pre-end state.
    // Refetching after the write would over-emit columns endSession never
    // touches (see read-after-write trap in the migration plan).
    final existingRow = await _dao.getSessionById(id);
    if (existingRow == null || existingRow.isDeleted) return;

    final endedDomain = FrontingSessionMapper.toDomain(
      existingRow,
    ).copyWith(endTime: endTime);
    final changedFields = diffSyncFields(
      _sessionFieldsFromRow(existingRow),
      _sessionFields(endedDomain),
    );
    if (changedFields.isEmpty) return;

    final companion = _partialSessionCompanion(changedFields);
    await _dao.updateSessionById(id, companion);
    await syncRecordUpdate(_table, id, changedFields);
  }

  @override
  Future<void> deleteSession(String id) async {
    int? epoch;
    final pkDao = _pkSyncDao;
    final existing = await _dao.getSessionById(id);
    final isLinked =
        existing != null &&
        existing.pluralkitUuid != null &&
        existing.pluralkitUuid!.isNotEmpty;
    if (pkDao != null && isLinked) {
      epoch = await pkDao.getLinkEpoch();
    }

    await _softDeleteAttachedComments(id);
    await _dao.softDeleteSession(id);
    if (epoch != null) {
      await _dao.stampDeleteIntent(id, epoch);
    }
    await syncRecordDelete(_table, id);
  }

  @override
  Future<List<domain.FrontingSession>> getDeletedLinkedSessions() async {
    final rows = await _dao.getDeletedLinkedSessions();
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Future<List<domain.FrontingSession>> getDeletedSleepSessions() async {
    final rows = await _dao.getDeletedSleepSessions();
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  @override
  Future<void> restoreSleepSession(String id) async {
    await _dao.restoreSleepSession(id);
    // Emit the revival as a best-effort op. prism-sync's terminal-tombstone
    // gate drops this on any peer that already holds the tombstone, so the
    // restore is effectively local-only; the local row is restored regardless.
    await syncRecordUpdate(_table, id, {'is_deleted': false});
  }

  @override
  Future<void> clearPluralKitLink(String id) async {
    await _dao.clearPluralKitLinkRaw(id);
    await syncRecordUpdate(_table, id, {'pluralkit_uuid': null});
  }

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {
    await _dao.stampDeletePushStartedAt(id, timestampMs);
    await syncRecordUpdate(_table, id, {'delete_push_started_at': timestampMs});
  }

  @override
  Future<({int count, Duration? avgDuration})> getSleepStats({
    required DateTime since,
    DateTime? until,
  }) => _dao.getSleepStats(since, until);

  @override
  Stream<List<domain.FrontingSession>> watchRecentSleepSessions({
    required int limit,
  }) {
    return _dao
        .watchRecentSleepSessions(limit)
        .map((rows) => rows.map(FrontingSessionMapper.toDomain).toList());
  }

  @override
  Future<int> getCount() => _dao.getCount();

  @override
  Future<int> getFrontingCount() => _dao.getFrontingCount();

  @override
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) => _dao.getMemberFrontingCounts(
    recentLimit: recentLimit,
    startHour: startHour,
    endHour: endHour,
    withinDays: withinDays,
  );

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _dao.getSessionsBetween(start, end);
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  /// Visible-for-testing: builds the field map this repository hands to the
  /// Rust sync engine for create/update. Exposed so a regression test can
  /// pin every emitted DateTime as Z-suffixed UTC — see
  /// drift_fronting_session_repository_test.
  @visibleForTesting
  Map<String, dynamic> debugSessionFields(domain.FrontingSession s) =>
      _sessionFields(s);

  /// Emit a final-state `syncRecordCreate` for [id] reflecting the
  /// row's current on-disk shape, or no-op when the row is missing or
  /// soft-deleted. Used by the data-import rescue path
  /// (`DataImportService.importData`) to emit one create per surviving
  /// session id after the suppressed in-transaction rescue + merge
  /// pass — see review finding #9. The post-suppress emission keeps
  /// peer state convergent without leaking the intermediate merge
  /// churn (create-then-update-then-delete) that the rescue body
  /// generates internally.
  Future<void> emitFinalStateCreateIfSurviving(String id) async {
    final row = await _dao.getSessionById(id);
    if (row == null || row.isDeleted) return;
    final session = FrontingSessionMapper.toDomain(row);
    await syncRecordCreate(_table, id, _sessionFields(session));
  }

  Map<String, dynamic> _sessionFields(domain.FrontingSession s) =>
      sessionFields(s);

  /// Mirror of [sessionFields] built from a Drift row. Used by the
  /// patch-style update flow as the "previous" side of the diff. Columns
  /// not emitted by [sessionFields] (`co_fronter_ids`, `pk_member_ids_json`,
  /// the PK-deletion bookkeeping ints) are intentionally omitted here too
  /// so the diff stays symmetric.
  Map<String, dynamic> _sessionFieldsFromRow(db.FrontingSession row) {
    return {
      'start_time': toSyncUtc(row.startTime),
      'end_time': toSyncUtcOrNull(row.endTime),
      'member_id': row.memberId,
      'notes': row.notes,
      'confidence': row.confidence,
      'pluralkit_uuid': row.pluralkitUuid,
      'pk_import_source': row.pkImportSource,
      'pk_file_switch_id': row.pkFileSwitchId,
      'session_type': row.sessionType,
      'quality': row.quality,
      'is_health_kit_import': row.isHealthKitImport,
      'is_deleted': row.isDeleted,
    };
  }

  db.FrontingSessionsCompanion _partialSessionCompanion(
    Map<String, dynamic> fields,
  ) {
    return db.FrontingSessionsCompanion(
      startTime: fields.containsKey('start_time')
          ? Value(parseSyncDateTime(fields['start_time']))
          : const Value.absent(),
      endTime: fields.containsKey('end_time')
          ? Value(
              fields['end_time'] == null
                  ? null
                  : parseSyncDateTime(fields['end_time']),
            )
          : const Value.absent(),
      memberId: fields.containsKey('member_id')
          ? Value(fields['member_id'] as String?)
          : const Value.absent(),
      notes: fields.containsKey('notes')
          ? Value(fields['notes'] as String?)
          : const Value.absent(),
      confidence: fields.containsKey('confidence')
          ? Value(fields['confidence'] as int?)
          : const Value.absent(),
      pluralkitUuid: fields.containsKey('pluralkit_uuid')
          ? Value(fields['pluralkit_uuid'] as String?)
          : const Value.absent(),
      pkImportSource: fields.containsKey('pk_import_source')
          ? Value(fields['pk_import_source'] as String?)
          : const Value.absent(),
      pkFileSwitchId: fields.containsKey('pk_file_switch_id')
          ? Value(fields['pk_file_switch_id'] as String?)
          : const Value.absent(),
      sessionType: fields.containsKey('session_type')
          ? Value(fields['session_type'] as int)
          : const Value.absent(),
      quality: fields.containsKey('quality')
          ? Value(fields['quality'] as int?)
          : const Value.absent(),
      isHealthKitImport: fields.containsKey('is_health_kit_import')
          ? Value(fields['is_health_kit_import'] as bool)
          : const Value.absent(),
      isDeleted: fields.containsKey('is_deleted')
          ? Value(fields['is_deleted'] as bool)
          : const Value.absent(),
      deletePushStartedAt: fields.containsKey('delete_push_started_at')
          ? Value(fields['delete_push_started_at'] as int?)
          : const Value.absent(),
    );
  }

  /// Field-map builder for fronting-session sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createSession()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> sessionFields(domain.FrontingSession s) {
    return {
      'start_time': toSyncUtc(s.startTime),
      'end_time': toSyncUtcOrNull(s.endTime),
      'member_id': s.memberId,
      'notes': s.notes,
      'confidence': s.confidence?.index,
      'pluralkit_uuid': s.pluralkitUuid,
      'pk_import_source': s.pkImportSource,
      'pk_file_switch_id': s.pkFileSwitchId,
      'session_type': s.sessionType.index,
      'quality': s.quality?.index,
      'is_health_kit_import': s.isHealthKitImport,
      'is_deleted': false,
    };
  }

  Future<void> _softDeleteAttachedComments(String sessionId) async {
    final commentsDao = _commentsDao;
    if (commentsDao == null) return;
    final comments = await commentsDao.getActiveCommentsForSession(sessionId);
    if (comments.isEmpty) return;
    await commentsDao.softDeleteCommentsForSession(sessionId);
    for (final comment in comments) {
      await syncRecordDelete(_commentsTable, comment.id);
    }
  }
}
