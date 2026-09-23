import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    show AppDatabase;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

class _Handle implements ffi.PrismSyncHandle {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WatchdogTimer implements Timer {
  _WatchdogTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }

  @override
  void cancel() => isActive = false;
}

typedef _Emission = ({
  String table,
  List<String> ids,
  ffi.PrismSyncHandle handle,
});

late _Api _api;

class _Proxy implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => _api.noSuchMethod(invocation);
}

class _Api implements RustLibApi {
  bool deferNextFront = false;
  Future<void> Function()? beforeEmission;
  final emitted = <_Emission>[];
  final pushed = <_Emission>[];
  final _pending = <_Emission>[];
  Completer<void> nextFront = Completer<void>();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #crateApiRecordCreateAt:
      case #crateApiRecordUpdateAt:
      case #crateApiRecordDeleteMulti:
        return Future<void>.delayed(const Duration(milliseconds: 10), () async {
          await beforeEmission?.call();
          final args = invocation.namedArguments;
          final emission = (
            table: args[#table] as String,
            ids:
                args[#entityIds] as List<String>? ??
                [args[#entityId] as String],
            handle: args[#handle] as ffi.PrismSyncHandle,
          );
          if (emission.table == 'fronting_sessions' && deferNextFront) {
            deferNextFront = false;
            throw StateError('sync not configured');
          }
          emitted.add(emission);
          _pending.add(emission);
          if (emission.table == 'fronting_sessions' && !nextFront.isCompleted) {
            nextFront.complete();
          }
        });
      case #crateApiReconnectWebsocket:
        return Future<void>.value();
      case #crateApiSyncNow:
        pushed.addAll(_pending);
        _pending.clear();
        return Future<String>.value('{"error":null}');
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _Proxy()));

  for (final background in [false, true]) {
    group('front outbox (background=$background)', () {
      late Directory directory;
      late AppDatabase db;
      late _Handle handle;
      late DriftMemberRepository members;
      late DriftFrontingSessionRepository fronts;
      late MutationRunner runner;
      late FrontingMutationService service;

      setUp(() async {
        ErrorReportingService.instance.clear();
        directory = Directory.systemTemp.createTempSync('prism-front-outbox-');
        final file = File('${directory.path}/app.sqlite');
        db = AppDatabase(
          background
              ? NativeDatabase.createInBackground(file)
              : NativeDatabase(file),
        );
        handle = _Handle();
        _api = _Api();
        syncCredentialsPersisted.value = true;
        syncCurrentHandle.value = handle;
        await triggerOutboxDrain(db, handle);
        members = DriftMemberRepository(db.membersDao, handle);
        fronts = DriftFrontingSessionRepository(db.frontingSessionsDao, handle);
        runner = MutationRunner.forDatabase(
          db,
          onCommitted: () =>
              unawaited(triggerInstalledOutboxDrain(syncCurrentHandle.value)),
        );
        service = FrontingMutationService(
          repository: fronts,
          memberRepository: members,
          lifecycle: SessionLifecycleService(memberRepository: members),
          mutationRunner: runner,
        );
        await members.createMember(
          Member(id: 'member', name: 'Test', createdAt: DateTime.now()),
        );
        await syncNowAfterOutboxDrain(db: db, handle: handle);
        expect(_api.pushed.single.table, 'members');
        _api.emitted.clear();
        _api.pushed.clear();
      });

      tearDown(() async {
        debugDisposeOutboxDrainForTesting();
        syncCredentialsPersisted.value = false;
        syncCurrentHandle.value = null;
        await db.close();
        directory.deleteSync(recursive: true);
      });

      for (final fireWatchdog in [false, true]) {
        test(
          'transaction drain watchdog cancels on completion (fire=$fireWatchdog)',
          () async {
            final watchdogs = <_WatchdogTimer>[];
            await runZoned(
              () async {
                await db.transaction(() async {
                  await fronts.createSession(
                    FrontingSession(
                      id: 'watchdog',
                      memberId: 'member',
                      startTime: DateTime.now(),
                    ),
                  );
                  expect(watchdogs, hasLength(1));
                  if (fireWatchdog) watchdogs.single.fire();
                });
                await syncNowAfterOutboxDrain(db: db, handle: handle);
              },
              zoneSpecification: ZoneSpecification(
                createTimer: (self, parent, zone, duration, callback) {
                  if (duration == const Duration(seconds: 10)) {
                    final timer = _WatchdogTimer(zone.bindCallback(callback));
                    watchdogs.add(timer);
                    return timer;
                  }
                  return parent.createTimer(zone, duration, callback);
                },
              ),
            );
            expect(watchdogs.single.isActive, isFalse);
            watchdogs.single.fire();
            expect(
              ErrorReportingService.instance.errors.where(
                (error) => error.message.contains('Do not await'),
              ),
              hasLength(fireWatchdog ? 1 : 0),
            );
            expect(await db.syncOutboxDao.count(), 0);
          },
        );
      }

      for (final resetFirst in [false, true]) {
        test(
          'close during emission reports failure and recovers (reset=$resetFirst)',
          () async {
            final started = Completer<void>();
            final release = Completer<void>();
            if (resetFirst) {
              void failingListener(AppError error) =>
                  throw StateError('listener failure');
              ErrorReportingService.instance.addListener(failingListener);
              addTearDown(
                () => ErrorReportingService.instance.removeListener(
                  failingListener,
                ),
              );
            }
            _api.beforeEmission = () {
              started.complete();
              return release.future;
            };
            await fronts.createSession(
              FrontingSession(
                id: 'closing',
                memberId: 'member',
                startTime: DateTime.now(),
              ),
            );
            await started.future.timeout(const Duration(seconds: 2));
            final manual = syncNowAfterOutboxDrain(db: db, handle: handle);
            final failed = expectLater(manual, throwsA(isA<StateError>()));
            if (resetFirst) debugDisposeOutboxDrainForTesting();
            await db.close();
            release.complete();
            await failed;
            expect(_api.pushed, isEmpty);
            expect(
              ErrorReportingService.instance.errors.any(
                (error) => error.message.contains('Sync outbox drain failed'),
              ),
              isTrue,
            );
            _api.beforeEmission = null;
            db = AppDatabase(
              background
                  ? NativeDatabase.createInBackground(
                      File('${directory.path}/app.sqlite'),
                    )
                  : NativeDatabase(File('${directory.path}/app.sqlite')),
            );
            expect(await db.syncOutboxDao.count(), 1);
            await syncNowAfterOutboxDrain(db: db, handle: handle);
            expect(await db.syncOutboxDao.count(), 0);
            expect(_api.pushed.any((op) => op.ids.contains('closing')), isTrue);
          },
        );
      }

      test(
        'closed backlog query remains an awaited error and can recover',
        () async {
          final captured = <CapturedSyncOp>[];
          await SyncRecordMixin.suppressAndCapture(
            () => fronts.createSession(
              FrontingSession(
                id: 'backlog',
                memberId: 'member',
                startTime: DateTime.now(),
              ),
            ),
            captured.add,
          );
          await SyncRecordMixin.persistCapturedOpsToOutbox(db, captured);
          await db.close();
          await expectLater(
            triggerOutboxDrain(db, null),
            throwsA(isA<StateError>()),
          );
          expect(
            ErrorReportingService.instance.errors.any(
              (error) => error.message.contains('Sync outbox drain failed'),
            ),
            isTrue,
          );
          db = AppDatabase(
            background
                ? NativeDatabase.createInBackground(
                    File('${directory.path}/app.sqlite'),
                  )
                : NativeDatabase(File('${directory.path}/app.sqlite')),
          );
          await syncNowAfterOutboxDrain(db: db, handle: handle);
          expect(await db.syncOutboxDao.count(), 0);
          expect(_api.pushed.single.ids, ['backlog']);
        },
      );

      test(
        'retry timer reports a closed database failure without losing rows',
        () async {
          final timers = <_WatchdogTimer>[];
          final reported = Completer<void>();
          void listener(AppError error) {
            if (error.message.contains('Sync outbox drain failed') &&
                !reported.isCompleted) {
              reported.complete();
            }
          }

          ErrorReportingService.instance.addListener(listener);
          addTearDown(
            () => ErrorReportingService.instance.removeListener(listener),
          );
          final captured = <CapturedSyncOp>[];
          await SyncRecordMixin.suppressAndCapture(
            () => fronts.createSession(
              FrontingSession(
                id: 'timer',
                memberId: 'member',
                startTime: DateTime.now(),
              ),
            ),
            captured.add,
          );
          await SyncRecordMixin.persistCapturedOpsToOutbox(db, captured);
          await runZoned(
            () => triggerOutboxDrain(db, null),
            zoneSpecification: ZoneSpecification(
              createTimer: (self, parent, zone, duration, callback) {
                if (duration == const Duration(seconds: 30)) {
                  final timer = _WatchdogTimer(zone.bindCallback(callback));
                  timers.add(timer);
                  return timer;
                }
                return parent.createTimer(zone, duration, callback);
              },
            ),
          );
          expect(timers, hasLength(1));
          await db.close();
          timers.single.fire();
          await reported.future.timeout(const Duration(seconds: 2));
          db = AppDatabase(
            background
                ? NativeDatabase.createInBackground(
                    File('${directory.path}/app.sqlite'),
                  )
                : NativeDatabase(File('${directory.path}/app.sqlite')),
          );
          await syncNowAfterOutboxDrain(db: db, handle: handle);
          expect(await db.syncOutboxDao.count(), 0);
          expect(_api.pushed.single.ids, ['timer']);
        },
      );

      for (final mutation in ['start', 'end', 'delete']) {
        test(
          '$mutation drains automatically and manual sync completes',
          () async {
            if (mutation != 'start') {
              await SyncRecordMixin.suppress(
                () => fronts.createSession(
                  FrontingSession(
                    id: 'existing-front',
                    memberId: 'member',
                    startTime: DateTime.now().subtract(
                      const Duration(minutes: 2),
                    ),
                    endTime: mutation == 'delete'
                        ? DateTime.now().subtract(const Duration(minutes: 1))
                        : null,
                  ),
                ),
              );
            }
            final result = switch (mutation) {
              'start' => await service.startFronting(['member']),
              'end' => await service.removeCoFronter('member'),
              _ => await service.executeDeleteOption(
                sessionId: 'existing-front',
                option: DeleteOption.delete,
                allSessions: await fronts.getAllSessions(),
              ),
            };
            expect(result.isSuccess, isTrue, reason: '${result.failureOrNull}');
            await _api.nextFront.future.timeout(const Duration(seconds: 2));
            await syncNowAfterOutboxDrain(
              db: db,
              handle: handle,
            ).timeout(const Duration(seconds: 2));
            expect(await db.syncOutboxDao.count(), 0);
            expect(
              _api.pushed.any((op) => op.table == 'fronting_sessions'),
              isTrue,
            );
            await members.deleteMember('member');
            await syncNowAfterOutboxDrain(db: db, handle: handle);
            expect(
              _api.pushed.any(
                (op) => op.table == 'members' && op.ids.contains('member'),
              ),
              isTrue,
            );
          },
        );
      }

      test(
        'outer rollback neither emits nor retains front or outbox rows',
        () async {
          await expectLater(
            db.transaction(() async {
              await fronts.createSession(
                FrontingSession(
                  id: 'rolled-back',
                  memberId: 'member',
                  startTime: DateTime.now(),
                ),
              );
              expect(await db.syncOutboxDao.count(), 1);
              await Future<void>.delayed(const Duration(milliseconds: 30));
              expect(_api.emitted, isEmpty);
              throw StateError('rollback');
            }),
            throwsStateError,
          );
          expect(await fronts.getSessionById('rolled-back'), isNull);
          expect(await db.syncOutboxDao.count(), 0);
          await syncNowAfterOutboxDrain(db: db, handle: handle);
          expect(_api.pushed, isEmpty);
        },
      );

      test(
        'outer capture remains responsible for nested repository emissions',
        () async {
          final captured = <CapturedSyncOp>[];
          await SyncRecordMixin.suppressAndCapture(
            () => fronts.createSession(
              FrontingSession(
                id: 'captured',
                memberId: 'member',
                startTime: DateTime.now(),
              ),
            ),
            captured.add,
          );
          expect(captured, hasLength(1));
          expect(await db.syncOutboxDao.count(), 0);
          expect(_api.emitted, isEmpty);
        },
      );

      test(
        'published handle takes precedence over repository fallback',
        () async {
          final replacement = _Handle();
          syncCurrentHandle.value = replacement;
          final result = await runner.run(
            action: () async {
              await fronts.createSession(
                FrontingSession(
                  id: 'new-handle',
                  memberId: 'member',
                  startTime: DateTime.now(),
                ),
              );
              expect(_api.emitted, isEmpty);
            },
          );
          expect(result.isSuccess, isTrue);
          await _api.nextFront.future.timeout(const Duration(seconds: 2));
          await syncNowAfterOutboxDrain(db: db, handle: replacement);
          expect(_api.emitted.single.handle, same(replacement));
          expect(await db.syncOutboxDao.count(), 0);
        },
      );

      test(
        'raw transaction drains and retries outside its closed zone',
        () async {
          var retries = 0;
          _api.deferNextFront = true;
          await runZoned(
            () async {
              await db.transaction(
                () => fronts.createSession(
                  FrontingSession(
                    id: 'retry',
                    memberId: 'member',
                    startTime: DateTime.now(),
                  ),
                ),
              );
              await _api.nextFront.future.timeout(const Duration(seconds: 2));
              await syncNowAfterOutboxDrain(db: db, handle: handle);
            },
            zoneSpecification: ZoneSpecification(
              createTimer: (self, parent, zone, duration, callback) {
                if (duration == const Duration(seconds: 30)) {
                  return parent.createTimer(
                    zone,
                    const Duration(milliseconds: 30),
                    () {
                      retries++;
                      expect(Zone.current[#DatabaseConnectionUser], isNull);
                      callback();
                    },
                  );
                }
                return parent.createTimer(zone, duration, callback);
              },
            ),
          );
          expect(retries, 1);
          expect(_api.pushed.single.ids, ['retry']);
          expect(await db.syncOutboxDao.count(), 0);
        },
      );

      test(
        'standalone grouped write drains nested repository emission',
        () async {
          await SyncRecordMixin.runSyncedDatabaseTransaction(
            db,
            () => fronts.createSession(
              FrontingSession(
                id: 'grouped',
                memberId: 'member',
                startTime: DateTime.now(),
              ),
            ),
            fallbackSyncHandle: handle,
          );
          await _api.nextFront.future.timeout(const Duration(seconds: 2));
          await syncNowAfterOutboxDrain(db: db, handle: handle);
          expect(_api.emitted, hasLength(1));
          expect(await db.syncOutboxDao.count(), 0);
        },
      );
    });
  }
}
