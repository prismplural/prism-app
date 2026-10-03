// Device-lane harness for the SPLIT resumable pairing surface.
//
// This is the on-device counterpart of `test/e2e/resumable_split_pairing_e2e_test.dart`.
// It drives the REAL generated FFI (`verifyInitiatorConfirmationResumable` ->
// `uploadPairingSnapshotResumable` -> `completeInitiatorResumableCeremony`)
// against the REAL Rust core, and against a relay the caller supplied.
//
// Differences from the host E2E lane, and why:
//
//  * The relay is NOT spawned here. `flutter drive` runs the test inside the
//    app process on a simulator/emulator, which has no access to the host
//    filesystem and cannot start a host binary. The runner
//    (`tool/run_resumable_simulator_matrix.sh`) starts the relay and publishes
//    its loopback URL to the device (iOS simulator shares host loopback;
//    Android reaches it through `adb reverse tcp:<port> tcp:<port>`).
//  * The native library is NOT opened with `ExternalLibrary.open`. On device the
//    `prism_sync` native-asset hook bundles the compiled Rust library into the
//    app, so plain `RustLib.init()` is the correct and only entry point.
//  * Fixture sizes and the scenario come from compile-time defines, because a
//    mobile app process does not inherit the shell environment:
//      PRISM_TEST_RELAY_URL           required; device-facing `http://localhost:<port>`
//      PRISM_RESUMABLE_SCENARIO       happy-resumable | dark-fallback | cancel-mid-upload
//      PRISM_RESUMABLE_SNAPSHOT_MIB   raw MiB of the injected incompressible blob
//      PRISM_TEST_RELAY_METRICS_TOKEN optional bearer token for `/metrics`
//
// The scenario is selected by `PRISM_RESUMABLE_SCENARIO` rather than by
// enumerating several tests, so one `flutter drive` invocation maps to exactly
// one scenario and the runner's pass/fail summary stays unambiguous.
//
// Metrics are read from the relay's own production `/metrics` route over plain
// HTTP (loopback), which is the same externally observable evidence an operator
// would use. Counters are compared as deltas against a baseline captured before
// the scenario, so a reused relay cannot make a stale counter look like success.
//
// Nothing here logs secrets or device identifiers: the relay URL is reduced to
// its origin, metrics tokens are never printed, and the snapshot is synthetic.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

/// Device-facing relay base URL (loopback on the device), supplied by the runner.
const String _relayUrl = String.fromEnvironment('PRISM_TEST_RELAY_URL');

/// Scenario to execute. See the file header for the supported values.
const String _scenario = String.fromEnvironment(
  'PRISM_RESUMABLE_SCENARIO',
  defaultValue: 'happy-resumable',
);

/// Raw MiB of the injected incompressible blob. `0` selects the per-scenario
/// default from [_defaultFixtureMiB].
const int _snapshotMiB = int.fromEnvironment(
  'PRISM_RESUMABLE_SNAPSHOT_MIB',
  defaultValue: 0,
);

/// Optional `METRICS_TOKEN` for the relay, when the runner configured one.
const String _metricsToken = String.fromEnvironment(
  'PRISM_TEST_RELAY_METRICS_TOKEN',
);

/// Take a device screenshot at scenario start/end when a driver is attached.
const bool _captureScreenshots = bool.fromEnvironment(
  'PRISM_RESUMABLE_SCREENSHOTS',
  defaultValue: false,
);

/// The v1 protocol chunk size. A multi-chunk transfer must exceed this.
const int _chunkBytes = 8 * 1024 * 1024;

/// A known-valid 12-word BIP39 phrase (all-zero entropy). The initiator needs
/// its mnemonic at pairing-complete time.
const String _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

const String _testPassword = 'e2e-pin-0000';

/// Production `/metrics` keys used as external evidence.
const String _chunksAcceptedMetric =
    'prism_snapshot_upload_chunks_total{result="accepted"}';
const String _completionsMetric = 'prism_snapshot_upload_completions_total';
const String _abortedMetric = 'prism_snapshot_upload_aborted_total';

