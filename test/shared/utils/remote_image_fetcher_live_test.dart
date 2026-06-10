/// Live-network regression test for the default remote-image HTTP client.
///
/// Excluded from normal test runs unless explicitly enabled:
///   PRISM_LIVE_IMAGE_FETCH=1 flutter test --tags integration \
///     test/shared/utils/remote_image_fetcher_live_test.dart
@Tags(['integration'])
library;

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';

void main() {
  const liveUrl = 'https://httpbin.org/image/png';
  final liveEnabled = Platform.environment['PRISM_LIVE_IMAGE_FETCH'] == '1';

  test(
    'default pinned client fetches HTTPS image bytes',
    () async {
      final bytes = await fetchRemoteImageBytes(
        liveUrl,
        timeout: const Duration(seconds: 5),
        maxAttempts: 1,
        initialRetryDelay: Duration.zero,
      );

      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
    },
    skip: liveEnabled
        ? false
        : 'Set PRISM_LIVE_IMAGE_FETCH=1 to run live image fetch regression.',
  );

  // The reported bug: users paste a bare host with no scheme and it's rejected.
  test(
    'fetches a scheme-less URL over the real network',
    () async {
      final bytes = await fetchRemoteImageBytes(
        'httpbin.org/image/png', // no https://
        timeout: const Duration(seconds: 5),
        maxAttempts: 1,
        initialRetryDelay: Duration.zero,
      );

      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
    },
    skip: liveEnabled
        ? false
        : 'Set PRISM_LIVE_IMAGE_FETCH=1 to run live image fetch regression.',
  );

  // The og:image rescue: a Tumblr blog page is HTML, not a direct image, but it
  // advertises a real image via <meta property="og:image">.
  test(
    'resolves og:image from a real HTML page (Tumblr)',
    () async {
      final result = await fetchRemoteImageResult(
        'https://staff.tumblr.com/',
        timeout: const Duration(seconds: 8),
        maxAttempts: 1,
        initialRetryDelay: Duration.zero,
        followLinkPreview: true,
      );

      expect(result.bytes, isNotNull);
      expect(result.bytes, isNotEmpty);
    },
    skip: liveEnabled
        ? false
        : 'Set PRISM_LIVE_IMAGE_FETCH=1 to run live image fetch regression.',
  );
}
