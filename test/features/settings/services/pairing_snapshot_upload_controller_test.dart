import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/features/settings/services/pairing_snapshot_upload_controller.dart';

class _FakeHandle implements ffi.PrismSyncHandle {
  const _FakeHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records every core call in order and lets each one be gated/scripted.
class _RecordingApi extends PairingCeremonyApi {
  _RecordingApi({
    this.verifyResult = true,
    this.verifyHandler,
    this.uploadHandler,
    this.completionHandler,
    this.capabilityState = ffi.SnapshotUploadCapabilityState.available,
  });

  final List<String> calls = <String>[];
  bool verifyResult;
  ffi.SnapshotUploadCapabilityState capabilityState;

  Future<bool> Function()? verifyHandler;
  Future<ffi.ResumableSnapshotUploadResult> Function()? uploadHandler;
  Future<ffi.ResumableCeremonyCompletion> Function({
    required List<int> password,
    required List<int> mnemonic,
  })?
  completionHandler;

  final List<List<int>> passwordsSeen = <List<int>>[];
  final List<List<int>> mnemonicsSeen = <List<int>>[];

  /// The exact buffer instances core was handed, retained so tests can assert
  /// the controller zeroes them.
  final List<List<int>> rawPasswords = <List<int>>[];
  final List<List<int>> rawMnemonics = <List<int>>[];
  final List<BigInt?> ttlSeen = <BigInt?>[];
  int cancelCount = 0;

  @override
  Future<bool> verifyInitiatorConfirmationResumable({
    required ffi.PrismSyncHandle handle,
  }) {
    calls.add('verify');
    return verifyHandler?.call() ?? Future<bool>.value(verifyResult);
  }

  @override
  Future<ffi.ResumableSnapshotUploadResult> uploadPairingSnapshotResumable({
    required ffi.PrismSyncHandle handle,
    BigInt? ttlSecs,
  }) {
    calls.add('upload');
    ttlSeen.add(ttlSecs);
    return uploadHandler?.call() ??
        Future<ffi.ResumableSnapshotUploadResult>.value(_resumableResult());
  }

  @override
  Future<ffi.ResumableCeremonyCompletion> completeInitiatorResumableCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) {
    calls.add('complete');
    rawPasswords.add(password);
    rawMnemonics.add(mnemonic);
    passwordsSeen.add(List<int>.of(password));
    mnemonicsSeen.add(List<int>.of(mnemonic));
    return completionHandler?.call(password: password, mnemonic: mnemonic) ??
        Future<ffi.ResumableCeremonyCompletion>.value(
          const ffi.ResumableCeremonyCompletion(
            completed: true,
            leaseActive: true,
            leaseRenewed: true,
            leaseCapable: true,
          ),
        );
  }

  @override
  Future<ffi.SnapshotUploadCapabilityInfo> snapshotUploadCapability({
    required ffi.PrismSyncHandle handle,
  }) {
    calls.add('capability');
    return Future<ffi.SnapshotUploadCapabilityInfo>.value(
      ffi.SnapshotUploadCapabilityInfo(
        state: capabilityState,
        version: capabilityState == ffi.SnapshotUploadCapabilityState.available
            ? 1
            : 0,
        chunkBytes: 1024,
        maxWireBytes: 1 << 20,
      ),
    );
  }

  @override
  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle}) {
    calls.add('cancel');
    cancelCount++;
    return Future<void>.value();
  }

  // Not used by the controller; kept abstract-satisfying.
  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
  }) => throw UnimplementedError();

  @override
  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  }) => throw UnimplementedError();

  @override
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) => throw UnimplementedError();
}

ffi.ResumableSnapshotUploadResult _resumableResult({
  int committed = 2048,
  int total = 2048,
  bool leaseActive = true,
}) {
  return ffi.ResumableSnapshotUploadResult(
    transport: ffi.SnapshotTransportUsed.resumable,
    uploadId: 'server-session',
    committedBytes: committed,
    totalBytes: total,
    leaseActive: leaseActive,
    leaseRenewed: leaseActive,
  );
}

