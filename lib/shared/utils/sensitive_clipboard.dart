import 'dart:async';

import 'package:flutter/services.dart';

/// Handles short-lived clipboard copies for sensitive values such as
/// recovery phrases and pairing payloads.
class SensitiveClipboard {
  SensitiveClipboard._();

  static Timer? _clearTimer;
  static int _copyGeneration = 0;

  static Future<void> copy(
    String text, {
    Duration clearAfter = const Duration(seconds: 15),
  }) async {
    await Clipboard.setData(ClipboardData(text: text));

    _copyGeneration++;
    final generation = _copyGeneration;
    _clearTimer?.cancel();
    _clearTimer = Timer(clearAfter, () async {
      if (generation != _copyGeneration) return;

      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != text) return;

      await Clipboard.setData(const ClipboardData(text: ''));
    });
  }
}
