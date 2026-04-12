import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// Cancel action button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Save action button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Delete action button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Edit action button label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Add action button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Done action button label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Close/dismiss action button label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Confirm action button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Back navigation button label
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Options menu button label
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// Activate action button label
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// Deactivate action button label
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivate;

  /// Generic loading state label
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// Empty search results label
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// Retry action button label
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// Search placeholder/label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Generic error label
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Suggestions section header in empty state widget
  ///
  /// In en, this message translates to:
  /// **'Suggestions:'**
  String get suggestions;

  /// Unknown member option in headmate picker
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// Placeholder text on datetime pill when no date is selected
  ///
  /// In en, this message translates to:
  /// **'Tap to set'**
  String get tapToSet;

  /// Semantics label for the floating navigation bar
  ///
  /// In en, this message translates to:
  /// **'Navigation bar'**
  String get navigationBar;

  /// Semantics label for the desktop sidebar navigation
  ///
  /// In en, this message translates to:
  /// **'Main navigation'**
  String get mainNavigation;

  /// Semantics label for the nav bar More/close trigger when expanded
  ///
  /// In en, this message translates to:
  /// **'Close menu'**
  String get closeMenu;

  /// Semantics label for the nav bar More trigger when collapsed
  ///
  /// In en, this message translates to:
  /// **'More tabs'**
  String get moreTabs;

  /// Semantics label for a nav bar tab with unread messages
  ///
  /// In en, this message translates to:
  /// **'{label}, {count} unread'**
  String navUnreadCount(String label, int count);

  /// Error message shown in headmate picker when members fail to load
  ///
  /// In en, this message translates to:
  /// **'Error loading {members}: {error}'**
  String errorLoadingMembers(String members, Object error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
