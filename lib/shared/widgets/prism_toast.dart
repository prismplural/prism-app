import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';

/// A frosted-glass toast rendered by a single app-level host.
///
/// Use [PrismToast.show] to display a toast message. The toast is attached to
/// the root app chrome rather than the caller's local overlay, so it can be
/// shown reliably from sheets, dialogs, and nested routes.
class PrismToast {
  PrismToast._();

  static final ValueNotifier<_ToastRequest?> _currentToast =
      ValueNotifier<_ToastRequest?>(null);

  static Timer? _autoDismissTimer;
  static int _nextToastId = 0;

  /// Shows a glass toast above the floating nav bar when the shell is active.
  ///
  /// Only one toast is visible at a time. Showing a new toast replaces the
  /// existing one immediately.
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
    Color? iconColor,
  }) {
    dismiss();

    final request = _ToastRequest(
      id: ++_nextToastId,
      message: message,
      bottomInset: _resolveBottomInset(context),
      icon: icon,
      iconColor: iconColor,
    );

    _currentToast.value = request;
    _autoDismissTimer = Timer(duration, () {
      if (_currentToast.value?.id == request.id) {
        dismiss();
      }
    });
  }

  /// Shows an error-styled toast.
  static void error(BuildContext context, {required String message}) {
    show(
      context,
      message: message,
      icon: AppIcons.errorOutlineRounded,
      iconColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 4),
    );
  }

  /// Shows a success-styled toast.
  static void success(BuildContext context, {required String message}) {
    show(context, message: message, icon: AppIcons.checkCircleOutlineRounded);
  }

  /// Dismisses the current toast immediately.
  static void dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _currentToast.value = null;
  }

  @visibleForTesting
  static void resetForTest() {
    dismiss();
    _nextToastId = 0;
  }

  static double _resolveBottomInset(BuildContext context) {
    final navBarInset = NavBarInset.of(context);
    if (navBarInset > 0) {
      return navBarInset + 4;
    }

    final mediaQuery = MediaQuery.maybeOf(context);
    final safeBottom = mediaQuery?.viewPadding.bottom ?? 0;
    final keyboardOpen = (mediaQuery?.viewInsets.bottom ?? 0) > 0;
    if (keyboardOpen) {
      return safeBottom + 12;
    }

    if (_isShellRoute(context)) {
      return safeBottom +
          kFloatingNavBarHeight +
          kFloatingNavBarBottomMargin +
          12;
    }

    return safeBottom + 12;
  }

  static bool _isShellRoute(BuildContext context) {
    try {
      final location = GoRouterState.of(context).matchedLocation;
      return location != AppRoutePaths.onboarding &&
          location != AppRoutePaths.secretKeySetup &&
          location != AppRoutePaths.syncSetup;
    } catch (_) {
      return false;
    }
  }
}

/// Installs the global toast host once near the app root.
///
/// Because `PrismToastHost` lives in `MaterialApp.builder`, the toast
/// overlay is a sibling of the Navigator in the Stack — not a descendant.
/// Widgets like `Tooltip` require an `Overlay` ancestor, so we provide one
/// via a nested `Overlay` that wraps just the toast layer.
class PrismToastHost extends StatelessWidget {
  const PrismToastHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        // Overlay provides an Overlay ancestor for widgets like Tooltip
        // inside the toast (which lives outside the Navigator subtree).
        // IgnorePointer is toggled so the overlay doesn't block taps when
        // no toast is visible.
        ValueListenableBuilder<_ToastRequest?>(
          valueListenable: PrismToast._currentToast,
          builder: (_, toast, child) => IgnorePointer(
            ignoring: toast == null,
            child: child,
          ),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => ValueListenableBuilder<_ToastRequest?>(
                  valueListenable: PrismToast._currentToast,
                  builder: (context, toast, _) {
                    if (toast == null) {
                      return const SizedBox.shrink();
                    }

                    return _ToastOverlay(
                      key: ValueKey<int>(toast.id),
                      toast: toast,
                      onDismiss: PrismToast.dismiss,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToastRequest {
  const _ToastRequest({
    required this.id,
    required this.message,
    required this.bottomInset,
    this.icon,
    this.iconColor,
  });

  final int id;
  final String message;
  final double bottomInset;
  final IconData? icon;
  final Color? iconColor;
}

class _ToastOverlay extends StatefulWidget {
  const _ToastOverlay({
    super.key,
    required this.toast,
    required this.onDismiss,
  });

  final _ToastRequest toast;
  final VoidCallback onDismiss;

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOled = theme.scaffoldBackgroundColor == Colors.black;
    final accentColor = theme.colorScheme.primary;
    final textColor = theme.colorScheme.onSurface;
    final messageStyle = theme.textTheme.bodyMedium?.copyWith(
      color: textColor.withValues(alpha: 0.92),
      fontWeight: FontWeight.w600,
      height: 1.25,
    );

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          PrismTokens.pageHorizontalPadding,
          12,
          PrismTokens.pageHorizontalPadding,
          widget.toast.bottomInset,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Semantics(
            container: true,
            liveRegion: true,
            label: widget.toast.message,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(PrismTokens.radiusPill),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: PrismTokens.glassBlurStrong,
                        sigmaY: PrismTokens.glassBlurStrong,
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            accentColor.withValues(alpha: isDark ? 0.08 : 0.06),
                            isDark
                                ? (isOled
                                      ? const Color(
                                          0xFF1A1A1A,
                                        ).withValues(alpha: 0.85)
                                      : AppColors.warmWhite.withValues(alpha: 0.08))
                                : AppColors.warmWhite.withValues(alpha: 0.78),
                          ),
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(PrismTokens.radiusPill),
                          ),
                          border: Border.all(
                            color: isDark
                                ? AppColors.warmWhite.withValues(alpha: 0.1)
                                : AppColors.warmBlack.withValues(alpha: 0.08),
                            width: PrismTokens.hairlineBorderWidth,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.warmBlack.withValues(
                                alpha: isDark ? 0.3 : 0.08,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (widget.toast.icon != null) ...[
                              Icon(
                                widget.toast.icon,
                                size: 18,
                                color: widget.toast.iconColor ?? accentColor,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Text(
                                widget.toast.message,
                                style: messageStyle,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Tooltip(
                              message: context.l10n.dismissNotification,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: widget.onDismiss,
                                  customBorder: PrismShapes.of(context).circleOrSquareBorder(),
                                  child: Ink(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: textColor.withValues(alpha: 0.08),
                                      shape: PrismShapes.of(context).avatarShape(),
                                      borderRadius: PrismShapes.of(context).avatarBorderRadius(),
                                    ),
                                    child: Icon(
                                      AppIcons.closeRounded,
                                      size: 16,
                                      color: textColor.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
