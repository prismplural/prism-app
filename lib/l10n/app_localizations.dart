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
  /// **'Private by default'**
  String get onboardingWelcomePrivateTitle;

  /// Feature row description in welcome step
  ///
  /// In en, this message translates to:
  /// **'Not even we can read your data. Everything stays on your device unless you choose to sync.'**
  String get onboardingWelcomePrivateDescription;

  /// Feature row title in welcome step
  ///
  /// In en, this message translates to:
  /// **'Sync across devices'**
  String get onboardingWelcomeSyncTitle;

  /// Feature row description in welcome step
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted. The server only sees noise.'**
  String get onboardingWelcomeSyncDescription;

  /// Feature row title in welcome step
  ///
  /// In en, this message translates to:
  /// **'Built for you'**
  String get onboardingWelcomeBuiltForYouTitle;

  /// Feature row description in welcome step
  ///
  /// In en, this message translates to:
  /// **'Your words, your colors, your features. Prism adapts to how your system works.'**
  String get onboardingWelcomeBuiltForYouDescription;

  /// Button label to load default members in add members step
  ///
  /// In en, this message translates to:
  /// **'Skylar\'s Defaults'**
  String get onboardingAddMembersSkylarsDefaults;

  /// Empty state text in add members step
  ///
  /// In en, this message translates to:
  /// **'No members yet.\nTap \"Add Member\" or use the defaults.'**
  String get onboardingAddMembersNoMembers;

  /// Tooltip for the remove member button in add members list
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get onboardingAddMembersRemoveMember;

  /// Button label to open the add member sheet
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get onboardingAddMembersAddMember;

  /// Title bar of the add member sheet
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get onboardingAddMemberSheetTitle;

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
  /// **'Internal messaging between system members'**
  String get onboardingFeaturesChatDescription;

  /// Feature toggle title for polls in features step
  ///
  /// In en, this message translates to:
  /// **'Polls'**
  String get onboardingFeaturesPolls;

  /// Feature toggle description for polls in features step
  ///
  /// In en, this message translates to:
  /// **'Create polls for system decisions'**
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
  /// **'Polls, votes — the democracy your system deserves.'**
  String get onboardingCompletePollsDescription;

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
  /// **'Import Members'**
  String get onboardingPluralKitImportButton;

  /// Success message after PluralKit import
  ///
  /// In en, this message translates to:
  /// **'Imported {count} members from PluralKit!'**
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
  /// **'This will restore your exported Prism system and finish setup on this device.'**
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
  /// **'Enter system name'**
  String get onboardingSystemNameHint;

  /// Helper text below the system name field
  ///
  /// In en, this message translates to:
  /// **'This is how your system will be identified in the app.'**
  String get onboardingSystemNameHelperText;

  /// Hint text above the fronter grid in whos fronting step
  ///
  /// In en, this message translates to:
  /// **'Tap to select who is currently fronting'**
  String get onboardingWhosFrontingSelectHint;

  /// Empty state message in whos fronting step
  ///
  /// In en, this message translates to:
  /// **'No members added yet.\nGo back to add members first.'**
  String get onboardingWhosFrontingNoMembers;

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

  /// Hint text for the custom channel name field
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get onboardingChatChannelNameHint;

  /// Section header for terminology section in preferences step
  ///
  /// In en, this message translates to:
  /// **'Terminology'**
  String get onboardingPreferencesTerminology;

  /// Label for the custom terminology option in preferences grid
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get onboardingPreferencesCustomTerminology;

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

  /// Section header for accent color in preferences step
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get onboardingPreferencesAccentColor;

  /// Toggle title for per-member colors in preferences step
  ///
  /// In en, this message translates to:
  /// **'Per-Member Colors'**
  String get onboardingPreferencesPerMemberColors;

  /// Toggle subtitle for per-member colors in preferences step
  ///
  /// In en, this message translates to:
  /// **'Let each member have their own accent color'**
  String get onboardingPreferencesPerMemberColorsSubtitle;

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

  /// Title on the password entry view during sync pairing
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get onboardingSyncEnterPassword;

  /// Description on the password entry view during sync pairing
  ///
  /// In en, this message translates to:
  /// **'Enter your sync password to finish enrolling this device.'**
  String get onboardingSyncEnterPasswordDescription;

  /// Hint text for the password field in sync pairing
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get onboardingSyncPasswordHint;

  /// Button label to complete sync pairing with password
  ///
  /// In en, this message translates to:
  /// **'Finish Pairing'**
  String get onboardingSyncFinishPairing;

  /// Toast shown when user taps Finish Pairing with empty password
  ///
  /// In en, this message translates to:
  /// **'Please enter your password.'**
  String get onboardingSyncEnterPasswordPrompt;

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

  /// Title shown when sync device pairing fails
  ///
  /// In en, this message translates to:
  /// **'Pairing failed'**
  String get onboardingSyncPairingFailed;

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
  /// **'Assigned Member'**
  String get habitsAssignedMember;

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

  /// Tooltip for the create habit button in the habits list
  ///
  /// In en, this message translates to:
  /// **'Create habit'**
  String get habitsCreateHabitTooltip;

  /// Empty state title on habits list
  ///
  /// In en, this message translates to:
  /// **'No habits yet'**
  String get habitsEmptyTitle;

  /// Empty state subtitle on habits list
  ///
  /// In en, this message translates to:
  /// **'Create habits to track daily routines, self-care, or anything your system wants to keep up with.'**
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
  /// **'Create a poll to get your system voting'**
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
  /// **'{count} options'**
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

  /// Suffix in the toast shown when no member is selected to vote as (prepended by terminology select text)
  ///
  /// In en, this message translates to:
  /// **'to vote as'**
  String get pollsDetailSelectToVoteAs;

  /// Message shown when no members are available for voting
  ///
  /// In en, this message translates to:
  /// **'No members available'**
  String get pollsDetailNoMembers;

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
