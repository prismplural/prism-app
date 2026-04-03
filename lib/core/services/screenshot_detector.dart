import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Detects screenshots on sensitive screens and shows a warning dialog.
///
/// Uses a native EventChannel backed by:
/// - iOS: `UIApplicationUserDidTakeScreenshotNotification`
/// - Android API 34+: `Activity.registerScreenCaptureCallback`
/// - Android API < 34: `ContentObserver` on `MediaStore.Images.Media`
///
/// Screenshots are NOT blocked — users may need to capture QR codes or
/// the 12-word phrase for legitimate purposes (e.g. remote pairing,
/// offline storage). The warning informs them after the fact.
class ScreenshotDetector {
  static const _channel = EventChannel(
    'com.prism.prism_plurality/screenshot_events',
  );

  StreamSubscription<dynamic>? _subscription;
  final _controller = StreamController<void>.broadcast();

  /// Emits an event whenever a screenshot is detected.
  Stream<void> get onScreenshot => _controller.stream;

  /// Start listening for screenshots from the platform.
  void startListening() {
    _subscription ??= _channel
        .receiveBroadcastStream()
        .listen((_) => _controller.add(null), onError: (_) {
      // Silently ignore errors (e.g., unsupported platform or permission
      // denied) so that the app continues working without the warning.
    });
  }

  /// Stop listening for screenshots.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Release resources.
  void dispose() {
    stopListening();
    _controller.close();
  }

  /// Show a warning dialog about a screenshot containing sensitive data.
  ///
  /// Call this from the [onScreenshot] stream listener on any sensitive screen.
  static Future<void> showScreenshotWarning(BuildContext context) {
    return PrismDialog.show(
      context: context,
      title: 'Screenshot Detected',
      message: 'The screenshot you just took may contain sensitive key material. '
          'Anyone you share it with could access your system data.',
      builder: (ctx) => Icon(
        AppIcons.warningAmberRounded,
        color: Theme.of(ctx).colorScheme.error,
        size: 32,
      ),
      actions: [
        PrismButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'I understand',
        ),
      ],
    );
  }
}
