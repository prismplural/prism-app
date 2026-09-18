// Cross-device rendezvous + fault-control client for the sync-resilience
// qualification harness.
//
// Both roles talk to a single host-side controller
// (`scripts/sync_resilience_qualification_controller.py`) that serves a small
// JSON KV store for barriers AND owns the raw-TCP fault proxy. On Android the
// controller and proxy are reachable through `adb reverse` at `localhost`,
// which is why every URL defaults to `localhost`.
//
// Barrier values (including pairing material) are in-memory only on the
// controller; [ResilienceController.evidence] rejects secret-shaped keys so a
// device can never publish them into the evidence record.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The qualification roles are fixed by native platform. Deriving this at
/// runtime keeps the macOS and Android builds byte-for-byte aligned with respect
/// to Dart defines, so concurrent Flutter invocations cannot overwrite a shared
/// build artifact with the peer's role compiled into it.
String get resilienceRole {
  if (Platform.isMacOS) return resilienceRoleMac;
  if (Platform.isAndroid) return resilienceRoleAndroid;
  return 'unsupported_${Platform.operatingSystem}';
}

const resilienceRunId = String.fromEnvironment('PRISM_RESILIENCE_RUN_ID');
const resilienceControllerUrl = String.fromEnvironment(
  'PRISM_RESILIENCE_CONTROLLER',
  defaultValue: 'http://localhost:50230',
);
const resilienceRelayUrl = String.fromEnvironment(
  'PRISM_RESILIENCE_RELAY',
  defaultValue: 'http://localhost:50225',
);

/// The raw-TCP fault proxy's own URL. The receiver points its engine at this
/// instead of the relay directly, so a blackhole can be armed on the one
/// upgraded socket the receiver is using.
///
/// `localhost` is required: the native relay client rejects a bare `127.0.0.1`
/// origin, and on Android `adb reverse tcp:50226 tcp:50226` maps it to the host.
const resilienceProxyUrl = String.fromEnvironment(
  'PRISM_RESILIENCE_PROXY',
  defaultValue: 'http://localhost:50226',
);

const resilienceRoleMac = 'mac_sender';
const resilienceRoleAndroid = 'android_receiver';

/// Minimal JSON KV + fault-control client. Every request is bounded by a
/// timeout so a stalled controller fails the run loudly instead of hanging.
class ResilienceController {
  ResilienceController({
    HttpClient? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = requestTimeout;
  }

  final HttpClient _client;
  final Duration requestTimeout;

  Uri _kv(String key) => Uri.parse(
    '$resilienceControllerUrl/kv/${Uri.encodeComponent(resilienceRunId)}/$key',
  );

  Uri _control(String path) => Uri.parse('$resilienceControllerUrl$path');

  Future<void> put(String key, Map<String, dynamic> value) async {
    final request = await _client.putUrl(_kv(key)).timeout(requestTimeout);
    request.headers.contentType = ContentType.json;
    final bodyBytes = utf8.encode(jsonEncode(value));
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
    final response = await request.close().timeout(requestTimeout);
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'controller PUT $key returned ${response.statusCode}: $body',
      );
    }
  }

  Future<Map<String, dynamic>?> get(String key) async {
    final request = await _client.getUrl(_kv(key)).timeout(requestTimeout);
    final response = await request.close().timeout(requestTimeout);
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(requestTimeout);
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'controller GET $key returned ${response.statusCode}: $body',
      );
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  /// Poll until [key] exists. This is the barrier primitive: no device advances
  /// past a stage until the peer has published the matching ready key.
  Future<Map<String, dynamic>> waitFor(
    String key, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await get(key);
      if (value != null) return value;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException(
      'timed out waiting for controller key $key',
      timeout,
    );
  }

  Future<Map<String, dynamic>> _post(String path) async {
    final request = await _client
        .postUrl(_control(path))
        .timeout(requestTimeout);
    request.headers.contentType = ContentType.json;
    request.contentLength = 0;
    final response = await request.close().timeout(requestTimeout);
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'controller POST $path returned ${response.statusCode}: $body',
      );
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final request = await _client
        .getUrl(_control(path))
        .timeout(requestTimeout);
    final response = await request.close().timeout(requestTimeout);
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'controller GET $path returned ${response.statusCode}: $body',
      );
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  /// Blackhole relay->receiver bytes on the sockets upgraded as of now, leaving
  /// them open. Returns `{armed, targets, upgraded_total}`; `targets` is the
  /// number of live upgraded sockets that were selected, so a caller can assert
  /// the fault landed on a real socket.
  Future<Map<String, dynamic>> armFault() => _post('/fault/arm');

  Future<Map<String, dynamic>> clearFault() => _post('/fault/clear');

  Future<Map<String, dynamic>> faultStatus() => _getJson('/fault/status');

  Future<void> evidence(String phase, Map<String, dynamic> assertions) {
    _rejectSecrets(assertions);
    return put('evidence/$resilienceRole/$phase', <String, dynamic>{
      'role': resilienceRole,
      'phase': phase,
      'assertions': assertions,
    });
  }

  void close() => _client.close(force: true);
}

void _rejectSecrets(Object? value, [String path = 'evidence']) {
  const forbidden = <String>{
    'token',
    'password',
    'mnemonic',
    'session',
    'secret',
    'dek',
  };
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (forbidden.any(key.contains)) {
        throw ArgumentError('secret-shaped evidence key rejected: $path.$key');
      }
      _rejectSecrets(entry.value, '$path.$key');
    }
  } else if (value is Iterable) {
    var index = 0;
    for (final item in value) {
      _rejectSecrets(item, '$path[$index]');
      index++;
    }
  }
}

int syncCount(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int intValue(Map<String, dynamic>? source, String key) {
  final value = source?[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

/// Poll [predicate] until it is true or [budget] elapses, yielding to the event
/// loop between checks. Returns the elapsed time on success, `null` on timeout.
///
/// This is the autonomous-recovery probe used by the receiver: it only observes
/// state, it never triggers a sync, rebind, or restart.
Future<Duration?> pollUntil(
  Future<bool> Function() predicate,
  Duration budget, {
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < budget) {
    if (await predicate()) return clock.elapsed;
    await Future<void>.delayed(interval);
  }
  return await predicate() ? clock.elapsed : null;
}
