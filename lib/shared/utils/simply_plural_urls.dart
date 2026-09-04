/// Returns whether [url] points at a retired Simply Plural media host.
///
/// The committed Simply Plural export fixture and the import parser both use
/// `serve.apparyllis.com` for avatar media. The wider `apparyllis.com` domain
/// is deliberately matched with a label boundary so scheme-less markdown,
/// mixed-case URLs, and a DNS trailing dot are safe to skip, while lookalikes
/// such as `apparyllis.com.example.org` and `notapparyllis.com` are not.
///
/// No other host is treated as retired. Add a host only after it is observed
/// in a real, non-sanitized Simply Plural export.
bool isRetiredSimplyPluralMediaUrl(String url) {
  var candidate = url.trim();
  if (candidate.isEmpty) return false;

  if (candidate.startsWith('//')) {
    candidate = 'https:$candidate';
  } else if (!candidate.contains('://')) {
    // Imported markdown permits scheme-less URL-like image references.
    candidate = 'https://$candidate';
  }

  final host = Uri.tryParse(
    candidate,
  )?.host.toLowerCase().replaceFirst(RegExp(r'\.+$'), '');
  if (host == null || host.isEmpty) return false;

  return host == 'apparyllis.com' || host.endsWith('.apparyllis.com');
}
