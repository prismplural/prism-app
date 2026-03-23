import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final rng = Random(42); // deterministic seed
  final image = img.Image(width: 64, height: 64, numChannels: 4);

  // Start with fully transparent
  image.clear(img.ColorRgba8(0, 0, 0, 0));

  for (int y = 0; y < 64; y++) {
    for (int x = 0; x < 64; x++) {
      if (rng.nextDouble() < 0.06) {
        // Sparse white dot at varying opacity (50-130 alpha out of 255)
        final alpha = (rng.nextDouble() * 80 + 50).round();
        image.setPixelRgba(x, y, 255, 255, 255, alpha);
      }
    }
  }

  final dir = Directory('assets/textures');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final png = img.encodePng(image);
  File('assets/textures/noise_64x64.png').writeAsBytesSync(png);
  // ignore: avoid_print
  print('Generated noise texture: ${png.length} bytes');
}
