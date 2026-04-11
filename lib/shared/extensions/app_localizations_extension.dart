import 'package:flutter/widgets.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

export 'package:prism_plurality/l10n/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  /// Access localized strings. Only call within the MaterialApp widget subtree.
  /// Will throw if called above MaterialApp (error widgets, builder: overlay).
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Safe locale string for DateFormat — e.g. 'en' or 'es'.
  String get dateLocale => Localizations.localeOf(this).toString();
}
