import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:prism_plurality/core/services/screen_security_service.dart';

/// Wraps sensitive content with platform-level screen capture protection.
///
/// While this widget is mounted:
/// - Android: FLAG_SECURE is set unless [allowAndroidScreenCapture] is true
/// - iOS: secure text field overlay is applied (blocks screen recording)
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
  /// backup or pairing key material.
  final bool allowAndroidScreenCapture;

  @override
  State<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends State<SecureScope> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ScreenSecurityService.enable(
        blockAndroidScreenCapture: !widget.allowAndroidScreenCapture,
      ),
    );
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
