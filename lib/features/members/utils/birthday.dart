import 'package:intl/intl.dart';

/// PluralKit "no year" sentinel. PK emits `0004-MM-DD` when the user has
/// chosen to hide the birth year. We preserve the sentinel on write so
/// round-trips back to PK are byte-identical, and collapse it to month/day
/// for display.
const int birthdayNoYearSentinel = 4;

/// Parses a PK-style `YYYY-MM-DD` birthday string.
///
/// Returns `null` for missing / empty / malformed input. Year `0004` is
/// preserved verbatim on the [DateTime] so callers can detect the sentinel
/// via [isBirthdayYearHidden].
DateTime? parseBirthday(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  try {
    // Use strict parsing — DateTime.parse would accept ISO timestamps too.
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (match == null) return null;
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    return DateTime(y, m, d);
  } catch (_) {
    return null;
  }
}

/// Serializes a [DateTime] to PK wire format (`YYYY-MM-DD`).
/// If [hideYear] is true, the sentinel year `0004` is emitted.
String formatBirthdayWire(DateTime date, {bool hideYear = false}) {
  final y = (hideYear ? birthdayNoYearSentinel : date.year)
      .toString()
      .padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Returns true if the parsed [date] uses the PK "no year" sentinel.
bool isBirthdayYearHidden(DateTime date) =>
    date.year == birthdayNoYearSentinel;

/// Human-readable display: full date when year is set, month+day when hidden.
String formatBirthdayDisplay(DateTime date, String locale) {
  if (isBirthdayYearHidden(date)) {
    return DateFormat.MMMd(locale).format(date);
  }
  return DateFormat.yMMMd(locale).format(date);
}
