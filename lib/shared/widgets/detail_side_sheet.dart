import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/widgets/modal_side_sheet_marker.dart';
import 'package:prism_plurality/shared/widgets/sheet_presentation.dart';

const _kSideSheetInset = 12.0;
const _kSideSheetRadius = 16.0;

/// Whether the current window is wide enough to present per-item detail as a
/// desktop detail surface.
///
/// This is intentionally width-only. Use [resolveAdaptiveSheetLayout] when a
/// modal surface should also honor accessibility presentation preferences.
bool shouldUseDetailSideSheet(BuildContext context) =>
    supportsDesktopDetailLayout(context);

/// Opens [builder] in a trailing modal side sheet.
Future<T?> showDetailSideSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = PrismTokens.detailSideSheetWidth,
  bool useRootNavigator = true,
  bool dismissible = true,
}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  final dimBackground = _dimBackgroundBehindSheets(context);
  final barrierColor = dimBackground
      ? _sideSheetBarrierColor(Theme.of(context))
      : Colors.transparent;

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: barrierColor,
      barrierDismissible: dismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      // Let the panel settle without making the barrier visually heavy.
      transitionDuration: reduceMotion ? Duration.zero : Anim.lg,
      reverseTransitionDuration: reduceMotion ? Duration.zero : Anim.md,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        final availableWidth = math.max(
          0.0,
          MediaQuery.sizeOf(ctx).width - (_kSideSheetInset * 2),
        );
        final sheetWidth = math.min(width, availableWidth);
        final theme = Theme.of(ctx);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final radius = PrismShapes.of(ctx).radius(_kSideSheetRadius);
        final panelColor = theme.scaffoldBackgroundColor;

        Widget panel = SizedBox(
          width: sheetWidth,
          height: double.infinity,
          child: Material(
            key: const Key('detailSideSheetPanel'),
            color: panelColor,
            surfaceTintColor: Colors.transparent,
            elevation: 20,
            shadowColor: colors.shadow.withValues(alpha: isDark ? 0.48 : 0.20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: colors.outlineVariant.withValues(
                  alpha: isDark ? 0.58 : 0.64,
                ),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ModalSideSheetMarker(child: builder(ctx)),
          ),
        );

        if (!reduceMotion) {
          // Fade with a small trailing-edge settle.
          final panelAnim = CurvedAnimation(
            parent: animation,
            curve: const Interval(0, 0.62, curve: Curves.easeOutCubic),
            reverseCurve: const Interval(0, 0.62, curve: Curves.easeIn),
          );
          panel = FadeTransition(
            opacity: panelAnim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(panelAnim),
              child: panel,
            ),
          );
        }

        Widget focusedPanel = Focus(autofocus: true, child: panel);

        if (dismissible) {
          focusedPanel = CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(ctx).maybePop(),
            },
            child: focusedPanel,
          );
        }

        return SafeArea(
          left: false,
          child: Padding(
            padding: const EdgeInsets.all(_kSideSheetInset),
            child: Align(alignment: Alignment.centerRight, child: focusedPanel),
          ),
        );
      },
    ),
  );
}

bool _dimBackgroundBehindSheets(BuildContext context) {
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    final dimBackgroundState = container.read(
      dimBackgroundBehindSheetsProvider,
    );
    return dimBackgroundState.hasValue
        ? dimBackgroundState.value ?? false
        : false;
  } on Object {
    return false;
  }
}

Color _sideSheetBarrierColor(ThemeData theme) {
  final colors = theme.colorScheme;
  final alpha = theme.brightness == Brightness.dark ? 0.34 : 0.22;
  return Color.alphaBlend(
    colors.primary.withValues(alpha: 0.10),
    colors.scrim.withValues(alpha: alpha),
  );
}