/// Default fixture size per scenario.
///
/// The happy path only has to prove the transfer is genuinely multi-chunk, so it
/// stays just above one chunk. The cancellation path has to be cancelled *while
/// chunks are still flowing*, so it needs several chunks of runway. The dark
/// path exercises the single `PUT` fallback, where an oversized fixture is pure
/// cost.
///
/// The compressed snapshot must stay under core's 100 MiB pre-upload gate, and
/// the wire envelope adds signature + base64 overhead on top.
int _defaultFixtureMiB(String scenario) {
  switch (scenario) {
    case 'cancel-mid-upload':
      return 64;
    case 'dark-fallback':
      return 2;
    default:
      return 24;
  }
}

int get _fixtureMiB =>
    _snapshotMiB > 0 ? _snapshotMiB : _defaultFixtureMiB(_scenario);

String _platformName() {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return Platform.operatingSystem;
}

/// Emit one structured, secret-free harness event. The runner captures these
/// from the Flutter log to build its pass/fail summary.
///
/// Errors are reported by type only: a relay client error can echo a URL, and a
/// pairing error can echo group or device identifiers.
void _emit(String event, Map<String, Object?> fields) {
  // ignore: avoid_print
  print(
    'PRISM_RESUMABLE_HARNESS ${jsonEncode({'event': event, 'scenario': _scenario, 'rssBytes': ProcessInfo.currentRss, 'maxRssBytes': ProcessInfo.maxRss, ...fields})}',
  );
}

/// The relay origin without any path or credentials — safe to log.
String _relayOrigin() => Uri.parse(_relayUrl).origin;

/// Prometheus text body from the relay's production `/metrics` route.
Future<Map<String, double>> _relayMetrics() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$_relayUrl/metrics'));
    if (_metricsToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_metricsToken',
      );
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    expect(
      response.statusCode,
      200,
      reason: 'the loopback /metrics route must be readable by the harness',
    );
    final parsed = <String, double>{};
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separator = trimmed.lastIndexOf(' ');
      if (separator <= 0) continue;
      final value = double.tryParse(trimmed.substring(separator + 1).trim());
      if (value != null) {
        parsed[trimmed.substring(0, separator).trim()] = value;
      }
    }
    return parsed;
  } finally {
    client.close(force: true);
  }
}

/// Counter value, treating an absent series as zero.
double _counter(Map<String, double> metrics, String key) => metrics[key] ?? 0;

/// Growth of [key] since the [before] baseline.
double _delta(
  Map<String, double> after,
  Map<String, double> before,
  String key,
) => _counter(after, key) - _counter(before, key);

/// Poll `/metrics` until [key] has grown by at least [atLeast] since [before].
///
/// The interval is deliberately tight at first: this is used to detect the
/// *first accepted chunk* of a transfer that is still running, and a coarse poll
/// would let a fast loopback upload finish before the cancellation is issued.
/// It backs off after [tightWindow] so a stuck run does not hammer `/metrics`
/// for the whole timeout.
Future<bool> _waitForGrowth(
  Map<String, double> before,
  String key, {
  required double atLeast,
  required Duration timeout,
  Duration tightInterval = const Duration(milliseconds: 25),
  Duration relaxedInterval = const Duration(milliseconds: 250),
  Duration tightWindow = const Duration(seconds: 20),
}) async {
  final started = DateTime.now();
  final deadline = started.add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final after = await _relayMetrics();
    if (_delta(after, before, key) >= atLeast) return true;
    final interval = DateTime.now().difference(started) < tightWindow
        ? tightInterval
        : relaxedInterval;
    await Future<void>.delayed(interval);
  }
  return false;
}

/// Deterministic, incompressible-enough bytes.
///
/// A low-entropy or repeating pattern would let zstd collapse the snapshot back
/// under one chunk, which is exactly what the multi-chunk assertion must avoid.
Uint8List _pseudoRandomBytes(int length, int seed) {
  final out = Uint8List(length);
  var state = (seed * 2654435761) & 0xFFFFFFFF;
  if (state == 0) state = 0x9E3779B9;
  for (var i = 0; i < length; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >>> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    out[i] = (state >>> 16) & 0xFF;
  }
  return out;
}

/// Base64 of [rawBytes] raw bytes, unique per [seed].
String _blobB64(int rawBytes, {required int seed}) =>
    base64Encode(_pseudoRandomBytes(rawBytes, seed));

/// A configured device plus the on-disk scratch directory it owns.
class _Device {
  _Device({
    required this.handle,
    required this.syncId,
    required this.password,
    required this.mnemonic,
    required this.workDir,
  });

