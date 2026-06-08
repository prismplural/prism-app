// Isolated contract for SyncRecordMixin.replayCapturedOps — the shared
// post-commit replay loop used by both the custom-field durable batch
// (DriftCustomFieldsRepository.commitValueBatch) and the SP importer.
//
// These tests drive the loop through a minimal mixin host whose syncRecord*
// methods are overridden to record (and optionally throw), so the loop's
// dispatch routing, ordering, per-op isolation, and failure collection are
// verified deterministically without an FFI handle. The real syncRecord*
// dispatch is covered separately by the commitValueBatch integration tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// Minimal [SyncRecordMixin] host. Overriding the three `syncRecord*` entry
/// points lets us observe exactly what the replay loop dispatches, in order,
/// and force a throw out of a chosen entity to exercise the per-op catch.
class _RecordingEmitter with SyncRecordMixin {
  _RecordingEmitter({this.throwOnEntityIds = const {}});

  final Set<String> throwOnEntityIds;
  final List<String> calls = [];

  @override
  ffi.PrismSyncHandle? get syncHandle => null;

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    if (throwOnEntityIds.contains(entityId)) throw Exception('boom-$entityId');
    calls.add('create:$table:$entityId');
  }

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    if (throwOnEntityIds.contains(entityId)) throw Exception('boom-$entityId');
    calls.add('update:$table:$entityId');
  }

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    if (throwOnEntityIds.contains(entityId)) throw Exception('boom-$entityId');
    calls.add('delete:$table:$entityId');
  }
}

CapturedSyncOp _op(
  String table,
  String id,
  SyncRecordOpType type, [
  Map<String, dynamic> fields = const {},
]) => CapturedSyncOp(table, id, type, fields);

void main() {
  test('dispatches each op type to the matching entry point, in order', () async {
    final e = _RecordingEmitter();
    final failures = await e.replayCapturedOps([
      _op('fields', 'a', SyncRecordOpType.create, {'x': 1}),
      _op('fields', 'b', SyncRecordOpType.update, {'y': 2}),
      _op('values', 'c', SyncRecordOpType.delete),
    ]);

    expect(failures, isEmpty);
    expect(e.calls, ['create:fields:a', 'update:fields:b', 'delete:values:c']);
  });

  test('empty list is a no-op', () async {
    final e = _RecordingEmitter();
    expect(await e.replayCapturedOps(const []), isEmpty);
    expect(e.calls, isEmpty);
  });

  test(
    'a throwing op is collected into failures and does NOT abort the rest',
    () async {
      final e = _RecordingEmitter(throwOnEntityIds: {'bad'});
      final failures = await e.replayCapturedOps([
        _op('t', 'a', SyncRecordOpType.create),
        _op('t', 'bad', SyncRecordOpType.create),
        _op('t', 'c', SyncRecordOpType.delete),
      ]);

      // Exactly the failed op is returned, identity-preserved.
      expect(failures.map((o) => o.entityId), ['bad']);
      // Survivors still dispatched, in order; the failed op recorded nothing.
      expect(e.calls, ['create:t:a', 'delete:t:c']);
    },
  );

  test('multiple failures are all collected, in encounter order', () async {
    final e = _RecordingEmitter(throwOnEntityIds: {'b', 'd'});
    final failures = await e.replayCapturedOps([
      _op('t', 'a', SyncRecordOpType.create),
      _op('t', 'b', SyncRecordOpType.update),
      _op('t', 'c', SyncRecordOpType.delete),
      _op('t', 'd', SyncRecordOpType.create),
    ]);

    expect(failures.map((o) => o.entityId), ['b', 'd']);
    expect(e.calls, ['create:t:a', 'delete:t:c']);
  });

  test('a per-op failure is reported with the given logLabel + warning severity',
      () async {
    final reported = <AppError>[];
    void listener(AppError err) => reported.add(err);
    ErrorReportingService.instance.addListener(listener);
    addTearDown(() => ErrorReportingService.instance.removeListener(listener));

    final e = _RecordingEmitter(throwOnEntityIds: {'x'});
    await e.replayCapturedOps(
      [_op('tbl', 'x', SyncRecordOpType.create)],
      logLabel: 'My batch',
    );

    final mine =
        reported.where((r) => r.message.contains('My batch replay failed'));
    expect(mine, hasLength(1));
    expect(mine.single.severity, ErrorSeverity.warning);
    expect(mine.single.message, startsWith('My batch replay failed for tbl/x'));
  });

  test('default logLabel is "Sync"', () async {
    final reported = <AppError>[];
    void listener(AppError err) => reported.add(err);
    ErrorReportingService.instance.addListener(listener);
    addTearDown(() => ErrorReportingService.instance.removeListener(listener));

    final e = _RecordingEmitter(throwOnEntityIds: {'z'});
    await e.replayCapturedOps([_op('tbl', 'z', SyncRecordOpType.update)]);

    expect(
      reported.where((r) => r.message.startsWith('Sync replay failed for tbl/z')),
      hasLength(1),
    );
  });
}
