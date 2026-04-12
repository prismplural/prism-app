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

  /// Member picker placeholder when no member is selected
  ///
  /// In en, this message translates to:
  /// **'Select member'**
  String get selectMember;

  /// Member picker placeholder for multi-select
  ///
  /// In en, this message translates to:
  /// **'Select members'**
  String get selectMembers;

  /// Member picker hint text
  ///
  /// In en, this message translates to:
  /// **'Select a member'**
  String get selectAMember;

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

  /// Search hint in member search
  ///
  /// In en, this message translates to:
  /// **'Search members...'**
  String get searchMembers;

  /// Empty state in member search
  ///
  /// In en, this message translates to:
  /// **'No members found'**
  String get noMembersFound;

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
  /// **'Per-Member Colors'**
  String get appearancePerMemberColors;

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

  /// Fronting pill label in the appearance preview card
  ///
  /// In en, this message translates to:
  /// **'Fronting'**
  String get appearanceFronting;

  /// Label shown below accent color picker when Material You is active
  ///
  /// In en, this message translates to:
  /// **'Using your system color palette'**
  String get appearanceUsingSystemPalette;

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

  /// Settings row title: change sync password
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get syncChangePassword;

  /// Settings row subtitle: change sync password
  ///
  /// In en, this message translates to:
  /// **'Update your sync encryption password'**
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

  /// Sync setup screen title: password step
  ///
  /// In en, this message translates to:
  /// **'Create Password'**
  String get syncSetupPasswordTitle;

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

  /// Intro text for the sync setup password step
  ///
  /// In en, this message translates to:
  /// **'Create a password to protect your encryption keys.'**
  String get syncSetupPasswordIntro;

  /// Help text below password intro
  ///
  /// In en, this message translates to:
  /// **'You\'ll need this password each time you set up a new device.'**
  String get syncSetupPasswordHelp;

  /// Label for password field in sync setup
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get syncSetupPasswordLabel;

  /// Label for confirm password field in sync setup
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get syncSetupConfirmPasswordLabel;

  /// Continue button on sync setup password step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get syncSetupContinueButton;

  /// Complete button on sync setup secret key step
  ///
  /// In en, this message translates to:
  /// **'Complete setup'**
  String get syncSetupCompleteButton;

  /// Validation error: password too short
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get syncSetupPasswordTooShort;

  /// Validation error: passwords do not match
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get syncSetupPasswordMismatch;

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

  /// Sheet title when verifying password to reveal key
  ///
  /// In en, this message translates to:
  /// **'Verify Password'**
  String get syncVerifyPasswordTitle;

  /// Prompt text in verify password sheet
  ///
  /// In en, this message translates to:
  /// **'Enter your sync password to reveal your 12-word recovery phrase.'**
  String get syncVerifyPasswordPrompt;

  /// Hint text for sync password field
  ///
  /// In en, this message translates to:
  /// **'Sync password'**
  String get syncPasswordHint;

  /// Tooltip for show password icon button
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get syncShowPassword;

  /// Tooltip for hide password icon button
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get syncHidePassword;

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

  /// Error when password verification fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again.'**
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
  /// **'Total members'**
  String get statisticsTotalMembers;

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
  /// **'{count} sessions'**
  String statisticsSessions(int count);

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

  /// Pill label for the current device
  ///
  /// In en, this message translates to:
  /// **'This Device'**
  String get devicesThisDevicePill;

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

  /// Tooltip for revoke device button
  ///
  /// In en, this message translates to:
  /// **'Revoke device'**
  String get devicesRevokeDevice;

  /// Toast after copying device ID
  ///
  /// In en, this message translates to:
  /// **'Device ID copied'**
  String get devicesDeviceCopied;

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
  /// **'Internal messaging between system members.'**
  String get featureChatDescription;

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
  /// **'In-system messaging between members'**
  String get featureChatEnableSubtitle;

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
  /// **'Track recurring tasks and build streaks with your system members.'**
  String get featureHabitsDescription;

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
  /// **'A personal journal for system members. Disabling hides notes from navigation but keeps existing entries.'**
  String get featureNotesDescription;

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
