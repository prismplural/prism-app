import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;

import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';

import '../../../helpers/media_codec_test_support.dart';

void main() {
  final mediaCodecFfiLibPath = resolveMediaCodecFfiLibPath();

  setUpAll(() async {
    if (mediaCodecFfiLibPath == null) return;
    await media_codec.MediaCodecRustLib.init(
      externalLibrary: ExternalLibrary.open(mediaCodecFfiLibPath),
    );
  });

  tearDownAll(() {
    if (mediaCodecFfiLibPath != null) {
      media_codec.MediaCodecRustLib.dispose();
    }
  });

  group('PkBannerCacheService', () {
    test('production default normalizer prepares off the main isolate', () {
      expect(
        identical(
          defaultPkBannerNormalizer,
          normalizeProfileHeaderImageOffMain,
        ),
        isTrue,
      );
      expect(
        identical(defaultPkBannerNormalizer, normalizeProfileHeaderImage),
        isFalse,
        reason: 'production must not use the inline UI-isolate path',
      );
    });

    test(
      'default-constructed service resolves a real banner off the main isolate',
      skip: missingMediaCodecFfiLibReason(
        mediaCodecFfiLibPath,
        'PK banner off-main default test',
      ),
      () async {
        final source = img.Image(width: 900, height: 900);
        img.fill(source, color: img.ColorRgb8(40, 80, 120));

        final service = PkBannerCacheService(
          fetcher: (_) async => Uint8List.fromList(img.encodePng(source)),
        );

        final result = await service.resolve(
          const PkBannerCacheInput(
            currentPkBannerUrl: null,
            currentPkBannerImageData: null,
            currentPkBannerCachedUrl: null,
            hasIncomingBannerField: true,
            incomingBannerUrl: 'https://cdn.example/banner.png',
          ),
        );

        expect(result.pkBannerUrl, 'https://cdn.example/banner.png');
        expect(result.pkBannerCachedUrl, 'https://cdn.example/banner.png');
        final bytes = result.pkBannerImageData;
        expect(bytes, isNotNull);
        expect(bytes!, isNotEmpty);
        expect(
          bytes.length,
          lessThanOrEqualTo(ProfileHeaderImageNormalizer.hardMaxBytes),
        );

        // The 900x900 source was center-cropped to 3:1 by the off-isolate prep.
        final decoded = img.decodeImage(bytes);
        expect(decoded, isNotNull);
        expect((decoded!.width, decoded.height), (900, 300));
      },
    );

    test('preserves cache when banner field is missing', () async {
      final service = PkBannerCacheService(
        fetcher: (_) => throw StateError('should not fetch'),
        normalizer: (_) => throw StateError('should not normalize'),
      );

      final result = await service.resolve(
        PkBannerCacheInput(
          currentPkBannerUrl: 'https://cdn.example/banner.png',
          currentPkBannerImageData: Uint8List.fromList([1, 2, 3]),
          currentPkBannerCachedUrl: 'https://cdn.example/banner.png',
          hasIncomingBannerField: false,
          incomingBannerUrl: null,
        ),
      );

      expect(result.pkBannerUrl, 'https://cdn.example/banner.png');
      expect(result.pkBannerImageData, [1, 2, 3]);
      expect(result.pkBannerCachedUrl, 'https://cdn.example/banner.png');
    });

    test('explicit null or blank banner clears URL and cache', () async {
      final service = PkBannerCacheService();

      for (final incoming in <String?>[null, '', '   ']) {
        final result = await service.resolve(
          PkBannerCacheInput(
            currentPkBannerUrl: 'https://cdn.example/banner.png',
            currentPkBannerImageData: Uint8List.fromList([1, 2, 3]),
            currentPkBannerCachedUrl: 'https://cdn.example/banner.png',
            hasIncomingBannerField: true,
            incomingBannerUrl: incoming,
          ),
        );

        expect(result.pkBannerUrl, isNull);
        expect(result.pkBannerImageData, isNull);
        expect(result.pkBannerCachedUrl, isNull);
      }
    });

    test('same cached URL with bytes avoids network', () async {
      final service = PkBannerCacheService(
        fetcher: (_) => throw StateError('should not fetch'),
        normalizer: (_) => throw StateError('should not normalize'),
      );

      final result = await service.resolve(
        PkBannerCacheInput(
          currentPkBannerUrl: 'https://cdn.example/banner.png',
          currentPkBannerImageData: Uint8List.fromList([9]),
          currentPkBannerCachedUrl: 'https://cdn.example/banner.png',
          hasIncomingBannerField: true,
          incomingBannerUrl: ' https://cdn.example/banner.png ',
        ),
      );

      expect(result.pkBannerUrl, 'https://cdn.example/banner.png');
      expect(result.pkBannerImageData, [9]);
      expect(result.pkBannerCachedUrl, 'https://cdn.example/banner.png');
    });

    test('changed URL fetches and normalizes banner bytes', () async {
      final fetched = <String>[];
      final normalized = Uint8List.fromList([4, 5, 6]);
      final service = PkBannerCacheService(
        fetcher: (url) async {
          fetched.add(url);
          return Uint8List.fromList([1, 2, 3]);
        },
        normalizer: (bytes) async {
          expect(bytes, [1, 2, 3]);
          return normalized;
        },
      );

      final result = await service.resolve(
        PkBannerCacheInput(
          currentPkBannerUrl: 'https://cdn.example/old.png',
          currentPkBannerImageData: Uint8List.fromList([9]),
          currentPkBannerCachedUrl: 'https://cdn.example/old.png',
          hasIncomingBannerField: true,
          incomingBannerUrl: 'https://cdn.example/new.png?size=large',
        ),
      );

      expect(fetched, ['https://cdn.example/new.png?size=large']);
      expect(result.pkBannerUrl, 'https://cdn.example/new.png?size=large');
      expect(result.pkBannerImageData, normalized);
      expect(
        result.pkBannerCachedUrl,
        'https://cdn.example/new.png?size=large',
      );
    });

    test('fetch failure preserves unchanged cache', () async {
      final service = PkBannerCacheService(
        fetcher: (_) async => null,
        normalizer: (_) => throw StateError('should not normalize'),
      );

      final result = await service.resolve(
        PkBannerCacheInput(
          currentPkBannerUrl: 'https://cdn.example/banner.png',
          currentPkBannerImageData: Uint8List.fromList([7, 8]),
          currentPkBannerCachedUrl: 'https://cdn.example/banner.png',
          hasIncomingBannerField: true,
          incomingBannerUrl: 'https://cdn.example/banner.png',
        ),
      );

      expect(result.pkBannerUrl, 'https://cdn.example/banner.png');
      expect(result.pkBannerImageData, [7, 8]);
      expect(result.pkBannerCachedUrl, 'https://cdn.example/banner.png');
    });

    test(
      'fetch failure for changed URL clears stale cache but keeps metadata',
      () async {
        final service = PkBannerCacheService(
          fetcher: (_) async => null,
          normalizer: (_) => throw StateError('should not normalize'),
        );

        final result = await service.resolve(
          PkBannerCacheInput(
            currentPkBannerUrl: 'https://cdn.example/old.png',
            currentPkBannerImageData: Uint8List.fromList([7, 8]),
            currentPkBannerCachedUrl: 'https://cdn.example/old.png',
            hasIncomingBannerField: true,
            incomingBannerUrl: 'https://cdn.example/new.png',
          ),
        );

        expect(result.pkBannerUrl, 'https://cdn.example/new.png');
        expect(result.pkBannerImageData, isNull);
        expect(result.pkBannerCachedUrl, isNull);
      },
    );

    test(
      'unsupported URL schemes clear stale cache as explicit invalid input',
      () async {
        final service = PkBannerCacheService();

        final result = await service.resolve(
          PkBannerCacheInput(
            currentPkBannerUrl: 'https://cdn.example/old.png',
            currentPkBannerImageData: Uint8List.fromList([7, 8]),
            currentPkBannerCachedUrl: 'https://cdn.example/old.png',
            hasIncomingBannerField: true,
            incomingBannerUrl: 'ftp://cdn.example/new.png',
          ),
        );

        expect(result.pkBannerUrl, isNull);
        expect(result.pkBannerImageData, isNull);
        expect(result.pkBannerCachedUrl, isNull);
      },
    );
  });
}
