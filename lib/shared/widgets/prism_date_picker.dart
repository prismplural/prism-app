import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';

const double _pickerWidth = 360;
const double _pickerHorizontalMargin = 16;
const double _pickerVerticalGap = 10;
const double _estimatedPickerHeight = 380;

/// Shows a calendar dropdown anchored to the calling widget.
///
/// Pass [anchorContext] from a [Builder] that wraps the trigger widget so the
/// popover anchors to the actual button. If omitted, [context] is used.
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

  return Navigator.of(context).push<DateTime?>(
    _AnchoredPickerRoute<DateTime?>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      anchorRenderBox: renderBox,
      theme: theme,
      child: _DatePickerContent(
        initialDate: initialDateOnly,
        firstDate: minimumDate,
        lastDate: maximumDate,
        initialCalendarMode: initialDatePickerMode,
      ),
    ),
  );
}

Future<DateTime?> showPrismMonthYearPicker({
  required BuildContext context,
  BuildContext? anchorContext,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  bool includeYear = true,
}) {
  final anchor = anchorContext ?? context;
  final renderBox = anchor.findRenderObject() as RenderBox?;
  final theme = Theme.of(context);
  final minimumDate = _dateOnly(firstDate ?? DateTime(1900, 1));
  final maximumCandidate = _dateOnly(lastDate ?? DateTime(2100, 12, 31));
  final maximumDate = maximumCandidate.isBefore(minimumDate)
      ? minimumDate
      : maximumCandidate;
  final initialDateOnly = _clampDate(
    _dateOnly(initialDate),
    minimumDate,
    maximumDate,
  );

  return Navigator.of(context).push<DateTime?>(
    _AnchoredPickerRoute<DateTime?>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      anchorRenderBox: renderBox,
      theme: theme,
      child: _MonthYearPicker(
        initialDate: initialDateOnly,
        firstDate: minimumDate,
        lastDate: maximumDate,
        includeYear: includeYear,
      ),
    ),
  );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _clampDate(DateTime date, DateTime minimum, DateTime maximum) {
  if (date.isBefore(minimum)) return minimum;
  if (date.isAfter(maximum)) return maximum;
  return date;
}

class _AnchoredPickerRoute<T> extends PopupRoute<T> {
  _AnchoredPickerRoute({
    required this.barrierLabel,
    required this.anchorRenderBox,
    required this.theme,
    required this.child,
  });

  final RenderBox? anchorRenderBox;
  final ThemeData theme;
  final Widget child;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return _AnchoredDatePickerRoute(
      anchorRenderBox: anchorRenderBox,
      theme: theme,
      animation: curved,
      child: child,
    );
  }
}

class _AnchoredDatePickerRoute extends StatelessWidget {
  const _AnchoredDatePickerRoute({
    required this.anchorRenderBox,
    required this.theme,
    required this.animation,
    this.child,
  });

  final RenderBox? anchorRenderBox;
  final ThemeData theme;
  final Animation<double> animation;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final safeArea = mediaQuery.padding;
    final width = (screenSize.width - _pickerHorizontalMargin * 2).clamp(
      0.0,
      _pickerWidth,
    );
    final anchorRect = _anchorRect();
    final topLimit = safeArea.top + _pickerHorizontalMargin;
    final bottomLimit =
        screenSize.height - safeArea.bottom - _pickerHorizontalMargin;
    final left = anchorRect == null
        ? (screenSize.width - width) / 2
        : (anchorRect.center.dx - width / 2).clamp(
            _pickerHorizontalMargin + safeArea.left,
            screenSize.width - width - _pickerHorizontalMargin - safeArea.right,
          );
    final position = _positionPicker(
      anchorRect: anchorRect,
      topLimit: topLimit,
      bottomLimit: bottomLimit,
      screenHeight: screenSize.height,
    );
    final alignment = position.bottom == null
        ? Alignment.topCenter
        : Alignment.bottomCenter;

