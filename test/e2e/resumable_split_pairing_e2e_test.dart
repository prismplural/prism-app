// End-to-end coverage for the SPLIT resumable pairing surface, driven through
// the generated `prism_sync` FFI against the real Rust core and a real spawned
// relay.
//
// Unlike `pairing_snapshot_upload_controller_test.dart` /
// `device_pairing_provider_test.dart` (app-level fakes) and
// `prism-sync/dart/packages/prism_sync/test/resumable_ceremony_api_test.dart`
// (compile-time shape only), this file exercises the actual generated functions
// `verifyInitiatorConfirmationResumable` ->
// `uploadPairingSnapshotResumable` -> `completeInitiatorResumableCeremony`
// against real `PrismSyncHandle`s, the real core ceremony, and the real relay
// HTTP routes.
//
// Two relay shapes are used:
//
//  * "resumable": the test-only `test_relay` example started with
//    `TEST_RELAY_RESUMABLE=1` (see `TEST_RELAY_MEDIA_DIR`). That opts the
//    otherwise dark-by-default pairing lease and resumable snapshot-upload
//    capability on. This is a deliberate test-only relay configuration; no
//    production code or default behaviour changes.
//  * "dark": the plain `test_relay` default, which is what an old or
//    not-yet-enabled deployment looks like.
//
// Native-lane prerequisites are enforced by `e2eSkip()`; run with the same
// environment as `scripts/test_native.sh` (see `PRISM_SYNC_FFI_LIB` /
// `PRISM_SYNC_RELAY_BIN`).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

/// Raw size of the injected blob for the multi-chunk test.
///
/// The blob is incompressible, so the compressed snapshot envelope comfortably
/// exceeds one 8 MiB chunk (the v1 chunk size) and the transfer is a genuine
/// multi-chunk resumable upload rather than a single-chunk one that merely used
/// the resumable route.
const int _multiChunkBlobBytes = 24 * 1024 * 1024;

/// Raw size of the injected blob for the mid-upload cancellation test.
///
/// Deliberately larger than [_multiChunkBlobBytes]: the cancellation has to land
/// while the transfer is still in flight, so the test waits only for the *first*
/// accepted chunk (observed through the relay's own production metrics) and
/// needs several chunks left to cancel into. Kept below ~75 MiB raw so the
/// compressed snapshot stays under core's 100 MiB `MAX_SNAPSHOT_COMPRESSED_BYTES`
/// pre-upload gate.
const int _cancelBlobBytes = 64 * 1024 * 1024;

/// How long the lease-capable split ceremony is made to idle between the verify
/// and upload steps.
///
/// Deliberately longer than the 15s per-phase wrapper the pre-existing app e2e
/// fixture applies: if any Dart/FFI layer still imposed a short fixed deadline
/// on the split steps, this would time out. Core's own lease-aware budget is
/// four hours and the relay's pairing session TTL is 300s, so a lease-capable
/// ceremony must survive this comfortably.
const Duration _beyondLegacyWrapperWait = Duration(seconds: 16);

/// A spawned relay with the pairing lease and resumable snapshot upload switched
/// on, plus a fresh media root the test can inspect.
Future<TestRelay> _resumableRelay() async {
  final mediaDir = await Directory.systemTemp.createTemp(
    'prism_split_e2e_media_',
  );
  return spawnRelay(
    extraEnv: {
      'TEST_RELAY_RESUMABLE': '1',
      'TEST_RELAY_MEDIA_DIR': mediaDir.path,
    },
  );
}

/// Deterministic, incompressible-enough bytes.
///
/// A repeating or low-entropy pattern would let zstd collapse the snapshot back
/// under the 8 MiB chunk size, which is exactly what the multi-chunk test must
/// avoid.
Uint8List _pseudoRandomBytes(int length, int seed) {
  final out = Uint8List(length);
  var s = (seed * 2654435761) & 0xFFFFFFFF;
  if (s == 0) s = 0x9E3779B9;
  for (var i = 0; i < length; i++) {
    s ^= (s << 13) & 0xFFFFFFFF;
    s ^= s >>> 17;
    s ^= (s << 5) & 0xFFFFFFFF;
    out[i] = (s >>> 16) & 0xFF;
  }
  return out;
}

