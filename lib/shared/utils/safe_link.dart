import 'package:url_launcher/url_launcher.dart';

const _allowedSchemes = {'http', 'https', 'mailto', 'tel'};
const _maxUrlLength = 2048;

// ASCII control chars U+0000–U+001F plus DEL U+007F.
final _controlChars = RegExp('[\x00-\x1F\x7F]');

/// Returns a launch-safe [Uri] for [href], or null if it fails any guard.
///
/// Pure (no platform access) so the scheme/guard policy is unit-testable.
/// Custom-field and other peer-synced values flow through here, so this is a
/// security boundary: positive scheme allowlist, length cap, control-char and
/// whitespace rejection — not a blocklist.
Uri? safeExternalUri(String? href) {
  if (href == null) return null;
  final trimmed = href.trim();
  if (trimmed.isEmpty || trimmed.length > _maxUrlLength) return null;
  if (_controlChars.hasMatch(trimmed)) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) return null;
  return uri;
}

/// Launches [href] in the external browser iff [safeExternalUri] accepts it.
/// Silently no-ops on unsafe/invalid input, and swallows any platform error
/// (e.g. no handler app installed, platform restriction) so a throw from
/// [launchUrl] never surfaces as an unhandled async error from a tap.
Future<void> launchSafeExternalUri(String? href) async {
  final uri = safeExternalUri(href);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Unsupported or blocked URI — no-op.
  }
}
