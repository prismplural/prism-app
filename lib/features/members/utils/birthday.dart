import 'package:intl/intl.dart';

/// PluralKit "no year" sentinel. PK emits `0004-MM-DD` when the user has
/// chosen to hide the birth year. We preserve the sentinel on write so
/// round-trips back to PK are byte-identical, and collapse it to month/day
/// for display.
const int birthdayNoYearSentinel = 4;

/// LEGACY PluralKit "no year" sentinel (2026-06 PK audit low). PK treats
/// `0001-MM-DD` like `0004-MM-DD`, so accept it on READ (legacy birthdays
/// display as month+day) but NEVER write it: [formatBirthdayWire] always
/// emits [birthdayNoYearSentinel] (0004 is a leap year; 0001 is not). The
/// raw wire string is only rewritten when the user edits the birthday.
const int birthdayNoYearLegacySentinel = 1;

/// Parses a PK-style `YYYY-MM-DD` birthday string. Returns `null` for
/// missing/empty/malformed input; sentinel years (`0004`, legacy `0001`) are
/// preserved verbatim so callers can detect them via [isBirthdayYearHidden].
/// Calendar-invalid dates (e.g. `2020-02-30`) return `null` rather than
/// being silently normalized by `DateTime(y, m, d)`.
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
    // UTC keeps the round-trip check timezone-independent: in a zone that
    // skips a calendar day (e.g. Pacific/Apia 2011-12-30), a local-time
    // constructor would normalize a legitimate date onto its neighbor.
    final parsed = DateTime.utc(y, m, d);
    // Reject silent overflow normalization: the constructed date must carry
    // exactly the components we parsed.
    if (parsed.year != y || parsed.month != m || parsed.day != d) return null;
    return parsed;
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

/// Returns true if the parsed [date] uses a PK "no year" sentinel — the
/// current `0004` or the legacy `0001` (see [birthdayNoYearLegacySentinel]).
bool isBirthdayYearHidden(DateTime date) =>
    date.year == birthdayNoYearSentinel ||
    date.year == birthdayNoYearLegacySentinel;

/// Human-readable display: full date when year is set, month+day when hidden.
String formatBirthdayDisplay(DateTime date, String locale) {
  if (isBirthdayYearHidden(date)) {
    return DateFormat.MMMd(locale).format(date);
  }
  return DateFormat.yMMMd(locale).format(date);
}
