import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/relay_cleanup.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('cleanupRelayRegistration', () {
    test(
      'returns deregistered and does not call deleteSyncGroup on success',
      () async {
        const handle = _FakePrismSyncHandle();
        var deregisterCalls = 0;
        var deleteGroupCalls = 0;
        final logs = <String>[];

        final result = await cleanupRelayRegistration(
          handle: handle,
          syncId: 'sync',
          deviceId: 'dev',
          sessionToken: 'token',
          deregister:
              ({
                required ffi.PrismSyncHandle handle,
                required String syncId,
                required String deviceId,
                required String sessionToken,
              }) async {
                deregisterCalls++;
              },
          deleteSyncGroup:
              ({
                required ffi.PrismSyncHandle handle,
                required String syncId,
                required String deviceId,
                required String sessionToken,
              }) async {
                deleteGroupCalls++;
              },
          log: logs.add,
        );

        expect(result, RelayCleanupOutcome.deregistered);
        expect(deregisterCalls, 1);
        expect(deleteGroupCalls, 0);
        expect(logs, isEmpty);
      },
    );

    test('falls back to deleteSyncGroup on last-active-device 403', () async {
      const handle = _FakePrismSyncHandle();
      var deleteGroupCalls = 0;
      final logs = <String>[];

      final result = await cleanupRelayRegistration(
        handle: handle,
        syncId: 'sync',
        deviceId: 'dev',
        sessionToken: 'token',
        deregister:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              throw Exception(
                'HTTP 403: Cannot deregister the last active device; '
                'delete the sync group instead',
              );
            },
        deleteSyncGroup:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              deleteGroupCalls++;
            },
        log: logs.add,
      );

      expect(result, RelayCleanupOutcome.groupDeleted);
      expect(deleteGroupCalls, 1);
      expect(logs.any((l) => l.contains('Last device')), isTrue);
    });

    test('can leave relay group intact on last-active-device 403', () async {
      const handle = _FakePrismSyncHandle();
      var deleteGroupCalls = 0;
      final logs = <String>[];

      final result = await cleanupRelayRegistration(
        handle: handle,
        syncId: 'sync',
        deviceId: 'dev',
        sessionToken: 'token',
        deregister:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              throw Exception(
                'HTTP 403: Cannot deregister the last active device; '
                'delete the sync group instead',
              );
            },
        deleteSyncGroup:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              deleteGroupCalls++;
            },
        log: logs.add,
        fallbackOnLastActiveDevice: false,
      );

      expect(result, RelayCleanupOutcome.skippedLastActiveDevice);
      expect(deleteGroupCalls, 0);
      expect(logs.any((l) => l.contains('leaving relay state intact')), isTrue);
    });

    test('does not fall back to deleteSyncGroup on unrelated error', () async {
      const handle = _FakePrismSyncHandle();
      var deleteGroupCalls = 0;
      final logs = <String>[];

      final result = await cleanupRelayRegistration(
        handle: handle,
        syncId: 'sync',
        deviceId: 'dev',
        sessionToken: 'token',
        deregister:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              throw Exception('Network unreachable');
            },
        deleteSyncGroup:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              deleteGroupCalls++;
            },
        log: logs.add,
      );

      expect(result, RelayCleanupOutcome.failed);
      expect(
        deleteGroupCalls,
        0,
        reason:
            'must not fall back unless the relay returned the sole-device 403',
      );
      expect(logs.any((l) => l.contains('non-fatal')), isTrue);
    });

    test('returns fallbackFailed when deleteSyncGroup also throws', () async {
      const handle = _FakePrismSyncHandle();
      final logs = <String>[];

      final result = await cleanupRelayRegistration(
        handle: handle,
        syncId: 'sync',
        deviceId: 'dev',
        sessionToken: 'token',
        deregister:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              throw Exception('HTTP 403: last active device');
            },
        deleteSyncGroup:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              throw Exception('Relay 502');
            },
        log: logs.add,
      );

      expect(result, RelayCleanupOutcome.fallbackFailed);
      expect(logs.any((l) => l.contains('sync group delete failed')), isTrue);
    });

    // ── Fallback policy: default vs full-reset opt-in ────

    test('fallbackOnAnyDeregisterFailure: true forces deleteSyncGroup on any '
        'deregister error (full-reset semantics)', () async {
      const handle = _FakePrismSyncHandle();
      var deleteGroupCalls = 0;
      final logs = <String>[];

      final result = await cleanupRelayRegistration(
        handle: handle,
        syncId: 'sync',
        deviceId: 'dev',
        sessionToken: 'token',
        deregister:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              // Generic transient failure — neither last-active nor 403.
              throw Exception('Network unreachable');
            },
        deleteSyncGroup:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              deleteGroupCalls++;
            },
        log: logs.add,
        fallbackOnAnyDeregisterFailure: true,
      );

      expect(result, RelayCleanupOutcome.groupDeleted);
      expect(
        deleteGroupCalls,
        1,
        reason:
            'full reset must force deleteSyncGroup so the relay-side '
            'group does not linger after a transient deregister failure',
      );
      expect(
        logs.any((l) => l.contains('full reset forcing sync group deletion')),
        isTrue,
      );
    });

    test(
      'fallbackOnAnyDeregisterFailure: false (default) skips deleteSyncGroup '
      'on a non-last-active deregister error',
      () async {
        const handle = _FakePrismSyncHandle();
        var deleteGroupCalls = 0;
        final logs = <String>[];

        final result = await cleanupRelayRegistration(
          handle: handle,
          syncId: 'sync',
          deviceId: 'dev',
          sessionToken: 'token',
          deregister:
              ({
                required ffi.PrismSyncHandle handle,
                required String syncId,
                required String deviceId,
                required String sessionToken,
              }) async {
                throw Exception('HTTP 401: token expired');
              },
          deleteSyncGroup:
              ({
                required ffi.PrismSyncHandle handle,
                required String syncId,
                required String deviceId,
                required String sessionToken,
              }) async {
                deleteGroupCalls++;
              },
          log: logs.add,
          // explicit for clarity; this is also the default
          fallbackOnAnyDeregisterFailure: false,
        );

        expect(result, RelayCleanupOutcome.failed);
        expect(deleteGroupCalls, 0);
      },
    );

    test('fallbackOnAnyDeregisterFailure: true skips deleteSyncGroup when relay '
        'requires atomic revoke', () async {
      const handle = _FakePrismSyncHandle();
      var deleteGroupCalls = 0;
      final logs = <String>[];

      final result = await cleanupRelayRegistration(
        handle: handle,
        syncId: 'sync',
        deviceId: 'dev',
        sessionToken: 'token',
        deregister:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              throw Exception(
                'HTTP 409: use_atomic_revoke; self-deregister with active peers '
                'requires atomic revoke',
              );
            },
        deleteSyncGroup:
            ({
              required ffi.PrismSyncHandle handle,
              required String syncId,
              required String deviceId,
              required String sessionToken,
            }) async {
              deleteGroupCalls++;
            },
        log: logs.add,
        fallbackOnAnyDeregisterFailure: true,
      );

      expect(result, RelayCleanupOutcome.failed);
      expect(deleteGroupCalls, 0);
      expect(logs.any((l) => l.contains('requires atomic revoke')), isTrue);
    });
  });

  group('isLastActiveDeviceError (tightened detector)', () {
    test('true when both 403 marker AND substring are present', () {
      expect(
        isLastActiveDeviceError(
          Exception('HTTP 403: Cannot deregister the last active device'),
        ),
        isTrue,
      );
      expect(
        isLastActiveDeviceError(
          Exception('Forbidden { message: "last active device" }'),
        ),
        isTrue,
      );
    });

    test('false for HTTP 403 without the substring (auth/permission)', () {
      // Old `||` logic would have wrongly fired on this and triggered
      // a destructive deleteSyncGroup fallback.
      expect(
        isLastActiveDeviceError(Exception('HTTP 403: auth token rejected')),
        isFalse,
      );
    });

    test(
      'false for the substring without a 403 (unrelated 500 / status code)',
      () {
        expect(
          isLastActiveDeviceError(
            Exception('Cannot delete: last active device — internal error 500'),
          ),
          isFalse,
        );
      },
    );

    test('false for unrelated errors', () {
      expect(
        isLastActiveDeviceError(Exception('Network unreachable')),
        isFalse,
      );
      expect(isLastActiveDeviceError(Exception('Timeout after 30s')), isFalse);
      expect(
        isLastActiveDeviceError(Exception('HTTP 500: bad gateway')),
        isFalse,
      );
    });
  });

  group('isAtomicRevokeRequiredError', () {
    test('true for relay atomic-revoke conflicts', () {
      expect(
        isAtomicRevokeRequiredError(Exception('HTTP 409: use_atomic_revoke')),
        isTrue,
      );
      expect(
        isAtomicRevokeRequiredError(
          Exception(
            'Conflict: Self-deregister with active peers requires atomic revoke',
          ),
        ),
        isTrue,
      );
    });

    test('false for unrelated conflicts or messages', () {
      expect(
        isAtomicRevokeRequiredError(Exception('HTTP 409: snapshot stale')),
        isFalse,
      );
      expect(
        isAtomicRevokeRequiredError(Exception('requires atomic revoke')),
        isFalse,
      );
      expect(
        isAtomicRevokeRequiredError(Exception('HTTP 403: use_atomic_revoke')),
        isFalse,
      );
    });
  });

  group('parseFirstDeviceRollbackResult', () {
    test('parses no_op outcome with reason', () {
      final r = parseFirstDeviceRollbackResult(
        '{"outcome":"no_op","reason":"sync_id missing"}',
      );
      expect(r, isNotNull);
      expect(r!.isNoOp, isTrue);
      expect(r.reason, 'sync_id missing');
      expect(r.toLogLine(), contains('reason=sync_id missing'));
    });

    test('parses deregistered outcome', () {
      final r = parseFirstDeviceRollbackResult('{"outcome":"deregistered"}');
      expect(r, isNotNull);
      expect(r!.isDeregistered, isTrue);
      expect(r.toLogLine(), 'relay rollback: deregistered');
    });

    test('parses group_deleted outcome with fallback_from', () {
      final r = parseFirstDeviceRollbackResult(
        '{"outcome":"group_deleted","fallback_from":"last_active_device"}',
      );
      expect(r, isNotNull);
      expect(r!.isGroupDeleted, isTrue);
      expect(r.fallbackFrom, 'last_active_device');
    });

    test('parses failed outcome with stage and reason', () {
      final r = parseFirstDeviceRollbackResult(
        '{"outcome":"failed","stage":"deregister","reason":"network error"}',
      );
      expect(r, isNotNull);
      expect(r!.isFailed, isTrue);
      expect(r.stage, 'deregister');
      expect(r.reason, 'network error');
    });

    test('returns null on garbage JSON', () {
      expect(parseFirstDeviceRollbackResult('not json'), isNull);
      expect(parseFirstDeviceRollbackResult('{}'), isNull);
      expect(parseFirstDeviceRollbackResult('[]'), isNull);
    });
  });

  group('rollbackFirstDeviceRegistration', () {
    test('returns null when the FFI throws', () async {
      const handle = _FakePrismSyncHandle();
      final r = await rollbackFirstDeviceRegistration(
        handle: handle,
        rollbackFn: ({required ffi.PrismSyncHandle handle}) async {
          throw Exception('boom');
        },
      );
      expect(r, isNull);
    });

    test('parses the FFI envelope on success', () async {
      const handle = _FakePrismSyncHandle();
      final r = await rollbackFirstDeviceRegistration(
        handle: handle,
        rollbackFn: ({required ffi.PrismSyncHandle handle}) async =>
            '{"outcome":"deregistered"}',
      );
      expect(r, isNotNull);
      expect(r!.isDeregistered, isTrue);
    });
  });
}
