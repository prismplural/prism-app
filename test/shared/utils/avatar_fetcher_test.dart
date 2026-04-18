import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/shared/utils/avatar_fetcher.dart';

void main() {
  group('fetchAvatarBytes', () {
    test('returns bytes on 2xx image response', () async {
      final body = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final client = MockClient((request) async {
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final bytes = await fetchAvatarBytes(
        'https://example.com/avatar.png',
        client: client,
      );

      expect(bytes, isNotNull);
      expect(bytes, equals(body));
    });

    test('returns null on 4xx', () async {
      final client = MockClient((request) async {
        return http.Response('nope', 404);
      });

      final bytes = await fetchAvatarBytes(
        'https://example.com/missing.png',
        client: client,
      );

      expect(bytes, isNull);
    });

    test('returns null when content-type is not image/*', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3]),
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final bytes = await fetchAvatarBytes(
        'https://example.com/page.html',
        client: client,
      );

      expect(bytes, isNull);
    });

    test('returns null on timeout', () async {
      final client = MockClient((request) async {
        // Stall longer than the configured timeout.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response.bytes(
          Uint8List.fromList([0]),
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final bytes = await fetchAvatarBytes(
        'https://example.com/slow.png',
        client: client,
        timeout: const Duration(milliseconds: 20),
      );

      expect(bytes, isNull);
    });

    test('returns null when response exceeds maxBytes cap', () async {
      final large = Uint8List(2048);
      final client = MockClient((request) async {
        return http.Response.bytes(
          large,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });

      final bytes = await fetchAvatarBytes(
        'https://example.com/big.jpg',
        client: client,
        maxBytes: 1024,
      );

      expect(bytes, isNull);
    });

    test('returns null on empty body even with image content-type', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          Uint8List(0),
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final bytes = await fetchAvatarBytes(
        'https://example.com/empty.png',
        client: client,
      );

      expect(bytes, isNull);
    });

    test('returns null when url is empty', () async {
      final client = MockClient((request) async => http.Response('', 200));
      final bytes = await fetchAvatarBytes('', client: client);
      expect(bytes, isNull);
    });
  });
}
