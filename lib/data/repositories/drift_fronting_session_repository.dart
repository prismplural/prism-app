import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';

class DriftFrontingSessionRepository
    with SyncRecordMixin
    implements FrontingSessionRepository {
  final FrontingSessionsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;
  // Plan 02 R1: optional link-epoch stamper (same pattern as the member repo).
  final PluralKitSyncDao? _pkSyncDao;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'fronting_sessions';

  DriftFrontingSessionRepository(
    this._dao,
    this._syncHandle, {
    PluralKitSyncDao? pkSyncDao,
  }) : _pkSyncDao = pkSyncDao;

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
    final companion = FrontingSessionMapper.toCompanion(session);
    await _dao.updateSession(companion);
    await syncRecordUpdate(_table, session.id, _sessionFields(session));
  }

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    await _dao.endSession(id, endTime);
    // Fetch the updated session to build a full field map for the Rust engine.
    final row = await _dao.getSessionById(id);
    if (row != null) {
      final session = FrontingSessionMapper.toDomain(row);
      await syncRecordUpdate(_table, id, _sessionFields(session));
    }
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

  Map<String, dynamic> _sessionFields(domain.FrontingSession s) {
    return {
      'start_time': _toSyncUtc(s.startTime),
      'end_time': _toSyncUtcOrNull(s.endTime),
      'member_id': s.memberId,
      'notes': s.notes,
      'confidence': s.confidence?.index,
      'pluralkit_uuid': s.pluralkitUuid,
      'session_type': s.sessionType.index,
      'quality': s.quality?.index,
      'is_health_kit_import': s.isHealthKitImport,
      'is_deleted': false,
    };
  }
}

/// Normalizes a DateTime to UTC ISO-8601 (Z-suffixed) for sync wire emission.
///
/// Local DateTimes serialize with no offset/Z, so a peer in a different
/// timezone would parse the value as their own local time and shift the
/// absolute moment by the timezone delta on every sync. Routing every
/// DateTime through here mirrors the `_dateTimeToSyncString` helper in
/// `core/sync/drift_sync_adapter.dart`.
String _toSyncUtc(DateTime dt) => dt.toUtc().toIso8601String();

String? _toSyncUtcOrNull(DateTime? dt) => dt?.toUtc().toIso8601String();
