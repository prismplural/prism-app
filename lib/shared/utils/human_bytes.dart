/// Format a byte count as a short human-readable string.
///
/// Uses SI-style binary prefixes ("KB", "MB", "GB") with one decimal place
/// for values at or above a kilobyte. Values below a kilobyte are rendered
/// as exact byte counts. Negative inputs are clamped to zero.
///
/// Examples:
/// ```
/// humanBytes(0)          // "0 B"
/// humanBytes(512)        // "512 B"
/// humanBytes(1536)       // "1.5 KB"
/// humanBytes(12_000_000) // "11.4 MB"
/// ```
String humanBytes(int bytes) {
  if (bytes < 0) bytes = 0;
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024.0;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(1)} ${units[unit]}';
}
