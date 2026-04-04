import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

/// Platform-adaptive time picker.
///
/// On iOS/macOS, shows a [CupertinoDatePicker] in time mode in a bottom sheet.
/// On Android/web, delegates to [showTimePicker].
Future<TimeOfDay?> showPrismTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  if (isApple) {
    return _showCupertinoTimePicker(
      context: context,
      initialTime: initialTime,
    );
  }

  return showTimePicker(
    context: context,
    initialTime: initialTime,
  );
}

Future<TimeOfDay?> _showCupertinoTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  final now = DateTime.now();
  final initialDateTime = DateTime(
    now.year,
    now.month,
    now.day,
    initialTime.hour,
    initialTime.minute,
  );
  TimeOfDay selected = initialTime;
  final use24h = MediaQuery.of(context).alwaysUse24HourFormat;

  return PrismSheet.show<TimeOfDay?>(
    context: context,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initialDateTime,
                  use24hFormat: use24h,
                  onDateTimeChanged: (dateTime) {
                    selected = TimeOfDay.fromDateTime(dateTime);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: PrismButton(
                  label: 'Done',
                  tone: PrismButtonTone.filled,
                  onPressed: () => Navigator.of(ctx).pop(selected),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