  final ffi.PrismSyncHandle handle;
  final String syncId;
  final List<int> password;
  final List<int> mnemonic;
  final Directory workDir;

  Future<void> dispose() async {
    try {
      handle.dispose();
    } catch (_) {}
    try {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}

/// Open a fresh sync handle backed by a real on-device SQLite file.
///
/// A file DB (not `:memory:`) is used because the split ceremony uploads a
/// snapshot that is staged on disk, and because a device lane that never touches
/// durable storage would not be exercising the shipping configuration.
Future<ffi.PrismSyncHandle> _openHandle(Directory workDir) =>
    ffi.createPrismSync(
      relayUrl: _relayUrl,
      dbPath: '${workDir.path}/prism_sync.db',
      allowInsecure: true,
      schemaJson: prismSyncSchema,
    );

/// Create a brand-new device that owns a fresh sync group on the relay.
Future<_Device> _createInitiator() async {
  final documents = await getApplicationDocumentsDirectory();
  final workDir = await Directory(
    '${documents.path}/resumable-harness-${DateTime.now().microsecondsSinceEpoch}',
  ).create(recursive: true);
  final handle = await _openHandle(workDir);
  final password = utf8.encode(_testPassword);
  final mnemonic = utf8.encode(_testMnemonic);
  try {
    final created =
        jsonDecode(
              await ffi.createSyncGroup(
                handle: handle,
                password: password,
                relayUrl: _relayUrl,
                mnemonic: Uint8List.fromList(mnemonic),
              ),
            )
            as Map<String, dynamic>;
    await ffi.configureEngine(handle: handle);
    return _Device(
      handle: handle,
      syncId: created['sync_id'] as String,
      password: password,
      mnemonic: mnemonic,
      workDir: workDir,
    );
  } catch (_) {
    handle.dispose();
    rethrow;
  }
}

/// Begin the split ceremony and return the in-flight joiner completion.
///
/// The joiner publishes the protected confirmation that step 1 (`verify...`)
/// waits for, so its completion must already be running before step 1 is called.
/// The `complete_*` pair unblocks each other through the relay's pairing slots.
Future<Future<String>> _beginSplitCeremony(
  _Device initiator,
  ffi.PrismSyncHandle joinerHandle,
) async {
  final joiner =
      jsonDecode(await ffi.startJoinerCeremony(handle: joinerHandle))
          as Map<String, dynamic>;
  final init =
      jsonDecode(
            await ffi.startInitiatorCeremony(
              handle: initiator.handle,
              tokenBytes: (joiner['token_bytes'] as List).cast<int>(),
            ),
          )
          as Map<String, dynamic>;

  final joinerSas =
      jsonDecode(await ffi.getJoinerSas(handle: joinerHandle))
          as Map<String, dynamic>;
  expect(
    joinerSas['sas_word_list'],
    equals(init['sas_word_list']),
    reason: 'the pairing SAS must match on both sides before anything is sent',
  );

  final joinerComplete = ffi.completeJoinerCeremony(
    handle: joinerHandle,
    password: initiator.password,
  );
  // Never let the detached future surface as an unhandled async error.
  unawaited(joinerComplete.then((_) {}, onError: (Object _) {}));
  return joinerComplete;
}

/// sha256 of a field value read back through the real FFI.
///
/// Hashing avoids holding two multi-megabyte strings for comparison while still
/// asserting byte-exactness.
Future<String> _sha256OfField(
  ffi.PrismSyncHandle handle,
  String entityId,
) async {
  final raw = await ffi.readFieldValue(
    handle: handle,
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

/// Bring the joiner up on the published snapshot, exactly as the app does.
Future<void> _bootstrapJoiner(ffi.PrismSyncHandle joinerHandle) async {
  await ffi
      .configureEngine(handle: joinerHandle)
      .timeout(const Duration(seconds: 90));
  await ffi
      .bootstrapFromSnapshot(handle: joinerHandle)
      .timeout(const Duration(minutes: 6));
  await ffi.acknowledgeSnapshotApplied(handle: joinerHandle);
}

/// True once the joiner's completion resolved within [window].
Future<bool> _completedWithin(Future<String> completion, Duration window) =>
    Future.any<bool>([
      completion.then((_) => true),
      Future<bool>.delayed(window, () => false),
    ]);

/// Best-effort screenshot hook. The runner also captures device screenshots
/// out-of-band, so a missing driver must never fail the scenario.
Future<void> _maybeScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String label,
) async {
  if (!_captureScreenshots) return;
  try {
    await binding.takeScreenshot('resumable-$_scenario-$label');
  } catch (_) {
    // No driver attached, or the platform surface is unavailable: ignore.
  }
}

/// happy-resumable: an enabled relay carries a genuinely multi-chunk resumable
/// transfer that publishes the exact snapshot bytes, with credentials held until
/// step 3.
Future<void> _runHappyResumable(Map<String, double> before) async {
  final initiator = await _createInitiator();
  ffi.PrismSyncHandle? joinerHandle;
  Directory? joinerDir;
  try {
    const entityId = 'm-resumable';
    final blob = _blobB64(_fixtureMiB * 1024 * 1024, seed: 0x51D3);
    final expectedHash = sha256.convert(utf8.encode(blob)).toString();
    await ffi.recordCreate(
      handle: initiator.handle,
      table: 'members',
      entityId: entityId,
      fieldsJson: jsonEncode({
        'name': 'Device harness',
        'avatar_image_data': blob,
      }),
    );

    // The capability probe reads the relay's real authenticated /capabilities.
    final capability = await ffi.snapshotUploadCapability(
      handle: initiator.handle,
    );
    expect(
      capability.state,
      equals(ffi.SnapshotUploadCapabilityState.available),
      reason:
          'a file-backed relay with SNAPSHOT_UPLOAD_ENABLED must advertise '
          'snapshot_upload',
    );
    expect(capability.version.toInt(), equals(1));
    expect(
      capability.chunkBytes.toInt(),
      equals(_chunkBytes),
      reason: 'v1 chunk size is 8 MiB',
    );
    expect(capability.maxWireBytes.toInt(), greaterThan(_chunkBytes));

    final documents = await getApplicationDocumentsDirectory();
    joinerDir = await Directory(
      '${documents.path}/resumable-joiner-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    joinerHandle = await _openHandle(joinerDir);

    final joinerComplete = await _beginSplitCeremony(initiator, joinerHandle);

    // ── Step 1: verify the joiner's confirmation ──
    final leaseActive = await ffi
        .verifyInitiatorConfirmationResumable(handle: initiator.handle)
        .timeout(const Duration(seconds: 90));
    expect(
      leaseActive,
      isTrue,
      reason: 'all three parties must negotiate lease v1 on an enabled relay',
    );

    // Ordering gate: a real verified ceremony is retained, but no upload has
    // happened, so credential release must be refused.
    await expectLater(
      ffi.completeInitiatorResumableCeremony(
        handle: initiator.handle,
        password: initiator.password,
        mnemonic: Uint8List.fromList(initiator.mnemonic),
      ),
      throwsA(
        predicate(
          (Object error) =>
              error.toString().contains('snapshot upload must succeed before'),
          'the upload gate must refuse credential release pre-complete',
        ),
      ),
    );

    // ── Step 2: produce + upload the snapshot ──
    final upload = await ffi
        .uploadPairingSnapshotResumable(
          handle: initiator.handle,
          ttlSecs: BigInt.from(86400),
        )
        .timeout(const Duration(minutes: 10));
    expect(
      upload.transport,
      equals(ffi.SnapshotTransportUsed.resumable),
      reason: 'an enabled relay with a targeted audience uses resumable v1',
    );
    expect(
      upload.uploadId,
      isNotEmpty,
      reason: 'a resumable upload has a session id',
    );
    expect(
      upload.committedBytes,
      equals(upload.totalBytes),
      reason: 'the transfer must commit every byte it staged',
    );
    expect(
      upload.totalBytes,
      greaterThan(_chunkBytes),
      reason: 'the fixture must exceed one chunk to be genuinely resumable',
    );
    expect(upload.leaseActive, isTrue);

    expect(
      await _completedWithin(joinerComplete, const Duration(milliseconds: 500)),
      isFalse,
      reason: 'credentials must not reach the joiner before step 3',
    );

    // ── Step 3: release credentials and await the joiner's terminal bundle ──
    final completion = await ffi
        .completeInitiatorResumableCeremony(
          handle: initiator.handle,
          password: initiator.password,
          mnemonic: Uint8List.fromList(initiator.mnemonic),
        )
        .timeout(const Duration(minutes: 10));
    expect(completion.completed, isTrue);
    expect(completion.leaseActive, isTrue);
    expect(completion.leaseCapable, isTrue);

    final joinerCompletion =
        jsonDecode(await joinerComplete.timeout(const Duration(seconds: 120)))
            as Map<String, dynamic>;
    expect(
      joinerCompletion['sync_id'],
      equals(initiator.syncId),
      reason: 'the joiner must land in the initiator\'s sync group',
    );

    await _bootstrapJoiner(joinerHandle);
    expect(
      await _sha256OfField(joinerHandle, entityId),
      equals(expectedHash),
      reason: 'the joiner must see the exact snapshot bytes',
    );

    final after = await _relayMetrics();
    final chunksAccepted = _delta(after, before, _chunksAcceptedMetric);
    expect(
      chunksAccepted,
      greaterThanOrEqualTo(2),
      reason: 'the happy path must have been genuinely multi-chunk',
    );
    expect(
      _delta(after, before, _completionsMetric),
      equals(1),
      reason: 'exactly one snapshot should have been published',
    );
    expect(_delta(after, before, _abortedMetric), equals(0));

    _emit('metrics', {
      'relayOrigin': _relayOrigin(),
      'platform': _platformName(),
      'fixtureMiB': _fixtureMiB,
      'chunksAccepted': chunksAccepted,
      'completions': _delta(after, before, _completionsMetric),
      'aborted': _delta(after, before, _abortedMetric),
      'transport': upload.transport.name,
      'snapshotHashMatched': true,
    });
  } finally {
    if (joinerHandle != null) {
      try {
        await ffi.cancelPairingCeremony(handle: joinerHandle);
      } catch (_) {}
      joinerHandle.dispose();
      if (joinerDir != null && joinerDir.existsSync()) {
        try {
          await joinerDir.delete(recursive: true);
        } catch (_) {}
      }
    }
    await initiator.dispose();
  }
}

/// dark-fallback: a relay that does not advertise the resumable capability must
/// downgrade to the unchanged single `PUT` and still complete.
Future<void> _runDarkFallback(Map<String, double> before) async {
  final initiator = await _createInitiator();
  ffi.PrismSyncHandle? joinerHandle;
  Directory? joinerDir;
  try {
    const entityId = 'm-dark';
    final blob = _blobB64(_fixtureMiB * 1024 * 1024, seed: 0x0DA4);
    final expectedHash = sha256.convert(utf8.encode(blob)).toString();
    await ffi.recordCreate(
      handle: initiator.handle,
      table: 'members',
      entityId: entityId,
      fieldsJson: jsonEncode({'name': 'Dark relay', 'avatar_image_data': blob}),
    );

    final capability = await ffi.snapshotUploadCapability(
      handle: initiator.handle,
    );
    expect(
      capability.state,
      isNot(equals(ffi.SnapshotUploadCapabilityState.available)),
      reason: 'a dark relay must not advertise the resumable capability',
    );

    final documents = await getApplicationDocumentsDirectory();
    joinerDir = await Directory(
      '${documents.path}/resumable-dark-joiner-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    joinerHandle = await _openHandle(joinerDir);

    final joinerComplete = await _beginSplitCeremony(initiator, joinerHandle);

    final leaseActive = await ffi
        .verifyInitiatorConfirmationResumable(handle: initiator.handle)
        .timeout(const Duration(seconds: 90));
    expect(
      leaseActive,
      isFalse,
      reason: 'a dark relay negotiates no pairing lease',
    );

    final upload = await ffi
        .uploadPairingSnapshotResumable(
          handle: initiator.handle,
          ttlSecs: BigInt.from(86400),
        )
        .timeout(const Duration(minutes: 10));
    expect(
      upload.transport,
      equals(ffi.SnapshotTransportUsed.singlePut),
      reason: 'capability absence is a documented downgrade, never an error',
    );
    expect(
      upload.uploadId,
      isEmpty,
      reason: 'no resumable session id exists on the fallback path',
    );
    expect(upload.committedBytes, equals(upload.totalBytes));
    expect(upload.leaseActive, isFalse);
    expect(upload.leaseRenewed, isFalse);

    final completion = await ffi
        .completeInitiatorResumableCeremony(
          handle: initiator.handle,
          password: initiator.password,
          mnemonic: Uint8List.fromList(initiator.mnemonic),
        )
        .timeout(const Duration(minutes: 10));
    expect(completion.completed, isTrue);
    expect(completion.leaseActive, isFalse);
    expect(completion.leaseCapable, isFalse);

    final joinerCompletion =
        jsonDecode(await joinerComplete.timeout(const Duration(seconds: 120)))
            as Map<String, dynamic>;
    expect(joinerCompletion['sync_id'], equals(initiator.syncId));

    await _bootstrapJoiner(joinerHandle);
    expect(await _sha256OfField(joinerHandle, entityId), equals(expectedHash));

    // The dark relay ran no resumable session at all.
    final after = await _relayMetrics();
    expect(
      _delta(after, before, _completionsMetric),
      equals(0),
      reason: 'no resumable session was completed on the dark relay',
    );
    expect(_delta(after, before, _abortedMetric), equals(0));

    _emit('metrics', {
      'relayOrigin': _relayOrigin(),
      'platform': _platformName(),
      'fixtureMiB': _fixtureMiB,
      'transport': upload.transport.name,
      'leaseActive': false,
      'completions': _delta(after, before, _completionsMetric),
      'aborted': _delta(after, before, _abortedMetric),
      'snapshotHashMatched': true,
    });
  } finally {
    if (joinerHandle != null) {
      try {
        await ffi.cancelPairingCeremony(handle: joinerHandle);
      } catch (_) {}
      joinerHandle.dispose();
      if (joinerDir != null && joinerDir.existsSync()) {
        try {
          await joinerDir.delete(recursive: true);
        } catch (_) {}
      }
    }
    await initiator.dispose();
  }
}

/// cancel-mid-upload: cancel while chunks are still being accepted must abort the
/// live relay session, publish nothing, and never release credentials.
///
/// Cancellation is only attempted once the relay's own metrics show at least one
/// accepted chunk, so the abort lands on a session that provably exists and is
/// still in flight rather than racing the session creation.
Future<void> _runCancelMidUpload(Map<String, double> before) async {
  final initiator = await _createInitiator();
  ffi.PrismSyncHandle? joinerHandle;
  Directory? joinerDir;
  try {
    const entityId = 'm-cancel';
    // Larger than the happy fixture: the cancellation needs several chunks of
    // runway so the abort lands while the transfer is still moving.
    final blob = _blobB64(_fixtureMiB * 1024 * 1024, seed: 0x0A0B);
    final expectedHash = sha256.convert(utf8.encode(blob)).toString();
    await ffi.recordCreate(
      handle: initiator.handle,
      table: 'members',
      entityId: entityId,
      fieldsJson: jsonEncode({'name': 'Cancel me', 'avatar_image_data': blob}),
    );

    final documents = await getApplicationDocumentsDirectory();
    joinerDir = await Directory(
      '${documents.path}/resumable-cancel-joiner-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    joinerHandle = await _openHandle(joinerDir);

    final joinerComplete = await _beginSplitCeremony(initiator, joinerHandle);

    final leaseActive = await ffi
        .verifyInitiatorConfirmationResumable(handle: initiator.handle)
        .timeout(const Duration(seconds: 90));
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
        onError: (Object error) => uploadError = error,
      ),
    );

    // Wait for relay evidence: a first accepted chunk proves a real session
    // exists and is still transferring.
    expect(
      await _waitForGrowth(
        before,
        _chunksAcceptedMetric,
        atLeast: 1,
        timeout: const Duration(minutes: 3),
      ),
      isTrue,
      reason:
          'the upload must reach the relay before we can cancel it mid-flight',
    );

    await ffi
        .cancelPairingCeremony(handle: initiator.handle)
        .timeout(const Duration(seconds: 30));

    expect(
      await _waitForGrowth(
        before,
        _abortedMetric,
        atLeast: 1,
        timeout: const Duration(seconds: 60),
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
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(
      uploadSucceeded,
      isFalse,
      reason: 'an aborted resumable upload must not report success',
    );
    expect(
      uploadError,
      isNotNull,
      reason: 'the aborted upload must fail promptly, not hang',
    );

    final after = await _relayMetrics();
    final aborted = _delta(after, before, _abortedMetric);
    final completions = _delta(after, before, _completionsMetric);
    expect(
      completions,
      equals(0),
      reason: 'a cancelled upload must publish no snapshot',
    );
    expect(
      await _completedWithin(joinerComplete, const Duration(milliseconds: 500)),
      isFalse,
      reason: 'the joiner must still be waiting for credentials it never gets',
    );

    _emit('metrics', {
      'relayOrigin': _relayOrigin(),
      'platform': _platformName(),
      'fixtureMiB': _fixtureMiB,
      'aborted': aborted,
      'completions': completions,
      'uploadFailed': uploadError != null,
      'snapshotHashMatched': false,
      'expectedSnapshotHashPresent': expectedHash.isNotEmpty,
    });
  } finally {
    try {
      await ffi.cancelPairingCeremony(handle: initiator.handle);
    } catch (_) {}
    if (joinerHandle != null) {
      try {
        await ffi.cancelPairingCeremony(handle: joinerHandle);
      } catch (_) {}
      joinerHandle.dispose();
      if (joinerDir != null && joinerDir.existsSync()) {
        try {
          await joinerDir.delete(recursive: true);
        } catch (_) {}
      }
    }
    await initiator.dispose();
  }
}

/// Fail fast with an actionable message when the runner misconfigured the lane.
void _validateConfig() {
  if (_relayUrl.isEmpty) {
    throw StateError(
      'PRISM_TEST_RELAY_URL is required (device-facing loopback URL, e.g. '
      'http://localhost:8080). Run tool/run_resumable_simulator_matrix.sh.',
    );
  }
  final uri = Uri.tryParse(_relayUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw StateError('PRISM_TEST_RELAY_URL is not a valid absolute URL.');
  }
  if (!uri.isScheme('http') && !uri.isScheme('https')) {
    throw StateError('PRISM_TEST_RELAY_URL must be http or https.');
  }
  const supported = {'happy-resumable', 'dark-fallback', 'cancel-mid-upload'};
  if (!supported.contains(_scenario)) {
    throw StateError(
      'Unsupported PRISM_RESUMABLE_SCENARIO "$_scenario"; '
      'expected one of ${supported.join(', ')}.',
    );
  }
  if (_fixtureMiB <= 0) {
    throw StateError('PRISM_RESUMABLE_SNAPSHOT_MIB must be positive.');
  }
  final platform = _platformName();
  if (platform != 'ios' && platform != 'android') {
    throw UnsupportedError(
      'The device lane must run on an iOS simulator or an Android emulator; '
      'found "$platform".',
    );
  }
}

/// Confirm the relay is reachable from the device before doing any real work.
///
/// This is the check that catches a missing `adb reverse` or a relay bound to a
/// different port, which otherwise surfaces much later as an opaque pairing
/// timeout.
Future<void> _assertRelayHealthy() async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse('$_relayUrl/health'))
        .timeout(const Duration(seconds: 15));
    final response = await request.close();
    await response.drain<void>();
    expect(
      response.statusCode,
      200,
      reason: 'the relay must be reachable from the device before the scenario',
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _validateConfig();
    await RustLib.init();
    await _assertRelayHealthy();
  });

  tearDownAll(RustLib.dispose);

  testWidgets(
    'resumable split pairing device scenario: $_scenario',
    (tester) async {
      final before = await _relayMetrics();
      _emit('scenario_start', {
        'platform': _platformName(),
        'relayOrigin': _relayOrigin(),
        'fixtureMiB': _fixtureMiB,
        'metricsTokenConfigured': _metricsToken.isNotEmpty,
      });
      await _maybeScreenshot(binding, 'start');
      try {
        switch (_scenario) {
          case 'happy-resumable':
            await _runHappyResumable(before);
          case 'dark-fallback':
            await _runDarkFallback(before);
          case 'cancel-mid-upload':
            await _runCancelMidUpload(before);
          default:
            fail('Unsupported PRISM_RESUMABLE_SCENARIO: $_scenario');
        }
        _emit('scenario_end', {'ok': true, 'platform': _platformName()});
      } catch (error) {
        // Type only: an error string can echo a URL or an identifier.
        _emit('scenario_end', {
          'ok': false,
          'platform': _platformName(),
          'errorType': error.runtimeType.toString(),
        });
        rethrow;
      } finally {
        await _maybeScreenshot(binding, 'end');
      }
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
