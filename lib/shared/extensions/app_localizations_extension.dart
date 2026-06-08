import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

export 'package:prism_plurality/l10n/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  /// Access localized strings. Only call within the MaterialApp widget subtree.
  /// Will throw if called above MaterialApp (error widgets, builder: overlay).
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Locale string for DateFormat/NumberFormat — uses the platform's regional
  /// format locale (e.g. 'en_CR', 'es_US') rather than the app's resolved
  /// language locale. This correctly handles mixed configurations where the
  /// user has English UI but a non-English region (different date order,
  /// decimal separator, currency symbol, etc.).
  String get dateLocale =>
      WidgetsBinding.instance.platformDispatcher.locale.toString();

  /// Resolved 12/24-hour preference. Prefers MediaQuery (subscribes to changes)
  /// and falls back to the platform dispatcher when MediaQuery is unavailable
  /// (e.g. above MaterialApp). The value is the OS-resolved setting, which
  /// already accounts for both the regional locale's default *and* any
  /// user-level override (iOS Settings > General > Date & Time > 24-Hour Time
  /// and Android equivalent).
  bool get use24HourTime =>
      MediaQuery.maybeOf(this)?.alwaysUse24HourFormat ??
      WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;

  /// Format a time like "2:30 PM" (12-hour) or "14:30" (24-hour), honoring
  /// both the regional locale and the OS 24-hour toggle.
  String formatTime(DateTime dt) {
    return use24HourTime
        ? DateFormat.Hm(dateLocale).format(dt)
        : DateFormat('h:mm a', dateLocale).format(dt);
  }

  /// Format a date+time like "Mar 9, 2:30 PM" or "Mar 9, 14:30", honoring
  /// the regional locale (date ordering) and the OS 24-hour toggle.
  ///
  /// Includes the year only when the date is not in the current calendar year
  /// (e.g. "Mar 9, 2025, 2:30 PM" vs "Mar 9, 2:30 PM").
  String formatDateTime(DateTime dt) {
    final base = dt.year == DateTime.now().year
        ? DateFormat.MMMd(dateLocale)
        : DateFormat.yMMMd(dateLocale);
    return use24HourTime
        ? base.add_Hm().format(dt)
        : base.addPattern('h:mm a').format(dt);
  }
}