    return Theme(
      data: theme,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: position.top,
            bottom: position.bottom,
            width: width,
            child: FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                alignment: alignment,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: position.maxHeight),
                  child: SingleChildScrollView(
                    child: Material(
                      color: theme.colorScheme.surface,
                      elevation: 8,
                      shadowColor: theme.colorScheme.shadow.withValues(
                        alpha: 0.18,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Rect? _anchorRect() {
    final renderBox = anchorRenderBox;
    if (renderBox == null || !renderBox.hasSize) return null;
    final origin = renderBox.localToGlobal(Offset.zero);
    return origin & renderBox.size;
  }

  _PickerPosition _positionPicker({
    required Rect? anchorRect,
    required double topLimit,
    required double bottomLimit,
    required double screenHeight,
  }) {
    if (anchorRect == null) {
      return _PickerPosition(
        top: topLimit,
        maxHeight: (bottomLimit - topLimit).clamp(0.0, double.infinity),
      );
    }

    final belowTop = anchorRect.bottom + _pickerVerticalGap;
    final availableBelow = bottomLimit - belowTop;
    final aboveBottom = screenHeight - anchorRect.top + _pickerVerticalGap;
    final availableAbove = anchorRect.top - _pickerVerticalGap - topLimit;
    final shouldOpenAbove =
        availableBelow < _estimatedPickerHeight &&
        availableAbove > availableBelow;

    if (shouldOpenAbove) {
      return _PickerPosition(
        bottom: aboveBottom,
        maxHeight: availableAbove.clamp(0.0, double.infinity),
      );
    }

    final top = belowTop.clamp(topLimit, bottomLimit);
    return _PickerPosition(
      top: top,
      maxHeight: (bottomLimit - top).clamp(0.0, double.infinity),
    );
  }
}

class _DatePickerContent extends StatefulWidget {
  const _DatePickerContent({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.initialCalendarMode,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final DatePickerMode initialCalendarMode;

  @override
  State<_DatePickerContent> createState() => _DatePickerContentState();
}

class _DatePickerContentState extends State<_DatePickerContent> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return CalendarDatePicker(
      initialDate: _selectedDate,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      currentDate: DateTime.now(),
      initialCalendarMode: widget.initialCalendarMode,
      onDateChanged: (date) {
        final picked = _dateOnly(date);
        final isYearOnlyChange =
            picked.year != _selectedDate.year &&
            picked.month == _selectedDate.month &&
            picked.day == _selectedDate.day;
        setState(() {
          _selectedDate = picked;
        });
        if (widget.initialCalendarMode == DatePickerMode.year ||
            !isYearOnlyChange) {
          Navigator.of(context).pop(picked);
        }
      },
    );
  }
}

class _PickerPosition {
  const _PickerPosition({this.top, this.bottom, required this.maxHeight});

  final double? top;
  final double? bottom;
  final double maxHeight;
}

class _MonthYearPicker extends StatefulWidget {
  const _MonthYearPicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.includeYear,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool includeYear;

  @override
  State<_MonthYearPicker> createState() => _MonthYearPickerState();
}

class _MonthYearPickerState extends State<_MonthYearPicker> {
  late DateTime _selectedDate;
  late bool _choosingYear;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _choosingYear = widget.includeYear;
  }

  @override
  Widget build(BuildContext context) {
    if (_choosingYear) {
      return CalendarDatePicker(
        initialDate: _selectedDate,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        currentDate: DateTime.now(),
        initialCalendarMode: DatePickerMode.year,
        onDateChanged: (date) {
          setState(() {
            final day = _selectedDate.day.clamp(
              1,
              DateUtils.getDaysInMonth(date.year, _selectedDate.month),
            );
            _selectedDate = _clampDate(
              DateTime(date.year, _selectedDate.month, day),
              widget.firstDate,
              widget.lastDate,
            );
            _choosingYear = false;
          });
        },
      );
    }

    final theme = Theme.of(context);
    final cupertinoLocalizations = CupertinoLocalizations.of(context);
    final year = _selectedDate.year;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.includeYear) ...[
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _choosingYear = true;
                  }),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).previousPageTooltip,
                ),
                Expanded(
                  child: Text(
                    year.toString(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
          ],
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.4,
            children: [
              for (var month = 1; month <= 12; month++)
                _MonthButton(
                  label: cupertinoLocalizations.datePickerStandaloneMonth(
                    month,
                  ),
                  selected: month == _selectedDate.month,
                  enabled: _isMonthEnabled(year, month),
                  onPressed: () {
                    final day = _selectedDate.day.clamp(
                      1,
                      DateUtils.getDaysInMonth(year, month),
                    );
                    Navigator.of(context).pop(
                      _clampDate(
                        DateTime(year, month, day),
                        widget.firstDate,
                        widget.lastDate,
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isMonthEnabled(int year, int month) {
    final firstOfMonth = DateTime(year, month);
    final lastOfMonth = DateTime(
      year,
      month,
      DateUtils.getDaysInMonth(year, month),
    );
    return !lastOfMonth.isBefore(widget.firstDate) &&
        !firstOfMonth.isAfter(widget.lastDate);
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return FilledButton.tonal(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: selected ? colors.primaryContainer : null,
        foregroundColor: selected ? colors.onPrimaryContainer : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
