import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:flutter/material.dart';

/// Shows an inline iOS 14+ calendar dropdown anchored to the calling widget.
///
/// Uses [cupertino_calendar_picker] on all platforms for a consistent,
/// modern date picking experience.
///
/// Pass [anchorContext] from a [Builder] that wraps the trigger widget so the
/// popover anchors to the actual button. If omitted, [context] is used, but
/// that produces a sized-wrong popover on Android when [context] is a full
/// sheet/screen (the package auto-shrinks when there's no space around the
/// anchor).
Future<DateTime?> showPrismDatePicker({
  required BuildContext context,
  BuildContext? anchorContext,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
}) {
  final anchor = anchorContext ?? context;
  final renderBox = anchor.findRenderObject() as RenderBox?;
  final theme = Theme.of(context);

  return showCupertinoCalendarPicker(
    context,
    widgetRenderBox: renderBox,
    initialDateTime: initialDate,
    minimumDateTime: firstDate ?? DateTime(1900),
    maximumDateTime: lastDate ?? DateTime(2100),
    mainColor: theme.colorScheme.primary,
    mode: CupertinoCalendarMode.date,
    containerDecoration: PickerContainerDecoration(
      backgroundType: PickerBackgroundType.plainColor,
      backgroundColor: theme.colorScheme.surface,
    ),
  );
}
