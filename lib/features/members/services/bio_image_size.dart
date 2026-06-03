/// Parsed sizing spec from a markdown image URL fragment.
///
/// Supports a superset of Simply Plural's `#WxH` convention so ported SP
/// bios render identically while adding single-dimension and percentage forms:
///
/// - `#200x150` → exact width × height in logical px (SP-compatible)
/// - `#200` or `#200x` → width 200px, height auto (preserve aspect ratio)
/// - `#x150` → height 150px, width auto (preserve aspect ratio)
/// - `#100%` / `#50%` → width as a fraction of available width, height auto
/// - `#10em` → width as a multiple of the surrounding text size, height auto
///
/// An empty/absent fragment yields [BioImageSize.unset], which renders at the
/// default size (DPR-scaled intrinsic, capped to a max height).
class BioImageSize {
  /// Explicit width in logical pixels, or null.
  final double? width;

  /// Explicit height in logical pixels, or null.
  final double? height;

  /// Width as a fraction (0–1) of the available width, or null.
  final double? widthFraction;

  /// Width as a multiple of the surrounding text's font size (`1em` = the
  /// effective body font size, accessibility scaling included), or null.
  /// Like [widthFraction] this is width-only; height follows the aspect ratio.
  final double? widthEm;

  const BioImageSize({
    this.width,
    this.height,
    this.widthFraction,
    this.widthEm,
  });

  static const unset = BioImageSize();

  bool get isUnset =>
      width == null &&
      height == null &&
      widthFraction == null &&
      widthEm == null;

  /// Parse a URL fragment (the part after `#`) into a [BioImageSize].
  factory BioImageSize.parse(String? fragment) {
    if (fragment == null || fragment.isEmpty) return unset;

    final f = fragment.trim();

    // Percentage: "100%", "50%" → width fraction, height auto.
    if (f.endsWith('%')) {
      final pct = double.tryParse(f.substring(0, f.length - 1));
      if (pct == null || pct <= 0) return unset;
      return BioImageSize(widthFraction: (pct / 100).clamp(0.0, 1.0));
    }

    // Em: "10em", "1.5em" → width as a multiple of the font size, height auto.
    // Clamped so a `#9999em` can't blow up layout (256em ≈ the 4096px px cap at
    // a typical font size).
    if (f.endsWith('em')) {
      final em = double.tryParse(f.substring(0, f.length - 2));
      if (em == null || em <= 0) return unset;
      return BioImageSize(widthEm: em.clamp(0.1, 256.0));
    }

    // WxH forms.
    final parts = f.split('x');
    if (parts.length == 2) {
      // "200x150" / "200x" / "x150"
      final w = parts[0].isEmpty ? null : double.tryParse(parts[0]);
      final h = parts[1].isEmpty ? null : double.tryParse(parts[1]);
      if (w == null && h == null) return unset;
      return BioImageSize(width: _clampPx(w), height: _clampPx(h));
    } else if (parts.length == 1) {
      // "200" → width only
      final w = double.tryParse(parts[0]);
      if (w == null) return unset;
      return BioImageSize(width: _clampPx(w));
    }

    return unset;
  }

  /// Clamp pixel dimensions to a sane range so a malicious `#99999x99999`
  /// can't blow up layout.
  static double? _clampPx(double? v) {
    if (v == null) return null;
    return v.clamp(1.0, 4096.0);
  }
}
