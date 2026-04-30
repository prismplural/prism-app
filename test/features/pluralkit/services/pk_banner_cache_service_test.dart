import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';

void main() {
  group('PkBannerCacheService', () {
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
