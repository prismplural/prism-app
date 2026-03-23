import 'package:intl/intl.dart';

extension DateTimeFormatting on DateTime {
  /// Returns time string like "2:30 PM".
  String toTimeString() => DateFormat.jm().format(this);

  /// Returns date string like "Mar 9, 2026".
  String toDateString() => DateFormat.yMMMd().format(this);

  /// Returns date and time like "Mar 9, 2:30 PM".
  String toDateTimeString() => DateFormat('MMM d, h:mm a').format(this);

  /// Returns a day key for grouping (e.g., "2026-03-10").
  String toDayKey() => DateFormat('yyyy-MM-dd').format(this);

  /// Returns a human-readable day header ("Today", "Yesterday", or date).
  static String formatDayHeader(String dayKey) {
    final date = DateFormat('yyyy-MM-dd').parse(dayKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat.yMMMd().format(date);
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
