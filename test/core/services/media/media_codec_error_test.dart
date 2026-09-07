import 'package:flutter_test/flutter_test.dart';
import 'package:prism_media_codec/prism_media_codec.dart' as media_codec;

void main() {
  test('an unavailable codec reports a user-facing error', () async {
    await expectLater(
      media_codec.encodeImage(
        imageBytes: const <int>[0],
        maxWidth: 1,
        maxHeight: 1,
        quality: 85,
      ),
      throwsA(
        predicate<Object>(
          (error) =>
              error.toString() ==
              'Image processing is unavailable. '
                  'Please restart Prism and try again.',
        ),
      ),
    );
  });
}
