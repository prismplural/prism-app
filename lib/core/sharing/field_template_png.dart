import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:prism_plurality/core/sharing/field_template_codec.dart'
    show kMaxTemplateCodeChars;

/// tEXt-chunk key carrying a Prism field-template share code inside a PNG.
/// Stable on purpose: desktop image-import reads this with no QR decoder.
const _templateTextKey = 'prismFieldTemplate';

/// The 8-byte PNG file signature. Sniffed before decoding so a mislabelled or
/// truncated file is rejected up front rather than crashing the decoder.
const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _looksLikePng(Uint8List bytes) {
  if (bytes.length < _pngMagic.length) return false;
  for (var i = 0; i < _pngMagic.length; i++) {
    if (bytes[i] != _pngMagic[i]) return false;
  }
  return true;
}

/// Returns a copy of [png] with [code] stored in its tEXt metadata chunk.
///
/// Non-PNG or undecodable bytes are returned unchanged. Uses
/// [img.Image.addTextData] instead of assigning into `textData` directly, since
/// `textData` is null on a freshly decoded image.
Uint8List embedTemplateInPng(Uint8List png, String code) {
  if (!_looksLikePng(png)) return png;
  try {
    final image = img.decodePng(png);
    if (image == null) return png;
    image.addTextData({_templateTextKey: code});
    return Uint8List.fromList(img.encodePng(image));
  } catch (_) {
    return png;
  }
}

/// Reads a previously embedded template code from [png]'s tEXt chunk, or null
/// when the chunk is absent, the bytes are not a PNG, or decoding fails.
///
/// Untrusted input: `decodePng` can throw on a truncated/garbage PNG, so the
/// decode is guarded, and an implausibly large chunk is rejected (the codec
/// caps it again on decode, but this avoids handing back a huge blob at all).
String? readTemplateFromPng(Uint8List png) {
  if (!_looksLikePng(png)) return null;
  try {
    final image = img.decodePng(png);
    final code = image?.textData?[_templateTextKey];
    if (code != null && code.length > kMaxTemplateCodeChars) return null;
    return code;
  } catch (_) {
    return null;
  }
}
