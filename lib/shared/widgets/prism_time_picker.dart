import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:flutter/material.dart';

/// Shows an inline iOS 14+ time picker dropdown anchored to the calling widget.
///
/// Uses [cupertino_calendar_picker] on all platforms for a consistent,
/// modern time picking experience.
///
/// Pass [anchorContext] from a [Builder] that wraps the trigger widget so the
/// popover anchors to the actual button. If omitted, [context] is used, but
/// that produces a sized-wrong popover on Android when [context] is a full
/// sheet/screen (the package auto-shrinks when there's no space around the
/// anchor).
Future<TimeOfDay?> showPrismTimePicker({
  required BuildContext context,
  BuildContext? anchorContext,
  required TimeOfDay initialTime,
}) {
  final anchor = anchorContext ?? context;
  final renderBox = anchor.findRenderObject() as RenderBox?;

  return showCupertinoTimePicker(
    context,
    widgetRenderBox: renderBox,
    initialTime: initialTime,
    use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
  );
}
