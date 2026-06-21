import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/core/sharing/field_template_png.dart';

void main() {
  Uint8List plainPng() {
    final image = img.Image(width: 4, height: 4);
    return Uint8List.fromList(img.encodePng(image));
  }

  test('embed then read round-trips the share code', () {
    final embedded = embedTemplateInPng(plainPng(), 'PF1:abc123');
    expect(readTemplateFromPng(embedded), 'PF1:abc123');
  });

  test('reading a plain PNG with no embedded code returns null', () {
    expect(readTemplateFromPng(plainPng()), isNull);
  });

  test('embedding keeps the PNG decodable', () {
    final embedded = embedTemplateInPng(plainPng(), 'PF1:xyz');
    expect(img.decodePng(embedded), isNotNull);
  });

  test('non-PNG bytes are returned unchanged', () {
    final garbage = Uint8List.fromList([1, 2, 3, 4]);
    expect(embedTemplateInPng(garbage, 'PF1:abc'), garbage);
    expect(readTemplateFromPng(garbage), isNull);
  });

  test('a truncated PNG (valid signature, garbage body) is handled safely', () {
    // Keeps the 8-byte PNG signature but cuts the body — decodePng can throw.
    final truncated = plainPng().sublist(0, 20);
    expect(readTemplateFromPng(truncated), isNull);
    expect(embedTemplateInPng(truncated, 'PF1:x'), truncated);
  });
}
