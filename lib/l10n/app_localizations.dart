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

  /// Settings section header: System
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSectionSystem;

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

  /// Settings section header: About
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// Settings link: System Information
  ///
  /// In en, this message translates to:
  /// **'System Information'**
  String get settingsSystemInformation;

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

  /// Settings link: Navigation
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get settingsNavigation;

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
  /// **'Sync'**
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

  /// Settings link: About
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Settings link: Encryption & Privacy
  ///
  /// In en, this message translates to:
  /// **'Encryption & Privacy'**
  String get settingsEncryptionPrivacy;

  /// Settings link: Debug
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get settingsDebug;

  /// Fallback display name when no system name is set
  ///
  /// In en, this message translates to:
  /// **'My System'**
  String get settingsFallbackSystemName;

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

  /// Appearance settings section: Accent Color
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get appearanceAccentColor;

  /// Appearance settings section: Per-Member Colors
  ///
  /// In en, this message translates to:
  /// **'Per-{term} Colors'**
  String appearancePerMemberColors(String term);

  /// Toggle row title: enable per-member accent colors
  ///
  /// In en, this message translates to:
  /// **'Per-{term} accent colors'**
  String appearancePerMemberColorsSwitchTitle(String term);

  /// Toggle row subtitle: explain per-member accent colors
  ///
  /// In en, this message translates to:
  /// **'Allow each {term} to have their own color'**
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

  /// Appearance settings section: Terminology
  ///
  /// In en, this message translates to:
  /// **'Terminology'**
  String get appearanceTerminology;

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
  /// **'Sync'**
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
  /// **'Sync is not set up'**
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
  /// **'Generate a pairing QR code'**
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
  /// **'Sync Preferences'**
  String get syncPreferencesSection;

  /// Description for sync preferences section
  ///
  /// In en, this message translates to:
  /// **'Control what settings are shared across your devices via sync.'**
  String get syncPreferencesDescription;

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
  /// **'Troubleshooting'**
  String get syncTroubleshootingLink;

  /// Label for synced last 24h count
  ///
  /// In en, this message translates to:
  /// **'Synced last 24h'**
  String get syncLast24h;

  /// Label for total synced count
  ///
  /// In en, this message translates to:
  /// **'Total synced'**
  String get syncTotal;

  /// Number of synced entities
  ///
  /// In en, this message translates to:
  /// **'{count} entities'**
  String syncEntitiesCount(int count);

  /// Toast message after a successful manual sync
  ///
  /// In en, this message translates to:
  /// **'Sync finished'**
  String get syncFinished;

  /// Toast message when sync fails
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(Object error);

  /// Sync status card: error state title
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
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
  /// **'Everything is end-to-end encrypted — the server never sees your data. You\'ll create a password and receive a recovery key to keep safe.'**
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

  /// Sync setup progress: bootstrapping data
  ///
  /// In en, this message translates to:
  /// **'Uploading your data...'**
  String get syncSetupProgressBootstrapping;

  /// Sync setup progress: syncing
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncSetupProgressSyncing;

  /// Sheet title when secret key is revealed
  ///
  /// In en, this message translates to:
  /// **'Secret Key'**
  String get syncSecretKeyTitle;

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
  /// **'Sync engine not available.'**
  String get syncEngineNotAvailable;

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
  /// **'This will permanently delete all your data including members, fronting sessions, messages, polls, habits, sleep data, and settings. This action cannot be undone.'**
  String get resetDataConfirmAll;

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

  /// Navigation settings screen title
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigationSettingsTitle;

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

  /// Title for the member comparison chart
  ///
  /// In en, this message translates to:
  /// **'Fronting Time by Member'**
  String get statisticsFrontingTimeByMember;

  /// Active/inactive member count breakdown in statistics
  ///
  /// In en, this message translates to:
  /// **'{active} active, {inactive} inactive'**
  String statisticsActiveMembersBreakdown(int active, int inactive);

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

  /// Debug tools: timeline sanitization title
  ///
  /// In en, this message translates to:
  /// **'Timeline Sanitization'**
  String get debugTimelineSanitization;

  /// Debug tools: timeline sanitization subtitle
  ///
  /// In en, this message translates to:
  /// **'Scan for and fix timeline issues'**
  String get debugTimelineSanitizationSubtitle;

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
  /// **'This will permanently erase all members, sessions, conversations, messages, and polls. There is no undo.'**
  String get debugResetDatabaseConfirm2Message;

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
  /// **'System Information'**
  String get systemInfoTitle;

  /// Avatar action: change avatar
  ///
  /// In en, this message translates to:
  /// **'Change avatar'**
  String get systemInfoChangeAvatar;

  /// Avatar action: remove avatar
  ///
  /// In en, this message translates to:
  /// **'Remove avatar'**
  String get systemInfoRemoveAvatar;

  /// System name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get systemInfoNameLabel;

  /// Hint text for system name field
  ///
  /// In en, this message translates to:
  /// **'System name'**
  String get systemInfoSystemNameHint;

  /// Tooltip for save system name button
  ///
  /// In en, this message translates to:
  /// **'Save system name'**
  String get systemInfoSaveSystemName;

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
  /// **'System description'**
  String get systemInfoDescriptionHint;

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
  /// **'Sync Troubleshooting'**
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

  /// Section header: actions
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get syncTroubleshootingActions;

  /// Button: force sync now
  ///
  /// In en, this message translates to:
  /// **'Force Sync'**
  String get syncTroubleshootingForceSync;

  /// Button: open sync event log
  ///
  /// In en, this message translates to:
  /// **'Open Sync Event Log'**
  String get syncTroubleshootingOpenEventLog;

  /// Button: reset sync system
  ///
  /// In en, this message translates to:
  /// **'Reset Sync System'**
  String get syncTroubleshootingResetSync;

  /// Button: re-pair device
  ///
  /// In en, this message translates to:
  /// **'Re-pair Device'**
  String get syncTroubleshootingRepair;

  /// Section header: common issues
  ///
  /// In en, this message translates to:
  /// **'Common Issues'**
  String get syncTroubleshootingCommonIssues;

  /// Common issue 1 title
  ///
  /// In en, this message translates to:
  /// **'Sync not working?'**
  String get syncTroubleshootingIssue1Title;

  /// Common issue 1 description
  ///
  /// In en, this message translates to:
  /// **'Check that your relay URL and sync ID are correctly configured in Sync settings. Both devices must use the same sync ID.'**
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
  /// **'If pairing failed mid-way, your device identity may be inconsistent. Use \"Re-pair Device\" to generate a fresh identity and pair again.'**
  String get syncTroubleshootingIssue5Description;

  /// Toast when sync finishes
  ///
  /// In en, this message translates to:
  /// **'Sync finished'**
  String get syncTroubleshootingFinished;

  /// Toast when sync fails
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncTroubleshootingFailed(Object error);

  /// Dialog title for sync reset
  ///
  /// In en, this message translates to:
  /// **'Reset sync system?'**
  String get syncTroubleshootingResetTitle;

  /// Dialog message for sync reset
  ///
  /// In en, this message translates to:
  /// **'This keeps your local app data, but wipes sync keys, relay configuration, device identity, and sync history from this device. You will need to set up sync again afterward.'**
  String get syncTroubleshootingResetMessage;

  /// Button: confirm sync reset
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get syncTroubleshootingResetConfirm;

  /// Toast after sync reset
  ///
  /// In en, this message translates to:
  /// **'Sync system reset'**
  String get syncTroubleshootingResetSuccess;

  /// Dialog title for re-pair
  ///
  /// In en, this message translates to:
  /// **'Re-pair Device?'**
  String get syncTroubleshootingRepairTitle;

  /// Dialog message for re-pair
  ///
  /// In en, this message translates to:
  /// **'This will clear your sync credentials and require you to pair again. Any local changes not yet synced will be lost.\n\nWe recommend exporting your data first as a safety net.'**
  String get syncTroubleshootingRepairMessage;

  /// Button: re-pair now
  ///
  /// In en, this message translates to:
  /// **'Re-pair Now'**
  String get syncTroubleshootingRepairNow;

  /// Button: export data first before re-pair
  ///
  /// In en, this message translates to:
  /// **'Export Data First'**
  String get syncTroubleshootingExportFirst;

  /// Toast after credentials cleared
  ///
  /// In en, this message translates to:
  /// **'Sync credentials cleared'**
  String get syncTroubleshootingCredentialsCleared;

  /// Description text on chat feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Internal messaging between system {term}.'**
  String featureChatDescription(String term);

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
  /// **'In-system messaging between {term}'**
  String featureChatEnableSubtitle(String term);

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

  /// Description text on habits feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Track recurring tasks and build streaks with your system {term}.'**
  String featureHabitsDescription(String term);

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

  /// Description text on polls feature settings screen
  ///
  /// In en, this message translates to:
  /// **'Let your system vote on decisions together. Disabling hides polls from navigation but keeps existing poll data.'**
  String get featurePollsDescription;

  /// Toggle title: enable polls
  ///
  /// In en, this message translates to:
  /// **'Enable Polls'**
  String get featurePollsEnable;

  /// Toggle subtitle: enable polls
  ///
  /// In en, this message translates to:
  /// **'Create polls for system decisions'**
  String get featurePollsEnableSubtitle;

  /// Description text on notes feature settings screen
  ///
  /// In en, this message translates to:
  /// **'A personal journal for system {term}. Disabling hides notes from navigation but keeps existing entries.'**
  String featureNotesDescription(String term);

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

  /// Info banner title when timeline validation issues are detected
  ///
  /// In en, this message translates to:
  /// **'Timeline issues found'**
  String get frontingTimelineIssuesFound;

  /// Info banner message showing timeline issue count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 timeline issue found. Tap to review.} other{{count} timeline issues found. Tap to review.}}'**
  String frontingTimelineIssuesBannerMessage(int count);

  /// Button label in timeline issues banner
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get frontingTimelineIssuesReview;

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

  /// Menu item to create a new poll
  ///
  /// In en, this message translates to:
  /// **'New Poll'**
  String get frontingMenuNewPoll;

  /// Menu item to start a sleep session
  ///
  /// In en, this message translates to:
  /// **'Start Sleep'**
  String get frontingMenuStartSleep;

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
  /// **'Add your first system {member} to get started'**
  String frontingWelcomeSubtitle(String member);

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

  /// Sheet title when creating a new fronting session (non-co-front mode)
  ///
  /// In en, this message translates to:
  /// **'New Session'**
  String get frontingNewSession;

  /// Sheet title when adding a co-fronter to the active session
  ///
  /// In en, this message translates to:
  /// **'Add Co-Fronter'**
  String get frontingAddCoFronterTitle;

  /// Section header when selecting the primary fronter
  ///
  /// In en, this message translates to:
  /// **'Select Fronter'**
  String get frontingSelectFronter;

  /// Section header when selecting a member in co-front mode
  ///
  /// In en, this message translates to:
  /// **'Select {term}'**
  String frontingSelectMember(String term);

  /// Toggle label to switch between new session and co-front mode
  ///
  /// In en, this message translates to:
  /// **'Co-front'**
  String get frontingCoFrontToggle;

  /// Section header for co-fronter selection in add session sheet
  ///
  /// In en, this message translates to:
  /// **'Co-Fronters'**
  String get frontingCoFronters;

  /// Empty state when no other members are available to add as co-fronters
  ///
  /// In en, this message translates to:
  /// **'No other {term} available'**
  String frontingNoOtherMembers(String term);

  /// Hint text shown in co-front mode on the add session sheet
  ///
  /// In en, this message translates to:
  /// **'Tap a {term} to add them to the co-front of the current session.'**
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
  /// **'Error adding co-fronter: {error}'**
  String frontingErrorAddingCoFronter(Object error);

  /// Error toast when creating a fronting session fails
  ///
  /// In en, this message translates to:
  /// **'Error creating session: {error}'**
  String frontingErrorCreatingSession(Object error);

  /// Header title on the add co-fronters bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Add Co-Fronters'**
  String get frontingAddCoFrontersTitle;

  /// Error toast when adding co-fronters fails
  ///
  /// In en, this message translates to:
  /// **'Error adding co-fronters: {error}'**
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
  /// **'Co-Fronters'**
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

  /// Screen title for the timeline sanitization screen
  ///
  /// In en, this message translates to:
  /// **'Timeline Sanitization'**
  String get frontingSanitizationTitle;

  /// Text shown while the sanitization scan is running
  ///
  /// In en, this message translates to:
  /// **'Scanning timeline…'**
  String get frontingSanitizationScanning;

  /// Title on the initial state of sanitization screen
  ///
  /// In en, this message translates to:
  /// **'Timeline Sanitization'**
  String get frontingSanitizationIntroTitle;

  /// Description on the initial state of sanitization screen
  ///
  /// In en, this message translates to:
  /// **'Scan your fronting history for overlapping, duplicate, or invalid sessions, then apply automatic fixes.'**
  String get frontingSanitizationIntroBody;

  /// Button to start a sanitization scan
  ///
  /// In en, this message translates to:
  /// **'Scan Timeline'**
  String get frontingSanitizationScanButton;

  /// Empty state title when no issues are found
  ///
  /// In en, this message translates to:
  /// **'Timeline looks clean!'**
  String get frontingSanitizationCleanTitle;

  /// Empty state subtitle when no issues are found
  ///
  /// In en, this message translates to:
  /// **'No overlaps, duplicates, or invalid sessions found.'**
  String get frontingSanitizationCleanSubtitle;

  /// Button to run a new scan after viewing results
  ///
  /// In en, this message translates to:
  /// **'Scan Again'**
  String get frontingSanitizationScanAgain;

  /// Summary banner showing total issues found
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Found 1 issue in your timeline.} other{Found {count} issues in your timeline.}}'**
  String frontingSanitizationIssuesFound(int count);

  /// Banner showing number of fixes applied
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 fix applied successfully.} other{{count} fixes applied successfully.}}'**
  String frontingSanitizationFixesApplied(int count);

  /// Error toast when a scan fails
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {error}'**
  String frontingSanitizationScanFailed(Object error);

  /// Error toast when applying a fix fails
  ///
  /// In en, this message translates to:
  /// **'Fix failed: {error}'**
  String frontingSanitizationFixFailed(Object error);

  /// Error toast when fix options cannot be loaded
  ///
  /// In en, this message translates to:
  /// **'Could not load fix options: {error}'**
  String frontingSanitizationLoadFixFailed(Object error);

  /// Sheet title for fix options
  ///
  /// In en, this message translates to:
  /// **'Fix Options'**
  String get frontingSanitizationFixOptionsTitle;

  /// Message shown when no automated fix plans are available
  ///
  /// In en, this message translates to:
  /// **'No automated fixes available for this issue.\nPlease review and resolve it manually.'**
  String get frontingSanitizationNoAutoFix;

  /// Button label to show fix preview
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get frontingSanitizationPreview;

  /// Button label to hide fix preview
  ///
  /// In en, this message translates to:
  /// **'Hide Preview'**
  String get frontingSanitizationHidePreview;

  /// Button label to apply a fix plan
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get frontingSanitizationApply;

  /// Issue type chip label: overlap
  ///
  /// In en, this message translates to:
  /// **'Overlap'**
  String get frontingIssueTypeOverlap;

  /// Issue type chip label: gap
  ///
  /// In en, this message translates to:
  /// **'Gap'**
  String get frontingIssueTypeGap;

  /// Issue type chip label: duplicate
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get frontingIssueTypeDuplicate;

  /// Issue type chip label: mergeable adjacent
  ///
  /// In en, this message translates to:
  /// **'Mergeable'**
  String get frontingIssueTypeMergeable;

  /// Issue type chip label: invalid range
  ///
  /// In en, this message translates to:
  /// **'Invalid Range'**
  String get frontingIssueTypeInvalidRange;

  /// Issue type chip label: future session
  ///
  /// In en, this message translates to:
  /// **'Future Session'**
  String get frontingIssueTypeFutureSession;

  /// Section header for overlapping issues in sanitization results
  ///
  /// In en, this message translates to:
  /// **'Overlapping Sessions'**
  String get frontingIssueSectionOverlap;

  /// Section header for gap issues in sanitization results
  ///
  /// In en, this message translates to:
  /// **'Gaps'**
  String get frontingIssueSectionGap;

  /// Section header for duplicate issues in sanitization results
  ///
  /// In en, this message translates to:
  /// **'Duplicates'**
  String get frontingIssueSectionDuplicate;

  /// Section header for mergeable adjacent issues in sanitization results
  ///
  /// In en, this message translates to:
  /// **'Mergeable Adjacent'**
  String get frontingIssueSectionMergeable;

  /// Section header for invalid range issues in sanitization results
  ///
  /// In en, this message translates to:
  /// **'Invalid Ranges'**
  String get frontingIssueSectionInvalidRange;

  /// Section header for future session issues in sanitization results
  ///
  /// In en, this message translates to:
  /// **'Future Sessions'**
  String get frontingIssueSectionFutureSession;

  /// Session count shown on a validation issue tile
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String frontingIssueSessionCount(int count);

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
  /// **'Create co-fronting session'**
  String get frontingOverlapCoFrontOption;

  /// Subtitle for co-fronting overlap resolution option
  ///
  /// In en, this message translates to:
  /// **'Split the overlapping time into shared co-fronting segments.'**
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
  /// **'Recent Sessions'**
  String get memberSectionRecentSessions;

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

  /// Section header shown above member bio/notes field on detail screen
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get memberSectionBio;

  /// Tooltip for edit member button
  ///
  /// In en, this message translates to:
  /// **'Edit member'**
  String get memberEditTooltip;

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
  /// **'Create groups to organize your system {termPlural}'**
  String memberGroupEmptySubtitle(String termPlural);

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

  /// Sheet title for headmate selection in note sheet
  ///
  /// In en, this message translates to:
  /// **'Choose Headmate'**
  String get memberNoteChooseHeadmate;

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

  /// Section header for members inside a group detail screen
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get memberGroupSectionMembers;

  /// Button label to add a member to a group
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get memberGroupAddMember;

  /// Confirmation dialog title when deleting a group
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get memberGroupDeleteTitle;

  /// Confirmation dialog message when deleting a group
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? Members will not be deleted.'**
  String memberGroupDeleteMessage(String name);

  /// Confirm button for group deletion dialog
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get memberGroupDeleteConfirm;

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

  /// Label for the group color hex text field
  ///
  /// In en, this message translates to:
  /// **'Color (hex)'**
  String get memberGroupColorLabel;

  /// Error toast when saving a group fails
  ///
  /// In en, this message translates to:
  /// **'Error saving group: {error}'**
  String memberGroupErrorSaving(Object error);

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
  /// **'Optional'**
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
  /// **'Admins can manage system settings'**
  String get memberAdminSubtitle;

  /// Switch label: custom color
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get memberCustomColorTitle;

  /// Switch subtitle: custom color
  ///
  /// In en, this message translates to:
  /// **'Use a personal color for this member'**
  String get memberCustomColorSubtitle;

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

  /// Age displayed on member detail screen
  ///
  /// In en, this message translates to:
  /// **'Age {age}'**
  String memberAgeDisplay(int age);

  /// Bulk selection count label in system management screen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String memberSelectedCount(int count);

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

  /// Empty state title when there are no conversations
  ///
  /// In en, this message translates to:
  /// **'No conversations'**
  String get chatNoConversations;

  /// Empty state subtitle when there are no conversations
  ///
  /// In en, this message translates to:
  /// **'Start chatting with your system'**
  String get chatNoConversationsSubtitle;

  /// Error message when conversations fail to load
  ///
  /// In en, this message translates to:
  /// **'Error loading conversations'**
  String get chatErrorLoadingConversations;

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

  /// Semantics label for the record voice note button
  ///
  /// In en, this message translates to:
  /// **'Record voice note'**
  String get chatRecordVoiceNote;

  /// Semantics label for the speaking-as avatar button
  ///
  /// In en, this message translates to:
  /// **'Speaking as {name}. Double tap to change.'**
  String chatSpeakingAs(String name);

  /// Semantics label for the speaking-as button when no member is selected
  ///
  /// In en, this message translates to:
  /// **'Choose speaking member'**
  String get chatChooseSpeakingMember;

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
  /// **'Add members'**
  String get chatInfoAddMembers;

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
  /// **'Unknown Member'**
  String get chatInfoUnknownMember;

  /// Error text when a participant member fails to load
  ///
  /// In en, this message translates to:
  /// **'Error loading member'**
  String get chatInfoErrorLoadingMember;

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
  /// **'Add Members'**
  String get chatAddMembersTitle;

  /// Message when all members are already participants
  ///
  /// In en, this message translates to:
  /// **'All active members are already in this conversation.'**
  String get chatAddMembersAllAdded;

  /// Toast when adding members fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add members: {error}'**
  String chatAddMembersFailed(Object error);

  /// Sheet title for creating a new conversation
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get chatCreateTitle;

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
  /// **'e.g., System Discussion'**
  String get chatCreateGroupNameHint;

  /// Header for participant selection in group chat creation
  ///
  /// In en, this message translates to:
  /// **'Select participants (2+)'**
  String get chatCreateSelectParticipants;

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
  /// **'No members available. Create members first.'**
  String get chatCreateNoMembers;

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
  /// **'No members available'**
  String get chatNoMembersAvailable;

  /// Short error text in speaking-as picker
  ///
  /// In en, this message translates to:
  /// **'Error loading members'**
  String get chatErrorLoadingMembersShort;

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

  /// Lead statement on the encryption and privacy screen
  ///
  /// In en, this message translates to:
  /// **'Your data is encrypted on this device with keys only your PIN can unlock.'**
  String get encryptionPrivacyIntroTitle;

  /// Supporting body text on the encryption and privacy screen
  ///
  /// In en, this message translates to:
  /// **'Even if someone copies this device\'s storage, they can\'t read your data without your PIN and recovery phrase.'**
  String get encryptionPrivacyIntroBody;

  /// Zero-knowledge sync note on the encryption and privacy screen
  ///
  /// In en, this message translates to:
  /// **'When sync is enabled, data is encrypted on your device before it leaves. The server only stores encrypted blobs it cannot read.'**
  String get encryptionPrivacySyncNote;

  /// Expandable section title on the encryption and privacy screen
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get encryptionPrivacyHowItWorks;

  /// Technical item title for database encryption details
  ///
  /// In en, this message translates to:
  /// **'Database encryption'**
  String get encryptionPrivacyDatabaseTitle;

  /// Technical item body for database encryption details
  ///
  /// In en, this message translates to:
  /// **'HKDF-SHA256(DEK, DeviceSecret) — per-device, PIN-derived key. Your device generates this key; no server ever sees it.'**
  String get encryptionPrivacyDatabaseBody;

  /// Technical item title for message encryption details
  ///
  /// In en, this message translates to:
  /// **'Message encryption'**
  String get encryptionPrivacyMessageTitle;

  /// Technical item body for message encryption details
  ///
  /// In en, this message translates to:
  /// **'XChaCha20-Poly1305 with per-message keys derived from your Data Encryption Key (DEK).'**
  String get encryptionPrivacyMessageBody;

  /// Technical item title for post-quantum identity details
  ///
  /// In en, this message translates to:
  /// **'Post-quantum device identity'**
  String get encryptionPrivacyPostQuantumTitle;

  /// Technical item body for post-quantum identity details
  ///
  /// In en, this message translates to:
  /// **'ML-KEM-768 (key exchange) and ML-DSA-65 (signatures) protect against future quantum attacks on device authentication.'**
  String get encryptionPrivacyPostQuantumBody;

  /// Technical item title for recovery details
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get encryptionPrivacyRecoveryTitle;

  /// Technical item body for recovery details
  ///
  /// In en, this message translates to:
  /// **'Your 12-word BIP39 recovery phrase re-derives all keys. Store it somewhere safe — it is the only way to recover your data if you lose your PIN.'**
  String get encryptionPrivacyRecoveryBody;

  /// Semantics label for a member avatar image
  ///
  /// In en, this message translates to:
  /// **'{name} avatar'**
  String memberAvatarSemantics(String name);

  /// Fallback semantics label for a member avatar image
  ///
  /// In en, this message translates to:
  /// **'Member avatar'**
  String get memberAvatarSemanticsUnnamed;

  /// Semantics label for an image inside a grouped member avatar
  ///
  /// In en, this message translates to:
  /// **'Group member avatar'**
  String get groupMemberAvatarSemantics;

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

  /// Default onboarding channel: group chat visible to all members (cannot be removed)
  ///
  /// In en, this message translates to:
  /// **'All Members'**
  String get onboardingChatChannelAllMembers;

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

  /// Helper text below the only-notify-when-fronting toggle
  ///
  /// In en, this message translates to:
  /// **'Reminders will fire even if this member isn\'t fronting — fronting-aware delivery requires background access.'**
  String get habitsOnlyFrontingCaveat;

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

  /// Reminder subtitle for daily repeat interval
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get remindersSubtitleDaily;

  /// Reminder subtitle for every N days repeat interval
  ///
  /// In en, this message translates to:
  /// **'Every {days} days'**
  String remindersSubtitleEveryNDays(int days);

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

  /// App name headline in the About section
  ///
  /// In en, this message translates to:
  /// **'Prism'**
  String get settingsAboutAppName;

  /// Tagline shown below the app name in About
  ///
  /// In en, this message translates to:
  /// **'Plural system management'**
  String get settingsAboutTagline;

  /// App version string in About section
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsAboutVersion(String version);

  /// Description paragraph in the About section
  ///
  /// In en, this message translates to:
  /// **'A privacy-focused app for managing plural systems. Track fronting, communicate between headmates, and keep your system organized.'**
  String get settingsAboutDescription;

  /// GitHub chip label in About section
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get settingsAboutGitHub;

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

  /// Toast shown when GitHub chip is tapped
  ///
  /// In en, this message translates to:
  /// **'GitHub link coming soon'**
  String get settingsAboutGitHubComingSoon;

  /// Toast shown when Privacy chip is tapped
  ///
  /// In en, this message translates to:
  /// **'Privacy policy coming soon'**
  String get settingsAboutPrivacyComingSoon;

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
  /// **'Add fields to track custom attributes for each member'**
  String get settingsCustomFieldsEmptySubtitle;

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
  /// **'Members'**
  String get settingsDataBrowserTabMembers;

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
  /// **'No members'**
  String get settingsDataBrowserNoMembers;

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
  /// **'Sync Event Log'**
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

  /// Header title for the onboarding welcome step
  ///
  /// In en, this message translates to:
  /// **'Welcome to Prism'**
  String get onboardingWelcomeTitle;

  /// Header subtitle for the onboarding welcome step
  ///
  /// In en, this message translates to:
  /// **'Your system, your way.'**
  String get onboardingWelcomeSubtitle;

  /// Link on welcome step to enter sync-from-device flow before PIN setup
  ///
  /// In en, this message translates to:
  /// **'I already use Prism on another device'**
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
  /// **'Your imported system is ready to use'**
  String get onboardingImportedDataReadySubtitle;

  /// Header title for the onboarding import-data step
  ///
  /// In en, this message translates to:
  /// **'Already have data?'**
  String get onboardingImportDataTitle;

  /// Header subtitle for the onboarding import-data step
  ///
  /// In en, this message translates to:
  /// **'Bring your system with you.'**
  String get onboardingImportDataSubtitle;

  /// Header title for the onboarding system-name step
  ///
  /// In en, this message translates to:
  /// **'Name your system'**
  String get onboardingSystemNameTitle;

  /// Header subtitle for the onboarding system-name step
  ///
  /// In en, this message translates to:
  /// **'Whatever feels right.'**
  String get onboardingSystemNameSubtitle;

  /// Header title for the onboarding add-members step
  ///
  /// In en, this message translates to:
  /// **'Who\'s here?'**
  String get onboardingAddMembersTitle;

  /// Header subtitle for the onboarding add-members step
  ///
  /// In en, this message translates to:
  /// **'Add the people in your system.'**
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

  /// Header title for the onboarding chat-setup step
  ///
  /// In en, this message translates to:
  /// **'Set up chat'**
  String get onboardingChatSetupTitle;

  /// Header subtitle for the onboarding chat-setup step
  ///
  /// In en, this message translates to:
  /// **'Channels for your system to talk.'**
  String get onboardingChatSetupSubtitle;

  /// Header title for the onboarding preferences step
  ///
  /// In en, this message translates to:
  /// **'Make it yours'**
  String get onboardingPreferencesTitle;

  /// Header subtitle for the onboarding preferences step
  ///
  /// In en, this message translates to:
  /// **'Colors, language, the small things.'**
  String get onboardingPreferencesSubtitle;

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
  /// **'We\'ll let you know when headmates log a switch or a habit reminder is due'**
  String get onboardingPermissionsNotificationRationale;

  /// Title for microphone permission request in onboarding
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get onboardingPermissionsMicrophoneTitle;

  /// Rationale for requesting microphone permission
  ///
  /// In en, this message translates to:
  /// **'So you can record voice messages for your headmates'**
  String get onboardingPermissionsMicrophoneRationale;

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
  /// **'Your system is set up. Here\'s what to explore.'**
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
  /// **'Add your first system {term} to get started'**
  String terminologyAddFirstSubtitle(String term);

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
  /// **'Write these 12 words somewhere safe. They\'re the only way to recover your data if you lose your PIN.'**
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

  /// Message shown in the backup reminder info banner on the home screen
  ///
  /// In en, this message translates to:
  /// **'Have you backed up your recovery phrase?'**
  String get backupReminderBannerText;

  /// Action button label on the backup reminder banner
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get backupReminderBannerAction;
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
