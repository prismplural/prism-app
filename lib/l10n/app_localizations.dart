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

  /// Notes screen title
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesTitle;

  /// Tooltip for the new note button in notes list
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get notesNewNoteTooltip;

  /// Empty state title when there are no notes
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get notesEmptyTitle;

  /// Empty state subtitle for notes list
  ///
  /// In en, this message translates to:
  /// **'Create notes to keep track of thoughts and observations'**
  String get notesEmptySubtitle;

  /// Action button label to create a new note
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get notesNewNoteAction;

  /// Fallback title for a note with no title or body
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get notesUntitled;

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
  /// **'Members'**
  String get migrationSupportedMembers;

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
  /// **'Member colors'**
  String get migrationSupportedMemberColors;

  /// Supported data type: member descriptions
  ///
  /// In en, this message translates to:
  /// **'Member descriptions'**
  String get migrationSupportedMemberDescriptions;

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
  /// **'This will delete all existing members, front history, conversations, and other data before importing. This action cannot be undone.\n\nIf you have sync set up, other paired devices should also be reset to avoid conflicts.'**
  String get migrationReplaceAllMessage;

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
  /// **'Members'**
  String get migrationResultMembers;

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

  /// Description text for the sync direction picker
  ///
  /// In en, this message translates to:
  /// **'Choose how data flows between Prism and PluralKit.'**
  String get pluralkitSyncDirectionDescription;

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
  /// **'{count, plural, =1{1 member pulled} other{{count} members pulled}}'**
  String pluralkitMembersPulled(int count);

  /// Sync summary row: members pushed to PluralKit
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member pushed} other{{count} members pushed}}'**
  String pluralkitMembersPushed(int count);

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
  /// **'{count, plural, =1{1 member unchanged} other{{count} members unchanged}}'**
  String pluralkitMembersUnchanged(int count);

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

  /// How It Works info row about member matching
  ///
  /// In en, this message translates to:
  /// **'Members are matched by PluralKit UUID. Existing members are updated, new ones are created.'**
  String get pluralkitInfoMembers;

  /// How It Works info row about switch import
  ///
  /// In en, this message translates to:
  /// **'Switches are imported as fronting sessions. Duplicate switches are automatically skipped.'**
  String get pluralkitInfoSwitches;

  /// Relative time label when PluralKit sync was less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get pluralkitJustNow;

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
  /// **'Import members & fronting via API token'**
  String get dataManagementPluralKitRowSubtitle;

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
  /// **'Create a password-protected backup of all your data including members, fronting sessions, messages, polls, and settings.'**
  String get dataManagementExportDescription;

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
  /// **'Use a passphrase of 15+ words for best protection'**
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
  /// **'Members'**
  String get dataManagementPreviewMembers;

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
