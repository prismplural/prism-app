import 'package:flutter/widgets.dart';
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
}