ffi.ResumableSnapshotUploadResult _singlePutResult({bool leaseActive = false}) {
  return ffi.ResumableSnapshotUploadResult(
    transport: ffi.SnapshotTransportUsed.singlePut,
    uploadId: '',
    committedBytes: 4096,
    totalBytes: 4096,
    leaseActive: leaseActive,
    leaseRenewed: false,
  );
}

const String _mnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

/// The exact PIN bytes the sheet hands to [PairingSnapshotUploadController.run]
/// after draining its buffer synchronously: ASCII `'1'`..`'6'`.
Uint8List _pinBytes() =>
    Uint8List.fromList([0x31, 0x32, 0x33, 0x34, 0x35, 0x36]);

SyncEvent _progress({required int sent, required int total}) {
  return SyncEvent.fromJson({
    'type': 'SnapshotUploadProgress',
    'bytes_sent': sent,
    'bytes_total': total,
  });
}

PairingSnapshotUploadController _controller(
  _RecordingApi api, {
  void Function(PairingCeremonyPhase)? onPhase,
  void Function(PairingProgressUpdate)? onProgress,
  void Function(ffi.ResumableSnapshotUploadResult)? onUploadResolved,
}) {
  return PairingSnapshotUploadController(
    handle: const _FakeHandle(),
    api: api,
    onPhaseChanged: onPhase,
    onProgress: onProgress,
    onUploadResolved: onUploadResolved,
  );
}

