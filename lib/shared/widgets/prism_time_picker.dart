import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:flutter/material.dart';

/// Shows an inline iOS 14+ time picker dropdown anchored to the calling widget.
///
/// Uses [cupertino_calendar_picker] on all platforms for a consistent,
/// modern time picking experience.
Future<TimeOfDay?> showPrismTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  final renderBox = context.findRenderObject() as RenderBox?;

  return showCupertinoTimePicker(
    context,
    widgetRenderBox: renderBox,
    initialTime: initialTime,
    use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
  );
}
