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
  final minimumDate = _dateOnly(firstDate ?? DateTime(1900));
  final maximumCandidate = _dateOnly(lastDate ?? DateTime(2100));
  final maximumDate = maximumCandidate.isBefore(minimumDate)
      ? minimumDate
      : maximumCandidate;
  final initialDateOnly = _clampDate(
    _dateOnly(initialDate),
    minimumDate,
    maximumDate,
  );

  return showCupertinoCalendarPicker(
    context,
    widgetRenderBox: renderBox,
    initialDateTime: initialDateOnly,
    minimumDateTime: minimumDate,
    maximumDateTime: maximumDate,
    mainColor: theme.colorScheme.primary,
    mode: CupertinoCalendarMode.date,
    containerDecoration: PickerContainerDecoration(
      backgroundType: PickerBackgroundType.plainColor,
      backgroundColor: theme.colorScheme.surface,
    ),
  );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _clampDate(DateTime date, DateTime minimum, DateTime maximum) {
  if (date.isBefore(minimum)) return minimum;
  if (date.isAfter(maximum)) return maximum;
  return date;
}
