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

  /// Member picker placeholder when no member is selected
  ///
  /// In en, this message translates to:
  /// **'Select {term}'**
  String selectMember(String term);

  /// Member picker placeholder for multi-select
  ///
  /// In en, this message translates to:
  /// **'Select {termPlural}'**
  String selectMembers(String termPlural);

  /// Member picker hint text
  ///
  /// In en, this message translates to:
  /// **'Select a {termLower}'**
  String selectAMember(String termLower);

  /// Error message with detail
  ///
  /// In en, this message translates to:
  /// **'Error: {detail}'**
  String errorWithDetail(Object detail);

  /// Semantics label for segmented control widget
  ///
  /// In en, this message translates to:
  /// **'Segmented control'**
  String get segmentedControl;

  /// Tooltip for dismiss button on toast notifications
  ///
  /// In en, this message translates to:
  /// **'Dismiss notification'**
  String get dismissNotification;

  /// Hint text in emoji search field
  ///
  /// In en, this message translates to:
  /// **'Search emoji...'**
  String get searchEmoji;

  /// Tooltip and semantics label for removing an emoji from a record
  ///
  /// In en, this message translates to:
  /// **'Clear emoji'**
  String get clearEmoji;

  /// Hint text and semantics label for Phosphor icon search
  ///
  /// In en, this message translates to:
  /// **'Search icons'**
  String get searchIcons;

  /// Tooltip and semantics label for removing a selected icon
  ///
  /// In en, this message translates to:
  /// **'Clear icon'**
  String get clearIcon;

  /// Tooltip and semantics label for choosing an icon
  ///
  /// In en, this message translates to:
  /// **'Pick icon'**
  String get pickIcon;

  /// Tab label for emoji choices in the combined icon picker
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get iconPickerEmojiTab;

  /// Tab label for Phosphor icon choices in the combined icon picker
  ///
  /// In en, this message translates to:
  /// **'Icons'**
  String get iconPickerIconsTab;

  /// Empty state text when icon picker search has no matching icons
  ///
  /// In en, this message translates to:
  /// **'No icons found'**
  String get iconPickerNoResults;

  /// Accessibility barrier label for dismissing dialogs
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Semantics hint for destructive action buttons
  ///
  /// In en, this message translates to:
  /// **'Destructive action'**
  String get destructiveAction;

  /// Empty state in member search
  ///
  /// In en, this message translates to:
  /// **'No {termPlural} found'**
  String noMembersFound(String termPlural);

  /// Tooltip for 'more options' menu button
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// Settings section header for system/collective data
  ///
  /// In en, this message translates to:
  /// **'{systemTerm}'**
  String settingsSectionSystem(String systemTerm);

  /// Settings section header: App
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsSectionApp;

  /// Settings section header: Data
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsSectionData;

  /// Settings link: System Information
  ///
  /// In en, this message translates to:
  /// **'{systemTerm} Information'**
  String settingsSystemInformation(String systemTerm);

  /// Settings link: Groups
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get settingsGroups;

  /// Settings link: Custom Fields
  ///
  /// In en, this message translates to:
  /// **'Custom Fields'**
  String get settingsCustomFields;

  /// Settings link: Statistics
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get settingsStatistics;

  /// Settings link: Appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Settings link and screen title for member and system terminology
  ///
  /// In en, this message translates to:
  /// **'Terminology'**
  String get settingsTerminology;

  /// Settings link: Navigation
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get settingsNavigation;

  /// Settings link: Accessibility
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsAccessibility;

  /// Settings link: Features
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get settingsFeatures;

  /// Settings link: Privacy & Security
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get settingsPrivacySecurity;

  /// Settings link: Notifications
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// Settings link: Sync
  ///
  /// In en, this message translates to:
  /// **'Prism Sync'**
  String get settingsSync;

  /// Settings link: Sharing
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get settingsSharing;

  /// Settings link: Import & Export
  ///
  /// In en, this message translates to:
  /// **'Import & Export'**
  String get settingsImportExport;

  /// Settings link: Reset Data
  ///
  /// In en, this message translates to:
  /// **'Reset Data'**
  String get settingsResetData;

  /// Settings link and page title: About Prism
  ///
  /// In en, this message translates to:
  /// **'About Prism'**
  String get settingsAbout;

  /// Settings link: Debug
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get settingsDebug;

  /// Fallback display name when no system name is set
  ///
  /// In en, this message translates to:
  /// **'My {systemTerm}'**
  String settingsFallbackSystemName(String systemTerm);

  /// Language settings row title
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// Language settings row subtitle
  ///
  /// In en, this message translates to:
  /// **'Follows your device settings'**
  String get settingsLanguageSubtitle;

  /// Appearance settings screen title
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceTitle;

  /// Accessibility settings screen title
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibilityTitle;

  /// Accessibility settings section for visual preferences
  ///
  /// In en, this message translates to:
  /// **'Visual'**
  String get accessibilityVisualSection;

  /// Accessibility setting title for dimming the app behind modal side sheets
  ///
  /// In en, this message translates to:
  /// **'Dim behind side sheets'**
  String get accessibilityDimSheetsTitle;

  /// Accessibility setting subtitle for dimming the app behind modal side sheets
  ///
  /// In en, this message translates to:
  /// **'Tint the rest of the app when a side pane is open.'**
  String get accessibilityDimSheetsSubtitle;

  /// Accessibility settings section for sheet presentation preferences
  ///
  /// In en, this message translates to:
  /// **'Sheets'**
  String get accessibilitySheetsSection;

  /// Accessibility setting title for forcing centered/mobile-style sheets on wide layouts
  ///
  /// In en, this message translates to:
  /// **'Use centered sheets'**
  String get accessibilityForceCenteredSheetsTitle;

  /// Accessibility setting subtitle for forcing centered/mobile-style sheets on wide layouts
  ///
  /// In en, this message translates to:
  /// **'Open forms and detail sheets in the centered sheet style on desktop.'**
  String get accessibilityForceCenteredSheetsSubtitle;

  /// Error shown when accessibility preferences fail to load
  ///
  /// In en, this message translates to:
  /// **'Could not load accessibility preferences.'**
  String get accessibilityPreferencesLoadError;

  /// Accessibility settings section for font, text size, and letter spacing controls
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get accessibilityTypographySection;

  /// Label for the app font family picker in accessibility settings
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get accessibilityFontFamilyLabel;

  /// Label for the app text size slider in accessibility settings
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get accessibilityFontSizeLabel;

  /// Displayed value for the app text size slider
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String accessibilityFontSizeValue(int percent);

  /// Label for the app letter spacing slider in accessibility settings
  ///
  /// In en, this message translates to:
  /// **'Letter spacing'**
  String get accessibilityLetterSpacingLabel;

  /// Displayed value for the app letter spacing slider. The value is measured in logical pixels.
  ///
  /// In en, this message translates to:
  /// **'{value} logical px'**
  String accessibilityLetterSpacingValue(String value);

  /// Displayed letter spacing value when the app uses the selected font's normal spacing
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get accessibilityLetterSpacingNormal;

  /// Displayed letter spacing offset from the selected font's normal spacing
  ///
  /// In en, this message translates to:
  /// **'{value} from normal'**
  String accessibilityLetterSpacingOffsetValue(String value);

  /// Preview sentence shown below typography accessibility controls
  ///
  /// In en, this message translates to:
  /// **'The quick brown fox jumps over the lazy dog. 0123456789 /?.,:;'**
  String get accessibilityTypographyPreviewText;

  /// Button that resets font family, text size, and letter spacing to defaults
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get accessibilityResetTypographyButton;

  /// Accessibility typography toggle title for using Prism's display font on titles and headings
  ///
  /// In en, this message translates to:
  /// **'Use display font'**
  String get accessibilityUseDisplayFontTitle;

  /// Accessibility typography toggle subtitle for using Prism's display font on titles and headings
  ///
  /// In en, this message translates to:
  /// **'Use Unbounded for titles and headings'**
  String get accessibilityUseDisplayFontSubtitle;

  /// Appearance settings section: Brightness
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get appearanceBrightness;

  /// Appearance settings section: Style
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get appearanceStyle;

  /// Label shown when Material You style is active
  ///
  /// In en, this message translates to:
  /// **'Uses your system color palette'**
  String get appearanceUsesSystemPalette;

  /// Theme style segment label for Prism's default theme
  ///
  /// In en, this message translates to:
  /// **'Prism'**
  String get appearanceStylePrism;

  /// Theme style segment label for OLED theme
  ///
  /// In en, this message translates to:
  /// **'OLED'**
  String get appearanceStyleOled;

  /// Theme style segment label for generated palette themes
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get appearanceStylePalette;

  /// Palette settings screen title
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get paletteTitle;

  /// Compact palette settings summary
  ///
  /// In en, this message translates to:
  /// **'{source} · {mood} · {contrast}'**
  String paletteSummary(String source, String mood, String contrast);

  /// Palette summary source label for a custom seed color
  ///
  /// In en, this message translates to:
  /// **'Custom {color}'**
  String paletteSummaryCustom(String color);

  /// Palette source section title
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get paletteSourceTitle;

  /// Palette source option for device dynamic colors
  ///
  /// In en, this message translates to:
  /// **'Device colors'**
  String get paletteSourceDeviceColors;

  /// Palette source option for user selected color
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get paletteSourceCustomColor;

  /// Subtitle for available device color source
  ///
  /// In en, this message translates to:
  /// **'Use colors from this device when Prism can read them'**
  String get paletteSourceDeviceSubtitle;

  /// Subtitle for unavailable device color source
  ///
  /// In en, this message translates to:
  /// **'Available on Android devices with dynamic colors'**
  String get paletteSourceDeviceUnavailableSubtitle;

  /// Subtitle for custom color palette source
  ///
  /// In en, this message translates to:
  /// **'Pick a seed color and let Prism generate the palette'**
  String get paletteSourceCustomSubtitle;

  /// Palette seed color section title
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get paletteColorTitle;

  /// Palette mood section title
  ///
  /// In en, this message translates to:
  /// **'Mood'**
  String get paletteMoodTitle;

  /// Palette mood label: tonal
  ///
  /// In en, this message translates to:
  /// **'Tonal'**
  String get paletteMoodTonal;

  /// Palette mood label: vibrant
  ///
  /// In en, this message translates to:
  /// **'Vibrant'**
  String get paletteMoodVibrant;

  /// Palette mood label: expressive
  ///
  /// In en, this message translates to:
  /// **'Expressive'**
  String get paletteMoodExpressive;

  /// Palette mood label: fidelity
  ///
  /// In en, this message translates to:
  /// **'Fidelity'**
  String get paletteMoodFidelity;

  /// Palette mood label: monochrome
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get paletteMoodMonochrome;

  /// Palette mood description: tonal
  ///
  /// In en, this message translates to:
  /// **'Balanced Prism color with gentle accents'**
  String get paletteMoodTonalDescription;

  /// Palette mood description: vibrant
  ///
  /// In en, this message translates to:
  /// **'Higher saturation for stronger accents'**
  String get paletteMoodVibrantDescription;

  /// Palette mood description: expressive
  ///
  /// In en, this message translates to:
  /// **'Playful hue shifts around your seed color'**
  String get paletteMoodExpressiveDescription;

  /// Palette mood description: fidelity
  ///
  /// In en, this message translates to:
  /// **'Stays close to the color you chose'**
  String get paletteMoodFidelityDescription;

  /// Palette mood description: monochrome
  ///
  /// In en, this message translates to:
  /// **'Low-chroma surfaces with grayscale accents'**
  String get paletteMoodMonochromeDescription;

  /// Palette contrast section title
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get paletteContrastTitle;

  /// Palette contrast label: soft
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get paletteContrastSoft;

  /// Palette contrast label: standard
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get paletteContrastStandard;

  /// Palette contrast label: high
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get paletteContrastHigh;

  /// Palette preview section title
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get palettePreviewTitle;

  /// First sample member name in the palette preview
  ///
  /// In en, this message translates to:
  /// **'Lavender'**
  String get palettePreviewMemberOne;

  /// First sample member detail in the palette preview
  ///
  /// In en, this message translates to:
  /// **'fronting now'**
  String get palettePreviewMemberOneDetail;

  /// Second sample member name in the palette preview
  ///
  /// In en, this message translates to:
  /// **'Sol'**
  String get palettePreviewMemberTwo;

  /// Second sample member detail in the palette preview
  ///
  /// In en, this message translates to:
  /// **'nearby'**
  String get palettePreviewMemberTwoDetail;

  /// Sample filled button label in the palette preview
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get palettePreviewButton;

  /// Sample input placeholder in the palette preview
  ///
  /// In en, this message translates to:
  /// **'Share a note...'**
  String get palettePreviewInput;

  /// Sample chip label in the palette preview
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get palettePreviewChip;

  /// Small navigation surface hint in the palette preview
  ///
  /// In en, this message translates to:
  /// **'Home · Members · Settings'**
  String get palettePreviewNavHint;

  /// Palette reset section title
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get paletteResetTitle;

  /// Palette reset action row title
  ///
  /// In en, this message translates to:
  /// **'Reset palette'**
  String get paletteResetAction;

  /// Palette reset action row subtitle
  ///
  /// In en, this message translates to:
  /// **'Restore source, mood, contrast, and seed color defaults'**
  String get paletteResetDescription;

  /// Palette seed color name for Prism's lavender default
  ///
  /// In en, this message translates to:
  /// **'Lavender'**
  String get paletteSeedLavender;

  /// Appearance settings section: Corner style
  ///
  /// In en, this message translates to:
  /// **'Corner style'**
  String get appearanceCornerStyleTitle;

  /// Corner style option: Rounded
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get appearanceCornerStyleRounded;

  /// Corner style option: Square
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get appearanceCornerStyleAngular;

  /// Description text for the corner style picker
  ///
  /// In en, this message translates to:
  /// **'Choose between rounded or square corners throughout the app.'**
  String get appearanceCornerStyleDescription;

  /// Appearance settings section: which member name to show
  ///
  /// In en, this message translates to:
  /// **'Member names'**
  String get appearanceMemberNamesTitle;

  /// Member name display option: show the full name
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get appearanceMemberNamesDisplay;

  /// Member name display option: show the canonical name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get appearanceMemberNamesLegacy;

  /// Description text for the member name display picker
  ///
  /// In en, this message translates to:
  /// **'Choose which name to show for members across the app.'**
  String get appearanceMemberNamesDescription;

  /// Toggle title for showing both full name and canonical name where space allows
  ///
  /// In en, this message translates to:
  /// **'Show alternate name'**
  String get appearanceMemberNamesShowAlternateTitle;

  /// Toggle description for showing both full name and canonical name where space allows
  ///
  /// In en, this message translates to:
  /// **'Shows the other name beside the primary name where there is room.'**
  String get appearanceMemberNamesShowAlternateDescription;

  /// Appearance settings section: Accent Color
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get appearanceAccentColor;

  /// Appearance settings section: Per-Member Colors
  ///
  /// In en, this message translates to:
  /// **'{term} accent colors'**
  String appearancePerMemberColors(String term);

  /// Toggle row title: enable per-member accent colors
  ///
  /// In en, this message translates to:
  /// **'Automatically assign accent colors'**
  String get appearancePerMemberColorsSwitchTitle;

  /// Toggle row subtitle: explain per-member accent colors
  ///
  /// In en, this message translates to:
  /// **'Assigns each {term} an accent color if they don\'t have one'**
  String appearancePerMemberColorsSwitchSubtitle(String term);

  /// Appearance settings section: Sync
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get appearanceSyncSection;

  /// Toggle title: sync theme across devices
  ///
  /// In en, this message translates to:
  /// **'Sync theme across devices'**
  String get appearanceSyncThemeTitle;

  /// Toggle subtitle: sync theme across devices
  ///
  /// In en, this message translates to:
  /// **'Share brightness, style, and accent color via sync'**
  String get appearanceSyncThemeSubtitle;

  /// Appearance settings section: bio rendering
  ///
  /// In en, this message translates to:
  /// **'Bios'**
  String get appearanceBioMarkdownSection;

  /// Toggle title: render member bios as markdown
  ///
  /// In en, this message translates to:
  /// **'Render bio markdown'**
  String get appearanceBioMarkdownTitle;

  /// Toggle subtitle: render member bios as markdown
  ///
  /// In en, this message translates to:
  /// **'Format bios with bold, italics, links, and lists'**
  String get appearanceBioMarkdownSubtitle;

  /// Appearance settings section: Terminology
  ///
  /// In en, this message translates to:
  /// **'Terminology'**
  String get appearanceTerminology;

  /// Settings section title for terminology used for people/members
  ///
  /// In en, this message translates to:
  /// **'Member terminology'**
  String get terminologyMemberSectionTitle;

  /// Settings section description for member terminology
  ///
  /// In en, this message translates to:
  /// **'Controls labels for people in Prism.'**
  String get terminologyMemberSectionDescription;

  /// Settings section title for terminology used for the user's collective/system
  ///
  /// In en, this message translates to:
  /// **'System terminology'**
  String get terminologySystemSectionTitle;

  /// Settings section description for system terminology
  ///
  /// In en, this message translates to:
  /// **'Controls labels for your collective across Prism.'**
  String get terminologySystemSectionDescription;

  /// Default singular collective/system terminology
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get terminologySystemDefaultSingular;

  /// Default plural collective/system terminology
  ///
  /// In en, this message translates to:
  /// **'Systems'**
  String get terminologySystemDefaultPlural;

  /// Preset singular collective/system terminology: Collective
  ///
  /// In en, this message translates to:
  /// **'Collective'**
  String get terminologySystemPresetCollectiveSingular;

  /// Preset plural collective/system terminology: Collectives
  ///
  /// In en, this message translates to:
  /// **'Collectives'**
  String get terminologySystemPresetCollectivePlural;

  /// Preset singular collective/system terminology: Community
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get terminologySystemPresetCommunitySingular;

  /// Preset plural collective/system terminology: Communities
  ///
  /// In en, this message translates to:
  /// **'Communities'**
  String get terminologySystemPresetCommunityPlural;

  /// Preset singular collective/system terminology: Network
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get terminologySystemPresetNetworkSingular;

  /// Preset plural collective/system terminology: Networks
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get terminologySystemPresetNetworkPlural;

  /// Preset singular collective/system terminology: Constellation
  ///
  /// In en, this message translates to:
  /// **'Constellation'**
  String get terminologySystemPresetConstellationSingular;

  /// Preset plural collective/system terminology: Constellations
  ///
  /// In en, this message translates to:
  /// **'Constellations'**
  String get terminologySystemPresetConstellationPlural;

  /// Subtitle for custom terminology choice tiles
  ///
  /// In en, this message translates to:
  /// **'Your own terms'**
  String get terminologyCustomTermsSubtitle;

  /// Segment label for default system terminology
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get terminologySystemModeDefault;

  /// Segment label for custom system terminology
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get terminologySystemModeCustom;

  /// Label for custom system singular terminology field
  ///
  /// In en, this message translates to:
  /// **'Singular'**
  String get terminologySystemCustomSingularLabel;

  /// Hint for custom system singular terminology field
  ///
  /// In en, this message translates to:
  /// **'Collective'**
  String get terminologySystemCustomSingularHint;

  /// Label for custom system plural terminology field
  ///
  /// In en, this message translates to:
  /// **'Plural'**
  String get terminologySystemCustomPluralLabel;

  /// Hint for custom system plural terminology field
  ///
  /// In en, this message translates to:
  /// **'Collectives'**
  String get terminologySystemCustomPluralHint;

  /// Validation message when a custom system term pair is incomplete
  ///
  /// In en, this message translates to:
  /// **'Enter both singular and plural terms.'**
  String get terminologySystemCustomRequired;

  /// Validation message when a custom system term is too long
  ///
  /// In en, this message translates to:
  /// **'Use {maxLength} characters or fewer.'**
  String terminologySystemCustomTooLong(int maxLength);

  /// Live preview for custom system terminology settings
  ///
  /// In en, this message translates to:
  /// **'\"{systemTerm} Information\" · \"Add your first {systemTermLower} {memberTermLower}\"'**
  String terminologySystemPreview(
    String systemTerm,
    String systemTermLower,
    String memberTermLower,
  );

  /// Settings section title for terminology used for fronting/presence/activity
  ///
  /// In en, this message translates to:
  /// **'Fronting terminology'**
  String get terminologyFrontingSectionTitle;

  /// Settings section description for fronting terminology
  ///
  /// In en, this message translates to:
  /// **'Controls labels for who\'s active now, related actions, history, and reminders.'**
  String get terminologyFrontingSectionDescription;

  /// Subtitle for custom fronting terminology choice tile
  ///
  /// In en, this message translates to:
  /// **'Full phrase editor'**
  String get terminologyFrontingCustomSubtitle;

  /// Intro text above custom fronting terminology fields
  ///
  /// In en, this message translates to:
  /// **'Advanced mode lets you edit every phrase Prism derives from this terminology.'**
  String get terminologyFrontingCustomIntro;

  /// Validation message when a custom fronting phrase bundle is incomplete
  ///
  /// In en, this message translates to:
  /// **'Fill in every fronting phrase before saving.'**
  String get terminologyFrontingCustomRequired;

  /// Validation message when a custom fronting phrase is too long
  ///
  /// In en, this message translates to:
  /// **'Use {maxLength} characters or fewer per phrase.'**
  String terminologyFrontingCustomTooLong(int maxLength);

  /// Live preview for fronting terminology settings
  ///
  /// In en, this message translates to:
  /// **'\"{question}\" · \"{activePlural}\" · \"{logAction}\" · \"{historyLabel}\"'**
  String terminologyFrontingPreview(
    String question,
    String activePlural,
    String logAction,
    String historyLabel,
  );

  /// Custom fronting terminology field group title
  ///
  /// In en, this message translates to:
  /// **'Primary labels'**
  String get terminologyFrontingGroupPrimary;

  /// Custom fronting terminology field group subtitle
  ///
  /// In en, this message translates to:
  /// **'Headings, current-state text, and active-member labels.'**
  String get terminologyFrontingGroupPrimarySubtitle;

  /// Custom fronting terminology action field group title
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get terminologyFrontingGroupActions;

  /// Custom fronting terminology action field group subtitle
  ///
  /// In en, this message translates to:
  /// **'Buttons, menu items, and hold hints.'**
  String get terminologyFrontingGroupActionsSubtitle;

  /// Custom fronting terminology history field group title
  ///
  /// In en, this message translates to:
  /// **'History and stats'**
  String get terminologyFrontingGroupHistory;

  /// Custom fronting terminology history field group subtitle
  ///
  /// In en, this message translates to:
  /// **'Session, analytics, sorting, and data labels.'**
  String get terminologyFrontingGroupHistorySubtitle;

  /// Custom fronting terminology co-fronting/together field group title
  ///
  /// In en, this message translates to:
  /// **'Together states'**
  String get terminologyFrontingGroupTogether;

  /// Custom fronting terminology co-fronting/together field group subtitle
  ///
  /// In en, this message translates to:
  /// **'Shared activity, overlap, and add-together phrases.'**
  String get terminologyFrontingGroupTogetherSubtitle;

  /// Custom fronting terminology changes/reminders field group title
  ///
  /// In en, this message translates to:
  /// **'Changes and reminders'**
  String get terminologyFrontingGroupChanges;

  /// Custom fronting terminology changes/reminders field group subtitle
  ///
  /// In en, this message translates to:
  /// **'Change events, reminder triggers, and delay labels.'**
  String get terminologyFrontingGroupChangesSubtitle;

  /// Custom fronting terminology pinned/correction field group title
  ///
  /// In en, this message translates to:
  /// **'Pinned and correction labels'**
  String get terminologyFrontingGroupPinned;

  /// Custom fronting terminology pinned/correction field group subtitle
  ///
  /// In en, this message translates to:
  /// **'Long-running, always-active, Quick Switch, and import event labels.'**
  String get terminologyFrontingGroupPinnedSubtitle;

  /// Section title for language picker in appearance settings
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get appearanceLanguage;

  /// Option to use the system/device language
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get appearanceLanguageSystem;

  /// Footer note below the language picker
  ///
  /// In en, this message translates to:
  /// **'More languages coming soon'**
  String get appearanceLanguageFooter;

  /// Appearance settings section: Preview
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get appearancePreview;

  /// Sample pronouns in the appearance preview card
  ///
  /// In en, this message translates to:
  /// **'she/her'**
  String get appearanceSamplePronouns;

  /// Sample member title in the appearance preview card
  ///
  /// In en, this message translates to:
  /// **'Sample {term}'**
  String appearanceSampleMember(String term);

  /// Fronting pill label in the appearance preview card
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get appearanceFronting;

  /// Sync settings screen title
  ///
  /// In en, this message translates to:
  /// **'Prism Sync'**
  String get syncTitle;

  /// Title shown when sync health is disconnected
  ///
  /// In en, this message translates to:
  /// **'Sync was disconnected'**
  String get syncDisconnectedTitle;

  /// Message shown when sync is disconnected
  ///
  /// In en, this message translates to:
  /// **'Set up sync again to reconnect your devices.'**
  String get syncDisconnectedMessage;

  /// Button label to navigate to sync setup
  ///
  /// In en, this message translates to:
  /// **'Set Up Sync'**
  String get syncSetUpSyncButton;

  /// Title shown when sync settings fail to load
  ///
  /// In en, this message translates to:
  /// **'Unable to load sync settings'**
  String get syncUnableToLoad;

  /// Title when sync has not been configured
  ///
  /// In en, this message translates to:
  /// **'Enable Prism Sync'**
  String get syncNotSetUp;

  /// Description shown when sync is not configured
  ///
  /// In en, this message translates to:
  /// **'Set up end-to-end encrypted sync to keep your data in sync across all your devices.'**
  String get syncNotSetUpDescription;

  /// Button label on sync setup intro step
  ///
  /// In en, this message translates to:
  /// **'Set up sync'**
  String get syncSetupButton;

  /// Settings row title: sync now
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNowTitle;

  /// Settings row subtitle: sync now
  ///
  /// In en, this message translates to:
  /// **'Check for changes and push local updates'**
  String get syncNowSubtitle;

  /// Label shown while sync is in progress
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncInProgress;

  /// Settings row title: set up another device
  ///
  /// In en, this message translates to:
  /// **'Set up another device'**
  String get syncSetUpAnotherDevice;

  /// Settings row subtitle: set up another device
  ///
  /// In en, this message translates to:
  /// **'Scan a pairing code'**
  String get syncSetUpAnotherDeviceSubtitle;

  /// Settings row title: manage devices
  ///
  /// In en, this message translates to:
  /// **'Manage Devices'**
  String get syncManageDevices;

  /// Settings row subtitle: manage devices
  ///
  /// In en, this message translates to:
  /// **'View and revoke linked devices'**
  String get syncManageDevicesSubtitle;

  /// Settings row title: change sync PIN
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get syncChangePassword;

  /// Settings row subtitle: change sync PIN
  ///
  /// In en, this message translates to:
  /// **'Update your sync encryption PIN'**
  String get syncChangePasswordSubtitle;

  /// Settings row title: view secret key
  ///
  /// In en, this message translates to:
  /// **'View Secret Key'**
  String get syncViewSecretKey;

  /// Settings row subtitle: view secret key
  ///
  /// In en, this message translates to:
  /// **'Show your 12-word recovery phrase'**
  String get syncViewSecretKeySubtitle;

  /// Section title for sync preferences
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get syncPreferencesSection;

  /// Description for sync preferences section
  ///
  /// In en, this message translates to:
  /// **'Control what settings are shared across your devices via sync.'**
  String get syncPreferencesDescription;

  /// Toggle title in Prism Sync preferences for sharing appearance settings
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get syncPreferenceAppearanceTitle;

  /// Toggle subtitle in Prism Sync preferences for sharing appearance settings
  ///
  /// In en, this message translates to:
  /// **'Share appearance settings across devices.'**
  String get syncPreferenceAppearanceSubtitle;

  /// Toggle title in Prism Sync preferences for ignoring incoming synced appearance settings
  ///
  /// In en, this message translates to:
  /// **'Local appearance'**
  String get syncPreferenceLocalAppearanceTitle;

  /// Toggle subtitle in Prism Sync preferences for ignoring incoming synced appearance settings
  ///
  /// In en, this message translates to:
  /// **'Do not apply appearance changes from other devices.'**
  String get syncPreferenceLocalAppearanceSubtitle;

  /// Toggle title in Prism Sync preferences for sharing navigation layout
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get syncPreferenceNavigationTitle;

  /// Toggle subtitle in Prism Sync preferences for sharing navigation layout
  ///
  /// In en, this message translates to:
  /// **'Share tab order across devices.'**
  String get syncPreferenceNavigationSubtitle;

  /// Toggle title: sync navigation layout
  ///
  /// In en, this message translates to:
  /// **'Sync navigation layout'**
  String get syncNavigationLayoutTitle;

  /// Toggle subtitle: sync navigation layout
  ///
  /// In en, this message translates to:
  /// **'Share tab arrangement across devices'**
  String get syncNavigationLayoutSubtitle;

  /// Toggle title: sync appearance across devices
  ///
  /// In en, this message translates to:
  /// **'Sync appearance across devices'**
  String get syncAppearanceToggleTitle;

  /// Toggle subtitle: sync appearance across devices
  ///
  /// In en, this message translates to:
  /// **'Share theme, accent color, and corner style between your paired devices.'**
  String get syncAppearanceToggleDescription;

  /// Toggle title: ignore synced appearance on this device
  ///
  /// In en, this message translates to:
  /// **'Ignore synced appearance on this device'**
  String get syncIgnoreAppearanceTitle;

  /// Toggle subtitle: ignore synced appearance on this device
  ///
  /// In en, this message translates to:
  /// **'Use local appearance settings on this device. Edits made here still sync to other devices if sharing is on.'**
  String get syncIgnoreAppearanceDescription;

  /// Navigation settings: toggle to show/hide the timeline/list view toggle button in the Home top bar
  ///
  /// In en, this message translates to:
  /// **'Show view toggle in Home'**
  String get navigationShowViewToggleTitle;

  /// Navigation settings: subtitle for the view toggle preference
  ///
  /// In en, this message translates to:
  /// **'Display the timeline / list toggle button in the Home tab top bar.'**
  String get navigationShowViewToggleSubtitle;

  /// Section title for quarantined sync issues
  ///
  /// In en, this message translates to:
  /// **'Sync Issues'**
  String get syncIssuesSection;

  /// Description for sync issues section
  ///
  /// In en, this message translates to:
  /// **'These records could not be applied due to data type mismatches. Clearing them removes the warning indicator.'**
  String get syncIssuesDescription;

  /// Button to clear all quarantined sync items
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get syncClearAll;

  /// Section title for sync connection details
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get syncDetailsSection;

  /// Label for the relay URL detail row
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get syncRelayLabel;

  /// Label for the sync ID detail row
  ///
  /// In en, this message translates to:
  /// **'Sync ID'**
  String get syncIdLabel;

  /// Label for the node ID detail row
  ///
  /// In en, this message translates to:
  /// **'Node ID'**
  String get syncNodeIdLabel;

  /// Value for node ID when not yet initialised
  ///
  /// In en, this message translates to:
  /// **'Not initialised'**
  String get syncNodeIdNotInitialised;

  /// Settings row title: troubleshooting link
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get syncTroubleshootingLink;

  /// Label for synced last 24h count
  ///
  /// In en, this message translates to:
  /// **'Last 24h'**
  String get syncLast24h;

  /// Label for total synced count
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get syncTotal;

  /// Number of synced entities
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entity} other{{count} entities}}'**
  String syncEntitiesCount(int count);

  /// Toast message after a successful manual sync
  ///
  /// In en, this message translates to:
  /// **'Sync finished'**
  String get syncFinished;

  /// Toast message when sync fails
  ///
  /// In en, this message translates to:
  /// **'Prism sync failed: {error}'**
  String syncFailed(Object error);

  /// Settings sync summary section title
  ///
  /// In en, this message translates to:
  /// **'Prism Sync'**
  String get syncSummarySectionTitle;

  /// Settings sync device-management section title
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get syncDevicesSectionTitle;

  /// Settings sync security and recovery-actions section title
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get syncSecuritySectionTitle;

  /// Sync summary headline: connected state
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get syncSummaryConnected;

  /// Sync summary headline: reconnecting state
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get syncSummaryReconnecting;

  /// Sync summary headline: warning or error state
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get syncSummaryNeedsAttention;

  /// Sync summary headline: offline state
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncSummaryOffline;

  /// Sync summary activity chip: idle connected state
  ///
  /// In en, this message translates to:
  /// **'Checking for changes...'**
  String get syncSummaryActivityChecking;

  /// Sync summary activity chip: active sync state
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncSummaryActivitySyncing;

  /// Sync summary activity chip: reconnecting state
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get syncSummaryActivityReconnecting;

  /// Sync summary activity chip: sync database repair needed
  ///
  /// In en, this message translates to:
  /// **'Needs repair'**
  String get syncSummaryNeedsRepair;

  /// Sync summary activity chip: local changes waiting to upload
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pending upload} other{{count} pending uploads}}'**
  String syncSummaryPendingUploads(int count);

  /// Sync summary chip: last successful sync was moments ago
  ///
  /// In en, this message translates to:
  /// **'Synced just now'**
  String get syncSummarySyncedJustNow;

  /// Sync summary chip: last successful sync time
  ///
  /// In en, this message translates to:
  /// **'Synced {timeAgo}'**
  String syncSummarySyncedAt(String timeAgo);

  /// Sync summary chip: no successful sync yet
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get syncSummaryNeverSynced;

  /// Sync status card: error state title
  ///
  /// In en, this message translates to:
  /// **'Prism sync error'**
  String get syncStatusError;

  /// Sync status card: syncing state title
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncStatusSyncing;

  /// Sync status card: syncing detail
  ///
  /// In en, this message translates to:
  /// **'Sync in progress…'**
  String get syncStatusSyncInProgress;

  /// Sync status card: synced with quarantine issues
  ///
  /// In en, this message translates to:
  /// **'Synced with issues'**
  String get syncStatusSyncedWithIssues;

  /// Sync status card: last synced title
  ///
  /// In en, this message translates to:
  /// **'Last synced'**
  String get syncStatusLastSynced;

  /// Sync status card: ready state title
  ///
  /// In en, this message translates to:
  /// **'Ready to sync'**
  String get syncStatusReadyToSync;

  /// Sync status card: waiting detail
  ///
  /// In en, this message translates to:
  /// **'Waiting for changes.'**
  String get syncStatusWaiting;

  /// Sync status card: needs reconnect title
  ///
  /// In en, this message translates to:
  /// **'Needs reconnect'**
  String get syncStatusNeedsReconnect;

  /// Sync status card: tap to reconnect detail
  ///
  /// In en, this message translates to:
  /// **'Tap Sync Now to reconnect.'**
  String get syncStatusTapToReconnect;

  /// Real-time WebSocket connected label
  ///
  /// In en, this message translates to:
  /// **'Real-time connected'**
  String get syncRealTimeConnected;

  /// Real-time WebSocket disconnected label
  ///
  /// In en, this message translates to:
  /// **'Real-time disconnected'**
  String get syncRealTimeDisconnected;

  /// Time ago: just now
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get syncJustNow;

  /// Time ago in minutes
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String syncMinutesAgo(int count);

  /// Time ago in hours
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String syncHoursAgo(int count);

  /// Time ago in days
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String syncDaysAgo(int count);

  /// Sync setup screen title: intro step
  ///
  /// In en, this message translates to:
  /// **'Set Up Sync'**
  String get syncSetupIntroTitle;

  /// Sync setup screen title: secret key step
  ///
  /// In en, this message translates to:
  /// **'Your Secret Key'**
  String get syncSetupSecretKeyTitle;

  /// Sync setup intro headline
  ///
  /// In en, this message translates to:
  /// **'Keep your data in sync across all your devices.'**
  String get syncSetupIntroHeadline;

  /// Sync setup intro body text
  ///
  /// In en, this message translates to:
  /// **'Everything is end-to-end encrypted — the server never sees your data. You\'ll create a password and receive a recovery key to keep safe. You\'ll need your 12-word recovery phrase to continue. Have it ready.'**
  String get syncSetupIntroBody;

  /// Toggle label for showing self-hosted relay fields
  ///
  /// In en, this message translates to:
  /// **'Self-hosted relay?'**
  String get syncSetupSelfHosted;

  /// Label for relay URL text field
  ///
  /// In en, this message translates to:
  /// **'Relay URL'**
  String get syncSetupRelayUrlLabel;

  /// Label for registration token field
  ///
  /// In en, this message translates to:
  /// **'Registration token'**
  String get syncSetupRegistrationToken;

  /// Hint text for registration token field
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get syncSetupRegistrationTokenHint;

  /// Help text for registration token field
  ///
  /// In en, this message translates to:
  /// **'Required if your relay has registration gating enabled.'**
  String get syncSetupRegistrationTokenHelp;

  /// Validation error for relay URL field
  ///
  /// In en, this message translates to:
  /// **'Relay URL must start with https://'**
  String get syncSetupRelayUrlError;

  /// Complete button on sync setup secret key step
  ///
  /// In en, this message translates to:
  /// **'Complete setup'**
  String get syncSetupCompleteButton;

  /// Label for the PIN field on the sync setup secret key step
  ///
  /// In en, this message translates to:
  /// **'App PIN'**
  String get syncSetupPinLabel;

  /// Sync setup progress: creating group
  ///
  /// In en, this message translates to:
  /// **'Creating sync group...'**
  String get syncSetupProgressCreatingGroup;

  /// Sync setup progress: configuring engine
  ///
  /// In en, this message translates to:
  /// **'Configuring encryption...'**
  String get syncSetupProgressConfiguringEngine;

  /// Sync setup progress: caching keys
  ///
  /// In en, this message translates to:
  /// **'Securing keys...'**
  String get syncSetupProgressCachingKeys;

  /// Sync setup progress: preparing local data for sync (offline)
  ///
  /// In en, this message translates to:
  /// **'Preparing your data for sync'**
  String get syncSetupProgressBootstrapping;

  /// Sync setup progress: measuring local snapshot size (offline)
  ///
  /// In en, this message translates to:
  /// **'Checking data size'**
  String get syncSetupProgressMeasuringSnapshot;

  /// Sheet title when secret key is revealed
  ///
  /// In en, this message translates to:
  /// **'Secret Key'**
  String get syncSecretKeyTitle;

  /// Sheet title explaining that the recovery phrase is not stored on the device
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase not stored'**
  String get syncSecretKeyNotStoredTitle;

  /// Body text on the 'recovery phrase not stored' informational sheet
  ///
  /// In en, this message translates to:
  /// **'Your recovery phrase is not stored on this device — it was shown once during setup.\n\nIf you saved it (for example, in a password manager or on a piece of paper), check there.\n\nIf you can\'t find it, disconnect this device and re-pair to generate a new phrase.'**
  String get syncSecretKeyNotStoredBody;

  /// Sheet title when verifying PIN to reveal key
  ///
  /// In en, this message translates to:
  /// **'Verify PIN'**
  String get syncVerifyPasswordTitle;

  /// Prompt text in verify PIN sheet
  ///
  /// In en, this message translates to:
  /// **'Enter your app PIN to reveal your 12-word recovery phrase.'**
  String get syncVerifyPasswordPrompt;

  /// Hint text for sync PIN field
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get syncPasswordHint;

  /// Button to reveal the secret key
  ///
  /// In en, this message translates to:
  /// **'Reveal Secret Key'**
  String get syncRevealSecretKey;

  /// Error when secret key is missing from keychain
  ///
  /// In en, this message translates to:
  /// **'Secret Key not found in keychain.'**
  String get syncSecretKeyNotFound;

  /// Error when sync engine handle is null
  ///
  /// In en, this message translates to:
  /// **'Sync isn\'t ready yet. Wait a moment and try again.'**
  String get syncEngineNotAvailable;

  /// Error when persistent sync identity is incomplete (device id or device secret missing) and the user tries to pair another device
  ///
  /// In en, this message translates to:
  /// **'Sync setup didn\'t finish on this device. Set up sync again to add more devices.'**
  String get syncEnginePartialIdentity;

  /// Error when wrapped DEK is missing and the user must re-confirm their PIN before pairing another device
  ///
  /// In en, this message translates to:
  /// **'Re-enter your PIN to restore your pairing key, then try again.'**
  String get syncEngineNeedsPinReconfirm;

  /// Error when PIN verification fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN. Please try again.'**
  String get syncIncorrectPassword;

  /// Generic error message in secret key reveal
  ///
  /// In en, this message translates to:
  /// **'An error occurred: {error}'**
  String syncAnErrorOccurred(Object error);

  /// Privacy & Security settings screen title
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get privacySecurityTitle;

  /// Screen privacy section title in Privacy & Security settings
  ///
  /// In en, this message translates to:
  /// **'Screen Privacy'**
  String get screenPrivacySection;

  /// Title for the toggle that blocks screenshots and hides the app from the OS app switcher
  ///
  /// In en, this message translates to:
  /// **'Hide app contents'**
  String get screenPrivacyToggleTitle;

  /// Subtitle for the screen privacy toggle, Android wording
  ///
  /// In en, this message translates to:
  /// **'Block screenshots and hide Prism from the app switcher.'**
  String get screenPrivacyToggleSubtitleAndroid;

  /// Subtitle for the screen privacy toggle, iOS wording — notes that iOS cannot block manual screenshots
  ///
  /// In en, this message translates to:
  /// **'Hide Prism from the app switcher and screen recordings. iOS can\'t block manual screenshots.'**
  String get screenPrivacyToggleSubtitleIos;

  /// PIN lock section title
  ///
  /// In en, this message translates to:
  /// **'PIN Lock'**
  String get pinLockSection;

  /// PIN lock toggle title
  ///
  /// In en, this message translates to:
  /// **'Enable PIN Lock'**
  String get pinLockEnableTitle;

  /// PIN lock toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Require a PIN to open the app'**
  String get pinLockEnableSubtitle;

  /// Biometric section title in PIN lock settings
  ///
  /// In en, this message translates to:
  /// **'Biometric'**
  String get pinLockBiometricSection;

  /// Biometric unlock toggle title
  ///
  /// In en, this message translates to:
  /// **'Biometric Unlock'**
  String get pinLockBiometricTitle;

  /// Biometric unlock subtitle when PIN is set
  ///
  /// In en, this message translates to:
  /// **'Use Face ID or fingerprint to unlock'**
  String get pinLockBiometricSubtitle;

  /// Biometric unlock subtitle when PIN is not set
  ///
  /// In en, this message translates to:
  /// **'Enable PIN Lock to use biometric unlock'**
  String get pinLockBiometricDisabledSubtitle;

  /// Unlock options section title in PIN lock settings
  ///
  /// In en, this message translates to:
  /// **'Unlock Options'**
  String get pinLockUnlockOptionsSection;

  /// Title for optional hard sync lock toggle
  ///
  /// In en, this message translates to:
  /// **'Require recovery for sync'**
  String get pinLockHardSyncLockTitle;

  /// Subtitle for optional hard sync lock toggle when PIN lock is set
  ///
  /// In en, this message translates to:
  /// **'When the app locks, forget the sync quick-unlock key. Background sync pauses until you enter your PIN and recovery phrase.'**
  String get pinLockHardSyncLockSubtitle;

  /// Subtitle for optional hard sync lock toggle when PIN lock is not set
  ///
  /// In en, this message translates to:
  /// **'Enable PIN Lock to require recovery after app lock.'**
  String get pinLockHardSyncLockDisabledSubtitle;

  /// Auto-lock section title
  ///
  /// In en, this message translates to:
  /// **'Auto-Lock'**
  String get pinLockAutoLockSection;

  /// Auto-lock delay label
  ///
  /// In en, this message translates to:
  /// **'Lock after leaving the app'**
  String get pinLockAfterLeaving;

  /// Manage PIN section title
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get pinLockManageSection;

  /// Change PIN row label
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get pinLockChange;

  /// Remove PIN row label
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get pinLockRemove;

  /// Title for set PIN screen
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get pinLockSetTitle;

  /// Title for confirm PIN screen
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get pinLockConfirmTitle;

  /// Title for unlock PIN screen
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get pinLockEnterTitle;

  /// Subtitle for set PIN screen
  ///
  /// In en, this message translates to:
  /// **'Choose a 6-digit PIN'**
  String get pinLockSetSubtitle;

  /// Subtitle for confirm PIN screen
  ///
  /// In en, this message translates to:
  /// **'Re-enter your PIN to confirm'**
  String get pinLockConfirmSubtitle;

  /// Subtitle for unlock PIN screen
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to unlock'**
  String get pinLockUnlockSubtitle;

  /// Auto-lock delay: Instant
  ///
  /// In en, this message translates to:
  /// **'Instant'**
  String get pinLockInstant;

  /// Auto-lock delay: 15 seconds
  ///
  /// In en, this message translates to:
  /// **'15s'**
  String get pinLock15s;

  /// Auto-lock delay: 1 minute
  ///
  /// In en, this message translates to:
  /// **'1m'**
  String get pinLock1m;

  /// Auto-lock delay: 5 minutes
  ///
  /// In en, this message translates to:
  /// **'5m'**
  String get pinLock5m;

  /// Auto-lock delay: 15 minutes
  ///
  /// In en, this message translates to:
  /// **'15m'**
  String get pinLock15m;

  /// Notifications settings screen title
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// Fronting reminders toggle title
  ///
  /// In en, this message translates to:
  /// **'Fronting reminders'**
  String get notificationsFrontingRemindersTitle;

  /// Fronting reminders toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Get reminded to log fronting changes'**
  String get notificationsFrontingRemindersSubtitle;

  /// Reminder interval row title
  ///
  /// In en, this message translates to:
  /// **'Reminder interval'**
  String get notificationsReminderIntervalTitle;

  /// Reminder interval row subtitle
  ///
  /// In en, this message translates to:
  /// **'How often to send reminders'**
  String get notificationsReminderIntervalSubtitle;

  /// Title for the row that lets the user set how long to skip the fronting reminder after a recent front log
  ///
  /// In en, this message translates to:
  /// **'Skip if logged recently'**
  String get notificationsSuppressIfRecentTitle;

  /// Subtitle explaining the suppress-after-recent-log behavior
  ///
  /// In en, this message translates to:
  /// **'Don\'t remind if you logged a front recently'**
  String get notificationsSuppressIfRecentSubtitle;

  /// Option label meaning the suppress-window is disabled
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get notificationsSuppressOff;

  /// Label for a suppress-window value in minutes
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute} other{{minutes} minutes}}'**
  String notificationsSuppressMinutes(int minutes);

  /// Label shown when the suppress window is a non-preset value
  ///
  /// In en, this message translates to:
  /// **'Custom ({minutes} min)'**
  String notificationsSuppressCustomLabel(int minutes);

  /// Menu option that opens a dialog to enter a custom suppress-window value
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get notificationsSuppressCustomOption;

  /// Title of the dialog that lets the user enter a custom suppress window
  ///
  /// In en, this message translates to:
  /// **'Skip reminder for'**
  String get notificationsSuppressCustomDialogTitle;

  /// Helper text under the input describing the allowed range
  ///
  /// In en, this message translates to:
  /// **'Between 1 and 60 minutes'**
  String get notificationsSuppressCustomDialogHelper;

  /// Suffix shown next to the custom-value input field
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get notificationsSuppressCustomSuffix;

  /// Chat notifications section title
  ///
  /// In en, this message translates to:
  /// **'Chat Notifications'**
  String get notificationsChatSection;

  /// Chat badge toggle title
  ///
  /// In en, this message translates to:
  /// **'Badge for all messages'**
  String get notificationsBadgeAllMessages;

  /// Chat badge subtitle when mentions-only mode is active
  ///
  /// In en, this message translates to:
  /// **'Only @mentions will badge for {member}'**
  String notificationsBadgeMentionsOnly(String member);

  /// Chat badge subtitle when all-messages mode is active
  ///
  /// In en, this message translates to:
  /// **'All new messages will badge for {member}'**
  String notificationsBadgeAllFor(String member);

  /// Notification permission status row title (loading)
  ///
  /// In en, this message translates to:
  /// **'Permission status'**
  String get notificationsPermissionStatus;

  /// Notification permission error message
  ///
  /// In en, this message translates to:
  /// **'Could not check permissions'**
  String get notificationsCouldNotCheck;

  /// Notification permission granted title
  ///
  /// In en, this message translates to:
  /// **'Notifications enabled'**
  String get notificationsEnabled;

  /// Notification permission granted subtitle
  ///
  /// In en, this message translates to:
  /// **'Permission granted'**
  String get notificationsPermissionGranted;

  /// Notification permission not granted title
  ///
  /// In en, this message translates to:
  /// **'Notifications not enabled'**
  String get notificationsNotEnabled;

  /// Notification permission not granted subtitle
  ///
  /// In en, this message translates to:
  /// **'Permission required for reminders'**
  String get notificationsPermissionRequired;

  /// Button to request notification permission
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get notificationsRequest;

  /// About text at the bottom of notification settings
  ///
  /// In en, this message translates to:
  /// **'Fronting reminders send periodic notifications to help you stay aware of who is fronting. This can be useful for logging switches and maintaining awareness throughout the day.'**
  String get notificationsAboutText;

  /// Android-only footnote below notification settings about text
  ///
  /// In en, this message translates to:
  /// **'On Android, reminders may arrive a few minutes late.'**
  String get notificationsAndroidFootnote;

  /// Reminder interval: 15 minutes
  ///
  /// In en, this message translates to:
  /// **'15 minutes'**
  String get notificationsInterval15m;

  /// Reminder interval: 30 minutes
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get notificationsInterval30m;

  /// Reminder interval: 1 hour
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get notificationsInterval1h;

  /// Reminder interval: 2 hours
  ///
  /// In en, this message translates to:
  /// **'2 hours'**
  String get notificationsInterval2h;

  /// Reminder interval: 4 hours
  ///
  /// In en, this message translates to:
  /// **'4 hours'**
  String get notificationsInterval4h;

  /// Reminder interval: 8 hours
  ///
  /// In en, this message translates to:
  /// **'8 hours'**
  String get notificationsInterval8h;

  /// Reset Data settings screen title
  ///
  /// In en, this message translates to:
  /// **'Reset Data'**
  String get resetDataTitle;

  /// Reset data: Categories section title
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get resetDataCategoriesSection;

  /// Reset data: Categories section description
  ///
  /// In en, this message translates to:
  /// **'Reset specific categories of data on this device. Sync System reset wipes sync setup without deleting your app data.'**
  String get resetDataCategoriesDescription;

  /// Reset data: Danger Zone section title
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get resetDataDangerZone;

  /// Confirmation dialog title for resetting a data category
  ///
  /// In en, this message translates to:
  /// **'Reset {category}?'**
  String resetDataConfirmTitle(String category);

  /// Confirmation message when resetting all data
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all your data including {termPluralLower}, fronting sessions, messages, polls, habits, sleep data, and settings. This action cannot be undone.'**
  String resetDataConfirmAll(String termPluralLower);

  /// Confirmation message when resetting sync
  ///
  /// In en, this message translates to:
  /// **'This keeps your local app data, but removes sync keys, relay configuration, device identity, and sync history from this device. You will need to set up sync again afterward.'**
  String get resetDataConfirmSync;

  /// Confirmation message when resetting a specific category
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all {category} data on this device. This action cannot be undone.'**
  String resetDataConfirmCategory(String category);

  /// Confirm button label when resetting all data
  ///
  /// In en, this message translates to:
  /// **'Reset Everything'**
  String get resetDataConfirmEverything;

  /// Confirm button label when resetting sync
  ///
  /// In en, this message translates to:
  /// **'Reset Sync'**
  String get resetDataConfirmSync2;

  /// Toast message after successful data reset
  ///
  /// In en, this message translates to:
  /// **'{category} reset successfully'**
  String resetDataSuccess(String category);

  /// Toast message when data reset fails
  ///
  /// In en, this message translates to:
  /// **'Failed to reset: {error}'**
  String resetDataFailed(Object error);

  /// Label for the Custom Fields reset row on the Reset Data screen.
  ///
  /// In en, this message translates to:
  /// **'Custom Fields'**
  String get resetDataCategoryCustomFieldsLabel;

  /// Subtitle for the Custom Fields reset row on the Reset Data screen.
  ///
  /// In en, this message translates to:
  /// **'Deletes all custom fields and their values.'**
  String get resetDataCategoryCustomFieldsDescription;

  /// Title for the Custom Fields reset confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Reset Custom Fields?'**
  String get resetDataConfirmCustomFieldsTitle;

  /// Body text explaining the cascading scope of the Custom Fields reset.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all custom field definitions and the values your members have for them. This action cannot be undone.'**
  String get resetDataConfirmCustomFieldsBody;

  /// Navigation settings screen title
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigationSettingsTitle;

  /// Navigation settings: section title above the sync / view-toggle switches
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get navigationPreferences;

  /// Navigation settings: when nav bar labels appear, setting title
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get navigationLabelVisibilityTitle;

  /// Navigation settings: label visibility setting subtitle
  ///
  /// In en, this message translates to:
  /// **'Choose when item labels appear in the mobile nav bar.'**
  String get navigationLabelVisibilitySubtitle;

  /// Navigation settings: labels always visible segment
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get navigationLabelVisibilityAlways;

  /// Navigation settings: labels visible only when the More menu is opened segment
  ///
  /// In en, this message translates to:
  /// **'When opened'**
  String get navigationLabelVisibilityWhenExpanded;

  /// Navigation settings: icons only, labels never shown segment
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get navigationLabelVisibilityNever;

  /// Navigation settings: label text style setting title
  ///
  /// In en, this message translates to:
  /// **'Label text'**
  String get navigationLabelStyleTitle;

  /// Navigation settings: label text style setting subtitle
  ///
  /// In en, this message translates to:
  /// **'Show the full label or trim it to fit.'**
  String get navigationLabelStyleSubtitle;

  /// Navigation settings: full label text segment
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get navigationLabelStyleFull;

  /// Navigation settings: truncated label text segment
  ///
  /// In en, this message translates to:
  /// **'Truncated'**
  String get navigationLabelStyleTruncated;

  /// Navigation settings: section title above the preview and reorderable items list
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get navigationLayoutSection;

  /// Navigation settings: Nav Bar section label
  ///
  /// In en, this message translates to:
  /// **'Nav Bar'**
  String get navigationNavBar;

  /// Navigation settings: More Menu section label
  ///
  /// In en, this message translates to:
  /// **'More Menu'**
  String get navigationMoreMenu;

  /// Navigation settings: Available section title
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get navigationAvailable;

  /// Navigation settings: Disabled Features section title
  ///
  /// In en, this message translates to:
  /// **'Disabled Features'**
  String get navigationDisabledFeatures;

  /// Navigation item disabled, tap to open Features settings
  ///
  /// In en, this message translates to:
  /// **'Enable in Features'**
  String get navigationEnableInFeatures;

  /// Tooltip: move item to nav bar
  ///
  /// In en, this message translates to:
  /// **'Move to nav bar'**
  String get navigationMoveToNavBar;

  /// Tooltip: move item to More menu
  ///
  /// In en, this message translates to:
  /// **'Move to More menu'**
  String get navigationMoveToMoreMenu;

  /// Tooltip: remove item from navigation
  ///
  /// In en, this message translates to:
  /// **'Remove from navigation'**
  String get navigationRemove;

  /// Tooltip: add item to nav bar
  ///
  /// In en, this message translates to:
  /// **'Add to nav bar'**
  String get navigationAddToNavBar;

  /// Tooltip: add item to More menu
  ///
  /// In en, this message translates to:
  /// **'Add to More menu'**
  String get navigationAddToMoreMenu;

  /// Features settings screen title
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get featuresTitle;

  /// Hint text at the bottom of features settings
  ///
  /// In en, this message translates to:
  /// **'Disabling a feature hides it from navigation without deleting any data.'**
  String get featuresDisablingHint;

  /// Semantics label for an enabled feature
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get featuresEnabled;

  /// Semantics label for a disabled feature
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get featuresDisabled;

  /// Feature name: Chat
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get featureChatTitle;

  /// Feature name: Fronting
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get featureFrontingTitle;

  /// Feature name: Habits
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get featureHabitsTitle;

  /// Feature name: Sleep
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get featureSleepTitle;

  /// Feature name: Polls
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get featurePollsTitle;

  /// Feature name: Notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get featureNotesTitle;

  /// Feature name: Reminders
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get featureRemindersTitle;

  /// Statistics screen title
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsTitle;

  /// Statistics: Overview section title
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get statisticsOverview;

  /// Statistics row: total members
  ///
  /// In en, this message translates to:
  /// **'Total {termPlural}'**
  String statisticsTotalMembers(String termPlural);

  /// Statistics row: total sessions
  ///
  /// In en, this message translates to:
  /// **'Total sessions'**
  String get statisticsTotalSessions;

  /// Statistics row: conversations
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get statisticsConversations;

  /// Statistics row: polls
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get statisticsPolls;

  /// Statistics section: most frequent fronters
  ///
  /// In en, this message translates to:
  /// **'Most Frequent Fronters'**
  String get statisticsMostFrequentFronters;

  /// Statistics section: average session duration
  ///
  /// In en, this message translates to:
  /// **'Average Session Duration'**
  String get statisticsAverageSessionDuration;

  /// Empty state for most frequent fronters
  ///
  /// In en, this message translates to:
  /// **'No fronting data yet'**
  String get statisticsNoFrontingData;

  /// Empty state for average session duration
  ///
  /// In en, this message translates to:
  /// **'No completed sessions yet'**
  String get statisticsNoCompletedSessions;

  /// Number of sessions in statistics fronter row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String statisticsSessions(int count);

  /// Title for the duration stats card
  ///
  /// In en, this message translates to:
  /// **'Duration Stats'**
  String get statisticsDurationStats;

  /// Label for session count in the duration stats card
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get statisticsDurationSessions;

  /// Label for total duration in the duration stats card
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get statisticsDurationTotal;

  /// Label for average duration in the duration stats card
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get statisticsDurationAverage;

  /// Label for median duration in the duration stats card
  ///
  /// In en, this message translates to:
  /// **'Median'**
  String get statisticsDurationMedian;

  /// Label for shortest session in the duration stats card
  ///
  /// In en, this message translates to:
  /// **'Shortest'**
  String get statisticsDurationShortest;

  /// Label for longest session in the duration stats card
  ///
  /// In en, this message translates to:
  /// **'Longest'**
  String get statisticsDurationLongest;

  /// Title for the per-member ranking chart. {term}-minutes (e.g., 'member-minutes', 'headmate-minutes'): when two co-front for an hour, that's two {term}-hours — same math as wall-clock-per-fronter, more honest framing. Mirrors the existing 'Per-{term} Colors' convention in appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Per-{term} minutes'**
  String statisticsFrontingTimeByMember(String term);

  /// Subtitle / accessibility hint clarifying that percentages are share of total {term}-minutes, not wall-clock fronting time.
  ///
  /// In en, this message translates to:
  /// **'% of total {term}-minutes'**
  String statisticsMemberMinutesAxisHint(String term);

  /// Statistics overview stat label: median session duration
  ///
  /// In en, this message translates to:
  /// **'Median Session'**
  String get statisticsMedianSessionLabel;

  /// Statistics overview stat label: total gap time between fronting sessions
  ///
  /// In en, this message translates to:
  /// **'Gap Time'**
  String get statisticsGapTimeLabel;

  /// Statistics overview stat label: average number of fronting switches per day
  ///
  /// In en, this message translates to:
  /// **'Switches/Day'**
  String get statisticsSwitchesPerDayLabel;

  /// Statistics overview stat label: count of unique fronters in the period. Uses the user's terminology for members.
  ///
  /// In en, this message translates to:
  /// **'Unique {termPlural}'**
  String statisticsUniqueFrontersLabel(String termPlural);

  /// Active/inactive member count breakdown in statistics
  ///
  /// In en, this message translates to:
  /// **'{active} active, {inactive} inactive'**
  String statisticsActiveMembersBreakdown(int active, int inactive);

  /// Time-of-day bucket label for 6am to 12pm
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get timeOfDayMorning;

  /// Time-of-day bucket label for 12pm to 6pm
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get timeOfDayAfternoon;

  /// Time-of-day bucket label for 6pm to 12am
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get timeOfDayEvening;

  /// Time-of-day bucket label for 12am to 6am
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get timeOfDayNight;

  /// Semantics fallback when the time-of-day chart has no data
  ///
  /// In en, this message translates to:
  /// **'No time-of-day data'**
  String get timeOfDayChartNoData;

  /// Semantics summary for the time-of-day chart
  ///
  /// In en, this message translates to:
  /// **'Time of day: {parts}'**
  String timeOfDayChartSemantics(String parts);

  /// Debug screen title
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get debugTitle;

  /// Debug: Danger Zone section title
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get debugDangerZone;

  /// Debug: Reset Database button
  ///
  /// In en, this message translates to:
  /// **'Reset Database'**
  String get debugResetDatabase;

  /// Debug: Export Data button
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get debugExportData;

  /// Toast for unimplemented debug actions
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get debugComingSoon;

  /// Debug: Stress Testing section title
  ///
  /// In en, this message translates to:
  /// **'Stress Testing'**
  String get debugStressTestingTitle;

  /// Debug: Stress Testing section description
  ///
  /// In en, this message translates to:
  /// **'Generate large datasets for performance testing'**
  String get debugStressTestingDescription;

  /// Debug: Generate Stress Data button
  ///
  /// In en, this message translates to:
  /// **'Generate Stress Data'**
  String get debugGenerateStressData;

  /// Debug: label while clearing stress data
  ///
  /// In en, this message translates to:
  /// **'Clearing...'**
  String get debugClearingStressData;

  /// Debug: Clear Stress Data button
  ///
  /// In en, this message translates to:
  /// **'Clear Stress Data'**
  String get debugClearStressData;

  /// Debug: Sync State section title
  ///
  /// In en, this message translates to:
  /// **'Sync State'**
  String get debugSyncState;

  /// Debug row: pending changes label
  ///
  /// In en, this message translates to:
  /// **'Pending changes'**
  String get debugPendingChanges;

  /// Debug row: last sync label
  ///
  /// In en, this message translates to:
  /// **'Last sync'**
  String get debugLastSync;

  /// Debug: last sync value when never synced
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get debugNeverSynced;

  /// Debug: button to open sync debug log
  ///
  /// In en, this message translates to:
  /// **'Open Sync Debug Log'**
  String get debugOpenSyncLog;

  /// Debug: Build Info section title
  ///
  /// In en, this message translates to:
  /// **'Build Info'**
  String get debugBuildInfo;

  /// Tooltip: copy build info to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy build info'**
  String get debugCopyBuildInfo;

  /// Toast after copying build info
  ///
  /// In en, this message translates to:
  /// **'Build info copied'**
  String get debugBuildInfoCopied;

  /// Debug row: app version label
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get debugAppVersion;

  /// Debug row: git label
  ///
  /// In en, this message translates to:
  /// **'Git'**
  String get debugGit;

  /// Debug row: branch label
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get debugBranch;

  /// Debug row: built label
  ///
  /// In en, this message translates to:
  /// **'Built'**
  String get debugBuilt;

  /// Debug row: package label
  ///
  /// In en, this message translates to:
  /// **'Package'**
  String get debugPackage;

  /// Debug: Tools section title
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get debugTools;

  /// Debug: Device section title
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get debugDevice;

  /// Debug row: node ID label
  ///
  /// In en, this message translates to:
  /// **'Node ID'**
  String get debugNodeId;

  /// Debug: node ID when not yet paired
  ///
  /// In en, this message translates to:
  /// **'Unavailable — not yet paired'**
  String get debugNodeIdUnavailable;

  /// Tooltip: copy node ID to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy Node ID'**
  String get debugCopyNodeId;

  /// Toast after copying node ID
  ///
  /// In en, this message translates to:
  /// **'Node ID copied to clipboard'**
  String get debugNodeIdCopied;

  /// First confirmation title for DB reset
  ///
  /// In en, this message translates to:
  /// **'Reset Database'**
  String get debugResetDatabaseConfirm1Title;

  /// First confirmation message for DB reset
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all data? This action cannot be undone.'**
  String get debugResetDatabaseConfirm1Message;

  /// Second confirmation title for DB reset
  ///
  /// In en, this message translates to:
  /// **'Really delete all data?'**
  String get debugResetDatabaseConfirm2Title;

  /// Second confirmation message for DB reset
  ///
  /// In en, this message translates to:
  /// **'This will permanently erase all {termPluralLower}, sessions, conversations, messages, and polls. There is no undo.'**
  String debugResetDatabaseConfirm2Message(String termPluralLower);

  /// Second confirmation: delete everything button
  ///
  /// In en, this message translates to:
  /// **'Delete Everything'**
  String get debugDeleteEverything;

  /// Toast after database reset
  ///
  /// In en, this message translates to:
  /// **'Database reset successfully'**
  String get debugDatabaseResetSuccess;

  /// Toast when database reset fails
  ///
  /// In en, this message translates to:
  /// **'Failed to reset: {error}'**
  String debugFailedToReset(Object error);

  /// Title of the stress test preset picker
  ///
  /// In en, this message translates to:
  /// **'Select Preset'**
  String get debugSelectPreset;

  /// Title when database already has data
  ///
  /// In en, this message translates to:
  /// **'Database Not Empty'**
  String get debugDatabaseNotEmpty;

  /// Message when database already has data
  ///
  /// In en, this message translates to:
  /// **'Your database already has data. Stress data will be added alongside it. Continue?'**
  String get debugDatabaseNotEmptyMessage;

  /// Toast when no stress data exists
  ///
  /// In en, this message translates to:
  /// **'No stress data to clear'**
  String get debugNoStressData;

  /// Confirmation title for clearing stress data
  ///
  /// In en, this message translates to:
  /// **'Clear Stress Data'**
  String get debugClearStressDataTitle;

  /// Confirmation message for clearing stress data
  ///
  /// In en, this message translates to:
  /// **'This will delete all generated stress test data. Your real data will not be affected.'**
  String get debugClearStressDataMessage;

  /// Toast after stress data is cleared
  ///
  /// In en, this message translates to:
  /// **'Stress data cleared'**
  String get debugStressDataCleared;

  /// Toast when clearing stress data fails
  ///
  /// In en, this message translates to:
  /// **'Failed to clear stress data: {error}'**
  String debugFailedToClearStress(Object error);

  /// Toast after stress data is generated
  ///
  /// In en, this message translates to:
  /// **'{preset} stress data generated'**
  String debugStressGenerated(String preset);

  /// Toast when stress data generation fails
  ///
  /// In en, this message translates to:
  /// **'Generation failed: {error}'**
  String debugGenerationFailed(Object error);

  /// Error history screen title
  ///
  /// In en, this message translates to:
  /// **'Error History'**
  String get errorHistoryTitle;

  /// Tooltip for clear history button
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get errorHistoryClear;

  /// Empty state title in error history
  ///
  /// In en, this message translates to:
  /// **'No errors recorded'**
  String get errorHistoryEmpty;

  /// Empty state subtitle in error history
  ///
  /// In en, this message translates to:
  /// **'Errors will appear here when they occur'**
  String get errorHistoryEmptySubtitle;

  /// Tooltip for copy error button
  ///
  /// In en, this message translates to:
  /// **'Copy error details'**
  String get errorHistoryCopyTooltip;

  /// Toast after copying error details
  ///
  /// In en, this message translates to:
  /// **'Error details copied'**
  String get errorHistoryCopied;

  /// System Information screen title
  ///
  /// In en, this message translates to:
  /// **'{systemTerm} Information'**
  String systemInfoTitle(String systemTerm);

  /// Avatar action: change avatar
  ///
  /// In en, this message translates to:
  /// **'Change avatar'**
  String get systemInfoChangeAvatar;

  /// Semantic label for the member avatar change button
  ///
  /// In en, this message translates to:
  /// **'Change {termSingularLower} avatar'**
  String memberChangeAvatar(String termSingularLower);

  /// Title for the avatar cropper
  ///
  /// In en, this message translates to:
  /// **'Crop avatar'**
  String get avatarCropTitle;

  /// Label for the button that rotates an image crop left
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get imageCropRotateLeft;

  /// Label for the button that rotates an image crop right
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get imageCropRotateRight;

  /// Toast message shown when image crop processing fails
  ///
  /// In en, this message translates to:
  /// **'Could not process that image.'**
  String get imageCropProcessingError;

  /// Avatar action: remove avatar
  ///
  /// In en, this message translates to:
  /// **'Remove avatar'**
  String get systemInfoRemoveAvatar;

  /// Button label to clear the saved member profile photo and revert to emoji
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get memberRemoveAvatar;

  /// Section title for member profile header settings
  ///
  /// In en, this message translates to:
  /// **'Profile banner'**
  String get memberProfileHeaderSectionTitle;

  /// Short description for member profile header settings
  ///
  /// In en, this message translates to:
  /// **'Choose the banner image source and layout for this profile.'**
  String get memberProfileHeaderSectionDescription;

  /// Toggle label controlling whether a member profile header banner is visible
  ///
  /// In en, this message translates to:
  /// **'Show profile banner'**
  String get memberProfileHeaderVisibleTitle;

  /// Helper text for the member profile header visibility toggle
  ///
  /// In en, this message translates to:
  /// **'Keeps the image and source saved while hiding the banner.'**
  String get memberProfileHeaderVisibleSubtitle;

  /// Profile header source option label for PluralKit
  ///
  /// In en, this message translates to:
  /// **'PluralKit'**
  String get memberProfileHeaderSourcePluralKit;

  /// Profile header source option label for Prism
  ///
  /// In en, this message translates to:
  /// **'Prism'**
  String get memberProfileHeaderSourcePrism;

  /// Helper text shown when the PluralKit profile header source is selected
  ///
  /// In en, this message translates to:
  /// **'Refreshed from PluralKit when Prism syncs.'**
  String get memberProfileHeaderSourcePluralKitHelper;

  /// Helper text shown when the Prism profile header source is selected
  ///
  /// In en, this message translates to:
  /// **'Private to Prism. Does not update PluralKit.'**
  String get memberProfileHeaderSourcePrismHelper;

  /// Explanation shown when PluralKit cannot be selected as a profile header source
  ///
  /// In en, this message translates to:
  /// **'PluralKit appears after this member has a linked or cached banner.'**
  String get memberProfileHeaderPluralKitUnavailable;

  /// Button label to add a Prism-owned profile header image when none is set
  ///
  /// In en, this message translates to:
  /// **'Add banner'**
  String get memberProfileHeaderAddImage;

  /// Button label to replace a Prism-owned profile header image
  ///
  /// In en, this message translates to:
  /// **'Change banner'**
  String get memberProfileHeaderChangeImage;

  /// Button label to remove a Prism-owned profile header image
  ///
  /// In en, this message translates to:
  /// **'Remove banner'**
  String get memberProfileHeaderRemoveImage;

  /// Switch label for hiding the profile header banner
  ///
  /// In en, this message translates to:
  /// **'Hide profile banner'**
  String get memberProfileHeaderHideTitle;

  /// Label for the member profile header layout selector
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get memberProfileHeaderLayoutLabel;

  /// Profile header layout option that preserves the compact member row
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get memberProfileHeaderLayoutCompact;

  /// Profile header layout option with a wide banner and overlapping avatar
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get memberProfileHeaderLayoutClassic;

  /// Title for the profile header cropper
  ///
  /// In en, this message translates to:
  /// **'Crop profile banner'**
  String get memberProfileHeaderCropTitle;

  /// Toast message shown when profile header image processing fails
  ///
  /// In en, this message translates to:
  /// **'Could not process that image.'**
  String get memberProfileHeaderProcessingError;

  /// Tooltip for the button that opens member name style controls
  ///
  /// In en, this message translates to:
  /// **'Edit name style'**
  String get memberNameStyleTooltip;

  /// Title of the member name style dialog
  ///
  /// In en, this message translates to:
  /// **'Name style'**
  String get memberNameStyleDialogTitle;

  /// Label for the member name font selector
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get memberNameStyleFontLabel;

  /// Default member name font option
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get memberNameStyleFontDefault;

  /// Display member name font option
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get memberNameStyleFontDisplay;

  /// Serif member name font option
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get memberNameStyleFontSerif;

  /// Monospace member name font option
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get memberNameStyleFontMono;

  /// Rounded member name font option
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get memberNameStyleFontRounded;

  /// Label for member name bold and italic toggles
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get memberNameStyleStyleLabel;

  /// Bold toggle label for member name style
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get memberNameStyleBold;

  /// Italic toggle label for member name style
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get memberNameStyleItalic;

  /// Label for the member name color selector
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get memberNameStyleColorLabel;

  /// Default member name color option
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get memberNameStyleColorDefault;

  /// Member accent color option for member name style
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get memberNameStyleColorAccent;

  /// Custom color option for member name style
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get memberNameStyleColorCustom;

  /// Button label to reset member name style to defaults
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get memberNameStyleReset;

  /// System name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get systemInfoNameLabel;

  /// Hint text for system name field
  ///
  /// In en, this message translates to:
  /// **'{systemTerm} name'**
  String systemInfoSystemNameHint(String systemTerm);

  /// Tooltip for save system name button
  ///
  /// In en, this message translates to:
  /// **'Save {systemTermLower} name'**
  String systemInfoSaveSystemName(String systemTermLower);

  /// Tooltip for cancel editing button
  ///
  /// In en, this message translates to:
  /// **'Cancel editing'**
  String get systemInfoCancelEditing;

  /// System description field label
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get systemInfoDescriptionLabel;

  /// Hint text for system description field
  ///
  /// In en, this message translates to:
  /// **'{systemTerm} description'**
  String systemInfoDescriptionHint(String systemTerm);

  /// Placeholder text when no description is set
  ///
  /// In en, this message translates to:
  /// **'Add a description...'**
  String get systemInfoAddDescription;

  /// Tooltip for save description button
  ///
  /// In en, this message translates to:
  /// **'Save description'**
  String get systemInfoSaveDescription;

  /// Label for the system tag field
  ///
  /// In en, this message translates to:
  /// **'{systemTerm} tag'**
  String systemInfoTagLabel(String systemTerm);

  /// Placeholder for the system tag field
  ///
  /// In en, this message translates to:
  /// **'e.g. | Skylars'**
  String get systemInfoTagHint;

  /// Helper text below the system tag field
  ///
  /// In en, this message translates to:
  /// **'Appended to proxied messages'**
  String get systemInfoTagHelper;

  /// Label for the system color row
  ///
  /// In en, this message translates to:
  /// **'{systemTerm} color'**
  String systemInfoColorLabel(String systemTerm);

  /// Button label / dialog title for picking a system color
  ///
  /// In en, this message translates to:
  /// **'Pick color'**
  String get systemInfoColorPickAction;

  /// Button label for clearing the system color
  ///
  /// In en, this message translates to:
  /// **'Clear color'**
  String get systemInfoColorClearAction;

  /// Shown when no system color has been chosen
  ///
  /// In en, this message translates to:
  /// **'No color set'**
  String get systemInfoColorNoneSet;

  /// Switch label for hiding member count totals and group count chips
  ///
  /// In en, this message translates to:
  /// **'Hide member counts'**
  String get systemInfoHideTotalMemberCountTitle;

  /// Helper text for hiding member count displays
  ///
  /// In en, this message translates to:
  /// **'Hides member totals in Settings, {systemTerm} Information, Statistics, diagnostics, and group or folder count chips.'**
  String systemInfoHideTotalMemberCountSubtitle(String systemTerm);

  /// Device management screen title
  ///
  /// In en, this message translates to:
  /// **'Manage Devices'**
  String get devicesTitle;

  /// Section header for the current device
  ///
  /// In en, this message translates to:
  /// **'This Device'**
  String get devicesThisDevice;

  /// Section header for other devices
  ///
  /// In en, this message translates to:
  /// **'Other Devices'**
  String get devicesOtherDevices;

  /// Error title when device list fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load devices'**
  String get devicesFailedToLoad;

  /// Empty state title in device management
  ///
  /// In en, this message translates to:
  /// **'No other devices'**
  String get devicesNoOtherDevices;

  /// Empty state subtitle in device management
  ///
  /// In en, this message translates to:
  /// **'Only this device is registered in the sync group.'**
  String get devicesNoOtherDevicesSubtitle;

  /// Device status: Active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get devicesStatusActive;

  /// Device status: Stale
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get devicesStatusStale;

  /// Device status: Revoked
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get devicesStatusRevoked;

  /// Tooltip for rotate signing key button
  ///
  /// In en, this message translates to:
  /// **'Rotate signing key'**
  String get devicesRotateKey;

  /// Dialog title for key rotation
  ///
  /// In en, this message translates to:
  /// **'Rotate Signing Key?'**
  String get devicesRotateKeyTitle;

  /// Dialog message for key rotation
  ///
  /// In en, this message translates to:
  /// **'This generates a new post-quantum signing key for this device. Other devices will accept the new key automatically. The old key remains valid for 30 days.'**
  String get devicesRotateKeyMessage;

  /// Button label: rotate key
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get devicesRotate;

  /// Toast after successful key rotation
  ///
  /// In en, this message translates to:
  /// **'Key rotated to generation {gen}'**
  String devicesKeyRotated(int gen);

  /// Toast when key rotation fails
  ///
  /// In en, this message translates to:
  /// **'Key rotation failed: {error}'**
  String devicesKeyRotationFailed(Object error);

  /// Dialog title for device revocation
  ///
  /// In en, this message translates to:
  /// **'Revoke Device?'**
  String get devicesRevokeTitle;

  /// Dialog message for device revocation
  ///
  /// In en, this message translates to:
  /// **'Device {shortId} will be removed from the sync group and can no longer sync. This cannot be undone.'**
  String devicesRevokeMessage(String shortId);

  /// Toggle title in revoke dialog: request wipe
  ///
  /// In en, this message translates to:
  /// **'Request remote data wipe'**
  String get devicesRequestWipeTitle;

  /// Toggle subtitle in revoke dialog: request wipe
  ///
  /// In en, this message translates to:
  /// **'Asks the device to erase its sync data. This is a request — if the device is offline or compromised, it may not be honored.'**
  String get devicesRequestWipeSubtitle;

  /// Button label: revoke device
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get devicesRevoke;

  /// Toast after device is revoked
  ///
  /// In en, this message translates to:
  /// **'Device {shortId} revoked'**
  String devicesRevoked(String shortId);

  /// Toast when device revocation fails
  ///
  /// In en, this message translates to:
  /// **'Failed to revoke: {error}'**
  String devicesFailedToRevoke(Object error);

  /// Semantics label for a device tile
  ///
  /// In en, this message translates to:
  /// **'Device {shortId}, {status}, key generation {gen}'**
  String devicesSemanticLabel(String shortId, String status, int gen);

  /// Semantics label for current device tile
  ///
  /// In en, this message translates to:
  /// **'Device {shortId}, {status}, key generation {gen}, this device'**
  String devicesSemanticLabelCurrent(String shortId, String status, int gen);

  /// Button label: continue to next step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// Device tile subtitle: epoch and key generation
  ///
  /// In en, this message translates to:
  /// **'Epoch {epoch} · Key gen {gen}'**
  String devicesEpochKeyGen(int epoch, int gen);

  /// Tooltip on rotate key button
  ///
  /// In en, this message translates to:
  /// **'Rotate signing key'**
  String get devicesRotateKeyTooltip;

  /// Tooltip on revoke button
  ///
  /// In en, this message translates to:
  /// **'Revoke device'**
  String get devicesRevokeTooltip;

  /// Toast when device ID is copied to clipboard
  ///
  /// In en, this message translates to:
  /// **'Device ID copied'**
  String get devicesIdCopied;

  /// Title of the sync troubleshooting screen
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get syncTroubleshootingTitle;

  /// Section header: connection status
  ///
  /// In en, this message translates to:
  /// **'Connection Status'**
  String get syncTroubleshootingConnectionStatus;

  /// Connection state: not configured
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get syncTroubleshootingNotConfigured;

  /// Connection state: connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get syncTroubleshootingConnected;

  /// Connection state: configured locally but engine not active
  ///
  /// In en, this message translates to:
  /// **'Configured locally'**
  String get syncTroubleshootingConfiguredLocally;

  /// Subtitle when sync is not configured
  ///
  /// In en, this message translates to:
  /// **'This device does not currently have sync set up.'**
  String get syncTroubleshootingNotConfiguredSubtitle;

  /// Subtitle when sync is connected
  ///
  /// In en, this message translates to:
  /// **'Sync engine is active and ready'**
  String get syncTroubleshootingConnectedSubtitle;

  /// Subtitle when configured locally but not active
  ///
  /// In en, this message translates to:
  /// **'Settings are stored. The engine will reconnect on the next sync.'**
  String get syncTroubleshootingConfiguredLocallySubtitle;

  /// Section header: last sync time
  ///
  /// In en, this message translates to:
  /// **'Last Sync'**
  String get syncTroubleshootingLastSync;

  /// Row title: last successful sync
  ///
  /// In en, this message translates to:
  /// **'Last successful sync'**
  String get syncTroubleshootingLastSuccessful;

  /// Subtitle when never synced
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get syncTroubleshootingNeverSynced;

  /// Row title: last sync error
  ///
  /// In en, this message translates to:
  /// **'Last sync error'**
  String get syncTroubleshootingLastError;

  /// Row title: current sync state
  ///
  /// In en, this message translates to:
  /// **'Current sync state'**
  String get syncTroubleshootingCurrentState;

  /// Sync state: syncing
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncTroubleshootingSyncing;

  /// Sync state: idle
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get syncTroubleshootingIdle;

  /// Row title: pending operations
  ///
  /// In en, this message translates to:
  /// **'Pending operations'**
  String get syncTroubleshootingPendingOps;

  /// Subtitle for pending ops count
  ///
  /// In en, this message translates to:
  /// **'{count} ops waiting to sync'**
  String syncTroubleshootingPendingOpsValue(int count);

  /// Banner title shown when local push batches exceeded the relay's body cap and were quarantined.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item is too large to sync} other{{count} items are too large to sync}}'**
  String syncQuarantinedBatchBannerTitle(int count);

  /// Banner body shown beneath the quarantine count, directing the user to the Repair action.
  ///
  /// In en, this message translates to:
  /// **'Tap Repair stuck sync below to split the affected items into smaller chunks. Your data is safe — nothing has been lost.'**
  String get syncQuarantinedBatchBannerBody;

  /// Button label shown alongside the quarantine banner to trigger Phase 1C repair.
  ///
  /// In en, this message translates to:
  /// **'Repair stuck sync'**
  String get syncQuarantinedBatchRepairAction;

  /// Description text shown beneath the Repair stuck sync button.
  ///
  /// In en, this message translates to:
  /// **'Splits the affected items into smaller chunks so they can finish syncing. Your data is not lost.'**
  String get syncQuarantinedBatchRepairDescription;

  /// Snackbar text after Repair stuck sync completes successfully.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Repaired 1 item — sync resuming…} other{Repaired {count} items — sync resuming…}}'**
  String syncQuarantinedBatchRepairSuccess(int count);

  /// Snackbar text shown when the Repair stuck sync action fails.
  ///
  /// In en, this message translates to:
  /// **'Repair failed: {error}'**
  String syncQuarantinedBatchRepairFailure(String error);

  /// Row title: sync ID
  ///
  /// In en, this message translates to:
  /// **'Sync ID'**
  String get syncTroubleshootingSyncId;

  /// Row title: relay URL
  ///
  /// In en, this message translates to:
  /// **'Relay URL'**
  String get syncTroubleshootingRelayUrl;

  /// Section header for copyable sync identifiers used in support requests
  ///
  /// In en, this message translates to:
  /// **'Support info'**
  String get syncTroubleshootingSupportInfo;

  /// Section header for active sync errors or repairable sync issues
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get syncTroubleshootingNeedsAttention;

  /// Section header for lower-priority sync activity and stats
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get syncTroubleshootingActivity;

  /// Toast when a sync support identifier is copied to clipboard
  ///
  /// In en, this message translates to:
  /// **'{label} copied'**
  String syncTroubleshootingCopied(String label);

  /// Section header: actions
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get syncTroubleshootingActions;

  /// Button: force sync now
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncTroubleshootingForceSync;

  /// Subtitle for the manual sync action row
  ///
  /// In en, this message translates to:
  /// **'Push and pull pending changes right away.'**
  String get syncTroubleshootingForceSyncSubtitle;

  /// Button: open sync event log
  ///
  /// In en, this message translates to:
  /// **'Open Prism Sync Event Log'**
  String get syncTroubleshootingOpenEventLog;

  /// Button: reset sync system
  ///
  /// In en, this message translates to:
  /// **'Reset sync'**
  String get syncTroubleshootingResetSync;

  /// Subtitle for the reset sync action row
  ///
  /// In en, this message translates to:
  /// **'Clear sync setup on this device; local data stays.'**
  String get syncTroubleshootingResetSyncSubtitle;

  /// Title for sync troubleshooting tips row and detail screen
  ///
  /// In en, this message translates to:
  /// **'Troubleshooting tips'**
  String get syncTroubleshootingTipsTitle;

  /// Subtitle for row linking to sync troubleshooting tips
  ///
  /// In en, this message translates to:
  /// **'Common fixes for connection, duplicate, and pairing issues.'**
  String get syncTroubleshootingTipsSubtitle;

  /// Section header for advanced sync diagnostic links
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get syncTroubleshootingDiagnostics;

  /// Short description for the advanced sync diagnostics section
  ///
  /// In en, this message translates to:
  /// **'Technical logs for support and deeper debugging; not usually needed for everyday fixes.'**
  String get syncTroubleshootingDiagnosticsSubtitle;

  /// Row title for the sync event log diagnostics screen
  ///
  /// In en, this message translates to:
  /// **'Sync event log'**
  String get syncTroubleshootingEventLogTitle;

  /// Row subtitle for the sync event log diagnostics screen
  ///
  /// In en, this message translates to:
  /// **'Stream of sync events from this session'**
  String get syncTroubleshootingEventLogSubtitle;

  /// Row title for the sync crypto storage diagnostics screen
  ///
  /// In en, this message translates to:
  /// **'Crypto storage'**
  String get syncTroubleshootingCryptoStorageTitle;

  /// Row subtitle for the sync crypto storage diagnostics screen
  ///
  /// In en, this message translates to:
  /// **'Keychain inventory and per-boot snapshot history'**
  String get syncTroubleshootingCryptoStorageSubtitle;

  /// Common issue 1 title
  ///
  /// In en, this message translates to:
  /// **'Sync not working?'**
  String get syncTroubleshootingIssue1Title;

  /// Common issue 1 description
  ///
  /// In en, this message translates to:
  /// **'Check that the relay URL and sync ID match on both devices.'**
  String get syncTroubleshootingIssue1Description;

  /// Common issue 2 title
  ///
  /// In en, this message translates to:
  /// **'Duplicate data?'**
  String get syncTroubleshootingIssue2Title;

  /// Common issue 2 description
  ///
  /// In en, this message translates to:
  /// **'Try resetting the sync system using the button above. This wipes local sync setup and lets you pair again cleanly.'**
  String get syncTroubleshootingIssue2Description;

  /// Common issue 3 title
  ///
  /// In en, this message translates to:
  /// **'Connection errors?'**
  String get syncTroubleshootingIssue3Title;

  /// Common issue 3 description
  ///
  /// In en, this message translates to:
  /// **'Verify that your device has network access and that the relay server is online. Check the relay URL for typos.'**
  String get syncTroubleshootingIssue3Description;

  /// Common issue 4 title
  ///
  /// In en, this message translates to:
  /// **'Sync is slow?'**
  String get syncTroubleshootingIssue4Title;

  /// Common issue 4 description
  ///
  /// In en, this message translates to:
  /// **'Initial sync may take longer with large datasets. Subsequent syncs are incremental and should be faster.'**
  String get syncTroubleshootingIssue4Description;

  /// Common issue 5 title
  ///
  /// In en, this message translates to:
  /// **'Device Identity Mismatch'**
  String get syncTroubleshootingIssue5Title;

  /// Common issue 5 description
  ///
  /// In en, this message translates to:
  /// **'If pairing failed mid-way, your device identity may be inconsistent. Use Reset sync to clear this device\'s sync identity, then pair again.'**
  String get syncTroubleshootingIssue5Description;

  /// Toast when sync finishes
  ///
  /// In en, this message translates to:
  /// **'Sync finished'**
  String get syncTroubleshootingFinished;

  /// Toast when sync fails
  ///
  /// In en, this message translates to:
  /// **'Prism sync failed: {error}'**
  String syncTroubleshootingFailed(Object error);

  /// Dialog title for sync reset
  ///
  /// In en, this message translates to:
  /// **'Reset sync setup?'**
  String get syncTroubleshootingResetTitle;

  /// Dialog message for sync reset
  ///
  /// In en, this message translates to:
  /// **'This clears sync credentials, relay settings, device identity, and sync history on this device. Your local Prism data stays here.\n\nAfter reset, Prism will return to the sync setup screen so you can pair again. Export first if you want an extra backup before changing sync setup.'**
  String get syncTroubleshootingResetMessage;

  /// Button: confirm sync reset
  ///
  /// In en, this message translates to:
  /// **'Reset sync'**
  String get syncTroubleshootingResetConfirm;

  /// Toast after sync reset
  ///
  /// In en, this message translates to:
  /// **'Sync system reset'**
  String get syncTroubleshootingResetSuccess;

  /// Button: go to import/export before resetting sync
  ///
  /// In en, this message translates to:
  /// **'Back up first'**
  String get syncTroubleshootingBackupFirst;

  /// Description text on chat feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Private messaging between {term} in your {systemTermLower}.'**
  String featureChatDescription(String term, String systemTermLower);

  /// Section title: general settings on chat feature screen
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get featureChatGeneral;

  /// Toggle title: enable chat
  ///
  /// In en, this message translates to:
  /// **'Enable Chat'**
  String get featureChatEnable;

  /// Toggle subtitle: enable chat
  ///
  /// In en, this message translates to:
  /// **'Messaging between {term} in this {systemTermLower}'**
  String featureChatEnableSubtitle(String term, String systemTermLower);

  /// Section title: options on chat feature screen
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get featureChatOptions;

  /// Toggle title: log front on speaker switch
  ///
  /// In en, this message translates to:
  /// **'Log Front on Switch'**
  String get featureChatLogFront;

  /// Toggle subtitle: log front on speaker switch
  ///
  /// In en, this message translates to:
  /// **'Changing who\'s speaking in chat also logs a front'**
  String get featureChatLogFrontSubtitle;

  /// Toggle title: use proxy tags to author single messages
  ///
  /// In en, this message translates to:
  /// **'Use proxy tags to author messages'**
  String get featureChatProxyTagAuthoring;

  /// Toggle subtitle: explains proxy-tag authoring and case sensitivity
  ///
  /// In en, this message translates to:
  /// **'Type a proxy tag (e.g. A:) to author as that {termSingularLower} for one message. Case-sensitive.'**
  String featureChatProxyTagAuthoringSubtitle(String termSingularLower);

  /// Chip label shown above the chat composer when a proxy tag matches the draft
  ///
  /// In en, this message translates to:
  /// **'Posting as {name}'**
  String chatPostingAsProxy(String name);

  /// Accessibility label for the dismiss button on the proxy-tag authoring chip
  ///
  /// In en, this message translates to:
  /// **'Don\'t post as proxy'**
  String get chatPostingAsProxyDismiss;

  /// Toggle title: GIF search
  ///
  /// In en, this message translates to:
  /// **'GIF Search'**
  String get featureChatGifSearch;

  /// Toggle subtitle: GIF search
  ///
  /// In en, this message translates to:
  /// **'Search and send GIFs in chat'**
  String get featureChatGifSearchSubtitle;

  /// Subtitle for GIF search before the user has decided
  ///
  /// In en, this message translates to:
  /// **'Off until you review the privacy details'**
  String get featureChatGifSearchUndecidedSubtitle;

  /// Subtitle for GIF search after the user has enabled it
  ///
  /// In en, this message translates to:
  /// **'Enabled on this device'**
  String get featureChatGifSearchEnabledSubtitle;

  /// Subtitle for GIF search after the user has declined it
  ///
  /// In en, this message translates to:
  /// **'Hidden after you declined it on this device'**
  String get featureChatGifSearchDeclinedSubtitle;

  /// Subtitle for GIF search when sync is not configured
  ///
  /// In en, this message translates to:
  /// **'Sync must be enabled to use GIFs'**
  String get featureChatGifSearchSyncRequiredSubtitle;

  /// Title for the dialog explaining GIFs need sync
  ///
  /// In en, this message translates to:
  /// **'Sync required for GIFs'**
  String get featureChatGifSearchSyncRequiredDialogTitle;

  /// Body text for the dialog explaining GIFs need sync
  ///
  /// In en, this message translates to:
  /// **'GIF search runs through your sync relay so the service stays private. Set up sync to enable GIFs on this device.'**
  String get featureChatGifSearchSyncRequiredDialogBody;

  /// Primary action label for the GIFs-need-sync dialog
  ///
  /// In en, this message translates to:
  /// **'Set up sync'**
  String get featureChatGifSearchSyncRequiredDialogAction;

  /// Title for voice notes feature toggle in chat settings
  ///
  /// In en, this message translates to:
  /// **'Voice Notes'**
  String get featureChatVoiceNotes;

  /// Subtitle for voice notes feature toggle
  ///
  /// In en, this message translates to:
  /// **'Send voice messages in chat'**
  String get featureChatVoiceNotesSubtitle;

  /// Description text on fronting feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Configure how fronting sessions work.'**
  String get featureFrontingDescription;

  /// Section title: options on fronting feature screen
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get featureFrontingOptions;

  /// Row title: quick switch setting
  ///
  /// In en, this message translates to:
  /// **'Quick Switch'**
  String get featureFrontingQuickSwitch;

  /// Quick switch label when off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get featureFrontingQuickSwitchOff;

  /// Quick switch label for seconds
  ///
  /// In en, this message translates to:
  /// **'{seconds}s correction window'**
  String featureFrontingQuickSwitchSeconds(int seconds);

  /// Quick switch label for minutes
  ///
  /// In en, this message translates to:
  /// **'{minutes}m correction window'**
  String featureFrontingQuickSwitchMinutes(int minutes);

  /// Dialog title for quick switch picker
  ///
  /// In en, this message translates to:
  /// **'Quick Switch Window'**
  String get featureFrontingQuickSwitchTitle;

  /// Dialog message for quick switch picker
  ///
  /// In en, this message translates to:
  /// **'If you switch fronters within this window, it corrects the current session instead of creating a new one.'**
  String get featureFrontingQuickSwitchMessage;

  /// Label for the show/hide Quick Front toggle in fronting settings
  ///
  /// In en, this message translates to:
  /// **'Quick Front'**
  String get featureFrontingShowQuickFront;

  /// Subtitle for the show/hide Quick Front toggle
  ///
  /// In en, this message translates to:
  /// **'Show frequently fronting {termPluralLower} as tap-and-hold shortcuts'**
  String featureFrontingShowQuickFrontSubtitle(String termPluralLower);

  /// Description text on habits feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Track recurring tasks and build streaks with {term} in your {systemTermLower}.'**
  String featureHabitsDescription(String term, String systemTermLower);

  /// Section title: general on habits feature screen
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get featureHabitsGeneral;

  /// Toggle title: enable habits
  ///
  /// In en, this message translates to:
  /// **'Enable Habits'**
  String get featureHabitsEnable;

  /// Toggle subtitle: enable habits
  ///
  /// In en, this message translates to:
  /// **'Track daily routines and goals'**
  String get featureHabitsEnableSubtitle;

  /// Section title: options on habits feature screen
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get featureHabitsOptions;

  /// Toggle title: due habits badge
  ///
  /// In en, this message translates to:
  /// **'Due Habits Badge'**
  String get featureHabitsDueBadge;

  /// Toggle subtitle: due habits badge
  ///
  /// In en, this message translates to:
  /// **'Show count of due habits on the tab icon'**
  String get featureHabitsDueBadgeSubtitle;

  /// Description text on sleep feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Sleep sessions help you track rest patterns alongside fronting sessions. You can start a sleep session from the moon icon on the fronting screen.'**
  String get featureSleepDescription;

  /// Section title: general on sleep feature screen
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get featureSleepGeneral;

  /// Toggle title: enable sleep
  ///
  /// In en, this message translates to:
  /// **'Enable Sleep'**
  String get featureSleepEnable;

  /// Toggle subtitle: enable sleep
  ///
  /// In en, this message translates to:
  /// **'Log and monitor sleep sessions'**
  String get featureSleepEnableSubtitle;

  /// Section title: options on sleep feature screen
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get featureSleepOptions;

  /// Row title: default sleep quality
  ///
  /// In en, this message translates to:
  /// **'Default Quality'**
  String get featureSleepDefaultQuality;

  /// Dialog title for default quality picker
  ///
  /// In en, this message translates to:
  /// **'Default Quality'**
  String get featureSleepDefaultQualityTitle;

  /// Dialog message for default quality picker
  ///
  /// In en, this message translates to:
  /// **'Choose the default quality rating for new sleep sessions.'**
  String get featureSleepDefaultQualityMessage;

  /// Section title: sleep data recovery
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get featureSleepRecovery;

  /// Row title: restore soft-deleted sleep sessions
  ///
  /// In en, this message translates to:
  /// **'Restore deleted sleep sessions'**
  String get featureSleepRestoreDeleted;

  /// Row subtitle: number of restorable deleted sleep sessions
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 deleted sleep session can be restored} other{{count} deleted sleep sessions can be restored}}'**
  String featureSleepRestoreDeletedSubtitle(int count);

  /// Confirm dialog message for restoring deleted sleep sessions
  ///
  /// In en, this message translates to:
  /// **'This brings back sleep sessions that were removed — including any you deleted on purpose. You can delete those again afterward.'**
  String get featureSleepRestoreConfirmMessage;

  /// Confirm dialog action label for restoring deleted sleep sessions
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get featureSleepRestoreConfirmAction;

  /// Toast after restoring deleted sleep sessions
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Restored 1 sleep session.} other{Restored {count} sleep sessions.}}'**
  String featureSleepRestoreSuccess(int count);

  /// Toast when there were no deleted sleep sessions to restore
  ///
  /// In en, this message translates to:
  /// **'No deleted sleep sessions to restore.'**
  String get featureSleepRestoreNone;

  /// Error toast when restoring deleted sleep sessions failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore sleep sessions.'**
  String get featureSleepRestoreFailed;

  /// Title of the sleep-recovery banner in the sleep view
  ///
  /// In en, this message translates to:
  /// **'Missing sleep sessions?'**
  String get featureSleepRecoveryBannerTitle;

  /// Body of the sleep-recovery banner; count is the number recoverable
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A past bug removed 1 of your sleep sessions. It\'s still saved and can be brought back.} other{A past bug removed {count} of your sleep sessions. They\'re still saved and can be brought back.}}'**
  String featureSleepRecoveryBannerBody(int count);

  /// Button on the sleep-recovery banner that opens the recovery sheet
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get featureSleepRecoveryBannerAction;

  /// Button label while a sleep recovery is in progress
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get featureSleepRecoverySheetRestoring;

  /// Description text on polls feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Let your {systemTermLower} vote on decisions together. Disabling hides polls from navigation but keeps existing poll data.'**
  String featurePollsDescription(String systemTermLower);

  /// Toggle title: enable polls
  ///
  /// In en, this message translates to:
  /// **'Enable Polls'**
  String get featurePollsEnable;

  /// Toggle subtitle: enable polls
  ///
  /// In en, this message translates to:
  /// **'Create polls for {systemTermLower} decisions'**
  String featurePollsEnableSubtitle(String systemTermLower);

  /// Description text on notes feature settings screen
  ///
  /// In en, this message translates to:
  /// **'A personal journal for {term} in your {systemTermLower}. Disabling hides notes from navigation but keeps existing entries.'**
  String featureNotesDescription(String term, String systemTermLower);

  /// Toggle title: enable notes
  ///
  /// In en, this message translates to:
  /// **'Enable Notes'**
  String get featureNotesEnable;

  /// Toggle subtitle: enable notes
  ///
  /// In en, this message translates to:
  /// **'Write notes and journal entries'**
  String get featureNotesEnableSubtitle;

  /// Description text on reminders feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Get reminded on a schedule or when fronters change. Disabling hides reminders from navigation but keeps existing ones.'**
  String get featureRemindersDescription;

  /// Section title: general on reminders feature screen
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get featureRemindersGeneral;

  /// Toggle title: enable reminders
  ///
  /// In en, this message translates to:
  /// **'Enable Reminders'**
  String get featureRemindersEnable;

  /// Toggle subtitle: enable reminders
  ///
  /// In en, this message translates to:
  /// **'Scheduled and front-change reminders'**
  String get featureRemindersEnableSubtitle;

  /// Section title: options on reminders feature screen
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get featureRemindersOptions;

  /// Row title: manage reminders
  ///
  /// In en, this message translates to:
  /// **'Manage Reminders'**
  String get featureRemindersManage;

  /// Row subtitle: manage reminders
  ///
  /// In en, this message translates to:
  /// **'Create and edit your reminders'**
  String get featureRemindersManageSubtitle;

  /// Status shown while a recorded voice note is being finalized before send
  ///
  /// In en, this message translates to:
  /// **'Preparing voice note...'**
  String get voicePreparingNote;

  /// Accessibility announcement when voice recording starts
  ///
  /// In en, this message translates to:
  /// **'Recording started.'**
  String get voiceRecordingStartedAnnouncement;

  /// Accessibility announcement when a recorded voice note is ready to send
  ///
  /// In en, this message translates to:
  /// **'Voice note ready to send.'**
  String get voiceRecordingReadyAnnouncement;

  /// Error shown when the user dismisses the microphone permission prompt
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to record voice notes.'**
  String get voiceMicPermissionDenied;

  /// Error shown when microphone permission is permanently denied
  ///
  /// In en, this message translates to:
  /// **'Microphone access is blocked. Enable it in Settings.'**
  String get voiceMicPermissionBlocked;

  /// Generic error when voice recording fails for a non-permission reason
  ///
  /// In en, this message translates to:
  /// **'Could not start recording.'**
  String get voiceRecordingFailed;

  /// Label for a button that opens the OS app settings page
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// Tooltip to switch to list view on the fronting screen
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get frontingListView;

  /// Tooltip to switch to timeline view on the fronting screen
  ///
  /// In en, this message translates to:
  /// **'Timeline view'**
  String get frontingTimelineView;

  /// Tooltip for the add button on the fronting screen
  ///
  /// In en, this message translates to:
  /// **'Add fronting entry'**
  String get frontingAddEntry;

  /// Accessibility announcement when loading older sessions on scroll
  ///
  /// In en, this message translates to:
  /// **'Loading older sessions'**
  String get frontingLoadingOlderSessions;

  /// Subtitle on the pinned 'always-present' header at the top of the home screen. The duration placeholder is a pre-formatted localized string like '2 weeks' or '3 hours'.
  ///
  /// In en, this message translates to:
  /// **'Always present · {duration}'**
  String frontingAlwaysPresentLabel(String duration);

  /// Subtitle for pinned header entries shown because their active fronting session has been running for a long time.
  ///
  /// In en, this message translates to:
  /// **'Long-running · {duration}'**
  String frontingLongRunningLabel(String duration);

  /// Subtitle for pinned header entries containing both Always fronting and long-running active sessions.
  ///
  /// In en, this message translates to:
  /// **'Always present + long-running · {duration}'**
  String frontingMixedPinnedLabel(String duration);

  /// Single combined screen-reader announcement for the always-present pinned header. Names is a comma+ampersand-joined member list; duration is the same pre-formatted string used in the visible subtitle.
  ///
  /// In en, this message translates to:
  /// **'Always-present fronters: {names}, {duration}'**
  String frontingAlwaysPresentSemantics(String names, String duration);

  /// Screen-reader announcement for the pinned header when at least one surfaced member is only there because their session has been running a long time, not because they explicitly opted into always fronting.
  ///
  /// In en, this message translates to:
  /// **'Long-running fronters: {names}, {duration}. Double tap to view details.'**
  String frontingLongRunningSemantics(String names, String duration);

  /// Duration formatted in whole weeks for the always-present header.
  ///
  /// In en, this message translates to:
  /// **'{weeks, plural, =1{1 week} other{{weeks} weeks}}'**
  String frontingAlwaysPresentDurationWeeks(int weeks);

  /// Duration formatted in whole days for the always-present header (used when under one week).
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String frontingAlwaysPresentDurationDays(int days);

  /// Duration formatted in whole hours for the always-present header (used when under one day, only reachable for explicit-always-fronting members whose session just started).
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour} other{{hours} hours}}'**
  String frontingAlwaysPresentDurationHours(int hours);

  /// Menu item to wake up and start fronting as a specific member
  ///
  /// In en, this message translates to:
  /// **'Wake Up As...'**
  String get frontingMenuWakeUpAs;

  /// Menu item to log a new fronting entry
  ///
  /// In en, this message translates to:
  /// **'Log Front'**
  String get frontingMenuLogFront;

  /// Menu item to log a closed historical fronting session
  ///
  /// In en, this message translates to:
  /// **'Log Past Session'**
  String get frontingMenuLogPastSession;

  /// Menu item to start a sleep session
  ///
  /// In en, this message translates to:
  /// **'Start Sleep'**
  String get frontingMenuStartSleep;

  /// Menu item to manually trigger a PluralKit sync
  ///
  /// In en, this message translates to:
  /// **'Sync with PluralKit'**
  String get frontingMenuSyncPluralKit;

  /// Toast shown when a manual PluralKit sync starts
  ///
  /// In en, this message translates to:
  /// **'Syncing with PluralKit…'**
  String get frontingPluralKitSyncingToast;

  /// Toast shown when a manual PluralKit sync finishes
  ///
  /// In en, this message translates to:
  /// **'PluralKit sync complete'**
  String get frontingPluralKitSyncDoneToast;

  /// Toast shown when a manual PluralKit sync fails
  ///
  /// In en, this message translates to:
  /// **'PluralKit sync failed: {error}'**
  String frontingPluralKitSyncFailedToast(Object error);

  /// Dialog title for selecting a member to front after waking up
  ///
  /// In en, this message translates to:
  /// **'Wake Up As...'**
  String get frontingWakeUpAsTitle;

  /// Error toast when waking up fails
  ///
  /// In en, this message translates to:
  /// **'Error waking up: {error}'**
  String frontingErrorWakingUp(Object error);

  /// Error toast when a quick-switch fronter action fails
  ///
  /// In en, this message translates to:
  /// **'Error switching fronter: {error}'**
  String frontingErrorSwitchingFronter(Object error);

  /// Empty state text when there is no fronting history
  ///
  /// In en, this message translates to:
  /// **'No session history yet'**
  String get frontingNoSessionHistory;

  /// Error shown in session history list when history fails to load
  ///
  /// In en, this message translates to:
  /// **'Error loading history: {error}'**
  String frontingErrorLoadingHistory(Object error);

  /// Title of the confirm dialog when deleting a multi-contributor period.
  ///
  /// In en, this message translates to:
  /// **'Delete period?'**
  String get frontingDeletePeriodTitle;

  /// Message in the confirm dialog when deleting a multi-contributor period.
  ///
  /// In en, this message translates to:
  /// **'This will remove {count, plural, =1{1 session} other{{count} sessions}} for {names}.'**
  String frontingDeletePeriodMessage(int count, String names);

  /// Confirmation dialog title for deleting a sleep session
  ///
  /// In en, this message translates to:
  /// **'Delete Sleep Session'**
  String get frontingDeleteSleepTitle;

  /// Confirmation dialog message for deleting a sleep session
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this sleep session?'**
  String get frontingDeleteSleepMessage;

  /// Label for a sleep session in the history list
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get frontingSleeping;

  /// Semantics label for a sleep session tile
  ///
  /// In en, this message translates to:
  /// **'Sleep session, {duration}, {timeRange}'**
  String frontingSleepSessionSemantics(String duration, String timeRange);

  /// Title on empty system view when no members exist
  ///
  /// In en, this message translates to:
  /// **'Welcome to Prism'**
  String get frontingWelcomeTitle;

  /// Subtitle on empty system view (uses terminology term for member)
  ///
  /// In en, this message translates to:
  /// **'Add your first {systemTermLower} {member} to get started'**
  String frontingWelcomeSubtitle(String systemTermLower, String member);

  /// Semantics label for a quick-front avatar button
  ///
  /// In en, this message translates to:
  /// **'Quick front {name}'**
  String frontingQuickFrontLabel(String name);

  /// Semantics long-press hint on quick front button
  ///
  /// In en, this message translates to:
  /// **'Hold to start fronting'**
  String get frontingQuickFrontHoldHint;

  /// Visible helper text above Quick Front shortcuts on the home screen
  ///
  /// In en, this message translates to:
  /// **'Press and hold'**
  String get frontingQuickFrontHoldInstruction;

  /// Sheet title when creating a new fronting session (non-co-front mode)
  ///
  /// In en, this message translates to:
  /// **'New Session'**
  String get frontingNewSession;

  /// Section header on the add-front sheet for choosing between a live session and a historical session
  ///
  /// In en, this message translates to:
  /// **'Session Time'**
  String get frontingSessionTime;

  /// Segmented-control option on the add-front sheet for starting an active session at an earlier time
  ///
  /// In en, this message translates to:
  /// **'Start Earlier'**
  String get frontingSessionTimeStartEarlier;

  /// Segmented-control option on the add-front sheet for starting a session immediately
  ///
  /// In en, this message translates to:
  /// **'Start Now'**
  String get frontingSessionTimeStartNow;

  /// Segmented-control option on the add-front sheet for logging a historical session
  ///
  /// In en, this message translates to:
  /// **'Past Session'**
  String get frontingSessionTimePastSession;

  /// Sheet title and disclosure label for the historical fronting session flow
  ///
  /// In en, this message translates to:
  /// **'Log Past Session'**
  String get frontingLogPastSession;

  /// Sheet title when adding a co-fronter to the active session
  ///
  /// In en, this message translates to:
  /// **'Add Fronter'**
  String get frontingAddCoFronterTitle;

  /// Tooltip and semantics label for confirming a new fronting session
  ///
  /// In en, this message translates to:
  /// **'Start session'**
  String get frontingStartSessionTooltip;

  /// Tooltip and semantics label for confirming a new co-front session
  ///
  /// In en, this message translates to:
  /// **'Add fronter'**
  String get frontingAddCoFronterTooltip;

  /// Section header when selecting the primary fronter
  ///
  /// In en, this message translates to:
  /// **'Select Fronter'**
  String get frontingSelectFronter;

  /// Add-front sheet segmented control: additive mode (joins existing fronts)
  ///
  /// In en, this message translates to:
  /// **'Add as fronter'**
  String get frontingAddFrontModeAdditive;

  /// Add-front sheet segmented control: replace mode (ends existing fronts, starts new)
  ///
  /// In en, this message translates to:
  /// **'Replace current'**
  String get frontingAddFrontModeReplace;

  /// Section header when selecting a member in co-front mode
  ///
  /// In en, this message translates to:
  /// **'Select {term}'**
  String frontingSelectMember(String term);

  /// Toggle label to switch between new session and co-front mode
  ///
  /// In en, this message translates to:
  /// **'Add fronter'**
  String get frontingCoFrontToggle;

  /// Section header for co-fronter selection in add session sheet
  ///
  /// In en, this message translates to:
  /// **'Fronters'**
  String get frontingCoFronters;

  /// Empty state when no other members are available to add as co-fronters
  ///
  /// In en, this message translates to:
  /// **'No other {term} available'**
  String frontingNoOtherMembers(String term);

  /// Hint text shown in co-front mode on the add session sheet
  ///
  /// In en, this message translates to:
  /// **'Tap a {term} to add them to the current front.'**
  String frontingCoFrontHint(String term);

  /// Section header for confidence level picker
  ///
  /// In en, this message translates to:
  /// **'Confidence Level'**
  String get frontingConfidenceLevel;

  /// Confidence level: unsure
  ///
  /// In en, this message translates to:
  /// **'Unsure'**
  String get frontingConfidenceUnsure;

  /// Confidence level: strong
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get frontingConfidenceStrong;

  /// Confidence level: certain
  ///
  /// In en, this message translates to:
  /// **'Certain'**
  String get frontingConfidenceCertain;

  /// Label for the notes field in add/edit session sheets
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get frontingNotes;

  /// Hint text for notes field in add session sheet
  ///
  /// In en, this message translates to:
  /// **'Optional notes about this session...'**
  String get frontingNotesHint;

  /// Hint text for notes field in edit session screen
  ///
  /// In en, this message translates to:
  /// **'Optional notes...'**
  String get frontingNotesHintEdit;

  /// Hint text in member search field on add session sheet
  ///
  /// In en, this message translates to:
  /// **'Search {term}...'**
  String frontingSearchMembersHint(String term);

  /// Empty state when search yields no members
  ///
  /// In en, this message translates to:
  /// **'No {term} matching \"{query}\"'**
  String frontingNoMembersMatching(String term, String query);

  /// Badge label shown on a member avatar who is already fronting
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get frontingFronting;

  /// Error toast when adding a co-fronter fails
  ///
  /// In en, this message translates to:
  /// **'Error adding fronter: {error}'**
  String frontingErrorAddingCoFronter(Object error);

  /// Error toast when creating a fronting session fails
  ///
  /// In en, this message translates to:
  /// **'Error creating session: {error}'**
  String frontingErrorCreatingSession(Object error);

  /// Header title on the add co-fronters bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Add Fronters'**
  String get frontingAddCoFrontersTitle;

  /// Error toast when adding co-fronters fails
  ///
  /// In en, this message translates to:
  /// **'Error adding fronters: {error}'**
  String frontingErrorAddingCoFronters(Object error);

  /// Title on the edit fronting session screen
  ///
  /// In en, this message translates to:
  /// **'Edit Session'**
  String get frontingEditSessionTitle;

  /// Semantics label for save button on edit session screen
  ///
  /// In en, this message translates to:
  /// **'Save session'**
  String get frontingSaveSession;

  /// Message shown when the requested session is not found
  ///
  /// In en, this message translates to:
  /// **'Session not found'**
  String get frontingSessionNotFound;

  /// Toggle label for marking a session as still active
  ///
  /// In en, this message translates to:
  /// **'Still Active'**
  String get frontingStillActive;

  /// Label for the start date/time field in session edit screen
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get frontingStart;

  /// Label for the end date/time field in session edit screen
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get frontingEnd;

  /// Section header for the fronter picker in edit session screen
  ///
  /// In en, this message translates to:
  /// **'Fronter'**
  String get frontingFronter;

  /// Dialog title warning about a very short session
  ///
  /// In en, this message translates to:
  /// **'Short Session'**
  String get frontingShortSessionTitle;

  /// Dialog message warning about a very short session
  ///
  /// In en, this message translates to:
  /// **'This session is less than a minute long. Save anyway?'**
  String get frontingShortSessionMessage;

  /// Dialog title warning about a duplicate session
  ///
  /// In en, this message translates to:
  /// **'Duplicate Session'**
  String get frontingDuplicateSessionTitle;

  /// Dialog message warning about duplicate sessions
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This session appears to be a duplicate of 1 other session. Save anyway?} other{This session appears to be a duplicate of {count} other sessions. Save anyway?}}'**
  String frontingDuplicateSessionMessage(int count);

  /// Confirm button label on duplicate session dialog
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get frontingSaveAnyway;

  /// Error toast when saving a session fails
  ///
  /// In en, this message translates to:
  /// **'Error saving session: {error}'**
  String frontingErrorSavingSession(Object error);

  /// Floating button label on active session detail to end the session
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get frontingEndSessionButton;

  /// Toast confirming a fronting session was ended
  ///
  /// In en, this message translates to:
  /// **'Ended {member}\'s session'**
  String frontingEndSessionEndedToast(String member);

  /// Title of dialog shown when ending the only active session
  ///
  /// In en, this message translates to:
  /// **'Who\'s fronting next?'**
  String get frontingNextFronterTitle;

  /// Body of next-fronter dialog
  ///
  /// In en, this message translates to:
  /// **'No one will be fronting after this.'**
  String get frontingNextFronterBody;

  /// Dialog action: open the new-front sheet
  ///
  /// In en, this message translates to:
  /// **'Pick a fronter'**
  String get frontingNextFronterPick;

  /// Dialog action: start an Unknown sentinel front
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get frontingNextFronterUnknown;

  /// Dialog action: end the session, leave no one fronting
  ///
  /// In en, this message translates to:
  /// **'End without fronting'**
  String get frontingNextFronterEnd;

  /// Tooltip on edit button in session detail screen
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get frontingSessionDetailEditTooltip;

  /// Tooltip on delete button in session detail screen
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get frontingSessionDetailDeleteTooltip;

  /// Substituted for the end time when a period is still open-ended (e.g. '10:00 AM – ongoing').
  ///
  /// In en, this message translates to:
  /// **'ongoing'**
  String get frontingPeriodOngoing;

  /// Fallback name displayed in place of a member name when the member cannot be resolved.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get frontingPeriodMemberUnknown;

  /// Section header for the co-fronters list on the period detail screen.
  ///
  /// In en, this message translates to:
  /// **'Fronters'**
  String get frontingPeriodCoFrontersTitle;

  /// Section header for brief visitors on the period detail screen.
  ///
  /// In en, this message translates to:
  /// **'Briefly joined'**
  String get frontingPeriodBrieflyJoinedTitle;

  /// Section header for always-present members on the period detail screen.
  ///
  /// In en, this message translates to:
  /// **'Always present'**
  String get frontingPeriodAlwaysPresentTitle;

  /// Subtitle on a brief-visitor row showing duration and start time.
  ///
  /// In en, this message translates to:
  /// **'joined for {dur} at {start}'**
  String frontingPeriodBriefVisitSubtitle(String dur, String start);

  /// Screen-reader-only Semantics label for the period detail header card.
  ///
  /// In en, this message translates to:
  /// **'Period: {names}, fronting from {start} to {end}, duration {duration}'**
  String frontingPeriodHeaderSemantic(
    String names,
    String start,
    String end,
    String duration,
  );

  /// Semantics label for an active co-fronter row on the period detail screen.
  ///
  /// In en, this message translates to:
  /// **'{name}, fronting since {start}, currently fronting. Double tap to view details.'**
  String frontingPeriodCoFronterSemanticActive(String name, String start);

  /// Semantics label for a closed co-fronter row on the period detail screen.
  ///
  /// In en, this message translates to:
  /// **'{name}, fronting from {start} to {end}, duration {duration}. Double tap to view details.'**
  String frontingPeriodCoFronterSemanticClosed(
    String name,
    String start,
    String end,
    String duration,
  );

  /// Semantics label for a brief-visitor row on the period detail screen.
  ///
  /// In en, this message translates to:
  /// **'{name}, briefly joined for {dur} at {start}. Double tap to view details.'**
  String frontingPeriodBriefVisitorSemantic(
    String name,
    String dur,
    String start,
  );

  /// Semantics label for an always-present member row on the period detail screen.
  ///
  /// In en, this message translates to:
  /// **'{name}, always present. Double tap to view profile.'**
  String frontingPeriodAlwaysPresentSemantic(String name);

  /// Joins exactly two member names with a conjunction ('Sky & Fern'). Translators replace '&' with the locale's equivalent (e.g. 'y' in Spanish).
  ///
  /// In en, this message translates to:
  /// **'{a} & {b}'**
  String memberListJoinPair(String a, String b);

  /// Joins a pre-comma-joined list of all-but-last names with the final name ('Sky, Fern & Aimee'). {items} is the comma-joined prefix; {last} is the final name. Translators replace '&' with the locale's conjunction.
  ///
  /// In en, this message translates to:
  /// **'{items} & {last}'**
  String memberListJoinAnd(String items, String last);

  /// Title on sleep session detail when session is still active
  ///
  /// In en, this message translates to:
  /// **'Sleeping now'**
  String get frontingSleepingNow;

  /// Title on sleep session detail when session has ended
  ///
  /// In en, this message translates to:
  /// **'Sleep session'**
  String get frontingSleepSession;

  /// Label for the started time row in session detail
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get frontingInfoStarted;

  /// Label for the ended time row in session detail
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get frontingInfoEnded;

  /// Label for the duration row in session detail
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get frontingInfoDuration;

  /// Value shown in session detail ended row when session is still active
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get frontingInfoActive;

  /// Label for the quality row in sleep session detail
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get frontingInfoQuality;

  /// Value shown when sleep quality has not been rated
  ///
  /// In en, this message translates to:
  /// **'Unrated'**
  String get frontingInfoQualityUnrated;

  /// Section header for time info in session detail
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get frontingTimeSection;

  /// Section header for confidence in session detail
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get frontingConfidenceSection;

  /// Section header for notes in session detail
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get frontingNotesSection;

  /// Section header for co-fronters in session detail
  ///
  /// In en, this message translates to:
  /// **'Fronters'**
  String get frontingCoFrontersSection;

  /// Headline on the active sleep mode card
  ///
  /// In en, this message translates to:
  /// **'Sleeping'**
  String get frontingSleepingLabel;

  /// Subtitle on sleep mode card showing when sleep started
  ///
  /// In en, this message translates to:
  /// **'Since {time}'**
  String frontingSleepSince(String time);

  /// Button label on sleep mode card to end sleep
  ///
  /// In en, this message translates to:
  /// **'Wake Up'**
  String get frontingWakeUp;

  /// Sleep quality label when no rating has been given
  ///
  /// In en, this message translates to:
  /// **'Sleep Quality: Unrated'**
  String get frontingSleepQualityUnrated;

  /// Sleep quality label with a rating
  ///
  /// In en, this message translates to:
  /// **'Sleep Quality: {label}'**
  String frontingSleepQualityRated(String label);

  /// Semantics label for a star rating button on sleep mode card
  ///
  /// In en, this message translates to:
  /// **'Rate sleep as {label}'**
  String frontingRateSleepAs(String label);

  /// Sleep quality label when not rated
  ///
  /// In en, this message translates to:
  /// **'Not rated'**
  String get sleepQualityNotRated;

  /// Sleep quality label: very poor
  ///
  /// In en, this message translates to:
  /// **'Very Poor'**
  String get sleepQualityVeryPoor;

  /// Sleep quality label: poor
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get sleepQualityPoor;

  /// Sleep quality label: fair
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get sleepQualityFair;

  /// Sleep quality label: good
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get sleepQualityGood;

  /// Sleep quality label: excellent
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get sleepQualityExcellent;

  /// Tooltip on the bedtime reminder banner's close button
  ///
  /// In en, this message translates to:
  /// **'Dismiss until tomorrow'**
  String get sleepSuggestionBedtimeDismiss;

  /// Sheet title for starting a sleep session
  ///
  /// In en, this message translates to:
  /// **'Start Sleep'**
  String get frontingStartSleepTitle;

  /// Button label to start sleep
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get frontingStartButton;

  /// Hint text for notes field in start sleep sheet
  ///
  /// In en, this message translates to:
  /// **'Optional notes about this sleep...'**
  String get frontingStartSleepNotesHint;

  /// Error toast when starting a sleep session fails
  ///
  /// In en, this message translates to:
  /// **'Error starting sleep: {error}'**
  String frontingErrorStartingSleep(Object error);

  /// Sheet title for editing a sleep session
  ///
  /// In en, this message translates to:
  /// **'Edit Sleep'**
  String get frontingEditSleepTitle;

  /// Section label inside the edit sleep sheet
  ///
  /// In en, this message translates to:
  /// **'Sleep session'**
  String get frontingEditSleepLabel;

  /// Toggle label for marking a sleep session as still active
  ///
  /// In en, this message translates to:
  /// **'Still Sleeping'**
  String get frontingStillSleeping;

  /// Subtitle on the Still Sleeping toggle
  ///
  /// In en, this message translates to:
  /// **'Leave the session open-ended'**
  String get frontingStillSleepingSubtitle;

  /// Label for the sleep quality dropdown in edit sleep sheet
  ///
  /// In en, this message translates to:
  /// **'Sleep quality'**
  String get frontingSleepQualityLabel;

  /// Hint text for notes field in edit sleep sheet
  ///
  /// In en, this message translates to:
  /// **'Optional notes about this sleep...'**
  String get frontingEditSleepNotesHint;

  /// Error toast when end time is not after start time
  ///
  /// In en, this message translates to:
  /// **'End time must be after start time.'**
  String get frontingEndTimeMustBeAfterStart;

  /// Error toast when saving a sleep session fails
  ///
  /// In en, this message translates to:
  /// **'Error saving sleep session: {error}'**
  String frontingErrorSavingSleepSession(Object error);

  /// Section header for comments in session detail
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get frontingCommentsTitle;

  /// Tooltip on the add comment button in session detail
  ///
  /// In en, this message translates to:
  /// **'Add comment'**
  String get frontingAddCommentTooltip;

  /// Empty state for comments section in session detail
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get frontingNoCommentsYet;

  /// Sheet title when adding a new comment
  ///
  /// In en, this message translates to:
  /// **'Add Comment'**
  String get frontingAddCommentTitle;

  /// Sheet title when editing an existing comment
  ///
  /// In en, this message translates to:
  /// **'Edit Comment'**
  String get frontingEditCommentTitle;

  /// Hint text for comment body field
  ///
  /// In en, this message translates to:
  /// **'Write your comment...'**
  String get frontingCommentHint;

  /// Confirmation dialog title for deleting a comment
  ///
  /// In en, this message translates to:
  /// **'Delete comment?'**
  String get frontingDeleteCommentTitle;

  /// Confirmation dialog message for deleting a comment
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get frontingDeleteCommentMessage;

  /// Label for the jump-to-date control in timeline view
  ///
  /// In en, this message translates to:
  /// **'Jump to date'**
  String get frontingTimelineJumpToDate;

  /// Tooltip for the today button in timeline controls
  ///
  /// In en, this message translates to:
  /// **'Jump to now'**
  String get frontingTimelineJumpToNow;

  /// Tooltip for zoom out button in timeline controls
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get frontingTimelineZoomOut;

  /// Tooltip for zoom in button in timeline controls
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get frontingTimelineZoomIn;

  /// Empty state title in timeline view
  ///
  /// In en, this message translates to:
  /// **'No fronting history'**
  String get frontingTimelineNoHistory;

  /// Empty state subtitle in timeline view
  ///
  /// In en, this message translates to:
  /// **'Start a fronting session to see it appear on the timeline.'**
  String get frontingTimelineNoHistorySubtitle;

  /// Screen-reader label for the floating active date chip in timeline view
  ///
  /// In en, this message translates to:
  /// **'Timeline position, {date}'**
  String frontingTimelinePositionLabel(String date);

  /// Dialog title when choosing a delete strategy for a session
  ///
  /// In en, this message translates to:
  /// **'What should happen to this time?'**
  String get frontingDeleteStrategyTitle;

  /// Badge shown on the recommended delete strategy
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get frontingDeleteStrategyRecommended;

  /// Dialog title when editing would create timeline gaps
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Gap detected} other{Gaps detected}}'**
  String frontingGapDetectedTitle(int count);

  /// Dialog message when editing would create timeline gaps
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This edit would create a gap totaling {total}.} other{This edit would create {count} gaps totaling {total}.}}'**
  String frontingGapDetectedMessage(int count, String total);

  /// Gap resolution option: fill with unknown fronter
  ///
  /// In en, this message translates to:
  /// **'Fill with unknown fronter'**
  String get frontingGapFillWithUnknown;

  /// Subtitle for fill-with-unknown gap resolution option
  ///
  /// In en, this message translates to:
  /// **'Create unknown sessions to cover the gaps.'**
  String get frontingGapFillWithUnknownSubtitle;

  /// Gap resolution option: leave the gaps as-is
  ///
  /// In en, this message translates to:
  /// **'Leave gaps'**
  String get frontingGapLeaveGaps;

  /// Subtitle for leave-gaps resolution option
  ///
  /// In en, this message translates to:
  /// **'Save without filling the gaps.'**
  String get frontingGapLeaveGapsSubtitle;

  /// Dialog title when the edited session overlaps others
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Overlap with 1 session} other{Overlap with {count} sessions}}'**
  String frontingOverlapTitle(int count);

  /// Overlap resolution option: trim conflicting sessions
  ///
  /// In en, this message translates to:
  /// **'Trim overlapping sessions'**
  String get frontingOverlapTrimOption;

  /// Subtitle for trim overlap resolution option
  ///
  /// In en, this message translates to:
  /// **'Shorten or remove sessions that conflict with your edit.'**
  String get frontingOverlapTrimSubtitle;

  /// Overlap resolution option: create co-fronting session
  ///
  /// In en, this message translates to:
  /// **'Create overlapping fronts'**
  String get frontingOverlapCoFrontOption;

  /// Subtitle for co-fronting overlap resolution option
  ///
  /// In en, this message translates to:
  /// **'Split the overlapping time into shared fronting segments.'**
  String get frontingOverlapCoFrontSubtitle;

  /// Confirmation dialog title when trimming would delete a session entirely
  ///
  /// In en, this message translates to:
  /// **'Remove Session'**
  String get frontingOverlapRemoveSessionTitle;

  /// Confirmation dialog message when trim would delete a session
  ///
  /// In en, this message translates to:
  /// **'This would remove a session entirely. Continue?'**
  String get frontingOverlapRemoveSessionMessage;

  /// Confirm button on the remove-session confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get frontingOverlapContinue;

  /// Section title for the timing mode setting
  ///
  /// In en, this message translates to:
  /// **'Timing Mode'**
  String get frontingTimingModeTitle;

  /// Timing mode option: Flexible
  ///
  /// In en, this message translates to:
  /// **'Flexible'**
  String get frontingTimingModeFlexible;

  /// Timing mode option: Strict
  ///
  /// In en, this message translates to:
  /// **'Strict'**
  String get frontingTimingModeStrict;

  /// Description shown when Flexible timing mode is selected
  ///
  /// In en, this message translates to:
  /// **'Small gaps (under 5 minutes) are allowed between sessions.'**
  String get frontingTimingModeFlexibleSubtitle;

  /// Description shown when Strict timing mode is selected
  ///
  /// In en, this message translates to:
  /// **'Sessions must be continuous with no gaps in the timeline.'**
  String get frontingTimingModeStrictSubtitle;

  /// Section header for custom fields on member detail screen
  ///
  /// In en, this message translates to:
  /// **'Custom Fields'**
  String get memberSectionCustomFields;

  /// Section header for fronting statistics on member detail screen
  ///
  /// In en, this message translates to:
  /// **'Fronting Stats'**
  String get memberSectionFrontingStats;

  /// Section header for recent fronting sessions on member detail screen
  ///
  /// In en, this message translates to:
  /// **'Fronting Sessions'**
  String get memberSectionRecentSessions;

  /// Button label on the member detail fronting sessions section that opens full history
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get memberSectionFrontingSessionsViewAll;

  /// Title for the full member session history screen
  ///
  /// In en, this message translates to:
  /// **'{member}\'s Sessions'**
  String memberFrontingHistoryTitle(String member);

  /// Empty state text for a member's full fronting history screen
  ///
  /// In en, this message translates to:
  /// **'No fronting sessions yet.'**
  String get memberFrontingHistoryEmpty;

  /// Toast shown when the member history go-to-day action cannot find sessions on the selected date
  ///
  /// In en, this message translates to:
  /// **'No fronting sessions found for that day.'**
  String get memberFrontingHistoryNoSessionsOnDate;

  /// Section header for conversations on member detail screen
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get memberSectionConversations;

  /// Section header for notes on member detail screen
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get memberSectionNotes;

  /// Section header shown above member bio/about field on detail screen
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get memberSectionBio;

  /// Section header for proxy tags on member surfaces
  ///
  /// In en, this message translates to:
  /// **'Proxy Tags'**
  String get memberSectionProxyTags;

  /// Subtitle explaining that proxy tags cannot be edited in Prism
  ///
  /// In en, this message translates to:
  /// **'Proxy tags are managed on PluralKit.'**
  String get memberProxyTagsManagedOnPk;

  /// Button label that opens the member's PluralKit dashboard page
  ///
  /// In en, this message translates to:
  /// **'Edit on PluralKit'**
  String get memberProxyTagsEditOnPk;

  /// Help text for local proxy tag editing on the member edit sheet and detail screen
  ///
  /// In en, this message translates to:
  /// **'Saved in Prism for chat proxy-tag authoring. Linked members sync with PluralKit when push sync is enabled.'**
  String get memberProxyTagsLocalDescription;

  /// Button label that opens Prism's local member editor for proxy tags
  ///
  /// In en, this message translates to:
  /// **'Edit proxy tags'**
  String get memberProxyTagsEditInPrism;

  /// Button label for adding a proxy tag row
  ///
  /// In en, this message translates to:
  /// **'Add proxy tag'**
  String get memberProxyTagsAdd;

  /// Tooltip and semantic label for removing a proxy tag row
  ///
  /// In en, this message translates to:
  /// **'Remove proxy tag'**
  String get memberProxyTagsRemove;

  /// Text field label for the proxy tag prefix
  ///
  /// In en, this message translates to:
  /// **'Prefix'**
  String get memberProxyTagPrefixLabel;

  /// Example proxy tag prefix hint
  ///
  /// In en, this message translates to:
  /// **'A:'**
  String get memberProxyTagPrefixHint;

  /// Text field label for the proxy tag suffix
  ///
  /// In en, this message translates to:
  /// **'Suffix'**
  String get memberProxyTagSuffixLabel;

  /// Example proxy tag suffix hint
  ///
  /// In en, this message translates to:
  /// **'-a'**
  String get memberProxyTagSuffixHint;

  /// Shown when a member has no proxy tags
  ///
  /// In en, this message translates to:
  /// **'No proxy tags set.'**
  String get memberProxyTagsEmpty;

  /// Subtitle on the proxy-tags summary row in the member edit sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None set} =1{1 tag} other{{count} tags}}'**
  String memberProxyTagsCount(int count);

  /// Subtitle on the custom-fields summary row in the member edit sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None set} =1{1 field} other{{count} fields}}'**
  String memberCustomFieldsCount(int count);

  /// Tooltip and semantic label for the back chevron in a member edit detail view
  ///
  /// In en, this message translates to:
  /// **'Back to edit {termSingularLower}'**
  String memberEditDetailBackTooltip(String termSingularLower);

  /// Tooltip for edit member button
  ///
  /// In en, this message translates to:
  /// **'Edit {termSingularLower}'**
  String memberEditTooltip(String termSingularLower);

  /// Tooltip for more options menu on member detail screen
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get memberMoreOptionsTooltip;

  /// Tooltip for add note button in notes section
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get memberAddNoteTooltip;

  /// Tooltip for save note button in note sheet
  ///
  /// In en, this message translates to:
  /// **'Save note'**
  String get memberSaveNoteTooltip;

  /// Tooltip for cancel selection button in system management screen
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get memberCancelSelectionTooltip;

  /// Tooltip for clear date button in custom fields date editor
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get memberClearDateTooltip;

  /// Tooltip for new group button
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get memberNewGroupTooltip;

  /// Toast shown when a member is added to a group
  ///
  /// In en, this message translates to:
  /// **'{term} added'**
  String memberAdded(String term);

  /// Toast shown when a member starts fronting
  ///
  /// In en, this message translates to:
  /// **'{name} is now fronting'**
  String memberIsFronting(String name);

  /// Toast shown when a member group is deleted
  ///
  /// In en, this message translates to:
  /// **'{name} deleted'**
  String memberGroupDeleted(String name);

  /// Toast shown when a member is activated
  ///
  /// In en, this message translates to:
  /// **'{name} activated'**
  String memberActivated(String name);

  /// Toast shown when a member is deactivated/archived
  ///
  /// In en, this message translates to:
  /// **'{name} archived'**
  String memberDeactivated(String name);

  /// Toast shown when a member is removed from a group
  ///
  /// In en, this message translates to:
  /// **'{name} removed'**
  String memberRemoved(String name);

  /// Dialog title when confirming removal of a member from a group
  ///
  /// In en, this message translates to:
  /// **'Remove {term}'**
  String memberRemoveFromGroupTitle(String term);

  /// Dialog message when removing a member from a group
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this group? The {termLower} will not be deleted.'**
  String memberRemoveFromGroupMessage(String name, String termLower);

  /// Empty state title on the groups screen
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get memberGroupEmptyList;

  /// Empty state subtitle on the groups screen
  ///
  /// In en, this message translates to:
  /// **'Create groups to organize {termPlural} in your {systemTermLower}'**
  String memberGroupEmptySubtitle(String termPlural, String systemTermLower);

  /// Empty state title in the desktop member detail pane when members exist but none is selected
  ///
  /// In en, this message translates to:
  /// **'Select a {termSingularLower}'**
  String memberSelectDetailPaneEmptyTitle(String termSingularLower);

  /// Empty state subtitle in the desktop member detail pane when members exist but none is selected
  ///
  /// In en, this message translates to:
  /// **'Choose a {termSingularLower} from the list to see their details here.'**
  String memberSelectDetailPaneEmptySubtitle(String termSingularLower);

  /// Empty state title inside a group detail screen
  ///
  /// In en, this message translates to:
  /// **'No {termPlural}'**
  String memberGroupNoMembers(String termPlural);

  /// Empty state subtitle inside a group detail screen
  ///
  /// In en, this message translates to:
  /// **'Add {termPlural} to this group'**
  String memberGroupNoMembersSubtitle(String termPlural);

  /// Empty state title in group detail when every member is inactive and the show-inactive toggle is off
  ///
  /// In en, this message translates to:
  /// **'All hidden by filter'**
  String get memberGroupAllInactiveHiddenTitle;

  /// Empty state subtitle in group detail when every member is inactive and the show-inactive toggle is off
  ///
  /// In en, this message translates to:
  /// **'All {termPlural} in this group are inactive. Turn on Show inactive to see them.'**
  String memberGroupAllInactiveHiddenSubtitle(String termPlural);

  /// Label for the inactive/archived filter chip in system management screen
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get memberArchived;

  /// Label for the active filter chip in system management screen
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get memberActive;

  /// Toast shown after reordering members
  ///
  /// In en, this message translates to:
  /// **'Order updated'**
  String get memberOrderUpdated;

  /// Section header for reorder options in the member list options menu
  ///
  /// In en, this message translates to:
  /// **'Reorder by'**
  String get memberReorderBy;

  /// Sort option: name ascending
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get memberSortNameAZ;

  /// Sort option: name descending
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get memberSortNameZA;

  /// Sort option: most recently created
  ///
  /// In en, this message translates to:
  /// **'Recently created'**
  String get memberSortRecentlyCreated;

  /// Sort option: most fronting sessions
  ///
  /// In en, this message translates to:
  /// **'Most fronting'**
  String get memberSortMostFronting;

  /// Sort option: fewest fronting sessions
  ///
  /// In en, this message translates to:
  /// **'Least fronting'**
  String get memberSortLeastFronting;

  /// Lock chip label on the group detail screen when sorted by name ascending
  ///
  /// In en, this message translates to:
  /// **'Name (A-Z)'**
  String get groupSortBadgeNameAsc;

  /// Lock chip label on the group detail screen when sorted by name descending
  ///
  /// In en, this message translates to:
  /// **'Name (Z-A)'**
  String get groupSortBadgeNameDesc;

  /// Lock chip label on the group detail screen when sorted by recently-added members
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get groupSortBadgeRecentDesc;

  /// Lock chip label on the group detail screen when in manual sort mode (chip is hidden in this mode; kept for completeness)
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get groupSortBadgeManual;

  /// Section header in the group detail options dropdown for locked-sort modes
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get groupSortSectionSortBy;

  /// Dialog title when choosing whether to sort only top-level groups or all group levels
  ///
  /// In en, this message translates to:
  /// **'Sort groups'**
  String get groupSortScopeTitle;

  /// Dialog message explaining the scope choice for one-shot group sorting
  ///
  /// In en, this message translates to:
  /// **'Apply this order to top-level groups only, or to each sub-group level too?'**
  String get groupSortScopeMessage;

  /// Dialog action that applies group sorting only to root-level groups
  ///
  /// In en, this message translates to:
  /// **'Top-level groups only'**
  String get groupSortScopeTopLevel;

  /// Dialog action that applies group sorting to every sortable group level
  ///
  /// In en, this message translates to:
  /// **'Groups and sub-groups'**
  String get groupSortScopeAllLevels;

  /// Menu item and dialog title for sorting members within a group
  ///
  /// In en, this message translates to:
  /// **'Sort {termPlural}'**
  String groupSortMembersAction(String termPlural);

  /// Menu item and dialog title for sorting immediate child groups
  ///
  /// In en, this message translates to:
  /// **'Sort sub-groups'**
  String get groupSortSubGroupsAction;

  /// Section header for persistent group member sort modes
  ///
  /// In en, this message translates to:
  /// **'Keep sorted by'**
  String get groupSortSectionKeepSorted;

  /// Section header for one-time group member ordering actions
  ///
  /// In en, this message translates to:
  /// **'Arrange once'**
  String get groupSortSectionApplyCurrent;

  /// Dropdown item: lock the group to sort members A-Z by name
  ///
  /// In en, this message translates to:
  /// **'Name A-Z'**
  String get groupSortItemNameAsc;

  /// Dropdown item: lock the group to sort members Z-A by name
  ///
  /// In en, this message translates to:
  /// **'Name Z-A'**
  String get groupSortItemNameDesc;

  /// Dropdown item: lock the group to show most-recently-added members first
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get groupSortItemRecentDesc;

  /// Dropdown item: switch the group back to manual drag-reorder mode
  ///
  /// In en, this message translates to:
  /// **'Sort manually'**
  String get groupSortItemManual;

  /// Dialog item: take a one-shot snapshot ordered by total fronting time, most first
  ///
  /// In en, this message translates to:
  /// **'Most-fronting first'**
  String get groupSortItemFrontingMost;

  /// Dialog item: take a one-shot snapshot ordered by total fronting time, least first
  ///
  /// In en, this message translates to:
  /// **'Least-fronting first'**
  String get groupSortItemFrontingLeast;

  /// Toast shown when a drag implicitly unlocks the group from a sorted mode
  ///
  /// In en, this message translates to:
  /// **'Switched to manual sort.'**
  String get groupSortSwitchedToManual;

  /// Screen-reader announcement shown when a drag implicitly unlocks the group from a sorted mode
  ///
  /// In en, this message translates to:
  /// **'Group is now sorted manually.'**
  String get groupSortSwitchedToManualAnnouncement;

  /// Toast shown when a manual reorder collided with a concurrent remote add or remove
  ///
  /// In en, this message translates to:
  /// **'Members changed during your reorder. Your order has been merged.'**
  String get groupSortRecoveredFromConcurrentChanges;

  /// Tooltip on the drag handle next to a group member row
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get groupMemberDragHandleTooltip;

  /// Screen-reader label on the drag handle next to a group member row
  ///
  /// In en, this message translates to:
  /// **'Reorder member'**
  String get groupMemberDragHandleLabel;

  /// Screen-reader hint on the drag handle when the group is in manual sort mode
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder this member.'**
  String get groupMemberDragHandleHintManual;

  /// Screen-reader hint on the drag handle when the group is in a locked sort mode (drag implicitly unlocks)
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder. This will switch the group to manual order.'**
  String get groupMemberDragHandleHintSorted;

  /// Custom semantic action label: move this member up one position in the manual order
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get groupSortActionMoveUp;

  /// Custom semantic action label: move this member down one position in the manual order
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get groupSortActionMoveDown;

  /// Custom semantic action label: move this member to the first position in the manual order
  ///
  /// In en, this message translates to:
  /// **'Move to top'**
  String get groupSortActionMoveToTop;

  /// Custom semantic action label: move this member to the last position in the manual order
  ///
  /// In en, this message translates to:
  /// **'Move to bottom'**
  String get groupSortActionMoveToBottom;

  /// Screen-reader announcement after a custom move semantic action completes
  ///
  /// In en, this message translates to:
  /// **'Moved to position {position} of {total}'**
  String groupSortActionMoved(int position, int total);

  /// Toggle option to show inactive members
  ///
  /// In en, this message translates to:
  /// **'Show inactive'**
  String get memberShowInactive;

  /// Toggle option to hide inactive members
  ///
  /// In en, this message translates to:
  /// **'Hide inactive'**
  String get memberHideInactive;

  /// Label for total sessions stat row
  ///
  /// In en, this message translates to:
  /// **'Total sessions'**
  String get memberStatsTotalSessions;

  /// Label for total time stat row
  ///
  /// In en, this message translates to:
  /// **'Total time'**
  String get memberStatsTotalTime;

  /// Label for last fronted stat row
  ///
  /// In en, this message translates to:
  /// **'Last fronted'**
  String get memberStatsLastFronted;

  /// Relative date: today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get memberStatsToday;

  /// Relative date: yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get memberStatsYesterday;

  /// Relative date: N days ago
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String memberStatsDaysAgo(int count);

  /// Relative date: N weeks ago
  ///
  /// In en, this message translates to:
  /// **'{count} weeks ago'**
  String memberStatsWeeksAgo(int count);

  /// Label shown on an active fronting session tile
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get memberSessionActive;

  /// Session date label when the session started today
  ///
  /// In en, this message translates to:
  /// **'Today at {time}'**
  String memberSessionTodayAt(String time);

  /// Chip label shown when a member is currently fronting
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get memberFrontingChip;

  /// Chip label shown when a member has admin status
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get memberAdminChip;

  /// Chip label shown when a member is inactive
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get memberInactiveChip;

  /// Subtle footer label showing the date a member was added
  ///
  /// In en, this message translates to:
  /// **'Added {date}'**
  String memberAddedAtProfileFooterLabel(String date);

  /// Menu action to set this member as the current fronter
  ///
  /// In en, this message translates to:
  /// **'Set as fronter'**
  String get memberSetAsFronter;

  /// Title shown in the note sheet top bar
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get memberNoteTitle;

  /// Fallback title for a note with no title
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get memberNoteUntitled;

  /// Shown when a note cannot be found
  ///
  /// In en, this message translates to:
  /// **'Note not found'**
  String get memberNoteNotFound;

  /// Confirmation dialog title when deleting a note
  ///
  /// In en, this message translates to:
  /// **'Delete note?'**
  String get memberNoteDeleteTitle;

  /// Confirmation dialog message when deleting a note
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"? This action cannot be undone.'**
  String memberNoteDeleteMessage(String title);

  /// Empty state text in the notes section on member detail screen
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get memberNoteNoNotesYet;

  /// Subtitle for empty notes list state
  ///
  /// In en, this message translates to:
  /// **'Create notes to keep track of thoughts and observations'**
  String get memberNoteEmptySubtitle;

  /// Empty state title in the desktop notes detail pane when notes exist but none is selected
  ///
  /// In en, this message translates to:
  /// **'Select a note'**
  String get memberNoteSelectEmptyTitle;

  /// Empty state subtitle in the desktop notes detail pane when notes exist but none is selected
  ///
  /// In en, this message translates to:
  /// **'Choose a note from the list to view it here.'**
  String get memberNoteSelectEmptySubtitle;

  /// Hint text for the note title field
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get memberNoteTitleHint;

  /// Hint text for the note body field
  ///
  /// In en, this message translates to:
  /// **'Start writing...'**
  String get memberNoteBodyHint;

  /// Toolbar chip label when no headmate is assigned to a note
  ///
  /// In en, this message translates to:
  /// **'Add {termLower}'**
  String memberNoteAddHeadmate(String termLower);

  /// Confirmation dialog title when discarding unsaved note changes
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get memberNoteDiscardTitle;

  /// Confirmation dialog message when discarding unsaved note changes
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Are you sure you want to discard them?'**
  String get memberNoteDiscardMessage;

  /// Confirm button label for discarding note changes
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get memberNoteDiscardConfirm;

  /// Tooltip for the button that switches the note editor into rendered markdown preview mode
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get memberNotePreviewTooltip;

  /// Sheet title for headmate selection in note sheet
  ///
  /// In en, this message translates to:
  /// **'Choose {termSingular}'**
  String memberNoteChooseHeadmate(String termSingular);

  /// Semantics label for the note date chip
  ///
  /// In en, this message translates to:
  /// **'Note date, {date}. Tap to change'**
  String memberNoteDateSemantics(String date);

  /// Semantics label for the selected headmate chip in note sheet
  ///
  /// In en, this message translates to:
  /// **'{termSingular}: {name}. Tap to change'**
  String memberNoteMemberSemantics(String termSingular, String name);

  /// Semantics label for the note sheet headmate picker when nothing is selected
  ///
  /// In en, this message translates to:
  /// **'No {termLower} selected. Tap to choose'**
  String memberNoteNoHeadmateSemantics(String termLower);

  /// Hint text for the notes search field
  ///
  /// In en, this message translates to:
  /// **'Search notes…'**
  String get memberNoteSearchHint;

  /// Tooltip for the search icon in the notes top bar
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get memberNoteSearchNotes;

  /// Tooltip for the filter-by-member icon in the notes top bar
  ///
  /// In en, this message translates to:
  /// **'Filter by member'**
  String get memberNoteFilterByMember;

  /// Empty state title when notes exist but filters produce no results
  ///
  /// In en, this message translates to:
  /// **'No notes match your search'**
  String get memberNoteNoFilteredNotes;

  /// Empty state subtitle when notes exist but filters produce no results
  ///
  /// In en, this message translates to:
  /// **'Try a different search term or clear filters'**
  String get memberNoteNoFilteredNotesSubtitle;

  /// Action label to clear all active search and filter criteria
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get memberNoteClearFilters;

  /// Label for filter chip showing notes with no member assigned
  ///
  /// In en, this message translates to:
  /// **'No member'**
  String get memberNoteFilterNoMember;

  /// Toast shown when the member selected as a filter has been deleted
  ///
  /// In en, this message translates to:
  /// **'Filtered member was deleted'**
  String get memberNoteFilterMemberDeleted;

  /// Option to clear headmate selection in note sheet
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get memberSelectNone;

  /// Title for the groups screen
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get memberGroupsTitle;

  /// Error message on the groups screen
  ///
  /// In en, this message translates to:
  /// **'Error loading groups: {error}'**
  String memberGroupErrorLoading(Object error);

  /// Error message on the group detail screen
  ///
  /// In en, this message translates to:
  /// **'Error loading group: {error}'**
  String memberGroupErrorLoadingDetail(Object error);

  /// Message shown when a group cannot be found
  ///
  /// In en, this message translates to:
  /// **'Group not found'**
  String get memberGroupNotFound;

  /// Section label for sub-groups in group detail
  ///
  /// In en, this message translates to:
  /// **'Sub-groups'**
  String get memberGroupSubGroupsLabel;

  /// Section header for members inside a group detail screen
  ///
  /// In en, this message translates to:
  /// **'{termPlural}'**
  String memberGroupSectionMembers(String termPlural);

  /// Button label to start a chat with all members in a group
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
  String get memberGroupStartChat;

  /// Button label to add a member to a group
  ///
  /// In en, this message translates to:
  /// **'Add {termSingularLower}'**
  String memberGroupAddMember(String termSingularLower);

  /// Button label to create a new sub-group inside an existing group
  ///
  /// In en, this message translates to:
  /// **'Add sub-group'**
  String get memberGroupAddSubGroup;

  /// Button label to add a member to a group
  ///
  /// In en, this message translates to:
  /// **'Add to group'**
  String get memberGroupAddToGroup;

  /// No description provided for @memberGroupAddToGroupSemantics.
  ///
  /// In en, this message translates to:
  /// **'Add {name} to a group'**
  String memberGroupAddToGroupSemantics(String name);

  /// Confirmation dialog title when deleting a group
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get memberGroupDeleteTitle;

  /// Confirmation dialog message when deleting a group
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? {termPlural} will not be deleted.'**
  String memberGroupDeleteMessage(String name, String termPlural);

  /// Confirm button for group deletion dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get memberGroupDeleteConfirm;

  /// Subtitle in cascade delete sheet explaining sub-groups exist
  ///
  /// In en, this message translates to:
  /// **'This group has sub-groups. What should happen to them?'**
  String get memberGroupDeleteCascadeSubtitle;

  /// Option to promote sub-groups to root before deleting parent
  ///
  /// In en, this message translates to:
  /// **'Move sub-groups to top level'**
  String get memberGroupDeletePromote;

  /// Description for the promote option in cascade delete sheet
  ///
  /// In en, this message translates to:
  /// **'Sub-groups stay, just without a parent'**
  String get memberGroupDeletePromoteSubtitle;

  /// Option to recursively delete group and all sub-groups
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get memberGroupDeleteAll;

  /// Description for the delete-all option in cascade delete sheet
  ///
  /// In en, this message translates to:
  /// **'All sub-groups will also be deleted'**
  String get memberGroupDeleteAllSubtitle;

  /// Confirmation dialog title for recursive group delete
  ///
  /// In en, this message translates to:
  /// **'Delete sub-groups too?'**
  String get memberGroupDeleteAllConfirmTitle;

  /// Confirmation dialog message for recursive group delete
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{name}\" and all its sub-groups. {termPlural} will not be deleted.'**
  String memberGroupDeleteAllConfirmMessage(String name, String termPlural);

  /// Toast shown after sub-groups are promoted to root
  ///
  /// In en, this message translates to:
  /// **'Sub-groups moved to top level'**
  String get memberGroupPromoted;

  /// Sheet title when editing an existing group
  ///
  /// In en, this message translates to:
  /// **'Edit Group'**
  String get memberGroupEditTitle;

  /// Sheet title when creating a new group
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get memberGroupNewTitle;

  /// Label for the group name text field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get memberGroupNameLabel;

  /// Placeholder inside the name field on the group editor sheet.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get memberGroupNameHint;

  /// Validation error when group name is empty
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get memberGroupNameRequired;

  /// Label for the group description text field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get memberGroupDescriptionLabel;

  /// Tooltip for the button that opens the full-screen group description editor
  ///
  /// In en, this message translates to:
  /// **'Open description in full screen'**
  String get memberGroupDescriptionFullscreenTooltip;

  /// Tooltip for the button that opens the full-screen system description editor
  ///
  /// In en, this message translates to:
  /// **'Open description in full screen'**
  String get systemInfoDescriptionFullscreenTooltip;

  /// Hint text for the inline group description text field
  ///
  /// In en, this message translates to:
  /// **'What\'s this group about?'**
  String get memberGroupDescriptionHint;

  /// Label for the group color hex text field
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get memberGroupColorLabel;

  /// Option label when no color is selected for a group
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get memberGroupColorNone;

  /// Button label in the group color picker dialog to remove the selected color
  ///
  /// In en, this message translates to:
  /// **'Clear color'**
  String get memberGroupColorClear;

  /// Label on the remove-photo button below the group avatar tile in the editor sheet
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get memberGroupRemovePhoto;

  /// Toggle label in the group editor sheet that controls whether the group emoji is rendered as a badge on the avatar photo
  ///
  /// In en, this message translates to:
  /// **'Show emoji on avatar'**
  String get memberGroupShowEmojiOnAvatar;

  /// Error toast when saving a group fails
  ///
  /// In en, this message translates to:
  /// **'Error saving group: {error}'**
  String memberGroupErrorSaving(Object error);

  /// Label for parent group selector in create/edit sheet
  ///
  /// In en, this message translates to:
  /// **'Parent group'**
  String get memberGroupParentLabel;

  /// Placeholder when no parent group is selected
  ///
  /// In en, this message translates to:
  /// **'None (top level)'**
  String get memberGroupParentNone;

  /// Filter chip label to show all members (no group filter)
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get memberGroupFilterAll;

  /// Accessibility label for the group filter bar
  ///
  /// In en, this message translates to:
  /// **'Filter by group'**
  String get memberGroupFilterBarLabel;

  /// Filter chip label to show only members not in any group
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get memberGroupFilterUngrouped;

  /// Title for the members list view settings sheet and menu row
  ///
  /// In en, this message translates to:
  /// **'View Settings'**
  String get memberListViewSettingsTitle;

  /// Title for the dismissible members list banner that points users to View Settings. The term is the user's chosen singular member terminology, capitalized.
  ///
  /// In en, this message translates to:
  /// **'{term} view options'**
  String memberViewSettingsBannerTitle(String term);

  /// Body for the dismissible members list banner that points users to View Settings. The term is the user's chosen singular member terminology in lowercase.
  ///
  /// In en, this message translates to:
  /// **'Group and {term} view preferences can be adjusted in View Settings.'**
  String memberViewSettingsBannerMessage(String term);

  /// Section label for the show/hide groups toggle in view settings
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get memberShowGroupSectionsLabel;

  /// Toggle label for showing group structure in the members list
  ///
  /// In en, this message translates to:
  /// **'Show group sections'**
  String get memberShowGroupSectionsToggle;

  /// Description for the show group sections toggle
  ///
  /// In en, this message translates to:
  /// **'Organizes members into group headers or folders.'**
  String get memberShowGroupSectionsToggleDescription;

  /// Label for choosing how the members list is displayed
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get memberListViewModeLabel;

  /// Helper text explaining the members list sections/folders view mode choice
  ///
  /// In en, this message translates to:
  /// **'Sections shows groups expanded inline. Folders shows groups as rows you can open.'**
  String get memberListViewModeDescription;

  /// Segment label for the grouped section members list view
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get memberListViewModeGroupedSections;

  /// Segment label for the folder-style members list view
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get memberListViewModeFolders;

  /// Label for choosing whether grouped sections start open or closed
  ///
  /// In en, this message translates to:
  /// **'Default section state'**
  String get memberGroupedDefaultStateLabel;

  /// Helper text explaining the open/closed default section state choice
  ///
  /// In en, this message translates to:
  /// **'Choose whether group sections are expanded or collapsed when the members list opens.'**
  String get memberGroupedDefaultStateDescription;

  /// Segment label for grouped sections starting open
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get memberGroupedDefaultStateOpen;

  /// Segment label for grouped sections starting closed
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get memberGroupedDefaultStateClosed;

  /// Label for choosing which members appear below folders
  ///
  /// In en, this message translates to:
  /// **'Main list'**
  String get memberFolderVisibilityLabel;

  /// Helper text explaining the all/ungrouped folder visibility choice
  ///
  /// In en, this message translates to:
  /// **'All repeats every member below the folders. Ungrouped only shows members not in a folder.'**
  String get memberFolderVisibilityDescription;

  /// Segment label for showing all members below folders
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get memberFolderVisibilityAll;

  /// Segment label for showing only ungrouped members below folders
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get memberFolderVisibilityUngrouped;

  /// Section label for member list display preferences
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get memberListDisplayLabel;

  /// Toggle label for showing pronouns in member rows
  ///
  /// In en, this message translates to:
  /// **'Show pronouns'**
  String get memberShowPronounsToggle;

  /// Description for the member pronouns visibility toggle
  ///
  /// In en, this message translates to:
  /// **'Shows pronouns under names in member rows.'**
  String get memberShowPronounsToggleDescription;

  /// Label for members list direct front button settings
  ///
  /// In en, this message translates to:
  /// **'Front buttons'**
  String get memberFrontButtonsLabel;

  /// Helper text explaining member row front buttons
  ///
  /// In en, this message translates to:
  /// **'Show a direct front action next to each member in the list.'**
  String get memberFrontButtonsDescription;

  /// Toggle label for showing direct member row front buttons
  ///
  /// In en, this message translates to:
  /// **'Show front buttons'**
  String get memberFrontButtonsToggle;

  /// Toggle helper text for direct member row front buttons
  ///
  /// In en, this message translates to:
  /// **'Adds a front button to non-fronting member rows.'**
  String get memberFrontButtonsToggleDescription;

  /// Label for choosing what direct member row front buttons do
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get memberFrontButtonBehaviorLabel;

  /// Segment label for adding a member to front
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get memberFrontButtonBehaviorAdd;

  /// Segment label for replacing current fronters with a member
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get memberFrontButtonBehaviorReplace;

  /// Accessibility label for a member row button that adds a member to front
  ///
  /// In en, this message translates to:
  /// **'Add {memberName} to front'**
  String memberFrontButtonAddSemantic(String memberName);

  /// Accessibility label for a member row button that replaces current fronters with a member
  ///
  /// In en, this message translates to:
  /// **'Replace front with {memberName}'**
  String memberFrontButtonReplaceSemantic(String memberName);

  /// Accessibility term for a nested member group
  ///
  /// In en, this message translates to:
  /// **'sub-group'**
  String get memberGroupSubGroupSemantic;

  /// Accessibility phrase for a group member count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0 {no members} =1 {1 member} other {{count} members}}'**
  String memberGroupMemberCountSemantic(int count);

  /// Accessibility phrase for group rows that navigate into a group
  ///
  /// In en, this message translates to:
  /// **'opens group'**
  String get memberGroupOpenSemantic;

  /// Accessibility label on the avatar picker tile in the group editor sheet
  ///
  /// In en, this message translates to:
  /// **'Group photo. Tap to change.'**
  String get memberGroupAvatarPickerSemantic;

  /// Accessibility hint fragment appended to a group row label when the group has a photo
  ///
  /// In en, this message translates to:
  /// **'photo'**
  String get memberGroupRowPhotoSemantic;

  /// Tooltip for a drag handle that reorders list items
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// Toast shown when all group members are already fronting
  ///
  /// In en, this message translates to:
  /// **'All {termPluralLower} are already fronting'**
  String memberGroupFrontAllAlreadyFronting(
    String termPluralLower,
    Object termPlural,
  );

  /// No description provided for @memberGroupFrontAllInactive.
  ///
  /// In en, this message translates to:
  /// **'All {termPluralLower} in {name} are inactive. Front anyway?'**
  String memberGroupFrontAllInactive(String name, String termPluralLower);

  /// Button label to front all members in a group
  ///
  /// In en, this message translates to:
  /// **'Front as Group'**
  String get memberGroupFrontGroup;

  /// Confirmation dialog title when fronting all members in a group
  ///
  /// In en, this message translates to:
  /// **'Front as {name}?'**
  String memberGroupFrontGroupConfirmTitle(String name);

  /// Confirmation dialog body when fronting multiple members in a group
  ///
  /// In en, this message translates to:
  /// **'This will start fronting for {count} {termForCount}.'**
  String memberGroupFrontGroupConfirmMessage(int count, String termForCount);

  /// No description provided for @memberGroupFrontGroupSemantics.
  ///
  /// In en, this message translates to:
  /// **'Front all {termPluralLower} in {name}'**
  String memberGroupFrontGroupSemantics(String name, String termPluralLower);

  /// No description provided for @memberGroupFrontSomeAlreadyFronting.
  ///
  /// In en, this message translates to:
  /// **'{count} {termForCount} already fronting. Add the remaining {remaining}?'**
  String memberGroupFrontSomeAlreadyFronting(
    int count,
    String termForCount,
    int remaining,
  );

  /// Empty state message on the manage groups screen
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get memberGroupManageNoGroups;

  /// Action button label on the manage groups empty state
  ///
  /// In en, this message translates to:
  /// **'Create a group'**
  String get memberGroupManageNoGroupsAction;

  /// Title for the manage groups screen
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get memberGroupManageTitle;

  /// Hint text for the group search field in manage groups sheet
  ///
  /// In en, this message translates to:
  /// **'Search groups'**
  String get memberGroupSearchHint;

  /// Empty state when group search yields no results
  ///
  /// In en, this message translates to:
  /// **'No groups found'**
  String get memberGroupSearchEmpty;

  /// Member count label for a group row, using the system's terminology
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 {singularLower}} other{{count} {pluralLower}}}'**
  String memberCount(int count, String singularLower, String pluralLower);

  /// Label for the member name text field (required)
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get memberNameLabel;

  /// Hint text for the member name field
  ///
  /// In en, this message translates to:
  /// **'Enter name'**
  String get memberNameHint;

  /// Validation error when member name is empty
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get memberNameRequired;

  /// Label for the member pronouns text field
  ///
  /// In en, this message translates to:
  /// **'Pronouns'**
  String get memberPronounsLabel;

  /// Hint text for the member pronouns field
  ///
  /// In en, this message translates to:
  /// **'e.g. she/her, they/them'**
  String get memberPronounsHint;

  /// Label for the member age text field
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get memberAgeLabel;

  /// Hint text for the member age field
  ///
  /// In en, this message translates to:
  /// **'e.g. ageless, middle, 27'**
  String get memberAgeHint;

  /// Label for the member bio text field
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get memberBioLabel;

  /// Hint text for the member bio field
  ///
  /// In en, this message translates to:
  /// **'A short description...'**
  String get memberBioHint;

  /// Tooltip for the button that opens the full-screen bio editor
  ///
  /// In en, this message translates to:
  /// **'Edit bio'**
  String get memberBioEditorTooltip;

  /// Tooltip for the button that switches the full-screen markdown editor into rendered preview mode
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get memberBioPreviewTooltip;

  /// Label for the Prism-only member full name text field
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get memberDisplayNameLabel;

  /// Hint text for the Prism-only member full name field
  ///
  /// In en, this message translates to:
  /// **''**
  String get memberDisplayNameHint;

  /// Label for the PluralKit-synced member display name text field
  ///
  /// In en, this message translates to:
  /// **'PluralKit Display Name'**
  String get memberPluralKitDisplayNameLabel;

  /// Hint text for the PluralKit-synced member display name field
  ///
  /// In en, this message translates to:
  /// **'Synced with PluralKit when connected'**
  String get memberPluralKitDisplayNameHint;

  /// Label for the member birthday field
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get memberBirthdayLabel;

  /// Placeholder text when no birthday is set
  ///
  /// In en, this message translates to:
  /// **'Tap to set a date'**
  String get memberBirthdayHint;

  /// Toggle label to hide the birth year
  ///
  /// In en, this message translates to:
  /// **'Hide year'**
  String get memberBirthdayHideYear;

  /// Subtitle for the hide-year toggle
  ///
  /// In en, this message translates to:
  /// **'Show only the month and day'**
  String get memberBirthdayHideYearSubtitle;

  /// Action to clear the birthday value
  ///
  /// In en, this message translates to:
  /// **'Clear birthday'**
  String get memberBirthdayClear;

  /// Label for member creation date field
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get memberCreatedAtLabel;

  /// Hint text for empty creation date field
  ///
  /// In en, this message translates to:
  /// **'Tap to set a date'**
  String get memberCreatedAtHint;

  /// Tooltip for clearing the creation date
  ///
  /// In en, this message translates to:
  /// **'Clear creation date'**
  String get memberCreatedAtClear;

  /// Section header for birthday on the member detail screen
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get memberSectionBirthday;

  /// Switch label: format bio as markdown
  ///
  /// In en, this message translates to:
  /// **'Format bio as markdown'**
  String get memberMarkdownTitle;

  /// Switch subtitle: format bio as markdown
  ///
  /// In en, this message translates to:
  /// **'Render bio text with markdown formatting'**
  String get memberMarkdownSubtitle;

  /// Switch label: admin status
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get memberAdminTitle;

  /// Switch subtitle: admin status
  ///
  /// In en, this message translates to:
  /// **'Admins can manage shared settings'**
  String get memberAdminSubtitle;

  /// Switch label: mark this member as always fronting
  ///
  /// In en, this message translates to:
  /// **'Always fronting'**
  String get memberAlwaysFrontingTitle;

  /// Switch subtitle: always-fronting opt-in
  ///
  /// In en, this message translates to:
  /// **'Keep an ongoing fronting session for this {termSingularLower}. They stay pinned separately and do not appear in regular fronting stacks.'**
  String memberAlwaysFrontingSubtitle(String termSingularLower);

  /// Dialog title shown when turning off Always fronting while the member has an active fronting session
  ///
  /// In en, this message translates to:
  /// **'End current front?'**
  String get memberAlwaysFrontingEndPromptTitle;

  /// Dialog body shown when turning off Always fronting while the member has an active fronting session
  ///
  /// In en, this message translates to:
  /// **'Turn off Always fronting for {memberName} and keep their current front active, or end it now?'**
  String memberAlwaysFrontingEndPromptMessage(String memberName);

  /// Dialog action: turn off Always fronting but leave the current fronting session active
  ///
  /// In en, this message translates to:
  /// **'Keep fronting'**
  String get memberAlwaysFrontingKeepFronting;

  /// Dialog action: turn off Always fronting and end the current fronting session
  ///
  /// In en, this message translates to:
  /// **'End front'**
  String get memberAlwaysFrontingEndFront;

  /// Section heading for the member accent color controls
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get memberAccentColorSectionTitle;

  /// Switch label: custom color
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get memberCustomColorTitle;

  /// Switch subtitle: custom color
  ///
  /// In en, this message translates to:
  /// **'Use a personal color for this {termSingularLower}'**
  String memberCustomColorSubtitle(String termSingularLower);

  /// Label for the member color hex text field
  ///
  /// In en, this message translates to:
  /// **'Color hex'**
  String get memberColorHexLabel;

  /// Error toast when saving a member fails
  ///
  /// In en, this message translates to:
  /// **'Error saving {term}: {error}'**
  String memberErrorSaving(String term, Object error);

  /// Toast when a member is saved successfully but one custom field write failed. The field stays dirty so the user can retry.
  ///
  /// In en, this message translates to:
  /// **'Saved, but couldn\'t save {fieldName} — try again.'**
  String memberSavePartialFailureSingle(String fieldName);

  /// Toast when a member is saved successfully but multiple custom field writes failed. The fields stay dirty so the user can retry.
  ///
  /// In en, this message translates to:
  /// **'Saved, but couldn\'t save {count} fields — try again.'**
  String memberSavePartialFailureMultiple(int count);

  /// Toast shown when form validation fails AND custom field edits are still staged. Reassures the user that their custom field work was not lost.
  ///
  /// In en, this message translates to:
  /// **'Your custom field changes are still pending — fix the errors above and tap Save.'**
  String get memberCustomFieldsPendingNote;

  /// Age displayed on member detail screen
  ///
  /// In en, this message translates to:
  /// **'Age {age}'**
  String memberAgeDisplay(String age);

  /// Bulk selection count label in system management screen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String memberSelectedCount(int count);

  /// Tooltip and semantics label for confirming selected members in the member search sheet
  ///
  /// In en, this message translates to:
  /// **'Confirm selected {termPluralLower}'**
  String memberSearchConfirmSelectionTooltip(String termPluralLower);

  /// Tooltip and semantics label for saving a member from the add/edit member sheet
  ///
  /// In en, this message translates to:
  /// **'Save {termSingularLower}'**
  String memberSaveTooltip(String termSingularLower);

  /// Tab label for the data/identity editing tab in the member edit sheet
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get memberEditTabEdit;

  /// Tab label for the appearance/style editing tab in the member edit sheet
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get memberEditTabStyle;

  /// Section header in the Edit tab for profile fields (pronouns, age, birthday, bio)
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get memberEditSectionAbout;

  /// Section header in the Edit tab for behavior toggles (markdown, admin)
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get memberEditSectionSettings;

  /// Bulk action button: activate selected members
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get memberBulkActivate;

  /// Bulk action button: deactivate selected members
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get memberBulkDeactivate;

  /// Empty state when there are no inactive members
  ///
  /// In en, this message translates to:
  /// **'No inactive {terms}'**
  String memberNoInactive(String terms);

  /// Empty state when there are no active members
  ///
  /// In en, this message translates to:
  /// **'No active {terms}'**
  String memberNoActive(String terms);

  /// Fallback title for a conversation with no title or emoji
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get memberConversationFallback;

  /// Placeholder text when no date is selected in a custom field date input
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get memberCustomFieldSelectDate;

  /// Hint text for a custom field text input
  ///
  /// In en, this message translates to:
  /// **'Enter {fieldName}'**
  String memberCustomFieldEnterHint(String fieldName);

  /// Chat tab title
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// Button to create a new conversation
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get chatNewConversation;

  /// Tooltip for manage categories button
  ///
  /// In en, this message translates to:
  /// **'Manage categories'**
  String get chatManageCategories;

  /// Tooltip for search messages button
  ///
  /// In en, this message translates to:
  /// **'Search messages'**
  String get chatSearchMessages;

  /// Chats tab segmented control option: direct messages
  ///
  /// In en, this message translates to:
  /// **'Direct Messages'**
  String get chatTabDirectMessages;

  /// Chats tab segmented control option: group chats
  ///
  /// In en, this message translates to:
  /// **'Group Chats'**
  String get chatTabGroupChats;

  /// Semantic label for the DM segment unread badge
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread direct message} other{{count} unread direct messages}}'**
  String chatUnreadDmsBadge(int count);

  /// Semantic label for the Group Chats segment unread badge
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread group chat} other{{count} unread group chats}}'**
  String chatUnreadGroupsBadge(int count);

  /// Empty state title when there are no conversations
  ///
  /// In en, this message translates to:
  /// **'No conversations'**
  String get chatNoConversations;

  /// Empty state subtitle when there are no conversations
  ///
  /// In en, this message translates to:
  /// **'Start chatting with your {systemTermLower}'**
  String chatNoConversationsSubtitle(String systemTermLower);

  /// Empty state title when the direct messages tab is empty
  ///
  /// In en, this message translates to:
  /// **'No direct messages'**
  String get chatNoDirectMessages;

  /// Empty state subtitle when the direct messages tab is empty
  ///
  /// In en, this message translates to:
  /// **'Start a one-on-one conversation'**
  String get chatNoDirectMessagesSubtitle;

  /// Empty state title when the group chats tab is empty
  ///
  /// In en, this message translates to:
  /// **'No group chats'**
  String get chatNoGroupChats;

  /// Empty state subtitle when the group chats tab is empty
  ///
  /// In en, this message translates to:
  /// **'Start a group conversation'**
  String get chatNoGroupChatsSubtitle;

  /// Empty state title in the desktop chat detail pane when conversations exist but none is selected
  ///
  /// In en, this message translates to:
  /// **'Select a conversation'**
  String get chatSelectConversationEmptyTitle;

  /// Empty state subtitle in the desktop chat detail pane when conversations exist but none is selected
  ///
  /// In en, this message translates to:
  /// **'Choose a conversation from the list to read it here.'**
  String get chatSelectConversationEmptySubtitle;

  /// Error message when conversations fail to load
  ///
  /// In en, this message translates to:
  /// **'Error loading conversations'**
  String get chatErrorLoadingConversations;

  /// Section header for group chats the viewer can see only via the admin moderation override
  ///
  /// In en, this message translates to:
  /// **'Admin · Not a member'**
  String get chatAdminNonParticipantSection;

  /// Title for the dismissible chat-tab notice explaining upgraded group chat visibility
  ///
  /// In en, this message translates to:
  /// **'Some group chats are visible to everyone'**
  String get chatGroupVisibilityNudgeTitle;

  /// Body for the dismissible chat-tab notice explaining where group chat visibility can be changed
  ///
  /// In en, this message translates to:
  /// **'You can change this in Conversation Details.'**
  String get chatGroupVisibilityNudgeMessage;

  /// Gentle banner shown in the chat list when nobody is fronting and no speaking-as member is picked
  ///
  /// In en, this message translates to:
  /// **'Pick a member from the speaker chip to see your chats.'**
  String get chatPickSpeakerBanner;

  /// Banner shown in a group conversation when an admin can view and moderate but is not a participant
  ///
  /// In en, this message translates to:
  /// **'Viewing as admin. Posting is disabled.'**
  String get chatAdminReadOnlyBanner;

  /// Label for conversations without a category
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get chatUncategorized;

  /// Context menu action to mark a conversation as read
  ///
  /// In en, this message translates to:
  /// **'Mark as Read'**
  String get chatMarkAsRead;

  /// App bar menu action to mark all conversations as read
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get chatMarkAllAsRead;

  /// Context menu action to mute a conversation
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get chatMute;

  /// Context menu action to unmute a conversation
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get chatUnmute;

  /// Dialog title when deleting a conversation
  ///
  /// In en, this message translates to:
  /// **'Delete Conversation'**
  String get chatDeleteConversationTitle;

  /// Dialog message when deleting a conversation from the list
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this conversation? All messages will be permanently removed.'**
  String get chatDeleteConversationMessage;

  /// Full dialog message when deleting a conversation from info sheet
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this conversation? All messages will be permanently removed. This cannot be undone.'**
  String get chatDeleteConversationFullMessage;

  /// Tooltip for badge mode: mentions only
  ///
  /// In en, this message translates to:
  /// **'Badge: mentions only'**
  String get chatBadgeMentionsOnly;

  /// Tooltip for badge mode: all messages
  ///
  /// In en, this message translates to:
  /// **'Badge: all messages'**
  String get chatBadgeAllMessages;

  /// Tooltip to hide archived conversations
  ///
  /// In en, this message translates to:
  /// **'Hide archived'**
  String get chatHideArchived;

  /// Tooltip to show archived conversations
  ///
  /// In en, this message translates to:
  /// **'Show archived'**
  String get chatShowArchived;

  /// Message when a conversation cannot be found
  ///
  /// In en, this message translates to:
  /// **'Conversation not found'**
  String get chatConversationNotFound;

  /// Tooltip for the conversation info button
  ///
  /// In en, this message translates to:
  /// **'Conversation info'**
  String get chatConversationInfo;

  /// Empty state when a conversation has no messages
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatNoMessages;

  /// Empty state subtitle encouraging user to send first message
  ///
  /// In en, this message translates to:
  /// **'Start the conversation!'**
  String get chatStartConversation;

  /// Error message when messages fail to load
  ///
  /// In en, this message translates to:
  /// **'Error loading messages: {error}'**
  String chatErrorLoadingMessages(Object error);

  /// Accessibility announcement when loading older messages
  ///
  /// In en, this message translates to:
  /// **'Loading older messages'**
  String get chatLoadingOlderMessages;

  /// Placeholder text in the chat search field
  ///
  /// In en, this message translates to:
  /// **'Search messages...'**
  String get chatSearchPlaceholder;

  /// Hint shown when the search field is empty
  ///
  /// In en, this message translates to:
  /// **'Find messages across your conversations'**
  String get chatSearchHint;

  /// Hint shown when the query is too short
  ///
  /// In en, this message translates to:
  /// **'Keep typing to search...'**
  String get chatSearchKeepTyping;

  /// Message when search returns no results
  ///
  /// In en, this message translates to:
  /// **'No messages found for \'{query}\''**
  String chatSearchNoResults(String query);

  /// Suggestion when search returns no results
  ///
  /// In en, this message translates to:
  /// **'Try fewer or different words'**
  String get chatSearchTryDifferent;

  /// Error message in search results
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String chatSearchError(Object error);

  /// Placeholder text in the message input field
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get chatMessagePlaceholder;

  /// Semantics label for the send message button when enabled
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get chatSendMessage;

  /// Semantics label for the send message button when disabled
  ///
  /// In en, this message translates to:
  /// **'Send message, disabled'**
  String get chatSendMessageDisabled;

  /// Screen-reader label and subtitle for broadcast mention autocomplete rows such as @everyone and @all.
  ///
  /// In en, this message translates to:
  /// **'Mention everyone in this chat'**
  String get chatMentionEveryoneSemantics;

  /// Title for the confirmation dialog shown before sending a broadcast chat mention.
  ///
  /// In en, this message translates to:
  /// **'Mention everyone in this chat?'**
  String get chatBroadcastMentionConfirmTitle;

  /// Body text for the confirmation dialog shown before sending a broadcast chat mention.
  ///
  /// In en, this message translates to:
  /// **'This will notify all {count} other participants in this chat.'**
  String chatBroadcastMentionConfirmMessage(int count);

  /// Semantics label for the record voice note button
  ///
  /// In en, this message translates to:
  /// **'Record voice note'**
  String get chatRecordVoiceNote;

  /// Semantics label for the speaking-as avatar button
  ///
  /// In en, this message translates to:
  /// **'Speaking as {name}. Tap to change.'**
  String chatSpeakingAs(String name);

  /// Semantics label for the speaking-as button when no member is selected
  ///
  /// In en, this message translates to:
  /// **'Choose speaking {termSingularLower}'**
  String chatChooseSpeakingMember(String termSingularLower);

  /// Tooltip/semantics for dismiss reply banner button
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get chatCancelReply;

  /// Title of the attachment picker sheet
  ///
  /// In en, this message translates to:
  /// **'Add Attachment'**
  String get chatAddAttachment;

  /// Attachment picker option: take photo with camera
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get chatCamera;

  /// Attachment picker option: choose from photo library
  ///
  /// In en, this message translates to:
  /// **'Photo Library'**
  String get chatPhotoLibrary;

  /// Context menu action: reply to a message
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get chatContextReply;

  /// Context menu action: copy message text
  ///
  /// In en, this message translates to:
  /// **'Copy Text'**
  String get chatContextCopyText;

  /// Context menu action: edit a message
  ///
  /// In en, this message translates to:
  /// **'Edit Message'**
  String get chatContextEditMessage;

  /// Context menu action: delete a message
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get chatContextDelete;

  /// Toast shown after copying message text
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get chatCopied;

  /// Dialog title for editing a message
  ///
  /// In en, this message translates to:
  /// **'Edit Message'**
  String get chatEditMessageTitle;

  /// Hint text in the edit message dialog
  ///
  /// In en, this message translates to:
  /// **'Message content'**
  String get chatMessageContentHint;

  /// Dialog title when deleting a message
  ///
  /// In en, this message translates to:
  /// **'Delete Message'**
  String get chatDeleteMessageTitle;

  /// Dialog message when deleting a message
  ///
  /// In en, this message translates to:
  /// **'This message will be permanently deleted.'**
  String get chatDeleteMessageMessage;

  /// Text shown in reply quote when original message is deleted
  ///
  /// In en, this message translates to:
  /// **'Original message deleted'**
  String get chatReplyQuoteDeleted;

  /// Semantics label for reply quote chip
  ///
  /// In en, this message translates to:
  /// **'Replying to {authorName}: {content}. Double-tap to scroll to message.'**
  String chatReplyQuoteSemantics(String authorName, String content);

  /// Semantics label for reply quote chip when original is deleted
  ///
  /// In en, this message translates to:
  /// **'Original message deleted'**
  String get chatReplyQuoteDeletedSemantics;

  /// Label shown on edited messages
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get chatMessageEdited;

  /// Long-press menu label for re-attributing a chat message to a different member.
  ///
  /// In en, this message translates to:
  /// **'Change author'**
  String get chatMessageChangeAuthor;

  /// Title for the member picker shown after tapping Change author in the message menu.
  ///
  /// In en, this message translates to:
  /// **'Set author'**
  String get chatMessageSetAuthorPickerTitle;

  /// Sheet title for conversation info when no title is set
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get chatInfoTitle;

  /// Label for conversation title field in info sheet
  ///
  /// In en, this message translates to:
  /// **'Conversation title'**
  String get chatInfoConversationTitle;

  /// Date the conversation was created
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String chatInfoCreatedAt(String date);

  /// Section header for participants list
  ///
  /// In en, this message translates to:
  /// **'Participants ({count})'**
  String chatInfoParticipants(int count);

  /// Tooltip for add members button in conversation info
  ///
  /// In en, this message translates to:
  /// **'Add {termPluralLower}'**
  String chatInfoAddMembers(String termPluralLower);

  /// Toggle title for include-everyone in conversation info
  ///
  /// In en, this message translates to:
  /// **'Include everyone'**
  String get chatInfoIncludeEveryone;

  /// Subtitle shown when include-everyone is on
  ///
  /// In en, this message translates to:
  /// **'All {count} active {termPluralLower}. New {termPluralLower} are added automatically.'**
  String chatInfoIncludeEveryoneOnSubtitle(int count, String termPluralLower);

  /// Subtitle shown when include-everyone is off
  ///
  /// In en, this message translates to:
  /// **'Only the {termPluralLower} listed below are in this chat.'**
  String chatInfoIncludeEveryoneOffSubtitle(String termPluralLower);

  /// Toast shown when include-everyone toggle fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change include-everyone: {error}'**
  String chatInfoIncludeEveryoneError(Object error);

  /// Role chip label for conversation owner
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get chatInfoOwner;

  /// Role chip label for admin member
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get chatInfoAdmin;

  /// Placeholder name for a member that could not be loaded
  ///
  /// In en, this message translates to:
  /// **'Unknown {termSingular}'**
  String chatInfoUnknownMember(String termSingular);

  /// Error text when a participant member fails to load
  ///
  /// In en, this message translates to:
  /// **'Error loading {termSingularLower}'**
  String chatInfoErrorLoadingMember(String termSingularLower);

  /// Label for the category picker row in conversation info
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get chatInfoCategory;

  /// Category picker option: no category
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get chatInfoCategoryNone;

  /// Semantics label for category picker
  ///
  /// In en, this message translates to:
  /// **'Category: {name}'**
  String chatInfoCategorySemantics(String name);

  /// Label shown when conversation is a DM and has no title
  ///
  /// In en, this message translates to:
  /// **'Direct Message'**
  String get chatInfoDirectMessage;

  /// Label shown when a group conversation has no title
  ///
  /// In en, this message translates to:
  /// **'Group Chat'**
  String get chatInfoGroupChat;

  /// Permission banner shown when the speaking member cannot manage the conversation
  ///
  /// In en, this message translates to:
  /// **'{memberName} can\'t manage this conversation'**
  String chatInfoCannotManage(String memberName);

  /// Action row to archive a conversation
  ///
  /// In en, this message translates to:
  /// **'Archive conversation'**
  String get chatInfoArchiveConversation;

  /// Action row to unarchive a conversation
  ///
  /// In en, this message translates to:
  /// **'Unarchive conversation'**
  String get chatInfoUnarchiveConversation;

  /// Action row to leave a conversation
  ///
  /// In en, this message translates to:
  /// **'Leave conversation'**
  String get chatInfoLeaveConversation;

  /// Action row to delete a conversation (destructive)
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get chatInfoDeleteConversation;

  /// Toast shown after archiving a conversation
  ///
  /// In en, this message translates to:
  /// **'Conversation archived'**
  String get chatInfoConversationArchived;

  /// Toast shown after unarchiving a conversation
  ///
  /// In en, this message translates to:
  /// **'Conversation unarchived'**
  String get chatInfoConversationUnarchived;

  /// Admin/creator action row to archive a conversation for every member at once (system-wide), shown alongside the per-member archive row
  ///
  /// In en, this message translates to:
  /// **'Archive for everyone'**
  String get chatInfoArchiveForEveryone;

  /// Admin/creator action row to clear a system-wide (for-everyone) archive
  ///
  /// In en, this message translates to:
  /// **'Unarchive for everyone'**
  String get chatInfoUnarchiveForEveryone;

  /// Non-interactive row shown to non-admin members when a conversation has been archived for everyone, so they understand why it is hidden
  ///
  /// In en, this message translates to:
  /// **'Archived for everyone'**
  String get chatInfoArchivedForEveryone;

  /// Subtitle explaining the effect of a for-everyone archive
  ///
  /// In en, this message translates to:
  /// **'Hidden from everyone\'s chat list'**
  String get chatInfoArchivedForEveryoneSubtitle;

  /// Toast shown after archiving a conversation for everyone
  ///
  /// In en, this message translates to:
  /// **'Archived for everyone'**
  String get chatInfoConversationArchivedForEveryone;

  /// Toast shown after clearing a for-everyone archive
  ///
  /// In en, this message translates to:
  /// **'Unarchived for everyone'**
  String get chatInfoConversationUnarchivedForEveryone;

  /// Toast when saving conversation title fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save title: {error}'**
  String chatInfoFailedSaveTitle(Object error);

  /// Toast when saving conversation emoji fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save emoji: {error}'**
  String chatInfoFailedSaveEmoji(Object error);

  /// Dialog title when leaving a conversation
  ///
  /// In en, this message translates to:
  /// **'Leave Conversation'**
  String get chatLeaveConversationTitle;

  /// Dialog message when leaving a conversation
  ///
  /// In en, this message translates to:
  /// **'Leave this conversation? Your past messages will remain.'**
  String get chatLeaveConversationMessage;

  /// Confirm button label when leaving a conversation
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get chatLeaveConversationConfirm;

  /// Dialog title for selecting a new conversation owner before leaving
  ///
  /// In en, this message translates to:
  /// **'Select new conversation owner'**
  String get chatSelectNewOwner;

  /// Sheet title for adding members to a conversation
  ///
  /// In en, this message translates to:
  /// **'Add {termPlural}'**
  String chatAddMembersTitle(String termPlural);

  /// Message when all members are already participants
  ///
  /// In en, this message translates to:
  /// **'All active {termPluralLower} are already in this conversation.'**
  String chatAddMembersAllAdded(String termPluralLower, Object termPlural);

  /// Toast when adding members fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add {termPluralLower}: {error}'**
  String chatAddMembersFailed(String termPluralLower, Object error);

  /// Sheet title for creating a new conversation
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get chatCreateTitle;

  /// Tooltip and semantics label for confirming conversation creation
  ///
  /// In en, this message translates to:
  /// **'Create conversation'**
  String get chatCreateConversationTooltip;

  /// Segmented control option: group conversation
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get chatCreateGroupTab;

  /// Segmented control option: direct message
  ///
  /// In en, this message translates to:
  /// **'Direct Message'**
  String get chatCreateDirectMessageTab;

  /// Label for the group name text field
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get chatCreateGroupName;

  /// Hint text for the group name text field
  ///
  /// In en, this message translates to:
  /// **'e.g., {systemTerm} Discussion'**
  String chatCreateGroupNameHint(String systemTerm);

  /// Header for participant selection in group chat creation
  ///
  /// In en, this message translates to:
  /// **'Select participants (2+)'**
  String get chatCreateSelectParticipants;

  /// Toggle to make every active member implicitly a participant of a group chat
  ///
  /// In en, this message translates to:
  /// **'Include everyone'**
  String get chatCreateIncludeEveryone;

  /// Subtitle under the include-everyone toggle
  ///
  /// In en, this message translates to:
  /// **'Every active {termPluralLower} is automatically a member, including any added later.'**
  String chatCreateIncludeEveryoneHint(String termPluralLower);

  /// Header for DM participant selection, showing current fronter
  ///
  /// In en, this message translates to:
  /// **'Message as {name} with:'**
  String chatCreateMessageAs(String name);

  /// Button to select all members
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get chatCreateSelectAll;

  /// Button to deselect all members
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get chatCreateDeselectAll;

  /// Message shown when no members exist for participant selection
  ///
  /// In en, this message translates to:
  /// **'No {termPluralLower} available. Create {termPluralLower} first.'**
  String chatCreateNoMembers(String termPluralLower);

  /// Chip label marking the currently fronting member
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get chatCreateFronting;

  /// Warning when the currently fronting member is not selected
  ///
  /// In en, this message translates to:
  /// **'{name} is currently fronting but not in this chat. You won\'t be able to see or send messages.'**
  String chatCreateFronterDeselectedWarning(String name);

  /// Toast when creating a conversation fails
  ///
  /// In en, this message translates to:
  /// **'Failed to create conversation: {error}'**
  String chatCreateFailed(Object error);

  /// Sheet title for category management
  ///
  /// In en, this message translates to:
  /// **'Manage Categories'**
  String get chatCategoriesTitle;

  /// Empty state when no categories exist
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get chatCategoriesNone;

  /// Hint text for new category name field
  ///
  /// In en, this message translates to:
  /// **'New category name'**
  String get chatCategoriesNewHint;

  /// Hint text for category name edit field
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get chatCategoriesCategoryNameHint;

  /// Tooltip for add category button
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get chatCategoriesAddTooltip;

  /// Dialog title when deleting a category
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String chatCategoriesDeleteTitle(String name);

  /// Dialog message when deleting a category
  ///
  /// In en, this message translates to:
  /// **'Conversations in this category will become uncategorized.'**
  String get chatCategoriesDeleteMessage;

  /// Toast when creating a category fails
  ///
  /// In en, this message translates to:
  /// **'Failed to create category: {error}'**
  String chatCategoriesCreateFailed(Object error);

  /// Toast when renaming a category fails
  ///
  /// In en, this message translates to:
  /// **'Failed to rename category: {error}'**
  String chatCategoriesRenameFailed(Object error);

  /// Toast when deleting a category fails
  ///
  /// In en, this message translates to:
  /// **'Failed to delete category: {error}'**
  String chatCategoriesDeleteFailed(Object error);

  /// Text shown in speaking-as picker when no members exist
  ///
  /// In en, this message translates to:
  /// **'No {termPluralLower} available'**
  String chatNoMembersAvailable(String termPluralLower);

  /// Short error text in speaking-as picker
  ///
  /// In en, this message translates to:
  /// **'Error loading {termPluralLower}'**
  String chatErrorLoadingMembersShort(String termPluralLower);

  /// Sheet title for GIF picker
  ///
  /// In en, this message translates to:
  /// **'GIFs'**
  String get chatGifsTitle;

  /// Hint text in GIF search field
  ///
  /// In en, this message translates to:
  /// **'Search for GIFs'**
  String get chatGifsSearchHint;

  /// Attribution text in GIF picker
  ///
  /// In en, this message translates to:
  /// **'Powered by KLIPY'**
  String get chatGifsPoweredBy;

  /// Error message when GIFs fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load GIFs'**
  String get chatGifsLoadFailed;

  /// Empty state when GIF search returns no results
  ///
  /// In en, this message translates to:
  /// **'No GIFs found'**
  String get chatGifsNotFound;

  /// Subtitle for empty GIF search results
  ///
  /// In en, this message translates to:
  /// **'Try different search terms'**
  String get chatGifsNotFoundSubtitle;

  /// Title for the first-use GIF privacy disclosure dialog
  ///
  /// In en, this message translates to:
  /// **'Enable GIFs?'**
  String get chatGifConsentTitle;

  /// Intro text for the first-use GIF privacy disclosure dialog
  ///
  /// In en, this message translates to:
  /// **'GIFs use a relay-backed Klipy service. Here\'s what each side can and cannot see.'**
  String get chatGifConsentIntro;

  /// Section title describing relay visibility for GIF search
  ///
  /// In en, this message translates to:
  /// **'What Prism relay can see'**
  String get chatGifConsentRelayTitle;

  /// Section body describing relay visibility for GIF search
  ///
  /// In en, this message translates to:
  /// **'Your relay can see the GIF searches you send through it and your device\'s network metadata. It cannot see your encrypted chats.'**
  String get chatGifConsentRelayBody;

  /// Section title describing Klipy visibility for GIF search
  ///
  /// In en, this message translates to:
  /// **'What Klipy can see'**
  String get chatGifConsentKlipyTitle;

  /// Section body describing Klipy visibility for GIF search
  ///
  /// In en, this message translates to:
  /// **'Klipy receives the search request from the relay and can see the search terms plus the relay\'s network identity, not yours directly.'**
  String get chatGifConsentKlipyBody;

  /// Section title describing media loading visibility for GIFs
  ///
  /// In en, this message translates to:
  /// **'What happens when you open a GIF'**
  String get chatGifConsentMediaTitle;

  /// Section body describing media loading visibility for GIFs
  ///
  /// In en, this message translates to:
  /// **'GIF previews and playback still load from Klipy\'s media host, so opening a GIF can contact Klipy directly from your device.'**
  String get chatGifConsentMediaBody;

  /// Decline button label in the GIF consent dialog
  ///
  /// In en, this message translates to:
  /// **'No Thanks'**
  String get chatGifConsentDecline;

  /// Accept button label in the GIF consent dialog
  ///
  /// In en, this message translates to:
  /// **'Enable GIFs'**
  String get chatGifConsentEnable;

  /// Accessibility announcement for GIF search result count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 GIF found} other{{count} GIFs found}}'**
  String chatGifsFound(int count);

  /// Send button in GIF preview overlay
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatGifSendButton;

  /// Semantics label for GIF preview overlay
  ///
  /// In en, this message translates to:
  /// **'GIF preview: {description}. Send button below.'**
  String chatGifPreviewSemantics(String description);

  /// Semantics label for a GIF cell with content description
  ///
  /// In en, this message translates to:
  /// **'GIF: {description}'**
  String chatGifCellSemantics(String description);

  /// Semantics label for a GIF cell with no content description
  ///
  /// In en, this message translates to:
  /// **'GIF: search result'**
  String get chatGifCellSemanticsDefault;

  /// Text and semantics label for expired/unavailable media placeholder
  ///
  /// In en, this message translates to:
  /// **'Media no longer available'**
  String get chatMediaNoLongerAvailable;

  /// Semantics label for attachment thumbnail in compose area
  ///
  /// In en, this message translates to:
  /// **'Attached image preview'**
  String get chatAttachedImagePreview;

  /// Semantics label for remove attachment button
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get chatRemoveAttachment;

  /// Semantics label for clearing the chat search field
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get chatSearchClear;

  /// Semantics label for editing a conversation emoji
  ///
  /// In en, this message translates to:
  /// **'Edit conversation emoji'**
  String get chatInfoEditEmoji;

  /// Tooltip and semantics label for removing a conversation emoji
  ///
  /// In en, this message translates to:
  /// **'Clear conversation emoji'**
  String get chatInfoClearEmoji;

  /// Semantics label for editing a conversation title
  ///
  /// In en, this message translates to:
  /// **'Edit conversation title'**
  String get chatInfoEditTitle;

  /// Fallback semantics label for an image attachment
  ///
  /// In en, this message translates to:
  /// **'Image attachment'**
  String get chatImageAttachment;

  /// Semantics label while an image attachment is loading
  ///
  /// In en, this message translates to:
  /// **'Image attachment loading.'**
  String get chatImageLoading;

  /// Semantics label for an image attachment that opens the full-screen viewer
  ///
  /// In en, this message translates to:
  /// **'Image attachment. Double tap to view full screen.'**
  String get chatImageOpenFullScreen;

  /// Semantics label for toggling a quick reaction on a message
  ///
  /// In en, this message translates to:
  /// **'Toggle reaction {emoji}'**
  String chatMessageToggleReaction(String emoji);

  /// Semantics label for adding a custom reaction to a message
  ///
  /// In en, this message translates to:
  /// **'Add custom reaction'**
  String get chatMessageAddCustomReaction;

  /// Semantics label for toggling the time format on a message
  ///
  /// In en, this message translates to:
  /// **'Toggle time format'**
  String get chatMessageToggleTimeFormat;

  /// Semantics label for adding a reaction from the reaction bar
  ///
  /// In en, this message translates to:
  /// **'Add reaction {emoji}'**
  String chatReactionAdd(String emoji);

  /// Dialog title showing who reacted with a specific emoji
  ///
  /// In en, this message translates to:
  /// **'{emoji} Reactions'**
  String chatReactionSheetTitle(String emoji);

  /// Semantics label for voice note bubble
  ///
  /// In en, this message translates to:
  /// **'Voice note from message, {duration}'**
  String chatVoiceNoteSemantics(String duration);

  /// Semantics label for voice note while loading
  ///
  /// In en, this message translates to:
  /// **'Loading voice note, {duration}'**
  String chatVoiceNoteLoading(String duration);

  /// Semantics label for voice note pause button
  ///
  /// In en, this message translates to:
  /// **'Pause voice note, {duration}'**
  String chatVoiceNotePause(String duration);

  /// Semantics label for voice note play button
  ///
  /// In en, this message translates to:
  /// **'Play voice note, {duration}'**
  String chatVoiceNotePlay(String duration);

  /// Semantics label for the speed chip on a voice note
  ///
  /// In en, this message translates to:
  /// **'Playback speed {speed}x. Double tap to change.'**
  String chatVoiceNoteSpeed(String speed);

  /// Semantics label for voice note error state with retry
  ///
  /// In en, this message translates to:
  /// **'Failed to load voice note. Tap to retry.'**
  String get chatVoiceNoteError;

  /// Semantics label for image attachment error state with retry
  ///
  /// In en, this message translates to:
  /// **'Failed to load image. Tap to retry.'**
  String get chatImageError;

  /// Toast shown when an image upload fails
  ///
  /// In en, this message translates to:
  /// **'Image failed to send'**
  String get chatImageUploadFailed;

  /// Toast shown when a voice note upload fails
  ///
  /// In en, this message translates to:
  /// **'Voice note failed to send'**
  String get chatVoiceNoteUploadFailed;

  /// Semantics label for cancel recording button
  ///
  /// In en, this message translates to:
  /// **'Cancel recording'**
  String get chatVoiceRecorderCancel;

  /// Semantics label for send voice note button
  ///
  /// In en, this message translates to:
  /// **'Send voice note'**
  String get chatVoiceRecorderSend;

  /// Semantics label for full-screen image viewer
  ///
  /// In en, this message translates to:
  /// **'Full screen image viewer. {caption}. Pinch to zoom, swipe down to close.'**
  String chatImageViewerSemantics(String caption);

  /// Semantics label for image viewer close button
  ///
  /// In en, this message translates to:
  /// **'Close viewer'**
  String get chatImageViewerClose;

  /// Semantics label for image viewer share button
  ///
  /// In en, this message translates to:
  /// **'Share image'**
  String get chatImageViewerShare;

  /// Fallback text for a conversation with no participants other than self
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get chatConversationNoTitle;

  /// Default title for an untitled group chat that includes every active member
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get chatEveryoneTitle;

  /// Error message in the member selection sheet when members fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load {termPlural}'**
  String memberSelectLoadFailed(String termPlural);

  /// Label shown when an onboarding permission has not been granted
  ///
  /// In en, this message translates to:
  /// **'Not granted'**
  String get onboardingPermissionsNotGranted;

  /// Status text while an existing device connects to the joining device
  ///
  /// In en, this message translates to:
  /// **'Connecting to joiner...'**
  String get syncSetupConnectingToJoiner;

  /// Status text while an existing device completes pairing
  ///
  /// In en, this message translates to:
  /// **'Completing pairing...'**
  String get syncSetupCompletingPairing;

  /// Intro text on the set up another device sheet before scanning
  ///
  /// In en, this message translates to:
  /// **'The new device can generate a pairing request QR code. Scan it here to approve the device and share your sync credentials.'**
  String get syncSetupScanJoinerPrompt;

  /// Title of the recovery phrase prompt in the 'set up another device' initiator flow
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery phrase'**
  String get setupDeviceEnterMnemonicTitle;

  /// Explanatory subtitle under the recovery phrase prompt in the set up another device flow
  ///
  /// In en, this message translates to:
  /// **'Needed to set up this new device. Your recovery phrase is not stored on this device — type it from your saved backup.'**
  String get setupDeviceEnterMnemonicSubtitle;

  /// Primary button label on the recovery phrase step of the set up another device flow
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get setupDeviceMnemonicContinue;

  /// Primary button label to scan the joiner's pairing QR code
  ///
  /// In en, this message translates to:
  /// **'Scan Joiner\'s QR'**
  String get syncSetupScanJoinerButton;

  /// Instruction text above the joiner QR scanner
  ///
  /// In en, this message translates to:
  /// **'Scan the joiner\'s pairing QR code.'**
  String get syncSetupScanJoinerDescription;

  /// Toast shown when the scanned joiner QR code is invalid
  ///
  /// In en, this message translates to:
  /// **'Invalid pairing QR code.'**
  String get syncSetupInvalidPairingQr;

  /// Fallback link beneath the joiner QR viewfinder that switches to the paste-a-code view.
  ///
  /// In en, this message translates to:
  /// **'No camera? Paste a code instead'**
  String get syncSetupPasteCodeLink;

  /// Label for the desktop webcam picker in the set up another device QR scanner
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get syncSetupDesktopCameraLabel;

  /// Tooltip and accessibility label for refreshing the desktop webcam list
  ///
  /// In en, this message translates to:
  /// **'Refresh cameras'**
  String get syncSetupDesktopCameraRefresh;

  /// Status text shown while opening a selected desktop webcam
  ///
  /// In en, this message translates to:
  /// **'Opening camera...'**
  String get syncSetupDesktopCameraOpening;

  /// Status text shown when the desktop webcam picker finds no cameras
  ///
  /// In en, this message translates to:
  /// **'No camera was found.'**
  String get syncSetupDesktopCameraNoCameras;

  /// Status text shown when the selected desktop webcam cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Could not open the selected camera. Check camera privacy settings and try another camera.'**
  String get syncSetupDesktopCameraOpenFailed;

  /// Title of the camera-less paste fallback view on the initiator desktop.
  ///
  /// In en, this message translates to:
  /// **'Paste a pairing code'**
  String get syncSetupPasteCodeTitle;

  /// Helper text on the paste fallback view explaining how the user gets the code over to the desktop.
  ///
  /// In en, this message translates to:
  /// **'On the new device, tap \"Copy pairing code\" and send the result to this device (e.g. through a message to yourself), then paste it below.'**
  String get syncSetupPasteCodeDescription;

  /// Label on the multi-line pairing code input.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get syncSetupPasteCodeLabel;

  /// Placeholder shown inside the empty pairing code input.
  ///
  /// In en, this message translates to:
  /// **'Paste the code from your other device'**
  String get syncSetupPasteCodeHint;

  /// Primary button label on the paste fallback view; starts the pairing ceremony from the pasted bytes.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get syncSetupPasteCodeSubmit;

  /// Error shown when pasted content has no valid pairing-code substring.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a pairing code — make sure you copied it from the other device\'s Prism app.'**
  String get syncSetupPasteCodeInvalidFormat;

  /// Instruction text on the existing-device security code verification step
  ///
  /// In en, this message translates to:
  /// **'Confirm these words match on the joining device.'**
  String get syncSetupVerifyDescription;

  /// Success banner on the existing-device setup flow after pairing completes
  ///
  /// In en, this message translates to:
  /// **'Pairing complete! The new device is now syncing.'**
  String get syncSetupPairingComplete;

  /// Informational note after pairing completes on the existing-device setup flow
  ///
  /// In en, this message translates to:
  /// **'An encrypted snapshot has been uploaded and will be automatically deleted after the new device connects (or after 24 hours).'**
  String get syncSetupSnapshotNotice;

  /// Title shown when the existing-device setup flow fails
  ///
  /// In en, this message translates to:
  /// **'Pairing Failed'**
  String get syncSetupPairingFailed;

  /// Title of the progress card shown while the encrypted pairing snapshot is uploading to the relay
  ///
  /// In en, this message translates to:
  /// **'Uploading your data to the new device'**
  String get syncSetupSnapshotUploadingTitle;

  /// Label under the snapshot upload progress bar, showing bytes uploaded out of total
  ///
  /// In en, this message translates to:
  /// **'{sent} of {total}'**
  String syncSetupSnapshotUploadProgress(String sent, String total);

  /// Placeholder label shown before the first upload progress event arrives
  ///
  /// In en, this message translates to:
  /// **'Preparing upload...'**
  String get syncSetupSnapshotUploadStarting;

  /// Title shown when the pair-time snapshot upload fails; accompanied by a retry button
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload your data'**
  String get syncSetupSnapshotUploadFailedTitle;

  /// Retry button label on the snapshot upload failure view
  ///
  /// In en, this message translates to:
  /// **'Retry upload'**
  String get syncSetupSnapshotUploadRetry;

  /// Title of the confirmation shown after a successful snapshot upload, before the sheet closes
  ///
  /// In en, this message translates to:
  /// **'Pairing ready'**
  String get syncSetupPairingReadyTitle;

  /// Body of the pairing-ready confirmation shown briefly after a successful snapshot upload
  ///
  /// In en, this message translates to:
  /// **'Waiting for the other device to finish setting up.'**
  String get syncSetupPairingReadyWaiting;

  /// Title on the pre-flight PIN verification screen before scanning the joiner QR
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get syncSetupVerifyPinTitle;

  /// Default subtitle on the pre-flight PIN verification screen
  ///
  /// In en, this message translates to:
  /// **'We\'ll check it matches this device before scanning.'**
  String get syncSetupVerifyPinSubtitle;

  /// Subtitle shown while the pre-flight PIN check is in progress
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get syncSetupVerifyPinChecking;

  /// Error subtitle shown when the pre-flight PIN check fails
  ///
  /// In en, this message translates to:
  /// **'That phrase and PIN don\'t unlock this device.'**
  String get syncSetupVerifyPinFailed;

  /// Link below the numpad on the pre-flight PIN screen that navigates back to mnemonic entry
  ///
  /// In en, this message translates to:
  /// **'Try a different phrase'**
  String get syncSetupTryDifferentPhrase;

  /// Step label for the mnemonic entry step in the pairing step indicator
  ///
  /// In en, this message translates to:
  /// **'Phrase'**
  String get syncSetupStepPhrase;

  /// Step label for the PIN entry step in the pairing step indicator
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get syncSetupStepPin;

  /// Step label for the QR scan step in the pairing step indicator
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get syncSetupStepScan;

  /// Accessible label for the pairing step indicator, announced as a live region on step changes
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 3: {name}'**
  String syncSetupStepIndicatorLabel(int step, String name);

  /// Accessibility label for the icon-only backspace button in the PIN numpad
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get syncSetupNumpadBackspaceLabel;

  /// Subtitle shown when the pre-flight PIN check is locked out, with a countdown
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds}s'**
  String syncSetupVerifyPinLockedOut(int seconds);

  /// Toast shown when PIN verification fails due to a transient infrastructure error (not a wrong credential). Lockout counter is NOT incremented.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify — try again'**
  String get syncSetupVerifyPinTransientError;

  /// Semantics label for a member avatar image
  ///
  /// In en, this message translates to:
  /// **'{name} avatar'**
  String memberAvatarSemantics(String name);

  /// Fallback semantics label for a member avatar image
  ///
  /// In en, this message translates to:
  /// **'{termSingular} avatar'**
  String memberAvatarSemanticsUnnamed(
    String termSingular,
    Object termSingularLower,
  );

  /// Semantics label for an image inside a grouped member avatar
  ///
  /// In en, this message translates to:
  /// **'Group {termSingularLower} avatar'**
  String groupMemberAvatarSemantics(String termSingularLower);

  /// Title for a scheduled habit reminder notification
  ///
  /// In en, this message translates to:
  /// **'Habit Reminder'**
  String get habitsReminderNotificationTitle;

  /// Default body text for a scheduled habit reminder notification
  ///
  /// In en, this message translates to:
  /// **'Time to complete: {habitName}'**
  String habitsReminderNotificationBody(String habitName);

  /// Preview text for a conversation with no messages
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatTileNoMessages;

  /// Tooltip to show a password field's text
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// Tooltip to hide a password field's text
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// Tooltip to show a token field's text
  ///
  /// In en, this message translates to:
  /// **'Show token'**
  String get showToken;

  /// Tooltip to hide a token field's text
  ///
  /// In en, this message translates to:
  /// **'Hide token'**
  String get hideToken;

  /// Tooltip for close button in onboarding top bar
  ///
  /// In en, this message translates to:
  /// **'Close onboarding'**
  String get onboardingCloseOnboarding;

  /// Semantics label for onboarding progress indicator
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingProgressStep(int current, int total);

  /// Primary CTA button on welcome and complete steps
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// Primary navigation button for intermediate onboarding steps
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// Title of the confirm dialog shown when leaving the add-members onboarding step without adding anyone
  ///
  /// In en, this message translates to:
  /// **'Add someone first?'**
  String get onboardingNoMembersConfirmTitle;

  /// Body of the confirm dialog shown when leaving the add-members onboarding step without adding anyone
  ///
  /// In en, this message translates to:
  /// **'You haven\'t added anyone yet. You can always add people later from the home screen. Continue without adding anyone?'**
  String get onboardingNoMembersConfirmMessage;

  /// Confirm button: proceed past the add-members step without adding anyone
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get onboardingNoMembersConfirmProceed;

  /// Cancel button: return to the add-members step to add someone
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get onboardingNoMembersConfirmCancel;

  /// Toast shown when onboarding commit fails
  ///
  /// In en, this message translates to:
  /// **'Error completing setup: {error}'**
  String onboardingErrorCompletingSetup(Object error);

  /// Title on the imported data ready screen
  ///
  /// In en, this message translates to:
  /// **'Import Complete'**
  String get onboardingImportCompleteTitle;

  /// Body text on the imported data ready screen
  ///
  /// In en, this message translates to:
  /// **'Your Prism export has been restored and this device is ready.'**
  String get onboardingImportCompleteDescription;

  /// Summary label on the imported data ready view
  ///
  /// In en, this message translates to:
  /// **'Imported data'**
  String get onboardingImportedDataLabel;

  /// Feature row title in welcome step
  ///
  /// In en, this message translates to:
  /// **'Your data is yours'**
  String get onboardingWelcomePrivateTitle;

  /// Feature row description in welcome step
  ///
  /// In en, this message translates to:
  /// **'Everything starts on this device. Sync is optional, encrypted end-to-end, and we can\'t read it.'**
  String get onboardingWelcomePrivateDescription;

  /// Feature row title in welcome step
  ///
  /// In en, this message translates to:
  /// **'Bring your setup with you'**
  String get onboardingWelcomeSyncTitle;

  /// Feature row description in welcome step
  ///
  /// In en, this message translates to:
  /// **'Import from Simply Plural, connect PluralKit, or pair an existing Prism device before setup.'**
  String get onboardingWelcomeSyncDescription;

  /// Feature row title in welcome step
  ///
  /// In en, this message translates to:
  /// **'Make yourself at home'**
  String get onboardingWelcomeBuiltForYouTitle;

  /// Feature row description in welcome step
  ///
  /// In en, this message translates to:
  /// **'Choose your words, colors, fronting defaults, chat, routines, and the features you actually want.'**
  String get onboardingWelcomeBuiltForYouDescription;

  /// Empty state text in add members step
  ///
  /// In en, this message translates to:
  /// **'No {termPluralLower} yet.\nTap \"Add {termSingular}\" to get started.'**
  String onboardingAddMembersNoMembers(
    String termPluralLower,
    String termSingular,
    Object termSingularLower,
  );

  /// Tooltip for the remove member button in add members list
  ///
  /// In en, this message translates to:
  /// **'Remove {termSingularLower}'**
  String onboardingAddMembersRemoveMember(String termSingularLower);

  /// Button label to open the add member sheet
  ///
  /// In en, this message translates to:
  /// **'Add {termSingular}'**
  String onboardingAddMembersAddMember(
    String termSingular,
    Object termSingularLower,
  );

  /// Title bar of the add member sheet
  ///
  /// In en, this message translates to:
  /// **'Add {termSingular}'**
  String onboardingAddMemberSheetTitle(
    String termSingular,
    Object termSingularLower,
  );

  /// Hint text for the emoji field in add member sheet
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get onboardingAddMemberFieldEmoji;

  /// Hint text for the name field (required) in add member sheet
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get onboardingAddMemberFieldName;

  /// Quick-select pronoun chip label
  ///
  /// In en, this message translates to:
  /// **'She/Her'**
  String get onboardingAddMemberPronounSheHer;

  /// Quick-select pronoun chip label
  ///
  /// In en, this message translates to:
  /// **'He/Him'**
  String get onboardingAddMemberPronounHeHim;

  /// Quick-select pronoun chip label
  ///
  /// In en, this message translates to:
  /// **'They/Them'**
  String get onboardingAddMemberPronounTheyThem;

  /// Hint text for custom pronouns field in add member sheet
  ///
  /// In en, this message translates to:
  /// **'Pronouns (custom)'**
  String get onboardingAddMemberFieldPronounsCustom;

  /// Hint text for age field in add member sheet
  ///
  /// In en, this message translates to:
  /// **'Age (optional)'**
  String get onboardingAddMemberFieldAge;

  /// Hint text for bio field in add member sheet
  ///
  /// In en, this message translates to:
  /// **'Bio (optional)'**
  String get onboardingAddMemberFieldBio;

  /// Save button label in add member sheet
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get onboardingAddMemberSaveButton;

  /// Feature toggle title for chat in features step
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get onboardingFeaturesChat;

  /// Feature toggle description for chat in features step
  ///
  /// In en, this message translates to:
  /// **'Internal messaging between {termPluralLower}'**
  String onboardingFeaturesChatDescription(String termPluralLower);

  /// Feature toggle description when Simply Plural chats were imported and chat cannot be disabled
  ///
  /// In en, this message translates to:
  /// **'Imported Simply Plural chats are already in Prism and stay enabled.'**
  String get onboardingFeaturesChatImportedDescription;

  /// Feature toggle title for polls in features step
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get onboardingFeaturesPolls;

  /// Feature toggle description for polls in features step
  ///
  /// In en, this message translates to:
  /// **'Create polls for shared decisions'**
  String get onboardingFeaturesPollsDescription;

  /// Feature toggle title for habits in features step
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get onboardingFeaturesHabits;

  /// Feature toggle description for habits in features step
  ///
  /// In en, this message translates to:
  /// **'Track daily habits and routines'**
  String get onboardingFeaturesHabitsDescription;

  /// Feature toggle title for sleep tracking in features step
  ///
  /// In en, this message translates to:
  /// **'Sleep Tracking'**
  String get onboardingFeaturesSleepTracking;

  /// Feature toggle description for sleep tracking in features step
  ///
  /// In en, this message translates to:
  /// **'Monitor sleep patterns and quality'**
  String get onboardingFeaturesSleepTrackingDescription;

  /// Feature toggle label for notes in features step
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get onboardingFeaturesNotes;

  /// Feature toggle description for notes in features step
  ///
  /// In en, this message translates to:
  /// **'A personal journal and writing space'**
  String get onboardingFeaturesNotesDescription;

  /// Feature toggle label for message boards in features step
  ///
  /// In en, this message translates to:
  /// **'Message Boards'**
  String get onboardingFeaturesBoards;

  /// Feature toggle description for message boards in features step
  ///
  /// In en, this message translates to:
  /// **'Short messages between headmates — public timeline plus private inbox.'**
  String get onboardingFeaturesBoardsDescription;

  /// Feature toggle description when Simply Plural board posts were imported and boards cannot be disabled
  ///
  /// In en, this message translates to:
  /// **'Imported Simply Plural message-board posts are already in Prism and stay enabled.'**
  String get onboardingFeaturesBoardsImportedDescription;

  /// Feature toggle label for reminders in features step
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get onboardingFeaturesReminders;

  /// Feature toggle description for reminders in features step
  ///
  /// In en, this message translates to:
  /// **'Set reminders for yourself or {termPluralLower}'**
  String onboardingFeaturesRemindersDescription(String termPluralLower);

  /// Next step row title in complete step
  ///
  /// In en, this message translates to:
  /// **'Track fronting'**
  String get onboardingCompleteTrackFrontingTitle;

  /// Next step row description in complete step
  ///
  /// In en, this message translates to:
  /// **'Log who\'s here and look back at patterns over time.'**
  String get onboardingCompleteTrackFrontingDescription;

  /// Next step row title in complete step
  ///
  /// In en, this message translates to:
  /// **'Talk to each other'**
  String get onboardingCompleteChatTitle;

  /// Next step row description in complete step
  ///
  /// In en, this message translates to:
  /// **'Leave messages for whoever fronts next, or chat in real time.'**
  String get onboardingCompleteChatDescription;

  /// Next step row title in complete step
  ///
  /// In en, this message translates to:
  /// **'Decide together'**
  String get onboardingCompletePollsTitle;

  /// Next step row description in complete step
  ///
  /// In en, this message translates to:
  /// **'Polls, votes — make decisions together.'**
  String get onboardingCompletePollsDescription;

  /// Large display text on the final onboarding step
  ///
  /// In en, this message translates to:
  /// **'Welcome to Prism'**
  String get onboardingCompleteWelcomeTitle;

  /// Intro text on the import data source picker screen
  ///
  /// In en, this message translates to:
  /// **'You can import your existing data or skip this step to start fresh.'**
  String get onboardingImportDataSourcePickerIntro;

  /// Import source card title for syncing from another device
  ///
  /// In en, this message translates to:
  /// **'Sync with Existing Device'**
  String get onboardingImportSyncWithDevice;

  /// Import source card description for syncing from another device
  ///
  /// In en, this message translates to:
  /// **'Scan a pairing QR code to sync data from another device'**
  String get onboardingImportSyncWithDeviceDescription;

  /// Import source card title for PluralKit
  ///
  /// In en, this message translates to:
  /// **'PluralKit'**
  String get onboardingImportPluralKit;

  /// Import source card description for PluralKit
  ///
  /// In en, this message translates to:
  /// **'Import members and fronting history from PluralKit via API token'**
  String get onboardingImportPluralKitDescription;

  /// Import source card title for Prism export file
  ///
  /// In en, this message translates to:
  /// **'Prism Export'**
  String get onboardingImportPrismExport;

  /// Import source card description for Prism export file
  ///
  /// In en, this message translates to:
  /// **'Import from a Prism .json or encrypted .prism export file'**
  String get onboardingImportPrismExportDescription;

  /// Import source card title for Simply Plural
  ///
  /// In en, this message translates to:
  /// **'Simply Plural'**
  String get onboardingImportSimplyPlural;

  /// Import source card description for Simply Plural
  ///
  /// In en, this message translates to:
  /// **'Import from a Simply Plural JSON export file'**
  String get onboardingImportSimplyPluralDescription;

  /// Hint at the bottom of the import source picker
  ///
  /// In en, this message translates to:
  /// **'You can always import data later from Settings.'**
  String get onboardingImportLaterHint;

  /// Back link text in import sub-flows
  ///
  /// In en, this message translates to:
  /// **'Other import options'**
  String get onboardingImportOtherOptions;

  /// Section header in PluralKit import instructions
  ///
  /// In en, this message translates to:
  /// **'How to get your token:'**
  String get onboardingPluralKitHowToGetToken;

  /// PluralKit instruction step 1
  ///
  /// In en, this message translates to:
  /// **'Open Discord'**
  String get onboardingPluralKitStep1;

  /// PluralKit instruction step 2
  ///
  /// In en, this message translates to:
  /// **'DM PluralKit bot: pk;token'**
  String get onboardingPluralKitStep2;

  /// PluralKit instruction step 3
  ///
  /// In en, this message translates to:
  /// **'Copy the token and paste below'**
  String get onboardingPluralKitStep3;

  /// Hint text for the PluralKit token field
  ///
  /// In en, this message translates to:
  /// **'Paste your PluralKit token'**
  String get onboardingPluralKitTokenHint;

  /// Button label to start PluralKit import
  ///
  /// In en, this message translates to:
  /// **'Import PluralKit Data'**
  String get onboardingPluralKitImportButton;

  /// Loading label shown while validating the PluralKit token
  ///
  /// In en, this message translates to:
  /// **'Connecting to PluralKit…'**
  String get onboardingPluralKitConnecting;

  /// Loading label shown while importing PluralKit members
  ///
  /// In en, this message translates to:
  /// **'Importing members…'**
  String get onboardingPluralKitImportingMembers;

  /// Loading label shown while importing PluralKit switch history
  ///
  /// In en, this message translates to:
  /// **'Importing switch history…'**
  String get onboardingPluralKitImportingHistory;

  /// Success message after PluralKit import
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 member from PluralKit!} other{Imported {count} members from PluralKit!}}'**
  String onboardingPluralKitImportSuccess(int count);

  /// Validation error when PluralKit token is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter your PluralKit token.'**
  String get onboardingPluralKitErrorEnterToken;

  /// Error when PluralKit token is invalid or connection fails
  ///
  /// In en, this message translates to:
  /// **'Could not connect. Please check your token.'**
  String get onboardingPluralKitErrorCouldNotConnect;

  /// Generic import failed error message
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String onboardingImportError(Object error);

  /// Error shown when reading an import file fails
  ///
  /// In en, this message translates to:
  /// **'Failed to read file: {error}'**
  String onboardingImportReadFileFailed(Object error);

  /// Validation error when export password is empty
  ///
  /// In en, this message translates to:
  /// **'Password cannot be empty'**
  String get onboardingImportPasswordEmpty;

  /// Error when the export password is wrong
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get onboardingImportIncorrectPassword;

  /// Error when decryption of the export file fails
  ///
  /// In en, this message translates to:
  /// **'Decryption failed: {error}'**
  String onboardingImportDecryptionFailed(Object error);

  /// Error when user imports an unencrypted Prism JSON backup during onboarding
  ///
  /// In en, this message translates to:
  /// **'This backup isn\'t encrypted. Re-export from the app to get a secure .prism file.'**
  String get onboardingImportUnencryptedBackup;

  /// Section header in Prism export import instructions
  ///
  /// In en, this message translates to:
  /// **'How to export from Prism:'**
  String get onboardingPrismExportHowToExport;

  /// Prism export instruction step 1
  ///
  /// In en, this message translates to:
  /// **'Open Prism on your other device'**
  String get onboardingPrismExportStep1;

  /// Prism export instruction step 2
  ///
  /// In en, this message translates to:
  /// **'Go to Settings → Import & Export → Export Data'**
  String get onboardingPrismExportStep2;

  /// Prism export instruction step 3
  ///
  /// In en, this message translates to:
  /// **'Save the .json or .prism file and select it below'**
  String get onboardingPrismExportStep3;

  /// Button label to pick a Prism export file
  ///
  /// In en, this message translates to:
  /// **'Select Export File'**
  String get onboardingPrismExportSelectFile;

  /// Title shown when an encrypted Prism export is selected
  ///
  /// In en, this message translates to:
  /// **'Encrypted Export'**
  String get onboardingPrismExportEncryptedTitle;

  /// Description shown when an encrypted Prism export is selected
  ///
  /// In en, this message translates to:
  /// **'Enter the export password to unlock this Prism backup.'**
  String get onboardingPrismExportEncryptedDescription;

  /// Hint text for the export password field
  ///
  /// In en, this message translates to:
  /// **'Export password'**
  String get onboardingPrismExportPasswordHint;

  /// Button label to decrypt and unlock a Prism export
  ///
  /// In en, this message translates to:
  /// **'Unlock Export'**
  String get onboardingPrismExportUnlockButton;

  /// Section header in Prism export preview
  ///
  /// In en, this message translates to:
  /// **'Ready to import'**
  String get onboardingPrismExportReadyToImport;

  /// Description text in Prism export preview
  ///
  /// In en, this message translates to:
  /// **'This will restore your exported Prism data and finish setup on this device.'**
  String get onboardingPrismExportPreviewDescription;

  /// Button label to start the Prism export import
  ///
  /// In en, this message translates to:
  /// **'Import and Continue'**
  String get onboardingPrismExportImportButton;

  /// Loading text while importing a Prism export
  ///
  /// In en, this message translates to:
  /// **'Importing your Prism export...'**
  String get onboardingPrismExportImporting;

  /// Section header in Simply Plural import instructions
  ///
  /// In en, this message translates to:
  /// **'How to export from Simply Plural:'**
  String get onboardingSimplyPluralHowToExport;

  /// Simply Plural instruction step 1
  ///
  /// In en, this message translates to:
  /// **'Open Simply Plural app'**
  String get onboardingSimplyPluralStep1;

  /// Simply Plural instruction step 2
  ///
  /// In en, this message translates to:
  /// **'Go to Settings → Export Data'**
  String get onboardingSimplyPluralStep2;

  /// Simply Plural instruction step 3
  ///
  /// In en, this message translates to:
  /// **'Save the JSON file and select it below'**
  String get onboardingSimplyPluralStep3;

  /// Button label to pick a Simply Plural export file
  ///
  /// In en, this message translates to:
  /// **'Select Export File'**
  String get onboardingSimplyPluralSelectFile;

  /// Loading text while parsing a Simply Plural file
  ///
  /// In en, this message translates to:
  /// **'Reading file...'**
  String get onboardingSimplyPluralReadingFile;

  /// Fallback loading text while preparing a Simply Plural import
  ///
  /// In en, this message translates to:
  /// **'Preparing import...'**
  String get onboardingSimplyPluralPreparingImport;

  /// Loading text while preparing Simply Plural member-link decisions
  ///
  /// In en, this message translates to:
  /// **'Preparing member choices...'**
  String get onboardingSimplyPluralPreparingMemberChoices;

  /// Fallback loading text while importing Simply Plural data
  ///
  /// In en, this message translates to:
  /// **'Importing Simply Plural data...'**
  String get onboardingSimplyPluralImportingData;

  /// Fallback loading text while importing Simply Plural avatar images
  ///
  /// In en, this message translates to:
  /// **'Importing avatar images...'**
  String get onboardingSimplyPluralImportingAvatarImages;

  /// Loading text while downloading Simply Plural avatars
  ///
  /// In en, this message translates to:
  /// **'Downloading avatars...'**
  String get onboardingSimplyPluralDownloadingAvatars;

  /// Loading text while retrying Simply Plural avatar downloads
  ///
  /// In en, this message translates to:
  /// **'Retrying avatars...'**
  String get onboardingSimplyPluralRetryingAvatars;

  /// Loading text while importing images referenced in Simply Plural bios
  ///
  /// In en, this message translates to:
  /// **'Importing bio images...'**
  String get onboardingSimplyPluralImportingBioImages;

  /// Section header in Simply Plural preview
  ///
  /// In en, this message translates to:
  /// **'Found data:'**
  String get onboardingSimplyPluralFoundData;

  /// Button label to start Simply Plural import
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get onboardingSimplyPluralImportButton;

  /// Success message after Simply Plural import
  ///
  /// In en, this message translates to:
  /// **'Import complete! Your data is ready.'**
  String get onboardingSimplyPluralImportComplete;

  /// Label for members row in import preview
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get onboardingImportPreviewMembers;

  /// Label for fronting sessions row in import preview
  ///
  /// In en, this message translates to:
  /// **'Fronting sessions'**
  String get onboardingImportPreviewFrontingSessions;

  /// Label for conversations row in import preview
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get onboardingImportPreviewConversations;

  /// Label for messages row in import preview
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get onboardingImportPreviewMessages;

  /// Label for habits row in import preview
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get onboardingImportPreviewHabits;

  /// Label for notes row in import preview
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get onboardingImportPreviewNotes;

  /// Label for total records row in import preview
  ///
  /// In en, this message translates to:
  /// **'Total records'**
  String get onboardingImportPreviewTotalRecords;

  /// Label for custom fronts row in import preview
  ///
  /// In en, this message translates to:
  /// **'Custom fronts'**
  String get onboardingImportPreviewCustomFronts;

  /// Label for groups row in import preview
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get onboardingImportPreviewGroups;

  /// Label for polls row in import preview
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get onboardingImportPreviewPolls;

  /// Label for custom fields row in import preview
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get onboardingImportPreviewCustomFields;

  /// Label for comments row in import preview
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get onboardingImportPreviewComments;

  /// Label for reminders row in import preview
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get onboardingImportPreviewReminders;

  /// Label for sleep sessions row in import preview
  ///
  /// In en, this message translates to:
  /// **'Sleep sessions'**
  String get onboardingImportPreviewSleepSessions;

  /// Label for friends row in import preview
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get onboardingImportPreviewFriends;

  /// Label for media attachments row in import preview
  ///
  /// In en, this message translates to:
  /// **'Media attachments'**
  String get onboardingImportPreviewMediaAttachments;

  /// Label for members row in data ready view
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get onboardingDataReadyMembers;

  /// Label for fronting sessions row in data ready view
  ///
  /// In en, this message translates to:
  /// **'Fronting sessions'**
  String get onboardingDataReadyFrontingSessions;

  /// Label for conversations row in data ready view
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get onboardingDataReadyConversations;

  /// Label for messages row in data ready view
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get onboardingDataReadyMessages;

  /// Label for habits row in data ready view
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get onboardingDataReadyHabits;

  /// Label for notes row in data ready view
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get onboardingDataReadyNotes;

  /// Summary label for synced data on pairing success screen
  ///
  /// In en, this message translates to:
  /// **'Synced data'**
  String get onboardingDataReadySyncedData;

  /// Hint text in the system name text field
  ///
  /// In en, this message translates to:
  /// **'Enter name'**
  String get onboardingSystemNameHint;

  /// Helper text below the system name field
  ///
  /// In en, this message translates to:
  /// **'This is how this profile will be identified in the app.'**
  String get onboardingSystemNameHelperText;

  /// Helper text on the name-your-system step when the name was pre-filled from an import
  ///
  /// In en, this message translates to:
  /// **'We pulled this from your import — edit it if you\'d like something different.'**
  String get onboardingSystemNameHelperTextImported;

  /// Hint text above the fronter grid in whos fronting step
  ///
  /// In en, this message translates to:
  /// **'Tap to select who is currently fronting'**
  String get onboardingWhosFrontingSelectHint;

  /// Message shown on onboarding when an import already created active current fronting sessions
  ///
  /// In en, this message translates to:
  /// **'Imported current front: {names}'**
  String onboardingWhosFrontingImportedCurrent(String names);

  /// Secondary action on the onboarding who's-fronting step that continues without setting a new current fronter
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get onboardingWhosFrontingSkip;

  /// Empty state message in whos fronting step
  ///
  /// In en, this message translates to:
  /// **'No {termPluralLower} added yet.\nGo back to add {termPluralLower} first.'**
  String onboardingWhosFrontingNoMembers(String termPluralLower);

  /// Section header for suggested channels in chat setup step
  ///
  /// In en, this message translates to:
  /// **'Suggested Channels'**
  String get onboardingChatSuggestedChannels;

  /// Section header for custom channel input in chat setup step
  ///
  /// In en, this message translates to:
  /// **'Custom Channel'**
  String get onboardingChatCustomChannel;

  /// Title for locked imported Simply Plural chats in chat setup step
  ///
  /// In en, this message translates to:
  /// **'Imported from Simply Plural'**
  String get onboardingChatImportedSimplyPluralTitle;

  /// Description for locked imported Simply Plural chats in chat setup step
  ///
  /// In en, this message translates to:
  /// **'These chats are already in Prism and stay enabled.'**
  String get onboardingChatImportedSimplyPluralDescription;

  /// Hint text for the custom channel name field
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get onboardingChatChannelNameHint;

  /// Default onboarding channel: group chat visible to all members (cannot be removed)
  ///
  /// In en, this message translates to:
  /// **'All {termPlural}'**
  String onboardingChatChannelAllMembers(
    String termPlural,
    Object termPluralLower,
  );

  /// Default onboarding channel suggestion: a place to vent
  ///
  /// In en, this message translates to:
  /// **'Venting'**
  String get onboardingChatChannelVenting;

  /// Default onboarding channel suggestion: planning channel
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get onboardingChatChannelPlanning;

  /// Default onboarding channel suggestion: journal channel
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get onboardingChatChannelJournal;

  /// Default onboarding channel suggestion: updates channel
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get onboardingChatChannelUpdates;

  /// Default onboarding channel suggestion: random/miscellaneous channel
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get onboardingChatChannelRandom;

  /// Section header for the onboarding screen that configures how the Home fronting view is displayed
  ///
  /// In en, this message translates to:
  /// **'Home view'**
  String get onboardingFrontingDefaultsHomeViewSection;

  /// Title for the onboarding preference that controls the default Home fronting view mode
  ///
  /// In en, this message translates to:
  /// **'Home fronting view'**
  String get onboardingFrontingDefaultsHomeViewTitle;

  /// Description for the onboarding preference that controls the default Home fronting view mode
  ///
  /// In en, this message translates to:
  /// **'Choose the view Home uses for fronting history.'**
  String get onboardingFrontingDefaultsHomeViewDescription;

  /// Segment label for showing fronting history as combined periods
  ///
  /// In en, this message translates to:
  /// **'Combined'**
  String get onboardingFrontingViewCombined;

  /// Segment label for showing fronting history as individual per-member rows
  ///
  /// In en, this message translates to:
  /// **'Individual'**
  String get onboardingFrontingViewIndividual;

  /// Segment label for showing fronting history as a timeline
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get onboardingFrontingViewTimeline;

  /// Selected-state explanation for the combined Home fronting view mode
  ///
  /// In en, this message translates to:
  /// **'Groups overlapping fronts into one combined period.'**
  String get onboardingFrontingViewCombinedDescription;

  /// Selected-state explanation for the individual Home fronting view mode
  ///
  /// In en, this message translates to:
  /// **'Shows each fronting session as its own row.'**
  String get onboardingFrontingViewIndividualDescription;

  /// Selected-state explanation for the timeline Home fronting view mode
  ///
  /// In en, this message translates to:
  /// **'Shows fronting as a visual timeline over time.'**
  String get onboardingFrontingViewTimelineDescription;

  /// Section header for onboarding controls that configure how fronting starts
  ///
  /// In en, this message translates to:
  /// **'Starting fronts'**
  String get onboardingFrontingDefaultsStartingSection;

  /// Title for onboarding preference that controls the Add Front sheet default behavior
  ///
  /// In en, this message translates to:
  /// **'When adding a new front'**
  String get onboardingAddFrontBehaviorTitle;

  /// Description for onboarding preference that controls the Add Front sheet default behavior
  ///
  /// In en, this message translates to:
  /// **'Choose what happens when you start a front from the full Add Front sheet.'**
  String get onboardingAddFrontBehaviorDescription;

  /// Title for onboarding preference that controls the quick-front shortcut default behavior
  ///
  /// In en, this message translates to:
  /// **'When using quick front'**
  String get onboardingQuickFrontBehaviorTitle;

  /// Description for onboarding preference that controls the quick-front shortcut default behavior
  ///
  /// In en, this message translates to:
  /// **'Choose what happens when you hold a quick-front button for a {termSingularLower} who is not already fronting.'**
  String onboardingQuickFrontBehaviorDescription(String termSingularLower);

  /// Segment label for adding a member while keeping current fronters active
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get onboardingFrontBehaviorAdditive;

  /// Segment label for replacing current fronters with the new member
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get onboardingFrontBehaviorReplace;

  /// Selected-state explanation for additive fronting behavior
  ///
  /// In en, this message translates to:
  /// **'Keeps everyone currently fronting and adds the new member as a fronter.'**
  String get onboardingFrontBehaviorAdditiveDescription;

  /// Selected-state explanation for replace fronting behavior
  ///
  /// In en, this message translates to:
  /// **'Ends the current front first, then starts the new member.'**
  String get onboardingFrontBehaviorReplaceDescription;

  /// Section header for theme brightness and OLED appearance choices in onboarding
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get onboardingAppearanceTheme;

  /// Section header for terminology section in preferences step
  ///
  /// In en, this message translates to:
  /// **'Terminology'**
  String get onboardingPreferencesTerminology;

  /// Section header for choosing terminology for members during onboarding
  ///
  /// In en, this message translates to:
  /// **'Member terminology'**
  String get onboardingPreferencesMemberTerminology;

  /// Section header for choosing terminology for the user's collective/system during onboarding
  ///
  /// In en, this message translates to:
  /// **'System terminology'**
  String get onboardingPreferencesSystemTerminology;

  /// Section header for choosing terminology for fronting/presence/activity during onboarding
  ///
  /// In en, this message translates to:
  /// **'Fronting terminology'**
  String get onboardingPreferencesFrontingTerminology;

  /// Label for the custom terminology option in preferences grid
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get onboardingPreferencesCustomTerminology;

  /// Option label for using Prism's default system terminology during onboarding
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get onboardingPreferencesSystemDefault;

  /// Option label for using custom system terminology during onboarding
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get onboardingPreferencesCustomSystemTerminology;

  /// Hint text for custom singular terminology field
  ///
  /// In en, this message translates to:
  /// **'Singular (e.g. Alter)'**
  String get onboardingPreferencesSingularHint;

  /// Hint text for custom plural terminology field
  ///
  /// In en, this message translates to:
  /// **'Plural (e.g. Alters)'**
  String get onboardingPreferencesPluralHint;

  /// Hint text for custom singular system terminology field
  ///
  /// In en, this message translates to:
  /// **'Singular (e.g. Collective)'**
  String get onboardingPreferencesSystemSingularHint;

  /// Hint text for custom plural system terminology field
  ///
  /// In en, this message translates to:
  /// **'Plural (e.g. Collectives)'**
  String get onboardingPreferencesSystemPluralHint;

  /// Section header for accent color in preferences step
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get onboardingPreferencesAccentColor;

  /// Toggle title for per-member colors in preferences step
  ///
  /// In en, this message translates to:
  /// **'{termSingular} accent colors'**
  String onboardingPreferencesPerMemberColors(
    String termSingular,
    Object termSingularLower,
  );

  /// Toggle subtitle for per-member colors in preferences step
  ///
  /// In en, this message translates to:
  /// **'Automatically assigns each {termSingularLower} an accent color if they don\'t have one'**
  String onboardingPreferencesPerMemberColorsSubtitle(String termSingularLower);

  /// Title on the join sync group prompt view
  ///
  /// In en, this message translates to:
  /// **'Join your sync group'**
  String get onboardingSyncJoinYourGroup;

  /// Description on the join sync group prompt view
  ///
  /// In en, this message translates to:
  /// **'Create a pairing request on this device and have an existing device approve it.'**
  String get onboardingSyncJoinDescription;

  /// Button label to generate a pairing request
  ///
  /// In en, this message translates to:
  /// **'Request to Join'**
  String get onboardingSyncRequestToJoin;

  /// Hint text below the request to join button
  ///
  /// In en, this message translates to:
  /// **'Show a QR code for your existing device to scan and approve.'**
  String get onboardingSyncRequestToJoinHint;

  /// Title on the QR code display view
  ///
  /// In en, this message translates to:
  /// **'Show this to your existing device'**
  String get onboardingSyncShowToExistingDevice;

  /// Instructions below the QR code
  ///
  /// In en, this message translates to:
  /// **'On your existing device, open \"Set Up Another Device\" and scan this code.'**
  String get onboardingSyncScanInstructions;

  /// Joiner-side fallback button: copies the QR's base64 contents to the clipboard so the user can paste them on a desktop without a working camera.
  ///
  /// In en, this message translates to:
  /// **'Copy pairing code'**
  String get onboardingSyncCopyPairingCode;

  /// Toast shown after the joiner taps the copy pairing code button.
  ///
  /// In en, this message translates to:
  /// **'Pairing code copied'**
  String get onboardingSyncPairingCodeCopied;

  /// Status text while waiting for QR code scan
  ///
  /// In en, this message translates to:
  /// **'Waiting for other device to scan...'**
  String get onboardingSyncWaitingForScan;

  /// Title shown while waiting for SAS codes to appear
  ///
  /// In en, this message translates to:
  /// **'Waiting for security verification...'**
  String get onboardingSyncWaitingForVerification;

  /// Subtitle shown while waiting for SAS codes
  ///
  /// In en, this message translates to:
  /// **'The other device is connecting. Security codes will appear shortly.'**
  String get onboardingSyncWaitingForVerificationSubtitle;

  /// Title on the SAS verification view
  ///
  /// In en, this message translates to:
  /// **'Verify Security Code'**
  String get onboardingSyncVerifySecurityCode;

  /// Description on the SAS verification view
  ///
  /// In en, this message translates to:
  /// **'Confirm these words match the ones shown on your existing device.'**
  String get onboardingSyncVerifyDescription;

  /// Button label to confirm SAS codes match
  ///
  /// In en, this message translates to:
  /// **'They Match'**
  String get onboardingSyncTheyMatch;

  /// Button label to reject SAS codes
  ///
  /// In en, this message translates to:
  /// **'They Don\'t Match'**
  String get onboardingSyncTheyDontMatch;

  /// Title on the PIN entry view during sync pairing
  ///
  /// In en, this message translates to:
  /// **'Enter your sync PIN'**
  String get onboardingSyncEnterPassword;

  /// Description on the PIN entry view during sync pairing
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit PIN from the device you\'re syncing with.'**
  String get onboardingSyncEnterPasswordDescription;

  /// Title shown while connecting and syncing during pairing
  ///
  /// In en, this message translates to:
  /// **'Pairing and syncing...'**
  String get onboardingSyncConnecting;

  /// Subtitle shown while connecting during pairing
  ///
  /// In en, this message translates to:
  /// **'This may take a moment while the device is enrolled.'**
  String get onboardingSyncConnectingSubtitle;

  /// Notice shown on success screen when sync is incomplete
  ///
  /// In en, this message translates to:
  /// **'Some data is still syncing and will appear shortly.'**
  String get onboardingSyncDataStillSyncing;

  /// Title on the sync pairing success screen
  ///
  /// In en, this message translates to:
  /// **'Welcome Back!'**
  String get onboardingSyncWelcomeBackTitle;

  /// Description on the sync pairing success screen
  ///
  /// In en, this message translates to:
  /// **'Your device has been paired and your data is ready.'**
  String get onboardingSyncWelcomeBackDescription;

  /// Fallback error message when no specific error is available
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred.'**
  String get onboardingSyncUnknownError;

  /// Sheet title when creating a new habit
  ///
  /// In en, this message translates to:
  /// **'New Habit'**
  String get habitsNewHabit;

  /// Sheet title when editing an existing habit
  ///
  /// In en, this message translates to:
  /// **'Edit Habit'**
  String get habitsEditHabit;

  /// Title shown in CompleteHabitSheet when editing an existing completion
  ///
  /// In en, this message translates to:
  /// **'Edit Completion'**
  String get habitsEditCompletion;

  /// Section header for basic info in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'BASIC INFO'**
  String get habitsSectionBasicInfo;

  /// Label for the name field in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get habitsFieldName;

  /// Hint text for the name field in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'e.g., Morning meditation'**
  String get habitsFieldNameHint;

  /// Label for the description field in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get habitsFieldDescription;

  /// Toast shown on save when user picks a future timestamp for a habit completion
  ///
  /// In en, this message translates to:
  /// **'Completion time can\'t be in the future.'**
  String get habitsFutureCompletionError;

  /// Section header for schedule in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'SCHEDULE'**
  String get habitsSectionSchedule;

  /// Label before interval day count in schedule section
  ///
  /// In en, this message translates to:
  /// **'Every '**
  String get habitsIntervalEvery;

  /// Label after interval day count in schedule section
  ///
  /// In en, this message translates to:
  /// **' days'**
  String get habitsIntervalDays;

  /// Tooltip for decrease interval button
  ///
  /// In en, this message translates to:
  /// **'Decrease interval'**
  String get habitsIntervalDecrease;

  /// Tooltip for increase interval button
  ///
  /// In en, this message translates to:
  /// **'Increase interval'**
  String get habitsIntervalIncrease;

  /// Section header for notifications in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get habitsSectionNotifications;

  /// Switch title for enabling reminders in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'Enable Reminders'**
  String get habitsEnableReminders;

  /// Row title for reminder time picker
  ///
  /// In en, this message translates to:
  /// **'Reminder Time'**
  String get habitsReminderTime;

  /// Trailing text when reminder time is not set
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get habitsReminderTimeNotSet;

  /// Snackbar message after saving a habit reminder time
  ///
  /// In en, this message translates to:
  /// **'Reminder set for {time}'**
  String habitsReminderSetFor(String time);

  /// Label for the custom notification message field
  ///
  /// In en, this message translates to:
  /// **'Custom message (optional)'**
  String get habitsCustomMessageField;

  /// Section header for assignment in add/edit habit sheet
  ///
  /// In en, this message translates to:
  /// **'ASSIGNMENT'**
  String get habitsSectionAssignment;

  /// Label for assigned member select field
  ///
  /// In en, this message translates to:
  /// **'Assigned {termSingular}'**
  String habitsAssignedMember(String termSingular);

  /// Option label for no assigned member
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get habitsAssignedMemberAnyone;

  /// Switch title for fronting-only notification in assignment section
  ///
  /// In en, this message translates to:
  /// **'Only notify when fronting'**
  String get habitsOnlyNotifyWhenFronting;

  /// Helper text below the only-notify-when-fronting toggle
  ///
  /// In en, this message translates to:
  /// **'Reminders for this {termSingularLower} only check fronts when Prism is open or syncing; they may not fire while the app is closed.'**
  String habitsOnlyFrontingCaveat(String termSingularLower);

  /// Switch title for private habit toggle
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get habitsPrivate;

  /// Switch subtitle for private habit toggle
  ///
  /// In en, this message translates to:
  /// **'Hide from shared views'**
  String get habitsPrivateSubtitle;

  /// Title bar of the complete habit sheet
  ///
  /// In en, this message translates to:
  /// **'Complete Habit'**
  String get habitsCompleteHabit;

  /// Label for the completed-at date/time picker in complete habit sheet
  ///
  /// In en, this message translates to:
  /// **'Completed At'**
  String get habitsCompletedAt;

  /// Label for the completed-by member picker in complete habit sheet
  ///
  /// In en, this message translates to:
  /// **'Completed By'**
  String get habitsCompletedBy;

  /// Section header for rating in complete habit sheet
  ///
  /// In en, this message translates to:
  /// **'RATING'**
  String get habitsSectionRating;

  /// Semantics label for a star rating button
  ///
  /// In en, this message translates to:
  /// **'Rate {n} out of 5 stars'**
  String habitsRateNStars(int n);

  /// Tooltip for a star rating button
  ///
  /// In en, this message translates to:
  /// **'Rate {n} stars'**
  String habitsRateNStarsTooltip(int n);

  /// Label for the notes field in complete habit sheet
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get habitsNotesField;

  /// Confirm dialog title when long-press → delete on a completion row
  ///
  /// In en, this message translates to:
  /// **'Delete completion?'**
  String get habitsDeleteCompletionTitle;

  /// Confirm dialog body when deleting a habit completion
  ///
  /// In en, this message translates to:
  /// **'This completion will be removed. Your streak may change.'**
  String get habitsDeleteCompletionMessage;

  /// Dialog title for delete habit confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete Habit'**
  String get habitsDetailDeleteTitle;

  /// Dialog message for delete habit confirmation
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete this habit and all its completions. This action cannot be undone.'**
  String get habitsDetailDeleteMessage;

  /// Tooltip for the more options popup menu in habit detail
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get habitsDetailMoreOptions;

  /// Frequency text for interval habits in habit detail header
  ///
  /// In en, this message translates to:
  /// **'Every {n} days'**
  String habitsDetailFrequencyEveryNDays(int n);

  /// Section header for recent completions in habit detail
  ///
  /// In en, this message translates to:
  /// **'Recent completions'**
  String get habitsDetailSectionRecentCompletions;

  /// Empty state title for completions in habit detail
  ///
  /// In en, this message translates to:
  /// **'No completions yet'**
  String get habitsDetailNoCompletions;

  /// Empty state subtitle for completions in habit detail
  ///
  /// In en, this message translates to:
  /// **'Complete this habit to start tracking progress.'**
  String get habitsDetailNoCompletionsSubtitle;

  /// Label for completions stat in habit stats row
  ///
  /// In en, this message translates to:
  /// **'Completions'**
  String get habitsStatCompletions;

  /// Label for completion rate stat in habit stats row
  ///
  /// In en, this message translates to:
  /// **'Completion Rate'**
  String get habitsStatCompletionRate;

  /// Streak pill label showing current streak count
  ///
  /// In en, this message translates to:
  /// **'{count} streak'**
  String habitsStatCurrentStreak(int count);

  /// Best streak pill label
  ///
  /// In en, this message translates to:
  /// **'{count} best'**
  String habitsStatBestStreak(int count);

  /// Semantics label for the stats row in habit detail
  ///
  /// In en, this message translates to:
  /// **'{completions} completions, {rate}% completion rate'**
  String habitsStatsSemanticsLabel(int completions, String rate);

  /// Semantics label for a star rating display in completion tile
  ///
  /// In en, this message translates to:
  /// **'Rated {n} out of 5 stars'**
  String habitsCompletionRatedNStars(int n);

  /// Date label when completion was today
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String habitsCompletionTileToday(String time);

  /// Date label when completion was yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday {time}'**
  String habitsCompletionTileYesterday(String time);

  /// Semantics label for the floating complete button when already completed
  ///
  /// In en, this message translates to:
  /// **'Habit already completed for this period'**
  String get habitsAlreadyCompleted;

  /// Semantics label for the floating complete button
  ///
  /// In en, this message translates to:
  /// **'Complete habit'**
  String get habitsCompleteButtonLabel;

  /// Label on the floating button when habit is already completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get habitsCompleted;

  /// Label on the floating button when habit is not yet completed
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get habitsComplete;

  /// Title in the habits list top bar
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get habitsListTitle;

  /// Habit detail popup-menu item for backdating a completion
  ///
  /// In en, this message translates to:
  /// **'Log missed completion'**
  String get habitsLogMissedCompletion;

  /// Tooltip for the create habit button in the habits list
  ///
  /// In en, this message translates to:
  /// **'Create habit'**
  String get habitsCreateHabitTooltip;

  /// Tooltip for the filter menu button in the habits list
  ///
  /// In en, this message translates to:
  /// **'Habit filters'**
  String get habitsFilterTooltip;

  /// Toggle label in the habits list filter menu
  ///
  /// In en, this message translates to:
  /// **'Show Deactivated Habits'**
  String get habitsShowDeactivated;

  /// Toggle label in the habits list filter menu
  ///
  /// In en, this message translates to:
  /// **'Show Completed Habits'**
  String get habitsShowCompleted;

  /// Empty state title on habits list
  ///
  /// In en, this message translates to:
  /// **'No habits yet'**
  String get habitsEmptyTitle;

  /// Empty state subtitle on habits list
  ///
  /// In en, this message translates to:
  /// **'Create habits to track daily routines, self-care, or anything you want to keep up with.'**
  String get habitsEmptySubtitle;

  /// Empty state action button label on habits list
  ///
  /// In en, this message translates to:
  /// **'Create Habit'**
  String get habitsEmptyCreateLabel;

  /// Section pill header for upcoming habits
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get habitsSectionUpcoming;

  /// Section pill header for inactive habits
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get habitsSectionInactive;

  /// Semantics label for the weekly progress pill in habit chip/row
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} days completed this week'**
  String habitsWeeklyProgressSemantics(int completed, int total);

  /// Text shown next to Today when all habits are completed
  ///
  /// In en, this message translates to:
  /// **'all done'**
  String get habitsTodayAllDone;

  /// Semantics container label for the today habits section
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get habitsTodaySemantics;

  /// Semantics label when today container is in all-done mode
  ///
  /// In en, this message translates to:
  /// **'Today, all habits complete'**
  String get habitsTodayAllDoneSemantics;

  /// Header text in the today habits container
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get habitsTodayHeader;

  /// Section pill header for today's completed habits
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get habitsSectionComplete;

  /// Semantics label for a completed habit chip leading circle
  ///
  /// In en, this message translates to:
  /// **'{name}, completed'**
  String habitsChipCompletedSemantics(String name);

  /// Semantics label for an incomplete habit chip leading circle
  ///
  /// In en, this message translates to:
  /// **'Complete {name}'**
  String habitsChipCompleteSemantics(String name);

  /// Semantics label for a color swatch in the habit color picker
  ///
  /// In en, this message translates to:
  /// **'Color #{hex}{selected}'**
  String habitsColorSemantics(String hex, String selected);

  /// Appended to color semantics label when the color is selected
  ///
  /// In en, this message translates to:
  /// **', selected'**
  String get habitsColorSelected;

  /// Sheet title when creating a new poll
  ///
  /// In en, this message translates to:
  /// **'New Poll'**
  String get pollsNewPoll;

  /// Label for the question field in create poll sheet
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get pollsQuestionLabel;

  /// Hint text for the question field in create poll sheet
  ///
  /// In en, this message translates to:
  /// **'What do you want to ask?'**
  String get pollsQuestionHint;

  /// Label for the description field in create poll sheet
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get pollsDescriptionLabel;

  /// Hint text for the description field in create poll sheet
  ///
  /// In en, this message translates to:
  /// **'Add context or details...'**
  String get pollsDescriptionHint;

  /// Section header above poll options list in create poll sheet
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get pollsOptionsHeader;

  /// Label for a numbered poll option field
  ///
  /// In en, this message translates to:
  /// **'Option {n}'**
  String pollsOptionLabel(int n);

  /// Tooltip for the remove option button in create poll
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get pollsRemoveOptionTooltip;

  /// Title of the full color picker dialog for a poll option's color
  ///
  /// In en, this message translates to:
  /// **'Option color'**
  String get pollsOptionColorTitle;

  /// Label for the swatch that clears a poll option's color
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get pollsOptionColorNone;

  /// Label for the swatch that opens the full custom color picker for a poll option
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get pollsOptionColorCustom;

  /// Name of the red quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get pollsOptionColorRed;

  /// Name of the orange quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get pollsOptionColorOrange;

  /// Name of the yellow quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get pollsOptionColorYellow;

  /// Name of the green quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get pollsOptionColorGreen;

  /// Name of the cyan quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get pollsOptionColorCyan;

  /// Name of the blue quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get pollsOptionColorBlue;

  /// Name of the violet quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get pollsOptionColorViolet;

  /// Name of the pink quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pollsOptionColorPink;

  /// Name of the gray quick-pick swatch for a poll option color
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get pollsOptionColorGray;

  /// Button label to add another poll option
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get pollsAddOption;

  /// Switch title for adding an other option to the poll
  ///
  /// In en, this message translates to:
  /// **'Add \"Other\" option'**
  String get pollsAddOtherOption;

  /// Switch subtitle for adding an other option
  ///
  /// In en, this message translates to:
  /// **'Allows free-text responses'**
  String get pollsAddOtherOptionSubtitle;

  /// Switch title for anonymous voting toggle in create poll
  ///
  /// In en, this message translates to:
  /// **'Anonymous voting'**
  String get pollsAnonymousVoting;

  /// Switch subtitle for anonymous voting toggle
  ///
  /// In en, this message translates to:
  /// **'Hide who voted for what'**
  String get pollsAnonymousVotingSubtitle;

  /// Switch title for multiple votes toggle in create poll
  ///
  /// In en, this message translates to:
  /// **'Allow multiple votes'**
  String get pollsAllowMultipleVotes;

  /// Switch subtitle for multiple votes toggle, using system terminology plural form
  ///
  /// In en, this message translates to:
  /// **'{plural} can vote for more than one option'**
  String pollsAllowMultipleVotesSubtitle(String plural);

  /// Switch title for expiration toggle in create poll
  ///
  /// In en, this message translates to:
  /// **'Set expiration'**
  String get pollsSetExpiration;

  /// Switch subtitle when no expiration is set
  ///
  /// In en, this message translates to:
  /// **'Poll stays open until manually closed'**
  String get pollsNoExpiration;

  /// Button label to pick an expiration date and time
  ///
  /// In en, this message translates to:
  /// **'Pick date & time'**
  String get pollsPickDateTime;

  /// Button label to change an already-set expiration date/time
  ///
  /// In en, this message translates to:
  /// **'Change: {datetime}'**
  String pollsChangeDateTime(String datetime);

  /// Toast shown when poll creation fails
  ///
  /// In en, this message translates to:
  /// **'Failed to create poll: {error}'**
  String pollsCreateError(Object error);

  /// Title in the polls list top bar
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get pollsListTitle;

  /// Tooltip for the create poll button in the polls list
  ///
  /// In en, this message translates to:
  /// **'Create poll'**
  String get pollsCreateTooltip;

  /// Poll filter menu item label
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get pollsFilterActive;

  /// Poll filter menu item label
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get pollsFilterClosed;

  /// Poll filter menu item label
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get pollsFilterAll;

  /// Empty state title when no active polls
  ///
  /// In en, this message translates to:
  /// **'No active polls'**
  String get pollsEmptyActiveTitle;

  /// Empty state subtitle when no active polls
  ///
  /// In en, this message translates to:
  /// **'Create a poll to start voting'**
  String get pollsEmptyActiveSubtitle;

  /// Empty state title when no closed polls
  ///
  /// In en, this message translates to:
  /// **'No closed polls'**
  String get pollsEmptyClosedTitle;

  /// Empty state subtitle when no closed polls
  ///
  /// In en, this message translates to:
  /// **'Closed and expired polls will appear here'**
  String get pollsEmptyClosedSubtitle;

  /// Empty state title when no polls at all
  ///
  /// In en, this message translates to:
  /// **'No polls yet'**
  String get pollsEmptyAllTitle;

  /// Empty state subtitle when no polls at all
  ///
  /// In en, this message translates to:
  /// **'Create your first poll to get started'**
  String get pollsEmptyAllSubtitle;

  /// Empty state action button label on polls list
  ///
  /// In en, this message translates to:
  /// **'Create Poll'**
  String get pollsEmptyCreateLabel;

  /// Error message when polls fail to load
  ///
  /// In en, this message translates to:
  /// **'Error loading polls'**
  String get pollsLoadError;

  /// Vote count label on poll card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 vote} other{{count} votes}}'**
  String pollsVoteCount(int count);

  /// Option count label on poll card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 option} other{{count} options}}'**
  String pollsOptionCount(int count);

  /// Pill label for expired poll
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get pollsExpired;

  /// Pill label for closed poll
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get pollsClosed;

  /// Countdown label when more than 1 day remains
  ///
  /// In en, this message translates to:
  /// **'{n}d left'**
  String pollsCountdownDays(int n);

  /// Countdown label when less than 1 day but more than 1 hour remains
  ///
  /// In en, this message translates to:
  /// **'{n}h left'**
  String pollsCountdownHours(int n);

  /// Countdown label when less than 1 hour but more than 1 minute remains
  ///
  /// In en, this message translates to:
  /// **'{n}m left'**
  String pollsCountdownMinutes(int n);

  /// Countdown label when less than 1 minute remains
  ///
  /// In en, this message translates to:
  /// **'Ending soon'**
  String get pollsCountdownEndingSoon;

  /// Info chip label for anonymous poll
  ///
  /// In en, this message translates to:
  /// **'Anonymous'**
  String get pollsAnonymous;

  /// Info chip label for multi-vote poll
  ///
  /// In en, this message translates to:
  /// **'Multi-vote'**
  String get pollsMultiVote;

  /// Error message when poll detail fails to load
  ///
  /// In en, this message translates to:
  /// **'Error loading poll: {error}'**
  String pollsDetailLoadError(Object error);

  /// Message shown when poll is not found in detail screen
  ///
  /// In en, this message translates to:
  /// **'Poll not found'**
  String get pollsDetailNotFound;

  /// Tooltip for the close poll button in poll detail top bar
  ///
  /// In en, this message translates to:
  /// **'Close poll'**
  String get pollsDetailClosePollTooltip;

  /// Tooltip for more options menu in poll detail
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get pollsDetailMoreOptions;

  /// Label above options when poll is closed (showing results)
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get pollsDetailResultsLabel;

  /// Label above options when poll is open
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get pollsDetailOptionsLabel;

  /// Label above the vote-as member picker
  ///
  /// In en, this message translates to:
  /// **'Vote as'**
  String get pollsDetailVoteAs;

  /// Message shown when no members are available for voting
  ///
  /// In en, this message translates to:
  /// **'No {termPluralLower} available'**
  String pollsDetailNoMembers(String termPluralLower);

  /// Button label to submit votes in poll detail
  ///
  /// In en, this message translates to:
  /// **'Submit Vote'**
  String get pollsDetailSubmitVote;

  /// Toast shown after successfully submitting a vote
  ///
  /// In en, this message translates to:
  /// **'Vote submitted'**
  String get pollsDetailVoteSubmitted;

  /// Toast shown when voting fails
  ///
  /// In en, this message translates to:
  /// **'Failed to vote: {error}'**
  String pollsDetailVoteError(Object error);

  /// Dialog title for close poll confirmation
  ///
  /// In en, this message translates to:
  /// **'Close poll?'**
  String get pollsDetailClosePollTitle;

  /// Dialog message for close poll confirmation
  ///
  /// In en, this message translates to:
  /// **'No more votes can be cast once the poll is closed. This cannot be undone.'**
  String get pollsDetailClosePollMessage;

  /// Dialog confirm button label for close poll
  ///
  /// In en, this message translates to:
  /// **'Close Poll'**
  String get pollsDetailClosePollConfirm;

  /// Dialog title for delete poll confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete poll?'**
  String get pollsDetailDeleteTitle;

  /// Dialog message for delete poll confirmation
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete the poll and all votes. This action cannot be undone.'**
  String get pollsDetailDeleteMessage;

  /// Metadata chip label when poll is expired
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get pollsDetailExpired;

  /// Metadata chip label showing expiration date
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String pollsDetailExpiresLabel(String date);

  /// Hint text for the other option response field
  ///
  /// In en, this message translates to:
  /// **'Enter your response...'**
  String get pollsDetailOtherResponseHint;

  /// Text on the poll notification banner showing how many polls need a vote
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 poll needs} other{{count} polls need}} your vote'**
  String pollsNotificationBanner(int count);

  /// Migration screen top bar title
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get migrationImportData;

  /// Loading message while reading an import file
  ///
  /// In en, this message translates to:
  /// **'Reading file…'**
  String get migrationReadingFile;

  /// Loading message while verifying the Simply Plural token
  ///
  /// In en, this message translates to:
  /// **'Verifying token…'**
  String get migrationVerifyingToken;

  /// Headline on the migration idle view
  ///
  /// In en, this message translates to:
  /// **'Import from Simply Plural'**
  String get migrationImportFromSimplyPlural;

  /// Body text on the migration idle view
  ///
  /// In en, this message translates to:
  /// **'Bring your existing data into Prism. Choose how you would like to import your Simply Plural data.'**
  String get migrationImportDescription;

  /// Import method card title for API import
  ///
  /// In en, this message translates to:
  /// **'Connect with API'**
  String get migrationConnectWithApi;

  /// Import method card subtitle for API import
  ///
  /// In en, this message translates to:
  /// **'No file export needed — imports directly from your account'**
  String get migrationConnectWithApiSubtitle;

  /// Chip label shown on the recommended import method
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get migrationRecommended;

  /// Import method card title for file import
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get migrationImportFromFile;

  /// Import method card subtitle for file import
  ///
  /// In en, this message translates to:
  /// **'Use a JSON export file from Simply Plural'**
  String get migrationImportFromFileSubtitle;

  /// Section heading for supported data types list
  ///
  /// In en, this message translates to:
  /// **'Supported data types'**
  String get migrationSupportedDataTypes;

  /// Supported data type: members
  ///
  /// In en, this message translates to:
  /// **'{termPlural}'**
  String migrationSupportedMembers(String termPlural);

  /// Supported data type: custom fronts
  ///
  /// In en, this message translates to:
  /// **'Custom fronts'**
  String get migrationSupportedCustomFronts;

  /// Supported data type: fronting history
  ///
  /// In en, this message translates to:
  /// **'Fronting history'**
  String get migrationSupportedFrontingHistory;

  /// Supported data type: chat channels and messages
  ///
  /// In en, this message translates to:
  /// **'Chat channels & messages'**
  String get migrationSupportedChatChannels;

  /// Supported data type: polls
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get migrationSupportedPolls;

  /// Supported data type: member colors
  ///
  /// In en, this message translates to:
  /// **'{termSingular} colors'**
  String migrationSupportedMemberColors(String termSingular);

  /// Supported data type: member descriptions
  ///
  /// In en, this message translates to:
  /// **'{termSingular} descriptions'**
  String migrationSupportedMemberDescriptions(String termSingular);

  /// Supported data type: avatar images
  ///
  /// In en, this message translates to:
  /// **'Avatar images'**
  String get migrationSupportedAvatarImages;

  /// Supported data type: notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get migrationSupportedNotes;

  /// Supported data type: custom fields
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get migrationSupportedCustomFields;

  /// Supported data type: groups
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get migrationSupportedGroups;

  /// Supported data type: comments on front sessions
  ///
  /// In en, this message translates to:
  /// **'Comments on front sessions'**
  String get migrationSupportedComments;

  /// Supported data type: reminders
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get migrationSupportedReminders;

  /// Token input screen title
  ///
  /// In en, this message translates to:
  /// **'Connect to Simply Plural'**
  String get migrationConnectToSimplyPlural;

  /// Body text on the token input screen
  ///
  /// In en, this message translates to:
  /// **'Enter your API token to import data directly.'**
  String get migrationEnterTokenDescription;

  /// Label for the API token input field
  ///
  /// In en, this message translates to:
  /// **'API Token'**
  String get migrationApiTokenLabel;

  /// Hint text for the API token input field
  ///
  /// In en, this message translates to:
  /// **'Paste your token here'**
  String get migrationPasteTokenHint;

  /// Tooltip to show the API token
  ///
  /// In en, this message translates to:
  /// **'Show token'**
  String get migrationShowToken;

  /// Tooltip to hide the API token
  ///
  /// In en, this message translates to:
  /// **'Hide token'**
  String get migrationHideToken;

  /// Tooltip for the paste-from-clipboard button
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get migrationPasteFromClipboard;

  /// Expandable help link label on the token input screen
  ///
  /// In en, this message translates to:
  /// **'Where do I find this?'**
  String get migrationWhereDoIFindThis;

  /// Help text explaining where to find the Simply Plural API token
  ///
  /// In en, this message translates to:
  /// **'In Simply Plural, go to Settings → Account → Tokens. Create a new token with Read permission and copy it.'**
  String get migrationTokenHelpText;

  /// Button label to verify the API token
  ///
  /// In en, this message translates to:
  /// **'Verify Token'**
  String get migrationVerifyToken;

  /// Status label shown when the Simply Plural token is verified
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get migrationConnected;

  /// Label showing the connected Simply Plural username
  ///
  /// In en, this message translates to:
  /// **'Signed in as {username}'**
  String migrationSignedInAs(String username);

  /// Button label to continue after token verification
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get migrationContinue;

  /// Headline shown while fetching data from Simply Plural API
  ///
  /// In en, this message translates to:
  /// **'Fetching data from Simply Plural…'**
  String get migrationFetchingData;

  /// Headline on the import preview step
  ///
  /// In en, this message translates to:
  /// **'Preview Import'**
  String get migrationPreviewImport;

  /// Body text on the import preview step
  ///
  /// In en, this message translates to:
  /// **'Review what was found before importing.'**
  String get migrationPreviewDescription;

  /// Info note on the import preview step
  ///
  /// In en, this message translates to:
  /// **'Imported data will be added alongside any existing data. Nothing will be overwritten.'**
  String get migrationImportInfoNote;

  /// Note shown when the API cannot provide reminders
  ///
  /// In en, this message translates to:
  /// **'Reminders are not available via the API. To import reminders, use a file export instead.'**
  String get migrationRemindersApiNote;

  /// Title for the warning shown when an old Simply Plural file export contains encrypted chat messages
  ///
  /// In en, this message translates to:
  /// **'Encrypted Simply Plural chats'**
  String get migrationEncryptedChatsTitle;

  /// Body text for the warning shown when an old Simply Plural file export contains encrypted chat messages
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This JSON export has 1 encrypted chat message from an older Simply Plural export. Prism cannot decrypt it.} other{This JSON export has {count} encrypted chat messages from an older Simply Plural export. Prism cannot decrypt them.}}'**
  String migrationEncryptedChatsDescription(int count);

  /// Help note explaining that newer Simply Plural exports should contain decrypted chat messages
  ///
  /// In en, this message translates to:
  /// **'Simply Plural fixed exports on March 8, 2026. A fresh export should include readable chat messages.'**
  String get migrationEncryptedChatsNote;

  /// Button label to continue importing Simply Plural data without chat channels or messages
  ///
  /// In en, this message translates to:
  /// **'Skip chat'**
  String get migrationEncryptedChatsSkip;

  /// Button label to reset and choose a newer Simply Plural export file
  ///
  /// In en, this message translates to:
  /// **'I\'ll get a fresh import'**
  String get migrationEncryptedChatsFresh;

  /// Button label when a previous import exists
  ///
  /// In en, this message translates to:
  /// **'Import All (add to existing)'**
  String get migrationImportAllAddToExisting;

  /// Button label to reset and re-import
  ///
  /// In en, this message translates to:
  /// **'Start Fresh (replace all data)'**
  String get migrationStartFresh;

  /// Button label to import all data
  ///
  /// In en, this message translates to:
  /// **'Import All'**
  String get migrationImportAll;

  /// Confirmation dialog title for replacing all data
  ///
  /// In en, this message translates to:
  /// **'Replace all data?'**
  String get migrationReplaceAllTitle;

  /// Confirmation dialog body for replacing all data
  ///
  /// In en, this message translates to:
  /// **'This will delete all existing {termPluralLower}, front history, conversations, and other data before importing. This action cannot be undone.\n\nIf you have sync set up, other paired devices should also be reset to avoid conflicts.'**
  String migrationReplaceAllMessage(String termPluralLower);

  /// Confirmation button to replace all data
  ///
  /// In en, this message translates to:
  /// **'Replace All'**
  String get migrationReplaceAll;

  /// Progress headline shown during import
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get migrationImporting;

  /// Headline shown when import finishes
  ///
  /// In en, this message translates to:
  /// **'Import Complete'**
  String get migrationImportComplete;

  /// Body text shown when import finishes
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {total} items in {seconds}s.'**
  String migrationImportSuccess(int total, int seconds);

  /// Section heading on the import complete view
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get migrationSummary;

  /// Import result row label for members
  ///
  /// In en, this message translates to:
  /// **'{termPlural}'**
  String migrationResultMembers(String termPlural);

  /// Import result row label for existing members linked during import
  ///
  /// In en, this message translates to:
  /// **'Matched {termPlural}'**
  String migrationResultMembersLinked(String termPlural);

  /// Import result row label for front sessions
  ///
  /// In en, this message translates to:
  /// **'Front sessions'**
  String get migrationResultFrontSessions;

  /// Import result row label for conversations
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get migrationResultConversations;

  /// Import result row label for messages
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get migrationResultMessages;

  /// Import result row label for polls
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get migrationResultPolls;

  /// Import result row label for notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get migrationResultNotes;

  /// Import result row label for comments
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get migrationResultComments;

  /// Import result row label for custom fields
  ///
  /// In en, this message translates to:
  /// **'Custom fields'**
  String get migrationResultCustomFields;

  /// Import result row label for groups
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get migrationResultGroups;

  /// Import result row label for reminders
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get migrationResultReminders;

  /// Import result row label for downloaded avatars
  ///
  /// In en, this message translates to:
  /// **'Avatars downloaded'**
  String get migrationResultAvatarsDownloaded;

  /// Warning count label on the import complete view
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 warning} other{{count} warnings}}'**
  String migrationWarnings(int count);

  /// Section heading for items that were not imported from SP
  ///
  /// In en, this message translates to:
  /// **'What didn\'t come over'**
  String get migrationNotImportedTitle;

  /// Friends item in the not-imported disclosure list
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get migrationNotImportedFriendsTitle;

  /// Explanation for why friends weren't imported
  ///
  /// In en, this message translates to:
  /// **'SP friends are separate accounts on another system. Prism doesn\'t have a cross-system friends concept yet.'**
  String get migrationNotImportedFriendsDetail;

  /// Board metadata item in not-imported list
  ///
  /// In en, this message translates to:
  /// **'Board message metadata'**
  String get migrationNotImportedBoardMetaTitle;

  /// Explanation for why board metadata wasn't imported
  ///
  /// In en, this message translates to:
  /// **'Message categories and bucket assignments aren\'t part of the export format.'**
  String get migrationNotImportedBoardMetaDetail;

  /// Notification preferences item in not-imported list
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get migrationNotImportedNotifTitle;

  /// Explanation for why notification prefs weren't imported
  ///
  /// In en, this message translates to:
  /// **'These are stored on your device in SP and aren\'t included in the export.'**
  String get migrationNotImportedNotifDetail;

  /// Front rules item in not-imported list
  ///
  /// In en, this message translates to:
  /// **'Custom front display rules'**
  String get migrationNotImportedFrontRulesTitle;

  /// Explanation for why front rules weren't imported
  ///
  /// In en, this message translates to:
  /// **'Display rules and front conditions don\'t map to Prism\'s system.'**
  String get migrationNotImportedFrontRulesDetail;

  /// Headline shown when import fails
  ///
  /// In en, this message translates to:
  /// **'Import Failed'**
  String get migrationImportFailed;

  /// Button to switch to file import after API import fails
  ///
  /// In en, this message translates to:
  /// **'Try file import instead'**
  String get migrationTryFileImport;

  /// Fallback error message
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred.'**
  String get migrationUnknownError;

  /// System name label on the import preview card
  ///
  /// In en, this message translates to:
  /// **'System: {name}'**
  String migrationPreviewSystem(String name);

  /// Section heading on the import preview card
  ///
  /// In en, this message translates to:
  /// **'Data found'**
  String get migrationPreviewDataFound;

  /// Preview card row label for front history entries
  ///
  /// In en, this message translates to:
  /// **'Front history entries'**
  String get migrationPreviewFrontHistoryEntries;

  /// Preview card row label for chat channels
  ///
  /// In en, this message translates to:
  /// **'Chat channels'**
  String get migrationPreviewChatChannels;

  /// Preview card row label for messages
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get migrationPreviewMessages;

  /// Preview card row label for total entities count
  ///
  /// In en, this message translates to:
  /// **'Total entities'**
  String get migrationPreviewTotalEntities;

  /// Preview card warnings section heading
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get migrationPreviewWarnings;

  /// Preview card row label for custom fronts
  ///
  /// In en, this message translates to:
  /// **'Custom fronts'**
  String get migrationPreviewCustomFronts;

  /// Preview card row label for groups
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get migrationPreviewGroups;

  /// Preview card row label for polls
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get migrationPreviewPolls;

  /// PluralKit setup screen title
  ///
  /// In en, this message translates to:
  /// **'PluralKit'**
  String get pluralkitTitle;

  /// Section header for PluralKit account
  ///
  /// In en, this message translates to:
  /// **'PluralKit Account'**
  String get pluralkitAccount;

  /// Section header for sync direction
  ///
  /// In en, this message translates to:
  /// **'Sync Direction'**
  String get pluralkitSyncDirection;

  /// Section header for sync actions
  ///
  /// In en, this message translates to:
  /// **'Sync Actions'**
  String get pluralkitSyncActions;

  /// Section header for how PluralKit sync works
  ///
  /// In en, this message translates to:
  /// **'How It Works'**
  String get pluralkitHowItWorks;

  /// Confirmation dialog title when disconnecting PluralKit
  ///
  /// In en, this message translates to:
  /// **'Disconnect PluralKit?'**
  String get pluralkitDisconnectTitle;

  /// Confirmation dialog body when disconnecting PluralKit
  ///
  /// In en, this message translates to:
  /// **'This will remove your token and disconnect from PluralKit. Your imported data will remain in the app.'**
  String get pluralkitDisconnectMessage;

  /// Button label to disconnect from PluralKit
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get pluralkitDisconnect;

  /// Status label when PluralKit token is connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get pluralkitConnected;

  /// Label showing when the last automatic sync occurred
  ///
  /// In en, this message translates to:
  /// **'Last sync: {when}'**
  String pluralkitLastSync(String when);

  /// Label showing when the last manual sync occurred
  ///
  /// In en, this message translates to:
  /// **'Last manual sync: {when}'**
  String pluralkitLastManualSync(String when);

  /// Label for the PluralKit token input field
  ///
  /// In en, this message translates to:
  /// **'PluralKit Token'**
  String get pluralkitTokenLabel;

  /// Hint text for the PluralKit token input field
  ///
  /// In en, this message translates to:
  /// **'Paste your token here'**
  String get pluralkitPasteTokenHint;

  /// Soft inline warning under the token field when the pasted token (after stripping whitespace) is not the expected PluralKit token length; submitting stays allowed
  ///
  /// In en, this message translates to:
  /// **'This doesn\'t look like a PluralKit token ({actual} characters — expected {expected}). You can still try connecting.'**
  String pluralkitTokenLengthWarning(int actual, int expected);

  /// Button label to connect PluralKit
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get pluralkitConnect;

  /// Help text for finding the PluralKit token
  ///
  /// In en, this message translates to:
  /// **'To get your token, DM the PluralKit bot on Discord with \"pk;token\" and paste the result here.'**
  String get pluralkitTokenHelp;

  /// Help text for the PluralKit settings file import entry point
  ///
  /// In en, this message translates to:
  /// **'Recover old PluralKit fronting history with a pk;export file and token. The file provides the switch history; the token lets Prism match it safely.'**
  String get pluralkitFileImportHelp;

  /// Button label to import all data from PluralKit
  ///
  /// In en, this message translates to:
  /// **'Import from PluralKit'**
  String get pluralkitImportButton;

  /// Button label to sync recent PluralKit changes
  ///
  /// In en, this message translates to:
  /// **'Sync Recent Changes'**
  String get pluralkitSyncRecent;

  /// Button label showing cooldown countdown
  ///
  /// In en, this message translates to:
  /// **'Sync Recent Changes ({seconds}s)'**
  String pluralkitSyncRecentCooldown(int seconds);

  /// Confirmation dialog title before running a PluralKit sync that may delete remote data
  ///
  /// In en, this message translates to:
  /// **'Sync may delete PluralKit data'**
  String get pluralkitDeleteRiskTitle;

  /// Confirmation button label for running a potentially destructive PluralKit sync
  ///
  /// In en, this message translates to:
  /// **'Sync Anyway'**
  String get pluralkitDeleteRiskConfirm;

  /// Cancel button label for a potentially destructive PluralKit sync
  ///
  /// In en, this message translates to:
  /// **'Cancel Sync'**
  String get pluralkitDeleteRiskCancel;

  /// Toast shown when Prism cannot preview a potentially destructive PluralKit sync
  ///
  /// In en, this message translates to:
  /// **'Prism couldn\'t check whether this sync would delete PluralKit data, so the sync was stopped.'**
  String get pluralkitDeleteRiskPreviewFailed;

  /// Confirmation body before a PluralKit sync removes remote data
  ///
  /// In en, this message translates to:
  /// **'This sync is about to remove {deleteText} from PluralKit. This usually means existing Prism data is linked to PluralKit records that are now marked for deletion.'**
  String pluralkitDeleteRiskMessage(String deleteText);

  /// Confirmation body before a PluralKit sync removes remote data, including skipped protected records
  ///
  /// In en, this message translates to:
  /// **'This sync is about to remove {deleteText} from PluralKit. This usually means existing Prism data is linked to PluralKit records that are now marked for deletion. Prism skipped {skippedCount, plural, =1{1 more item} other{{skippedCount} more items}} because they still look active or protected.'**
  String pluralkitDeleteRiskMessageWithSkipped(
    String deleteText,
    int skippedCount,
  );

  /// Count label for PluralKit members that may be deleted
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String pluralkitDeleteRiskMembers(int count);

  /// Count label for PluralKit switches that may be deleted
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 switch} other{{count} switches}}'**
  String pluralkitDeleteRiskSwitches(int count);

  /// Count label for PluralKit group memberships that may be removed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group membership} other{{count} group memberships}}'**
  String pluralkitDeleteRiskGroupMemberships(int count);

  /// Count label for PluralKit member proxy tags that may be removed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{proxy tags for 1 member} other{proxy tags for {count} members}}'**
  String pluralkitDeleteRiskProxyTags(int count);

  /// Joins two PluralKit delete-risk count labels
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String pluralkitDeleteRiskJoinTwo(String first, String second);

  /// Joins three PluralKit delete-risk count labels
  ///
  /// In en, this message translates to:
  /// **'{first}, {second}, and {third}'**
  String pluralkitDeleteRiskJoinThree(
    String first,
    String second,
    String third,
  );

  /// Description text for the sync direction picker
  ///
  /// In en, this message translates to:
  /// **'Choose how data flows between Prism and PluralKit.'**
  String get pluralkitSyncDirectionDescription;

  /// Description text for the PluralKit sync mode picker
  ///
  /// In en, this message translates to:
  /// **'Choose how much PluralKit data Prism syncs.'**
  String get pluralkitSyncModeDescription;

  /// PluralKit sync mode label for full sync
  ///
  /// In en, this message translates to:
  /// **'Full Sync'**
  String get pluralkitSyncModeFullSync;

  /// PluralKit sync mode label for live fronters only
  ///
  /// In en, this message translates to:
  /// **'Live Fronts Only'**
  String get pluralkitSyncModeLiveFrontsOnly;

  /// Explanatory text for PluralKit full sync mode
  ///
  /// In en, this message translates to:
  /// **'Sync recent PluralKit changes using the direction below. Import and pk;export recovery still run explicit full imports.'**
  String get pluralkitSyncModeFullSyncDescription;

  /// Explanatory text for PluralKit live fronts only mode
  ///
  /// In en, this message translates to:
  /// **'Records new PluralKit front changes while Prism is open. Older history, profile, group, and system data are left untouched.'**
  String get pluralkitSyncModeLiveFrontsOnlyDescription;

  /// Description text for the PluralKit sleep sync behavior picker
  ///
  /// In en, this message translates to:
  /// **'When Prism records sleep, choose how PluralKit should represent it.'**
  String get pluralkitSleepSyncBehaviorDescription;

  /// PluralKit sleep sync behavior label for leaving PK unchanged
  ///
  /// In en, this message translates to:
  /// **'Leave Unchanged'**
  String get pluralkitSleepSyncLeaveUnchanged;

  /// PluralKit sleep sync behavior label for clearing PK fronters
  ///
  /// In en, this message translates to:
  /// **'Clear Fronters'**
  String get pluralkitSleepSyncClearFronters;

  /// Explanatory text for leaving PK unchanged while sleeping
  ///
  /// In en, this message translates to:
  /// **'Prism records sleep locally and leaves PluralKit\'s current fronters as-is.'**
  String get pluralkitSleepSyncLeaveUnchangedDescription;

  /// Explanatory text for clearing PK fronters while sleeping
  ///
  /// In en, this message translates to:
  /// **'Prism records sleep locally and clears PluralKit\'s current fronters.'**
  String get pluralkitSleepSyncClearFrontersDescription;

  /// PluralKit sync direction: pull only
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get pluralkitPull;

  /// PluralKit sync direction: bidirectional
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get pluralkitBoth;

  /// PluralKit sync direction: push only
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get pluralkitPush;

  /// Card heading for the last PluralKit sync summary
  ///
  /// In en, this message translates to:
  /// **'Last Sync Summary'**
  String get pluralkitLastSyncSummary;

  /// Message when there are no sync changes
  ///
  /// In en, this message translates to:
  /// **'Everything is up to date.'**
  String get pluralkitUpToDate;

  /// Sync summary row: members pulled from PluralKit
  ///
  /// In en, this message translates to:
  /// **'{count} {termForCount} pulled'**
  String pluralkitMembersPulled(int count, String termForCount);

  /// Sync summary row: members pushed to PluralKit
  ///
  /// In en, this message translates to:
  /// **'{count} {termForCount} pushed'**
  String pluralkitMembersPushed(int count, String termForCount);

  /// Sync summary row: switches pulled from PluralKit
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 switch pulled} other{{count} switches pulled}}'**
  String pluralkitSwitchesPulled(int count);

  /// Sync summary row: switches pushed to PluralKit
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 switch pushed} other{{count} switches pushed}}'**
  String pluralkitSwitchesPushed(int count);

  /// Sync summary row: members with no changes
  ///
  /// In en, this message translates to:
  /// **'{count} {termForCount} unchanged'**
  String pluralkitMembersUnchanged(int count, String termForCount);

  /// How It Works info row about sync direction
  ///
  /// In en, this message translates to:
  /// **'Supports pull, push, or bidirectional sync. Choose your preferred direction above.'**
  String get pluralkitInfoSync;

  /// How It Works info row about token security
  ///
  /// In en, this message translates to:
  /// **'Your token is stored securely in the device keychain and never leaves your device.'**
  String get pluralkitInfoToken;

  /// How It Works info row about the link-members step
  ///
  /// In en, this message translates to:
  /// **'After connecting, link your PluralKit members to Prism {termPluralLower} — or import them as new — so nothing gets duplicated.'**
  String pluralkitInfoMembers(String termPluralLower);

  /// How It Works info row about fronting history recovery from PluralKit
  ///
  /// In en, this message translates to:
  /// **'Fronting history recovery uses a pk;export file plus a token so Prism can match export switches to PluralKit switch IDs.'**
  String get pluralkitInfoSwitches;

  /// Relative time label when PluralKit sync was less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get pluralkitJustNow;

  /// Review comparison heading for the local group
  ///
  /// In en, this message translates to:
  /// **'This group'**
  String get pluralkitRepairThisGroup;

  /// Review comparison heading for a known PluralKit candidate group
  ///
  /// In en, this message translates to:
  /// **'PK group'**
  String get pluralkitRepairPkGroup;

  /// Review comparison heading when only a suspected PluralKit UUID is known
  ///
  /// In en, this message translates to:
  /// **'PluralKit group'**
  String get pluralkitRepairPluralKitGroup;

  /// Fallback chip shown when no live PK reference data is available
  ///
  /// In en, this message translates to:
  /// **'Reconnect PluralKit to see comparison details'**
  String get pluralkitRepairReconnectForComparison;

  /// Chip showing shared PK member count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shared PK {termSingularLower}} other{{count} shared PK {termPluralLower}}}'**
  String pluralkitRepairSharedPkMembers(
    int count,
    String termSingularLower,
    String termPluralLower,
  );

  /// Chip showing local-only member count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 local-only {termSingularLower}} other{{count} local-only {termPluralLower}}}'**
  String pluralkitRepairLocalOnlyMembers(
    int count,
    String termSingularLower,
    String termPluralLower,
  );

  /// Chip showing candidate-only PK member count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 only in PK} other{{count} only in PK}}'**
  String pluralkitRepairOnlyInPkMembers(int count);

  /// Label for suspected PK UUID in repair review
  ///
  /// In en, this message translates to:
  /// **'Suspected PK UUID: {uuid}'**
  String pluralkitRepairSuspectedPkUuid(String uuid);

  /// Action preview sentence for repair review merge
  ///
  /// In en, this message translates to:
  /// **'Using this match will {summary}.'**
  String pluralkitRepairMergeActionPreview(String summary);

  /// Merge action preview fragment
  ///
  /// In en, this message translates to:
  /// **'link this local group to the suspected PK group'**
  String get pluralkitRepairPreviewLinkLocalGroup;

  /// Merge action preview fragment
  ///
  /// In en, this message translates to:
  /// **'preserve {count, plural, =1{1 shared PK membership} other{{count} shared PK memberships}}'**
  String pluralkitRepairPreviewPreserveShared(int count);

  /// Merge action preview fragment
  ///
  /// In en, this message translates to:
  /// **'keep {count, plural, =1{1 local-only membership} other{{count} local-only memberships}}'**
  String pluralkitRepairPreviewKeepLocalOnly(int count);

  /// Merge action preview fragment
  ///
  /// In en, this message translates to:
  /// **'leave {count, plural, =1{1 PK-only {termSingularLower}} other{{count} PK-only {termPluralLower}}} unmatched'**
  String pluralkitRepairPreviewLeavePkOnly(
    int count,
    String termSingularLower,
    String termPluralLower,
  );

  /// Button label for accepting the suggested PluralKit group match
  ///
  /// In en, this message translates to:
  /// **'Use this PluralKit match'**
  String get pluralkitRepairUsePluralKitMatch;

  /// Button label for keeping a reviewed local group separate from the suggested PluralKit group
  ///
  /// In en, this message translates to:
  /// **'Keep my Prism group'**
  String get pluralkitRepairKeepMyPrismGroup;

  /// Button label for dismissing a review item false positive
  ///
  /// In en, this message translates to:
  /// **'Dismiss false positive'**
  String get pluralkitRepairDismissFalsePositive;

  /// Section header for PluralKit group repair
  ///
  /// In en, this message translates to:
  /// **'Group repair'**
  String get pluralkitRepairSection;

  /// Dialog title for entering a temporary PK token for group repair
  ///
  /// In en, this message translates to:
  /// **'Temporary PluralKit token'**
  String get pluralkitRepairTemporaryTokenTitle;

  /// Dialog body for entering a temporary PK token for group repair
  ///
  /// In en, this message translates to:
  /// **'Use a one-off token for this repair run only. Prism will not save it.'**
  String get pluralkitRepairTemporaryTokenBody;

  /// Temporary PK token field label
  ///
  /// In en, this message translates to:
  /// **'PluralKit token'**
  String get pluralkitRepairTokenLabel;

  /// Temporary PK token field hint
  ///
  /// In en, this message translates to:
  /// **'Paste a temporary token'**
  String get pluralkitRepairTokenHint;

  /// Temporary PK token help text
  ///
  /// In en, this message translates to:
  /// **'This token is only used to compare your local groups against live PluralKit group data for one repair run.'**
  String get pluralkitRepairTemporaryTokenHelp;

  /// Button label to run PK group repair with a temporary token
  ///
  /// In en, this message translates to:
  /// **'Run token-backed repair'**
  String get pluralkitRepairRunTokenBacked;

  /// Loading label for PK group repair status
  ///
  /// In en, this message translates to:
  /// **'Loading repair status...'**
  String get pluralkitRepairLoadingStatus;

  /// No description provided for @pluralkitRepairCardTitle.
  ///
  /// In en, this message translates to:
  /// **'PluralKit group repair'**
  String get pluralkitRepairCardTitle;

  /// No description provided for @pluralkitRepairRunLocal.
  ///
  /// In en, this message translates to:
  /// **'Run local repair'**
  String get pluralkitRepairRunLocal;

  /// No description provided for @pluralkitRepairRun.
  ///
  /// In en, this message translates to:
  /// **'Run repair'**
  String get pluralkitRepairRun;

  /// No description provided for @pluralkitRepairResetAndReimport.
  ///
  /// In en, this message translates to:
  /// **'Reset PK groups and re-import'**
  String get pluralkitRepairResetAndReimport;

  /// No description provided for @pluralkitRepairResetOnly.
  ///
  /// In en, this message translates to:
  /// **'Reset PK groups only'**
  String get pluralkitRepairResetOnly;

  /// No description provided for @pluralkitRepairCurrentStatus.
  ///
  /// In en, this message translates to:
  /// **'Current status'**
  String get pluralkitRepairCurrentStatus;

  /// No description provided for @pluralkitRepairPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get pluralkitRepairPendingReview;

  /// No description provided for @pluralkitRepairLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last run'**
  String get pluralkitRepairLastRun;

  /// No description provided for @pluralkitRepairWhatChanged.
  ///
  /// In en, this message translates to:
  /// **'What changed'**
  String get pluralkitRepairWhatChanged;

  /// No description provided for @pluralkitRepairUseTemporaryToken.
  ///
  /// In en, this message translates to:
  /// **'Use temporary token'**
  String get pluralkitRepairUseTemporaryToken;

  /// No description provided for @pluralkitRepairCutoverTitle.
  ///
  /// In en, this message translates to:
  /// **'PK group sync v2 cutover'**
  String get pluralkitRepairCutoverTitle;

  /// No description provided for @pluralkitRepairSharedEnablement.
  ///
  /// In en, this message translates to:
  /// **'Shared enablement'**
  String get pluralkitRepairSharedEnablement;

  /// No description provided for @pluralkitRepairEnablePkGroupSync.
  ///
  /// In en, this message translates to:
  /// **'Enable PK group sync'**
  String get pluralkitRepairEnablePkGroupSync;

  /// No description provided for @pluralkitRepairHeadlineRunning.
  ///
  /// In en, this message translates to:
  /// **'Scanning linked groups, repairing obvious duplicates, and cross-checking live PK groups when a token is available.'**
  String get pluralkitRepairHeadlineRunning;

  /// No description provided for @pluralkitRepairHeadlinePending.
  ///
  /// In en, this message translates to:
  /// **'Ambiguous imported groups are currently suppressed so Prism does not create duplicate sync links.'**
  String get pluralkitRepairHeadlinePending;

  /// No description provided for @pluralkitRepairHeadlineReconnectRequired.
  ///
  /// In en, this message translates to:
  /// **'Local repair can still restore directly provable PK links, but reconnecting PluralKit is still required to reconstruct missing PK group identity automatically.'**
  String get pluralkitRepairHeadlineReconnectRequired;

  /// No description provided for @pluralkitRepairHeadlineChanged.
  ///
  /// In en, this message translates to:
  /// **'The last run made concrete local repair changes. Review the summary below before enabling PK-backed group sync.'**
  String get pluralkitRepairHeadlineChanged;

  /// No description provided for @pluralkitRepairHeadlineCompleted.
  ///
  /// In en, this message translates to:
  /// **'The last run completed. You can rerun repair after reconnecting or importing more PluralKit data.'**
  String get pluralkitRepairHeadlineCompleted;

  /// No description provided for @pluralkitRepairHeadlineDefault.
  ///
  /// In en, this message translates to:
  /// **'Fixes obvious PK group duplicates locally and flags ambiguous matches for follow-up review.'**
  String get pluralkitRepairHeadlineDefault;

  /// No description provided for @pluralkitRepairStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Repair running'**
  String get pluralkitRepairStatusRunning;

  /// No description provided for @pluralkitRepairStatusRetryNeeded.
  ///
  /// In en, this message translates to:
  /// **'Retry needed'**
  String get pluralkitRepairStatusRetryNeeded;

  /// No description provided for @pluralkitRepairStatusPendingReview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pending review} other{{count} pending review}}'**
  String pluralkitRepairStatusPendingReview(num count);

  /// No description provided for @pluralkitRepairStatusLastRunComplete.
  ///
  /// In en, this message translates to:
  /// **'Last run complete'**
  String get pluralkitRepairStatusLastRunComplete;

  /// No description provided for @pluralkitRepairStatusReadyToRun.
  ///
  /// In en, this message translates to:
  /// **'Ready to run'**
  String get pluralkitRepairStatusReadyToRun;

  /// No description provided for @pluralkitRepairTokenBackedReady.
  ///
  /// In en, this message translates to:
  /// **'Token-backed ready'**
  String get pluralkitRepairTokenBackedReady;

  /// No description provided for @pluralkitRepairLocalOnlyUntilToken.
  ///
  /// In en, this message translates to:
  /// **'Local-only until token'**
  String get pluralkitRepairLocalOnlyUntilToken;

  /// No description provided for @pluralkitRepairCheckingTokenAccess.
  ///
  /// In en, this message translates to:
  /// **'Checking token access'**
  String get pluralkitRepairCheckingTokenAccess;

  /// No description provided for @pluralkitRepairCutoverEnabledChip.
  ///
  /// In en, this message translates to:
  /// **'PK sync v2 enabled'**
  String get pluralkitRepairCutoverEnabledChip;

  /// No description provided for @pluralkitRepairCutoverOffChip.
  ///
  /// In en, this message translates to:
  /// **'PK sync v2 off'**
  String get pluralkitRepairCutoverOffChip;

  /// No description provided for @pluralkitRepairCheckingCutover.
  ///
  /// In en, this message translates to:
  /// **'Checking cutover'**
  String get pluralkitRepairCheckingCutover;

  /// No description provided for @pluralkitRepairCurrentRunning.
  ///
  /// In en, this message translates to:
  /// **'Repair is running now.'**
  String get pluralkitRepairCurrentRunning;

  /// No description provided for @pluralkitRepairCurrentError.
  ///
  /// In en, this message translates to:
  /// **'The last manual run failed. Retry below when you are ready.'**
  String get pluralkitRepairCurrentError;

  /// No description provided for @pluralkitRepairCurrentPending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group still needs review before it can be linked or cleared.} other{{count} groups still need review before they can be linked or cleared.}}'**
  String pluralkitRepairCurrentPending(num count);

  /// No description provided for @pluralkitRepairCurrentNoRun.
  ///
  /// In en, this message translates to:
  /// **'No repair run has been recorded in this app session yet.'**
  String get pluralkitRepairCurrentNoRun;

  /// No description provided for @pluralkitRepairCurrentReconnectRequired.
  ///
  /// In en, this message translates to:
  /// **'The last run finished the safe local repair pass, but missing PK group identity still needs a live PluralKit reference source to be reconstructed automatically.'**
  String get pluralkitRepairCurrentReconnectRequired;

  /// No description provided for @pluralkitRepairCurrentChanged.
  ///
  /// In en, this message translates to:
  /// **'The last run changed local PK group data. See the last-run summary below for the exact repairs applied.'**
  String get pluralkitRepairCurrentChanged;

  /// No description provided for @pluralkitRepairCurrentNoChanges.
  ///
  /// In en, this message translates to:
  /// **'The last run did not find any new PK group repairs to apply.'**
  String get pluralkitRepairCurrentNoChanges;

  /// No description provided for @pluralkitRepairCutoverHeadlineEnabled.
  ///
  /// In en, this message translates to:
  /// **'PK-backed group sync is enabled for this sync group. Manual/local-only groups still stay local.'**
  String get pluralkitRepairCutoverHeadlineEnabled;

  /// No description provided for @pluralkitRepairCutoverHeadlineReady.
  ///
  /// In en, this message translates to:
  /// **'Local repair prerequisites are satisfied. The remaining safety boundary is explicit operator confirmation of cutover.'**
  String get pluralkitRepairCutoverHeadlineReady;

  /// No description provided for @pluralkitRepairCutoverHeadlineBlocked.
  ///
  /// In en, this message translates to:
  /// **'PK-backed group sync stays off until repair is complete and you explicitly confirm that legacy devices are no longer paired.'**
  String get pluralkitRepairCutoverHeadlineBlocked;

  /// No description provided for @pluralkitRepairCutoverStatusLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the shared cutover setting for this sync group.'**
  String get pluralkitRepairCutoverStatusLoading;

  /// No description provided for @pluralkitRepairCutoverStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled for this sync group after explicit confirmation.'**
  String get pluralkitRepairCutoverStatusEnabled;

  /// No description provided for @pluralkitRepairCutoverStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Unavailable while repair is still running.'**
  String get pluralkitRepairCutoverStatusRunning;

  /// No description provided for @pluralkitRepairCutoverStatusNoRun.
  ///
  /// In en, this message translates to:
  /// **'Unavailable until a repair run completes in this app session.'**
  String get pluralkitRepairCutoverStatusNoRun;

  /// No description provided for @pluralkitRepairCutoverStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Unavailable until pending review items are resolved or kept local-only.'**
  String get pluralkitRepairCutoverStatusPending;

  /// No description provided for @pluralkitRepairCutoverStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to enable after explicit cutover confirmation.'**
  String get pluralkitRepairCutoverStatusReady;

  /// No description provided for @pluralkitRepairCutoverRecommendationEnabled.
  ///
  /// In en, this message translates to:
  /// **'This only affects PK-backed group sync. Manual/local-only groups remain unaffected.'**
  String get pluralkitRepairCutoverRecommendationEnabled;

  /// No description provided for @pluralkitRepairCutoverRecommendationRunFirst.
  ///
  /// In en, this message translates to:
  /// **'Run repair first. Prism keeps PK group sync v2 off until this client has completed a repair pass.'**
  String get pluralkitRepairCutoverRecommendationRunFirst;

  /// No description provided for @pluralkitRepairCutoverRecommendationPending.
  ///
  /// In en, this message translates to:
  /// **'Resolve each pending review item or explicitly keep it local-only before enabling cutover.'**
  String get pluralkitRepairCutoverRecommendationPending;

  /// No description provided for @pluralkitRepairCutoverRecommendationReady.
  ///
  /// In en, this message translates to:
  /// **'Only enable after every legacy 0.4.0+1-era device in this sync group has been upgraded, reset/re-paired, removed, or after you moved testing to a fresh sync group.'**
  String get pluralkitRepairCutoverRecommendationReady;

  /// No description provided for @pluralkitRepairPendingNone.
  ///
  /// In en, this message translates to:
  /// **'No ambiguous PK group matches are waiting for review.'**
  String get pluralkitRepairPendingNone;

  /// No description provided for @pluralkitRepairPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group still needs follow-up review.} other{{count} groups still need follow-up review.}}'**
  String pluralkitRepairPendingCount(num count);

  /// No description provided for @pluralkitRepairModeLocalOnlyRun.
  ///
  /// In en, this message translates to:
  /// **'Local-only run'**
  String get pluralkitRepairModeLocalOnlyRun;

  /// No description provided for @pluralkitRepairModeStoredTokenRun.
  ///
  /// In en, this message translates to:
  /// **'Stored-token run'**
  String get pluralkitRepairModeStoredTokenRun;

  /// No description provided for @pluralkitRepairModeTemporaryTokenRun.
  ///
  /// In en, this message translates to:
  /// **'Temporary-token run'**
  String get pluralkitRepairModeTemporaryTokenRun;

  /// No description provided for @pluralkitRepairLastRunPrefixLocal.
  ///
  /// In en, this message translates to:
  /// **'Local run'**
  String get pluralkitRepairLastRunPrefixLocal;

  /// No description provided for @pluralkitRepairLastRunPrefixStoredToken.
  ///
  /// In en, this message translates to:
  /// **'Stored-token run'**
  String get pluralkitRepairLastRunPrefixStoredToken;

  /// No description provided for @pluralkitRepairLastRunPrefixTemporaryToken.
  ///
  /// In en, this message translates to:
  /// **'Temporary-token run'**
  String get pluralkitRepairLastRunPrefixTemporaryToken;

  /// No description provided for @pluralkitRepairLastRunNoChanges.
  ///
  /// In en, this message translates to:
  /// **'{prefix} found no new PK group changes to apply.'**
  String pluralkitRepairLastRunNoChanges(Object prefix);

  /// No description provided for @pluralkitRepairLastRunChanged.
  ///
  /// In en, this message translates to:
  /// **'{prefix} {summary}.'**
  String pluralkitRepairLastRunChanged(Object prefix, Object summary);

  /// No description provided for @pluralkitRepairJoinPair.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String pluralkitRepairJoinPair(Object first, Object second);

  /// No description provided for @pluralkitRepairJoinSerial.
  ///
  /// In en, this message translates to:
  /// **'{leading}, and {last}'**
  String pluralkitRepairJoinSerial(Object last, Object leading);

  /// No description provided for @pluralkitRepairSummaryUpdatedParentLinks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{updated 1 child-group parent link} other{updated {count} child-group parent links}}'**
  String pluralkitRepairSummaryUpdatedParentLinks(num count);

  /// No description provided for @pluralkitRepairSummaryMovedMemberships.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{moved 1 group membership} other{moved {count} group memberships}}'**
  String pluralkitRepairSummaryMovedMemberships(num count);

  /// No description provided for @pluralkitRepairSummaryRemovedDuplicateGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{removed 1 duplicate local group} other{removed {count} duplicate local groups}}'**
  String pluralkitRepairSummaryRemovedDuplicateGroups(num count);

  /// No description provided for @pluralkitRepairSummaryRemovedConflictingMemberships.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{removed 1 conflicting group membership} other{removed {count} conflicting group memberships}}'**
  String pluralkitRepairSummaryRemovedConflictingMemberships(num count);

  /// No description provided for @pluralkitRepairSummarySuppressedAmbiguousGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{suppressed 1 ambiguous group for review} other{suppressed {count} ambiguous groups for review}}'**
  String pluralkitRepairSummarySuppressedAmbiguousGroups(num count);

  /// No description provided for @pluralkitRepairSummaryRestoredMissingMemberships.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{restored 1 missing PK membership link} other{restored {count} missing PK membership links}}'**
  String pluralkitRepairSummaryRestoredMissingMemberships(num count);

  /// No description provided for @pluralkitRepairSummaryRecordedLegacyAliases.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{recorded 1 legacy group alias} other{recorded {count} legacy group aliases}}'**
  String pluralkitRepairSummaryRecordedLegacyAliases(num count);

  /// No description provided for @pluralkitRepairDetailUpdatedParentLinks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 child-group parent link to point at the surviving group.} other{Updated {count} child-group parent links to point at the surviving group.}}'**
  String pluralkitRepairDetailUpdatedParentLinks(num count);

  /// No description provided for @pluralkitRepairDetailMovedMemberships.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Moved 1 group membership onto the surviving group.} other{Moved {count} group memberships onto the surviving group.}}'**
  String pluralkitRepairDetailMovedMemberships(num count);

  /// No description provided for @pluralkitRepairDetailRemovedDuplicateGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Removed 1 duplicate local group.} other{Removed {count} duplicate local groups.}}'**
  String pluralkitRepairDetailRemovedDuplicateGroups(num count);

  /// No description provided for @pluralkitRepairDetailRemovedConflictingMemberships.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Removed 1 conflicting group membership while merging duplicates.} other{Removed {count} conflicting group memberships while merging duplicates.}}'**
  String pluralkitRepairDetailRemovedConflictingMemberships(num count);

  /// No description provided for @pluralkitRepairDetailSuppressedAmbiguousGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Suppressed 1 ambiguous group for review before sync can continue.} other{Suppressed {count} ambiguous groups for review before sync can continue.}}'**
  String pluralkitRepairDetailSuppressedAmbiguousGroups(num count);

  /// No description provided for @pluralkitRepairDetailRestoredMissingMemberships.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Restored 1 missing PK membership link.} other{Restored {count} missing PK membership links.}}'**
  String pluralkitRepairDetailRestoredMissingMemberships(num count);

  /// No description provided for @pluralkitRepairDetailRecordedLegacyAliases.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Recorded 1 legacy group alias so older group IDs still resolve.} other{Recorded {count} legacy group aliases so older group IDs still resolve.}}'**
  String pluralkitRepairDetailRecordedLegacyAliases(num count);

  /// No description provided for @pluralkitRepairReferenceImportOnly.
  ///
  /// In en, this message translates to:
  /// **'This looks like import-only PK data with no local PK-linked groups left to use as repair references. Prism can still repair directly linked rows locally, but reconnecting PluralKit or using a temporary token is the only way to reconstruct missing PK group identity automatically.'**
  String get pluralkitRepairReferenceImportOnly;

  /// No description provided for @pluralkitRepairReferenceStoredTokenFailed.
  ///
  /// In en, this message translates to:
  /// **'A stored token exists, but the last live reference lookup failed. Reconnect PluralKit or use a temporary token if you want a full token-backed repair pass.'**
  String get pluralkitRepairReferenceStoredTokenFailed;

  /// No description provided for @pluralkitRepairReferenceReconnectOrToken.
  ///
  /// In en, this message translates to:
  /// **'Reconnect PluralKit above or use a temporary token for a fuller repair pass. Local repair still handles the obvious duplicates.'**
  String get pluralkitRepairReferenceReconnectOrToken;

  /// No description provided for @pluralkitRepairReferenceTokenRecommended.
  ///
  /// In en, this message translates to:
  /// **'A token-backed repair run is recommended when you can provide one. Until then, Prism will only run the safe local repair pass.'**
  String get pluralkitRepairReferenceTokenRecommended;

  /// No description provided for @pluralkitRepairReferenceLocalNow.
  ///
  /// In en, this message translates to:
  /// **'Repair can run locally now. Live PK cross-checks appear once token access is confirmed.'**
  String get pluralkitRepairReferenceLocalNow;

  /// No description provided for @pluralkitRepairReferenceError.
  ///
  /// In en, this message translates to:
  /// **'Live PK lookup failed on the last run, so Prism fell back to the local repair pass. {error}'**
  String pluralkitRepairReferenceError(Object error);

  /// No description provided for @pluralkitRepairError.
  ///
  /// In en, this message translates to:
  /// **'Repair failed: {error}'**
  String pluralkitRepairError(Object error);

  /// No description provided for @pluralkitRepairConfirmEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable PK sync v2?'**
  String get pluralkitRepairConfirmEnableTitle;

  /// No description provided for @pluralkitRepairConfirmEnableBody.
  ///
  /// In en, this message translates to:
  /// **'Only enable this after every legacy 0.4.0+1-era device has been upgraded, reset/re-paired, removed, or after you moved to a fresh sync group.'**
  String get pluralkitRepairConfirmEnableBody;

  /// No description provided for @pluralkitRepairConfirmEnableFootnote.
  ///
  /// In en, this message translates to:
  /// **'If any device is unaccounted for, keep this off. Manual/local-only groups stay local either way.'**
  String get pluralkitRepairConfirmEnableFootnote;

  /// No description provided for @pluralkitRepairConfirmEnableAction.
  ///
  /// In en, this message translates to:
  /// **'Enable PK sync v2'**
  String get pluralkitRepairConfirmEnableAction;

  /// No description provided for @pluralkitRepairConfirmResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset PK groups only?'**
  String get pluralkitRepairConfirmResetTitle;

  /// No description provided for @pluralkitRepairConfirmResetConnectedBody.
  ///
  /// In en, this message translates to:
  /// **'Prism will remove PK-linked and repair-suppressed groups, keep manual/local-only groups, clear deferred PK membership ops, and then re-import your current PK groups.'**
  String get pluralkitRepairConfirmResetConnectedBody;

  /// No description provided for @pluralkitRepairConfirmResetDisconnectedBody.
  ///
  /// In en, this message translates to:
  /// **'Prism will remove PK-linked and repair-suppressed groups, keep manual/local-only groups, and clear deferred PK membership ops. Reconnect PluralKit or import again afterward to rebuild them.'**
  String get pluralkitRepairConfirmResetDisconnectedBody;

  /// No description provided for @pluralkitRepairConfirmResetExportHint.
  ///
  /// In en, this message translates to:
  /// **'Export data first if you want a full backup before the reset.'**
  String get pluralkitRepairConfirmResetExportHint;

  /// No description provided for @pluralkitRepairConfirmResetExportFirst.
  ///
  /// In en, this message translates to:
  /// **'Export data first'**
  String get pluralkitRepairConfirmResetExportFirst;

  /// No description provided for @pluralkitRepairConfirmResetActionConnected.
  ///
  /// In en, this message translates to:
  /// **'Reset and re-import'**
  String get pluralkitRepairConfirmResetActionConnected;

  /// No description provided for @pluralkitRepairConfirmResetActionDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Reset PK groups'**
  String get pluralkitRepairConfirmResetActionDisconnected;

  /// No description provided for @pluralkitRepairFailedToast.
  ///
  /// In en, this message translates to:
  /// **'PluralKit group repair failed: {error}'**
  String pluralkitRepairFailedToast(Object error);

  /// No description provided for @pluralkitRepairReviewDismissed.
  ///
  /// In en, this message translates to:
  /// **'Group review dismissed. Sync suppression was cleared.'**
  String get pluralkitRepairReviewDismissed;

  /// No description provided for @pluralkitRepairKeepLocalOnlySuccess.
  ///
  /// In en, this message translates to:
  /// **'Group kept local-only. It will stay out of sync.'**
  String get pluralkitRepairKeepLocalOnlySuccess;

  /// No description provided for @pluralkitRepairMergedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Group linked to the PluralKit match.'**
  String get pluralkitRepairMergedSuccess;

  /// No description provided for @pluralkitRepairDismissReviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not dismiss this repair review item: {error}'**
  String pluralkitRepairDismissReviewFailed(Object error);

  /// No description provided for @pluralkitRepairKeepLocalOnlyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not keep this group local-only: {error}'**
  String pluralkitRepairKeepLocalOnlyFailed(Object error);

  /// No description provided for @pluralkitRepairMergeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not use this PluralKit match: {error}'**
  String pluralkitRepairMergeFailed(Object error);

  /// No description provided for @pluralkitRepairCutoverSettingsLoadingError.
  ///
  /// In en, this message translates to:
  /// **'Could not verify the shared cutover setting yet. Wait for repair status to finish loading and try again.'**
  String get pluralkitRepairCutoverSettingsLoadingError;

  /// No description provided for @pluralkitRepairCutoverAlreadyEnabled.
  ///
  /// In en, this message translates to:
  /// **'PK group sync v2 is already enabled for this sync group.'**
  String get pluralkitRepairCutoverAlreadyEnabled;

  /// No description provided for @pluralkitRepairCutoverRepairLoadingError.
  ///
  /// In en, this message translates to:
  /// **'Repair status is still loading or running. Wait for it to finish before enabling PK group sync v2.'**
  String get pluralkitRepairCutoverRepairLoadingError;

  /// No description provided for @pluralkitRepairCutoverRunRepairFirstError.
  ///
  /// In en, this message translates to:
  /// **'Run PluralKit group repair first. PK group sync v2 stays off until this client completes a repair pass.'**
  String get pluralkitRepairCutoverRunRepairFirstError;

  /// No description provided for @pluralkitRepairCutoverPendingReviewError.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Resolve or keep local-only the 1 pending review item before enabling PK group sync v2.} other{Resolve or keep local-only the {count} pending review items before enabling PK group sync v2.}}'**
  String pluralkitRepairCutoverPendingReviewError(num count);

  /// No description provided for @pluralkitRepairCutoverEnabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'PK group sync v2 enabled for this sync group. Manual/local-only groups are unchanged.'**
  String get pluralkitRepairCutoverEnabledSuccess;

  /// No description provided for @pluralkitRepairCutoverEnableFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not enable PK group sync v2: {error}'**
  String pluralkitRepairCutoverEnableFailed(Object error);

  /// No description provided for @pluralkitRepairResetNoGroupsNeeded.
  ///
  /// In en, this message translates to:
  /// **'No PK-backed or repair-suppressed groups needed reset on this device.'**
  String get pluralkitRepairResetNoGroupsNeeded;

  /// No description provided for @pluralkitRepairResetFinishedReconnect.
  ///
  /// In en, this message translates to:
  /// **'PK group reset finished. {summary} Reconnect PluralKit or import from a file to rebuild them.'**
  String pluralkitRepairResetFinishedReconnect(Object summary);

  /// No description provided for @pluralkitRepairResetFinishedReimported.
  ///
  /// In en, this message translates to:
  /// **'PK group reset finished. {summary} Current PK groups were re-imported.'**
  String pluralkitRepairResetFinishedReimported(Object summary);

  /// No description provided for @pluralkitRepairResetFinishedReimportFailed.
  ///
  /// In en, this message translates to:
  /// **'PK group reset finished, but re-import failed: {error}. {summary}'**
  String pluralkitRepairResetFinishedReimportFailed(
    Object error,
    Object summary,
  );

  /// No description provided for @pluralkitRepairResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reset PK groups: {error}'**
  String pluralkitRepairResetFailed(Object error);

  /// No description provided for @pluralkitRepairNoNewNeeded.
  ///
  /// In en, this message translates to:
  /// **'No new PK group repairs were needed.'**
  String get pluralkitRepairNoNewNeeded;

  /// No description provided for @pluralkitRepairSuccessLocalLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Repair finished locally. {detail} Live PK lookup failed, so a token-backed rerun is still recommended.'**
  String pluralkitRepairSuccessLocalLookupFailed(Object detail);

  /// No description provided for @pluralkitRepairSuccessLocalLookupFailedWithFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Repair finished locally. {detail} {followUp} Live PK lookup failed, so a token-backed rerun is still recommended.'**
  String pluralkitRepairSuccessLocalLookupFailedWithFollowUp(
    Object detail,
    Object followUp,
  );

  /// No description provided for @pluralkitRepairSuccessWithFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Repair finished. {detail} {followUp}'**
  String pluralkitRepairSuccessWithFollowUp(Object detail, Object followUp);

  /// No description provided for @pluralkitRepairSuccess.
  ///
  /// In en, this message translates to:
  /// **'Repair finished. {detail}'**
  String pluralkitRepairSuccess(Object detail);

  /// No description provided for @pluralkitRepairFollowUpPendingReview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 suppressed group still needs follow-up review.} other{{count} suppressed groups still need follow-up review.}}'**
  String pluralkitRepairFollowUpPendingReview(num count);

  /// No description provided for @pluralkitRepairStatusLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load repair status: {error}'**
  String pluralkitRepairStatusLoadFailed(Object error);

  /// No description provided for @pluralkitRepairResetSummaryRemovedGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{removed 1 PK-backed or suppressed group} other{removed {count} PK-backed or suppressed groups}}'**
  String pluralkitRepairResetSummaryRemovedGroups(num count);

  /// No description provided for @pluralkitRepairResetSummaryPromotedChildGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{promoted 1 local child group to root} other{promoted {count} local child groups to root}}'**
  String pluralkitRepairResetSummaryPromotedChildGroups(num count);

  /// No description provided for @pluralkitRepairResetSummaryClearedDeferredOps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{cleared 1 deferred PK membership op} other{cleared {count} deferred PK membership ops}}'**
  String pluralkitRepairResetSummaryClearedDeferredOps(num count);

  /// No description provided for @pluralkitRepairResetSummaryNoGroupsNeeded.
  ///
  /// In en, this message translates to:
  /// **'No PK-backed groups needed reset.'**
  String get pluralkitRepairResetSummaryNoGroupsNeeded;

  /// Relative time label for minutes ago in PluralKit
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String pluralkitMinutesAgo(int minutes);

  /// Relative time label for hours ago in PluralKit
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String pluralkitHoursAgo(int hours);

  /// Relative time label for days ago in PluralKit
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String pluralkitDaysAgo(int days);

  /// Per-member progress status while importing PluralKit members
  ///
  /// In en, this message translates to:
  /// **'Importing member {current}/{total}: {name}'**
  String pluralkitImportingMember(int current, int total, String name);

  /// Per-member progress status while importing PluralKit members from a pk;export file
  ///
  /// In en, this message translates to:
  /// **'Importing member {current}/{total} from file: {name}'**
  String pluralkitImportingMemberFromFile(int current, int total, String name);

  /// Export sheet top bar title
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get dataManagementExportTitle;

  /// Import sheet top bar title
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get dataManagementImportTitle;

  /// Import/export screen top bar title
  ///
  /// In en, this message translates to:
  /// **'Import & Export'**
  String get dataManagementImportExportTitle;

  /// Section title for the export row on the import/export screen
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get dataManagementExportSectionTitle;

  /// Section title for the import row on the import/export screen
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get dataManagementImportSectionTitle;

  /// Section title for other app imports
  ///
  /// In en, this message translates to:
  /// **'Import from Other Apps'**
  String get dataManagementImportFromOtherApps;

  /// Settings row title for exporting data
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get dataManagementExportRowTitle;

  /// Settings row subtitle for exporting data
  ///
  /// In en, this message translates to:
  /// **'Create a password-protected backup'**
  String get dataManagementExportRowSubtitle;

  /// Settings row title for importing data
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get dataManagementImportRowTitle;

  /// Settings row subtitle for importing data
  ///
  /// In en, this message translates to:
  /// **'Restore data from a Prism export file (.json or .prism)'**
  String get dataManagementImportRowSubtitle;

  /// Settings row subtitle for PluralKit import
  ///
  /// In en, this message translates to:
  /// **'Import {termPluralLower} & fronting via API token'**
  String dataManagementPluralKitRowSubtitle(String termPluralLower);

  /// Settings row title for Simply Plural import
  ///
  /// In en, this message translates to:
  /// **'Simply Plural'**
  String get dataManagementSimplyPluralRowTitle;

  /// Settings row subtitle for Simply Plural import
  ///
  /// In en, this message translates to:
  /// **'Import from a Simply Plural export file'**
  String get dataManagementSimplyPluralRowSubtitle;

  /// Headline on the export idle state
  ///
  /// In en, this message translates to:
  /// **'Export Your Data'**
  String get dataManagementExportYourData;

  /// Body text on the export idle state
  ///
  /// In en, this message translates to:
  /// **'Create a password-protected backup of all your data including {termPluralLower}, fronting sessions, messages, polls, and settings.'**
  String dataManagementExportDescription(String termPluralLower);

  /// Button label to start the export flow
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get dataManagementExportButton;

  /// Headline on the export password step
  ///
  /// In en, this message translates to:
  /// **'Encrypt Export'**
  String get dataManagementEncryptExport;

  /// Body text on the export password step
  ///
  /// In en, this message translates to:
  /// **'Set a password to encrypt your export file. You will need this password to import the data later.'**
  String get dataManagementEncryptDescription;

  /// Warning about unencrypted exports
  ///
  /// In en, this message translates to:
  /// **'Unencrypted exports are plain JSON. Anyone who opens the file can read its contents.'**
  String get dataManagementUnencryptedWarning;

  /// Label for the export password field
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get dataManagementPasswordLabel;

  /// Hint for the export password field
  ///
  /// In en, this message translates to:
  /// **'At least 12 characters — a long passphrase is best'**
  String get dataManagementPasswordHint;

  /// Tooltip to show the password
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get dataManagementShowPassword;

  /// Tooltip to hide the password
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get dataManagementHidePassword;

  /// Label for the confirm password field
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get dataManagementConfirmPasswordLabel;

  /// Button label to export without encryption
  ///
  /// In en, this message translates to:
  /// **'Export Unencrypted'**
  String get dataManagementExportUnencrypted;

  /// Button label to encrypt and export
  ///
  /// In en, this message translates to:
  /// **'Encrypt'**
  String get dataManagementEncrypt;

  /// Progress message while exporting
  ///
  /// In en, this message translates to:
  /// **'Exporting your data…'**
  String get dataManagementExporting;

  /// Hint that the operation may take some time
  ///
  /// In en, this message translates to:
  /// **'This may take a moment.'**
  String get dataManagementMayTakeMoment;

  /// Headline when export fails
  ///
  /// In en, this message translates to:
  /// **'Export Failed'**
  String get dataManagementExportFailed;

  /// Button label to retry a failed export
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get dataManagementRetry;

  /// Headline when export succeeds
  ///
  /// In en, this message translates to:
  /// **'Export Complete'**
  String get dataManagementExportComplete;

  /// Headline shown after the export is built but before the user has saved it
  ///
  /// In en, this message translates to:
  /// **'Export Ready'**
  String get dataManagementExportReadyTitle;

  /// Body text explaining that the export still needs to be saved
  ///
  /// In en, this message translates to:
  /// **'Tap Save to choose where to keep your export. The file is only kept in temporary storage until you save it somewhere.'**
  String get dataManagementExportReadyDescription;

  /// Button label to open the share sheet for the prepared export file
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get dataManagementShareExport;

  /// Confirmation dialog title for unencrypted export
  ///
  /// In en, this message translates to:
  /// **'Export without encryption?'**
  String get dataManagementExportWithoutEncryptionTitle;

  /// Confirmation dialog body for unencrypted export
  ///
  /// In en, this message translates to:
  /// **'This will create a plain JSON file that anyone who opens it can read. Use encrypted export unless you specifically need an insecure backup.'**
  String get dataManagementExportWithoutEncryptionMessage;

  /// Confirmation button for unencrypted export dialog
  ///
  /// In en, this message translates to:
  /// **'Export Unencrypted'**
  String get dataManagementExportUnencryptedConfirm;

  /// Validation error when password is empty
  ///
  /// In en, this message translates to:
  /// **'Password cannot be empty'**
  String get dataManagementPasswordEmpty;

  /// Validation error when password is too short
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 12 characters'**
  String get dataManagementPasswordTooShort;

  /// Validation error when passwords do not match
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get dataManagementPasswordMismatch;

  /// Button label to pick an import file
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get dataManagementSelectFile;

  /// Body text on the import idle state
  ///
  /// In en, this message translates to:
  /// **'Select a Prism export file (.json or .prism) to restore your data. Existing data will not be overwritten.'**
  String get dataManagementImportFileDescription;

  /// Headline when the selected import file is encrypted
  ///
  /// In en, this message translates to:
  /// **'Encrypted File'**
  String get dataManagementEncryptedFile;

  /// Body text when the import file is encrypted
  ///
  /// In en, this message translates to:
  /// **'This export file is encrypted. Enter the password that was used when the export was created.'**
  String get dataManagementEncryptedFileDescription;

  /// Button label to decrypt the import file
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get dataManagementDecrypt;

  /// Headline on the import preview step
  ///
  /// In en, this message translates to:
  /// **'Import Preview'**
  String get dataManagementImportPreview;

  /// Label showing when the export was created
  ///
  /// In en, this message translates to:
  /// **'Exported: {date}'**
  String dataManagementExportedDate(String date);

  /// Import preview row label for members
  ///
  /// In en, this message translates to:
  /// **'{termPlural}'**
  String dataManagementPreviewMembers(String termPlural);

  /// Import preview row label for front sessions
  ///
  /// In en, this message translates to:
  /// **'Front Sessions'**
  String get dataManagementPreviewFrontSessions;

  /// Import preview row label for sleep sessions
  ///
  /// In en, this message translates to:
  /// **'Sleep Sessions'**
  String get dataManagementPreviewSleepSessions;

  /// Import preview row label for conversations
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get dataManagementPreviewConversations;

  /// Import preview row label for messages
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get dataManagementPreviewMessages;

  /// Import preview row label for polls
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get dataManagementPreviewPolls;

  /// Import preview row label for poll options
  ///
  /// In en, this message translates to:
  /// **'Poll Options'**
  String get dataManagementPreviewPollOptions;

  /// Import preview row label for settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get dataManagementPreviewSettings;

  /// Import preview row label for habits
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get dataManagementPreviewHabits;

  /// Import preview row label for habit completions
  ///
  /// In en, this message translates to:
  /// **'Habit Completions'**
  String get dataManagementPreviewHabitCompletions;

  /// Import preview row label for member groups
  ///
  /// In en, this message translates to:
  /// **'Member Groups'**
  String get dataManagementPreviewMemberGroups;

  /// Import preview row label for member group membership records
  ///
  /// In en, this message translates to:
  /// **'Member Group Entries'**
  String get dataManagementPreviewMemberGroupEntries;

  /// Import preview row label for custom fields
  ///
  /// In en, this message translates to:
  /// **'Custom Fields'**
  String get dataManagementPreviewCustomFields;

  /// Import preview row label for custom field values
  ///
  /// In en, this message translates to:
  /// **'Custom Field Values'**
  String get dataManagementPreviewCustomFieldValues;

  /// Import preview row label for notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get dataManagementPreviewNotes;

  /// Import preview row label for front session comments
  ///
  /// In en, this message translates to:
  /// **'Front Session Comments'**
  String get dataManagementPreviewFrontSessionComments;

  /// Import preview row label for conversation categories
  ///
  /// In en, this message translates to:
  /// **'Conversation Categories'**
  String get dataManagementPreviewConversationCategories;

  /// Import preview row label for reminders
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get dataManagementPreviewReminders;

  /// Import preview row label for friend records
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get dataManagementPreviewFriends;

  /// Import preview row label for media attachments
  ///
  /// In en, this message translates to:
  /// **'Media Attachments'**
  String get dataManagementPreviewMediaAttachments;

  /// Import preview row label for member board posts
  ///
  /// In en, this message translates to:
  /// **'Member Board Posts'**
  String get dataManagementPreviewMemberBoardPosts;

  /// Import preview row label for app preferences
  ///
  /// In en, this message translates to:
  /// **'App Preferences'**
  String get dataManagementPreviewAppPreferences;

  /// Import preview row label for total records
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get dataManagementPreviewTotal;

  /// Import complete row label for total records created
  ///
  /// In en, this message translates to:
  /// **'Total Created'**
  String get dataManagementPreviewTotalCreated;

  /// Button label to start the import
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get dataManagementImport;

  /// Progress message while importing
  ///
  /// In en, this message translates to:
  /// **'Importing your data…'**
  String get dataManagementImporting;

  /// Hint shown while importing
  ///
  /// In en, this message translates to:
  /// **'This may take a moment. Do not close the app.'**
  String get dataManagementImportingMessage;

  /// Headline when import succeeds
  ///
  /// In en, this message translates to:
  /// **'Import Complete'**
  String get dataManagementImportComplete;

  /// Import warning when abandoned timestamp-only front session comments could not be restored because they lacked a usable session id
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 fronting comment was dropped because it was not attached to a session.} other{{count} fronting comments were dropped because they were not attached to a session.}}'**
  String dataImportTimestampOnlyCommentsDropped(int count);

  /// Headline when import fails
  ///
  /// In en, this message translates to:
  /// **'Import Failed'**
  String get dataManagementImportFailed;

  /// Note shown when import fails
  ///
  /// In en, this message translates to:
  /// **'No data was imported. The database was not modified.'**
  String get dataManagementImportFailedNote;

  /// Error shown when the import file password is wrong
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get dataManagementIncorrectPassword;

  /// Error shown when import file decryption fails
  ///
  /// In en, this message translates to:
  /// **'Decryption failed: {error}'**
  String dataManagementDecryptionFailed(String error);

  /// Error when user imports an unencrypted Prism JSON backup
  ///
  /// In en, this message translates to:
  /// **'This backup isn\'t encrypted. Re-export from the app to get a secure .prism file.'**
  String get dataManagementUnencryptedBackup;

  /// Validation error when import password is empty
  ///
  /// In en, this message translates to:
  /// **'Password cannot be empty'**
  String get dataManagementPasswordEmptyImport;

  /// Sharing screen title
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get sharingTitle;

  /// Tooltip for refresh inbox button
  ///
  /// In en, this message translates to:
  /// **'Refresh inbox'**
  String get sharingRefreshInbox;

  /// Tooltip for use sharing code button
  ///
  /// In en, this message translates to:
  /// **'Use sharing code'**
  String get sharingUseSharingCodeTooltip;

  /// Tooltip for share your code button
  ///
  /// In en, this message translates to:
  /// **'Share your code'**
  String get sharingShareYourCodeTooltip;

  /// Section header for pending sharing requests
  ///
  /// In en, this message translates to:
  /// **'Pending Requests'**
  String get sharingPendingRequests;

  /// Section header for established sharing relationships
  ///
  /// In en, this message translates to:
  /// **'Trusted People'**
  String get sharingTrustedPeople;

  /// Empty state title on sharing screen
  ///
  /// In en, this message translates to:
  /// **'No sharing relationships yet'**
  String get sharingEmptyTitle;

  /// Empty state subtitle on sharing screen
  ///
  /// In en, this message translates to:
  /// **'Share your code so someone can send you a request, or use someone else\'s code to connect.'**
  String get sharingEmptySubtitle;

  /// Button label to open create invite sheet
  ///
  /// In en, this message translates to:
  /// **'Share My Code'**
  String get sharingShareMyCode;

  /// Button label to open accept invite sheet
  ///
  /// In en, this message translates to:
  /// **'Use a Code'**
  String get sharingUseACode;

  /// Toast message after sending a sharing request
  ///
  /// In en, this message translates to:
  /// **'Sharing request sent. They will see it the next time they check sharing.'**
  String get sharingRequestSent;

  /// Toast when inbox refresh finds no new requests
  ///
  /// In en, this message translates to:
  /// **'No new sharing requests'**
  String get sharingNoNewRequests;

  /// Error toast when inbox refresh fails
  ///
  /// In en, this message translates to:
  /// **'Unable to refresh sharing inbox'**
  String get sharingUnableToRefresh;

  /// Error message when sync is not set up
  ///
  /// In en, this message translates to:
  /// **'Sync is not configured'**
  String get sharingSyncNotConfigured;

  /// Toast when a sharing request is accepted
  ///
  /// In en, this message translates to:
  /// **'Sharing request accepted'**
  String get sharingRequestAccepted;

  /// Error toast when accepting a sharing request fails
  ///
  /// In en, this message translates to:
  /// **'Unable to accept request'**
  String get sharingUnableToAccept;

  /// Toast when a sharing request is dismissed
  ///
  /// In en, this message translates to:
  /// **'Request dismissed'**
  String get sharingRequestDismissed;

  /// Confirmation dialog title for removing a friend
  ///
  /// In en, this message translates to:
  /// **'Remove relationship'**
  String get sharingRemoveTitle;

  /// Confirmation dialog body for removing a friend
  ///
  /// In en, this message translates to:
  /// **'Remove {name} and revoke their access? This cannot be undone.'**
  String sharingRemoveMessage(String name);

  /// Confirm button for removing a friend
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get sharingRemove;

  /// Subtitle when a friend has no granted scopes
  ///
  /// In en, this message translates to:
  /// **'No scopes granted'**
  String get sharingNoScopesGranted;

  /// Relative time: less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get sharingJustNow;

  /// Relative time: N minutes ago
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String sharingMinutesAgo(int minutes);

  /// Relative time: N hours ago
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String sharingHoursAgo(int hours);

  /// Relative time: N days ago
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String sharingDaysAgo(int days);

  /// Button to ignore a pending sharing request that can be accepted
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get sharingIgnore;

  /// Button to dismiss a pending sharing request that cannot be accepted
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get sharingDismiss;

  /// Button to accept a pending sharing request
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get sharingAccept;

  /// Title on the accept invite sheet
  ///
  /// In en, this message translates to:
  /// **'Use Sharing Code'**
  String get sharingUseSharingCode;

  /// Label for the sharing code input field
  ///
  /// In en, this message translates to:
  /// **'Sharing code'**
  String get sharingSharingCodeLabel;

  /// Hint for the sharing code input field
  ///
  /// In en, this message translates to:
  /// **'Paste the code you received'**
  String get sharingSharingCodeHint;

  /// Status text when a valid invite with a display name is parsed
  ///
  /// In en, this message translates to:
  /// **'Connecting with {name}'**
  String sharingConnectingWith(String name);

  /// Status text when a valid invite without a display name is parsed
  ///
  /// In en, this message translates to:
  /// **'Ready to send a sharing request'**
  String get sharingReadyToSend;

  /// Label for the display name field on accept invite sheet
  ///
  /// In en, this message translates to:
  /// **'Your display name'**
  String get sharingYourDisplayName;

  /// Hint for the display name field on accept invite sheet
  ///
  /// In en, this message translates to:
  /// **'How they will see you'**
  String get sharingDisplayNameHint;

  /// Section heading for scope selection on accept invite sheet
  ///
  /// In en, this message translates to:
  /// **'What to share'**
  String get sharingWhatToShare;

  /// Button label while submitting a sharing request
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sharingSending;

  /// Button label to send a sharing request
  ///
  /// In en, this message translates to:
  /// **'Send Request'**
  String get sharingSendRequest;

  /// Error when the sharing code cannot be parsed
  ///
  /// In en, this message translates to:
  /// **'Invalid sharing code'**
  String get sharingInvalidCode;

  /// Error when sending a sharing request fails
  ///
  /// In en, this message translates to:
  /// **'Failed to send sharing request: {error}'**
  String sharingFailedToSend(Object error);

  /// Title on the create invite sheet when an invite exists
  ///
  /// In en, this message translates to:
  /// **'Share Your Code'**
  String get sharingShareYourCode;

  /// Title on the create invite sheet before generating an invite
  ///
  /// In en, this message translates to:
  /// **'Enable Sharing'**
  String get sharingEnableSharing;

  /// Description text on the create invite sheet
  ///
  /// In en, this message translates to:
  /// **'Sharing uses a stable code instead of an inline key exchange. Anyone with this code can send you a sharing request.'**
  String get sharingDescription;

  /// Label for the optional display name field on create invite sheet
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get sharingDisplayNameOptionalLabel;

  /// Hint for the optional display name field on create invite sheet
  ///
  /// In en, this message translates to:
  /// **'Shown to the person opening your code'**
  String get sharingDisplayNameOptionalHint;

  /// Card heading for the generated sharing code
  ///
  /// In en, this message translates to:
  /// **'Sharing Code'**
  String get sharingSharingCodeTitle;

  /// Note about the sharing code validity
  ///
  /// In en, this message translates to:
  /// **'This code stays valid until you turn sharing off.'**
  String get sharingCodeValidNote;

  /// Button label to copy the sharing code
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get sharingCopy;

  /// Error when enabling sharing fails
  ///
  /// In en, this message translates to:
  /// **'Failed to enable sharing: {error}'**
  String sharingFailedToEnable(Object error);

  /// Toast when sharing code is copied to clipboard
  ///
  /// In en, this message translates to:
  /// **'Sharing code copied (auto-clears in 15s)'**
  String get sharingCodeCopied;

  /// Fallback title on friend detail screen
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get sharingFriend;

  /// Message when friend is not found on detail screen
  ///
  /// In en, this message translates to:
  /// **'Friend not found'**
  String get sharingFriendNotFound;

  /// Section heading for granted scopes on friend detail screen
  ///
  /// In en, this message translates to:
  /// **'Granted Scopes'**
  String get sharingGrantedScopes;

  /// Label for the sharing ID row on friend detail screen
  ///
  /// In en, this message translates to:
  /// **'Sharing ID'**
  String get sharingSharingId;

  /// Tooltip to copy the sharing ID
  ///
  /// In en, this message translates to:
  /// **'Copy sharing ID'**
  String get sharingCopySharingId;

  /// Toast when sharing ID is copied
  ///
  /// In en, this message translates to:
  /// **'Sharing ID copied'**
  String get sharingSharingIdCopied;

  /// Label for the last synced row on friend detail screen
  ///
  /// In en, this message translates to:
  /// **'Last synced'**
  String get sharingLastSynced;

  /// Button label to revoke a friend's access
  ///
  /// In en, this message translates to:
  /// **'Revoke Access'**
  String get sharingRevokeAccess;

  /// Status label for a verified friend
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get sharingVerified;

  /// Status label for an unverified friend
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get sharingNotVerified;

  /// Label showing when a friend was added
  ///
  /// In en, this message translates to:
  /// **'Added {date}'**
  String sharingAddedDate(String date);

  /// Heading on the verification card for unverified friends
  ///
  /// In en, this message translates to:
  /// **'Verification Recommended'**
  String get sharingVerificationRecommended;

  /// Body text on the verification card
  ///
  /// In en, this message translates to:
  /// **'Compare fingerprints with {name} out of band before marking this relationship as verified.'**
  String sharingVerificationDescription(String name);

  /// Button to open the fingerprint comparison dialog
  ///
  /// In en, this message translates to:
  /// **'Compare Fingerprint'**
  String get sharingCompareFingerprint;

  /// Title of the security fingerprint dialog
  ///
  /// In en, this message translates to:
  /// **'Security Fingerprint'**
  String get sharingSecurityFingerprintTitle;

  /// Instruction text in the fingerprint dialog
  ///
  /// In en, this message translates to:
  /// **'Compare this fingerprint with {name}. Only mark it verified if they see the same value.'**
  String sharingFingerprintCompareText(String name);

  /// Warning text in the fingerprint dialog
  ///
  /// In en, this message translates to:
  /// **'Do not verify if the fingerprints differ.'**
  String get sharingFingerprintWarning;

  /// Button to mark a friend as verified
  ///
  /// In en, this message translates to:
  /// **'Mark Verified'**
  String get sharingMarkVerified;

  /// Confirmation dialog title for revoking a friend's access
  ///
  /// In en, this message translates to:
  /// **'Revoke access'**
  String get sharingRevokeTitle;

  /// Confirmation dialog body for revoking a friend's access
  ///
  /// In en, this message translates to:
  /// **'Revoke all access for {name}? Resource keys will be rotated.'**
  String sharingRevokeMessage(String name);

  /// Confirm button for revoking access
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get sharingRevoke;

  /// Error toast when fingerprint cannot be computed
  ///
  /// In en, this message translates to:
  /// **'Unable to compute fingerprint'**
  String get sharingUnableToComputeFingerprint;

  /// Toast when fingerprint or identity is copied
  ///
  /// In en, this message translates to:
  /// **'{label} copied'**
  String sharingFingerprintCopied(String label);

  /// Tooltip for copying fingerprint or identity
  ///
  /// In en, this message translates to:
  /// **'Copy {label}'**
  String sharingCopyLabel(String label);

  /// Label for fingerprint row when fingerprint data is available
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get sharingFingerprint;

  /// Label for identity row when fingerprint data is not yet loaded
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get sharingIdentity;

  /// Title of the Reminders screen
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get remindersTitle;

  /// Error message when reminders fail to load
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String remindersLoadError(String error);

  /// Empty state title on reminders screen
  ///
  /// In en, this message translates to:
  /// **'No reminders'**
  String get remindersEmptyTitle;

  /// Empty state subtitle on reminders screen
  ///
  /// In en, this message translates to:
  /// **'Create reminders for fronting changes or scheduled times'**
  String get remindersEmptySubtitle;

  /// Empty state action button label on reminders screen
  ///
  /// In en, this message translates to:
  /// **'Add Reminder'**
  String get remindersEmptyAction;

  /// Confirmation dialog title when disabling a reminder
  ///
  /// In en, this message translates to:
  /// **'Disable reminder?'**
  String get remindersDisableTitle;

  /// Confirmation dialog message when disabling a reminder
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will stop sending notifications until you turn it back on.'**
  String remindersDisableMessage(String name);

  /// Confirm button label when disabling a reminder
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get remindersDisableConfirm;

  /// Snackbar text after deleting a reminder
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String remindersDeletedSnackbar(String name);

  /// Undo action label in reminder deletion snackbar
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get remindersUndoAction;

  /// Reminder subtitle when trigger is on front change with no delay
  ///
  /// In en, this message translates to:
  /// **'On front change'**
  String get remindersSubtitleOnFrontChange;

  /// Reminder subtitle when trigger is on front change with a delay
  ///
  /// In en, this message translates to:
  /// **'On front change ({hours}h delay)'**
  String remindersSubtitleOnFrontChangeDelay(int hours);

  /// Reminder subtitle and frequency segment label for daily repeat interval
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get remindersSubtitleDaily;

  /// Reminder subtitle for every N days repeat interval
  ///
  /// In en, this message translates to:
  /// **'Every {days} days'**
  String remindersSubtitleEveryNDays(int days);

  /// Frequency segment label and subtitle fallback for weekly reminders
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get remindersFrequencyWeekly;

  /// Frequency segment label for reminders that repeat every N days
  ///
  /// In en, this message translates to:
  /// **'Every few days'**
  String get remindersFrequencyInterval;

  /// Section header above the reminder frequency segmented control
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get remindersScheduleLabel;

  /// Helper text shown when the weekly frequency is chosen but no weekdays are selected
  ///
  /// In en, this message translates to:
  /// **'Select at least one day'**
  String get remindersWeeklyEmptyHelper;

  /// Reminder subtitle shown when all 7 weekdays are selected
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get remindersSubtitleEveryDay;

  /// Reminder subtitle shorthand for Monday through Friday selection
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get remindersSubtitleWeekdays;

  /// Reminder subtitle shorthand for Saturday and Sunday selection
  ///
  /// In en, this message translates to:
  /// **'Weekends'**
  String get remindersSubtitleWeekends;

  /// Reminder subtitle when more than three weekdays are selected but not a named shorthand
  ///
  /// In en, this message translates to:
  /// **'{count} days/week'**
  String remindersSubtitleDaysPerWeek(int count);

  /// Short abbreviation for Sunday (3 letters)
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdayAbbreviationSun;

  /// Short abbreviation for Monday (3 letters)
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayAbbreviationMon;

  /// Short abbreviation for Tuesday (3 letters)
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayAbbreviationTue;

  /// Short abbreviation for Wednesday (3 letters)
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayAbbreviationWed;

  /// Short abbreviation for Thursday (3 letters)
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayAbbreviationThu;

  /// Short abbreviation for Friday (3 letters)
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayAbbreviationFri;

  /// Short abbreviation for Saturday (3 letters)
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdayAbbreviationSat;

  /// Trigger type label and fallback subtitle for scheduled reminders
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get remindersScheduled;

  /// Sheet title when editing an existing reminder
  ///
  /// In en, this message translates to:
  /// **'Edit Reminder'**
  String get remindersEditTitle;

  /// Sheet title when creating a new reminder
  ///
  /// In en, this message translates to:
  /// **'New Reminder'**
  String get remindersNewTitle;

  /// Label for the reminder name text field
  ///
  /// In en, this message translates to:
  /// **'Reminder name'**
  String get remindersNameLabel;

  /// Label for the notification message text field
  ///
  /// In en, this message translates to:
  /// **'Notification message'**
  String get remindersMessageLabel;

  /// Section label for reminder trigger type selector
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get remindersTriggerLabel;

  /// Reminder trigger type: triggers on fronting change
  ///
  /// In en, this message translates to:
  /// **'Front Change'**
  String get remindersTriggerFrontChange;

  /// Label for the repeat interval picker row
  ///
  /// In en, this message translates to:
  /// **'Repeat every'**
  String get remindersRepeatEveryLabel;

  /// Interval picker option for number of days
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String remindersIntervalDays(int count);

  /// Label for the time picker row in scheduled reminder
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get remindersTimeLabel;

  /// Label for the delay picker row in front-change reminder
  ///
  /// In en, this message translates to:
  /// **'Delay after front change'**
  String get remindersDelayLabel;

  /// Delay option: no delay, trigger immediately on front change
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get remindersImmediately;

  /// Delay picker option for number of hours
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String remindersDelayHours(int count);

  /// Section label for the optional member target picker on a front-change reminder
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get remindersTargetLabel;

  /// Target picker option meaning the reminder fires on any front change (no specific member)
  ///
  /// In en, this message translates to:
  /// **'Any front change'**
  String get remindersTargetAny;

  /// Honesty disclosure shown when a member-targeted front-change reminder is configured. Prism is end-to-end encrypted, so the relay cannot push notifications for a specific member switch.
  ///
  /// In en, this message translates to:
  /// **'Only fires when Prism is running on this device and notices the switch. If Prism is closed and the switch is logged elsewhere, this reminder will not trigger right away.'**
  String get remindersTargetDisclosure;

  /// Reminder list subtitle prefix shown when a front-change reminder targets a specific member
  ///
  /// In en, this message translates to:
  /// **'When {name} fronts'**
  String remindersSubtitleTargetPrefix(String name);

  /// App name headline in the About section
  ///
  /// In en, this message translates to:
  /// **'Prism'**
  String get settingsAboutAppName;

  /// Tagline shown below the app name in About
  ///
  /// In en, this message translates to:
  /// **'Plural management'**
  String get settingsAboutTagline;

  /// App version string in About section
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsAboutVersion(String version);

  /// Description paragraph in the About section
  ///
  /// In en, this message translates to:
  /// **'A privacy-focused app for managing plural {systemTermPluralLower}. Track fronting, communicate between {termPluralLower}, and keep your {systemTermLower} organized.'**
  String settingsAboutDescription(
    String termPluralLower,
    String systemTermLower,
    String systemTermPluralLower,
  );

  /// Website chip label in About section
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get settingsAboutWebsite;

  /// GitHub chip label in About section
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get settingsAboutGitHub;

  /// Discord chip label in About section
  ///
  /// In en, this message translates to:
  /// **'Discord'**
  String get settingsAboutDiscord;

  /// Bluesky chip label in About section
  ///
  /// In en, this message translates to:
  /// **'Bluesky'**
  String get settingsAboutBluesky;

  /// Tumblr chip label in About section
  ///
  /// In en, this message translates to:
  /// **'Tumblr'**
  String get settingsAboutTumblr;

  /// Privacy chip label in About section
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsAboutPrivacy;

  /// Feedback chip label in About section
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get settingsAboutFeedback;

  /// Toast shown when an About section external link cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Could not open that link'**
  String get settingsAboutLinkOpenFailed;

  /// Toast shown when GitHub chip is tapped
  ///
  /// In en, this message translates to:
  /// **'GitHub link coming soon'**
  String get settingsAboutGitHubComingSoon;

  /// Security chip label in About screen
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsAboutSecurity;

  /// Toast shown when Feedback chip is tapped
  ///
  /// In en, this message translates to:
  /// **'Feedback form coming soon'**
  String get settingsAboutFeedbackComingSoon;

  /// Title for the custom fields settings screen
  ///
  /// In en, this message translates to:
  /// **'Custom Fields'**
  String get settingsCustomFieldsTitle;

  /// Tooltip for the add field action button
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get settingsCustomFieldsAddTooltip;

  /// Error state text in custom fields screen
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String settingsCustomFieldsError(String error);

  /// Empty state title when no custom fields exist
  ///
  /// In en, this message translates to:
  /// **'No custom fields'**
  String get settingsCustomFieldsEmptyTitle;

  /// Empty state subtitle for custom fields screen
  ///
  /// In en, this message translates to:
  /// **'Add fields to track custom attributes for each {termSingularLower}'**
  String settingsCustomFieldsEmptySubtitle(String termSingularLower);

  /// Empty state action button label for adding a custom field
  ///
  /// In en, this message translates to:
  /// **'Add Field'**
  String get settingsCustomFieldsAddAction;

  /// Title of the delete field confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Field'**
  String get settingsCustomFieldsDeleteTitle;

  /// Body of the delete field confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This will delete the field and all its values.'**
  String settingsCustomFieldsDeleteConfirm(String name);

  /// Toast shown after a custom field is deleted
  ///
  /// In en, this message translates to:
  /// **'{name} deleted'**
  String settingsCustomFieldsDeletedToast(String name);

  /// Not found message for a deleted or missing custom field
  ///
  /// In en, this message translates to:
  /// **'Field not found'**
  String get settingsCustomFieldNotFound;

  /// Heading for the members with values section on custom field detail
  ///
  /// In en, this message translates to:
  /// **'Filled In'**
  String get settingsCustomFieldFilledInHeading;

  /// Subtitle showing how many members have a value for a custom field
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Filled in for 1 {termSingularLower}} other{Filled in for {count} {termPluralLower}}}'**
  String settingsCustomFieldFilledInCount(
    int count,
    String termSingularLower,
    String termPluralLower,
  );

  /// Empty state title when no members have a custom field value
  ///
  /// In en, this message translates to:
  /// **'Nothing filled in yet'**
  String get settingsCustomFieldNoValuesTitle;

  /// Empty state subtitle when no members have a custom field value
  ///
  /// In en, this message translates to:
  /// **'When {termPluralLower} fill in this field, they’ll appear here.'**
  String settingsCustomFieldNoValuesSubtitle(String termPluralLower);

  /// Friendly warning shown on short text custom fields when several saved values are long
  ///
  /// In en, this message translates to:
  /// **'This field is collecting longer answers. {fieldType} may be easier to read and edit.'**
  String settingsCustomFieldLongShortTextHint(String fieldType);

  /// Screen reader label for a member custom field value row
  ///
  /// In en, this message translates to:
  /// **'{fieldName} for {memberName}: {value}'**
  String settingsCustomFieldValueSemantics(
    String fieldName,
    String memberName,
    String value,
  );

  /// Tooltip for the Prism Iris accent color option
  ///
  /// In en, this message translates to:
  /// **'Prism Iris'**
  String get settingsAccentColorPrismIris;

  /// Tooltip for the Heather accent color option
  ///
  /// In en, this message translates to:
  /// **'Heather'**
  String get settingsAccentColorHeather;

  /// Tooltip for the Periwinkle accent color option
  ///
  /// In en, this message translates to:
  /// **'Periwinkle'**
  String get settingsAccentColorPeriwinkle;

  /// Tooltip for the Dusty Rose accent color option
  ///
  /// In en, this message translates to:
  /// **'Dusty Rose'**
  String get settingsAccentColorDustyRose;

  /// Tooltip for the Soft Coral accent color option
  ///
  /// In en, this message translates to:
  /// **'Soft Coral'**
  String get settingsAccentColorSoftCoral;

  /// Tooltip for the Sage accent color option
  ///
  /// In en, this message translates to:
  /// **'Sage'**
  String get settingsAccentColorSage;

  /// Tooltip for the Seafoam accent color option
  ///
  /// In en, this message translates to:
  /// **'Seafoam'**
  String get settingsAccentColorSeafoam;

  /// Tooltip for the Azure accent color option
  ///
  /// In en, this message translates to:
  /// **'Azure'**
  String get settingsAccentColorAzure;

  /// Tooltip for the Violet accent color option
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get settingsAccentColorViolet;

  /// Tooltip for the Orchid accent color option
  ///
  /// In en, this message translates to:
  /// **'Orchid'**
  String get settingsAccentColorOrchid;

  /// Tooltip for the Raspberry accent color option
  ///
  /// In en, this message translates to:
  /// **'Raspberry'**
  String get settingsAccentColorRaspberry;

  /// Tooltip for the Emerald accent color option
  ///
  /// In en, this message translates to:
  /// **'Emerald'**
  String get settingsAccentColorEmerald;

  /// Tooltip for the Cyan accent color option
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get settingsAccentColorCyan;

  /// Tooltip for the Ember accent color option
  ///
  /// In en, this message translates to:
  /// **'Ember'**
  String get settingsAccentColorEmber;

  /// Tooltip for the Prism Purple accent color option
  ///
  /// In en, this message translates to:
  /// **'Prism Purple'**
  String get settingsAccentColorPrismPurple;

  /// Tooltip for the Blue accent color option
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get settingsAccentColorBlue;

  /// Tooltip for the Green accent color option
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get settingsAccentColorGreen;

  /// Tooltip for the Red accent color option
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get settingsAccentColorRed;

  /// Tooltip for the Orange accent color option
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get settingsAccentColorOrange;

  /// Tooltip for the Pink accent color option
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get settingsAccentColorPink;

  /// Tooltip for the Teal accent color option
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get settingsAccentColorTeal;

  /// Tooltip for the Amber accent color option
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get settingsAccentColorAmber;

  /// Tooltip for the Indigo accent color option
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get settingsAccentColorIndigo;

  /// Tooltip for the Gray accent color option
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get settingsAccentColorGray;

  /// Tooltip for the system color circle when Material You is active
  ///
  /// In en, this message translates to:
  /// **'System color'**
  String get settingsAccentColorSystemColor;

  /// Tooltip for the custom color picker circle
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsAccentColorCustom;

  /// Title of the custom color picker dialog
  ///
  /// In en, this message translates to:
  /// **'Pick a color'**
  String get settingsAccentColorPickerTitle;

  /// Confirm button label in the color picker dialog
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get settingsAccentColorSelect;

  /// Note shown below color swatches when Material You is active
  ///
  /// In en, this message translates to:
  /// **'Using your system color palette'**
  String get settingsAccentColorSystemPaletteNote;

  /// Warning when accent color has very low luminance
  ///
  /// In en, this message translates to:
  /// **'Your accent color is very dark — it may be hard to see on dark backgrounds.'**
  String get accentLegibilityTooDark;

  /// Warning when accent color has very high luminance
  ///
  /// In en, this message translates to:
  /// **'Your accent color is very light — it may be hard to see on light backgrounds.'**
  String get accentLegibilityTooLight;

  /// Warning when accent color has very low saturation
  ///
  /// In en, this message translates to:
  /// **'Your accent color is very gray — it may blend into the background.'**
  String get accentLegibilityTooDesaturated;

  /// Title of the change PIN sheet
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get settingsChangePinTitle;

  /// Body text of the verify step in the change PIN flow
  ///
  /// In en, this message translates to:
  /// **'Enter your current PIN to continue.'**
  String get settingsChangePinVerifyBody;

  /// Label for the current PIN text field
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get settingsChangePinCurrentLabel;

  /// Continue button in the verify step of change PIN
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get settingsChangePinContinue;

  /// Validation error when current PIN field is empty
  ///
  /// In en, this message translates to:
  /// **'Enter your current PIN.'**
  String get settingsChangePinCurrentRequired;

  /// Error when the secret key is missing during PIN change
  ///
  /// In en, this message translates to:
  /// **'Secret Key not found on this device. Re-pair to restore it.'**
  String get settingsChangePinNoSecretKey;

  /// Error when the sync engine handle is null during PIN change
  ///
  /// In en, this message translates to:
  /// **'Sync engine not available.'**
  String get settingsChangePinEngineUnavailable;

  /// Error when the current PIN is wrong during verification
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN. Please try again.'**
  String get settingsChangePinIncorrect;

  /// Error when PIN verification fails with a known error message
  ///
  /// In en, this message translates to:
  /// **'Verification failed: {error}'**
  String settingsChangePinVerifyFailed(String error);

  /// Generic error during PIN change flow
  ///
  /// In en, this message translates to:
  /// **'An error occurred: {error}'**
  String settingsChangePinGenericError(String error);

  /// Error shown when the verified session is lost (e.g. hot-reload)
  ///
  /// In en, this message translates to:
  /// **'Session expired — please verify again.'**
  String get settingsChangePinSessionExpired;

  /// Warning body text before changing the PIN
  ///
  /// In en, this message translates to:
  /// **'Your other devices will need to enter the new PIN when they next open Prism.'**
  String get settingsChangePinWarnBody;

  /// Button label for the change PIN action
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get settingsChangePinAction;

  /// Body text of the new PIN step
  ///
  /// In en, this message translates to:
  /// **'Choose a new sync PIN.'**
  String get settingsChangePinNewBody;

  /// Label for the new PIN text field
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get settingsChangePinNewLabel;

  /// Label for the confirm new PIN text field
  ///
  /// In en, this message translates to:
  /// **'Confirm new PIN'**
  String get settingsChangePinConfirmLabel;

  /// Validation error when new PIN field is empty
  ///
  /// In en, this message translates to:
  /// **'Enter a new PIN.'**
  String get settingsChangePinNewRequired;

  /// Validation error when new PIN is not 6 digits
  ///
  /// In en, this message translates to:
  /// **'PIN must be exactly 6 digits.'**
  String get settingsChangePinInvalidLength;

  /// Error when new PIN is the same as the current PIN
  ///
  /// In en, this message translates to:
  /// **'Your sync PIN is already set to that.'**
  String get settingsChangePinSamePin;

  /// Error when new PIN and confirm PIN do not match
  ///
  /// In en, this message translates to:
  /// **'PINs don\'t match.'**
  String get settingsChangePinMismatch;

  /// Error when a generation conflict is detected during PIN change
  ///
  /// In en, this message translates to:
  /// **'Another device recently changed settings — please try again.'**
  String get settingsChangePinGenerationConflict;

  /// Generic failure message when PIN change fails
  ///
  /// In en, this message translates to:
  /// **'Failed to change PIN: {error}'**
  String settingsChangePinFailed(String error);

  /// Title on the success screen after changing PIN
  ///
  /// In en, this message translates to:
  /// **'PIN changed'**
  String get settingsChangePinSuccessTitle;

  /// Body text on the success screen after changing PIN
  ///
  /// In en, this message translates to:
  /// **'Your sync PIN has been updated on this device.'**
  String get settingsChangePinSuccessBody;

  /// Title of the recovery phrase step in the change PIN flow
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery phrase'**
  String get changePinEnterMnemonicTitle;

  /// Explanatory subtitle of the recovery phrase step in the change PIN flow
  ///
  /// In en, this message translates to:
  /// **'Your 12-word phrase is not stored on this device. Type it from your saved backup.'**
  String get changePinEnterMnemonicSubtitle;

  /// Hint text for the recovery phrase entry field
  ///
  /// In en, this message translates to:
  /// **'12 words separated by spaces'**
  String get changePinMnemonicHint;

  /// Validation error when the typed recovery phrase cannot be parsed as a valid BIP39 mnemonic
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a valid recovery phrase.'**
  String get changePinMnemonicInvalid;

  /// Validation error when the recovery phrase field is empty
  ///
  /// In en, this message translates to:
  /// **'Enter your 12-word recovery phrase.'**
  String get changePinMnemonicRequired;

  /// Primary button label for the recovery phrase step of the change PIN flow
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get changePinVerifyButton;

  /// Generic error shown when either the PIN or the recovery phrase failed verification; does not disclose which one was wrong
  ///
  /// In en, this message translates to:
  /// **'PIN or recovery phrase is incorrect.'**
  String get changePinVerificationFailed;

  /// Title of the edit field sheet
  ///
  /// In en, this message translates to:
  /// **'Edit Field'**
  String get settingsCreateEditFieldEditTitle;

  /// Title of the new field sheet
  ///
  /// In en, this message translates to:
  /// **'New Field'**
  String get settingsCreateEditFieldNewTitle;

  /// Label for the field name text input
  ///
  /// In en, this message translates to:
  /// **'Field Name'**
  String get settingsCreateEditFieldNameLabel;

  /// Hint text for the field name input
  ///
  /// In en, this message translates to:
  /// **'e.g. Birthday, Favorite Color'**
  String get settingsCreateEditFieldNameHint;

  /// Heading for the field type picker section
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get settingsCreateEditFieldTypeHeading;

  /// Note shown below type chips when editing a field
  ///
  /// In en, this message translates to:
  /// **'Type cannot be changed after creation.'**
  String get settingsCreateEditFieldTypeImmutable;

  /// Heading for the date precision picker section
  ///
  /// In en, this message translates to:
  /// **'Date Precision'**
  String get settingsCreateEditFieldDatePrecisionHeading;

  /// Toast shown when saving a field fails
  ///
  /// In en, this message translates to:
  /// **'Error saving field: {error}'**
  String settingsCreateEditFieldSaveError(String error);

  /// Label for the short text custom field type
  ///
  /// In en, this message translates to:
  /// **'Short Text'**
  String get customFieldTypeShortText;

  /// Label for the long text custom field type
  ///
  /// In en, this message translates to:
  /// **'Long Text'**
  String get customFieldTypeLongText;

  /// Label for the color custom field type
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get customFieldTypeColor;

  /// Label for the date custom field type
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get customFieldTypeDate;

  /// Label for full date custom field precision
  ///
  /// In en, this message translates to:
  /// **'Full Date'**
  String get customFieldDatePrecisionFull;

  /// Label for month and year custom field precision
  ///
  /// In en, this message translates to:
  /// **'Month & Year'**
  String get customFieldDatePrecisionMonthYear;

  /// Label for month and day custom field precision
  ///
  /// In en, this message translates to:
  /// **'Month & Day'**
  String get customFieldDatePrecisionMonthDay;

  /// Label for month custom field precision
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get customFieldDatePrecisionMonth;

  /// Label for year custom field precision
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get customFieldDatePrecisionYear;

  /// Label for date and time custom field precision
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get customFieldDatePrecisionTimestamp;

  /// Label for the choice (single/multi-select) custom field type
  ///
  /// In en, this message translates to:
  /// **'Choice'**
  String get customFieldTypeChoice;

  /// Section heading for the choice field options list in the create/edit field sheet
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get customFieldChoiceOptionsHeading;

  /// Button label to add a new choice option
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get customFieldChoiceAddOption;

  /// Placeholder text inside a choice option label text field
  ///
  /// In en, this message translates to:
  /// **'Option label'**
  String get customFieldChoiceOptionPlaceholder;

  /// Toggle label for allowing multiple selections in a choice field
  ///
  /// In en, this message translates to:
  /// **'Allow multiple selections'**
  String get customFieldChoiceAllowMultipleLabel;

  /// Toggle label for allowing an 'Other' free-text entry in a choice field
  ///
  /// In en, this message translates to:
  /// **'Allow \'Other\' free text'**
  String get customFieldChoiceAllowOtherLabel;

  /// Section heading for the choice field layout choice (auto/compact/stacked) in field settings
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get customFieldChoiceLayoutHeading;

  /// Layout choice meaning 'use the type-aware default' (currently compact for top-level choice fields and stacked for grouped choice fields)
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get customFieldChoiceLayoutAuto;

  /// Layout choice: label-left, choice chips-right on one row
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get customFieldChoiceLayoutCompact;

  /// Layout choice: label above, choice chips on their own row below
  ///
  /// In en, this message translates to:
  /// **'Stacked'**
  String get customFieldChoiceLayoutStacked;

  /// Warning chip shown when a choice option label duplicates another option
  ///
  /// In en, this message translates to:
  /// **'Duplicate label'**
  String get customFieldChoiceDuplicateLabel;

  /// Tooltip for the remove button on a choice option row
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get customFieldChoiceRemoveOptionTooltip;

  /// Tooltip for the drag handle on a choice option row
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get customFieldChoiceReorderHandleTooltip;

  /// Tooltip for the color swatch button that opens the color picker
  ///
  /// In en, this message translates to:
  /// **'Change color'**
  String get customFieldChoiceColorCycleTooltip;

  /// Title for the dialog that lets a user rename a choice option
  ///
  /// In en, this message translates to:
  /// **'Edit option label'**
  String get customFieldChoiceEditLabelDialogTitle;

  /// Hint text for the text field inside the edit-label dialog
  ///
  /// In en, this message translates to:
  /// **'Option label'**
  String get customFieldChoiceOptionLabelHint;

  /// Title of the confirm-delete dialog for a choice option
  ///
  /// In en, this message translates to:
  /// **'Delete option'**
  String get customFieldChoiceDeleteOptionTitle;

  /// Body of the confirm-delete dialog for a choice option
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" will be soft-deleted. Members who selected it will still see it (faded) but can no longer choose it. This affects all members.'**
  String customFieldChoiceDeleteOptionMessage(String label);

  /// Context-menu item to rename a choice option chip
  ///
  /// In en, this message translates to:
  /// **'Edit label'**
  String get customFieldChoiceEditMenuLabel;

  /// Context-menu item to open the color picker for a choice option chip
  ///
  /// In en, this message translates to:
  /// **'Change color'**
  String get customFieldChoiceChangeColorMenuLabel;

  /// Context-menu item to soft-delete a choice option
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get customFieldChoiceDeleteMenuLabel;

  /// Label for the 'Other' chip that toggles the free-text entry
  ///
  /// In en, this message translates to:
  /// **'Other…'**
  String get customFieldChoiceOtherChipLabel;

  /// Hint text inside the Other free-text field
  ///
  /// In en, this message translates to:
  /// **'Specify…'**
  String get customFieldChoiceOtherTextHint;

  /// Tooltip shown on a soft-deleted option chip to signal it is no longer choosable
  ///
  /// In en, this message translates to:
  /// **'(removed)'**
  String get customFieldChoiceRemovedSuffix;

  /// Chip/text label for an Other free-text answer, e.g. 'Other: my answer'
  ///
  /// In en, this message translates to:
  /// **'Other: {value}'**
  String customFieldChoiceOtherPrefix(String value);

  /// Accessibility suffix appended to a choice chip label when the option is selected
  ///
  /// In en, this message translates to:
  /// **'selected'**
  String get customFieldChoiceSelectedSuffix;

  /// Accessibility suffix appended to a choice chip label when the option is not selected
  ///
  /// In en, this message translates to:
  /// **'not selected'**
  String get customFieldChoiceNotSelectedSuffix;

  /// Semantics label for the Other free-text field (accessibility)
  ///
  /// In en, this message translates to:
  /// **'Other, free text'**
  String get customFieldChoiceOtherSemanticLabel;

  /// Title of the data browser debug screen
  ///
  /// In en, this message translates to:
  /// **'Data Browser'**
  String get settingsDataBrowserTitle;

  /// Tooltip for the reload button in the data browser
  ///
  /// In en, this message translates to:
  /// **'Reload data'**
  String get settingsDataBrowserReloadTooltip;

  /// Tab label for the members table in the data browser
  ///
  /// In en, this message translates to:
  /// **'{termPlural}'**
  String settingsDataBrowserTabMembers(String termPlural);

  /// Tab label for the sessions table in the data browser
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get settingsDataBrowserTabSessions;

  /// Tab label for the conversations table in the data browser
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get settingsDataBrowserTabChats;

  /// Tab label for the messages table in the data browser
  ///
  /// In en, this message translates to:
  /// **'Msgs'**
  String get settingsDataBrowserTabMessages;

  /// Tab label for the polls table in the data browser
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get settingsDataBrowserTabPolls;

  /// Error state text in the data browser
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String settingsDataBrowserError(String error);

  /// Empty state text when members table is empty
  ///
  /// In en, this message translates to:
  /// **'No {termPluralLower}'**
  String settingsDataBrowserNoMembers(String termPluralLower);

  /// Empty state text when sessions table is empty
  ///
  /// In en, this message translates to:
  /// **'No sessions'**
  String get settingsDataBrowserNoSessions;

  /// Empty state text when conversations table is empty
  ///
  /// In en, this message translates to:
  /// **'No conversations'**
  String get settingsDataBrowserNoConversations;

  /// Empty state text when messages table is empty
  ///
  /// In en, this message translates to:
  /// **'No messages'**
  String get settingsDataBrowserNoMessages;

  /// Empty state text when polls table is empty
  ///
  /// In en, this message translates to:
  /// **'No polls'**
  String get settingsDataBrowserNoPolls;

  /// Secondary field label for an active fronting session
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsDataBrowserSessionActive;

  /// Secondary field label for an ended fronting session
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get settingsDataBrowserSessionEnded;

  /// Fallback title for conversations without a title
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get settingsDataBrowserUntitled;

  /// Participant count shown in conversation rows
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 participant} other{{count} participants}}'**
  String settingsDataBrowserParticipantCount(int count);

  /// Secondary field label for system messages
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsDataBrowserSystemMessage;

  /// Secondary field label for closed polls
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get settingsDataBrowserPollClosed;

  /// Secondary field label for active polls
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsDataBrowserPollActive;

  /// Text shown when a conversation has no messages
  ///
  /// In en, this message translates to:
  /// **'No messages in this conversation.'**
  String get settingsDataBrowserNoMessagesInConversation;

  /// Subtitle shown on a conversation row when messages fail to load
  ///
  /// In en, this message translates to:
  /// **'Error loading — tap to retry'**
  String get settingsDataBrowserLoadError;

  /// Message count subtitle on a conversation row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message} other{{count} messages}}'**
  String settingsDataBrowserMessageCount(int count);

  /// Subtitle shown on a conversation row before messages are loaded
  ///
  /// In en, this message translates to:
  /// **'Tap to load messages'**
  String get settingsDataBrowserTapToLoad;

  /// Value shown in the endTime field for an active session
  ///
  /// In en, this message translates to:
  /// **'null (active)'**
  String get settingsDataBrowserSessionEndTimeActive;

  /// Title of the sync event log debug screen
  ///
  /// In en, this message translates to:
  /// **'Prism Sync Event Log'**
  String get settingsSyncDebugTitle;

  /// Subtitle showing the number of sync events recorded
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 event} other{{count} events}}'**
  String settingsSyncDebugEventCount(int count);

  /// Tooltip for the copy log button in the sync debug screen
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get settingsSyncDebugCopyLogTooltip;

  /// Tooltip for the clear log button in the sync debug screen
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get settingsSyncDebugClearLogTooltip;

  /// Toast shown after copying the sync event log
  ///
  /// In en, this message translates to:
  /// **'Sync event log copied'**
  String get settingsSyncDebugCopiedToast;

  /// Empty state title in the sync event log screen
  ///
  /// In en, this message translates to:
  /// **'No sync events recorded'**
  String get settingsSyncDebugEmptyTitle;

  /// Empty state body in the sync event log screen
  ///
  /// In en, this message translates to:
  /// **'Sync events will appear here as they happen.'**
  String get settingsSyncDebugEmptyBody;

  /// Title of the PluralKit sync log debug screen
  ///
  /// In en, this message translates to:
  /// **'PluralKit sync log'**
  String get settingsPkSyncDebugTitle;

  /// Subtitle showing the number of PluralKit sync events recorded
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No events} =1{1 event} other{{count} events}}'**
  String settingsPkSyncDebugEventCount(int count);

  /// Empty state title in the PluralKit sync log screen
  ///
  /// In en, this message translates to:
  /// **'No PluralKit events'**
  String get settingsPkSyncDebugEmptyTitle;

  /// Empty state body in the PluralKit sync log screen
  ///
  /// In en, this message translates to:
  /// **'Sync with PluralKit to start recording events.'**
  String get settingsPkSyncDebugEmptyBody;

  /// Tooltip for the copy log button in the PluralKit sync log screen
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get settingsPkSyncDebugCopyTooltip;

  /// Tooltip for the clear log button in the PluralKit sync log screen
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get settingsPkSyncDebugClearTooltip;

  /// Toast shown after copying the PluralKit sync log
  ///
  /// In en, this message translates to:
  /// **'PluralKit sync log copied'**
  String get settingsPkSyncDebugCopiedToast;

  /// Tile title on the PluralKit settings screen that opens the sync log
  ///
  /// In en, this message translates to:
  /// **'Sync activity log'**
  String get settingsPkSyncDebugOpenTile;

  /// Subtitle on the PluralKit sync log tile when no events have been recorded
  ///
  /// In en, this message translates to:
  /// **'No events recorded yet'**
  String get settingsPkSyncDebugOpenSubtitleEmpty;

  /// Subtitle on the PluralKit sync log tile when events are available
  ///
  /// In en, this message translates to:
  /// **'View recent PluralKit sync activity'**
  String get settingsPkSyncDebugOpenSubtitleActive;

  /// Cross-link from the Prism sync debug screen to the PluralKit sync log
  ///
  /// In en, this message translates to:
  /// **'View PluralKit sync log'**
  String get settingsPkSyncDebugCrossLinkFromSyncDebug;

  /// Label for the terminology dropdown picker
  ///
  /// In en, this message translates to:
  /// **'Terminology'**
  String get settingsTerminologyPickerLabel;

  /// Terminology option: Members (plural)
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get settingsTerminologyOptionMembers;

  /// Terminology option: member (singular)
  ///
  /// In en, this message translates to:
  /// **'member'**
  String get settingsTerminologyOptionMembersSingular;

  /// Terminology option: Headmates (plural)
  ///
  /// In en, this message translates to:
  /// **'Headmates'**
  String get settingsTerminologyOptionHeadmates;

  /// Terminology option: headmate (singular)
  ///
  /// In en, this message translates to:
  /// **'headmate'**
  String get settingsTerminologyOptionHeadmatesSingular;

  /// Terminology option: Alters (plural)
  ///
  /// In en, this message translates to:
  /// **'Alters'**
  String get settingsTerminologyOptionAlters;

  /// Terminology option: alter (singular)
  ///
  /// In en, this message translates to:
  /// **'alter'**
  String get settingsTerminologyOptionAltersSingular;

  /// Terminology option: Parts (plural)
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get settingsTerminologyOptionParts;

  /// Terminology option: part (singular)
  ///
  /// In en, this message translates to:
  /// **'part'**
  String get settingsTerminologyOptionPartsSingular;

  /// Terminology option: Facets (plural)
  ///
  /// In en, this message translates to:
  /// **'Facets'**
  String get settingsTerminologyOptionFacets;

  /// Terminology option: facet (singular)
  ///
  /// In en, this message translates to:
  /// **'facet'**
  String get settingsTerminologyOptionFacetsSingular;

  /// Terminology option: Custom (plural label)
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsTerminologyOptionCustom;

  /// Terminology option: custom term (singular label)
  ///
  /// In en, this message translates to:
  /// **'custom term'**
  String get settingsTerminologyOptionCustomSingular;

  /// Label for the custom singular term text field
  ///
  /// In en, this message translates to:
  /// **'Custom term (singular)'**
  String get settingsTerminologyCustomSingularLabel;

  /// Hint text for the custom singular term text field
  ///
  /// In en, this message translates to:
  /// **'e.g. fragment'**
  String get settingsTerminologyCustomSingularHint;

  /// Label for the custom plural term text field
  ///
  /// In en, this message translates to:
  /// **'Custom term (plural)'**
  String get settingsTerminologyCustomPluralLabel;

  /// Hint text for the custom plural term text field
  ///
  /// In en, this message translates to:
  /// **'e.g. fragments'**
  String get settingsTerminologyCustomPluralHint;

  /// Label above the live terminology preview box
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsTerminologyPreviewLabel;

  /// Section header in terminology picker for English-language options, shown to users with a non-English device language
  ///
  /// In en, this message translates to:
  /// **'In English'**
  String get terminologyEnglishOptionsLabel;

  /// Bottom navigation tab label for the Home (fronting) tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation tab label for the Chat tab
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navChat;

  /// Bottom navigation tab label for the Habits tab
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get navHabits;

  /// Bottom navigation tab label for the Polls tab
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get navPolls;

  /// Bottom navigation tab label for the Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Empty state subtitle in the desktop settings detail pane when no setting is selected
  ///
  /// In en, this message translates to:
  /// **'Choose a setting from the list to view it here.'**
  String get settingsSelectEmptySubtitle;

  /// Bottom navigation tab label for the Members tab (default; overridden by user terminology)
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get navMembers;

  /// Bottom navigation tab label for the Reminders tab
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get navReminders;

  /// Bottom navigation tab label for the Notes tab
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get navNotes;

  /// Bottom navigation tab label for the Statistics tab
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get navStatistics;

  /// Bottom navigation tab label for the Timeline tab
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get navTimeline;

  /// Bottom navigation tab label for the Sleep tab
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get navSleep;

  /// Bottom navigation tab label for the Boards (message boards) tab
  ///
  /// In en, this message translates to:
  /// **'Boards'**
  String get navBoards;

  /// Bottom navigation tab label for the Groups tab (optional; lists member groups)
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get navGroups;

  /// Bottom navigation tab label for the optional Media library tab
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get navMedia;

  /// Title shown in the top bar of the Sleep screen
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleepScreenTitle;

  /// Tooltip for the + icon button on the Sleep screen top bar
  ///
  /// In en, this message translates to:
  /// **'Log sleep'**
  String get sleepScreenAddTooltip;

  /// Tooltip for the settings gear icon button on the Sleep screen top bar
  ///
  /// In en, this message translates to:
  /// **'Sleep settings'**
  String get sleepScreenSettingsTooltip;

  /// Empty state heading on the Sleep screen when no sessions exist
  ///
  /// In en, this message translates to:
  /// **'No sleep sessions yet'**
  String get sleepEmptyTitle;

  /// Empty state body on the Sleep screen (em dash, no period per spec)
  ///
  /// In en, this message translates to:
  /// **'Tap + to log your first'**
  String get sleepEmptyBody;

  /// Label for the Last Night stat card on the Sleep screen
  ///
  /// In en, this message translates to:
  /// **'Last night'**
  String get sleepLastNightLabel;

  /// Label for the 7-day average stat card on the Sleep screen
  ///
  /// In en, this message translates to:
  /// **'7-day avg'**
  String get sleepSevenDayAvgLabel;

  /// Section header for the recent sleep sessions list on the Sleep screen
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sleepRecentSectionHeader;

  /// Placeholder shown in a stat card when no data is available (em dash)
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get sleepStatUnavailable;

  /// Row label in Settings → Features → Sleep that navigates to the Sleep screen
  ///
  /// In en, this message translates to:
  /// **'View sleep history'**
  String get sleepViewAllHistory;

  /// Trend line on the 7-day average sleep stat card showing change vs prior 7 days
  ///
  /// In en, this message translates to:
  /// **'vs prior week: {delta}'**
  String sleepTrendVsPriorWeek(String delta);

  /// Inline warning chip on a sleep session row when the start date is in the future (clock skew)
  ///
  /// In en, this message translates to:
  /// **'Date looks off'**
  String get sleepDateLooksOff;

  /// Soft warning shown in StartSleepSheet when a historical sleep entry overlaps an existing session
  ///
  /// In en, this message translates to:
  /// **'This overlaps an existing sleep session'**
  String get sleepOverlapsExistingWarning;

  /// Disclosure link in StartSleepSheet to switch into historical-logging mode with an end-time field
  ///
  /// In en, this message translates to:
  /// **'Log past sleep'**
  String get logPastSleep;

  /// Semantics hint announced on rows that open a long-press context menu
  ///
  /// In en, this message translates to:
  /// **'Long-press for more options'**
  String get longPressForOptionsHint;

  /// Link in StartSleepSheet to cancel historical-logging mode and return to start-now defaults
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelHistoricalSleep;

  /// Header title for the onboarding welcome step
  ///
  /// In en, this message translates to:
  /// **'Together in Prism.'**
  String get onboardingWelcomeTitle;

  /// Header subtitle for the onboarding welcome step
  ///
  /// In en, this message translates to:
  /// **'Fronting, chat, notes, habits, and decisions in one private place.'**
  String get onboardingWelcomeSubtitle;

  /// Link on welcome step to enter sync-from-device flow before PIN setup
  ///
  /// In en, this message translates to:
  /// **'Pair with another device via Prism Sync'**
  String get onboardingWelcomeSyncLink;

  /// Header title for the onboarding biometric setup step
  ///
  /// In en, this message translates to:
  /// **'Enable biometrics'**
  String get onboardingBiometricSetupTitle;

  /// Header subtitle for the onboarding biometric setup step
  ///
  /// In en, this message translates to:
  /// **'Use Face ID or Touch ID to unlock.'**
  String get onboardingBiometricSetupSubtitle;

  /// Header title for the onboarding sync device step
  ///
  /// In en, this message translates to:
  /// **'Sync From Device'**
  String get onboardingSyncDeviceTitle;

  /// Header subtitle for the onboarding sync device step
  ///
  /// In en, this message translates to:
  /// **'Pair with an existing device'**
  String get onboardingSyncDeviceSubtitle;

  /// Header title for the onboarding imported-data-ready step
  ///
  /// In en, this message translates to:
  /// **'Data Ready'**
  String get onboardingImportedDataReadyTitle;

  /// Header subtitle for the onboarding imported-data-ready step
  ///
  /// In en, this message translates to:
  /// **'Your imported data is ready to use'**
  String get onboardingImportedDataReadySubtitle;

  /// Header title for the onboarding import-data step
  ///
  /// In en, this message translates to:
  /// **'Already have data?'**
  String get onboardingImportDataTitle;

  /// Header subtitle for the onboarding import-data step
  ///
  /// In en, this message translates to:
  /// **'Bring your data with you.'**
  String get onboardingImportDataSubtitle;

  /// Header title for the onboarding system-name step
  ///
  /// In en, this message translates to:
  /// **'Name this profile'**
  String get onboardingSystemNameTitle;

  /// Header subtitle for the onboarding system-name step
  ///
  /// In en, this message translates to:
  /// **'Whatever feels right.'**
  String get onboardingSystemNameSubtitle;

  /// Header title for the onboarding terminology step
  ///
  /// In en, this message translates to:
  /// **'Choose your words'**
  String get onboardingTerminologyTitle;

  /// Header subtitle for the onboarding terminology step
  ///
  /// In en, this message translates to:
  /// **'This changes labels throughout Prism.'**
  String get onboardingTerminologySubtitle;

  /// Header title for the onboarding add-members step
  ///
  /// In en, this message translates to:
  /// **'Who\'s here?'**
  String get onboardingAddMembersTitle;

  /// Header subtitle for the onboarding add-members step
  ///
  /// In en, this message translates to:
  /// **'Add your people.'**
  String get onboardingAddMembersSubtitle;

  /// Header title for the onboarding features step
  ///
  /// In en, this message translates to:
  /// **'Pick your tools'**
  String get onboardingFeaturesTitle;

  /// Header subtitle for the onboarding features step
  ///
  /// In en, this message translates to:
  /// **'Turn on what you need. Change anytime.'**
  String get onboardingFeaturesSubtitle;

  /// Header title for the onboarding navigation step
  ///
  /// In en, this message translates to:
  /// **'Arrange navigation'**
  String get onboardingNavigationTitle;

  /// Inline hint explaining the onboarding navigation More menu
  ///
  /// In en, this message translates to:
  /// **'Move less-used items into More,\nthe three-dot button opens that menu.'**
  String get onboardingNavigationMoreHint;

  /// Header title for the onboarding fronting defaults step
  ///
  /// In en, this message translates to:
  /// **'Fronting defaults'**
  String get onboardingFrontingDefaultsTitle;

  /// Header subtitle for the onboarding fronting defaults step
  ///
  /// In en, this message translates to:
  /// **'Choose how Home shows and starts fronts.'**
  String get onboardingFrontingDefaultsSubtitle;

  /// Header title for the onboarding chat-setup step
  ///
  /// In en, this message translates to:
  /// **'Set up chat'**
  String get onboardingChatSetupTitle;

  /// Header subtitle for the onboarding chat-setup step
  ///
  /// In en, this message translates to:
  /// **'Channels to talk.'**
  String get onboardingChatSetupSubtitle;

  /// Header title for the onboarding appearance step
  ///
  /// In en, this message translates to:
  /// **'Make it yours'**
  String get onboardingAppearanceTitle;

  /// Header subtitle for the onboarding appearance step
  ///
  /// In en, this message translates to:
  /// **'Colors, theme, the small things.'**
  String get onboardingAppearanceSubtitle;

  /// Header title for the onboarding permissions step
  ///
  /// In en, this message translates to:
  /// **'One more thing'**
  String get onboardingPermissionsTitle;

  /// Header subtitle for the onboarding permissions step
  ///
  /// In en, this message translates to:
  /// **'Optional permissions for the best experience.'**
  String get onboardingPermissionsSubtitle;

  /// Title for notification permission request in onboarding
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get onboardingPermissionsNotificationTitle;

  /// Rationale for requesting notification permission
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know when {termPluralLower} log a switch or a habit reminder is due'**
  String onboardingPermissionsNotificationRationale(String termPluralLower);

  /// Title for microphone permission request in onboarding
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get onboardingPermissionsMicrophoneTitle;

  /// Rationale for requesting microphone permission
  ///
  /// In en, this message translates to:
  /// **'So you can record voice messages for your {termPluralLower}'**
  String onboardingPermissionsMicrophoneRationale(String termPluralLower);

  /// Label shown when a permission has been granted
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get onboardingPermissionsAllowed;

  /// Button label to request a permission
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get onboardingPermissionsAllow;

  /// Link to open device settings when permission is permanently denied
  ///
  /// In en, this message translates to:
  /// **'Change in Settings'**
  String get onboardingPermissionsOpenSettings;

  /// Header title for the onboarding who's-fronting step
  ///
  /// In en, this message translates to:
  /// **'Who\'s fronting?'**
  String get onboardingWhosFrontingTitle;

  /// Header subtitle for the onboarding who's-fronting step
  ///
  /// In en, this message translates to:
  /// **'Tap whoever\'s here right now.'**
  String get onboardingWhosFrontingSubtitle;

  /// Header title for the onboarding complete step
  ///
  /// In en, this message translates to:
  /// **'Ready when you are'**
  String get onboardingCompleteTitle;

  /// Header subtitle for the onboarding complete step
  ///
  /// In en, this message translates to:
  /// **'Prism is set up. Here\'s what to explore.'**
  String get onboardingCompleteSubtitle;

  /// Button label to add a new member/alter/headmate — {term} is user's chosen singular
  ///
  /// In en, this message translates to:
  /// **'Add {term}'**
  String terminologyAddButton(String term);

  /// Search field hint text — {term} is user's chosen plural lowercase
  ///
  /// In en, this message translates to:
  /// **'Search {term}...'**
  String terminologySearchHint(String term);

  /// Empty state title for all members shown — {term} is user's chosen plural lowercase
  ///
  /// In en, this message translates to:
  /// **'No {term} yet'**
  String terminologyEmptyTitle(String term);

  /// Empty state title when only active members shown — {term} is user's chosen plural lowercase
  ///
  /// In en, this message translates to:
  /// **'No active {term} yet'**
  String terminologyEmptyActiveTitle(String term);

  /// Sheet title when creating a new member — {term} is user's chosen singular
  ///
  /// In en, this message translates to:
  /// **'New {term}'**
  String terminologyNewItem(String term);

  /// Sheet title when editing a member — {term} is user's chosen singular
  ///
  /// In en, this message translates to:
  /// **'Edit {term}'**
  String terminologyEditItem(String term);

  /// Dialog title when deleting a member — {term} is user's chosen singular
  ///
  /// In en, this message translates to:
  /// **'Delete {term}'**
  String terminologyDeleteItem(String term);

  /// System management screen title — {term} is user's chosen plural
  ///
  /// In en, this message translates to:
  /// **'Manage {term}'**
  String terminologyManage(String term);

  /// Bulk delete action label — {term} is user's chosen plural
  ///
  /// In en, this message translates to:
  /// **'Delete Selected {term}'**
  String terminologyDeleteSelected(String term);

  /// Prompt to select a member — {term} is user's chosen singular lowercase
  ///
  /// In en, this message translates to:
  /// **'Select a {term}'**
  String terminologySelectPrompt(String term);

  /// Search empty state — {term} is user's chosen plural lowercase
  ///
  /// In en, this message translates to:
  /// **'No {term} found'**
  String terminologyNoFound(String term);

  /// Error when member list fails to load — {term} is plural lowercase, {error} is error message
  ///
  /// In en, this message translates to:
  /// **'Error loading {term}: {error}'**
  String terminologyLoadError(String term, String error);

  /// Members empty state subtitle — {term} is user's chosen singular lowercase
  ///
  /// In en, this message translates to:
  /// **'Add your first {systemTermLower} {term} to get started'**
  String terminologyAddFirstSubtitle(String term, String systemTermLower);

  /// Toast when trying to vote without selecting a member to vote as — {term} is user's chosen singular lowercase
  ///
  /// In en, this message translates to:
  /// **'Select a {term} to vote as'**
  String pollsVotingAsSelectPrompt(String term);

  /// Title for onboarding PIN setup step
  ///
  /// In en, this message translates to:
  /// **'Set your PIN'**
  String get onboardingPinSetupTitle;

  /// Subtitle for onboarding PIN setup step
  ///
  /// In en, this message translates to:
  /// **'You\'ll use this 6-digit PIN to lock Prism and recover access if needed.'**
  String get onboardingPinSetupSubtitle;

  /// Title for onboarding recovery phrase backup step
  ///
  /// In en, this message translates to:
  /// **'Save your recovery phrase'**
  String get onboardingRecoveryPhraseTitle;

  /// Subtitle for onboarding recovery phrase backup step
  ///
  /// In en, this message translates to:
  /// **'Write these 12 words somewhere safe. You\'ll need them to set up sync, add new devices, or change your PIN.'**
  String get onboardingRecoveryPhraseSubtitle;

  /// Title for onboarding recovery phrase confirmation step
  ///
  /// In en, this message translates to:
  /// **'Verify your phrase'**
  String get onboardingConfirmPhraseTitle;

  /// Subtitle for onboarding recovery phrase confirmation step
  ///
  /// In en, this message translates to:
  /// **'Select the correct word for each position.'**
  String get onboardingConfirmPhraseSubtitle;

  /// Title for the PIN entry sheet used to authenticate sync
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get syncPinSheetTitle;

  /// Subtitle for the PIN entry sheet used to authenticate sync
  ///
  /// In en, this message translates to:
  /// **'Your PIN is required to unlock Prism.'**
  String get syncPinSheetSubtitle;

  /// Subtitle shown on step 1 of the sync PIN sheet when prompting for the recovery phrase.
  ///
  /// In en, this message translates to:
  /// **'Enter your 12-word recovery phrase to continue. This isn\'t stored on your device.'**
  String get syncPinSheetMnemonicSubtitle;

  /// Inline error shown under the mnemonic field when validation fails.
  ///
  /// In en, this message translates to:
  /// **'This doesn\'t look like a valid recovery phrase.'**
  String get syncPinSheetMnemonicInvalid;

  /// Generic unlock failure message that doesn't disclose which input was wrong.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t unlock with this phrase and PIN.'**
  String get syncPinSheetUnlockFailed;

  /// Inline toggle that expands a short explainer for users who have lost their recovery phrase.
  ///
  /// In en, this message translates to:
  /// **'Lost your phrase?'**
  String get syncPinSheetLostPhrase;

  /// Explainer body shown when the 'Lost your phrase?' row is expanded.
  ///
  /// In en, this message translates to:
  /// **'Your recovery phrase is the only way to unlock sync on this device. If you\'ve lost it, reset the app and restore from an exported backup.'**
  String get syncPinSheetLostPhraseBody;

  /// Primary action button on step 1 of the sync PIN sheet.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get syncPinSheetMnemonicContinue;

  /// Back affordance on step 2 that returns to the mnemonic step without dismissing the sheet.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get syncPinSheetBack;

  /// Title for the wrapped_dek recovery sheet.
  ///
  /// In en, this message translates to:
  /// **'Restore your pairing key'**
  String get syncRewrapSheetTitle;

  /// Subtitle for step 1 of the recovery sheet (mnemonic). Reassures the user data is safe.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find part of your pairing key. Re-enter your recovery phrase and PIN to fix this — your data is safe.'**
  String get syncRewrapSheetMnemonicSubtitle;

  /// Subtitle for step 2 of the recovery sheet (PIN entry).
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to finish restoring your pairing key.'**
  String get syncRewrapSheetPinSubtitle;

  /// Generic failure message for the recovery sheet that doesn't disclose which input was wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN or recovery phrase.'**
  String get syncRewrapSheetFailed;

  /// Counter showing how many of the 12 BIP39 words have been entered and recognized.
  ///
  /// In en, this message translates to:
  /// **'{filled} of 12 words'**
  String mnemonicFieldWordCounter(String filled);

  /// Tooltip for the clipboard-paste button on the mnemonic field.
  ///
  /// In en, this message translates to:
  /// **'Paste phrase'**
  String get mnemonicFieldPaste;

  /// Tooltip for the visibility toggle in the hidden state.
  ///
  /// In en, this message translates to:
  /// **'Show words'**
  String get mnemonicFieldShowWords;

  /// Tooltip for the visibility toggle in the visible state.
  ///
  /// In en, this message translates to:
  /// **'Hide words'**
  String get mnemonicFieldHideWords;

  /// Accessibility label for an empty mnemonic slot.
  ///
  /// In en, this message translates to:
  /// **'Word {n}'**
  String mnemonicFieldWordSlotLabel(String n);

  /// Accessibility label for a filled mnemonic chip that matches the BIP39 wordlist.
  ///
  /// In en, this message translates to:
  /// **'Word {n}: {word}, valid'**
  String mnemonicFieldWordChipValid(String n, String word);

  /// Accessibility label for a filled mnemonic chip whose value isn't in the BIP39 wordlist.
  ///
  /// In en, this message translates to:
  /// **'Word {n}: {word}, not recognized'**
  String mnemonicFieldWordChipInvalid(String n, String word);

  /// Tooltip for scanning a recovery phrase QR code
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get mnemonicFieldScanQrTooltip;

  /// Tooltip for showing the recovery phrase as a QR code
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get mnemonicFieldShowQrTooltip;

  /// Dialog title for showing a recovery phrase QR code
  ///
  /// In en, this message translates to:
  /// **'Recovery Phrase QR'**
  String get mnemonicFieldQrTitle;

  /// Dialog body for showing a recovery phrase QR code
  ///
  /// In en, this message translates to:
  /// **'Scan this QR code to fill the 12-word recovery phrase on another device.'**
  String get mnemonicFieldQrDescription;

  /// Dialog title for scanning a recovery phrase QR code
  ///
  /// In en, this message translates to:
  /// **'Scan Recovery QR'**
  String get mnemonicFieldScanQrTitle;

  /// Dialog body for scanning a recovery phrase QR code
  ///
  /// In en, this message translates to:
  /// **'Scan a QR code that contains your 12-word recovery phrase.'**
  String get mnemonicFieldScanQrDescription;

  /// Error shown when a scanned QR code does not contain a valid recovery phrase
  ///
  /// In en, this message translates to:
  /// **'Invalid QR code. Scan a 12-word recovery phrase.'**
  String get mnemonicFieldInvalidQr;

  /// Title shown when the user needs to grant camera access before the QR scanner can open
  ///
  /// In en, this message translates to:
  /// **'Camera permission needed'**
  String get mnemonicFieldCameraPermissionTitle;

  /// Body shown when the user denied camera access one time
  ///
  /// In en, this message translates to:
  /// **'Prism needs the camera to scan your recovery QR code. Try again and allow camera access when prompted.'**
  String get mnemonicFieldCameraPermissionDeniedBody;

  /// Body shown when camera access is permanently denied or restricted
  ///
  /// In en, this message translates to:
  /// **'Camera access is blocked. Open Settings to grant Prism camera permission, then try again.'**
  String get mnemonicFieldCameraPermissionPermanentlyDeniedBody;

  /// Button that deep-links to the OS app settings page so the user can grant camera permission
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get mnemonicFieldCameraPermissionOpenSettings;

  /// PluralKit setup section heading for automatic polling
  ///
  /// In en, this message translates to:
  /// **'Auto-sync'**
  String get pluralkitAutoSyncSection;

  /// Title for the PluralKit auto-poll toggle
  ///
  /// In en, this message translates to:
  /// **'Pull new switches automatically'**
  String get pluralkitAutoSyncTitle;

  /// Body for the PluralKit auto-poll toggle
  ///
  /// In en, this message translates to:
  /// **'While Prism is open, check PluralKit for new switches on an interval. Pauses in the background.'**
  String get pluralkitAutoSyncDescription;

  /// Label for the PluralKit auto-poll interval chips
  ///
  /// In en, this message translates to:
  /// **'Check every'**
  String get pluralkitAutoSyncIntervalLabel;

  /// Shown when PluralKit auto-poll settings fail to load
  ///
  /// In en, this message translates to:
  /// **'Could not load auto-sync settings.'**
  String get pluralkitAutoSyncLoadFailed;

  /// Button label to import a PluralKit pk;export JSON file
  ///
  /// In en, this message translates to:
  /// **'Recover history from pk;export'**
  String get pluralkitImportFromFile;

  /// Title for the post-connect mapping required banner
  ///
  /// In en, this message translates to:
  /// **'One more step: link your {termPluralLower}'**
  String pluralkitMappingBannerTitle(String termPluralLower);

  /// Body for the post-connect mapping required banner
  ///
  /// In en, this message translates to:
  /// **'You\'re connected. Before sync turns on, match each PluralKit member to a {termSingularLower} in Prism — or import them as new. This prevents duplicates and keeps switch history attached to the right person.'**
  String pluralkitMappingBannerBody(String termSingularLower);

  /// Button label inside the mapping banner that opens the mapping flow
  ///
  /// In en, this message translates to:
  /// **'Link {termPluralLower}'**
  String pluralkitMappingBannerButton(String termPluralLower);

  /// Heading for the sync direction step in the PluralKit setup wizard
  ///
  /// In en, this message translates to:
  /// **'How should this sync?'**
  String get pluralkitDirectionStepHeading;

  /// Hint text below the heading for the sync direction step
  ///
  /// In en, this message translates to:
  /// **'Pick a sync direction to finish setting up.'**
  String get pluralkitDirectionStepHint;

  /// Caption for the full-sync mode option in the direction step
  ///
  /// In en, this message translates to:
  /// **'Sync members, history, and current fronters.'**
  String get pluralkitModeFullSyncCaption;

  /// Caption for the live-fronters-only mode option in the direction step
  ///
  /// In en, this message translates to:
  /// **'Sync only who\'s currently fronting.'**
  String get pluralkitModeLiveOnlyCaption;

  /// Caption explaining the sync direction choices
  ///
  /// In en, this message translates to:
  /// **'Pull from PluralKit, push to PluralKit, or both.'**
  String get pluralkitDirectionCaption;

  /// Continue button label in the sync direction step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get pluralkitDirectionContinue;

  /// Validation message when user taps Continue without choosing a direction
  ///
  /// In en, this message translates to:
  /// **'Choose a sync direction to continue.'**
  String get pluralkitDirectionMustChoose;

  /// Title of the 'Who's fronting?' resolution sheet
  ///
  /// In en, this message translates to:
  /// **'Who\'s fronting?'**
  String get pluralkitWhosFrontingTitle;

  /// Subtitle explaining the fronter disagreement in the resolution sheet
  ///
  /// In en, this message translates to:
  /// **'Prism and PluralKit have different answers for who\'s currently fronting. Pick the one that\'s correct and we\'ll sync from there.'**
  String get pluralkitWhosFrontingSubtitle;

  /// Button label to defer the fronter resolution decision
  ///
  /// In en, this message translates to:
  /// **'Decide later'**
  String get pluralkitWhosFrontingDecideLater;

  /// Option label to use Prism's current fronters
  ///
  /// In en, this message translates to:
  /// **'Use Prism\'s'**
  String get pluralkitWhosFrontingUsePrism;

  /// Option label to use PluralKit's current fronters
  ///
  /// In en, this message translates to:
  /// **'Use PluralKit\'s'**
  String get pluralkitWhosFrontingUsePk;

  /// Option label to co-front with both Prism and PluralKit fronters
  ///
  /// In en, this message translates to:
  /// **'Use both'**
  String get pluralkitWhosFrontingCofront;

  /// Card action label to set the listed members as fronting
  ///
  /// In en, this message translates to:
  /// **'Set {names} fronting'**
  String pluralkitWhosFrontingSetMembers(String names);

  /// Card action label to keep the listed members fronting
  ///
  /// In en, this message translates to:
  /// **'Keep {names} fronting'**
  String pluralkitWhosFrontingKeepMembers(String names);

  /// Option label to leave no one fronting
  ///
  /// In en, this message translates to:
  /// **'Leave no one fronting'**
  String get pluralkitWhosFrontingNoneFronting;

  /// Option label to match PluralKit's empty fronters state
  ///
  /// In en, this message translates to:
  /// **'Match PluralKit (no one fronting)'**
  String get pluralkitWhosFrontingMatchPkNone;

  /// Badge label shown on the recommended fronter choice card
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get pluralkitWhosFrontingRecommended;

  /// Heads-up notice shown in pull-only mode before mapping, naming the current PK fronter(s)
  ///
  /// In en, this message translates to:
  /// **'PluralKit currently has {names} fronting; this will become your active fronter when you sync.'**
  String pluralkitPullOnlyHeadsUp(String names);

  /// Banner shown when the user chose 'Decide later' during the fronter resolution step
  ///
  /// In en, this message translates to:
  /// **'First sync deferred. Tap **Sync recent** when you\'re ready — it\'ll pull your full PluralKit history.'**
  String get pluralkitFirstSyncDeferred;

  /// Notice shown when a pending fronting migration is blocking PluralKit setup
  ///
  /// In en, this message translates to:
  /// **'Resolve the fronting migration to finish setting up PluralKit sync.'**
  String get pluralkitMigrationBlockedNotice;

  /// Wake-up sheet greeting shown between 5am and noon
  ///
  /// In en, this message translates to:
  /// **'Good morning!'**
  String get sleepWakeUpMorning;

  /// Wake-up sheet greeting shown between noon and 5pm
  ///
  /// In en, this message translates to:
  /// **'Good afternoon!'**
  String get sleepWakeUpAfternoon;

  /// Wake-up sheet greeting shown between 5pm and 9pm
  ///
  /// In en, this message translates to:
  /// **'Good evening!'**
  String get sleepWakeUpEvening;

  /// Wake-up sheet greeting shown between 9pm and 5am (nap wakeup)
  ///
  /// In en, this message translates to:
  /// **'Rise and shine!'**
  String get sleepWakeUpNight;

  /// Subtitle in wake-up sheet showing sleep duration
  ///
  /// In en, this message translates to:
  /// **'You slept for {duration}'**
  String sleepWakeUpSleptFor(String duration);

  /// Label above quality star rating in wake-up sheet
  ///
  /// In en, this message translates to:
  /// **'How was your sleep?'**
  String get sleepWakeUpQualityQuestion;

  /// Label above member picker in wake-up sheet
  ///
  /// In en, this message translates to:
  /// **'Who\'s fronting now?'**
  String get sleepWakeUpWhosFronting;

  /// Primary action button in wake-up sheet
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sleepWakeUpDone;

  /// Secondary action button in wake-up sheet (ends sleep without rating/fronting)
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get sleepWakeUpSkip;

  /// Button to show remaining members not in quick-front circles
  ///
  /// In en, this message translates to:
  /// **'Others...'**
  String get sleepWakeUpOthers;

  /// Bedtime reminder banner title on fronting screen
  ///
  /// In en, this message translates to:
  /// **'It\'s your usual bedtime'**
  String get sleepSuggestionBedtime;

  /// Action button on bedtime reminder banner
  ///
  /// In en, this message translates to:
  /// **'Start Sleep'**
  String get sleepSuggestionBedtimeAction;

  /// Nudge text shown on sleep card when wake suggestion duration exceeded
  ///
  /// In en, this message translates to:
  /// **'You\'ve been sleeping for {duration}'**
  String sleepWakeSuggestionNudge(String duration);

  /// Section title for suggestion settings on sleep feature screen
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get featureSleepSuggestions;

  /// Toggle title for bedtime reminder setting
  ///
  /// In en, this message translates to:
  /// **'Bedtime Reminder'**
  String get featureSleepBedtimeReminder;

  /// Toggle subtitle for bedtime reminder setting
  ///
  /// In en, this message translates to:
  /// **'Show a reminder at your usual bedtime'**
  String get featureSleepBedtimeReminderSubtitle;

  /// Row title for bedtime time picker
  ///
  /// In en, this message translates to:
  /// **'Bedtime'**
  String get featureSleepBedtimeTime;

  /// Toggle title for wake reminder setting
  ///
  /// In en, this message translates to:
  /// **'Wake Reminder'**
  String get featureSleepWakeReminder;

  /// Toggle subtitle for wake reminder setting
  ///
  /// In en, this message translates to:
  /// **'Nudge to wake after a set duration'**
  String get featureSleepWakeReminderSubtitle;

  /// Row title for wake duration picker
  ///
  /// In en, this message translates to:
  /// **'Wake After'**
  String get featureSleepWakeAfter;

  /// Display format for wake duration setting
  ///
  /// In en, this message translates to:
  /// **'{hours} hours'**
  String featureSleepWakeAfterHours(String hours);

  /// No description provided for @onboardingSyncMembersLabel.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get onboardingSyncMembersLabel;

  /// No description provided for @onboardingSyncPhaseConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get onboardingSyncPhaseConnectTitle;

  /// No description provided for @onboardingSyncPhaseConnectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Saying hello to your other device'**
  String get onboardingSyncPhaseConnectSubtitle;

  /// No description provided for @onboardingSyncPhaseDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading your data'**
  String get onboardingSyncPhaseDownloadTitle;

  /// No description provided for @onboardingSyncPhaseDownloadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pulling the encrypted snapshot'**
  String get onboardingSyncPhaseDownloadSubtitle;

  /// No description provided for @onboardingSyncPhaseRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restoring your data'**
  String get onboardingSyncPhaseRestoreTitle;

  /// No description provided for @onboardingSyncPhaseRestoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unpacking headmates, messages, and notes'**
  String get onboardingSyncPhaseRestoreSubtitle;

  /// No description provided for @onboardingSyncPhaseFinishTitle.
  ///
  /// In en, this message translates to:
  /// **'Wrapping up'**
  String get onboardingSyncPhaseFinishTitle;

  /// No description provided for @onboardingSyncPhaseFinishSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Locking things in for good'**
  String get onboardingSyncPhaseFinishSubtitle;

  /// No description provided for @onboardingSyncReassurance.
  ///
  /// In en, this message translates to:
  /// **'Still going — larger restores can take a minute on slow networks.'**
  String get onboardingSyncReassurance;

  /// No description provided for @onboardingSyncReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to the relay…'**
  String get onboardingSyncReconnecting;

  /// No description provided for @onboardingSyncNoDataToRestore.
  ///
  /// In en, this message translates to:
  /// **'No prior data to restore — starting fresh.'**
  String get onboardingSyncNoDataToRestore;

  /// No description provided for @onboardingSyncStillPullingBackground.
  ///
  /// In en, this message translates to:
  /// **'Still pulling updates in the background. You can continue.'**
  String get onboardingSyncStillPullingBackground;

  /// No description provided for @onboardingSyncPhaseAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Now {phase}'**
  String onboardingSyncPhaseAnnouncement(String phase);

  /// No description provided for @onboardingSyncRestoredSummary.
  ///
  /// In en, this message translates to:
  /// **'Restored {members} members and {messages} messages.'**
  String onboardingSyncRestoredSummary(int members, int messages);

  /// Semantics label for the onboarding phase progress indicator
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingPhaseSegmentsSemantics(int current, int total);

  /// Title of the first-pull PK system profile disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'Import your system profile from PluralKit?'**
  String get pkProfileDisclosureTitle;

  /// Subtitle of the first-pull PK system profile disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'We\'ll only copy what you check.'**
  String get pkProfileDisclosureSubtitle;

  /// Primary action on the PK system profile disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'Import selected'**
  String get pkProfileDisclosureImport;

  /// Secondary action on the PK system profile disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get pkProfileDisclosureSkip;

  /// Row label for the PK system name field on the disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'System name'**
  String get pkProfileFieldName;

  /// Row label for the PK system description field on the disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get pkProfileFieldDescription;

  /// Row label for the PK system tag field on the disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'System tag'**
  String get pkProfileFieldTag;

  /// Row label for the PK system avatar field on the disclosure sheet
  ///
  /// In en, this message translates to:
  /// **'System avatar'**
  String get pkProfileFieldAvatar;

  /// Hint shown when a Prism system settings field is already populated and would be overwritten by PK import
  ///
  /// In en, this message translates to:
  /// **'Prism already has a value — tick to overwrite.'**
  String get pkProfileFieldOverwriteHint;

  /// Top bar title for the SP custom-fronts disposition step
  ///
  /// In en, this message translates to:
  /// **'Custom fronts'**
  String get migrationCfStepTitle;

  /// Header copy on the custom-fronts disposition step
  ///
  /// In en, this message translates to:
  /// **'Simply Plural has custom fronts (Co-fronting, Asleep, and others). Prism doesn\'t track these as first-class statuses. Pick how to handle each one.'**
  String get migrationCfStepExplainer;

  /// Button that re-seeds custom front dispositions from the heuristics
  ///
  /// In en, this message translates to:
  /// **'Reset to smart defaults'**
  String get migrationCfResetDefaults;

  /// Back button on the custom-fronts disposition step
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get migrationCfBack;

  /// Continue button on the custom-fronts disposition step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get migrationCfContinue;

  /// Disposition option: create a tagged member for the custom front
  ///
  /// In en, this message translates to:
  /// **'Import as {termSingularLower}'**
  String migrationCfOptionMember(String termSingularLower);

  /// Disposition option: append the CF name to affected session notes
  ///
  /// In en, this message translates to:
  /// **'Merge into notes'**
  String get migrationCfOptionNote;

  /// Disposition option: turn primary CF entries into sleep sessions
  ///
  /// In en, this message translates to:
  /// **'Convert to sleep'**
  String get migrationCfOptionSleep;

  /// Disposition option: drop the CF entirely
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get migrationCfOptionSkip;

  /// Longer description of the import-as-member disposition
  ///
  /// In en, this message translates to:
  /// **'Creates a {termSingularLower} with this name. Front history entries for it are kept as {termSingularLower} sessions.'**
  String migrationCfOptionMemberDesc(String termSingularLower);

  /// Longer description of the merge-as-note disposition
  ///
  /// In en, this message translates to:
  /// **'No member is created. The custom front\'s name is appended to the notes of sessions it touches.'**
  String get migrationCfOptionNoteDesc;

  /// Longer description of the convert-to-sleep disposition
  ///
  /// In en, this message translates to:
  /// **'Front history entries where this is the primary fronter become sleep sessions instead.'**
  String get migrationCfOptionSleepDesc;

  /// Longer description of the skip disposition
  ///
  /// In en, this message translates to:
  /// **'No member, no note. Sessions with no other fronter are dropped.'**
  String get migrationCfOptionSkipDesc;

  /// Smart-default reason: CF name looked like sleep
  ///
  /// In en, this message translates to:
  /// **'Name matches sleep keywords'**
  String get migrationCfReasonSleepName;

  /// Smart-default reason: CF is unused
  ///
  /// In en, this message translates to:
  /// **'Never used in front history or timers'**
  String get migrationCfReasonZeroUsage;

  /// Smart-default reason: CF only appears as co-fronter
  ///
  /// In en, this message translates to:
  /// **'Only used as fronter'**
  String get migrationCfReasonCoFronterOnly;

  /// Smart-default reason: CF dominates as primary
  ///
  /// In en, this message translates to:
  /// **'Used mostly as primary fronter'**
  String get migrationCfReasonPrimaryHeavy;

  /// Smart-default reason: fallback disposition
  ///
  /// In en, this message translates to:
  /// **'Mixed usage — safest to preserve as a note'**
  String get migrationCfReasonFallback;

  /// Per-CF usage summary: primary / co-fronter / timer counts
  ///
  /// In en, this message translates to:
  /// **'{primary, plural, =0{Never primary} =1{1 primary} other{{primary} primary}} · {coFront, plural, =0{0 overlaps} =1{1 overlap} other{{coFront} overlaps}} · {timers, plural, =0{0 timers} =1{1 timer} other{{timers} timers}}'**
  String migrationCfUsageSummary(int primary, int coFront, int timers);

  /// Import-preview card summary of the chosen custom-front dispositions
  ///
  /// In en, this message translates to:
  /// **'{asMember, plural, =1{1 as member} other{{asMember} as members}} · {asSleep, plural, =1{1 as sleep} other{{asSleep} as sleep}} · {asNote, plural, =1{1 note} other{{asNote} notes}} · {asSkip, plural, =1{1 skipped} other{{asSkip} skipped}}'**
  String migrationCfPreviewBreakdown(
    int asMember,
    int asSleep,
    int asNote,
    int asSkip,
  );

  /// Warning: sessions dropped because their primary was a skipped CF and nothing could be promoted
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 front-history entry dropped (primary was a skipped custom front with no fronters).} other{{count} front-history entries dropped (primary was a skipped custom front with no fronters).}}'**
  String migrationWarnCfDroppedEntries(int count);

  /// Warning: sleep-converted sessions had co-fronters dropped
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sleep-mode session had fronters that were discarded.} other{{count} sleep-mode sessions had fronters that were discarded.}}'**
  String migrationWarnCfSleepCoFrontersDiscarded(int count);

  /// Warning: sleep CF in co-fronter list preserved as note
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 front session had a sleep custom front as fronter, preserved as note only.} other{{count} front sessions had a sleep custom front as fronter, preserved as note only.}}'**
  String migrationWarnCfSleepCoFronterAsNote(int count);

  /// Warning: sleep sessions overlap existing/other sessions
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sleep session overlaps with other sessions in your timeline — resolve in the Fronting tab.} other{{count} sleep sessions overlap with other sessions in your timeline — resolve in the Fronting tab.}}'**
  String migrationWarnCfSleepOverlap(int count);

  /// Warning: comments orphaned by dropped CF entries
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 comment dropped (attached to skipped custom-front sessions).} other{{count} comments dropped (attached to skipped custom-front sessions).}}'**
  String migrationWarnCfCommentsDropped(int count);

  /// Warning: prior-import CF members were scrubbed from the map but not the DB
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 previously-imported custom front is no longer imported as a member; the existing member record remains — delete manually if you want it gone.} other{{count} previously-imported custom fronts are no longer imported as members; the existing member records remain — delete manually if you want them gone.}}'**
  String migrationWarnCfStaleMembers(int count);

  /// Warning: synthetic CF fallback used because referenced CF was missing
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 front-history reference pointed to a custom front deleted in SP — handled as a note.} other{{count} front-history references pointed to custom fronts deleted in SP — handled as notes.}}'**
  String migrationWarnCfDeletedRefs(int count);

  /// Warning: open-ended sleep entries were clamped to 24h
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open-ended SP sleep entry clamped to 24h duration.} other{{count} open-ended SP sleep entries clamped to 24h duration.}}'**
  String migrationWarnCfSleepClamped(int count);

  /// Warning: timers pointing at non-member CFs were adjusted
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 timer targeted a custom front that isn\'t imported as a member — target dropped or timer removed.} other{{count} timers targeted custom fronts that aren\'t imported as members — target dropped or timer removed.}}'**
  String migrationWarnCfTimersAdjusted(int count);

  /// Warning: same-start SP sleep entries were deduped
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 duplicate-start SP sleep entry collapsed.} other{{count} duplicate-start SP sleep entries collapsed.}}'**
  String migrationWarnCfSleepDedup(int count);

  /// Title bar of the per-member fronting upgrade modal
  ///
  /// In en, this message translates to:
  /// **'Fronting upgrade'**
  String get frontingUpgradeTitle;

  /// Intro screen headline
  ///
  /// In en, this message translates to:
  /// **'We\'re upgrading how fronting is stored'**
  String get frontingUpgradeIntroHeadline;

  /// Intro screen body explaining the upgrade
  ///
  /// In en, this message translates to:
  /// **'Overlapping fronts now use one record per {termSingularLower} instead of one shared record. This makes overlaps, edits, and analytics work correctly. We\'ll save a backup of your current data first, then run the upgrade.'**
  String frontingUpgradeIntroBody(String termSingularLower);

  /// Primary continue button on the intro screen
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get frontingUpgradeContinue;

  /// Role-selection screen headline
  ///
  /// In en, this message translates to:
  /// **'Is this your main device?'**
  String get frontingUpgradeRoleHeadline;

  /// Role-selection screen body
  ///
  /// In en, this message translates to:
  /// **'Your main device keeps all your fronting history. Other devices will need to pair again afterward and pull the migrated history from the main device.'**
  String get frontingUpgradeRoleBody;

  /// Primary-role button
  ///
  /// In en, this message translates to:
  /// **'Yes, this is my main device'**
  String get frontingUpgradeRolePrimary;

  /// Secondary-role button
  ///
  /// In en, this message translates to:
  /// **'No, this is a secondary'**
  String get frontingUpgradeRoleSecondary;

  /// Mode-picker screen headline
  ///
  /// In en, this message translates to:
  /// **'How should we upgrade?'**
  String get frontingUpgradeModeHeadline;

  /// Mode card: upgradeAndKeep title
  ///
  /// In en, this message translates to:
  /// **'Keep my data'**
  String get frontingUpgradeModeKeepTitle;

  /// Mode card: upgradeAndKeep body
  ///
  /// In en, this message translates to:
  /// **'Your existing fronts stay. PluralKit-imported fronts get re-imported with the new shape on next PluralKit sync.'**
  String get frontingUpgradeModeKeepBody;

  /// Mode card: startFresh title
  ///
  /// In en, this message translates to:
  /// **'Start fresh'**
  String get frontingUpgradeModeFreshTitle;

  /// Mode card: startFresh body
  ///
  /// In en, this message translates to:
  /// **'All fronts are wiped. Useful if your fronting history is messy and you want a clean slate. A backup file is still created.'**
  String get frontingUpgradeModeFreshBody;

  /// Recommended badge on the keep-data mode card
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get frontingUpgradeRecommended;

  /// Password screen headline
  ///
  /// In en, this message translates to:
  /// **'Protect your backup'**
  String get frontingUpgradePasswordHeadline;

  /// Password screen body
  ///
  /// In en, this message translates to:
  /// **'We\'re about to back up your current fronting data and then upgrade it.'**
  String get frontingUpgradePasswordBody;

  /// Password screen note above the input
  ///
  /// In en, this message translates to:
  /// **'This password protects your backup file. Save it somewhere safe — without it, the file can\'t be recovered.'**
  String get frontingUpgradePasswordNote;

  /// Submit button on the password screen
  ///
  /// In en, this message translates to:
  /// **'Back up and upgrade'**
  String get frontingUpgradePasswordSubmit;

  /// Title shown while the migration is running
  ///
  /// In en, this message translates to:
  /// **'Migrating your fronting history…'**
  String get frontingUpgradeRunning;

  /// Subtitle shown while the migration is running
  ///
  /// In en, this message translates to:
  /// **'This may take a moment. Don\'t close the app.'**
  String get frontingUpgradeRunningSubtitle;

  /// Title shown while the PRISM1 backup is being exported
  ///
  /// In en, this message translates to:
  /// **'Building your backup…'**
  String get frontingUpgradeExporting;

  /// Subtitle shown while the PRISM1 backup is being exported
  ///
  /// In en, this message translates to:
  /// **'Encrypting your fronting data so you can keep a copy.'**
  String get frontingUpgradeExportingSubtitle;

  /// Headline of the durable-save gate that runs before the destructive migration step
  ///
  /// In en, this message translates to:
  /// **'Backup ready'**
  String get frontingUpgradeBackupReadyHeadline;

  /// Body text on the durable-save gate explaining why saving the file is important
  ///
  /// In en, this message translates to:
  /// **'Save this backup somewhere you\'ll be able to find it later — outside the app. Without it, you can\'t recover your old data if anything goes wrong.'**
  String get frontingUpgradeBackupReadyBody;

  /// Primary action on the backup-ready step — opens a file picker to save the file to a user-chosen destination
  ///
  /// In en, this message translates to:
  /// **'Save backup…'**
  String get frontingUpgradeBackupSaveAs;

  /// Secondary action on the backup-ready step — opens the system share sheet
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get frontingUpgradeBackupShare;

  /// Manual checkbox on the backup-ready step — auto-ticks on a successful save
  ///
  /// In en, this message translates to:
  /// **'I have saved this backup somewhere I can find later'**
  String get frontingUpgradeBackupAcknowledge;

  /// Continue button on the backup-ready step; disabled until the acknowledgment checkbox is ticked
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get frontingUpgradeBackupContinue;

  /// Success screen headline
  ///
  /// In en, this message translates to:
  /// **'Migration complete!'**
  String get frontingUpgradeSuccessHeadline;

  /// Success counter: SP rows migrated
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Migrated 1 Simply Plural session.} other{Migrated {count} Simply Plural sessions.}}'**
  String frontingUpgradeCountSpMigrated(int count);

  /// Success counter: native rows migrated
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Migrated 1 fronting session.} other{Migrated {count} fronting sessions.}}'**
  String frontingUpgradeCountNativeMigrated(int count);

  /// Success counter: native rows fanned out
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Expanded 1 overlapping period into per-{termSingularLower} records.} other{Expanded {count} overlapping periods into per-{termSingularLower} records.}}'**
  String frontingUpgradeCountNativeExpanded(
    int count,
    String termSingularLower,
  );

  /// Success counter and follow-up guidance when old-format PluralKit fronting history was cleared
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Old-format PluralKit history was cleared (1 session). Re-import it from a PluralKit token or a pk;export file.} other{Old-format PluralKit history was cleared ({count} sessions). Re-import it from a PluralKit token or a pk;export file.}}'**
  String frontingUpgradeCountPkDeleted(int count);

  /// Success counter: comments migrated
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Migrated 1 comment.} other{Migrated {count} comments.}}'**
  String frontingUpgradeCountCommentsMigrated(int count);

  /// Success counter: orphan rows assigned to sentinel
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Assigned 1 unattributed session to the Unknown {termSingularLower}.} other{Assigned {count} unattributed sessions to the Unknown {termSingularLower}.}}'**
  String frontingUpgradeCountOrphansAssigned(
    int count,
    String termSingularLower,
  );

  /// Success counter: sentinel was created
  ///
  /// In en, this message translates to:
  /// **'Created an Unknown {termSingularLower} to hold sessions with no clear fronter.'**
  String frontingUpgradeCountSentinelCreated(String termSingularLower);

  /// Success counter: rows whose co_fronter_ids JSON failed to parse and were migrated as single-member fallback
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session had unreadable fronter data and was migrated as single-{termSingularLower}.} other{{count} sessions had unreadable fronter data and were migrated as single-{termSingularLower}.}}'**
  String frontingUpgradeCountCorruptCoFronters(
    int count,
    String termSingularLower,
  );

  /// Warning shown on the upgrade modal's intro screen — the sync state wipe clears pending_ops, so any local writes that haven't been pushed yet will only exist on this device after the upgrade.
  ///
  /// In en, this message translates to:
  /// **'If you have unsynced changes from offline use, make sure your device is online and synced before you continue. Pending uploads will need to be redone after the upgrade.'**
  String get frontingUpgradeIntroPendingSyncWarning;

  /// One-line FYI shown on the upgrade success screen explaining the analytics relabel from 'fronting time' to '{term}-minutes' (e.g., 'member-minutes', 'headmate-minutes').
  ///
  /// In en, this message translates to:
  /// **'Analytics are now framed as {term}-minutes — when two of you are fronting at once for an hour, that\'s two {term}-hours. Same math as before, clearer label.'**
  String frontingUpgradeAnalyticsNote(String term);

  /// Re-pair guidance for primary devices
  ///
  /// In en, this message translates to:
  /// **'Your other devices need to pair again to receive the migrated history. Open Settings → Sync on your other devices and follow the pairing flow.'**
  String get frontingUpgradeRepairPrimary;

  /// Re-pair guidance for secondary devices
  ///
  /// In en, this message translates to:
  /// **'Pair this device with your main device again to receive the migrated history.'**
  String get frontingUpgradeRepairSecondary;

  /// Final note for solo devices, no re-pair needed
  ///
  /// In en, this message translates to:
  /// **'All set. Your fronting data is on the new format.'**
  String get frontingUpgradeRepairSolo;

  /// Button label on the fronting migration success screen that opens PluralKit import options
  ///
  /// In en, this message translates to:
  /// **'Open PluralKit import'**
  String get frontingUpgradeOpenPluralKitImport;

  /// Failure screen headline
  ///
  /// In en, this message translates to:
  /// **'Migration failed'**
  String get frontingUpgradeFailureHeadline;

  /// Reassurance shown on the failure screen when a backup exists
  ///
  /// In en, this message translates to:
  /// **'Your backup file was saved or shared. Use the location you chose if you need to recover.'**
  String get frontingUpgradeFailureBackupNote;

  /// Home-screen banner title when migration cleanup needs to be resumed
  ///
  /// In en, this message translates to:
  /// **'Fronting upgrade pending'**
  String get frontingUpgradeBannerTitle;

  /// Home-screen banner message when migration cleanup needs to be resumed
  ///
  /// In en, this message translates to:
  /// **'Tap to continue the upgrade.'**
  String get frontingUpgradeBannerMessage;

  /// Headline shown when a previous migration attempt left the device mid-cleanup and the modal is offering to finish the remaining sync-credential reset.
  ///
  /// In en, this message translates to:
  /// **'Finish migration'**
  String get frontingUpgradeResumeCleanupHeadline;

  /// Body text on the resume-cleanup step explaining what the remaining work touches.
  ///
  /// In en, this message translates to:
  /// **'A previous upgrade attempt finished the data migration but couldn\'t complete the sync reset. Tap below to finish — no data will be touched, only the sync credentials.'**
  String get frontingUpgradeResumeCleanupBody;

  /// Primary button on the resume-cleanup step.
  ///
  /// In en, this message translates to:
  /// **'Finish migration'**
  String get frontingUpgradeResumeCleanupButton;

  /// Title of the dialog that asks for a PluralKit token after the migration finishes, used to re-import PK fronting history.
  ///
  /// In en, this message translates to:
  /// **'PluralKit token'**
  String get frontingUpgradePkTokenDialogTitle;

  /// Body of the post-migration PluralKit token dialog.
  ///
  /// In en, this message translates to:
  /// **'Import PluralKit fronting history now. This uses the token once and does not turn on PluralKit sync.'**
  String get frontingUpgradePkTokenDialogMessage;

  /// Field label inside the post-migration PluralKit token dialog.
  ///
  /// In en, this message translates to:
  /// **'PluralKit token'**
  String get frontingUpgradePkTokenLabel;

  /// Field placeholder inside the post-migration PluralKit token dialog.
  ///
  /// In en, this message translates to:
  /// **'Paste your PluralKit token'**
  String get frontingUpgradePkTokenHint;

  /// Confirm button on the post-migration PluralKit token dialog.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get frontingUpgradePkTokenImport;

  /// Button on the post-migration success screen that opens the PK token dialog.
  ///
  /// In en, this message translates to:
  /// **'Import with PluralKit token'**
  String get frontingUpgradePkImportButton;

  /// Idle hint shown on the post-migration success screen before the user opts into a one-shot PK re-import.
  ///
  /// In en, this message translates to:
  /// **'PluralKit history can be re-imported here with a temporary token. The token is used once and PluralKit sync stays off.'**
  String get frontingUpgradePkImportIdle;

  /// Status line shown while the post-migration PluralKit re-import is running.
  ///
  /// In en, this message translates to:
  /// **'Re-importing PluralKit history...'**
  String get frontingUpgradePkImportRunning;

  /// Confirmation line shown after a successful post-migration PluralKit re-import.
  ///
  /// In en, this message translates to:
  /// **'PluralKit history was re-imported.'**
  String get frontingUpgradePkImportImported;

  /// Optional follow-on line on the post-migration success screen reporting tombstoned rows the corrective re-import declined to resurrect.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 deleted row was left as-is to honor the local delete.} other{{count} deleted rows were left as-is to honor the local delete.}}'**
  String frontingUpgradePkImportTombstoneLine(int count);

  /// Optional follow-on line reporting zero-length presence skips during the post-migration PluralKit re-import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 zero-length close was skipped (PluralKit listed an enter and a leave at the same instant).} other{{count} zero-length closes were skipped (PluralKit listed an enter and a leave at the same instant).}}'**
  String frontingUpgradePkImportZeroLengthLine(int count);

  /// Status line shown when the post-migration PluralKit re-import needs a token from the user.
  ///
  /// In en, this message translates to:
  /// **'No stored PluralKit token was found. You can import with a temporary token here without turning on PluralKit sync.'**
  String get frontingUpgradePkImportNeedsToken;

  /// Status line shown when the post-migration PluralKit re-import errors out.
  ///
  /// In en, this message translates to:
  /// **'PluralKit re-import failed: {error}'**
  String frontingUpgradePkImportFailed(String error);

  /// PluralKit file import preview/result row label for the count of members. Uses the user's terminology.
  ///
  /// In en, this message translates to:
  /// **'{termPlural}'**
  String pkFileImportMembersLabel(String termPlural);

  /// PluralKit file import preview/result row label for the count of groups. Kept generic — PluralKit's own 'group' concept.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get pkFileImportGroupsLabel;

  /// PluralKit file import preview row label for switches found in the export but not imported from file.
  ///
  /// In en, this message translates to:
  /// **'Switches found (not imported)'**
  String get pkFileImportFrontingSessionsLabel;

  /// PluralKit file import preview/result row label for switches found in the export but not imported from file.
  ///
  /// In en, this message translates to:
  /// **'Switches found (not imported)'**
  String get pkFileImportSwitchesFoundLabel;

  /// Informational note shown on the PluralKit file import preview screen before file plus token fronting import.
  ///
  /// In en, this message translates to:
  /// **'Existing {termPlural} with the same PluralKit ID will be updated. To import fronting history, add a PluralKit token so Prism can match export switches before importing fronts.'**
  String pkFileImportPreviewNote(String termPlural);

  /// PluralKit file import: primary action button on the preview screen
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get pkFileImportImportButton;

  /// PluralKit file import result row label for switches reconciled against the API by the token-backed import path.
  ///
  /// In en, this message translates to:
  /// **'Switches matched with token'**
  String get pkFileImportSwitchesMatchedLabel;

  /// PluralKit file import result row label for API-only switches outside the export's range.
  ///
  /// In en, this message translates to:
  /// **'Newer switches from PluralKit'**
  String get pkFileImportNewerSwitchesLabel;

  /// Note shown on the import-complete screen when fronting history was imported via the token path.
  ///
  /// In en, this message translates to:
  /// **'Fronting history was imported through the token-backed PluralKit path so Prism can keep using canonical switch IDs.'**
  String get pkFileImportFrontingImportedNote;

  /// Variant of the imported note that also reports the count of newer API-only switches.
  ///
  /// In en, this message translates to:
  /// **'Fronting history was imported through the token-backed PluralKit path so Prism can keep using canonical switch IDs. Prism also imported {count} newer switches from PluralKit that were not in the export.'**
  String pkFileImportFrontingImportedNoteWithNewer(int count);

  /// Note shown on the import-complete screen when fronting history was not imported.
  ///
  /// In en, this message translates to:
  /// **'Fronting history was not imported because the export and PluralKit API did not match safely.'**
  String get pkFileImportFrontingNotImportedNote;

  /// Primary button on the PluralKit file import complete screen.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get pkFileImportDoneButton;

  /// Headline on the PluralKit file import error screen.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get pkFileImportFailedHeadline;

  /// Button on the PluralKit file import error screen that resets the flow.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get pkFileImportTryAgainButton;

  /// PluralKit file import: secondary action button on the preview screen to choose a different file
  ///
  /// In en, this message translates to:
  /// **'Pick a different file'**
  String get pkFileImportPickDifferentButton;

  /// PluralKit file import: heading on the success screen
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get pkFileImportCompleteHeading;

  /// PluralKit file import result row: count of switches that were newly created. 'Switches' is PluralKit-internal vocabulary and is intentionally not localised through the terminology system.
  ///
  /// In en, this message translates to:
  /// **'Switches created'**
  String get pkFileImportSwitchesCreatedLabel;

  /// PluralKit file import result row: count of switches found in the export but not imported from file. 'Switches' is PluralKit-internal vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Switches found (not imported)'**
  String get pkFileImportSwitchesSkippedLabel;

  /// Section header on the fronting feature settings screen, grouping the list view-mode preference and the add-front / quick-front default behavior preferences.
  ///
  /// In en, this message translates to:
  /// **'Session display & front behavior'**
  String get settingsFrontingSessionDisplaySectionTitle;

  /// Row title for the home-screen session list view-mode preference (combined periods / per-member rows / timeline).
  ///
  /// In en, this message translates to:
  /// **'Session list view'**
  String get settingsFrontingListViewModeLabel;

  /// Option label: render the home-screen session list as combined periods (avatar stacks per unique fronter group).
  ///
  /// In en, this message translates to:
  /// **'Combined periods'**
  String get settingsFrontingListViewModeCombinedPeriods;

  /// Option subtitle for the combined-periods session list view mode.
  ///
  /// In en, this message translates to:
  /// **'Avatar stacks for each unique fronter group'**
  String get settingsFrontingListViewModeCombinedPeriodsDescription;

  /// Option label: render the home-screen session list as one row per fronter session, side-by-side. {term} is the user's chosen singular member terminology (lowercase).
  ///
  /// In en, this message translates to:
  /// **'Per-{term} rows'**
  String settingsFrontingListViewModePerMemberRows(String term);

  /// Option subtitle for the per-member-rows session list view mode.
  ///
  /// In en, this message translates to:
  /// **'One row per fronter session, side-by-side'**
  String get settingsFrontingListViewModePerMemberRowsDescription;

  /// Option label: render the home-screen session list as a timeline / bar chart over time.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get settingsFrontingListViewModeTimeline;

  /// Option subtitle for the timeline session list view mode.
  ///
  /// In en, this message translates to:
  /// **'Bar chart view of fronting over time'**
  String get settingsFrontingListViewModeTimelineDescription;

  /// Row title for the default behavior preference when starting a new front from the add-front sheet.
  ///
  /// In en, this message translates to:
  /// **'When adding a new front'**
  String get settingsAddFrontDefaultBehaviorLabel;

  /// Option label: starting a new front leaves any existing fronts in place; the new member joins as a co-fronter.
  ///
  /// In en, this message translates to:
  /// **'Add as fronter'**
  String get settingsAddFrontDefaultBehaviorAdditive;

  /// Option subtitle for the additive add-front default behavior.
  ///
  /// In en, this message translates to:
  /// **'New fronts join existing ones'**
  String get settingsAddFrontDefaultBehaviorAdditiveDescription;

  /// Option label: starting a new front ends all existing fronts before the new member begins.
  ///
  /// In en, this message translates to:
  /// **'Replace current fronters'**
  String get settingsAddFrontDefaultBehaviorReplace;

  /// Option subtitle for the replace add-front default behavior.
  ///
  /// In en, this message translates to:
  /// **'End all current fronts before starting new ones'**
  String get settingsAddFrontDefaultBehaviorReplaceDescription;

  /// Row title for the default behavior preference when triggering quick front (the per-member quick-action shortcut).
  ///
  /// In en, this message translates to:
  /// **'When using quick front'**
  String get settingsQuickFrontDefaultBehaviorLabel;

  /// Switch label for whether long-running fronting sessions should appear in the pinned header even without explicit always-fronting opt-in.
  ///
  /// In en, this message translates to:
  /// **'Show long-running fronts in header'**
  String get settingsAutoPromoteLongFrontingSessionsLabel;

  /// Switch subtitle for whether long-running fronting sessions should appear in the pinned header even without explicit always-fronting opt-in.
  ///
  /// In en, this message translates to:
  /// **'After 7 days, show active fronts in the pinned header without marking them Always fronting or hiding them from history.'**
  String get settingsAutoPromoteLongFrontingSessionsDescription;

  /// Option label: quick front leaves existing fronts in place; the tapped member joins as a co-fronter.
  ///
  /// In en, this message translates to:
  /// **'Add as fronter'**
  String get settingsQuickFrontDefaultBehaviorAdditive;

  /// Option label: quick front ends all existing fronts before the tapped member begins.
  ///
  /// In en, this message translates to:
  /// **'Replace current fronters'**
  String get settingsQuickFrontDefaultBehaviorReplace;

  /// Settings row + dialog title for how chat and message-board composers pick the default member you act as.
  ///
  /// In en, this message translates to:
  /// **'Default when composing'**
  String get settingsComposerDefaultMemberLabel;

  /// Option label: default to the most recently started front.
  ///
  /// In en, this message translates to:
  /// **'Latest fronter'**
  String get settingsComposerDefaultMemberLatestFronter;

  /// Option subtitle for the latest-fronter composer default.
  ///
  /// In en, this message translates to:
  /// **'Open as whoever started fronting most recently'**
  String get settingsComposerDefaultMemberLatestFronterDescription;

  /// Option label: default to whoever you last acted as.
  ///
  /// In en, this message translates to:
  /// **'Last used'**
  String get settingsComposerDefaultMemberLastUsed;

  /// Option subtitle for the last-used composer default.
  ///
  /// In en, this message translates to:
  /// **'Open as whoever you picked last time'**
  String get settingsComposerDefaultMemberLastUsedDescription;

  /// Option label: open the picker each time you start composing.
  ///
  /// In en, this message translates to:
  /// **'Ask each time'**
  String get settingsComposerDefaultMemberAskEachTime;

  /// Option subtitle for the ask-each-time composer default.
  ///
  /// In en, this message translates to:
  /// **'Open the picker each time you start writing'**
  String get settingsComposerDefaultMemberAskEachTimeDescription;

  /// Muted section label above the current-fronters block in member picker sheets.
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get memberPickerFrontingSectionLabel;

  /// Title of the Message Boards feature settings screen.
  ///
  /// In en, this message translates to:
  /// **'Message Boards'**
  String get featureBoardsTitle;

  /// Description shown at the top of the Message Boards feature settings screen.
  ///
  /// In en, this message translates to:
  /// **'Short messages between headmates — public timeline plus private inbox.'**
  String get featureBoardsDescription;

  /// Toggle row title for enabling the Message Boards feature.
  ///
  /// In en, this message translates to:
  /// **'Enable Message Boards'**
  String get featureBoardsEnable;

  /// Toggle row subtitle explaining what enabling Message Boards does.
  ///
  /// In en, this message translates to:
  /// **'Adds the Boards tab to your nav.'**
  String get featureBoardsEnableSubtitle;

  /// One-time toast shown when Message Boards is first enabled via the settings toggle.
  ///
  /// In en, this message translates to:
  /// **'Message Boards added to your nav menu — drag it where you want.'**
  String get navMenuToastBoardsAdded;

  /// Suffix shown after the timestamp on a board post tile when the post has been edited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get boardsTileEdited;

  /// Recipient chip text shown on a public post with no specific target member.
  ///
  /// In en, this message translates to:
  /// **'to everyone'**
  String get boardsTileToEveryone;

  /// Recipient name shown after the to connector on public board posts with no specific target member.
  ///
  /// In en, this message translates to:
  /// **'everyone'**
  String get boardsTileEveryone;

  /// Fallback name shown when the author or target member of a board post no longer exists.
  ///
  /// In en, this message translates to:
  /// **'Removed member'**
  String get boardsTileRemovedMember;

  /// Edit action label in the board post detail sheet and context menu.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get boardsDetailEdit;

  /// Delete action label in the board post detail sheet and context menu.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get boardsDetailDelete;

  /// Title of the confirmation dialog shown before deleting a board post.
  ///
  /// In en, this message translates to:
  /// **'Delete this post?'**
  String get boardsDeleteConfirmTitle;

  /// Body text of the confirmation dialog shown before deleting a board post.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get boardsDeleteConfirmBody;

  /// Title of the per-member board messages screen and section. The screen only shows public posts.
  ///
  /// In en, this message translates to:
  /// **'Public Posts'**
  String get memberBoardScreenTitle;

  /// Empty state subtitle shown when a member's board has no posts.
  ///
  /// In en, this message translates to:
  /// **'No public posts here yet.'**
  String get memberBoardEmpty;

  /// Title shown in the top bar of the main Boards screen.
  ///
  /// In en, this message translates to:
  /// **'Boards'**
  String get boardsScreenTitle;

  /// Label for the Public sub-tab on the Boards screen.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get boardsTabPublic;

  /// Label for the Inbox sub-tab on the Boards screen.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get boardsTabInbox;

  /// Inbox view-filter option: show posts for all currently-fronting members.
  ///
  /// In en, this message translates to:
  /// **'All fronters'**
  String get boardsViewFilterAll;

  /// Inbox view-filter option showing a specific member's name.
  ///
  /// In en, this message translates to:
  /// **'{name}'**
  String boardsViewFilterMember(String name);

  /// Empty state subtitle for the Public sub-tab when no posts exist.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the public timeline yet.'**
  String get boardsEmptyPublic;

  /// Empty state subtitle for the Inbox sub-tab when there are no private posts.
  ///
  /// In en, this message translates to:
  /// **'No private posts right now.'**
  String get boardsEmptyInbox;

  /// Hint shown in the Inbox empty state when no members are currently fronting.
  ///
  /// In en, this message translates to:
  /// **'No one\'s fronting right now — start a session to post.'**
  String get boardsComposeNoFronterHint;

  /// Toast shown when the inbox view-filter member stops fronting, resetting the filter.
  ///
  /// In en, this message translates to:
  /// **'{name} de-fronted — showing all'**
  String boardsToastFronterDeFronted(String name);

  /// Recipient picker option: post is public and addressed to all system members.
  ///
  /// In en, this message translates to:
  /// **'Everyone (public)'**
  String get boardsComposeRecipientPublicEveryone;

  /// Recipient picker option: post is public and addressed to a specific member.
  ///
  /// In en, this message translates to:
  /// **'{name} (public)'**
  String boardsComposeRecipientPublicMember(String name);

  /// Recipient picker option: post is private and addressed to a specific member.
  ///
  /// In en, this message translates to:
  /// **'{name} (private)'**
  String boardsComposeRecipientPrivateMember(String name);

  /// Affordance label to reveal the optional title field in the compose sheet.
  ///
  /// In en, this message translates to:
  /// **'+ Add title'**
  String get boardsComposeAddTitle;

  /// Placeholder text for the optional title field in the compose sheet.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get boardsComposeTitlePlaceholder;

  /// Placeholder text for the required body field in the compose sheet.
  ///
  /// In en, this message translates to:
  /// **'Write something...'**
  String get boardsComposeBodyPlaceholder;

  /// Consequence text shown when composing a private post to a named member.
  ///
  /// In en, this message translates to:
  /// **'Only {name} will see this in their Inbox.'**
  String boardsComposeConsequencePrivate(String name);

  /// Consequence text shown when composing a public post directed at a named member.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s profile and the Public feed will show this.'**
  String boardsComposeConsequencePublicMember(String name);

  /// Consequence text shown when composing a public post addressed to no specific member.
  ///
  /// In en, this message translates to:
  /// **'Everyone will see this in the Public feed.'**
  String get boardsComposeConsequencePublicEveryone;

  /// Save/submit button label in the compose post sheet.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get boardsComposeSave;

  /// Cancel button label in the compose post sheet.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get boardsComposeCancel;

  /// Sheet title when editing an existing board post.
  ///
  /// In en, this message translates to:
  /// **'Edit post'**
  String get boardsComposeEditing;

  /// Sheet title when composing a new board post.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get boardsComposeNewPost;

  /// Audience segment label: post visible to everyone in the system.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get boardsComposeAudienceEveryone;

  /// Audience segment label: post visible only to the addressed headmate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get boardsComposeAudiencePrivate;

  /// Label shown in the recipient row when no headmate has been addressed.
  ///
  /// In en, this message translates to:
  /// **'No recipient'**
  String get boardsComposeToNoHeadmate;

  /// Dialog title asking which co-fronter is authoring the board post.
  ///
  /// In en, this message translates to:
  /// **'Who is posting?'**
  String get boardsComposeWhoIsPosting;

  /// Semantic label for the author avatar tap target in the compose toolbar when no author is selected.
  ///
  /// In en, this message translates to:
  /// **'Select author'**
  String get boardsComposeSelectAuthor;

  /// Section heading on a member's profile. The section only shows public posts (private posts addressed to the member live in the Inbox).
  ///
  /// In en, this message translates to:
  /// **'Public Posts'**
  String get memberSectionBoardMessages;

  /// Link shown below the board preview when there are 4 or more public posts.
  ///
  /// In en, this message translates to:
  /// **'See all {count} public posts'**
  String memberBoardSeeAll(int count);

  /// Tooltip for the + button in the Board Messages section header.
  ///
  /// In en, this message translates to:
  /// **'Post to {name}'**
  String memberBoardAddPost(String name);

  /// Top bar title on the full-screen board post detail view.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get boardsPostDetailTitle;

  /// Shown on the post detail screen when the post id no longer resolves (deleted, never synced).
  ///
  /// In en, this message translates to:
  /// **'This post is no longer available.'**
  String get boardsPostDetailNotFound;

  /// Explains the Simply Plural member mapping step.
  ///
  /// In en, this message translates to:
  /// **'Choose which Simply Plural members should link to existing Prism members. Linked members keep their current Prism profile photo; members imported as new use the Simply Plural data.'**
  String get spMemberMappingIntro;

  /// Button that restores suggested Simply Plural member matches.
  ///
  /// In en, this message translates to:
  /// **'Reset matches'**
  String get spMemberMappingResetDefaults;

  /// Select option to create a new Prism member for a Simply Plural member.
  ///
  /// In en, this message translates to:
  /// **'Import as new'**
  String get spMemberMappingOptionImportNew;

  /// Select option to link a Simply Plural member to an existing Prism member.
  ///
  /// In en, this message translates to:
  /// **'Link → {name}'**
  String spMemberMappingOptionLink(String name);

  /// Reason text for a Simply Plural member matched from an existing SP import mapping.
  ///
  /// In en, this message translates to:
  /// **'Matched previous import: {name}'**
  String spMemberMappingMatchedPrevious(String name);

  /// Reason text for a Simply Plural member matched by PluralKit short ID.
  ///
  /// In en, this message translates to:
  /// **'Matched PluralKit ID: {name}'**
  String spMemberMappingMatchedPk(String name);

  /// Reason text for a Simply Plural member matched by unique local name.
  ///
  /// In en, this message translates to:
  /// **'Matched name: {name}'**
  String spMemberMappingMatchedName(String name);

  /// Reason text for a Simply Plural member without a suggested local match.
  ///
  /// In en, this message translates to:
  /// **'No suggested match'**
  String get spMemberMappingNoMatch;

  /// Accessibility label for a Simply Plural member mapping row.
  ///
  /// In en, this message translates to:
  /// **'Simply Plural member {name}'**
  String spMemberMappingMemberSemantics(String name);

  /// Button label to continue from Simply Plural member mapping.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get spMemberMappingContinue;

  /// Top bar title on the PluralKit member mapping screen.
  ///
  /// In en, this message translates to:
  /// **'Link members'**
  String get pkMappingTitle;

  /// Error shown when the PK mapping screen fails to load PluralKit members.
  ///
  /// In en, this message translates to:
  /// **'Failed to load PluralKit members:\n{error}'**
  String pkMappingLoadError(String error);

  /// Retry button on the PK mapping load-error state.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get pkMappingRetry;

  /// Empty state title when neither side has members to map.
  ///
  /// In en, this message translates to:
  /// **'Nothing to map'**
  String get pkMappingEmptyTitle;

  /// Empty state subtitle on the PK mapping screen when neither side has anything to map.
  ///
  /// In en, this message translates to:
  /// **'Your PluralKit system has no members and there are no local members to push.'**
  String get pkMappingEmptySubtitle;

  /// Empty state subtitle on the PK mapping screen when every local member already carries a PluralKit link and every PluralKit member is already mapped (e.g. after restoring Prism data on an account that was previously PK-paired).
  ///
  /// In en, this message translates to:
  /// **'Every member is already linked to PluralKit — nothing to map.'**
  String get pkMappingAllLinkedSubtitle;

  /// Intro paragraph at the top of the PK mapping screen explaining the per-row decisions.
  ///
  /// In en, this message translates to:
  /// **'For each PluralKit member, link to an existing Prism member, import as new, or skip. Unlinked Prism members can be pushed to PluralKit below.'**
  String get pkMappingIntro;

  /// Section heading for the list of PluralKit members on the mapping screen.
  ///
  /// In en, this message translates to:
  /// **'PluralKit members'**
  String get pkMappingSectionPkMembers;

  /// Section heading for unlinked local members that can be pushed to PluralKit.
  ///
  /// In en, this message translates to:
  /// **'Local members to push'**
  String get pkMappingSectionLocalToPush;

  /// Progress label while the PK mapping is being applied.
  ///
  /// In en, this message translates to:
  /// **'Applying… {percent}%'**
  String pkMappingApplyProgress(int percent);

  /// Status text shown above the Apply button while PK switch history is being imported after the mapping decisions have all applied.
  ///
  /// In en, this message translates to:
  /// **'Importing switch history…'**
  String get pkMappingImportingHistory;

  /// Status text shown above the Apply button while the user's selected current-fronter set is being applied after the PluralKit mapping decisions.
  ///
  /// In en, this message translates to:
  /// **'Resolving fronter choice…'**
  String get pkMappingResolvingFronters;

  /// Status text shown above the Apply button while pending switch updates are being pushed to PluralKit after the mapping decisions have all applied.
  ///
  /// In en, this message translates to:
  /// **'Pushing switch updates to PluralKit…'**
  String get pkMappingPushingHistory;

  /// Error banner shown on the Link Members screen when the Apply pre-flight check cannot reach PluralKit (offline, DNS failure, etc.).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach PluralKit. Check your internet connection and tap Apply again.'**
  String get pkMappingNetworkErrorOffline;

  /// Footer button that applies the chosen PK mapping decisions.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get pkMappingApply;

  /// Footer button that dismisses the PK mapping screen without applying.
  ///
  /// In en, this message translates to:
  /// **'I\'ll do this later'**
  String get pkMappingDoLater;

  /// Per-row option: import the PluralKit member as a brand-new local member.
  ///
  /// In en, this message translates to:
  /// **'Import as new'**
  String get pkMappingOptionImportNew;

  /// Per-row option: skip this PluralKit member (don't link, don't import).
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get pkMappingOptionSkip;

  /// Per-row option: link this PK member to an existing local member.
  ///
  /// In en, this message translates to:
  /// **'Link → {name}'**
  String pkMappingOptionLink(String name);

  /// Local-row option: push this local member up to PluralKit as a new PK member.
  ///
  /// In en, this message translates to:
  /// **'Push to PK'**
  String get pkMappingOptionPush;

  /// Local-row option: leave this local member unpushed.
  ///
  /// In en, this message translates to:
  /// **'Don\'t push'**
  String get pkMappingOptionDontPush;

  /// Summary line shown after applying PK mapping decisions. The 'cleared N unresolved links' clause is only included when unresolvedCleared > 0.
  ///
  /// In en, this message translates to:
  /// **'{linked} linked, {imported} imported, {pushed} pushed, {skipped} skipped, {failed} failed{unresolvedCleared, plural, =0{} other{, cleared {unresolvedCleared} unresolved links}}'**
  String pkMappingResultsSummary(
    int linked,
    int imported,
    int pushed,
    int skipped,
    int failed,
    int unresolvedCleared,
  );

  /// Muted caption shown under a local member in the PK-row link dropdown when the local carries stale PK fields (linked to a member not in the currently-paired PluralKit system). Linking will overwrite those stale fields.
  ///
  /// In en, this message translates to:
  /// **'Was linked to a PluralKit member no longer in this system'**
  String get pkMappingRowUnresolvedCandidateCaption;

  /// Caption shown under a PK member row when no local member is available to link to. Steers the user toward 'Import as new' or the future Manage screen.
  ///
  /// In en, this message translates to:
  /// **'No candidates — import as new or open Manage links to resolve'**
  String get pkMappingRowNoCandidatesCaption;

  /// Section-2 (Local members to push) caption shown under a local that carries unresolved PK fields and has been defaulted to Skip. Explains the asymmetric default and how to override.
  ///
  /// In en, this message translates to:
  /// **'Was linked to a PluralKit member no longer in this system. Defaulting to Skip — change to Push if you want to create a new PluralKit member.'**
  String get pkMappingSectionToPushUnresolvedCaption;

  /// Header above the per-row failure list in the PK mapping results card.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get pkMappingErrorsHeader;

  /// Semantics label for a PluralKit member row in the mapping list.
  ///
  /// In en, this message translates to:
  /// **'PluralKit member {name}'**
  String pkMappingPkMemberSemantics(String name);

  /// Semantics label for a local member row in the mapping list.
  ///
  /// In en, this message translates to:
  /// **'Local member {name}'**
  String pkMappingLocalMemberSemantics(String name);

  /// Failure-list verb describing a 'link' decision for the named PK member.
  ///
  /// In en, this message translates to:
  /// **'Link {name}'**
  String pkMappingDescribeLink(String name);

  /// Failure-list verb describing an 'import' decision for the named PK member.
  ///
  /// In en, this message translates to:
  /// **'Import {name}'**
  String pkMappingDescribeImport(String name);

  /// Failure-list verb describing a 'push to PK' decision for the local member id.
  ///
  /// In en, this message translates to:
  /// **'Push local {id}'**
  String pkMappingDescribePush(String id);

  /// Failure-list verb describing a 'skip' decision.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get pkMappingDescribeSkip;

  /// Lowercase fallback when a PK mapping failure has no error message.
  ///
  /// In en, this message translates to:
  /// **'unknown error'**
  String get pkMappingUnknownError;

  /// Top-bar title on the Manage PluralKit links screen.
  ///
  /// In en, this message translates to:
  /// **'Manage PluralKit links'**
  String get pkLinkManagementTitle;

  /// Title on the row in the PluralKit setup screen that navigates to the Manage PluralKit links screen.
  ///
  /// In en, this message translates to:
  /// **'Manage member links'**
  String get pkLinkManagementEntryRowTitle;

  /// Subtitle on the row in the PluralKit setup screen that navigates to the Manage PluralKit links screen.
  ///
  /// In en, this message translates to:
  /// **'Exclude or resume sync, fix unresolved links, or link an existing member.'**
  String get pkLinkManagementEntryRowSubtitle;

  /// Title on the row in the PluralKit setup screen that opens the mapping wizard for newly added members on either side.
  ///
  /// In en, this message translates to:
  /// **'Map new members'**
  String get pkMapNewMembersEntryRowTitle;

  /// Subtitle on the row in the PluralKit setup screen that opens the mapping wizard for newly added members on either side.
  ///
  /// In en, this message translates to:
  /// **'Import new PluralKit members or push new local members.'**
  String get pkMapNewMembersEntryRowSubtitle;

  /// Subtitle on the row in the PluralKit setup screen that opens the pk;export file import flow.
  ///
  /// In en, this message translates to:
  /// **'Restore switch history from a PluralKit data export.'**
  String get pkImportFromFileEntryRowSubtitle;

  /// Section header on the Manage PluralKit links screen for members whose PluralKit fields resolve in the current fetch and sync is active.
  ///
  /// In en, this message translates to:
  /// **'Synced with PluralKit'**
  String get pkLinkManagementSectionSynced;

  /// Section header on the Manage PluralKit links screen for members the user has excluded from PluralKit sync.
  ///
  /// In en, this message translates to:
  /// **'Excluded from sync'**
  String get pkLinkManagementSectionExcluded;

  /// Section header on the Manage PluralKit links screen for members whose stored PluralKit fields don't resolve against the current system.
  ///
  /// In en, this message translates to:
  /// **'Unresolved links'**
  String get pkLinkManagementSectionUnresolved;

  /// Action button on the Manage PluralKit links screen that excludes a member from PluralKit sync.
  ///
  /// In en, this message translates to:
  /// **'Exclude'**
  String get pkLinkManagementExclude;

  /// Action button on the Manage PluralKit links screen that resumes sync on an excluded member.
  ///
  /// In en, this message translates to:
  /// **'Resume sync'**
  String get pkLinkManagementResume;

  /// Action button on the Manage PluralKit links screen that opens a search to link a local member to a PluralKit member.
  ///
  /// In en, this message translates to:
  /// **'Link to PluralKit member…'**
  String get pkLinkManagementLinkAction;

  /// Action button on Synced rows of the Manage PluralKit links screen that opens a search to re-point a local member at a different PluralKit member.
  ///
  /// In en, this message translates to:
  /// **'Change link'**
  String get pkLinkManagementChangeLinkAction;

  /// Toast shown when the user taps Change link but every PluralKit member is already linked to another local.
  ///
  /// In en, this message translates to:
  /// **'No unmapped PluralKit members — exclude another link first.'**
  String get pkLinkManagementChangeLinkNoCandidatesCaption;

  /// Title of the confirmation dialog before overwriting a resolved PluralKit link on a Synced row.
  ///
  /// In en, this message translates to:
  /// **'Change PluralKit link for {localName}?'**
  String pkLinkManagementChangeLinkConfirmTitle(String localName);

  /// Body of the confirmation dialog before overwriting a resolved PluralKit link on a Synced row.
  ///
  /// In en, this message translates to:
  /// **'Currently linked to {currentPkName} ({currentPkId}). The new link will replace it. Switch history already imported from the old PluralKit member stays attributed to this {termSingularLower}.'**
  String pkLinkManagementChangeLinkConfirmMessage(
    String currentPkName,
    String currentPkId,
    String termSingularLower,
  );

  /// Destructive-confirm button label in the Change PluralKit link dialog.
  ///
  /// In en, this message translates to:
  /// **'Change link'**
  String get pkLinkManagementChangeLinkConfirmAction;

  /// Caption shown under members in the Unresolved section of the Manage PluralKit links screen.
  ///
  /// In en, this message translates to:
  /// **'Stored PK ID is no longer in your PluralKit system'**
  String get pkLinkManagementUnresolvedCaption;

  /// Caption shown at the top of the Manage PluralKit links screen when the user is not connected to PluralKit. Link actions are disabled in this state.
  ///
  /// In en, this message translates to:
  /// **'Connect to PluralKit to manage'**
  String get pkLinkManagementOfflineCaption;

  /// Caption shown on Synced section rows when the user is not connected to PluralKit.
  ///
  /// In en, this message translates to:
  /// **'Linked (offline)'**
  String get pkLinkManagementOfflineRowCaption;

  /// Caption shown at the top of the Manage PluralKit links screen when the user is connected to PluralKit but the most recent fetch failed (network error, server error). Refresh stays enabled in this state.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load PluralKit members. Tap Refresh to retry.'**
  String get pkLinkManagementFetchFailedCaption;

  /// Generic error toast when a Link decision from the Manage PluralKit links screen fails. The raw cause is logged via debugPrint; this user-facing message is intentionally generic to avoid surfacing English StateError text from the applier.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t link to {pkName}. The PluralKit member may already be linked to another local member, or PluralKit may be unreachable. Check Settings if this persists.'**
  String pkLinkManagementLinkFailed(String pkName);

  /// Top-of-screen action on the Manage PluralKit links screen that re-fetches members from PluralKit.
  ///
  /// In en, this message translates to:
  /// **'Refresh from PluralKit'**
  String get pkLinkManagementRefresh;

  /// Top-of-screen action on the Manage PluralKit links screen that opens a search over all local members to add a PluralKit link.
  ///
  /// In en, this message translates to:
  /// **'Add link to existing member'**
  String get pkLinkManagementAddLinkAction;

  /// Subtitle row label in the 'Add link to existing member' search for a local already linked to a resolved PluralKit member.
  ///
  /// In en, this message translates to:
  /// **'Linked to {pkName}'**
  String pkLinkManagementMemberStateLinked(String pkName);

  /// Subtitle row label in the 'Add link to existing member' search for a local that is excluded from sync but had been linked to a resolved PK member.
  ///
  /// In en, this message translates to:
  /// **'Excluded — was linked to {pkName}'**
  String pkLinkManagementMemberStateExcludedLinked(String pkName);

  /// Subtitle row label in the 'Add link to existing member' search for a local that is excluded from sync and has no PK fields.
  ///
  /// In en, this message translates to:
  /// **'Excluded — not linked'**
  String get pkLinkManagementMemberStateExcludedUnlinked;

  /// Subtitle row label in the 'Add link to existing member' search for a local whose PK fields don't resolve in the current PluralKit system.
  ///
  /// In en, this message translates to:
  /// **'Linked to {pkId} (not in current system)'**
  String pkLinkManagementMemberStateUnresolved(String pkId);

  /// Subtitle row label in the 'Add link to existing member' search for a local with no PK fields and not excluded.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get pkLinkManagementMemberStateNotLinked;

  /// Subtitle on the empty state of the Manage PluralKit links screen when there are no members in any of the three sections.
  ///
  /// In en, this message translates to:
  /// **'No members to manage yet.'**
  String get pkLinkManagementEmptyCount;

  /// Section header in the member editor sheet's Edit tab for the PluralKit link controls.
  ///
  /// In en, this message translates to:
  /// **'PluralKit'**
  String get memberEditorPluralKitSection;

  /// Summary line in the editor sheet's PluralKit section for a synced, resolved member.
  ///
  /// In en, this message translates to:
  /// **'Linked as {pkName}'**
  String memberEditorPluralKitLinkedAs(String pkName);

  /// Summary line in the editor sheet's PluralKit section for a non-excluded member whose PK fields don't resolve in the current PluralKit system.
  ///
  /// In en, this message translates to:
  /// **'Linked to {pkId} (not in your current PluralKit system)'**
  String memberEditorPluralKitLinkedToUnresolved(String pkId);

  /// Summary line in the editor sheet's PluralKit section for an excluded member whose PK fields resolve.
  ///
  /// In en, this message translates to:
  /// **'Excluded from sync — was linked as {pkName}'**
  String memberEditorPluralKitExcludedLinked(String pkName);

  /// Summary line in the editor sheet's PluralKit section for an excluded member whose PK fields don't resolve in the current PluralKit system.
  ///
  /// In en, this message translates to:
  /// **'Excluded from sync — was linked to {pkId} (not in current system)'**
  String memberEditorPluralKitExcludedUnresolved(String pkId);

  /// Summary line in the editor sheet's PluralKit section for an excluded member with no PK fields.
  ///
  /// In en, this message translates to:
  /// **'Excluded from sync — not linked'**
  String get memberEditorPluralKitExcludedUnlinked;

  /// Summary line in the editor sheet's PluralKit section for a non-excluded member without PK fields.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get memberEditorPluralKitNotLinked;

  /// Action button in the editor sheet's PluralKit section that excludes this member from PluralKit sync.
  ///
  /// In en, this message translates to:
  /// **'Exclude from PluralKit sync'**
  String get memberEditorPluralKitExcludeAction;

  /// Action button in the editor sheet's PluralKit section that resumes sync on this excluded member.
  ///
  /// In en, this message translates to:
  /// **'Resume PluralKit sync'**
  String get memberEditorPluralKitResumeAction;

  /// Action button in the editor sheet's PluralKit section that opens a search to link this member to a PluralKit member.
  ///
  /// In en, this message translates to:
  /// **'Link to PluralKit member…'**
  String get memberEditorPluralKitLinkAction;

  /// Top bar title on the Secret Key reveal screen during setup.
  ///
  /// In en, this message translates to:
  /// **'Your Secret Key'**
  String get secretKeyTitle;

  /// Top bar title shown when the Secret Key reveal screen is opened but the mnemonic has already been consumed/dismissed.
  ///
  /// In en, this message translates to:
  /// **'Secret Key Unavailable'**
  String get secretKeyUnavailableTitle;

  /// Headline body text on the Secret Key Unavailable screen.
  ///
  /// In en, this message translates to:
  /// **'This Secret Key is no longer available.'**
  String get secretKeyUnavailableMessage;

  /// Subtitle directing the user back to Sync settings.
  ///
  /// In en, this message translates to:
  /// **'Return to Sync settings and generate a new key if you still need to save it.'**
  String get secretKeyUnavailableHint;

  /// Button on the Secret Key Unavailable screen that returns to the Sync settings screen.
  ///
  /// In en, this message translates to:
  /// **'Back to Sync'**
  String get secretKeyBackToSync;

  /// Info banner above the Secret Key word list explaining where to store it.
  ///
  /// In en, this message translates to:
  /// **'Write these words down somewhere safe — a password manager, or paper kept offline. You\'ll need them to add new devices, change your PIN, or set up sync. There\'s no way to recover them if lost.'**
  String get secretKeyWriteDownInfo;

  /// Button that copies the Secret Key mnemonic to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get secretKeyCopyButton;

  /// Button that opens the share sheet with a formatted Secret Key backup file.
  ///
  /// In en, this message translates to:
  /// **'Save Backup'**
  String get secretKeySaveBackupButton;

  /// Button that reveals the Secret Key QR code for cross-device transfer.
  ///
  /// In en, this message translates to:
  /// **'Show QR Code'**
  String get secretKeyShowQrButton;

  /// Button that hides the Secret Key QR code.
  ///
  /// In en, this message translates to:
  /// **'Hide QR Code'**
  String get secretKeyHideQrButton;

  /// Caption under the Secret Key QR code explaining how to use it.
  ///
  /// In en, this message translates to:
  /// **'Scan from another device to transfer your Secret Key'**
  String get secretKeyQrInstructions;

  /// Checkbox the user must tick to acknowledge they've saved their Secret Key before continuing.
  ///
  /// In en, this message translates to:
  /// **'I have saved my Secret Key'**
  String get secretKeyHaveSavedCheckbox;

  /// Toast shown after the Secret Key is copied to the clipboard, noting the auto-clear timer.
  ///
  /// In en, this message translates to:
  /// **'Copied — clipboard will be cleared in 15 seconds'**
  String get secretKeyCopiedToast;

  /// Title of the warning dialog shown before sharing the Secret Key via the system share sheet.
  ///
  /// In en, this message translates to:
  /// **'Share Secret Key?'**
  String get secretKeyShareDialogTitle;

  /// Body of the Share Secret Key warning dialog.
  ///
  /// In en, this message translates to:
  /// **'You are about to share your 12-word Secret Key using the system share sheet.\n\nAnyone who receives this text — including cloud storage apps, messaging apps, or clipboard sync services — can use it to access your data.\n\nOnly share to a secure, private destination you control, such as a password manager or an encrypted notes app.'**
  String get secretKeyShareDialogMessage;

  /// Confirm button on the Share Secret Key warning dialog.
  ///
  /// In en, this message translates to:
  /// **'Share Anyway'**
  String get secretKeyShareConfirm;

  /// Email/share subject line on the exported Secret Key backup file.
  ///
  /// In en, this message translates to:
  /// **'Prism Secret Key Backup'**
  String get secretKeyBackupSubject;

  /// Body of the exported Secret Key backup text file shared via the system share sheet.
  ///
  /// In en, this message translates to:
  /// **'Prism Secret Key Backup\n========================\n\nYour Secret Key (12-word recovery phrase):\n\n{numberedWords}\n\nIMPORTANT:\n- Store this in a safe place — you will need it to set up new devices.\n- Anyone with this phrase AND your password can access your data.\n- Prism cannot recover this key if lost.\n\nGenerated: {date}\n'**
  String secretKeyBackupFileText(String numberedWords, String date);

  /// Title of the onboarding step that offers optional biometric enrollment.
  ///
  /// In en, this message translates to:
  /// **'Use biometrics to unlock Prism'**
  String get onboardingBiometricTitle;

  /// Body text on the onboarding biometric setup step.
  ///
  /// In en, this message translates to:
  /// **'Your encryption key will be protected by Face ID or Touch ID so only you can unlock Prism.'**
  String get onboardingBiometricDescription;

  /// Primary button on the onboarding biometric setup step.
  ///
  /// In en, this message translates to:
  /// **'Enable biometrics'**
  String get onboardingBiometricEnable;

  /// Secondary button that dismisses the biometric setup step.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get onboardingBiometricNotNow;

  /// Heading on the device-pairing fatal error view in onboarding.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed'**
  String get onboardingPairingFailed;

  /// Heading on the device-pairing snapshot-failure view in onboarding (pairing succeeded but snapshot bootstrap failed).
  ///
  /// In en, this message translates to:
  /// **'Pairing incomplete'**
  String get onboardingPairingIncomplete;

  /// Retry button on the device-pairing snapshot-failure view.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get onboardingPairingRetry;

  /// Destructive button that deregisters this device and aborts the pairing flow.
  ///
  /// In en, this message translates to:
  /// **'Cancel and remove this device'**
  String get onboardingPairingCancelAndRemove;

  /// Heading on the pairing error view when a leftover encrypted sync database from a previous install can't be opened with the new pairing key.
  ///
  /// In en, this message translates to:
  /// **'Leftover sync data found'**
  String get onboardingPairingStaleDataTitle;

  /// Explanatory body on the pairing error view telling the user that erasing leftover sync data is safe and keeps local content.
  ///
  /// In en, this message translates to:
  /// **'This device still has encrypted sync data from a previous install, and it can\'t be opened with this new pairing. Erasing it removes only that leftover sync data — your existing members and fronts on this device are kept — and lets you pair again.'**
  String get onboardingPairingStaleDataBody;

  /// Destructive button that deletes the leftover sync database and restarts the pairing flow.
  ///
  /// In en, this message translates to:
  /// **'Erase old sync data & retry'**
  String get onboardingPairingEraseAndRetry;

  /// Heading on the pairing error view when the automatic erase of leftover sync data failed (e.g. the file was locked).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove old sync data'**
  String get onboardingPairingStaleEraseFailedTitle;

  /// Explanatory body shown when erasing leftover sync data failed, telling the user how to recover manually.
  ///
  /// In en, this message translates to:
  /// **'The leftover sync data couldn\'t be removed automatically — the file may be locked. Make sure no other copy of the app is running, then try again. If it keeps failing, delete prism_sync.db from the app\'s data folder manually and reopen the app.'**
  String get onboardingPairingStaleEraseFailedBody;

  /// No description provided for @migrationAvatarZipTitle.
  ///
  /// In en, this message translates to:
  /// **'Avatar ZIP (optional)'**
  String get migrationAvatarZipTitle;

  /// No description provided for @migrationAvatarZipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import photos from the paired Simply Plural avatar ZIP.'**
  String get migrationAvatarZipSubtitle;

  /// No description provided for @migrationAvatarZipSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {fileName}'**
  String migrationAvatarZipSelected(Object fileName);

  /// No description provided for @migrationAvatarZipRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove avatar ZIP'**
  String get migrationAvatarZipRemove;

  /// No description provided for @migrationResultAvatarZipImported.
  ///
  /// In en, this message translates to:
  /// **'Avatar ZIP images imported'**
  String get migrationResultAvatarZipImported;

  /// No description provided for @onboardingSimplyPluralAddAvatarZip.
  ///
  /// In en, this message translates to:
  /// **'Add Avatar ZIP (optional)'**
  String get onboardingSimplyPluralAddAvatarZip;

  /// No description provided for @onboardingSimplyPluralChangeAvatarZip.
  ///
  /// In en, this message translates to:
  /// **'Change Avatar ZIP'**
  String get onboardingSimplyPluralChangeAvatarZip;

  /// No description provided for @onboardingSimplyPluralRemoveAvatarZip.
  ///
  /// In en, this message translates to:
  /// **'Remove Avatar ZIP'**
  String get onboardingSimplyPluralRemoveAvatarZip;

  /// No description provided for @onboardingSimplyPluralAvatarZipSelected.
  ///
  /// In en, this message translates to:
  /// **'Avatar ZIP: {fileName}'**
  String onboardingSimplyPluralAvatarZipSelected(Object fileName);

  /// No description provided for @dataManagementSimplyPluralAvatarZipRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Simply Plural Avatar ZIP'**
  String get dataManagementSimplyPluralAvatarZipRowTitle;

  /// No description provided for @dataManagementSimplyPluralAvatarZipRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update photos for existing imported members'**
  String get dataManagementSimplyPluralAvatarZipRowSubtitle;

  /// Title for SP creation date backfill row in import/export settings
  ///
  /// In en, this message translates to:
  /// **'Update creation dates'**
  String get dataManagementSpCreationDateRowTitle;

  /// Subtitle for SP creation date backfill row
  ///
  /// In en, this message translates to:
  /// **'Import original creation dates from a Simply Plural export'**
  String get dataManagementSpCreationDateRowSubtitle;

  /// No description provided for @spAvatarZipSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Simply Plural Avatar ZIP'**
  String get spAvatarZipSheetTitle;

  /// No description provided for @spAvatarZipUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update photos from ZIP'**
  String get spAvatarZipUpdateTitle;

  /// No description provided for @spAvatarZipDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the avatar ZIP exported by Simply Plural. Prism will match images to existing imported members and update only their photos.'**
  String get spAvatarZipDescription;

  /// No description provided for @spAvatarZipSelect.
  ///
  /// In en, this message translates to:
  /// **'Select Avatar ZIP'**
  String get spAvatarZipSelect;

  /// No description provided for @spAvatarZipImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing avatar ZIP...'**
  String get spAvatarZipImporting;

  /// No description provided for @spAvatarZipImportingDescription.
  ///
  /// In en, this message translates to:
  /// **'Matching ZIP images to existing Simply Plural imports.'**
  String get spAvatarZipImportingDescription;

  /// Commit-aware avatar ZIP import progress
  ///
  /// In en, this message translates to:
  /// **'Processed {processed} of {total} matching photos'**
  String spAvatarZipProgress(int processed, int total);

  /// No description provided for @spAvatarZipNoMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching photos found'**
  String get spAvatarZipNoMatchesTitle;

  /// No description provided for @spAvatarZipCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos updated'**
  String get spAvatarZipCompleteTitle;

  /// No description provided for @spAvatarZipPartialTitle.
  ///
  /// In en, this message translates to:
  /// **'Some photos need attention'**
  String get spAvatarZipPartialTitle;

  /// No description provided for @spAvatarZipPartialMessage.
  ///
  /// In en, this message translates to:
  /// **'Prism saved every photo it could. Review the details below or retry the ZIP.'**
  String get spAvatarZipPartialMessage;

  /// No description provided for @spAvatarZipNoMatchesMessage.
  ///
  /// In en, this message translates to:
  /// **'Run the Simply Plural JSON import first, then try this ZIP again.'**
  String get spAvatarZipNoMatchesMessage;

  /// No description provided for @spAvatarZipUpdatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} member photo(s).'**
  String spAvatarZipUpdatedMessage(Object count);

  /// No description provided for @spAvatarZipImagesFound.
  ///
  /// In en, this message translates to:
  /// **'Images found'**
  String get spAvatarZipImagesFound;

  /// No description provided for @spAvatarZipMemberPhotosUpdated.
  ///
  /// In en, this message translates to:
  /// **'Member photos updated'**
  String get spAvatarZipMemberPhotosUpdated;

  /// No description provided for @spAvatarZipSystemPhotoUpdated.
  ///
  /// In en, this message translates to:
  /// **'System photo updated'**
  String get spAvatarZipSystemPhotoUpdated;

  /// No description provided for @spAvatarZipUnmatchedImages.
  ///
  /// In en, this message translates to:
  /// **'Unmatched images'**
  String get spAvatarZipUnmatchedImages;

  /// No description provided for @spAvatarZipFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not import avatar ZIP'**
  String get spAvatarZipFailedTitle;

  /// Title of the creation date backfill sheet
  ///
  /// In en, this message translates to:
  /// **'Update Creation Dates'**
  String get spCreationDateBackfillTitle;

  /// Description text in the backfill sheet
  ///
  /// In en, this message translates to:
  /// **'Simply Plural stores when each member was first created. This updates your Prism members with those original dates.'**
  String get spCreationDateBackfillDescription;

  /// Button label for selecting a Simply Plural JSON export in the creation date backfill sheet
  ///
  /// In en, this message translates to:
  /// **'Select SP JSON'**
  String get spCreationDateBackfillSelectJson;

  /// Loading label while the creation date backfill sheet reads a Simply Plural JSON export
  ///
  /// In en, this message translates to:
  /// **'Reading SP JSON...'**
  String get spCreationDateBackfillReadingJson;

  /// Message when no SP import history exists
  ///
  /// In en, this message translates to:
  /// **'No Simply Plural import history found. Import your SP data first to set up member links.'**
  String get spCreationDateBackfillNoMapping;

  /// Message when no members matched in backfill
  ///
  /// In en, this message translates to:
  /// **'None of the members in this export matched your current members.'**
  String get spCreationDateBackfillNoMatches;

  /// Title above the preview list in backfill sheet
  ///
  /// In en, this message translates to:
  /// **'Preview changes'**
  String get spCreationDateBackfillPreviewTitle;

  /// Button label to apply the backfill
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get spCreationDateBackfillApply;

  /// Success message after backfill
  ///
  /// In en, this message translates to:
  /// **'Updated creation dates for {count} members.'**
  String spCreationDateBackfillSuccess(int count);

  /// Label showing current creation date in preview
  ///
  /// In en, this message translates to:
  /// **'Current: {date}'**
  String spCreationDateBackfillCurrent(String date);

  /// Label showing new creation date in preview
  ///
  /// In en, this message translates to:
  /// **'New: {date}'**
  String spCreationDateBackfillNew(String date);

  /// Message showing count of unmatched members in backfill
  ///
  /// In en, this message translates to:
  /// **'{count} members could not be matched'**
  String spCreationDateBackfillUnmatched(int count);

  /// Heading shown above the grouped SP import warning summary. Leads with reassurance.
  ///
  /// In en, this message translates to:
  /// **'Your data is in.'**
  String get spImportWarningsTitle;

  /// Subtitle shown below the title on the grouped SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Here’s what to know:'**
  String get spImportWarningsSubtitle;

  /// Button label to expand a warning category beyond the first 10 items.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Show 1 more} other{Show all {count} more}}'**
  String spImportWarningsShowAll(int count);

  /// Button label to retry avatar downloads on the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get spImportWarningsRetry;

  /// Button label shown while avatar downloads are being retried.
  ///
  /// In en, this message translates to:
  /// **'Retrying…'**
  String get spImportWarningsRetrying;

  /// Accessibility label for the warning count chip on a category tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 warning in this category} other{{count} warnings in this category}}'**
  String spImportWarningsCountSemantics(int count);

  /// Category headline for avatar download failures in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Avatar downloads'**
  String get spImportWarningsAvatarsHeadline;

  /// Plain-language explanation for avatar download failures in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Simply Plural is shutting down and these URLs no longer load. Pair this import with an avatar ZIP export to keep the pixels.'**
  String get spImportWarningsAvatarsExplanation;

  /// Category headline for missing-reference warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Sessions missing a member'**
  String get spImportWarningsMissingReferencesHeadline;

  /// Plain-language explanation for missing-reference warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'These imported fine — they just don’t have a member attached, because that member was deleted in Simply Plural before the export.'**
  String get spImportWarningsMissingReferencesExplanation;

  /// Category headline for custom-front adjustment warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Custom front adjustments'**
  String get spImportWarningsCustomFrontAdjustmentsHeadline;

  /// Plain-language explanation for custom-front adjustment warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Some sleep sessions were clamped or merged, or custom fronts were handled as notes.'**
  String get spImportWarningsCustomFrontAdjustmentsExplanation;

  /// Category headline for encrypted message warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Encrypted chat messages'**
  String get spImportWarningsEncryptedMessagesHeadline;

  /// Plain-language explanation for encrypted message warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Some chat messages were still encrypted in this export and couldn’t be imported.'**
  String get spImportWarningsEncryptedMessagesExplanation;

  /// Category headline for data-quality warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Data quality drops'**
  String get spImportWarningsDataQualityHeadline;

  /// Plain-language explanation for data-quality warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Some records were missing required fields in the source export and were skipped.'**
  String get spImportWarningsDataQualityExplanation;

  /// Category headline for sync-emission warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Sync emissions'**
  String get spImportWarningsSyncEmissionHeadline;

  /// Plain-language explanation for sync-emission warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Some imported entries didn’t sync to other devices automatically. Local data is correct; peers may be missing these until you edit them or re-run sync.'**
  String get spImportWarningsSyncEmissionExplanation;

  /// Category headline for unclassified warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get spImportWarningsOtherHeadline;

  /// Plain-language explanation for unclassified warnings in the SP import warning summary.
  ///
  /// In en, this message translates to:
  /// **'These warnings don’t match a known category. If anything looks unexpected, send them to support.'**
  String get spImportWarningsOtherExplanation;

  /// Title of the banner shown on the fronting screen when local Prism members exist that haven't been pushed to PluralKit.
  ///
  /// In en, this message translates to:
  /// **'Local members not on PluralKit'**
  String get pkUnpushedMembersBannerTitle;

  /// Body of the unpushed-members banner when exactly one local member is missing from PluralKit.
  ///
  /// In en, this message translates to:
  /// **'1 Prism member isn\'t on PluralKit yet.'**
  String get pkUnpushedMembersBannerMessageOne;

  /// Body of the unpushed-members banner when more than one local member is missing from PluralKit.
  ///
  /// In en, this message translates to:
  /// **'{count} Prism members aren\'t on PluralKit yet.'**
  String pkUnpushedMembersBannerMessageMany(int count);

  /// Title of the sheet that lists local Prism members that aren't on PluralKit yet.
  ///
  /// In en, this message translates to:
  /// **'Review local-only members'**
  String get pkUnpushedMembersReviewSheetTitle;

  /// Intro paragraph explaining the local-only member review sheet.
  ///
  /// In en, this message translates to:
  /// **'These members live only in Prism while push is off. Push them now without changing your sync settings.'**
  String get pkUnpushedMembersReviewIntro;

  /// Per-row action button to push a single local member to PluralKit without enabling general push sync.
  ///
  /// In en, this message translates to:
  /// **'Push once'**
  String get pkUnpushedMembersRowPushOnce;

  /// Per-row action button to mark a local member as durably Prism-only (sets pluralkitSyncIgnored).
  ///
  /// In en, this message translates to:
  /// **'Keep local'**
  String get pkUnpushedMembersRowKeepLocal;

  /// Bottom-of-sheet action that hides the local-only members banner until the cohort of unpushed members changes.
  ///
  /// In en, this message translates to:
  /// **'Dismiss for now'**
  String get pkUnpushedMembersDismissForNow;

  /// Title of the dialog shown immediately after creating a new local member when PluralKit is paired but push is disabled.
  ///
  /// In en, this message translates to:
  /// **'Push {name} to PluralKit?'**
  String pkPushNewMemberDialogTitle(String name);

  /// Body text of the push-on-create dialog explaining the one-time push escape hatch.
  ///
  /// In en, this message translates to:
  /// **'Push is off, so {name} and their sessions stay Prism-only. One-time push syncs them now without changing your sync settings.'**
  String pkPushNewMemberDialogBody(String name);

  /// Primary action button on the push-on-create dialog that triggers a one-shot push of the newly-created member.
  ///
  /// In en, this message translates to:
  /// **'Push once'**
  String get pkPushNewMemberDialogConfirm;

  /// Secondary action button on the push-on-create dialog that durably marks the new member as Prism-only.
  ///
  /// In en, this message translates to:
  /// **'Keep local'**
  String get pkPushNewMemberDialogKeepLocal;

  /// Success toast shown after a one-shot push of a newly-created member completes.
  ///
  /// In en, this message translates to:
  /// **'{name} pushed to PluralKit.'**
  String pkPushNewMemberDialogSuccess(String name);

  /// Error toast shown when a one-shot push of a newly-created member fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t push {name} to PluralKit: {error}'**
  String pkPushNewMemberDialogError(String name, String error);

  /// Settings row title for the Verify Saved Backup feature
  ///
  /// In en, this message translates to:
  /// **'Verify saved backup'**
  String get verifyBackupRowTitle;

  /// Settings row subtitle for the Verify Saved Backup feature
  ///
  /// In en, this message translates to:
  /// **'Check saved words match this install'**
  String get verifyBackupRowSubtitle;

  /// Screen title for the Verify Saved Backup screen
  ///
  /// In en, this message translates to:
  /// **'Verify saved backup'**
  String get verifyBackupScreenTitle;

  /// Step indicator label for the phrase entry step
  ///
  /// In en, this message translates to:
  /// **'Phrase'**
  String get verifyBackupStepPhrase;

  /// Step indicator label for the PIN entry step
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get verifyBackupStepPin;

  /// Step indicator label for the result step
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get verifyBackupStepResult;

  /// Accessible label for the step indicator on the Verify Saved Backup screen
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 3: {name}'**
  String verifyBackupStepIndicatorLabel(int step, String name);

  /// Headline shown when the backup phrase and PIN match
  ///
  /// In en, this message translates to:
  /// **'These words unlock this device'**
  String get verifyBackupMatchHeadline;

  /// Body text shown when the backup phrase and PIN match
  ///
  /// In en, this message translates to:
  /// **'Save this QR to skip typing next time.'**
  String get verifyBackupMatchBody;

  /// Caption showing the verification date
  ///
  /// In en, this message translates to:
  /// **'Verified {date}'**
  String verifyBackupVerifiedOn(String date);

  /// Headline shown when the backup phrase and PIN do not match
  ///
  /// In en, this message translates to:
  /// **'That didn\'t match'**
  String get verifyBackupNoMatchHeadline;

  /// Body text shown when the backup phrase and PIN do not match
  ///
  /// In en, this message translates to:
  /// **'Try another saved backup, or double-check the PIN. Older installs have different phrases.'**
  String get verifyBackupNoMatchBody;

  /// Button label to try a different backup phrase
  ///
  /// In en, this message translates to:
  /// **'Try a different backup'**
  String get verifyBackupTryDifferentBackup;

  /// Button label to re-enter the PIN
  ///
  /// In en, this message translates to:
  /// **'Re-enter PIN'**
  String get verifyBackupReenterPin;

  /// Button label to share the QR code
  ///
  /// In en, this message translates to:
  /// **'Share QR'**
  String get verifyBackupShareQrButton;

  /// Done button label on the verify backup result screen
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get verifyBackupDoneButton;

  /// Banner shown when the device is locked
  ///
  /// In en, this message translates to:
  /// **'Your device is locked — unlock it first'**
  String get verifyBackupLockedBanner;

  /// Button label to unlock the device
  ///
  /// In en, this message translates to:
  /// **'Unlock device'**
  String get verifyBackupUnlockButton;

  /// Banner shown when the runtime DEK restore is deferred
  ///
  /// In en, this message translates to:
  /// **'Sync access needs to be restored'**
  String get verifyBackupRuntimeDeferredBanner;

  /// Banner shown while waiting for device unlock (Android Keystore)
  ///
  /// In en, this message translates to:
  /// **'Unlock your device to continue'**
  String get verifyBackupAwaitingUnlockBanner;

  /// Banner shown when the wrapped DEK needs to be re-wrapped
  ///
  /// In en, this message translates to:
  /// **'Your backup needs to be re-secured'**
  String get verifyBackupNeedsRewrapBanner;

  /// Button label to trigger the re-wrap flow
  ///
  /// In en, this message translates to:
  /// **'Re-secure backup'**
  String get verifyBackupNeedsRewrapButton;

  /// Empty state message when there is no active install
  ///
  /// In en, this message translates to:
  /// **'No active install to verify against.'**
  String get verifyBackupNoActiveInstall;

  /// Button label to scan a QR code containing the backup phrase
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get verifyBackupScanQrButton;

  /// Error shown when a scanned QR does not contain a valid BIP39 phrase
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read this QR — try typing the words instead'**
  String get verifyBackupScanInvalid;

  /// Subtitle shown while validating the mnemonic and PIN
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get verifyBackupValidating;

  /// Accessible label for the QR code on the match result screen
  ///
  /// In en, this message translates to:
  /// **'QR code containing your recovery phrase'**
  String get verifyBackupNoQrSemanticLabel;

  /// Live-region accessible label announced when the backup matches
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verifyBackupSrAnnounceMatch;

  /// Live-region accessible label announced when the backup does not match
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get verifyBackupSrAnnounceNoMatch;

  /// Label for the group custom field type (shown in settings list subtitle)
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get customFieldTypeGroup;

  /// Button label shown inside an empty group editor to add the first child field
  ///
  /// In en, this message translates to:
  /// **'Add field to this group'**
  String get customFieldGroupAddChildButton;

  /// Sheet title when creating a new field nested inside a group
  ///
  /// In en, this message translates to:
  /// **'Add field to group'**
  String get customFieldGroupNewChildTitle;

  /// Title of the delete-group confirm dialog
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String customFieldGroupDeleteTitle(String name);

  /// Body of the delete-group confirm dialog explaining the choice for child fields
  ///
  /// In en, this message translates to:
  /// **'What should happen to the fields inside this group?'**
  String get customFieldGroupDeleteMessage;

  /// Action button in the delete-group dialog that promotes child fields to top level instead of deleting them
  ///
  /// In en, this message translates to:
  /// **'Promote to top level'**
  String get customFieldGroupPromoteChildren;

  /// Action button in the delete-group dialog that deletes all child fields along with the group
  ///
  /// In en, this message translates to:
  /// **'Delete them too'**
  String get customFieldGroupDeleteChildren;

  /// Toggle label in the group editor sheet that controls whether the group's name renders as a header on member profiles
  ///
  /// In en, this message translates to:
  /// **'Show title on profiles'**
  String get customFieldGroupShowTitleLabel;

  /// Sub-label under the show-title toggle explaining what hiding the title means
  ///
  /// In en, this message translates to:
  /// **'Hide to use the group as a visual container only.'**
  String get customFieldGroupShowTitleSubtitle;

  /// Toggle label in the field editor sheet (all field types) that controls whether the field's label renders next to its value on member profiles
  ///
  /// In en, this message translates to:
  /// **'Show title on profiles'**
  String get customFieldShowTitleLabel;

  /// Sub-label under the show-title toggle for any custom field type, explaining what hiding the title means
  ///
  /// In en, this message translates to:
  /// **'Hide to render the value without a label.'**
  String get customFieldShowTitleSubtitle;

  /// Small section header in the field editor sheet above presentation options like the show-title toggle
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get customFieldDisplaySectionHeader;

  /// Small heading above the segmented control that chooses how a custom field group appears on member profiles
  ///
  /// In en, this message translates to:
  /// **'Profile display'**
  String get customFieldGroupProfileDisplayHeading;

  /// Segment label for rendering a custom field group inline on the member profile
  ///
  /// In en, this message translates to:
  /// **'Inline'**
  String get customFieldGroupProfileDisplayInline;

  /// Segment label for rendering a custom field group as an expandable/collapsible section on the member profile
  ///
  /// In en, this message translates to:
  /// **'Collapsible'**
  String get customFieldGroupProfileDisplayCollapsible;

  /// Segment label for rendering a custom field group as a row that opens a separate member profile page
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get customFieldGroupProfileDisplayPage;

  /// Small heading above the segmented control that chooses whether a collapsible custom field group starts open, closed, or remembered
  ///
  /// In en, this message translates to:
  /// **'Default state'**
  String get customFieldGroupCollapseDefaultHeading;

  /// Segment label for making a collapsible custom field group start open
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get customFieldGroupCollapseDefaultOpen;

  /// Segment label for making a collapsible custom field group start closed
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get customFieldGroupCollapseDefaultClosed;

  /// Segment label for making a collapsible custom field group remember its last open or closed state
  ///
  /// In en, this message translates to:
  /// **'Last state'**
  String get customFieldGroupCollapseDefaultLastState;

  /// Label for the custom field header icon picker in the field editor sheet
  ///
  /// In en, this message translates to:
  /// **'Header icon'**
  String get customFieldHeaderIconLabel;

  /// Subtitle explaining where a custom field header icon appears
  ///
  /// In en, this message translates to:
  /// **'Shown beside the field in settings and profiles.'**
  String get customFieldHeaderIconSubtitle;

  /// Fallback label for a group whose name is empty; shown in the settings list and on the detail screen so users can still find/edit it
  ///
  /// In en, this message translates to:
  /// **'Untitled group'**
  String get customFieldGroupUntitledFallback;

  /// Section heading on the group detail screen for the list of child fields
  ///
  /// In en, this message translates to:
  /// **'Fields in this group'**
  String get customFieldGroupChildrenHeading;

  /// Count line under the group children heading on the detail screen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No fields yet} =1{1 field} other{{count} fields}}'**
  String customFieldGroupChildrenCount(int count);

  /// Short label for the CTA that adds a new field to the group, used on the detail screen
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get customFieldGroupAddChildButtonShort;

  /// Empty-state title shown on the group detail screen when the group has no child fields
  ///
  /// In en, this message translates to:
  /// **'No fields yet'**
  String get customFieldGroupChildrenEmptyTitle;

  /// Empty-state subtitle shown on the group detail screen when the group has no child fields
  ///
  /// In en, this message translates to:
  /// **'Add fields to organize related details together.'**
  String get customFieldGroupChildrenEmptySubtitle;

  /// Label for the Scale custom field type in the type picker
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get customFieldTypeScale;

  /// Section heading for the emoji picker in scale field config
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get customFieldScaleEmojiHeading;

  /// Section heading for the steps slider in scale field config
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get customFieldScaleStepsHeading;

  /// Deprecated; replaced by customFieldScaleCustomEmoji.
  ///
  /// In en, this message translates to:
  /// **'Advanced: any emoji'**
  String get customFieldScaleAdvancedEmoji;

  /// Tooltip/label for the custom-emoji button that lets users type any emoji.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customFieldScaleCustomEmoji;

  /// Hint text for the custom emoji text field in scale field config
  ///
  /// In en, this message translates to:
  /// **'Type or paste an emoji'**
  String get customFieldScaleCustomEmojiHint;

  /// Live label showing the current number of steps in the scale steps slider
  ///
  /// In en, this message translates to:
  /// **'{count} steps'**
  String customFieldScaleStepsHelpFew(int count);

  /// Soft warning shown below the steps slider when steps > 7
  ///
  /// In en, this message translates to:
  /// **'Larger scales may be cramped on small screens'**
  String get customFieldScaleStepsHelpMany;

  /// Section heading for the scale field layout choice (auto/compact/stacked) in field settings
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get customFieldScaleLayoutHeading;

  /// Layout choice meaning 'use the type-aware default' (currently compact for scale)
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get customFieldScaleLayoutAuto;

  /// Layout choice: label-left, emojis-right on one row
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get customFieldScaleLayoutCompact;

  /// Layout choice: label above, emojis on their own row below
  ///
  /// In en, this message translates to:
  /// **'Stacked'**
  String get customFieldScaleLayoutStacked;

  /// Soft suggestion shown below the layout chooser when steps > 5 and layout is not stacked
  ///
  /// In en, this message translates to:
  /// **'Stacked layout reads better with this many steps'**
  String get customFieldScaleLayoutSuggestStacked;

  /// Tooltip for the × clear button in the scale field editor
  ///
  /// In en, this message translates to:
  /// **'Clear rating'**
  String get customFieldScaleClearTooltip;

  /// Screen-reader announcement spoken when the scale rating is cleared via long-press
  ///
  /// In en, this message translates to:
  /// **'Cleared rating'**
  String get customFieldScaleClearedAnnouncement;

  /// Accessibility label for the scale emoji row, describing the current rating
  ///
  /// In en, this message translates to:
  /// **'{name}: {step} of {total}'**
  String customFieldScaleSemanticLabel(String name, int step, int total);

  /// Label for the Slider custom field type in the type picker
  ///
  /// In en, this message translates to:
  /// **'Slider'**
  String get customFieldTypeSlider;

  /// Label for the Member custom field type in the type picker
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get customFieldTypeMember;

  /// Section heading for the member field layout choice (auto/compact/stacked) in field settings
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get customFieldMemberLayoutHeading;

  /// Layout choice meaning 'use the type-aware default' (currently compact for member fields)
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get customFieldMemberLayoutAuto;

  /// Layout choice: label-left, member chips-right on one row
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get customFieldMemberLayoutCompact;

  /// Layout choice: label above, member chips on their own row below
  ///
  /// In en, this message translates to:
  /// **'Stacked'**
  String get customFieldMemberLayoutStacked;

  /// Semantics label for a selected member custom field chip
  ///
  /// In en, this message translates to:
  /// **'{fieldName}, {memberName}, selected member'**
  String customFieldMemberSelectedSemantic(String fieldName, String memberName);

  /// Tooltip and semantics label for removing a selected member custom field chip
  ///
  /// In en, this message translates to:
  /// **'Remove {memberName}'**
  String customFieldMemberRemoveMember(String memberName);

  /// Placeholder label for a member custom field that references its owner
  ///
  /// In en, this message translates to:
  /// **'Self reference'**
  String get customFieldMemberSelfReference;

  /// Placeholder label for a member custom field reference that cannot be resolved
  ///
  /// In en, this message translates to:
  /// **'Unavailable member'**
  String get customFieldMemberUnavailable;

  /// Semantics label for a member custom field placeholder chip
  ///
  /// In en, this message translates to:
  /// **'{fieldName}, {label}'**
  String customFieldMemberChipSemantic(String fieldName, String label);

  /// Tooltip and semantics label for removing a member custom field placeholder chip
  ///
  /// In en, this message translates to:
  /// **'Remove {label}'**
  String customFieldMemberRemoveSelection(String label);

  /// Summary label for a member custom field value that references the owner member
  ///
  /// In en, this message translates to:
  /// **'Self ({memberName})'**
  String customFieldMemberSelfReferenceWithName(String memberName);

  /// Section heading for the slider mode chooser (labeled vs numeric)
  ///
  /// In en, this message translates to:
  /// **'Slider type'**
  String get customFieldSliderModeHeading;

  /// Label for the labeled slider mode card
  ///
  /// In en, this message translates to:
  /// **'Mood / Intensity'**
  String get customFieldSliderModeLabeled;

  /// Description text on the labeled slider mode card
  ///
  /// In en, this message translates to:
  /// **'A spectrum with named endpoints.'**
  String get customFieldSliderModeLabeledDescription;

  /// Label for the numeric slider mode card
  ///
  /// In en, this message translates to:
  /// **'Measurement'**
  String get customFieldSliderModeNumeric;

  /// Description text on the numeric slider mode card
  ///
  /// In en, this message translates to:
  /// **'A scale with numbers you can define.'**
  String get customFieldSliderModeNumericDescription;

  /// Notice shown in edit mode explaining the slider mode cannot be changed
  ///
  /// In en, this message translates to:
  /// **'Slider type is fixed once the field is created.'**
  String get customFieldSliderModeLockNotice;

  /// Label for the left anchor text field in labeled slider config
  ///
  /// In en, this message translates to:
  /// **'Left label (optional)'**
  String get customFieldSliderLeftLabel;

  /// Label for the right anchor text field in labeled slider config
  ///
  /// In en, this message translates to:
  /// **'Right label (optional)'**
  String get customFieldSliderRightLabel;

  /// Label for the center anchor text field in labeled slider config; when set, adds a center snap position
  ///
  /// In en, this message translates to:
  /// **'Center label (optional)'**
  String get customFieldSliderCenterLabel;

  /// Section heading for the gradient preset picker in labeled slider config
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get customFieldSliderGradientHeading;

  /// Deprecated; replaced by customFieldSliderCustomGradient.
  ///
  /// In en, this message translates to:
  /// **'Advanced: custom colors'**
  String get customFieldSliderAdvancedColors;

  /// Chip label that selects custom per-anchor colors instead of a gradient preset.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customFieldSliderCustomGradient;

  /// Title of the color picker dialog for a slider anchor (left/center/right).
  ///
  /// In en, this message translates to:
  /// **'Pick a color'**
  String get customFieldSliderColorAnchorTitle;

  /// Tooltip / label for the add-color button in the custom gradient swatch row.
  ///
  /// In en, this message translates to:
  /// **'Add color'**
  String get customFieldSliderAddColor;

  /// Tooltip / label for the remove-color action in the custom gradient swatch row.
  ///
  /// In en, this message translates to:
  /// **'Remove color'**
  String get customFieldSliderRemoveColor;

  /// Accessible action label to move a gradient swatch one position to the left.
  ///
  /// In en, this message translates to:
  /// **'Move left'**
  String get customFieldSliderMoveLeft;

  /// Accessible action label to move a gradient swatch one position to the right.
  ///
  /// In en, this message translates to:
  /// **'Move right'**
  String get customFieldSliderMoveRight;

  /// Accessible label for the drag handle below a gradient color swatch.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder color'**
  String get customFieldSliderReorderHandle;

  /// Semantic label for a gradient color swatch, e.g. for screen readers.
  ///
  /// In en, this message translates to:
  /// **'Gradient color {index} of {total}, {hex}'**
  String customFieldSliderGradientColorSemantics(
    int index,
    int total,
    String hex,
  );

  /// Default title for the shared color picker dialog (choice options, color field).
  ///
  /// In en, this message translates to:
  /// **'Pick a color'**
  String get customFieldColorPickerTitle;

  /// Tooltip for the insert-table button in long-text editors.
  ///
  /// In en, this message translates to:
  /// **'Insert table'**
  String get tableInsertTooltip;

  /// Title of the insert-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Insert table'**
  String get tableInsertTitle;

  /// Confirm button label in the insert-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get tableInsertConfirm;

  /// Label for the column-count stepper in the insert-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get tableColumnsLabel;

  /// Label for the row-count stepper in the insert-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get tableRowsLabel;

  /// Tooltip for the decrement-columns button.
  ///
  /// In en, this message translates to:
  /// **'Remove column'**
  String get tableRemoveColumn;

  /// Tooltip for the increment-columns button.
  ///
  /// In en, this message translates to:
  /// **'Add column'**
  String get tableAddColumn;

  /// Tooltip for the decrement-rows button.
  ///
  /// In en, this message translates to:
  /// **'Remove row'**
  String get tableRemoveRow;

  /// Tooltip for the increment-rows button.
  ///
  /// In en, this message translates to:
  /// **'Add row'**
  String get tableAddRow;

  /// Label for the show-borders toggle in the insert-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Show borders'**
  String get tableShowBordersLabel;

  /// Label for the border-color picker row in the insert-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Border color'**
  String get tableBorderColorLabel;

  /// Value shown when the table border uses the theme default color.
  ///
  /// In en, this message translates to:
  /// **'Theme default'**
  String get tableBorderColorDefault;

  /// Label for the header-row toggle in the insert-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Header row'**
  String get tableHeaderRowLabel;

  /// Subtitle explaining the header-row toggle.
  ///
  /// In en, this message translates to:
  /// **'First row is column headings'**
  String get tableHeaderRowSubtitle;

  /// Hint shown when a header row is enabled on a borderless table.
  ///
  /// In en, this message translates to:
  /// **'Without borders the header row looks the same as other rows.'**
  String get tableHeaderRowPlainHint;

  /// Toggle label for snap-to-positions in labeled slider config
  ///
  /// In en, this message translates to:
  /// **'Snap to positions'**
  String get customFieldSliderSnapToPositions;

  /// Label for the minimum value text field in numeric slider config
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get customFieldSliderMin;

  /// Label for the maximum value text field in numeric slider config
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get customFieldSliderMax;

  /// Label for the step size text field in numeric slider config
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get customFieldSliderStep;

  /// Label for the unit suffix text field in numeric slider config
  ///
  /// In en, this message translates to:
  /// **'Unit (optional)'**
  String get customFieldSliderUnit;

  /// Toggle label for showing tick marks in numeric slider config
  ///
  /// In en, this message translates to:
  /// **'Show tick marks'**
  String get customFieldSliderShowTicks;

  /// Value indicator pill text for labeled slider mode, shown above the thumb
  ///
  /// In en, this message translates to:
  /// **'Closer to {anchor}, {percent}%'**
  String customFieldSliderValueLabel(String anchor, int percent);

  /// Value indicator pill text when the thumb is exactly on the center anchor in labeled slider mode
  ///
  /// In en, this message translates to:
  /// **'{anchor}, {percent}%'**
  String customFieldSliderValueLabelCentered(String anchor, int percent);

  /// Value indicator pill text for numeric slider mode; unit may be empty
  ///
  /// In en, this message translates to:
  /// **'{value}{unit}'**
  String customFieldSliderNumericValueLabel(String value, String unit);

  /// Screen-reader label for numeric slider mode
  ///
  /// In en, this message translates to:
  /// **'{name}, {value} {unit}'**
  String customFieldSliderSemanticLabel(String name, String value, String unit);

  /// Screen-reader label for labeled slider mode; description is the pill text
  ///
  /// In en, this message translates to:
  /// **'{name}, {description}'**
  String customFieldSliderSemanticLabelLabeled(String name, String description);

  /// Category heading for identity gradient presets
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get customFieldSliderCategoryIdentity;

  /// Category heading for mood/intensity gradient presets
  ///
  /// In en, this message translates to:
  /// **'Mood / Intensity'**
  String get customFieldSliderCategoryMoodIntensity;

  /// Category heading for temperature gradient presets
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get customFieldSliderCategoryTemperature;

  /// Category heading for neutral gradient presets
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get customFieldSliderCategoryNeutral;

  /// Category heading for palette gradient presets
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get customFieldSliderCategoryPalette;

  /// Validation error shown when numeric slider min >= max
  ///
  /// In en, this message translates to:
  /// **'Max must be greater than min'**
  String get customFieldSliderMinMaxError;

  /// Validation error shown when numeric slider step <= 0
  ///
  /// In en, this message translates to:
  /// **'Step must be greater than zero'**
  String get customFieldSliderStepError;

  /// Validation error shown when numeric slider min or max cannot be parsed
  ///
  /// In en, this message translates to:
  /// **'Min and max must be valid numbers'**
  String get customFieldSliderNumericRangeError;

  /// Tooltip and screen-reader label for the clear (×) button next to the slider editor
  ///
  /// In en, this message translates to:
  /// **'Clear value'**
  String get customFieldSliderClearTooltip;

  /// Screen-reader announcement when the slider field has no value (pristine or cleared)
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get customFieldSliderNotSet;

  /// Label for the femme-masc gradient preset
  ///
  /// In en, this message translates to:
  /// **'Femme ↔︎ Masc presentation'**
  String get sliderGradientPresetFemmeMasc;

  /// Label for the soft-hard gradient preset
  ///
  /// In en, this message translates to:
  /// **'Soft ↔︎ Hard'**
  String get sliderGradientPresetSoftHard;

  /// Label for the high-low gender gradient preset
  ///
  /// In en, this message translates to:
  /// **'Agender ↔︎ Highly gendered'**
  String get sliderGradientPresetHighLowGender;

  /// Label for the calm-intense gradient preset
  ///
  /// In en, this message translates to:
  /// **'Calm ↔︎ Intense'**
  String get sliderGradientPresetCalmIntense;

  /// Label for the sad-happy gradient preset
  ///
  /// In en, this message translates to:
  /// **'Sad ↔︎ Happy'**
  String get sliderGradientPresetSadHappy;

  /// Label for the low-high energy gradient preset
  ///
  /// In en, this message translates to:
  /// **'Low ↔︎ High energy'**
  String get sliderGradientPresetLowHighEnergy;

  /// Label for the soft-bold gradient preset
  ///
  /// In en, this message translates to:
  /// **'Soft ↔︎ Bold'**
  String get sliderGradientPresetSoftBold;

  /// Label for the cool-warm gradient preset
  ///
  /// In en, this message translates to:
  /// **'Cool ↔︎ Warm'**
  String get sliderGradientPresetCoolWarm;

  /// Label for the day-night gradient preset
  ///
  /// In en, this message translates to:
  /// **'Day ↔︎ Night'**
  String get sliderGradientPresetDayNight;

  /// Label for the solid-accent gradient preset (single color, no gradient)
  ///
  /// In en, this message translates to:
  /// **'Solid accent'**
  String get sliderGradientPresetSolidAccent;

  /// Label for the monochrome gradient preset
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get sliderGradientPresetMonochrome;

  /// Label for the rose-dusk gradient preset
  ///
  /// In en, this message translates to:
  /// **'Rose dusk'**
  String get sliderGradientPresetPaletteRoseDusk;

  /// Label for the sage-meadow gradient preset
  ///
  /// In en, this message translates to:
  /// **'Sage meadow'**
  String get sliderGradientPresetPaletteSageMeadow;

  /// Label for the last-light gradient preset
  ///
  /// In en, this message translates to:
  /// **'Last light'**
  String get sliderGradientPresetPaletteLastLight;

  /// Label for the amber-fire gradient preset
  ///
  /// In en, this message translates to:
  /// **'Amber fire'**
  String get sliderGradientPresetPaletteAmberFire;

  /// Label for the mauve-bloom gradient preset
  ///
  /// In en, this message translates to:
  /// **'Mauve bloom'**
  String get sliderGradientPresetPaletteMauveBloom;

  /// Label for the warm-ink gradient preset
  ///
  /// In en, this message translates to:
  /// **'Warm ink'**
  String get sliderGradientPresetPaletteWarmInk;

  /// Context menu item to edit a custom field
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get customFieldMenuEdit;

  /// Context menu / top-bar action to share a custom field or group as a reusable template
  ///
  /// In en, this message translates to:
  /// **'Share as template'**
  String get customFieldMenuShareAsTemplate;

  /// Context menu item to move a field into a group; tapping shows a submenu of groups
  ///
  /// In en, this message translates to:
  /// **'Move into group'**
  String get customFieldMenuMoveIntoGroup;

  /// Context menu item to move a nested field back to top level
  ///
  /// In en, this message translates to:
  /// **'Move out of group'**
  String get customFieldMenuMoveOutOfGroup;

  /// Context menu item to move a nested field into a different group
  ///
  /// In en, this message translates to:
  /// **'Move to another group'**
  String get customFieldMenuMoveToAnotherGroup;

  /// Context menu item to delete a custom field
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get customFieldMenuDelete;

  /// Badge shown on the custom field detail screen when the field is nested inside a group
  ///
  /// In en, this message translates to:
  /// **'Inside: {group}'**
  String customFieldDetailInsideGroup(String group);

  /// One-shot snackbar tip shown after the first group field is created
  ///
  /// In en, this message translates to:
  /// **'Long-press a field to move it into a group'**
  String get customFieldFirstGroupTip;

  /// Disabled menu item shown when there are no eligible target groups for a move action
  ///
  /// In en, this message translates to:
  /// **'No groups to move into'**
  String get customFieldNoEligibleGroups;

  /// Small label on the shareable field-template card identifying it as a Prism field template
  ///
  /// In en, this message translates to:
  /// **'Field template'**
  String get fieldTemplateCardKicker;

  /// Count of fields included in a shared field template
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No fields} =1{1 field} other{{count} fields}}'**
  String fieldTemplateFieldCount(int count);

  /// Hint on the shareable field-template card explaining how the recipient imports it
  ///
  /// In en, this message translates to:
  /// **'Scan or paste to import'**
  String get fieldTemplateCardScanHint;

  /// Hint on the shareable field-template card when the code is too long for a QR, so scanning isn't possible
  ///
  /// In en, this message translates to:
  /// **'Copy the text to import'**
  String get fieldTemplateCardCopyHint;

  /// Shown in place of the QR on the card when the template code is too long to fit a scannable QR
  ///
  /// In en, this message translates to:
  /// **'Too large for a QR code'**
  String get fieldTemplateCardNoQr;

  /// Accessibility label for the QR code image on a shared field template
  ///
  /// In en, this message translates to:
  /// **'QR code for the {name} field template'**
  String fieldTemplateQrSemanticLabel(String name);

  /// Title of the sheet for sharing a custom-field group or field as a template
  ///
  /// In en, this message translates to:
  /// **'Share template'**
  String get fieldTemplateShareTitle;

  /// Primary action on the share-template sheet: copy the template to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy template'**
  String get fieldTemplateShareCopy;

  /// Toast shown after copying a template to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Template copied'**
  String get fieldTemplateShareCopiedToast;

  /// Action to save the branded template card as a PNG image (desktop)
  ///
  /// In en, this message translates to:
  /// **'Save image'**
  String get fieldTemplateShareSaveImage;

  /// Action to share the branded template card as a PNG image (mobile)
  ///
  /// In en, this message translates to:
  /// **'Share image'**
  String get fieldTemplateShareShareImage;

  /// Toast shown after the branded template image is saved
  ///
  /// In en, this message translates to:
  /// **'Template image saved'**
  String get fieldTemplateShareImageSaved;

  /// Toast shown when rendering or saving the branded template image fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the image'**
  String get fieldTemplateShareImageFailed;

  /// Subject line used when sharing a template image via the system share sheet
  ///
  /// In en, this message translates to:
  /// **'Prism field template'**
  String get fieldTemplateShareSubject;

  /// Heading above the list of fields a shared template contains
  ///
  /// In en, this message translates to:
  /// **'What\'s included'**
  String get fieldTemplateShareWhatsIncluded;

  /// Inline note shown when a template is too long to render as a scannable QR
  ///
  /// In en, this message translates to:
  /// **'This template is too long to fit a QR code — copy it or share it as text.'**
  String get fieldTemplateShareNoQrWarning;

  /// Action to share the template code as plain text via the system share sheet (used when the template is too large for a QR image)
  ///
  /// In en, this message translates to:
  /// **'Share as text'**
  String get fieldTemplateShareAsText;

  /// Shown when a template exceeds the import size limits and can't be shared at all
  ///
  /// In en, this message translates to:
  /// **'This template is too large to share — try removing some fields or choice options.'**
  String get fieldTemplateShareTooLarge;

  /// Label above the selectable template text field shown on desktop for keyboard copy
  ///
  /// In en, this message translates to:
  /// **'Template text'**
  String get fieldTemplateShareTextLabel;

  /// Inline badge on a template field whose type this app version doesn't recognise; it imports as-is
  ///
  /// In en, this message translates to:
  /// **'Newer version'**
  String get fieldTemplatePreviewUnknownBadge;

  /// Accessibility label for one field row in a template summary or preview
  ///
  /// In en, this message translates to:
  /// **'{name}, {type}'**
  String fieldTemplatePreviewRowSemantic(String name, String type);

  /// Title of the sheet that previews a template's fields before importing
  ///
  /// In en, this message translates to:
  /// **'Review template'**
  String get fieldTemplateImportPreviewTitle;

  /// Reassurance shown in the import preview that the imported fields are independent copies
  ///
  /// In en, this message translates to:
  /// **'Saved to your fields. Changes won\'t affect the original.'**
  String get fieldTemplateImportOwnershipLine;

  /// Primary action that imports the previewed template's fields
  ///
  /// In en, this message translates to:
  /// **'Import fields'**
  String get fieldTemplateImportConfirm;

  /// Title of the import-template entry sheet and its top-bar action
  ///
  /// In en, this message translates to:
  /// **'Import template'**
  String get fieldTemplateImportTitle;

  /// Explainer at the top of the import-template entry sheet
  ///
  /// In en, this message translates to:
  /// **'Paste a template, choose its image, or scan a QR code to add someone\'s custom fields to your own.'**
  String get fieldTemplateImportDescription;

  /// Label on the paste field in the import-template sheet
  ///
  /// In en, this message translates to:
  /// **'Paste template'**
  String get fieldTemplateImportPasteLabel;

  /// Button that decodes and previews a pasted template
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get fieldTemplateImportPasteAction;

  /// Button to pick a saved template image file to import
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get fieldTemplateImportChooseImage;

  /// Button (mobile) to open the camera and scan a template QR code
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get fieldTemplateImportScan;

  /// Instruction shown above the camera when scanning a template QR code
  ///
  /// In en, this message translates to:
  /// **'Point your camera at a template\'s QR code.'**
  String get fieldTemplateImportScanDescription;

  /// Divider label between the paste field and the image/scan options
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get fieldTemplateImportDividerOr;

  /// Error shown when a pasted or scanned template can't be decoded
  ///
  /// In en, this message translates to:
  /// **'This code doesn\'t look right — check for typos or ask for a new one.'**
  String get fieldTemplateImportErrorInvalid;

  /// Error shown when a template was made by a newer, unsupported version
  ///
  /// In en, this message translates to:
  /// **'This template needs a newer version of Prism. Update the app to import it.'**
  String get fieldTemplateImportErrorVersion;

  /// Error shown when a chosen image contains no readable template
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find a template in that image — try pasting it instead.'**
  String get fieldTemplateImportErrorNoImage;

  /// Error shown when importing a previewed template fails to write
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import the template.'**
  String get fieldTemplateImportErrorFailed;

  /// Toast shown after a template is imported
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} imported (1 field)} other{{name} imported ({count} fields)}}'**
  String fieldTemplateImportSuccessToast(String name, int count);

  /// Title of the Media settings screen, which manages the encrypted image library, chat images, and avatars/banners
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get mediaScreenTitle;

  /// Tooltip on the add-image button in the Media screen top bar; opens a menu of image sources
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get mediaAddImageTooltip;

  /// Tooltip on the overflow (more-actions) menu in the Media screen top bar
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get mediaMoreActionsTooltip;

  /// Media screen menu action: re-request blobs this device references but is missing from its cache and the relay
  ///
  /// In en, this message translates to:
  /// **'Request missing media'**
  String get mediaRequestMissingTitle;

  /// Snackbar shown when there is no missing media to request
  ///
  /// In en, this message translates to:
  /// **'No missing media — everything\'s here'**
  String get mediaRequestMissingNone;

  /// Snackbar after the user taps Request missing media
  ///
  /// In en, this message translates to:
  /// **'Re-requesting {count} missing media'**
  String mediaRequestMissingStarted(int count);

  /// Snackbar after Request missing media when some blobs were already judged unavailable and likely need another device that holds them
  ///
  /// In en, this message translates to:
  /// **'Re-requesting {count} missing media; {terminal} may need another device online'**
  String mediaRequestMissingStartedSomeUnavailable(int count, int terminal);

  /// Add-image source menu item: take a photo with the camera
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get mediaSourceCamera;

  /// Add-image source menu item: pick from the device's photo library
  ///
  /// In en, this message translates to:
  /// **'Photo library'**
  String get mediaSourcePhotoLibrary;

  /// Add-image source menu item: pick an image file
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get mediaSourceFile;

  /// Add-image source menu item: fetch an image from a web URL
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get mediaSourceUrl;

  /// Add-image source menu item: insert an image already stored in the shared Prism image library
  ///
  /// In en, this message translates to:
  /// **'Prism library'**
  String get mediaSourcePrismLibrary;

  /// Label above the image width selector in the insert-image dialogs.
  ///
  /// In en, this message translates to:
  /// **'Image width'**
  String get mediaSizeLabel;

  /// Image width mode: the image's default/intrinsic size (no explicit width).
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get mediaSizeModeDefault;

  /// Image width mode: a fixed width in logical pixels. Abbreviation for 'pixels'; keep short.
  ///
  /// In en, this message translates to:
  /// **'px'**
  String get mediaSizeModePixels;

  /// Image width mode: a percentage of the available content width. The percent sign.
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get mediaSizeModePercent;

  /// Image width mode: a multiple of the surrounding text size. The CSS 'em' unit; leave untranslated.
  ///
  /// In en, this message translates to:
  /// **'em'**
  String get mediaSizeModeEm;

  /// Hint for the numeric width value field in the image size selector (units come from the selected mode).
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get mediaSizeValueHint;

  /// Title of the dialog that asks for a size when inserting an image from the Prism library.
  ///
  /// In en, this message translates to:
  /// **'Image size'**
  String get mediaInsertSizeTitle;

  /// Confirm button: insert the chosen library image at the selected size.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get mediaInsertButton;

  /// Title of the dialog for adding a picked image to the shared image library
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get mediaAddToLibraryTitle;

  /// Title of the dialog (shown from a markdown editor) for staging a picked image into the image library
  ///
  /// In en, this message translates to:
  /// **'Add image to library'**
  String get mediaAddImageToLibraryTitle;

  /// Title of the dialog prompting for an image's web URL
  ///
  /// In en, this message translates to:
  /// **'Image URL'**
  String get mediaImageUrlTitle;

  /// Hint/placeholder text for the image URL input field. Example URL — keep it a plausible image URL.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/image.png'**
  String get mediaImageUrlHint;

  /// Hint for the optional tag field when adding an image to the library. 'nbflag' is an example tag (a short identifier the user types to reference the image as the markdown code); leave it untranslated as it's example data.
  ///
  /// In en, this message translates to:
  /// **'Tag (optional) e.g. nbflag'**
  String get mediaTagFieldHint;

  /// Hint for the optional alternative-text field when adding an image (describes the image for screen readers)
  ///
  /// In en, this message translates to:
  /// **'Alt text (optional)'**
  String get mediaAltTextFieldHint;

  /// Hint for the tag field when editing an existing image's tag. 'nbflag' and 'divider' are example tags; leave untranslated as example data.
  ///
  /// In en, this message translates to:
  /// **'e.g. nbflag, divider'**
  String get mediaEditTagHint;

  /// Confirm button on the image-URL dialog; fetches the image from the entered URL
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get mediaFetchButton;

  /// Toast confirming an image was added to the library under the given tag
  ///
  /// In en, this message translates to:
  /// **'Added \"{tag}\" to library'**
  String mediaAddedToLibrary(String tag);

  /// Error toast when adding an image to the library fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add image: {error}'**
  String mediaAddImageFailed(String error);

  /// Error toast when replacing an existing library image's bytes fails
  ///
  /// In en, this message translates to:
  /// **'Failed to replace image: {error}'**
  String mediaReplaceImageFailed(String error);

  /// Error toast when an image cannot be fetched from the entered URL (Media screen)
  ///
  /// In en, this message translates to:
  /// **'Could not fetch image from URL'**
  String get mediaFetchFromUrlFailed;

  /// Error toast when an image cannot be fetched from the entered URL (markdown editor)
  ///
  /// In en, this message translates to:
  /// **'Could not fetch image'**
  String get mediaFetchImageFailed;

  /// Error toast when a fetched URL returns a web page or other non-image content instead of a direct image
  ///
  /// In en, this message translates to:
  /// **'That link is a web page, not an image. Open the image itself and copy its direct link (it should end in .jpg, .png, .gif, etc.).'**
  String get mediaFetchNotAnImage;

  /// Error toast when an image URL can't be reached (DNS/connection/timeout/HTTP error)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach that image. Check the link and your connection, then try again.'**
  String get mediaFetchUnreachable;

  /// Error toast when a fetched image exceeds the size cap
  ///
  /// In en, this message translates to:
  /// **'That image is too large to add.'**
  String get mediaFetchTooLarge;

  /// Error toast when a typed image tag normalizes to an empty string (all characters were stripped as invalid)
  ///
  /// In en, this message translates to:
  /// **'Tag has no usable characters'**
  String get mediaTagNoUsableCharacters;

  /// Error toast when the typed image tag collides with an existing library tag
  ///
  /// In en, this message translates to:
  /// **'Tag \"{tag}\" is already in use'**
  String mediaTagAlreadyInUse(String tag);

  /// Toast confirming an image tag was renamed (no references needed updating)
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get mediaTagRenamed;

  /// Toast confirming an image tag was renamed and that this many references to it were repointed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Renamed; updated 1 reference} other{Renamed; updated {count} references}}'**
  String mediaTagRenamedWithReferences(int count);

  /// Error toast shown when committing a markdown edit but one or more staged images failed to upload
  ///
  /// In en, this message translates to:
  /// **'Some images couldn\'t be saved'**
  String get mediaSomeImagesNotSaved;

  /// Toast confirming the image's markdown reference code was copied to the clipboard. {reference} is the literal markdown code and should not be translated.
  ///
  /// In en, this message translates to:
  /// **'Copied {reference}'**
  String mediaCopiedReference(String reference);

  /// Error toast when jumping to the chat message that used an image, but that message has been deleted
  ///
  /// In en, this message translates to:
  /// **'Message no longer exists'**
  String get mediaMessageNoLongerExists;

  /// Title of the confirmation dialog for deleting a stored image
  ///
  /// In en, this message translates to:
  /// **'Delete image?'**
  String get mediaDeleteImageTitle;

  /// Body of the confirmation dialog for deleting a stored image
  ///
  /// In en, this message translates to:
  /// **'This will remove the image from all synced devices. Any bios referencing it will show a missing image.'**
  String get mediaDeleteImageMessage;

  /// Title of the dialog asking whether to repoint existing references when renaming an in-use image tag
  ///
  /// In en, this message translates to:
  /// **'Update references?'**
  String get mediaUpdateReferencesTitle;

  /// Body of the rename-references dialog. Explains how many places reference the old tag and offers to update them to the new tag or leave them.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{\"{oldTag}\" is used in 1 place. Update that reference to \"{newTag}\", or leave it on \"{oldTag}\" — e.g. to free up the name for a different image?} other{\"{oldTag}\" is used in {count} places. Update those references to \"{newTag}\", or leave them on \"{oldTag}\" — e.g. to free up the name for a different image?}}'**
  String mediaUpdateReferencesMessage(int count, String oldTag, String newTag);

  /// Button on the rename-references dialog: keep existing references pointing at the old tag
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get mediaActionLeave;

  /// Button on the rename-references dialog: repoint existing references to the new tag
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get mediaActionUpdate;

  /// Section title for the storage overview on the Media screen
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get mediaSectionStorage;

  /// Storage row label for end-to-end encrypted media (library + chat images)
  ///
  /// In en, this message translates to:
  /// **'Encrypted media'**
  String get mediaStorageEncryptedMedia;

  /// Storage row label for member avatars and banners stored locally
  ///
  /// In en, this message translates to:
  /// **'Member data'**
  String get mediaStorageMemberData;

  /// Section title for the shared, reusable image library on the Media screen
  ///
  /// In en, this message translates to:
  /// **'Image library'**
  String get mediaSectionImageLibrary;

  /// Section title for images attached to chat messages on the Media screen
  ///
  /// In en, this message translates to:
  /// **'Chat images'**
  String get mediaSectionChatImages;

  /// Section title for member avatars and profile banners on the Media screen
  ///
  /// In en, this message translates to:
  /// **'Avatars & banners'**
  String get mediaSectionAvatarsBanners;

  /// Footer note under the avatars & banners section explaining where they're managed and that they stay on-device
  ///
  /// In en, this message translates to:
  /// **'Managed from the member edit sheet. Stored locally on device.'**
  String get mediaAvatarsBannersFooter;

  /// Storage row label for member avatars
  ///
  /// In en, this message translates to:
  /// **'Avatars'**
  String get mediaLabelAvatars;

  /// Storage row label for member profile banners
  ///
  /// In en, this message translates to:
  /// **'Banners'**
  String get mediaLabelBanners;

  /// Empty-state text on the Media screen when there are no library images, chat images, avatars, or banners
  ///
  /// In en, this message translates to:
  /// **'No stored media'**
  String get mediaNoStoredMedia;

  /// Count fragment in a storage summary, e.g. '3 items'. Joined with a size like '3 items, 1.2 MB'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} item} other{{count} items}}'**
  String mediaSummaryItems(int count);

  /// Count fragment in a storage summary for avatars, e.g. '2 avatars'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} avatar} other{{count} avatars}}'**
  String mediaSummaryAvatars(int count);

  /// Count fragment in a storage summary for banners, e.g. '2 banners'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} banner} other{{count} banners}}'**
  String mediaSummaryBanners(int count);

  /// Label on a library image card indicating the image isn't referenced anywhere
  ///
  /// In en, this message translates to:
  /// **'Unused'**
  String get mediaUsageUnused;

  /// Label on a library image card indicating how many surfaces reference the image
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Used in 1 place} other{Used in {count} places}}'**
  String mediaUsageUsedInPlaces(int count);

  /// Context menu item: show the list of places that reference this library image
  ///
  /// In en, this message translates to:
  /// **'View usage'**
  String get mediaMenuViewUsage;

  /// Context menu item: copy the markdown reference code for this image to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get mediaMenuCopyCode;

  /// Context menu item: rename this image's tag
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get mediaMenuEditTag;

  /// Context menu item: swap this image's pixels while keeping its tag and references
  ///
  /// In en, this message translates to:
  /// **'Replace image'**
  String get mediaMenuReplaceImage;

  /// Context menu item: delete this image
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get mediaMenuDelete;

  /// Context menu item on a chat image: navigate to the message that contains it
  ///
  /// In en, this message translates to:
  /// **'Jump to message'**
  String get mediaMenuJumpToMessage;

  /// Title of the screen listing every surface that references a library image
  ///
  /// In en, this message translates to:
  /// **'Used by'**
  String get mediaUsageScreenTitle;

  /// Empty-state text on the image-usage screen when nothing references the image
  ///
  /// In en, this message translates to:
  /// **'Not used anywhere'**
  String get mediaUsageNotUsedAnywhere;

  /// Usage-kind label: the image is referenced in a member's bio
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get mediaUsageKindBio;

  /// Usage-kind label: the image is referenced in a note
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get mediaUsageKindNote;

  /// Usage-kind label: the image is referenced in a group description
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get mediaUsageKindGroup;

  /// Usage-kind label: the image is referenced in a custom field value
  ///
  /// In en, this message translates to:
  /// **'Custom field'**
  String get mediaUsageKindCustomField;

  /// Usage-kind label: the image is referenced in a chat message
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get mediaUsageKindChat;

  /// Usage-kind label: the image is referenced in a board post
  ///
  /// In en, this message translates to:
  /// **'Board post'**
  String get mediaUsageKindBoardPost;

  /// Usage list label pointing at a member's bio, e.g. "Alex's bio"
  ///
  /// In en, this message translates to:
  /// **'{name}\'s bio'**
  String mediaUsageLabelBio(String name);

  /// Usage list label pointing at a titled note
  ///
  /// In en, this message translates to:
  /// **'Note: {title}'**
  String mediaUsageLabelNote(String title);

  /// Usage list label for a note that has no title
  ///
  /// In en, this message translates to:
  /// **'Untitled note'**
  String get mediaUsageLabelUntitledNote;

  /// Usage list label pointing at a member's custom-field value, e.g. "Alex · Pronouns". The middle dot separator should be kept.
  ///
  /// In en, this message translates to:
  /// **'{member} · {field}'**
  String mediaUsageLabelCustomField(String member, String field);

  /// Usage list label for a chat message that references the image but has no other preview text
  ///
  /// In en, this message translates to:
  /// **'Chat message'**
  String get mediaUsageLabelChatMessage;

  /// Usage list label pointing at a board post with a title or preview
  ///
  /// In en, this message translates to:
  /// **'Board post: {title}'**
  String mediaUsageLabelBoardPost(String title);

  /// Usage list label for a board post that has no title or preview text
  ///
  /// In en, this message translates to:
  /// **'Untitled board post'**
  String get mediaUsageLabelBoardPostUntitled;

  /// Fallback name used in a custom-field usage label when the referenced member can't be resolved
  ///
  /// In en, this message translates to:
  /// **'a member'**
  String get mediaUsageLabelUnknownMember;

  /// Fallback name used in a custom-field usage label when the referenced field can't be resolved
  ///
  /// In en, this message translates to:
  /// **'a field'**
  String get mediaUsageLabelUnknownField;

  /// Title of the full-screen picker for choosing an image from the shared library to insert
  ///
  /// In en, this message translates to:
  /// **'Image library'**
  String get mediaLibraryPickerTitle;

  /// Toast shown when opening the image-library picker but the library has no images
  ///
  /// In en, this message translates to:
  /// **'No images in library yet'**
  String get mediaLibraryEmpty;

  /// Screen-reader label for an image with no caption and no owning member (e.g. a chat image)
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageSemanticLabel;

  /// Screen-reader label for an image embedded in a member's bio, e.g. "Image in Alex's bio"
  ///
  /// In en, this message translates to:
  /// **'Image in {name}\'s bio'**
  String imageSemanticInBio(String name);

  /// Screen-reader label for an image placeholder while the image is loading
  ///
  /// In en, this message translates to:
  /// **'Image loading'**
  String get imageSemanticLoading;

  /// Screen-reader label and visible caption for an image that failed to load (tap to retry)
  ///
  /// In en, this message translates to:
  /// **'Image couldn\'t load'**
  String get imageSemanticLoadFailed;

  /// Screen-reader label and visible caption for an image whose remote blob has expired and is no longer available
  ///
  /// In en, this message translates to:
  /// **'Image expired'**
  String get imageSemanticExpired;

  /// Screen-reader label for a small image thumbnail
  ///
  /// In en, this message translates to:
  /// **'Media thumbnail'**
  String get imageSemanticThumbnail;
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
