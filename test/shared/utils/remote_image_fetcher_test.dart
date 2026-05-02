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
      final client = MockClient((request) async {
        return http.Response.bytes(Uint8List.fromList([1]), 302);
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/redirect',
        client: client,
      );

      expect(bytes, isNull);
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
      );

      expect(bytes, isNull);
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