void main() {
  group('PairingSnapshotUploadController ordering', () {
    test(
      'calls verify → upload → complete exactly once, in that order',
      () async {
        final api = _RecordingApi();
        final controller = _controller(api);

        final ok = await controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );

        expect(ok, isTrue);
        // The capability probe is UX-only and may interleave anywhere; the three
        // ceremony steps must not.
        expect(
          api.calls.where((c) => c != 'capability').toList(),
          equals(['verify', 'upload', 'complete']),
        );
        expect(api.ttlSeen.single, pairingSnapshotTtlSeconds);
        expect(controller.phase, PairingCeremonyPhase.completed);
      },
    );

    test(
      'emits verifying → uploading → finalizing → completed phases',
      () async {
        final api = _RecordingApi();
        final phases = <PairingCeremonyPhase>[];
        final controller = _controller(api, onPhase: phases.add);

        await controller.run(pinBytes: _pinBytes(), mnemonic: _mnemonic);

        expect(phases, [
          PairingCeremonyPhase.verifying,
          PairingCeremonyPhase.uploading,
          PairingCeremonyPhase.finalizing,
          PairingCeremonyPhase.completed,
        ]);
      },
    );

    test('never calls complete when the upload fails', () async {
      final api = _RecordingApi(
        uploadHandler: () =>
            Future<ffi.ResumableSnapshotUploadResult>.error(StateError('boom')),
      );
      final controller = _controller(api);

      final ok = await controller.run(
        pinBytes: _pinBytes(),
        mnemonic: _mnemonic,
      );

      expect(ok, isFalse);
      expect(api.calls, contains('upload'));
      expect(api.calls, isNot(contains('complete')));
      expect(api.passwordsSeen, isEmpty);
      expect(controller.phase, PairingCeremonyPhase.failed);
    });

    test('never calls complete when verification fails', () async {
      final api = _RecordingApi(
        verifyHandler: () => Future<bool>.error(StateError('no joiner')),
      );
      final controller = _controller(api);

      final ok = await controller.run(
        pinBytes: _pinBytes(),
        mnemonic: _mnemonic,
      );

      expect(ok, isFalse);
      expect(api.calls, isNot(contains('upload')));
      expect(api.calls, isNot(contains('complete')));
      expect(controller.phase, PairingCeremonyPhase.failed);
    });

    test(
      'treats completed:false from core as a failure, not a success',
      () async {
        final api = _RecordingApi(
          completionHandler: ({required password, required mnemonic}) =>
              Future<ffi.ResumableCeremonyCompletion>.value(
                const ffi.ResumableCeremonyCompletion(
                  completed: false,
                  leaseActive: true,
                  leaseRenewed: false,
                  leaseCapable: true,
                ),
              ),
        );
        final controller = _controller(api);

        final ok = await controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );

        expect(ok, isFalse);
        expect(controller.phase, PairingCeremonyPhase.failed);
      },
    );

    test(
      'hands the caller-owned PIN bytes to core and zeroes only its own copy',
      () async {
        final api = _RecordingApi();
        final controller = _controller(api);
        final pinBytes = _pinBytes();

        await controller.run(pinBytes: pinBytes, mnemonic: _mnemonic);

        // What core received must decode correctly...
        expect(
          api.passwordsSeen.single,
          equals([0x31, 0x32, 0x33, 0x34, 0x35, 0x36]),
        );
        expect(
          String.fromCharCodes(api.mnemonicsSeen.single),
          equals(_mnemonic),
        );
        // ...the run-owned mnemonic copy is zeroed once the run returns...
        expect(api.rawMnemonics.single, everyElement(0));
        // ...and the PIN buffer stays caller-owned: the controller must not zero
        // it, because the sheet owns its lifecycle and overwrites it in its own
        // `finally` after step 3.
        expect(pinBytes, equals([0x31, 0x32, 0x33, 0x34, 0x35, 0x36]));
      },
    );

    test(
      'forwards the caller\'s buffer without copying or retaining it',
      () async {
        final api = _RecordingApi();
        final controller = _controller(api);
        final pinBytes = _pinBytes();

        await controller.run(pinBytes: pinBytes, mnemonic: _mnemonic);

        // Identity, not just equality: step 3 receives the caller's own buffer
        // (so nothing PIN-shaped is duplicated or held by the controller), and
        // the caller is still free to overwrite it in its own `finally`.
        expect(identical(api.rawPasswords.single, pinBytes), isTrue);
      },
    );
  });

  group('PairingSnapshotUploadController cancellation', () {
    test(
      'cancel does not await the in-flight upload and ignores its late result',
      () async {
        final uploadCompleter = Completer<ffi.ResumableSnapshotUploadResult>();
        final verifyGate = Completer<void>();
        final api = _RecordingApi(
          verifyHandler: () async {
            await verifyGate.future;
            return true;
          },
          uploadHandler: () => uploadCompleter.future,
        );
        final phases = <PairingCeremonyPhase>[];
        final controller = _controller(api, onPhase: phases.add);

        final runFuture = controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );
        // Let the run reach the upload.
        await Future<void>.delayed(Duration.zero);
        verifyGate.complete();
        await Future<void>.delayed(Duration.zero);

        expect(controller.phase, PairingCeremonyPhase.uploading);

        // Cancelling must complete promptly and drive the UI phase from the
        // cancel result, without waiting for the upload future.
        await controller.cancel();
        expect(controller.phase, PairingCeremonyPhase.cancelled);
        expect(phases, contains(PairingCeremonyPhase.cancelled));
        expect(api.cancelCount, 1);

        // The abandoned upload finishes late. It must not reach step 3, must not
        // change the phase, and must not complete the run as a success.
        uploadCompleter.complete(_resumableResult());
        final ok = await runFuture;

        expect(ok, isFalse);
        expect(api.calls, isNot(contains('complete')));
        expect(controller.phase, PairingCeremonyPhase.cancelled);
      },
    );

    test(
      'cancel ignores a late upload error without an unhandled async error',
      () async {
        final uploadCompleter = Completer<ffi.ResumableSnapshotUploadResult>();
        final verifyGate = Completer<void>();
        final api = _RecordingApi(
          verifyHandler: () async {
            await verifyGate.future;
            return true;
          },
          uploadHandler: () => uploadCompleter.future,
        );
        final controller = _controller(api);

        final runFuture = controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );
        await Future<void>.delayed(Duration.zero);
        verifyGate.complete();
        await Future<void>.delayed(Duration.zero);

        unawaited(controller.cancel());
        uploadCompleter.completeError(StateError('late failure'));

        final ok = await runFuture;
        expect(ok, isFalse);
        expect(controller.phase, PairingCeremonyPhase.cancelled);
        expect(api.calls, isNot(contains('complete')));
      },
    );

    test(
      'dispose drops callbacks and suppresses later phase/progress mutation',
      () async {
        final uploadCompleter = Completer<ffi.ResumableSnapshotUploadResult>();
        final verifyGate = Completer<void>();
        final api = _RecordingApi(
          verifyHandler: () async {
            await verifyGate.future;
            return true;
          },
          uploadHandler: () => uploadCompleter.future,
        );
        final phases = <PairingCeremonyPhase>[];
        final progress = <PairingProgressUpdate>[];
        final controller = _controller(
          api,
          onPhase: phases.add,
          onProgress: progress.add,
        );

        final runFuture = controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );
        await Future<void>.delayed(Duration.zero);
        verifyGate.complete();
        await Future<void>.delayed(Duration.zero);

        final phasesBeforeDispose = phases.length;
        final progressBeforeDispose = progress.length;
        controller.dispose();

        controller.handleSyncEvent(_progress(sent: 100, total: 200));
        uploadCompleter.complete(_resumableResult());
        final ok = await runFuture;

        expect(ok, isFalse);
        expect(phases.length, phasesBeforeDispose);
        expect(progress.length, progressBeforeDispose);
        expect(api.calls, isNot(contains('complete')));
      },
    );

    test('cancelled run reports no published upload', () async {
      final uploadCompleter = Completer<ffi.ResumableSnapshotUploadResult>();
      final verifyGate = Completer<void>();
      final api = _RecordingApi(
        verifyHandler: () async {
          await verifyGate.future;
          return true;
        },
        uploadHandler: () => uploadCompleter.future,
      );
      final controller = _controller(api);

      final runFuture = controller.run(
        pinBytes: _pinBytes(),
        mnemonic: _mnemonic,
      );
      await Future<void>.delayed(Duration.zero);
      verifyGate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(controller.uploadPublished, isFalse);
      unawaited(controller.cancel());
      uploadCompleter.complete(_resumableResult());
      await runFuture;

      expect(controller.uploadPublished, isFalse);
      expect(controller.isCancelled, isTrue);
    });
  });

  group('PairingSnapshotUploadController transport handling', () {
    test(
      'singlePut fallback completes the ceremony and is not an error',
      () async {
        final api = _RecordingApi(
          uploadHandler: () => Future.value(_singlePutResult()),
        );
        final resolved = <ffi.ResumableSnapshotUploadResult>[];
        final controller = _controller(api, onUploadResolved: resolved.add);

        final ok = await controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );

        expect(ok, isTrue);
        expect(api.calls, contains('complete'));
        expect(resolved.single.transport, ffi.SnapshotTransportUsed.singlePut);
        // A downgrade must never promise slow-link survival...
        expect(controller.resumableTransfer, isFalse);
        // ...and with no streamed progress at all there is no total to show.
        expect(controller.showByteProgress, isFalse);
        expect(controller.phase, PairingCeremonyPhase.completed);
      },
    );

    test(
      'singlePut keeps determinate byte progress once the stream reported a total',
      () async {
        // Core emits SnapshotUploadProgress for whichever transport it picks, so a
        // relay that downgrades mid-flight must not tear the bar back from
        // determinate to indeterminate at resolution.
        final uploadGate = Completer<ffi.ResumableSnapshotUploadResult>();
        final api = _RecordingApi(uploadHandler: () => uploadGate.future);
        final updates = <PairingProgressUpdate>[];
        final controller = _controller(api, onProgress: updates.add);

        final runFuture = controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        // Mid-flight: the stream has reported a total, so the bar is determinate.
        controller.handleSyncEvent(_progress(sent: 1024, total: 8192));
        expect(controller.showByteProgress, isTrue);
        final midFlight = updates.last;
        expect(midFlight.showByteProgress, isTrue);
        expect(midFlight.bytesSent, 1024);
        expect(midFlight.bytesTotal, 8192);

        // Resolution reports single PUT with its own (unusable) terminal counts.
        uploadGate.complete(_singlePutResult());
        expect(await runFuture, isTrue);

        final resolved = updates.last;
        expect(
          resolved.showByteProgress,
          isTrue,
          reason: 'must not snap to indeterminate',
        );
        expect(
          resolved.bytesSent,
          1024,
          reason: 'terminal single-PUT bytes are ignored',
        );
        expect(resolved.bytesTotal, 8192);
        expect(resolved.resumableTransfer, isFalse);
        expect(controller.phase, PairingCeremonyPhase.completed);
      },
    );

    test(
      'resumable transport with a lease reports byte progress and resumability',
      () async {
        final api = _RecordingApi(
          uploadHandler: () =>
              Future.value(_resumableResult(committed: 512, total: 4096)),
        );
        final updates = <PairingProgressUpdate>[];
        final controller = _controller(
          api,
          onProgress: updates.add,
          onUploadResolved: (result) {},
        );

        await controller.run(pinBytes: _pinBytes(), mnemonic: _mnemonic);

        expect(controller.resumableTransfer, isTrue);
        expect(controller.showByteProgress, isTrue);
        expect(controller.leaseActive, isTrue);
        final last = updates.last;
        expect(last.resumableTransfer, isTrue);
        expect(last.showByteProgress, isTrue);
        expect(last.bytesSent, 512);
        expect(last.bytesTotal, 4096);
      },
    );

    test(
      'legacy non-lease resumable transfer does not promise slow links',
      () async {
        final completionGate = Completer<void>();
        final api = _RecordingApi(
          verifyResult: false,
          uploadHandler: () =>
              Future.value(_resumableResult(leaseActive: false)),
          completionHandler: ({required password, required mnemonic}) async {
            await completionGate.future;
            return const ffi.ResumableCeremonyCompletion(
              completed: true,
              leaseActive: false,
              leaseRenewed: false,
              leaseCapable: false,
            );
          },
        );
        final updates = <PairingProgressUpdate>[];
        final controller = _controller(api, onProgress: updates.add);

        final runFuture = controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );
        // Let the upload resolve while the credential-release half is still open,
        // so the mid-flow messaging state is observable.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(api.calls, contains('upload'));
        expect(controller.leaseActive, isFalse);
        expect(controller.resumableTransfer, isFalse);
        // Every update delivered during the upload must also withhold the promise.
        expect(updates, isNotEmpty);
        expect(updates.every((u) => u.resumableTransfer == false), isTrue);

        completionGate.complete();
        expect(await runFuture, isTrue);
      },
    );

    test(
      'capability probe is UX-only and never changes the calls made',
      () async {
        final api = _RecordingApi(
          capabilityState: ffi.SnapshotUploadCapabilityState.unavailable,
        );
        final controller = _controller(api);

        final ok = await controller.run(
          pinBytes: _pinBytes(),
          mnemonic: _mnemonic,
        );

        expect(ok, isTrue);
        expect(
          api.calls.where((c) => c != 'capability').toList(),
          equals(['verify', 'upload', 'complete']),
        );
        expect(controller.resumableExpectedHint, isFalse);
      },
    );

    test('a failing capability probe is ignored', () async {
      final api = _RecordingApi();
      final controller = PairingSnapshotUploadController(
        handle: const _FakeHandle(),
        api: _ProbeThrowingApi(api),
      );

      final ok = await controller.run(
        pinBytes: _pinBytes(),
        mnemonic: _mnemonic,
      );

      expect(ok, isTrue);
      expect(api.calls, contains('complete'));
    });
  });

  group('PairingSnapshotUploadController progress', () {
    test('progress is monotonic in both directions', () async {
      final uploadGate = Completer<ffi.ResumableSnapshotUploadResult>();
      final api = _RecordingApi(uploadHandler: () => uploadGate.future);
      final updates = <PairingProgressUpdate>[];
      final controller = _controller(api, onProgress: updates.add);

      final runFuture = controller.run(
        pinBytes: _pinBytes(),
        mnemonic: _mnemonic,
      );
      await Future<void>.delayed(Duration.zero);

      controller.handleSyncEvent(_progress(sent: 500, total: 2000));
      controller.handleSyncEvent(_progress(sent: 1500, total: 2000));
      // A duplicated / reordered acknowledgement must not rewind the bar.
      controller.handleSyncEvent(_progress(sent: 900, total: 2000));
      controller.handleSyncEvent(_progress(sent: 2000, total: 2000));

      // The first emission (run start) carries no byte counts at all; the
      // monotonic clamp must still never move backwards afterwards.
      final reported = updates
          .map((u) => u.bytesSent)
          .whereType<int>()
          .toList();
      expect(reported, [500, 1500, 2000]);
      expect(reported, isNot(contains(greaterThan(2000))));
      expect(updates.lastWhere((u) => u.bytesSent != null).bytesSent, 2000);

      uploadGate.complete(_resumableResult(committed: 2000, total: 2000));
      await runFuture;
    });

    test('progress is not reported before a run starts', () {
      final api = _RecordingApi();
      final updates = <PairingProgressUpdate>[];
      final controller = _controller(api, onProgress: updates.add);

      controller.handleSyncEvent(_progress(sent: 10, total: 100));

      expect(updates, isEmpty);
    });

    test(
      'transport resolution wins over an optimistically-expected resumable hint',
      () async {
        // The probe says resumable, but core actually used the single PUT.
        final api = _RecordingApi(
          capabilityState: ffi.SnapshotUploadCapabilityState.available,
          uploadHandler: () => Future.value(_singlePutResult()),
        );
        final updates = <PairingProgressUpdate>[];
        final controller = _controller(api, onProgress: updates.add);

        await controller.run(pinBytes: _pinBytes(), mnemonic: _mnemonic);

        expect(controller.resumableExpectedHint, isTrue);
        expect(updates.last.resumableTransfer, isFalse);
        expect(updates.last.showByteProgress, isFalse);
      },
    );

    test('a retry starts from clean state', () async {
      final api = _RecordingApi(
        uploadHandler: () => Future<ffi.ResumableSnapshotUploadResult>.error(
          StateError('first'),
        ),
      );
      final updates = <PairingProgressUpdate>[];
      final controller = _controller(api, onProgress: updates.add);

      final first = await controller.run(
        pinBytes: _pinBytes(),
        mnemonic: _mnemonic,
      );
      expect(first, isFalse);
      expect(controller.phase, PairingCeremonyPhase.failed);

      // Second attempt succeeds on the resumable transport.
      api.uploadHandler = () =>
          Future.value(_resumableResult(committed: 64, total: 128));
      updates.clear();

      final second = await controller.run(
        pinBytes: _pinBytes(),
        mnemonic: _mnemonic,
      );

      expect(second, isTrue);
      expect(controller.phase, PairingCeremonyPhase.completed);
      expect(controller.uploadPublished, isTrue);
      // The failed attempt must not leak its transport/progress into the retry.
      expect(updates.first.bytesSent, isNull);
      expect(updates.first.bytesTotal, isNull);
    });
  });

  group('pairingSnapshotTtlSeconds', () {
    test('is 86400 seconds', () {
      expect(pairingSnapshotTtlSeconds, BigInt.from(86400));
    });
  });
}

