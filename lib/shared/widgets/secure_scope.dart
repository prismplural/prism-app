import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/core/services/screenshot_detector.dart';

/// Wraps sensitive content with platform-level screen capture protection
/// and post-capture screenshot warnings.
///
/// While this widget is mounted:
/// - Android: FLAG_SECURE is set unless [allowAndroidScreenCapture] is true
/// - iOS: secure text field overlay is applied (blocks screen recording)
/// - Both: screenshot events trigger a warning dialog
///
/// Uses ref-counting internally, so nesting multiple [SecureScope] widgets
/// is safe.
class SecureScope extends StatefulWidget {
  const SecureScope({
    required this.child,
    this.allowAndroidScreenCapture = false,
    super.key,
  });

  final Widget child;

  /// Allow Android screenshots/recording for screens that intentionally show
  /// backup or pairing key material. Screenshot warnings still run.
  final bool allowAndroidScreenCapture;

  @override
  State<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends State<SecureScope> {
  final _detector = ScreenshotDetector();
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(
      ScreenSecurityService.enable(
        blockAndroidScreenCapture: !widget.allowAndroidScreenCapture,
      ),
    );
    _detector.startListening();
    _subscription = _detector.onScreenshot.listen((_) {
      if (mounted) {
        ScreenshotDetector.showScreenshotWarning(context);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SecureScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allowAndroidScreenCapture ==
        widget.allowAndroidScreenCapture) {
      return;
    }
    if (!Platform.isAndroid) return;

    unawaited(
      ScreenSecurityService.disable(
        blockAndroidScreenCapture: !oldWidget.allowAndroidScreenCapture,
      ),
    );
    unawaited(
      ScreenSecurityService.enable(
        blockAndroidScreenCapture: !widget.allowAndroidScreenCapture,
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _detector.dispose();
    unawaited(
      ScreenSecurityService.disable(
        blockAndroidScreenCapture: !widget.allowAndroidScreenCapture,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
