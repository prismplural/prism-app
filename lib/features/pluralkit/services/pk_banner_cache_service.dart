import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../shared/utils/profile_header_image_normalizer.dart';
import '../../../shared/utils/remote_image_fetcher.dart';

typedef PkBannerFetcher = Future<Uint8List?> Function(String url);
typedef PkBannerNormalizer = Future<Uint8List> Function(Uint8List bytes);

class PkBannerCacheInput {
  const PkBannerCacheInput({
    required this.currentPkBannerUrl,
    required this.currentPkBannerImageData,
    required this.currentPkBannerCachedUrl,
    required this.hasIncomingBannerField,
    required this.incomingBannerUrl,
  });

  final String? currentPkBannerUrl;
  final Uint8List? currentPkBannerImageData;
  final String? currentPkBannerCachedUrl;
  final bool hasIncomingBannerField;
  final String? incomingBannerUrl;
}

class PkBannerCacheResult {
  const PkBannerCacheResult({
    required this.pkBannerUrl,
    required this.pkBannerImageData,
    required this.pkBannerCachedUrl,
  });

  final String? pkBannerUrl;
  final Uint8List? pkBannerImageData;
  final String? pkBannerCachedUrl;
}

class PkBannerCacheService {
  PkBannerCacheService({
    http.Client? client,
    PkBannerFetcher? fetcher,
    PkBannerNormalizer? normalizer,
  }) : _fetcher =
           fetcher ??
           ((url) => fetchRemoteImageBytes(
             url,
             client: client,
             maxBytes: bannerMaxBytes,
           )),
       _normalizer = normalizer ?? normalizeProfileHeaderImage;

  static const bannerMaxBytes = 10 * 1024 * 1024;

  final PkBannerFetcher _fetcher;
  final PkBannerNormalizer _normalizer;

  Future<PkBannerCacheResult> resolve(PkBannerCacheInput input) async {
    if (!input.hasIncomingBannerField) {
      return PkBannerCacheResult(
        pkBannerUrl: input.currentPkBannerUrl,
        pkBannerImageData: input.currentPkBannerImageData,
        pkBannerCachedUrl: input.currentPkBannerCachedUrl,
      );
    }

    final incomingUrl = _normalizeIncomingUrl(input.incomingBannerUrl);
    if (incomingUrl == null) {
      return const PkBannerCacheResult(
        pkBannerUrl: null,
        pkBannerImageData: null,
        pkBannerCachedUrl: null,
      );
    }

    final cachedBytes = input.currentPkBannerImageData;
    if (input.currentPkBannerCachedUrl == incomingUrl &&
        cachedBytes != null &&
        cachedBytes.isNotEmpty) {
      return PkBannerCacheResult(
        pkBannerUrl: incomingUrl,
        pkBannerImageData: cachedBytes,
        pkBannerCachedUrl: incomingUrl,
      );
    }

    try {
      final fetched = await _fetcher(incomingUrl);
      if (fetched == null || fetched.isEmpty) {
        return _failureResult(input, incomingUrl);
      }

      final normalized = await _normalizer(fetched);
      if (normalized.isEmpty) {
        return _failureResult(input, incomingUrl);
      }

      return PkBannerCacheResult(
        pkBannerUrl: incomingUrl,
        pkBannerImageData: normalized,
        pkBannerCachedUrl: incomingUrl,
      );
    } catch (_) {
      return _failureResult(input, incomingUrl);
    }
  }

  PkBannerCacheResult _failureResult(
    PkBannerCacheInput input,
    String incomingUrl,
  ) {
    final unchanged = input.currentPkBannerUrl == incomingUrl;
    final cachedBytes = input.currentPkBannerImageData;
    if (unchanged && cachedBytes != null && cachedBytes.isNotEmpty) {
      return PkBannerCacheResult(
        pkBannerUrl: incomingUrl,
        pkBannerImageData: cachedBytes,
        pkBannerCachedUrl: input.currentPkBannerCachedUrl,
      );
    }

    return PkBannerCacheResult(
      pkBannerUrl: incomingUrl,
      pkBannerImageData: null,
      pkBannerCachedUrl: null,
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