/// Wraps a recording API but fails the capability probe.
class _ProbeThrowingApi extends PairingCeremonyApi {
  _ProbeThrowingApi(this._inner);

  final _RecordingApi _inner;

  @override
  Future<ffi.SnapshotUploadCapabilityInfo> snapshotUploadCapability({
    required ffi.PrismSyncHandle handle,
  }) => Future<ffi.SnapshotUploadCapabilityInfo>.error(
    StateError('probe unavailable'),
  );

  @override
  Future<bool> verifyInitiatorConfirmationResumable({
    required ffi.PrismSyncHandle handle,
  }) => _inner.verifyInitiatorConfirmationResumable(handle: handle);

  @override
  Future<ffi.ResumableSnapshotUploadResult> uploadPairingSnapshotResumable({
    required ffi.PrismSyncHandle handle,
    BigInt? ttlSecs,
  }) => _inner.uploadPairingSnapshotResumable(handle: handle, ttlSecs: ttlSecs);

  @override
  Future<ffi.ResumableCeremonyCompletion> completeInitiatorResumableCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) => _inner.completeInitiatorResumableCeremony(
    handle: handle,
    password: password,
    mnemonic: mnemonic,
  );

  @override
  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle}) =>
      _inner.cancelPairingCeremony(handle: handle);

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
  }) => throw UnimplementedError();

  @override
  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  }) => throw UnimplementedError();

  @override
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) => throw UnimplementedError();
}
