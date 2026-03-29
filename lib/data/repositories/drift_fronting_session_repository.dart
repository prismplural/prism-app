import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';

class DriftFrontingSessionRepository
    with SyncRecordMixin
    implements FrontingSessionRepository {
  final FrontingSessionsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'fronting_sessions';

  DriftFrontingSessionRepository(this._dao, this._syncHandle);

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
    await _dao.softDeleteSession(id);
    await syncRecordDelete(_table, id);
  }

  @override
  Future<int> getCount() => _dao.getCount();

  @override
  Future<int> getFrontingCount() => _dao.getFrontingCount();

  @override
  Future<Map<String, int>> getMemberFrontingCounts({int limit = 50}) =>
      _dao.getMemberFrontingCounts(limit: limit);

  @override
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _dao.getSessionsBetween(start, end);
    return rows.map(FrontingSessionMapper.toDomain).toList();
  }

  Map<String, dynamic> _sessionFields(domain.FrontingSession s) {
    return {
      'start_time': s.startTime.toIso8601String(),
      'end_time': s.endTime?.toIso8601String(),
      'member_id': s.memberId,
      'co_fronter_ids': jsonEncode(s.coFronterIds),
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
