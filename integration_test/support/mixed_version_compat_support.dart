import 'dart:async';
import 'dart:convert';
import 'dart:io';

const compatRole = String.fromEnvironment('PRISM_COMPAT_ROLE');
const compatRunId = String.fromEnvironment('PRISM_COMPAT_RUN_ID');
const compatControllerUrl = String.fromEnvironment(
  'PRISM_COMPAT_CONTROLLER',
  defaultValue: 'http://localhost:50220',
);
const compatRelayUrl = String.fromEnvironment(
  'PRISM_COMPAT_RELAY',
  defaultValue: 'http://localhost:50225',
);
const compatCompleteRepair = bool.fromEnvironment(
  'PRISM_COMPAT_COMPLETE_REPAIR',
  defaultValue: false,
);

class CompatController {
  CompatController({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Uri _uri(String key) => Uri.parse(
    '$compatControllerUrl/kv/${Uri.encodeComponent(compatRunId)}/$key',
  );

  Future<void> put(String key, Map<String, dynamic> value) async {
    final request = await _client.putUrl(_uri(key));
    request.headers.contentType = ContentType.json;
    final bodyBytes = utf8.encode(jsonEncode(value));
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'controller PUT $key returned ${response.statusCode}: $body',
      );
    }
  }

  Future<Map<String, dynamic>?> get(String key) async {
    final request = await _client.getUrl(_uri(key));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'controller GET $key returned ${response.statusCode}: $body',
      );
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> waitFor(
    String key, {
    Duration timeout = const Duration(minutes: 3),
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

  Future<void> evidence(String phase, Map<String, dynamic> assertions) {
    _rejectSecrets(assertions);
    return put('evidence/$compatRole/$phase', <String, dynamic>{
      'role': compatRole,
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
