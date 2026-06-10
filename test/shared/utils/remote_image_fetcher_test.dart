import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';

void main() {
  group('fetchRemoteImageBytes', () {
    test('returns bytes for image responses', () async {
      final body = Uint8List.fromList([1, 2, 3]);
      final client = MockClient((request) async {
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/banner.png',
        client: client,
      );

      expect(bytes, body);
    });

    test('returns null for non-image MIME types', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/banner.json',
        client: client,
      );

      expect(bytes, isNull);
    });

    test('returns null for non-200 responses', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response.bytes(Uint8List.fromList([1]), 302);
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/redirect',
        client: client,
      );

      expect(bytes, isNull);
      expect(calls, 1);
    });

    test('returns null for empty bodies', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          Uint8List(0),
          200,
          headers: {'content-type': 'image/webp'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/empty.webp',
        client: client,
      );

      expect(bytes, isNull);
    });

    test('returns null when content-length exceeds maxBytes', () async {
      final client = _StreamingClient(
        statusCode: 200,
        headers: {'content-type': 'image/jpeg', 'content-length': '2048'},
        chunks: [
          Uint8List.fromList([1]),
        ],
      );

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/large.jpg',
        client: client,
        maxBytes: 1024,
      );

      expect(bytes, isNull);
    });

    test('returns null when streamed bytes exceed maxBytes', () async {
      final client = _StreamingClient(
        statusCode: 200,
        headers: {'content-type': 'image/jpeg'},
        chunks: [Uint8List(700), Uint8List(700)],
      );

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/large.jpg',
        client: client,
        maxBytes: 1024,
      );

      expect(bytes, isNull);
    });

    test('returns null on timeout', () async {
      final client = _StreamingClient(
        statusCode: 200,
        headers: {'content-type': 'image/png'},
        chunks: [
          Uint8List.fromList([1]),
        ],
        firstChunkDelay: const Duration(milliseconds: 200),
      );

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/slow.png',
        client: client,
        timeout: const Duration(milliseconds: 20),
        maxAttempts: 1,
      );

      expect(bytes, isNull);
    });

    test('retries transient HTTP responses', () async {
      final body = Uint8List.fromList([4, 5, 6]);
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response('temporarily unavailable', 503);
        }
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/flaky.png',
        client: client,
        initialRetryDelay: Duration.zero,
      );

      expect(bytes, body);
      expect(calls, 2);
    });

    test('retries thrown client errors', () async {
      final body = Uint8List.fromList([7, 8, 9]);
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException('connection reset', request.url);
        }
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/reset.png',
        client: client,
        initialRetryDelay: Duration.zero,
      );

      expect(bytes, body);
      expect(calls, 2);
    });

    test('honors maxAttempts for transient failures', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('still down', 500);
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/down.png',
        client: client,
        maxAttempts: 2,
        initialRetryDelay: Duration.zero,
      );

      expect(bytes, isNull);
      expect(calls, 2);
    });

    test('does not retry permanent image validation failures', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3]),
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/page.html',
        client: client,
        initialRetryDelay: Duration.zero,
      );

      expect(bytes, isNull);
      expect(calls, 1);
    });

    test('returns null for invalid or unsupported URLs', () async {
      final client = MockClient((request) async => http.Response('', 200));

      expect(await fetchRemoteImageBytes('', client: client), isNull);
      expect(
        await fetchRemoteImageBytes(
          'ftp://example.com/image.png',
          client: client,
        ),
        isNull,
      );
    });

    test('pinned HTTPS connections are upgraded to TLS', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final firstBytes = Completer<List<int>>();
      final serverSub = server.listen((socket) {
        final bytes = <int>[];
        late StreamSubscription<List<int>> socketSub;
        socketSub = socket.listen(
          (chunk) {
            bytes.addAll(chunk);
            if (bytes.length >= 3 && !firstBytes.isCompleted) {
              firstBytes.complete(bytes.take(3).toList());
              socket.destroy();
              unawaited(socketSub.cancel());
            }
          },
          onDone: () {
            if (!firstBytes.isCompleted) firstBytes.complete(bytes);
          },
        );
      });
      addTearDown(serverSub.cancel);

      final rawTask = ConnectionTask.fromSocket(
        Socket.connect(server.address, server.port),
        () {},
      );
      final upgradedTask = upgradePinnedConnectionForTesting(
        rawTask,
        Uri.parse('https://example.com/image.png'),
      );
      final clientFuture = upgradedTask.socket
          .then((socket) => socket.destroy())
          .catchError((_) {});

      final bytes = await firstBytes.future.timeout(const Duration(seconds: 5));
      await clientFuture;

      expect(bytes, hasLength(greaterThanOrEqualTo(3)));
      expect(bytes[0], 0x16, reason: 'TLS handshake record type');
      expect(bytes[1], 0x03, reason: 'TLS major version');
    });
  });

  group('isPrivateHostLiteral', () {
    test('rejects canonical private/loopback literals', () {
      expect(isPrivateHostLiteral('127.0.0.1'), isTrue);
      expect(isPrivateHostLiteral('10.0.0.5'), isTrue);
      expect(isPrivateHostLiteral('192.168.1.1'), isTrue);
      expect(isPrivateHostLiteral('172.16.0.1'), isTrue);
      expect(isPrivateHostLiteral('169.254.169.254'), isTrue);
      expect(isPrivateHostLiteral('100.64.0.1'), isTrue); // CGNAT
    });

    test('rejects well-known private hostnames', () {
      expect(isPrivateHostLiteral('localhost'), isTrue);
      expect(isPrivateHostLiteral('foo.local'), isTrue);
      expect(isPrivateHostLiteral('metadata.google.internal'), isTrue);
      expect(isPrivateHostLiteral('svc.cluster.internal'), isTrue);
    });

    test('rejects IPv6 loopback / ULA / link-local literals', () {
      expect(isPrivateHostLiteral('::1'), isTrue);
      expect(isPrivateHostLiteral('[::1]'), isTrue);
      expect(isPrivateHostLiteral('fc00::1'), isTrue);
      expect(isPrivateHostLiteral('fe80::1'), isTrue);
    });

    test('rejects IPv4-mapped IPv6 private addresses', () {
      expect(isPrivateHostLiteral('::ffff:10.0.0.1'), isTrue);
      expect(isPrivateHostLiteral('::ffff:127.0.0.1'), isTrue);
      expect(isPrivateHostLiteral('::ffff:169.254.169.254'), isTrue);
      // Hex form of the embedded IPv4 (10.0.0.1) must also be caught.
      expect(isPrivateHostLiteral('::ffff:0a00:0001'), isTrue);
    });

    // The alternate IPv4 encodings the security review flagged: these all parse
    // as NULL via InternetAddress.tryParse and previously slipped past the
    // literal check entirely.
    test('rejects decimal-encoded private IPv4 literals', () {
      expect(isPrivateHostLiteral('2130706433'), isTrue); // 127.0.0.1
      expect(isPrivateHostLiteral('167772161'), isTrue); // 10.0.0.1
      expect(isPrivateHostLiteral('2852039166'), isTrue); // 169.254.169.254
    });

    test('rejects hex-encoded private IPv4 literals', () {
      expect(isPrivateHostLiteral('0x7f000001'), isTrue); // 127.0.0.1
      expect(isPrivateHostLiteral('0x0a000005'), isTrue); // 10.0.0.5
      expect(isPrivateHostLiteral('0xA.0.0.1'), isTrue); // 10.0.0.1 (mixed)
    });

    test('rejects abbreviated private IPv4 literals', () {
      expect(isPrivateHostLiteral('127.1'), isTrue); // 127.0.0.1
      expect(isPrivateHostLiteral('10.1'), isTrue); // 10.0.0.1
      expect(isPrivateHostLiteral('192.168.1'), isTrue); // 192.168.0.1
      expect(isPrivateHostLiteral('100.64.1'), isTrue); // 100.64.0.1 CGNAT
    });

    test('does NOT flag public hosts or public alternate-encoded IPv4', () {
      expect(isPrivateHostLiteral('api.klipy.com'), isFalse);
      expect(isPrivateHostLiteral('evil.example.com'), isFalse);
      expect(isPrivateHostLiteral('8.8.8.8'), isFalse);
      expect(isPrivateHostLiteral('134744072'), isFalse); // 8.8.8.8 decimal
      expect(isPrivateHostLiteral('0x08080808'), isFalse); // 8.8.8.8 hex
    });

    test('treats malformed alternate encodings as non-literal (DNS name)', () {
      // Out-of-range / junk parts are not valid IP literals; the async path
      // (DNS resolution + pinned re-validation) is responsible for these.
      expect(isPrivateHostLiteral('127.0.0.256.1'), isFalse);
      expect(isPrivateHostLiteral('0xZZ'), isFalse);
      expect(isPrivateHostLiteral('12.34.56.78.90'), isFalse);
    });
  });
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient({
    required this.statusCode,
    required this.headers,
    required this.chunks,
    this.firstChunkDelay,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<Uint8List> chunks;
  final Duration? firstChunkDelay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = (() async* {
      if (firstChunkDelay != null) {
        await Future<void>.delayed(firstChunkDelay!);
      }
      for (final chunk in chunks) {
        yield chunk;
      }
    })();

    return http.StreamedResponse(stream, statusCode, headers: headers);
  }
}
