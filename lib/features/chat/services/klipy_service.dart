/// Service for interacting with the Klipy GIF API.
///
/// Klipy serves GIFs as MP4 videos from its CDN. This service validates
/// URLs and provides search functionality.
class KlipyService {
  KlipyService._();

  /// Allowed CDN host patterns for Klipy media URLs.
  static const _allowedHosts = [
    'media.klipy.co',
    'cdn.klipy.co',
  ];

  /// Returns `true` if [url] is a valid Klipy GIF URL.
  ///
  /// Checks that the URL parses correctly and points to a known Klipy CDN host.
  static bool isValidGifUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    if (uri.scheme != 'https') return false;
    return _allowedHosts.any((host) => uri.host == host);
  }
}
