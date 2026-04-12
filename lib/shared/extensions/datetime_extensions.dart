import 'package:intl/intl.dart';

extension DateTimeFormatting on DateTime {
  /// Returns time string like "2:30 PM".
  /// Pass [locale] (e.g. from context.dateLocale) to respect the device's
  /// regional format; omitting it uses the ICU default (en-US order).
  String toTimeString([String? locale]) => DateFormat.jm(locale).format(this);

  /// Returns date string like "Mar 9, 2026".
  /// Pass [locale] to respect the device's regional date format.
  String toDateString([String? locale]) =>
      DateFormat.yMMMd(locale).format(this);

  /// Returns date and time like "Mar 9, 2:30 PM".
  /// Pass [locale] to respect the device's regional format.
  String toDateTimeString([String? locale]) =>
      DateFormat('MMM d, h:mm a', locale).format(this);

  /// Returns a day key for grouping (e.g., "2026-03-10").
  String toDayKey() => DateFormat('yyyy-MM-dd').format(this);

  /// Returns a human-readable day header ("Today", "Yesterday", or date).
  ///
  /// Uses "April 7" for dates in the current year and "April 7, 2025" for
  /// older dates to save space.
  static String formatDayHeader(String dayKey) {
    final date = DateFormat('yyyy-MM-dd').parse(dayKey);
    return date.toDayHeaderLabel();
  }

  /// Returns a human-readable day label ("Today", "Yesterday", or date).
  ///
  /// Uses "April 7" for dates in the current year and "April 7, 2025" for
  /// older dates. Pass [locale] (from context.dateLocale) to format the date
  /// portion in the device's regional format. "Today"/"Yesterday" strings
  /// remain English here — full l10n of those strings requires a BuildContext
  /// and is tracked in TODOS.md (in-app format region control).
  String toDayHeaderLabel([String? locale]) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(year, month, this.day);

    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (year == now.year) return DateFormat('MMMM d', locale).format(this);
    return DateFormat('MMMM d, y', locale).format(this);
  }

  /// Returns a relative description like "5 minutes ago" or "Yesterday".
  String toRelativeString() {
    final now = DateTime.now();
    final diff = now.difference(this);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    }
    return toDateString();
  }
}
