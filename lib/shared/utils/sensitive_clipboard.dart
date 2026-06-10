import 'dart:async';

import 'package:flutter/services.dart';

/// Handles short-lived clipboard copies for sensitive values such as
/// recovery phrases and pairing payloads.
///
/// DEFERRED (needs a platform channel — intentionally NOT done here): Flutter's
/// [Clipboard.setData] cannot mark a copy as sensitive, so this helper does not
/// set Android 13's `EXTRA_IS_SENSITIVE` (which suppresses the clipboard
/// preview UI and excludes the value from cloud-synced clipboard history) nor
/// iOS `UIPasteboard` `localOnly` + `expirationDate`. Implementing those
/// requires native Kotlin/Swift behind a MethodChannel. Until then:
///   * the [clearAfter] timer below is the only mitigation, and it is
///     best-effort — on Android 10+ a backgrounded app reads `null` from
///     [Clipboard.getData], so the match-and-clear no-ops in the common case
///     where the user backgrounded Prism to paste elsewhere;
///   * the value remains eligible for the clipboard preview and cloud-synced
///     clipboards within the window.
/// See docs/security-reviews/2026-06-09 finding M4 for the full native fix.
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
