// Native E2E requires explicit artifacts with verified provenance.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

String get _nativeLaneHint =>
    'PRISM_SYNC_DIR=/path/to/prism-sync scripts/test_native.sh';

String _requiredEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name is required. Run: $_nativeLaneHint');
  }
  return value;
}

String _canonicalExistingFile(String path, String name) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('$name is missing: $path. Run: $_nativeLaneHint');
  }
  return file.resolveSymbolicLinksSync();
}

String _fileSha256(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void _checkNativeProvenance() {
  final manifestPath = _requiredEnv('PRISM_NATIVE_PROVENANCE');
  final manifest = File(manifestPath);
  if (!manifest.existsSync()) {
    throw StateError('Native provenance record is missing: $manifestPath');
  }
  final data = jsonDecode(manifest.readAsStringSync()) as Map;
  final expectedRevision = _requiredEnv('PRISM_EXPECTED_SYNC_REV');
  if (data['sync_revision'] != expectedRevision) {
    throw StateError(
      'Native artifact revision ${data['sync_revision']} does not match '
      'the resolved Prism Sync revision $expectedRevision.',
    );
  }
  final ffiLibrary = _canonicalExistingFile(
    _requiredEnv('PRISM_SYNC_FFI_LIB'),
    'FFI library',
  );
  final relayBinary = _canonicalExistingFile(
    _requiredEnv('PRISM_SYNC_RELAY_BIN'),
    'relay binary',
  );
  if (data['ffi_library'] != ffiLibrary ||
      data['relay_binary'] != relayBinary) {
    throw StateError('Native artifact paths do not match $manifestPath.');
  }
  if (data['ffi_sha256'] != _fileSha256(ffiLibrary) ||
      data['relay_sha256'] != _fileSha256(relayBinary)) {
    throw StateError('Native artifact hashes do not match $manifestPath.');
  }
}

/// Optional discovery skips; enabled lanes reject missing or mismatched artifacts.
String? e2eSkip() {
  if (Platform.environment['PRISM_ENABLE_NATIVE_E2E'] != '1') {
    return 'Native E2E is disabled. Run: $_nativeLaneHint';
  }
  _checkNativeProvenance();
  return null;
}

/// Absolute path to the provenance-checked `libprism_sync_ffi` dynamic library.
String resolveFfiLib() {
  _checkNativeProvenance();
  return _canonicalExistingFile(
    _requiredEnv('PRISM_SYNC_FFI_LIB'),
    'FFI library',
  );
}

/// Absolute path to the host-built `test_relay` example binary.
String resolveRelayBinary() {
  _checkNativeProvenance();
  return _canonicalExistingFile(
    _requiredEnv('PRISM_SYNC_RELAY_BIN'),
    'relay binary',
  );
}

/// A spawned localhost relay. Call [stop] in teardown.
class TestRelay {
  TestRelay(this._process, this.baseUrl);
  final Process _process;
  final String baseUrl;
  void stop() => _process.kill();
}

/// Bind an ephemeral localhost port, release it, and return the number — for
/// pre-allocating a fixed port a restartable relay can re-bind.
Future<int> findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Spawn the test relay and wait until it's serving (confirmed via /health).
///
/// With [port] and [dbPath] the relay binds a FIXED port and a persistent file
/// DB, so it can be killed and restarted on the same URL with the same state
/// (used by the outage/recovery chaos test). Defaults: ephemeral port + in-memory.
Future<TestRelay> spawnRelay({int? port, String? dbPath}) async {
  final env = <String, String>{};
  if (port != null) env['TEST_RELAY_PORT'] = '$port';
  if (dbPath != null) env['TEST_RELAY_DB'] = dbPath;
  final proc = await Process.start(
    resolveRelayBinary(),
    const [],
    environment: env.isEmpty ? null : env,
  );
  final urlCompleter = Completer<String>();
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
    line,
  ) {
    if (line.startsWith('RELAY_URL=') && !urlCompleter.isCompleted) {
      urlCompleter.complete(line.substring('RELAY_URL='.length).trim());
    }
  });
  proc.stderr.transform(utf8.decoder).listen((_) {}); // drain so it can't block

  final rawUrl = await urlCompleter.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () {
      proc.kill();
      throw StateError('test_relay did not print RELAY_URL within 20s');
    },
  );
  // ServerRelay (the FFI's HTTP client) only accepts `http://localhost` or
  // `https://` — not a bare `127.0.0.1`. Same loopback, accepted form.
  final url = rawUrl.replaceFirst('127.0.0.1', 'localhost');

  // Confirm it's actually serving before handing it back.
  final client = HttpClient();
  try {
    for (var attempt = 0; attempt < 50; attempt++) {
      try {
        final req = await client.getUrl(Uri.parse('$url/health'));
        final resp = await req.close();
        await resp.drain<void>();
        if (resp.statusCode == 200) break;
      } catch (_) {
        // not up yet
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  } finally {
    client.close(force: true);
  }

  return TestRelay(proc, url);
}
