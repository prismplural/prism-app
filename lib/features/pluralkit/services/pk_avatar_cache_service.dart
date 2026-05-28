import 'dart:typed_data';

import 'package:prism_plurality/shared/utils/avatar_fetcher.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

typedef PkAvatarFetcher = Future<Uint8List?> Function(String url);
typedef PkAvatarNormalizer = Uint8List? Function(Uint8List bytes);

class PkAvatarCacheInput {
  const PkAvatarCacheInput({
    required this.currentAvatarImageData,
    required this.currentPkAvatarCachedUrl,
    required this.incomingAvatarUrl,
  });

  final Uint8List? currentAvatarImageData;
  final String? currentPkAvatarCachedUrl;
  final String? incomingAvatarUrl;
}

class PkAvatarCacheResult {
  const PkAvatarCacheResult({
    required this.avatarImageData,
    required this.pkAvatarCachedUrl,
  });

  final Uint8List? avatarImageData;
  final String? pkAvatarCachedUrl;
}

class PkAvatarCacheService {
  PkAvatarCacheService({
    PkAvatarFetcher? fetcher,
    PkAvatarNormalizer? normalizer,
  }) : _fetcher = fetcher ?? fetchAvatarBytes,
       _normalizer = normalizer ?? AvatarNormalizer.normalize;

  final PkAvatarFetcher _fetcher;
  final PkAvatarNormalizer _normalizer;

  Future<PkAvatarCacheResult> resolve(PkAvatarCacheInput input) async {
    final incomingUrl = _normalizeIncomingUrl(input.incomingAvatarUrl);
    if (incomingUrl == null) {
      return PkAvatarCacheResult(
        avatarImageData: input.currentAvatarImageData,
        pkAvatarCachedUrl: input.currentPkAvatarCachedUrl,
      );
    }

    final cachedBytes = input.currentAvatarImageData;
    if (input.currentPkAvatarCachedUrl == incomingUrl &&
        cachedBytes != null &&
        cachedBytes.isNotEmpty) {
      return PkAvatarCacheResult(
        avatarImageData: cachedBytes,
        pkAvatarCachedUrl: incomingUrl,
      );
    }

    if (input.currentPkAvatarCachedUrl == null &&
        cachedBytes != null &&
        cachedBytes.isNotEmpty) {
      return PkAvatarCacheResult(
        avatarImageData: cachedBytes,
        pkAvatarCachedUrl: incomingUrl,
      );
    }

    try {
      final fetched = await _fetcher(incomingUrl);
      if (fetched == null || fetched.isEmpty) return _failureResult(input);

      final normalized = _normalizer(fetched);
      if (normalized == null || normalized.isEmpty) {
        return _failureResult(input);
      }

      return PkAvatarCacheResult(
        avatarImageData: normalized,
        pkAvatarCachedUrl: incomingUrl,
      );
    } catch (_) {
      return _failureResult(input);
    }
  }

  PkAvatarCacheResult _failureResult(PkAvatarCacheInput input) {
    return PkAvatarCacheResult(
      avatarImageData: input.currentAvatarImageData,
      pkAvatarCachedUrl: input.currentPkAvatarCachedUrl,
    );
  }

  static String? _normalizeIncomingUrl(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return null;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return trimmed;
  }
}
