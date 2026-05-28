import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_avatar_cache_service.dart';

void main() {
  group('PkAvatarCacheService', () {
    test('preserves bytes when the cached URL still matches', () async {
      var fetches = 0;
      final bytes = Uint8List.fromList([1, 2, 3]);
      final service = PkAvatarCacheService(
        fetcher: (_) async {
          fetches++;
          return Uint8List.fromList([9, 9, 9]);
        },
        normalizer: (input) => input,
      );

      final result = await service.resolve(
        PkAvatarCacheInput(
          currentAvatarImageData: bytes,
          currentPkAvatarCachedUrl: 'https://cdn.example/avatar.png',
          incomingAvatarUrl: 'https://cdn.example/avatar.png',
        ),
      );

      expect(result.avatarImageData, bytes);
      expect(result.pkAvatarCachedUrl, 'https://cdn.example/avatar.png');
      expect(fetches, 0);
    });

    test('baselines a legacy local avatar before replacing it', () async {
      var fetches = 0;
      final bytes = Uint8List.fromList([1, 2, 3]);
      final service = PkAvatarCacheService(
        fetcher: (_) async {
          fetches++;
          return Uint8List.fromList([9, 9, 9]);
        },
        normalizer: (input) => input,
      );

      final result = await service.resolve(
        PkAvatarCacheInput(
          currentAvatarImageData: bytes,
          currentPkAvatarCachedUrl: null,
          incomingAvatarUrl: 'https://cdn.example/avatar.png',
        ),
      );

      expect(result.avatarImageData, bytes);
      expect(result.pkAvatarCachedUrl, 'https://cdn.example/avatar.png');
      expect(fetches, 0);
    });

    test('fetches when the incoming URL changes', () async {
      final fetched = Uint8List.fromList([9, 8, 7]);
      final service = PkAvatarCacheService(
        fetcher: (url) async {
          expect(url, 'https://cdn.example/new.png');
          return fetched;
        },
        normalizer: (input) => input,
      );

      final result = await service.resolve(
        PkAvatarCacheInput(
          currentAvatarImageData: Uint8List.fromList([1, 2, 3]),
          currentPkAvatarCachedUrl: 'https://cdn.example/old.png',
          incomingAvatarUrl: 'https://cdn.example/new.png',
        ),
      );

      expect(result.avatarImageData, fetched);
      expect(result.pkAvatarCachedUrl, 'https://cdn.example/new.png');
    });

    test(
      'keeps the old cache marker when a changed URL fails to fetch',
      () async {
        final old = Uint8List.fromList([1, 2, 3]);
        final service = PkAvatarCacheService(
          fetcher: (_) async => null,
          normalizer: (input) => input,
        );

        final result = await service.resolve(
          PkAvatarCacheInput(
            currentAvatarImageData: old,
            currentPkAvatarCachedUrl: 'https://cdn.example/old.png',
            incomingAvatarUrl: 'https://cdn.example/new.png',
          ),
        );

        expect(result.avatarImageData, old);
        expect(result.pkAvatarCachedUrl, 'https://cdn.example/old.png');
      },
    );
  });
}