/// A base64 blob of [rawBytes] raw bytes, unique per [seed].
String _blobB64(int rawBytes, {required int seed}) =>
    base64Encode(_pseudoRandomBytes(rawBytes, seed));

/// Prometheus text body from the relay's production `/metrics` route.
///
/// Used only as read-only, externally observable evidence that a real upload
/// session existed and went terminal — the same signal an operator would use.
Future<Map<String, double>> _relayMetrics(String baseUrl) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('$baseUrl/metrics'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    expect(resp.statusCode, 200, reason: 'loopback /metrics must be readable');
    final parsed = <String, double>{};
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final sep = trimmed.lastIndexOf(' ');
      if (sep <= 0) continue;
      final value = double.tryParse(trimmed.substring(sep + 1).trim());
      if (value != null) parsed[trimmed.substring(0, sep).trim()] = value;
    }
    return parsed;
  } finally {
    client.close(force: true);
  }
}

/// Poll `/metrics` until [key] satisfies [predicate]. Returns whether it did.
Future<bool> _waitForMetric(
  String baseUrl,
  String key,
  bool Function(double value) predicate, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final value = (await _relayMetrics(baseUrl))[key];
    if (value != null && predicate(value)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return false;
}

const String _chunksAcceptedMetric =
    'prism_snapshot_upload_chunks_total{result="accepted"}';
const String _completionsMetric = 'prism_snapshot_upload_completions_total';
const String _abortedMetric = 'prism_snapshot_upload_aborted_total';

/// Everything the split ceremony produced for one pairing.
class SplitPairOutcome {
  SplitPairOutcome({
    required this.joiner,
    required this.leaseActive,
    required this.upload,
    required this.completion,
    required this.joinerCompletion,
  });

  final E2EDevice joiner;

  /// Result of step 1 (`verifyInitiatorConfirmationResumable`).
  final bool leaseActive;

  /// Result of step 2 (`uploadPairingSnapshotResumable`).
  final ffi.ResumableSnapshotUploadResult upload;

  /// Result of step 3 (`completeInitiatorResumableCeremony`).
  final ffi.ResumableCeremonyCompletion completion;

  /// The joiner's own completion payload, decoded.
  final Map<String, dynamic> joinerCompletion;
}

/// Pair a fresh joiner into [initiator]'s group through the SPLIT ceremony.
///
/// The joiner's own `completeJoinerCeremony` publishes the protected
/// confirmation that step 1 waits for, so it must be in flight first — the same
/// mutual-unblocking concurrency the legacy fixture needs, only with the
/// initiator side split into its three ordered calls.
///
/// [afterVerify] and [afterUpload] run between the steps, which is where the
/// ordering invariants are asserted.
Future<SplitPairOutcome> runSplitPairing(
  TestRelay relay,
  E2EDevice initiator, {
  Future<void> Function(ffi.PrismSyncHandle initiatorHandle)? afterVerify,
  Future<void> Function(
    ffi.ResumableSnapshotUploadResult upload,
    Future<String> joinerCompletion,
  )?
  afterUpload,
}) async {
  final b = await ffi.createPrismSync(
    relayUrl: relay.baseUrl,
    dbPath: ':memory:',
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );

  try {
    // Joiner: rendezvous token -> initiator consumes it.
    final joiner =
        jsonDecode(await ffi.startJoinerCeremony(handle: b))
            as Map<String, dynamic>;
    final tokenBytes = (joiner['token_bytes'] as List).cast<int>();
    final init =
        jsonDecode(
              await ffi.startInitiatorCeremony(
                handle: initiator.handle,
                tokenBytes: tokenBytes,
              ),
            )
            as Map<String, dynamic>;

    final bSas =
        jsonDecode(await ffi.getJoinerSas(handle: b)) as Map<String, dynamic>;
    expect(
      bSas['sas_word_list'],
      equals(init['sas_word_list']),
      reason: 'pairing SAS must match on both sides',
    );

    // The joiner's confirmation only exists once its completion is running, so
    // start it detached and never let it surface as an unhandled async error.
    final joinerComplete = ffi.completeJoinerCeremony(
      handle: b,
      password: initiator.password,
    );
    unawaited(joinerComplete.then((_) {}, onError: (Object _) {}));

    // ── Step 1: verify the joiner's confirmation ──
    final leaseActive = await ffi
        .verifyInitiatorConfirmationResumable(handle: initiator.handle)
        .timeout(const Duration(seconds: 60));
    if (afterVerify != null) await afterVerify(initiator.handle);

    // ── Step 2: produce + upload the snapshot ──
    final upload = await ffi
        .uploadPairingSnapshotResumable(
          handle: initiator.handle,
          ttlSecs: BigInt.from(86400),
        )
        .timeout(const Duration(minutes: 4));
    if (afterUpload != null) await afterUpload(upload, joinerComplete);

    // ── Step 3: release credentials and wait for the joiner's terminal bundle ──
    final completion = await ffi
        .completeInitiatorResumableCeremony(
          handle: initiator.handle,
          password: initiator.password,
          mnemonic: Uint8List.fromList(initiator.mnemonic),
        )
        .timeout(const Duration(minutes: 4));

    // Step 3 returns only after the joiner's terminal bundle landed, so the
    // joiner's own completion must resolve here.
    final joinerCompletion =
        jsonDecode(await joinerComplete.timeout(const Duration(seconds: 60)))
            as Map<String, dynamic>;
    expect(
      joinerCompletion['sync_id'],
      equals(initiator.syncId),
      reason: 'the joiner must land in the initiator\'s sync group',
    );

    // Bring the joiner up on the published snapshot, exactly as the app does.
    await ffi.configureEngine(handle: b).timeout(const Duration(seconds: 60));
    await ffi
        .bootstrapFromSnapshot(handle: b)
        .timeout(const Duration(minutes: 3));
    await ffi.acknowledgeSnapshotApplied(handle: b);

    return SplitPairOutcome(
      joiner: E2EDevice(
        handle: b,
        syncId: initiator.syncId,
        password: initiator.password,
        mnemonic: initiator.mnemonic,
      ),
      leaseActive: leaseActive,
      upload: upload,
      completion: completion,
      joinerCompletion: joinerCompletion,
    );
  } catch (_) {
    try {
      await ffi.cancelPairingCeremony(handle: b);
    } catch (_) {}
    b.dispose();
    rethrow;
  }
}

/// sha256 of a field value read back through the real FFI, so exactness is
/// asserted without holding two multi-megabyte strings for comparison.
Future<String> _sha256OfField(E2EDevice device, String entityId) async {
  final raw = await ffi.readFieldValue(
    handle: device.handle,
    table: 'members',
    entityId: entityId,
    field: 'avatar_image_data',
  );
  expect(
    raw,
    isNotNull,
    reason: 'the joiner must have received the snapshot field',
  );
  final decoded = jsonDecode(raw!) as String;
  return sha256.convert(utf8.encode(decoded)).toString();
}

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test(
    'split ceremony: new/new multi-chunk resumable upload publishes the exact '
    'snapshot bytes to the joiner',
    skip: e2eSkip(),
    () async {
      final relay = await _resumableRelay();
      E2EDevice? a;
      E2EDevice? b;
      try {
        a = await createDevice(relay);

        // A member carrying an incompressible blob, so the exported snapshot is
        // a genuine multi-chunk envelope. The value itself is the thing the
        // joiner must end up with byte-for-byte.
        final blob = _blobB64(_multiChunkBlobBytes, seed: 0x51D3);
        await ffi.recordCreate(
          handle: a.handle,
          table: 'members',
          entityId: 'm-multichunk',
          fieldsJson: jsonEncode({
            'name': 'Multi-chunk',
            'avatar_image_data': blob,
          }),
        );
        final expectedHash = sha256.convert(utf8.encode(blob)).toString();

        // The capability probe reads the relay's real authenticated
        // `/capabilities` response.
        final capability = await ffi.snapshotUploadCapability(handle: a.handle);
        expect(
          capability.state,
          equals(ffi.SnapshotUploadCapabilityState.available),
          reason: 'a file-backed, enabled relay must advertise snapshot_upload',
        );
        expect(capability.version, equals(1));
        expect(
          capability.chunkBytes.toInt(),
          equals(8 * 1024 * 1024),
          reason: 'v1 chunk size is 8 MiB',
        );

        final outcome = await runSplitPairing(
          relay,
          a,
          afterVerify: (handle) async {
            // Ordering: after a *real* verified ceremony is retained but before
            // any upload, credential release must be refused. This is the gate
            // itself, reached through the generated API rather than a fake.
            await expectLater(
              ffi.completeInitiatorResumableCeremony(
                handle: handle,
                password: a!.password,
                mnemonic: Uint8List.fromList(a.mnemonic),
              ),
              throwsA(
                predicate(
                  (Object e) => e.toString().contains(
                    'snapshot upload must succeed before',
                  ),
                  'the upload gate must refuse credential release',
                ),
              ),
            );
          },
          afterUpload: (upload, joinerCompletion) async {
            expect(
              upload.transport,
              equals(ffi.SnapshotTransportUsed.resumable),
              reason:
                  'an enabled relay with a targeted audience uses resumable v1',
            );
            expect(
              upload.uploadId,
              isNotEmpty,
              reason: 'a resumable upload has a session id',
            );
            expect(
              upload.committedBytes,
              equals(upload.totalBytes),
              reason: 'the transfer must commit every byte',
            );
            expect(upload.totalBytes, greaterThan(8 * 1024 * 1024));
            expect(
              upload.leaseActive,
              isTrue,
              reason: 'all three parties negotiated lease v1',
            );
            // `leaseRenewed` is intentionally not pinned: step 1 already performs
            // the initial renewal, so the upload's first progress renewal can be
            // coalesced away. Core owns that policy and this test must not
            // restate it.

            // Credentials are still held: the joiner is waiting for them.
            final releasedEarly = await Future.any<bool>([
              joinerCompletion.then((_) => true),
              Future<bool>.delayed(
                const Duration(milliseconds: 400),
                () => false,
              ),
            ]);
            expect(
              releasedEarly,
              isFalse,
              reason: 'credentials must not reach the joiner before step 3',
            );
          },
        );
        b = outcome.joiner;

        expect(outcome.leaseActive, isTrue);
        expect(outcome.completion.completed, isTrue);
        expect(outcome.completion.leaseActive, isTrue);
        expect(outcome.completion.leaseCapable, isTrue);

        // Exact snapshot bytes visible to the joiner.
        expect(
          await _sha256OfField(b, 'm-multichunk'),
          equals(expectedHash),
          reason: 'the joiner must see the exact snapshot bytes',
        );

        // Production observability: exactly one published snapshot, no abort.
        final metrics = await _relayMetrics(relay.baseUrl);
        expect(metrics[_completionsMetric], equals(1));
        expect(metrics[_abortedMetric] ?? 0, equals(0));
        expect(
          metrics[_chunksAcceptedMetric],
          greaterThanOrEqualTo(2),
          reason: 'the transfer must have been genuinely multi-chunk',
        );
      } finally {
        a?.dispose();
        b?.dispose();
        relay.stop();
      }
    },
  );

  test(
    'split ceremony: dark (old) relay downgrades the upload to a single PUT and '
    'still completes',
    skip: e2eSkip(),
    () async {
      // The default test relay: pairing lease and resumable upload dark, exactly
      // like an old or not-yet-enabled deployment.
      final relay = await spawnRelay();
      E2EDevice? a;
      E2EDevice? b;
      try {
        a = await createDevice(relay);

        final blob = _blobB64(64 * 1024, seed: 0x0DA4);
        await ffi.recordCreate(
          handle: a.handle,
          table: 'members',
          entityId: 'm-dark',
          fieldsJson: jsonEncode({
            'name': 'Dark relay',
            'avatar_image_data': blob,
          }),
        );
        final expectedHash = sha256.convert(utf8.encode(blob)).toString();

        final capability = await ffi.snapshotUploadCapability(handle: a.handle);
        expect(
          capability.state,
          isNot(equals(ffi.SnapshotUploadCapabilityState.available)),
          reason: 'a dark relay must not advertise the resumable capability',
        );

        final outcome = await runSplitPairing(
          relay,
          a,
          afterUpload: (upload, _) async {
            // Capability absence is a documented downgrade, never an error.
            expect(
              upload.transport,
              equals(ffi.SnapshotTransportUsed.singlePut),
              reason: 'a dark relay falls back to the unchanged single PUT',
            );
            expect(
              upload.uploadId,
              isEmpty,
              reason: 'no resumable session id exists',
            );
            expect(upload.committedBytes, equals(upload.totalBytes));
            expect(
              upload.leaseActive,
              isFalse,
              reason: 'no lease was negotiated',
            );
            expect(upload.leaseRenewed, isFalse);
          },
        );
        b = outcome.joiner;

        expect(
          outcome.leaseActive,
          isFalse,
          reason: 'step 1 must report no lease',
        );
        expect(outcome.completion.completed, isTrue);
        expect(outcome.completion.leaseActive, isFalse);
        expect(outcome.completion.leaseCapable, isFalse);

        expect(await _sha256OfField(b, 'm-dark'), equals(expectedHash));

        // The dark relay ran no resumable session at all.
        final metrics = await _relayMetrics(relay.baseUrl);
        expect(metrics[_completionsMetric] ?? 0, equals(0));
        expect(metrics[_abortedMetric] ?? 0, equals(0));
      } finally {
        a?.dispose();
        b?.dispose();
        relay.stop();
      }
    },
  );

  test(
    'split ceremony: cancelling mid-upload aborts the relay session and never '
    'releases credentials',
    skip: e2eSkip(),
    () async {
      final relay = await _resumableRelay();
      E2EDevice? a;
      ffi.PrismSyncHandle? bHandle;
      try {
        final initiator = await createDevice(relay);
        a = initiator;

        final blob = _blobB64(_cancelBlobBytes, seed: 0x0A0B);
        await ffi.recordCreate(
          handle: initiator.handle,
          table: 'members',
          entityId: 'm-cancel',
          fieldsJson: jsonEncode({
            'name': 'Cancel me',
            'avatar_image_data': blob,
          }),
        );

        final b = await ffi.createPrismSync(
          relayUrl: relay.baseUrl,
          dbPath: ':memory:',
          allowInsecure: true,
          schemaJson: prismSyncSchema,
        );
        bHandle = b;

        final joiner =
            jsonDecode(await ffi.startJoinerCeremony(handle: b))
                as Map<String, dynamic>;
        final init =
            jsonDecode(
                  await ffi.startInitiatorCeremony(
                    handle: initiator.handle,
                    tokenBytes: (joiner['token_bytes'] as List).cast<int>(),
                  ),
                )
                as Map<String, dynamic>;
        final bSas =
            jsonDecode(await ffi.getJoinerSas(handle: b))
                as Map<String, dynamic>;
        expect(bSas['sas_word_list'], equals(init['sas_word_list']));

        final joinerComplete = ffi.completeJoinerCeremony(
          handle: b,
          password: initiator.password,
        );
        unawaited(joinerComplete.then((_) {}, onError: (Object _) {}));

        final leaseActive = await ffi
            .verifyInitiatorConfirmationResumable(handle: initiator.handle)
            .timeout(const Duration(seconds: 60));
        expect(leaseActive, isTrue, reason: 'this relay negotiates lease v1');

        // Start the upload detached so it can be cancelled mid-flight.
        final upload = ffi.uploadPairingSnapshotResumable(
          handle: initiator.handle,
          ttlSecs: BigInt.from(86400),
        );
        Object? uploadError;
        var uploadSucceeded = false;
        unawaited(
          upload.then(
            (ffi.ResumableSnapshotUploadResult _) => uploadSucceeded = true,
            onError: (Object e) => uploadError = e,
          ),
        );

        // The relay's own metrics are the in-flight signal: a first accepted
        // chunk proves a real session exists and is still transferring.
        expect(
          await _waitForMetric(
            relay.baseUrl,
            _chunksAcceptedMetric,
            (value) => value >= 1,
            timeout: const Duration(seconds: 60),
          ),
          isTrue,
          reason:
              'the upload must reach the relay before we can cancel it mid-flight',
        );

        // Cancellation must be prompt and must abort exactly that session.
        await ffi
            .cancelPairingCeremony(handle: initiator.handle)
            .timeout(const Duration(seconds: 20));

        expect(
          await _waitForMetric(
            relay.baseUrl,
            _abortedMetric,
            (value) => value >= 1,
            timeout: const Duration(seconds: 30),
          ),
          isTrue,
          reason:
              'cancel must abort the live resumable session, not leak its reservation',
        );

        // No credentials may be released for a cancelled ceremony.
        await expectLater(
          ffi.completeInitiatorResumableCeremony(
            handle: initiator.handle,
            password: initiator.password,
            mnemonic: Uint8List.fromList(initiator.mnemonic),
          ),
          throwsA(anything),
          reason:
              'a cancelled ceremony has no released credentials to complete with',
        );

        // Give the detached upload a moment to observe the terminal session.
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(
          uploadSucceeded,
          isFalse,
          reason: 'an aborted resumable upload must not report success',
        );
        expect(
          uploadError,
          isNotNull,
          reason: 'the aborted upload must fail, not hang',
        );

        // Nothing was published, and the joiner never received credentials.
        final metrics = await _relayMetrics(relay.baseUrl);
        expect(metrics[_completionsMetric] ?? 0, equals(0));
        expect(
          await Future.any<bool>([
            joinerComplete.then(
              (_) => true,
              onError: (Object error) {
                expect(
                  error.toString(),
                  contains(
                    'credential bundle: protocol error: session not found',
                  ),
                );
                return false;
              },
            ),
            Future<bool>.delayed(
              const Duration(milliseconds: 300),
              () => false,
            ),
          ]),
          isFalse,
          reason:
              'the joiner must never receive credentials for a cancelled session',
        );
      } finally {
        a?.dispose();
        bHandle?.dispose();
        relay.stop();
      }
    },
  );

  test(
    'split ceremony: a lease-capable verified ceremony survives a wait longer '
    'than the legacy 15s per-phase wrapper',
    skip: e2eSkip(),
    () async {
      // This is the anti-preemption check: the split steps must be bounded only
      // by core's own lease-aware budget, never by a short Dart/FFI wrapper.
      // The pre-existing app e2e fixture wraps each phase in 15s; a verified
      // ceremony that is deliberately left idle for longer than that must still
      // be able to upload and complete.
      final relay = await _resumableRelay();
      E2EDevice? a;
      E2EDevice? b;
      try {
        a = await createDevice(relay);

        final blob = _blobB64(64 * 1024, seed: 0x57A1);
        await ffi.recordCreate(
          handle: a.handle,
          table: 'members',
          entityId: 'm-longwait',
          fieldsJson: jsonEncode({
            'name': 'Long wait',
            'avatar_image_data': blob,
          }),
        );
        final expectedHash = sha256.convert(utf8.encode(blob)).toString();

        final started = DateTime.now();
        final outcome = await runSplitPairing(
          relay,
          a,
          afterVerify: (_) async {
            // Idle well past any 15s wrapper, while leaving the ceremony usable.
            await Future<void>.delayed(_beyondLegacyWrapperWait);
          },
        );
        b = outcome.joiner;

        expect(
          DateTime.now().difference(started),
          greaterThan(_beyondLegacyWrapperWait),
          reason:
              'the wait must actually have elapsed between verify and upload',
        );
        expect(outcome.leaseActive, isTrue);
        expect(
          outcome.upload.transport,
          equals(ffi.SnapshotTransportUsed.resumable),
        );
        expect(outcome.upload.leaseActive, isTrue);
        expect(outcome.completion.completed, isTrue);

        expect(await _sha256OfField(b, 'm-longwait'), equals(expectedHash));
      } finally {
        a?.dispose();
        b?.dispose();
        relay.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
