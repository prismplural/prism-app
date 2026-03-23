import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/sleep_sessions_dao.dart';
import 'package:prism_plurality/data/mappers/sleep_session_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/sleep_session.dart' as domain;
import 'package:prism_plurality/domain/repositories/sleep_session_repository.dart';

class DriftSleepSessionRepository
    with SyncRecordMixin
    implements SleepSessionRepository {
  final SleepSessionsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'sleep_sessions';

  DriftSleepSessionRepository(this._dao, this._syncHandle);

  @override
  Stream<List<domain.SleepSession>> watchAllSleepSessions() {
    return _dao.watchAllSleepSessions().map(
      (rows) => rows.map(SleepSessionMapper.toDomain).toList(),
    );
  }

  @override
  Stream<domain.SleepSession?> watchActiveSleepSession() {
    return _dao.watchActiveSleepSession().map(
      (row) => row != null ? SleepSessionMapper.toDomain(row) : null,
    );
  }

  @override
  Future<List<domain.SleepSession>> getRecentSleepSessions({
    int limit = 10,
  }) async {
    final rows = await _dao.getRecentSleepSessions(limit);
    return rows.map(SleepSessionMapper.toDomain).toList();
  }

  @override
  Future<void> createSleepSession(domain.SleepSession session) async {
    final companion = SleepSessionMapper.toCompanion(session);
    await _dao.createSleepSession(companion);
    await syncRecordCreate(_table, session.id, _sleepSessionFields(session));
  }

  @override
  Future<void> updateSleepSession(domain.SleepSession session) async {
    final companion = SleepSessionMapper.toCompanion(session);
    await _dao.updateSleepSession(session.id, companion);
    await syncRecordUpdate(_table, session.id, _sleepSessionFields(session));
  }

  @override
  Future<void> endSleepSession(String id, DateTime endTime) async {
    await _dao.endSleepSession(id, endTime);
    // Build a minimal field map with the updated end_time.
    // We pass all known fields by constructing from what we have.
    // Since SleepSessionsDao has no getById, we pass what we know changed.
    await syncRecordUpdate(_table, id, {'end_time': endTime.toIso8601String()});
  }

  @override
  Future<void> deleteSleepSession(String id) async {
    await _dao.deleteSleepSession(id);
    await syncRecordDelete(_table, id);
  }

  Map<String, dynamic> _sleepSessionFields(domain.SleepSession s) {
    return {
      'start_time': s.startTime.toIso8601String(),
      'end_time': s.endTime?.toIso8601String(),
      'quality': s.quality.index,
      'notes': s.notes,
      'is_health_kit_import': s.isHealthKitImport,
      'is_deleted': false,
    };
  }
}
