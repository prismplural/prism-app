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
}
