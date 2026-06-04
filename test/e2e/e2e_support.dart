// Shared helpers for the end-to-end FFI harness: resolve the host-built Rust
// artifacts (built from the sibling prism-sync worktree) and spawn a throwaway
// localhost relay.
//
// Build prerequisites (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:async';
import 'dart:convert';
import 'dart:io';

String _libExt() => Platform.isMacOS
    ? 'dylib'
    : Platform.isWindows
    ? 'dll'
    : 'so';

List<String> _ffiLibCandidates() {
  final ext = _libExt();
  final name = Platform.isWindows ? 'prism_sync_ffi.$ext' : 'libprism_sync_ffi.$ext';
  final cwd = Directory.current.path; // prism-app worktree root
  return [
    '$cwd/../prism-sync/target/release/$name',
    '$cwd/../prism-sync/crates/prism-sync-ffi/target/release/$name',
  ];
}

String _relayBinPath() {
  final name = Platform.isWindows ? 'test_relay.exe' : 'test_relay';
  return '${Directory.current.path}/../prism-sync/target/release/examples/$name';
}

String? _firstExisting(List<String> paths) {
  for (final p in paths) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

/// The build command that produces the artifacts these tests need.
const String e2eBuildHint =
    '(cd ../prism-sync && cargo build --release -p prism_sync_ffi && '
    'cargo build --release -p prism-sync-relay --example test_relay)';

/// Skip reason if the host artifacts aren't built yet, else null. Pass to
/// `test(..., skip: e2eSkip())` so CI runs that haven't built the Rust side are
/// skipped (yellow), not failed (red). Run locally after [e2eBuildHint].
String? e2eSkip() {
  final missing = <String>[];
  if (_firstExisting(_ffiLibCandidates()) == null) missing.add('libprism_sync_ffi');
  if (!File(_relayBinPath()).existsSync()) missing.add('test_relay');
  if (missing.isEmpty) return null;
  return 'E2E Rust artifacts not built (${missing.join(', ')}). Build: $e2eBuildHint';
}

/// Absolute path to the host-built `libprism_sync_ffi` dynamic library.
String resolveFfiLib() =>
    _firstExisting(_ffiLibCandidates()) ?? (throw StateError('FFI lib not built: $e2eBuildHint'));

/// Absolute path to the host-built `test_relay` example binary.
String resolveRelayBinary() {
  final path = _relayBinPath();
  if (File(path).existsSync()) return path;
  throw StateError('test_relay not built: $e2eBuildHint');
}

/// A spawned localhost relay. Call [stop] in teardown.
class TestRelay {
  TestRelay(this._process, this.baseUrl);
  final Process _process;
  final String baseUrl;
  void stop() => _process.kill();
}

/// Spawn the test relay on an ephemeral localhost port and wait until it prints
/// its URL (and is serving — confirmed via /health).
Future<TestRelay> spawnRelay() async {
  final proc = await Process.start(resolveRelayBinary(), const []);
  final urlCompleter = Completer<String>();
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
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
