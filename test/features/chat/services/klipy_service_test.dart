import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';

/// Helper to build a realistic Klipy API response body.
Map<String, dynamic> _buildResponse(List<Map<String, dynamic>> items) {
  return {
    'data': {
      'data': items,
    },
  };
}

/// A minimal valid GIF item with the nested file structure.
Map<String, dynamic> _gifItem({
  String id = '123',
  String title = 'funny cat',
  String type = 'gif',
  Map<String, dynamic>? file,
}) {
  return {
    'id': id,
    'title': title,
    'type': type,
    'file': file ??
        {
          'xs': {
            'mp4': {
              'url': 'https://media.klipy.com/xs.mp4',
              'width': 100,
              'height': 80,
              'size': 50000,
            },
            'gif': {
              'url': 'https://media.klipy.com/xs.gif',
              'width': 100,
              'height': 80,
              'size': 200000,
            },
          },
          'sm': {
            'mp4': {
              'url': 'https://media.klipy.com/sm.mp4',
              'width': 200,
              'height': 160,
              'size': 84000,
            },
          },
        },
  };
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // URL construction
  // ══════════════════════════════════════════════════════════════════════════

  group('URL construction', () {
    test('trending builds correct URL with query params', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode(_buildResponse([])), 200);
      });
      final service = KlipyService(httpClient: client);

      await service.trending();

      expect(capturedUri, isNotNull);
      expect(
        capturedUri!.toString(),
        startsWith(
          'https://api.klipy.com/api/v1/PRISM_KLIPY_DEV/gifs/trending',
        ),
      );
      expect(capturedUri!.queryParameters['per_page'], '30');
      expect(capturedUri!.queryParameters['page'], '1');
      expect(capturedUri!.queryParameters['content_filter'], 'medium');

      service.dispose();
    });

    test('search builds correct URL with q parameter', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode(_buildResponse([])), 200);
      });
      final service = KlipyService(httpClient: client);

      await service.search('cats');

      expect(capturedUri, isNotNull);
      expect(
        capturedUri!.toString(),
        startsWith(
          'https://api.klipy.com/api/v1/PRISM_KLIPY_DEV/gifs/search',
        ),
      );
      expect(capturedUri!.queryParameters['q'], 'cats');
      expect(capturedUri!.queryParameters['per_page'], '30');
      expect(capturedUri!.queryParameters['page'], '1');
      expect(capturedUri!.queryParameters['content_filter'], 'medium');

      service.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Response parsing
  // ══════════════════════════════════════════════════════════════════════════

  group('response parsing', () {
    test('parses KlipyGif with xs mp4 url, preview, and dimensions', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(_buildResponse([_gifItem()])),
          200,
        );
      });
      final service = KlipyService(httpClient: client);

      final gifs = await service.trending();

      expect(gifs, hasLength(1));
      final gif = gifs.first;
      expect(gif.id, '123');
      expect(gif.title, 'funny cat');
      expect(gif.mp4Url, 'https://media.klipy.com/xs.mp4');
      expect(gif.previewUrl, 'https://media.klipy.com/xs.gif');
      expect(gif.width, 100);
      expect(gif.height, 80);

      service.dispose();
    });

    test('falls back to sm mp4 when xs has no mp4', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(_buildResponse([
            _gifItem(file: {
              'xs': {
                'gif': {
                  'url': 'https://media.klipy.com/xs.gif',
                  'width': 100,
                  'height': 80,
                },
              },
              'sm': {
                'mp4': {
                  'url': 'https://media.klipy.com/sm.mp4',
                  'width': 200,
                  'height': 160,
                },
              },
            }),
          ])),
          200,
        );
      });
      final service = KlipyService(httpClient: client);

      final gifs = await service.trending();

      expect(gifs, hasLength(1));
      expect(gifs.first.mp4Url, 'https://media.klipy.com/sm.mp4');
      expect(gifs.first.width, 200);
      expect(gifs.first.height, 160);

      service.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Filtering
  // ══════════════════════════════════════════════════════════════════════════

  group('filtering', () {
    test('excludes items with type "ad"', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(_buildResponse([
            _gifItem(id: 'real-gif', type: 'gif'),
            _gifItem(id: 'ad-item', type: 'ad'),
          ])),
          200,
        );
      });
      final service = KlipyService(httpClient: client);

      final gifs = await service.trending();

      expect(gifs, hasLength(1));
      expect(gifs.first.id, 'real-gif');

      service.dispose();
    });

    test('excludes items with no mp4 url', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(_buildResponse([
            _gifItem(id: 'good'),
            _gifItem(id: 'empty-file', file: {}),
          ])),
          200,
        );
      });
      final service = KlipyService(httpClient: client);

      final gifs = await service.trending();

      expect(gifs, hasLength(1));
      expect(gifs.first.id, 'good');

      service.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Error handling
  // ══════════════════════════════════════════════════════════════════════════

  group('error handling', () {
    test('429 throws KlipyRateLimitError', () async {
      final client = MockClient((request) async {
        return http.Response('Rate limited', 429);
      });
      final service = KlipyService(httpClient: client);

      expect(service.trending, throwsA(isA<KlipyRateLimitError>()));

      service.dispose();
    });

    test('500 throws KlipyApiError', () async {
      final client = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });
      final service = KlipyService(httpClient: client);

      expect(service.trending, throwsA(isA<KlipyApiError>()));

      service.dispose();
    });

    test('KlipyRateLimitError is a KlipyApiError', () {
      const error = KlipyRateLimitError();
      expect(error, isA<KlipyApiError>());
      expect(error.statusCode, 429);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Empty query fallback
  // ══════════════════════════════════════════════════════════════════════════

  group('empty query fallback', () {
    test('search with empty string calls trending endpoint', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode(_buildResponse([])), 200);
      });
      final service = KlipyService(httpClient: client);

      await service.search('');

      expect(capturedUri, isNotNull);
      expect(capturedUri!.path, contains('/trending'));
      expect(capturedUri!.queryParameters.containsKey('q'), isFalse);

      service.dispose();
    });

    test('search with whitespace-only string calls trending endpoint',
        () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode(_buildResponse([])), 200);
      });
      final service = KlipyService(httpClient: client);

      await service.search('   ');

      expect(capturedUri, isNotNull);
      expect(capturedUri!.path, contains('/trending'));

      service.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // URL validation
  // ══════════════════════════════════════════════════════════════════════════

  group('isValidGifUrl', () {
    test('accepts Klipy CDN URL', () {
      expect(
        KlipyService.isValidGifUrl('https://media.klipy.com/gif.mp4'),
        isTrue,
      );
    });

    test('accepts Tenor view URL', () {
      expect(
        KlipyService.isValidGifUrl('https://tenor.com/view/cat.gif'),
        isTrue,
      );
    });

    test('accepts Tenor CDN subdomain', () {
      expect(
        KlipyService.isValidGifUrl('https://c.tenor.com/thing.mp4'),
        isTrue,
      );
    });

    test('accepts gstatic CDN URL', () {
      expect(
        KlipyService.isValidGifUrl('https://fonts.gstatic.com/thing.mp4'),
        isTrue,
      );
    });

    test('rejects unknown domain', () {
      expect(
        KlipyService.isValidGifUrl('https://evil.com/gif.mp4'),
        isFalse,
      );
    });

    test('rejects domain that looks like klipy but is not', () {
      expect(
        KlipyService.isValidGifUrl('https://fakeklipy.com/gif.mp4'),
        isFalse,
      );
    });

    test('rejects non-http scheme', () {
      expect(
        KlipyService.isValidGifUrl('ftp://media.klipy.com/gif.mp4'),
        isFalse,
      );
    });

    test('rejects empty string', () {
      expect(KlipyService.isValidGifUrl(''), isFalse);
    });

    test('rejects malformed URL', () {
      expect(KlipyService.isValidGifUrl('not a url at all'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Dimension validation
  // ══════════════════════════════════════════════════════════════════════════

  group('dimension validation', () {
    test('clamps width > 10000 to 0', () {
      final gif = KlipyGif.fromJson({
        'id': '1',
        'title': 'wide',
        'type': 'gif',
        'file': {
          'xs': {
            'mp4': {
              'url': 'https://media.klipy.com/xs.mp4',
              'width': 20000,
              'height': 100,
            },
          },
        },
      });

      expect(gif.width, 0);
    });

    test('clamps height > 10000 to 0', () {
      final gif = KlipyGif.fromJson({
        'id': '1',
        'title': 'tall',
        'type': 'gif',
        'file': {
          'xs': {
            'mp4': {
              'url': 'https://media.klipy.com/xs.mp4',
              'width': 100,
              'height': 15000,
            },
          },
        },
      });

      expect(gif.height, 0);
    });

    test('clamps negative width to 0', () {
      final gif = KlipyGif.fromJson({
        'id': '1',
        'title': 'negative',
        'type': 'gif',
        'file': {
          'xs': {
            'mp4': {
              'url': 'https://media.klipy.com/xs.mp4',
              'width': -5,
              'height': 100,
            },
          },
        },
      });

      expect(gif.width, 0);
    });

    test('clamps zero height to 0', () {
      final gif = KlipyGif.fromJson({
        'id': '1',
        'title': 'zero',
        'type': 'gif',
        'file': {
          'xs': {
            'mp4': {
              'url': 'https://media.klipy.com/xs.mp4',
              'width': 100,
              'height': 0,
            },
          },
        },
      });

      expect(gif.height, 0);
    });
  });
}
