import 'package:flutter/foundation.dart';
import 'package:qr_code_dart_decoder/qr_code_dart_decoder.dart' as qr_decoder;

Future<String?> decodeDesktopQr(Uint8List rgba, int width, int height) async {
  final event = qr_decoder.FileDecodeEvent(
    image: rgba,
    width: width,
    height: height,
    formats: const [qr_decoder.BarcodeFormat.qrCode],
  );
  final result = await qr_decoder.FileDecode.decode(event.toMap());
  return result?.text;
}
