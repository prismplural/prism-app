import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// A styled dialog wrapper with consistent Prism design language.
///
/// Uses [GlassSurface] for a frosted glass appearance that matches the app's
/// visual language. Falls back to [TintedGlassSurface] automatically when
/// visual effects are reduced.
///
/// Use [PrismDialog.show] for custom content or [PrismDialog.confirm] for a
/// standard confirmation dialog with title, message, and confirm/cancel buttons.
///
/// The body ([child] plus icon/title/message) scrolls inside the dialog shell;
/// [actions] are pinned at the bottom. Two consequences for callers:
///
/// - Put buttons in [actions], not [child] — buttons embedded in [child]
///   scroll with the body and can be pushed off-screen by tall content.
/// - Don't put [Expanded] or [Flexible] at the root of [child]. The body has
///   unbounded vertical constraints; a root-level flex child would assert.
class PrismDialog extends StatelessWidget {
  const PrismDialog({
    super.key,
    this.title,
    this.message,
    required this.child,
    this.actions,
    this.icon,
    this.iconColor,
  });

  /// Optional title rendered as `titleLarge`.
  final String? title;

  /// Optional message rendered below the title.
  final String? message;

  /// The main body content of the dialog.
  final Widget child;

  /// Optional action row at the bottom.
  final List<Widget>? actions;

  /// Optional icon rendered above the title.
  final IconData? icon;

  /// Color for the icon. Defaults to `colorScheme.primary`.
  final Color? iconColor;

  /// Show a Prism-styled glass dialog with custom content.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    String? message,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: context.l10n.dismiss,
      barrierColor: AppColors.warmBlack.withValues(alpha: isDark ? 0.55 : 0.45),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder:
          (transitionContext, animation, secondaryAnimation, child) {
            if (MediaQuery.of(transitionContext).disableAnimations) {
              return child;
            }
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
      pageBuilder: (dialogContext, _, _) {
        final content = builder(dialogContext);
        return _KeyboardAvoidingDialog(
          child: _GlassDialogShell(
            child: PrismDialog(
              title: title,
              message: message,
              actions: actions,
              child: content,
            ),
          ),
        );
      },
    );
  }

  /// Show a confirmation dialog that returns `true` on confirm or `false` on
  /// cancel / dismissal.
  ///
  /// Set [destructive] to `true` to render the confirm button in the
  /// destructive tone (error color).
  ///
  /// Provide [icon] to render an icon above the title for contextual emphasis
  /// (e.g. a warning icon for destructive confirmations).
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    bool barrierDismissible = true,
    IconData? icon,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: context.l10n.dismiss,
      barrierColor: AppColors.warmBlack.withValues(alpha: isDark ? 0.55 : 0.45),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder:
          (transitionContext, animation, secondaryAnimation, child) {
            if (MediaQuery.of(transitionContext).disableAnimations) {
              return child;
            }
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
      pageBuilder: (dialogContext, _, _) {
        return _KeyboardAvoidingDialog(
          child: _GlassDialogShell(
            child: PrismDialog(
              title: title,
              message: message,
              icon: icon,
              iconColor: destructive
                  ? Theme.of(dialogContext).colorScheme.error
                  : null,
              actions: [
                PrismButton(
                  label: cancelLabel,
                  tone: PrismButtonTone.outlined,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                PrismButton(
                  label: confirmLabel,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  tone: destructive
                      ? PrismButtonTone.destructive
                      : PrismButtonTone.filled,
                ),
              ],
              child: const SizedBox.shrink(),
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActions = actions != null && actions!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 32,
                      color: iconColor ?? theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (title != null) ...[
                    Text(
                      title!,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (message != null) ...[
                    Text(
                      message!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  child,
                ],
              ),
            ),
          ),
          if (hasActions) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shifts the centered dialog above the on-screen keyboard.
///
/// Flutter's stock [Dialog] widget does this internally; [showGeneralDialog]
/// does not, so dialogs whose content includes text input (e.g. the color
/// picker hex field) get covered on iOS without this wrapper.
class _KeyboardAvoidingDialog extends StatelessWidget {
  const _KeyboardAvoidingDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      padding: MediaQuery.viewInsetsOf(context),
      duration: const Duration(milliseconds: 100),
      curve: Curves.decelerate,
      child: MediaQuery.removeViewInsets(
        context: context,
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        child: Center(child: child),
      ),
    );
  }
}

/// Glass chrome shell for dialogs.
///
/// Inlines the frosted glass treatment so the shell shrink-wraps its content
/// (GlassSurface's Container uses alignment which forces expansion).
class _GlassDialogShell extends StatelessWidget {
  const _GlassDialogShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final maxWidth = min(size.width - 48.0, PrismTokens.dialogMaxWidth);
    final maxHeight = min(size.height * 0.8, 560.0);

    final borderRadius = BorderRadius.circular(
      PrismShapes.of(context).radius(PrismTokens.radiusLarge),
    );
    final isDark = theme.brightness == Brightness.dark;
    final dialogBaseColor =
        theme.dialogTheme.backgroundColor ??
        (isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surfaceContainerLow);
    final fillColor = dialogBaseColor.withValues(alpha: isDark ? 0.9 : 0.96);
    final borderColor = theme.colorScheme.onSurface.withValues(
      alpha: isDark ? 0.12 : 0.08,
    );

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: PrismTokens.glassBlurMedium,
              sigmaY: PrismTokens.glassBlurMedium,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: borderRadius,
                border: Border.all(
                  color: borderColor,
                  width: PrismTokens.hairlineBorderWidth,
                ),
              ),
              // A transparent Material under the glass fill so ListTile ink and
              // selection highlights paint on top of it, not behind the fill.
              child: Material(
                type: MaterialType.transparency,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
