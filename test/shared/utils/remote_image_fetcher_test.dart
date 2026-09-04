import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';

final _testPublicAddress = InternetAddress('93.184.216.34');

Future<List<InternetAddress>> _testPublicLookup(String _) async => [
  _testPublicAddress,
];

void main() {
  setUpAll(() => setRemoteImageHostLookupForTesting(_testPublicLookup));
  tearDownAll(() => setRemoteImageHostLookupForTesting(null));

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

    test(
      'rejects AVIF image responses until the app-owned codec supports AVIF',
      () async {
        final body = _avifHeader();
        final client = MockClient((request) async {
          return http.Response.bytes(
            body,
            200,
            headers: {'content-type': 'image/avif'},
          );
        });

        final bytes = await fetchRemoteImageBytes(
          'https://example.com/banner.avif',
          client: client,
        );

        expect(bytes, isNull);
      },
    );

    test(
      'does not sniff AVIF bytes while AVIF codec support is disabled',
      () async {
        final body = _avifHeader();
        final client = MockClient((request) async {
          return http.Response.bytes(
            body,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        });

        final bytes = await fetchRemoteImageBytes(
          'https://example.com/banner',
          client: client,
        );

        expect(bytes, isNull);
      },
    );

    test('does not sniff animated AVIF as a supported still image', () async {
      final body = _avisHeader();
      final client = MockClient((request) async {
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/banner',
        client: client,
      );

      expect(bytes, isNull);
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

      // followLinkPreview:false isolates the retry semantic — otherwise a
      // notAnImage verdict legitimately triggers one extra GET for og:image.
      final result = await fetchRemoteImageResult(
        'https://example.com/page.html',
        client: client,
        initialRetryDelay: Duration.zero,
        followLinkPreview: false,
      );

      expect(result.bytes, isNull);
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

    // ── Scheme normalization (mobile users paste bare hosts) ────────────────
    test('normalizeImageUrl prepends https to a scheme-less host', () {
      expect(
        normalizeImageUrl('i.postimg.cc/x/y.png'),
        'https://i.postimg.cc/x/y.png',
      );
      expect(
        normalizeImageUrl('  files.catbox.moe/abc.png  '),
        'https://files.catbox.moe/abc.png',
      );
      expect(
        normalizeImageUrl('//cdn.example.com/a.png'),
        'https://cdn.example.com/a.png',
      );
      // Already-schemed URLs are left untouched (so http:// can be rejected).
      expect(
        normalizeImageUrl('https://example.com/a.png'),
        'https://example.com/a.png',
      );
      expect(
        normalizeImageUrl('http://example.com/a.png'),
        'http://example.com/a.png',
      );
      expect(normalizeImageUrl(''), '');
    });

    test('fetches a scheme-less URL by normalizing to https', () async {
      final body = _png([1, 2, 3]);
      Uri? seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'example.com/avatar.png',
        client: client,
      );

      expect(bytes, body);
      expect(seen?.scheme, 'https');
      expect(seen?.host, 'example.com');
    });

    // ── Magic-byte fallback for mislabeled content-types ────────────────────
    test('accepts a real image served as application/octet-stream', () async {
      final body = _png([9, 9, 9, 9]);
      final client = MockClient((request) async {
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      });

      final bytes = await fetchRemoteImageBytes(
        'https://example.com/abc.png',
        client: client,
      );

      expect(bytes, body);
    });

    test('accepts a JPEG served as the non-standard image/jpg', () async {
      final body = _jpeg([4, 5, 6]);
      final client = MockClient((request) async {
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'image/jpg'},
        );
      });

      expect(
        await fetchRemoteImageBytes(
          'https://example.com/p.jpg',
          client: client,
        ),
        body,
      );
    });

    test('accepts a real image even when labeled text/html', () async {
      final body = _png([1]);
      final client = MockClient((request) async {
        return http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      expect(
        await fetchRemoteImageBytes(
          'https://example.com/weird',
          client: client,
        ),
        body,
      );
    });

    test('rejects non-image bytes under octet-stream as notAnImage', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          Uint8List.fromList([0x3c, 0x68, 0x74, 0x6d, 0x6c]), // "<html"
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      });

      final result = await fetchRemoteImageResult(
        'https://example.com/page',
        client: client,
        initialRetryDelay: Duration.zero,
      );

      expect(result.bytes, isNull);
      expect(result.error, RemoteImageFetchError.notAnImage);
    });

    // ── Distinct failure reasons drive the UI message ───────────────────────
    test('reports notAnImage for a web page (text/html)', () async {
      final client = MockClient((request) async {
        return http.Response(
          '<!doctype html><html></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final result = await fetchRemoteImageResult(
        'https://example.com/pin/123/',
        client: client,
      );

      expect(result.error, RemoteImageFetchError.notAnImage);
    });

    test('reports unreachable for a 404', () async {
      final client = MockClient((request) async => http.Response('nope', 404));
      final result = await fetchRemoteImageResult(
        'https://example.com/missing.png',
        client: client,
      );
      expect(result.error, RemoteImageFetchError.unreachable);
    });

    test('reports tooLarge when the image exceeds the cap', () async {
      final client = _StreamingClient(
        statusCode: 200,
        headers: {'content-type': 'image/jpeg', 'content-length': '2048'},
        chunks: [
          Uint8List.fromList([1]),
        ],
      );
      final result = await fetchRemoteImageResult(
        'https://example.com/big.jpg',
        client: client,
        maxBytes: 1024,
      );
      expect(result.error, RemoteImageFetchError.tooLarge);
    });

    test('reports invalidUrl for an explicit non-https scheme', () async {
      final client = MockClient((request) async => http.Response('', 200));
      final result = await fetchRemoteImageResult(
        'http://example.com/a.png',
        client: client,
      );
      expect(result.error, RemoteImageFetchError.invalidUrl);
    });

    test('reports blockedHost for a private/loopback target', () async {
      final client = MockClient((request) async => http.Response('', 200));
      final result = await fetchRemoteImageResult(
        'https://localhost/a.png',
        client: client,
      );
      expect(result.error, RemoteImageFetchError.blockedHost);
    });

    test(
      'still blocks a hostname resolved to a private address in tests',
      () async {
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          return http.Response.bytes(
            Uint8List.fromList([1, 2, 3]),
            200,
            headers: {'content-type': 'image/png'},
          );
        });
        setRemoteImageHostLookupForTesting(
          (_) async => [InternetAddress.loopbackIPv4],
        );
        addTearDown(
          () => setRemoteImageHostLookupForTesting(_testPublicLookup),
        );

        final result = await fetchRemoteImageResult(
          'https://example.com/private-dns.png',
          client: client,
        );

        expect(result.bytes, isNull);
        expect(result.error, RemoteImageFetchError.blockedHost);
        expect(calls, 0);
      },
    );

    // ── og:image link-preview fallback (pasted page, not raw image) ─────────
    test('falls back to og:image when the URL is a web page', () async {
      final image = _png([5, 5, 5]);
      var imageHits = 0;
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/pin':
            return http.Response(
              '<html><head>'
              '<meta property="og:image" '
              'content="https://example.com/real.png">'
              '</head><body>page</body></html>',
              200,
              headers: {'content-type': 'text/html'},
            );
          case '/real.png':
            imageHits++;
            return http.Response.bytes(
              image,
              200,
              headers: {'content-type': 'image/png'},
            );
        }
        return http.Response('nope', 404);
      });

      final result = await fetchRemoteImageResult(
        'https://example.com/pin',
        client: client,
        followLinkPreview: true,
      );

      expect(result.bytes, image);
      expect(imageHits, 1);
    });

    test('uses twitter:image when there is no og:image', () async {
      final image = _jpeg([1, 2]);
      final client = MockClient((request) async {
        if (request.url.path == '/post') {
          return http.Response(
            '<head><meta name="twitter:image" '
            'content="https://example.com/tw.jpg"></head>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response.bytes(
          image,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });

      final result = await fetchRemoteImageResult(
        'https://example.com/post',
        client: client,
        followLinkPreview: true,
      );
      expect(result.bytes, image);
    });

    test('resolves a relative og:image against the page URL', () async {
      final image = _png([7]);
      Uri? imageReq;
      final client = MockClient((request) async {
        if (request.url.path == '/a/pin') {
          return http.Response(
            '<head><meta property="og:image" content="/cdn/x.png"></head>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        imageReq = request.url;
        return http.Response.bytes(
          image,
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final result = await fetchRemoteImageResult(
        'https://example.com/a/pin',
        client: client,
        followLinkPreview: true,
      );

      expect(result.bytes, image);
      expect(imageReq?.toString(), 'https://example.com/cdn/x.png');
    });

    test('does not follow an og:image that points at a private host', () async {
      final client = MockClient((request) async {
        // Page advertises a loopback preview image — an SSRF attempt.
        return http.Response(
          '<head><meta property="og:image" '
          'content="https://localhost/secret.png"></head>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final result = await fetchRemoteImageResult(
        'https://example.com/evil',
        client: client,
      );

      expect(result.bytes, isNull);
      expect(result.error, RemoteImageFetchError.notAnImage);
    });

    test('followLinkPreview: false skips the og:image fallback', () async {
      var imageHits = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/pin') {
          return http.Response(
            '<head><meta property="og:image" '
            'content="https://example.com/real.png"></head>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        imageHits++;
        return http.Response.bytes(
          _png([1]),
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final result = await fetchRemoteImageResult(
        'https://example.com/pin',
        client: client,
        followLinkPreview: false,
      );

      expect(result.error, RemoteImageFetchError.notAnImage);
      expect(imageHits, 0);
    });

    // ── Preview-metadata extraction ─────────────────────────────────────────
    test('extractPreviewImageUrl prefers og:image and decodes entities', () {
      const html =
          '<html><head>'
          '<meta name="twitter:image" content="https://e.com/tw.png">'
          '<meta content="https://e.com/og.png?a=1&amp;b=2" property="og:image">'
          '</head><body><img src="https://e.com/body.png"></body></html>';
      expect(
        extractPreviewImageUrlForTesting(html),
        'https://e.com/og.png?a=1&b=2',
      );
    });

    test('extractPreviewImageUrl falls back to twitter:image then image_src', () {
      expect(
        extractPreviewImageUrlForTesting(
          '<head><meta name="twitter:image" content="https://e.com/t.png"></head>',
        ),
        'https://e.com/t.png',
      );
      expect(
        extractPreviewImageUrlForTesting(
          '<head><link rel="image_src" href="https://e.com/l.png"></head>',
        ),
        'https://e.com/l.png',
      );
      expect(
        extractPreviewImageUrlForTesting('<head><title>x</title></head>'),
        isNull,
      );
    });

    test(
      'extractPreviewImageUrl ignores og:image structured sub-properties',
      () {
        // og:image:width appears BEFORE og:image; a substring match would return
        // "640". Exact-property matching must return the real image URL.
        const html =
            '<head>'
            '<meta property="og:image:width" content="640">'
            '<meta property="og:image:height" content="480">'
            '<meta property="og:image" content="https://e.com/real.png">'
            '</head>';
        expect(
          extractPreviewImageUrlForTesting(html),
          'https://e.com/real.png',
        );
      },
    );

    test('extractPreviewImageUrl is bounded against adversarial HTML', () {
      // ~150KB of unterminated <meta with no '>' must not drive quadratic
      // backtracking on the UI isolate (the old unbounded regex took ~7s).
      // Bounded quantifiers + the scan cap keep this well under budget; no tag
      // ever closes, so the result is null — the point is that it's FAST.
      final junk = '<meta property="og:image" ' * 6000; // ~150KB, no '>'
      final html = '<head>$junk</head>';
      final sw = Stopwatch()..start();
      final result = extractPreviewImageUrlForTesting(html);
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        lessThan(3000),
        reason: 'extraction must stay bounded on adversarial input',
      );
      expect(result, isNull);
    });

    test(
      'rejects BOM-prefixed SVG even under a trusted image/* type',
      () async {
        // EF BB BF (UTF-8 BOM) + "<svg" — a naive trimLeft() would miss the BOM
        // and accept it. The markup sniff fires regardless of content-type.
        final body = Uint8List.fromList([
          0xEF, 0xBB, 0xBF, //
          ...'<svg xmlns="http://www.w3.org/2000/svg"></svg>'.codeUnits,
        ]);
        final client = MockClient((request) async {
          return http.Response.bytes(
            body,
            200,
            headers: {'content-type': 'image/png'},
          ); // trusted, but lying
        });

        final result = await fetchRemoteImageResult(
          'https://example.com/sneaky.png',
          client: client,
        );

        expect(result.bytes, isNull);
        expect(result.error, RemoteImageFetchError.notAnImage);
      },
    );

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

Uint8List _avifHeader() => Uint8List.fromList([
  0x00,
  0x00,
  0x00,
  0x20,
  0x66,
  0x74,
  0x79,
  0x70,
  0x61,
  0x76,
  0x69,
  0x66,
]);

Uint8List _avisHeader() => Uint8List.fromList([
  0x00,
  0x00,
  0x00,
  0x20,
  0x66,
  0x74,
  0x79,
  0x70,
  0x61,
  0x76,
  0x69,
  0x73,
]);

/// A minimal PNG payload: the 8-byte signature followed by [trailer].
Uint8List _png(List<int> trailer) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...trailer,
]);

/// A minimal JPEG payload: SOI + APP0 marker bytes followed by [trailer].
Uint8List _jpeg(List<int> trailer) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...trailer]);

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
