import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:flutter/material.dart';

/// Shows an inline iOS 14+ calendar dropdown anchored to the calling widget.
///
/// Uses [cupertino_calendar_picker] on all platforms for a consistent,
/// modern date picking experience.
Future<DateTime?> showPrismDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
}) {
  final renderBox = context.findRenderObject() as RenderBox?;
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
