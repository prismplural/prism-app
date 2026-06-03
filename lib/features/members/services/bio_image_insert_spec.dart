/// The size chosen in the insert-image dialog, and how to turn it into the
/// markdown sizing fragment [BioImageSize] understands.
///
/// The dialog only offers width (height always follows the image's aspect
/// ratio), mirroring the percent/em forms — the explicit `#WxH` form stays
/// available to hand-authors and SP imports but isn't surfaced in the UI.
library;

/// How an inserted image's width is specified. Each mode maps to one sizing
/// fragment form: none, `#<px>`, `#<n>%`, or `#<n>em`.
enum ImageSizeMode { defaultSize, widthPx, percent, em }

/// A size choice from the insert dialog. [value] is interpreted per [mode]
/// (pixels, percent 1–100, or em multiple) and ignored for
/// [ImageSizeMode.defaultSize].
class ImageSizeSpec {
  const ImageSizeSpec({this.mode = ImageSizeMode.defaultSize, this.value});

  final ImageSizeMode mode;
  final double? value;

  static const unset = ImageSizeSpec();

  ImageSizeSpec copyWith({ImageSizeMode? mode, double? value}) =>
      ImageSizeSpec(mode: mode ?? this.mode, value: value ?? this.value);

  /// The URL fragment to append after `#` (without the `#`), or `''` for the
  /// default size. Clamped to the same ranges [BioImageSize] accepts so the
  /// emitted fragment always round-trips back to the size the author picked.
  /// A missing or non-positive [value] falls back to `''` (no sizing).
  String get fragment {
    final v = value;
    switch (mode) {
      case ImageSizeMode.defaultSize:
        return '';
      case ImageSizeMode.widthPx:
        if (v == null || v <= 0) return '';
        return _trimZero(v.clamp(1.0, 4096.0));
      case ImageSizeMode.percent:
        if (v == null || v <= 0) return '';
        return '${_trimZero(v.clamp(1.0, 100.0))}%';
      case ImageSizeMode.em:
        if (v == null || v <= 0) return '';
        return '${_trimZero(v.clamp(0.1, 256.0))}em';
    }
  }

  /// `10.0` → `"10"`, `1.5` → `"1.5"` — drops a trailing `.0` so whole-number
  /// sizes stay tidy while fractional ones (e.g. `12.5%`) survive intact.
  static String _trimZero(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}

/// Builds an image markdown reference (`![alt](ref#fragment)`) for insertion,
/// appending the sizing fragment from [size] when present. [alt] is omitted
/// from the `![]` when empty.
String buildImageRef({
  required String tag,
  String alt = '',
  ImageSizeSpec size = ImageSizeSpec.unset,
}) {
  final frag = size.fragment;
  final ref = frag.isEmpty ? tag : '$tag#$frag';
  return alt.isEmpty ? '![]($ref)' : '![$alt]($ref)';
}
