import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

enum AdaptiveSheetRole { transientSheet, modalDetail, embeddedDetail }

enum AdaptiveSheetLayout { centeredSheet, sideSheet, route, embeddedPane }

bool supportsDesktopDetailLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= PrismTokens.detailSideSheetMinWidth;

AdaptiveSheetLayout resolveAdaptiveSheetLayout(
  BuildContext context, {
  required AdaptiveSheetRole role,
}) {
  final supportsDesktop = supportsDesktopDetailLayout(context);

  if (role == AdaptiveSheetRole.embeddedDetail) {
    return supportsDesktop
        ? AdaptiveSheetLayout.embeddedPane
        : AdaptiveSheetLayout.route;
  }

  if (!supportsDesktop) {
    return role == AdaptiveSheetRole.transientSheet
        ? AdaptiveSheetLayout.centeredSheet
        : AdaptiveSheetLayout.route;
  }

  final forceCentered = _forceCenteredSheets(context);
  if (forceCentered) return AdaptiveSheetLayout.centeredSheet;

  return AdaptiveSheetLayout.sideSheet;
}

bool _forceCenteredSheets(BuildContext context) {
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    final forceCenteredState = container.read(forceCenteredSheetsProvider);
    return forceCenteredState.hasValue
        ? forceCenteredState.value ?? false
        : false;
  } on Object {
    return false;
  }
}
