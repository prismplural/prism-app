import 'dart:async';

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/sheet_presentation.dart';

/// Shows a detail surface as a side sheet, centered sheet, or route.
///
/// Route fallbacks are fire-and-forget and return `null`.
Future<T?> showAdaptiveDetailSurface<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  FutureOr<void> Function(BuildContext context)? route,
  bool useRootNavigator = true,
  bool isDismissible = true,
}) async {
  AdaptiveSheetLayout layout;
  if (supportsDesktopDetailLayout(context)) {
    layout = resolveAdaptiveSheetLayout(
      context,
      role: AdaptiveSheetRole.modalDetail,
    );
  } else {
    layout = AdaptiveSheetLayout.route;
  }

  switch (layout) {
    case AdaptiveSheetLayout.sideSheet:
      return showDetailSideSheet<T>(
        context,
        useRootNavigator: useRootNavigator,
        dismissible: isDismissible,
        builder: builder,
      );
    case AdaptiveSheetLayout.centeredSheet:
      return PrismSheet.showFullScreen<T>(
        context: context,
        useRootNavigator: useRootNavigator,
        isDismissible: isDismissible,
        builder: (sheetContext, _) => builder(sheetContext),
      );
    case AdaptiveSheetLayout.route:
    case AdaptiveSheetLayout.embeddedPane:
      final routeCallback = route;
      if (routeCallback != null) {
        final result = routeCallback(context);
        if (result is Future<void>) {
          unawaited(result);
        }
      }
      return null;
  }
}
