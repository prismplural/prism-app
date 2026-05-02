// Provider-level tests for [pairedDeviceCountProvider]'s null-handle
// discriminator.
//
// Fix Z's existing test (in `upgrade_modal_test.dart`) overrides the
// public-facing `pairedDeviceCountProvider` with a throwing future and asserts
// the modal's catch falls back to "ask role." That proves the modal's
// fallback works, but it does NOT exercise the actual `handle == null +
// syncIdProvider check` logic inside the real provider — the override
// short-circuits the provider body entirely.
//
// These tests run the real `pairedDeviceCountProvider` and pin its three
// distinct branches:
//   1. handle null + sync_id absent → 0 (genuinely unpaired, modal skips
//      role question).
//   2. handle null + sync_id present → throws (configured-but-broken; the
//      modal's catch falls back to pairedCount = 1, asks role).
//   3. handle non-null → counts active peers via deviceListProvider.
//
// Scenario 3 also overrides `deviceListProvider` because the real provider
// calls into the Rust FFI; we don't have a real handle in unit tests.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/settings/providers/device_management_provider.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandleNotifier extends PrismSyncHandleNotifier {
  _FakeHandleNotifier(this._handle);
  final ffi.PrismSyncHandle? _handle;

  @override
  Future<ffi.PrismSyncHandle?> build() async => _handle;
}

class _FakeDeviceListNotifier extends DeviceListNotifier {
  _FakeDeviceListNotifier(this._devices);
  final List<Device> _devices;

  @override
  Future<List<Device>> build() async => _devices;
}

Device _device(String id, {String status = 'active'}) =>
    Device(deviceId: id, epoch: 0, status: status);

void main() {
  group('pairedDeviceCountProvider null-handle discriminator', () {
    test('handle null + sync_id absent → 0 (genuinely unpaired)', () async {
      final container = ProviderContainer(
        overrides: [
          prismSyncHandleProvider.overrideWith(() => _FakeHandleNotifier(null)),
          syncIdProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final count = await container.read(pairedDeviceCountProvider.future);
      expect(count, 0);
    });

    test('handle null + sync_id empty → 0 (treated as absent)', () async {
      final container = ProviderContainer(
        overrides: [
          prismSyncHandleProvider.overrideWith(() => _FakeHandleNotifier(null)),
          syncIdProvider.overrideWith((ref) async => ''),
        ],
      );
      addTearDown(container.dispose);

      final count = await container.read(pairedDeviceCountProvider.future);
      expect(count, 0);
    });

    test(
      'handle null + sync_id present → throws (configured-but-broken)',
      () async {
        final container = ProviderContainer(
          overrides: [
            prismSyncHandleProvider.overrideWith(
              () => _FakeHandleNotifier(null),
            ),
            syncIdProvider.overrideWith((ref) async => 'sync-id-foo'),
          ],
        );
        addTearDown(container.dispose);

        // The provider must throw so the modal's existing try/catch falls
        // back to `pairedCount = 1` and shows the role question. Returning
        // 0 here would silently mis-classify a configured install as solo.
        await expectLater(
          container.read(pairedDeviceCountProvider.future),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'handle non-null + listDevices returns 2 active → 1 (peers exclude self)',
      () async {
        const handle = _FakePrismSyncHandle();
        final container = ProviderContainer(
          overrides: [
            prismSyncHandleProvider.overrideWith(
              () => _FakeHandleNotifier(handle),
            ),
            syncIdProvider.overrideWith((ref) async => 'sync-id-foo'),
            deviceListProvider.overrideWith(
              () => _FakeDeviceListNotifier([_device('d1'), _device('d2')]),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Two active devices → one peer (the count excludes self).
        final count = await container.read(pairedDeviceCountProvider.future);
        expect(count, 1);
      },
    );

    test('handle non-null + listDevices returns 3 active → 2', () async {
      const handle = _FakePrismSyncHandle();
      final container = ProviderContainer(
        overrides: [
          prismSyncHandleProvider.overrideWith(
            () => _FakeHandleNotifier(handle),
          ),
          syncIdProvider.overrideWith((ref) async => 'sync-id-foo'),
          deviceListProvider.overrideWith(
            () => _FakeDeviceListNotifier([
              _device('d1'),
              _device('d2'),
              _device('d3'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final count = await container.read(pairedDeviceCountProvider.future);
      expect(count, 2);
    });

    test(
      'handle non-null + listDevices returns 1 active + 1 revoked → 0',
      () async {
        const handle = _FakePrismSyncHandle();
        final container = ProviderContainer(
          overrides: [
            prismSyncHandleProvider.overrideWith(
              () => _FakeHandleNotifier(handle),
            ),
            syncIdProvider.overrideWith((ref) async => 'sync-id-foo'),
            deviceListProvider.overrideWith(
              () => _FakeDeviceListNotifier([
                _device('d1'),
                _device('d2', status: 'revoked'),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Only one active device (self), so 0 peers.
        final count = await container.read(pairedDeviceCountProvider.future);
        expect(count, 0);
      },
    );
  });
}
