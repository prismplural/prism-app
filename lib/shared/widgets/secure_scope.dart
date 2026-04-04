import 'dart:async';

import 'package:flutter/material.dart';

import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/core/services/screenshot_detector.dart';

/// Wraps sensitive content with platform-level screen capture protection
/// and post-capture screenshot warnings.
///
/// While this widget is mounted:
/// - Android: FLAG_SECURE is set (blocks screenshots and screen recording)
/// - iOS: secure text field overlay is applied (blocks screen recording)
/// - Both: screenshot events trigger a warning dialog
///
/// Uses ref-counting internally, so nesting multiple [SecureScope] widgets
/// is safe.
class SecureScope extends StatefulWidget {
  const SecureScope({required this.child, super.key});

  final Widget child;

  @override
  State<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends State<SecureScope> {
  final _detector = ScreenshotDetector();
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    ScreenSecurityService.enable();
    _detector.startListening();
    _subscription = _detector.onScreenshot.listen((_) {
      if (mounted) {
        ScreenshotDetector.showScreenshotWarning(context);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _detector.dispose();
    ScreenSecurityService.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
