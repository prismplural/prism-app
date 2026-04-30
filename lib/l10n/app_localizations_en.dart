// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get confirm => 'Confirm';

  @override
  String get back => 'Back';

  @override
  String get options => 'Options';

  @override
  String get activate => 'Activate';

  @override
  String get deactivate => 'Deactivate';

  @override
  String get loading => 'Loading…';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get search => 'Search';

  @override
  String get error => 'Error';

  @override
  String get suggestions => 'Suggestions:';

  @override
  String get unknown => 'Unknown';

  @override
  String get tapToSet => 'Tap to set';

  @override
  String get navigationBar => 'Navigation bar';

  @override
  String get mainNavigation => 'Main navigation';

  @override
  String get closeMenu => 'Close menu';

  @override
  String get moreTabs => 'More tabs';

  @override
  String navUnreadCount(String label, int count) {
    return '$label, $count unread';
  }

  @override
  String errorLoadingMembers(String members, Object error) {
    return 'Error loading $members: $error';
  }

  @override
  String selectMember(String term) {
    return 'Select $term';
  }

  @override
  String selectMembers(String termPlural) {
    return 'Select $termPlural';
  }

  @override
  String selectAMember(String termLower) {
    return 'Select a $termLower';
  }

  @override
  String errorWithDetail(Object detail) {
    return 'Error: $detail';
  }

  @override
  String get segmentedControl => 'Segmented control';

  @override
  String get dismissNotification => 'Dismiss notification';

  @override
  String get searchEmoji => 'Search emoji...';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get destructiveAction => 'Destructive action';

  @override
  String noMembersFound(String termPlural) {
    return 'No $termPlural found';
  }

  @override
  String get moreOptions => 'More options';

  @override
  String get settingsSectionSystem => 'System';

  @override
  String get settingsSectionApp => 'App';

  @override
  String get settingsSectionData => 'Data';

  @override
  String get settingsSystemInformation => 'System Information';

  @override
  String get settingsGroups => 'Groups';

  @override
  String get settingsCustomFields => 'Custom Fields';

  @override
  String get settingsStatistics => 'Statistics';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsNavigation => 'Navigation';

  @override
  String get settingsFeatures => 'Features';

  @override
  String get settingsPrivacySecurity => 'Privacy & Security';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsSync => 'Prism Sync';

  @override
  String get settingsSharing => 'Sharing';

  @override
  String get settingsImportExport => 'Import & Export';

  @override
  String get settingsResetData => 'Reset Data';

  @override
  String get settingsAbout => 'About Prism';

  @override
  String get settingsDebug => 'Debug';

  @override
  String get settingsFallbackSystemName => 'My System';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Follows your device settings';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceBrightness => 'Brightness';

  @override
  String get appearanceStyle => 'Style';

  @override
  String get appearanceUsesSystemPalette => 'Uses your system color palette';

  @override
  String get appearanceCornerStyleTitle => 'Corner style';

  @override
  String get appearanceCornerStyleRounded => 'Rounded';

  @override
  String get appearanceCornerStyleAngular => 'Angular';

  @override
  String get appearanceCornerStyleDescription =>
      'Choose between rounded or angular corners throughout the app.';

  @override
  String get appearanceAccentColor => 'Accent Color';

  @override
  String appearancePerMemberColors(String term) {
    return 'Per-$term Colors';
  }

  @override
  String appearancePerMemberColorsSwitchTitle(String term) {
    return 'Per-$term accent colors';
  }

  @override
  String appearancePerMemberColorsSwitchSubtitle(String term) {
    return 'Allow each $term to have their own color';
  }

  @override
  String get appearanceSyncSection => 'Sync';

  @override
  String get appearanceSyncThemeTitle => 'Sync theme across devices';

  @override
  String get appearanceSyncThemeSubtitle =>
      'Share brightness, style, and accent color via sync';

  @override
  String get appearanceTerminology => 'Terminology';

  @override
  String get appearanceLanguage => 'Language';

  @override
  String get appearanceLanguageSystem => 'System default';

  @override
  String get appearanceLanguageFooter => 'More languages coming soon';

  @override
  String get appearancePreview => 'Preview';

  @override
  String get appearanceSamplePronouns => 'she/her';

  @override
  String appearanceSampleMember(String term) {
    return 'Sample $term';
  }

  @override
  String get appearanceFronting => 'Fronting';

  @override
  String get syncTitle => 'Prism Sync';

  @override
  String get syncDisconnectedTitle => 'Sync was disconnected';

  @override
  String get syncDisconnectedMessage =>
      'Set up sync again to reconnect your devices.';

  @override
  String get syncSetUpSyncButton => 'Set Up Sync';

  @override
  String get syncUnableToLoad => 'Unable to load sync settings';

  @override
  String get syncNotSetUp => 'Sync is not set up';

  @override
  String get syncNotSetUpDescription =>
      'Set up end-to-end encrypted sync to keep your data in sync across all your devices.';

  @override
  String get syncSetupButton => 'Set up sync';

  @override
  String get syncNowTitle => 'Sync now';

  @override
  String get syncNowSubtitle => 'Check for changes and push local updates';

  @override
  String get syncInProgress => 'Syncing…';

  @override
  String get syncSetUpAnotherDevice => 'Set up another device';

  @override
  String get syncSetUpAnotherDeviceSubtitle => 'Generate a pairing QR code';

  @override
  String get syncManageDevices => 'Manage Devices';

  @override
  String get syncManageDevicesSubtitle => 'View and revoke linked devices';

  @override
  String get syncChangePassword => 'Change PIN';

  @override
  String get syncChangePasswordSubtitle => 'Update your sync encryption PIN';

  @override
  String get syncViewSecretKey => 'View Secret Key';

  @override
  String get syncViewSecretKeySubtitle => 'Show your 12-word recovery phrase';

  @override
  String get syncPreferencesSection => 'Sync Preferences';

  @override
  String get syncPreferencesDescription =>
      'Control what settings are shared across your devices via sync.';

  @override
  String get syncNavigationLayoutTitle => 'Sync navigation layout';

  @override
  String get syncNavigationLayoutSubtitle =>
      'Share tab arrangement across devices';

  @override
  String get syncAppearanceToggleTitle => 'Sync appearance across devices';

  @override
  String get syncAppearanceToggleDescription =>
      'Share theme, accent color, and corner style between your paired devices.';

  @override
  String get syncIgnoreAppearanceTitle =>
      'Ignore synced appearance on this device';

  @override
  String get syncIgnoreAppearanceDescription =>
      'Use local appearance settings on this device. Edits made here still sync to other devices if sharing is on.';

  @override
  String get navigationShowViewToggleTitle => 'Show view toggle in Home';

  @override
  String get navigationShowViewToggleSubtitle =>
      'Display the timeline / list toggle button in the Home tab top bar.';

  @override
  String get syncIssuesSection => 'Sync Issues';

  @override
  String get syncIssuesDescription =>
      'These records could not be applied due to data type mismatches. Clearing them removes the warning indicator.';

  @override
  String get syncClearAll => 'Clear all';

  @override
  String get syncDetailsSection => 'Details';

  @override
  String get syncRelayLabel => 'Relay';

  @override
  String get syncIdLabel => 'Sync ID';

  @override
  String get syncNodeIdLabel => 'Node ID';

  @override
  String get syncNodeIdNotInitialised => 'Not initialised';

  @override
  String get syncTroubleshootingLink => 'Troubleshooting';

  @override
  String get syncLast24h => 'Synced last 24h';

  @override
  String get syncTotal => 'Total synced';

  @override
  String syncEntitiesCount(int count) {
    return '$count entities';
  }

  @override
  String get syncFinished => 'Sync finished';

  @override
  String syncFailed(Object error) {
    return 'Sync failed: $error';
  }

  @override
  String get syncStatusError => 'Sync error';

  @override
  String get syncStatusSyncing => 'Syncing';

  @override
  String get syncStatusSyncInProgress => 'Sync in progress…';

  @override
  String get syncStatusSyncedWithIssues => 'Synced with issues';

  @override
  String get syncStatusLastSynced => 'Last synced';

  @override
  String get syncStatusReadyToSync => 'Ready to sync';

  @override
  String get syncStatusWaiting => 'Waiting for changes.';

  @override
  String get syncStatusNeedsReconnect => 'Needs reconnect';

  @override
  String get syncStatusTapToReconnect => 'Tap Sync Now to reconnect.';

  @override
  String get syncRealTimeConnected => 'Real-time connected';

  @override
  String get syncRealTimeDisconnected => 'Real-time disconnected';

  @override
  String get syncJustNow => 'Just now';

  @override
  String syncMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String syncHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String syncDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get syncSetupIntroTitle => 'Set Up Sync';

  @override
  String get syncSetupSecretKeyTitle => 'Your Secret Key';

  @override
  String get syncSetupIntroHeadline =>
      'Keep your data in sync across all your devices.';

  @override
  String get syncSetupIntroBody =>
      'Everything is end-to-end encrypted — the server never sees your data. You\'ll create a password and receive a recovery key to keep safe. You\'ll need your 12-word recovery phrase to continue. Have it ready.';

  @override
  String get syncSetupSelfHosted => 'Self-hosted relay?';

  @override
  String get syncSetupRelayUrlLabel => 'Relay URL';

  @override
  String get syncSetupRegistrationToken => 'Registration token';

  @override
  String get syncSetupRegistrationTokenHint => 'Optional';

  @override
  String get syncSetupRegistrationTokenHelp =>
      'Required if your relay has registration gating enabled.';

  @override
  String get syncSetupRelayUrlError => 'Relay URL must start with https://';

  @override
  String get syncSetupCompleteButton => 'Complete setup';

  @override
  String get syncSetupPinLabel => 'App PIN';

  @override
  String get syncSetupProgressCreatingGroup => 'Creating sync group...';

  @override
  String get syncSetupProgressConfiguringEngine => 'Configuring encryption...';

  @override
  String get syncSetupProgressCachingKeys => 'Securing keys...';

  @override
  String get syncSetupProgressBootstrapping => 'Preparing your data for sync';

  @override
  String get syncSetupProgressMeasuringSnapshot => 'Checking data size';

  @override
  String get syncSecretKeyTitle => 'Secret Key';

  @override
  String get syncSecretKeyNotStoredTitle => 'Recovery phrase not stored';

  @override
  String get syncSecretKeyNotStoredBody =>
      'Your recovery phrase is not stored on this device — it was shown once during setup.\n\nIf you saved it (for example, in a password manager or on a piece of paper), check there.\n\nIf you can\'t find it, disconnect this device and re-pair to generate a new phrase.';

  @override
  String get syncVerifyPasswordTitle => 'Verify PIN';

  @override
  String get syncVerifyPasswordPrompt =>
      'Enter your app PIN to reveal your 12-word recovery phrase.';

  @override
  String get syncPasswordHint => 'PIN';

  @override
  String get syncRevealSecretKey => 'Reveal Secret Key';

  @override
  String get syncSecretKeyNotFound => 'Secret Key not found in keychain.';

  @override
  String get syncEngineNotAvailable => 'Sync engine not available.';

  @override
  String get syncIncorrectPassword => 'Incorrect PIN. Please try again.';

  @override
  String syncAnErrorOccurred(Object error) {
    return 'An error occurred: $error';
  }

  @override
  String get privacySecurityTitle => 'Privacy & Security';

  @override
  String get pinLockSection => 'PIN Lock';

  @override
  String get pinLockEnableTitle => 'Enable PIN Lock';

  @override
  String get pinLockEnableSubtitle => 'Require a PIN to open the app';

  @override
  String get pinLockBiometricSection => 'Biometric';

  @override
  String get pinLockBiometricTitle => 'Biometric Unlock';

  @override
  String get pinLockBiometricSubtitle => 'Use Face ID or fingerprint to unlock';

  @override
  String get pinLockBiometricDisabledSubtitle =>
      'Enable PIN Lock to use biometric unlock';

  @override
  String get pinLockAutoLockSection => 'Auto-Lock';

  @override
  String get pinLockAfterLeaving => 'Lock after leaving the app';

  @override
  String get pinLockManageSection => 'Manage';

  @override
  String get pinLockChange => 'Change PIN';

  @override
  String get pinLockRemove => 'Remove PIN';

  @override
  String get pinLockSetTitle => 'Set PIN';

  @override
  String get pinLockConfirmTitle => 'Confirm PIN';

  @override
  String get pinLockEnterTitle => 'Enter PIN';

  @override
  String get pinLockSetSubtitle => 'Choose a 6-digit PIN';

  @override
  String get pinLockConfirmSubtitle => 'Re-enter your PIN to confirm';

  @override
  String get pinLockUnlockSubtitle => 'Enter your PIN to unlock';

  @override
  String get pinLockInstant => 'Instant';

  @override
  String get pinLock15s => '15s';

  @override
  String get pinLock1m => '1m';

  @override
  String get pinLock5m => '5m';

  @override
  String get pinLock15m => '15m';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsFrontingRemindersTitle => 'Fronting reminders';

  @override
  String get notificationsFrontingRemindersSubtitle =>
      'Get reminded to log fronting changes';

  @override
  String get notificationsReminderIntervalTitle => 'Reminder interval';

  @override
  String get notificationsReminderIntervalSubtitle =>
      'How often to send reminders';

  @override
  String get notificationsChatSection => 'Chat Notifications';

  @override
  String get notificationsBadgeAllMessages => 'Badge for all messages';

  @override
  String notificationsBadgeMentionsOnly(String member) {
    return 'Only @mentions will badge for $member';
  }

  @override
  String notificationsBadgeAllFor(String member) {
    return 'All new messages will badge for $member';
  }

  @override
  String get notificationsPermissionStatus => 'Permission status';

  @override
  String get notificationsCouldNotCheck => 'Could not check permissions';

  @override
  String get notificationsEnabled => 'Notifications enabled';

  @override
  String get notificationsPermissionGranted => 'Permission granted';

  @override
  String get notificationsNotEnabled => 'Notifications not enabled';

  @override
  String get notificationsPermissionRequired =>
      'Permission required for reminders';

  @override
  String get notificationsRequest => 'Request';

  @override
  String get notificationsAboutText =>
      'Fronting reminders send periodic notifications to help you stay aware of who is fronting. This can be useful for logging switches and maintaining awareness throughout the day.';

  @override
  String get notificationsAndroidFootnote =>
      'On Android, reminders may arrive a few minutes late.';

  @override
  String get notificationsInterval15m => '15 minutes';

  @override
  String get notificationsInterval30m => '30 minutes';

  @override
  String get notificationsInterval1h => '1 hour';

  @override
  String get notificationsInterval2h => '2 hours';

  @override
  String get notificationsInterval4h => '4 hours';

  @override
  String get notificationsInterval8h => '8 hours';

  @override
  String get resetDataTitle => 'Reset Data';

  @override
  String get resetDataCategoriesSection => 'Categories';

  @override
  String get resetDataCategoriesDescription =>
      'Reset specific categories of data on this device. Sync System reset wipes sync setup without deleting your app data.';

  @override
  String get resetDataDangerZone => 'Danger Zone';

  @override
  String resetDataConfirmTitle(String category) {
    return 'Reset $category?';
  }

  @override
  String resetDataConfirmAll(String termPluralLower) {
    return 'This will permanently delete all your data including $termPluralLower, fronting sessions, messages, polls, habits, sleep data, and settings. This action cannot be undone.';
  }

  @override
  String get resetDataConfirmSync =>
      'This keeps your local app data, but removes sync keys, relay configuration, device identity, and sync history from this device. You will need to set up sync again afterward.';

  @override
  String resetDataConfirmCategory(String category) {
    return 'This will permanently delete all $category data on this device. This action cannot be undone.';
  }

  @override
  String get resetDataConfirmEverything => 'Reset Everything';

  @override
  String get resetDataConfirmSync2 => 'Reset Sync';

  @override
  String resetDataSuccess(String category) {
    return '$category reset successfully';
  }

  @override
  String resetDataFailed(Object error) {
    return 'Failed to reset: $error';
  }

  @override
  String get navigationSettingsTitle => 'Navigation';

  @override
  String get navigationPreferences => 'Preferences';

  @override
  String get navigationLayoutSection => 'Layout';

  @override
  String get navigationNavBar => 'Nav Bar';

  @override
  String get navigationMoreMenu => 'More Menu';

  @override
  String get navigationAvailable => 'Available';

  @override
  String get navigationDisabledFeatures => 'Disabled Features';

  @override
  String get navigationEnableInFeatures => 'Enable in Features';

  @override
  String get navigationMoveToNavBar => 'Move to nav bar';

  @override
  String get navigationMoveToMoreMenu => 'Move to More menu';

  @override
  String get navigationRemove => 'Remove from navigation';

  @override
  String get navigationAddToNavBar => 'Add to nav bar';

  @override
  String get navigationAddToMoreMenu => 'Add to More menu';

  @override
  String get featuresTitle => 'Features';

  @override
  String get featuresDisablingHint =>
      'Disabling a feature hides it from navigation without deleting any data.';

  @override
  String get featuresEnabled => 'Enabled';

  @override
  String get featuresDisabled => 'Disabled';

  @override
  String get featureChatTitle => 'Chat';

  @override
  String get featureFrontingTitle => 'Fronting';

  @override
  String get featureHabitsTitle => 'Habits';

  @override
  String get featureSleepTitle => 'Sleep';

  @override
  String get featurePollsTitle => 'Polls';

  @override
  String get featureNotesTitle => 'Notes';

  @override
  String get featureRemindersTitle => 'Reminders';

  @override
  String get statisticsTitle => 'Statistics';

  @override
  String get statisticsOverview => 'Overview';

  @override
  String statisticsTotalMembers(String termPlural) {
    return 'Total $termPlural';
  }

  @override
  String get statisticsTotalSessions => 'Total sessions';

  @override
  String get statisticsConversations => 'Conversations';

  @override
  String get statisticsPolls => 'Polls';

  @override
  String get statisticsMostFrequentFronters => 'Most Frequent Fronters';

  @override
  String get statisticsAverageSessionDuration => 'Average Session Duration';

  @override
  String get statisticsNoFrontingData => 'No fronting data yet';

  @override
  String get statisticsNoCompletedSessions => 'No completed sessions yet';

  @override
  String statisticsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String get statisticsDurationStats => 'Duration Stats';

  @override
  String get statisticsDurationSessions => 'Sessions';

  @override
  String get statisticsDurationTotal => 'Total';

  @override
  String get statisticsDurationAverage => 'Average';

  @override
  String get statisticsDurationMedian => 'Median';

  @override
  String get statisticsDurationShortest => 'Shortest';

  @override
  String get statisticsDurationLongest => 'Longest';

  @override
  String statisticsFrontingTimeByMember(String term) {
    return 'Per-$term minutes';
  }

  @override
  String statisticsMemberMinutesAxisHint(String term) {
    return '% of system $term-minutes';
  }

  @override
  String get statisticsMedianSessionLabel => 'Median Session';

  @override
  String get statisticsGapTimeLabel => 'Gap Time';

  @override
  String get statisticsSwitchesPerDayLabel => 'Switches/Day';

  @override
  String statisticsUniqueFrontersLabel(String termPlural) {
    return 'Unique $termPlural';
  }

  @override
  String statisticsActiveMembersBreakdown(int active, int inactive) {
    return '$active active, $inactive inactive';
  }

  @override
  String get timeOfDayMorning => 'Morning';

  @override
  String get timeOfDayAfternoon => 'Afternoon';

  @override
  String get timeOfDayEvening => 'Evening';

  @override
  String get timeOfDayNight => 'Night';

  @override
  String get timeOfDayChartNoData => 'No time-of-day data';

  @override
  String timeOfDayChartSemantics(String parts) {
    return 'Time of day: $parts';
  }

  @override
  String get debugTitle => 'Debug';

  @override
  String get debugDangerZone => 'Danger Zone';

  @override
  String get debugResetDatabase => 'Reset Database';

  @override
  String get debugExportData => 'Export Data';

  @override
  String get debugComingSoon => 'Coming soon';

  @override
  String get debugStressTestingTitle => 'Stress Testing';

  @override
  String get debugStressTestingDescription =>
      'Generate large datasets for performance testing';

  @override
  String get debugGenerateStressData => 'Generate Stress Data';

  @override
  String get debugClearingStressData => 'Clearing...';

  @override
  String get debugClearStressData => 'Clear Stress Data';

  @override
  String get debugSyncState => 'Sync State';

  @override
  String get debugPendingChanges => 'Pending changes';

  @override
  String get debugLastSync => 'Last sync';

  @override
  String get debugNeverSynced => 'Never';

  @override
  String get debugOpenSyncLog => 'Open Sync Debug Log';

  @override
  String get debugBuildInfo => 'Build Info';

  @override
  String get debugCopyBuildInfo => 'Copy build info';

  @override
  String get debugBuildInfoCopied => 'Build info copied';

  @override
  String get debugAppVersion => 'App version';

  @override
  String get debugGit => 'Git';

  @override
  String get debugBranch => 'Branch';

  @override
  String get debugBuilt => 'Built';

  @override
  String get debugPackage => 'Package';

  @override
  String get debugTools => 'Tools';

  @override
  String get debugTimelineSanitization => 'Timeline Sanitization';

  @override
  String get debugTimelineSanitizationSubtitle =>
      'Scan for and fix timeline issues';

  @override
  String get debugDevice => 'Device';

  @override
  String get debugNodeId => 'Node ID';

  @override
  String get debugNodeIdUnavailable => 'Unavailable — not yet paired';

  @override
  String get debugCopyNodeId => 'Copy Node ID';

  @override
  String get debugNodeIdCopied => 'Node ID copied to clipboard';

  @override
  String get debugResetDatabaseConfirm1Title => 'Reset Database';

  @override
  String get debugResetDatabaseConfirm1Message =>
      'Are you sure you want to delete all data? This action cannot be undone.';

  @override
  String get debugResetDatabaseConfirm2Title => 'Really delete all data?';

  @override
  String debugResetDatabaseConfirm2Message(String termPluralLower) {
    return 'This will permanently erase all $termPluralLower, sessions, conversations, messages, and polls. There is no undo.';
  }

  @override
  String get debugDeleteEverything => 'Delete Everything';

  @override
  String get debugDatabaseResetSuccess => 'Database reset successfully';

  @override
  String debugFailedToReset(Object error) {
    return 'Failed to reset: $error';
  }

  @override
  String get debugSelectPreset => 'Select Preset';

  @override
  String get debugDatabaseNotEmpty => 'Database Not Empty';

  @override
  String get debugDatabaseNotEmptyMessage =>
      'Your database already has data. Stress data will be added alongside it. Continue?';

  @override
  String get debugNoStressData => 'No stress data to clear';

  @override
  String get debugClearStressDataTitle => 'Clear Stress Data';

  @override
  String get debugClearStressDataMessage =>
      'This will delete all generated stress test data. Your real data will not be affected.';

  @override
  String get debugStressDataCleared => 'Stress data cleared';

  @override
  String debugFailedToClearStress(Object error) {
    return 'Failed to clear stress data: $error';
  }

  @override
  String debugStressGenerated(String preset) {
    return '$preset stress data generated';
  }

  @override
  String debugGenerationFailed(Object error) {
    return 'Generation failed: $error';
  }

  @override
  String get errorHistoryTitle => 'Error History';

  @override
  String get errorHistoryClear => 'Clear History';

  @override
  String get errorHistoryEmpty => 'No errors recorded';

  @override
  String get errorHistoryEmptySubtitle =>
      'Errors will appear here when they occur';

  @override
  String get errorHistoryCopyTooltip => 'Copy error details';

  @override
  String get errorHistoryCopied => 'Error details copied';

  @override
  String get systemInfoTitle => 'System Information';

  @override
  String get systemInfoChangeAvatar => 'Change avatar';

  @override
  String memberChangeAvatar(String termSingularLower) {
    return 'Change $termSingularLower avatar';
  }

  @override
  String get avatarCropTitle => 'Crop avatar';

  @override
  String get systemInfoRemoveAvatar => 'Remove avatar';

  @override
  String get memberRemoveAvatar => 'Remove photo';

  @override
  String get memberProfileHeaderSectionTitle => 'Profile header';

  @override
  String get memberProfileHeaderSectionDescription =>
      'Choose the image source and layout for this profile.';

  @override
  String get memberProfileHeaderVisibleTitle => 'Show profile header';

  @override
  String get memberProfileHeaderVisibleSubtitle =>
      'Keeps the image and source saved while hiding the banner.';

  @override
  String get memberProfileHeaderSourcePluralKit => 'PluralKit';

  @override
  String get memberProfileHeaderSourcePrism => 'Prism';

  @override
  String get memberProfileHeaderSourcePluralKitHelper =>
      'Refreshed from PluralKit when Prism syncs.';

  @override
  String get memberProfileHeaderSourcePrismHelper =>
      'Private to Prism. Does not update PluralKit.';

  @override
  String get memberProfileHeaderPluralKitUnavailable =>
      'PluralKit appears after this member has a linked or cached banner.';

  @override
  String get memberProfileHeaderChangeImage => 'Change image';

  @override
  String get memberProfileHeaderRemoveImage => 'Remove image';

  @override
  String get memberProfileHeaderLayoutLabel => 'Layout';

  @override
  String get memberProfileHeaderLayoutCompact => 'Compact';

  @override
  String get memberProfileHeaderLayoutClassic => 'Classic';

  @override
  String get memberProfileHeaderCropTitle => 'Crop profile header';

  @override
  String get memberProfileHeaderProcessingError =>
      'Could not process that image.';

  @override
  String get memberNameStyleTooltip => 'Edit name style';

  @override
  String get memberNameStyleDialogTitle => 'Name style';

  @override
  String get memberNameStyleFontLabel => 'Font';

  @override
  String get memberNameStyleFontDefault => 'Default';

  @override
  String get memberNameStyleFontDisplay => 'Display';

  @override
  String get memberNameStyleFontSerif => 'Serif';

  @override
  String get memberNameStyleFontMono => 'Mono';

  @override
  String get memberNameStyleFontRounded => 'Rounded';

  @override
  String get memberNameStyleStyleLabel => 'Style';

  @override
  String get memberNameStyleBold => 'Bold';

  @override
  String get memberNameStyleItalic => 'Italic';

  @override
  String get memberNameStyleColorLabel => 'Color';

  @override
  String get memberNameStyleColorDefault => 'Default';

  @override
  String get memberNameStyleColorAccent => 'Accent';

  @override
  String get memberNameStyleColorCustom => 'Custom';

  @override
  String get memberNameStyleReset => 'Reset';

  @override
  String get systemInfoNameLabel => 'Name';

  @override
  String get systemInfoSystemNameHint => 'System name';

  @override
  String get systemInfoSaveSystemName => 'Save system name';

  @override
  String get systemInfoCancelEditing => 'Cancel editing';

  @override
  String get systemInfoDescriptionLabel => 'Description';

  @override
  String get systemInfoDescriptionHint => 'System description';

  @override
  String get systemInfoAddDescription => 'Add a description...';

  @override
  String get systemInfoSaveDescription => 'Save description';

  @override
  String get systemInfoTagLabel => 'System tag';

  @override
  String get systemInfoTagHint => 'e.g. | Skylars';

  @override
  String get systemInfoTagHelper => 'Appended to proxied messages';

  @override
  String get systemInfoColorLabel => 'System color';

  @override
  String get systemInfoColorPickAction => 'Pick color';

  @override
  String get systemInfoColorClearAction => 'Clear color';

  @override
  String get systemInfoColorNoneSet => 'No color set';

  @override
  String get devicesTitle => 'Manage Devices';

  @override
  String get devicesThisDevice => 'This Device';

  @override
  String get devicesOtherDevices => 'Other Devices';

  @override
  String get devicesFailedToLoad => 'Failed to load devices';

  @override
  String get devicesNoOtherDevices => 'No other devices';

  @override
  String get devicesNoOtherDevicesSubtitle =>
      'Only this device is registered in the sync group.';

  @override
  String get devicesStatusActive => 'Active';

  @override
  String get devicesStatusStale => 'Stale';

  @override
  String get devicesStatusRevoked => 'Revoked';

  @override
  String get devicesRotateKey => 'Rotate signing key';

  @override
  String get devicesRotateKeyTitle => 'Rotate Signing Key?';

  @override
  String get devicesRotateKeyMessage =>
      'This generates a new post-quantum signing key for this device. Other devices will accept the new key automatically. The old key remains valid for 30 days.';

  @override
  String get devicesRotate => 'Rotate';

  @override
  String devicesKeyRotated(int gen) {
    return 'Key rotated to generation $gen';
  }

  @override
  String devicesKeyRotationFailed(Object error) {
    return 'Key rotation failed: $error';
  }

  @override
  String get devicesRevokeTitle => 'Revoke Device?';

  @override
  String devicesRevokeMessage(String shortId) {
    return 'Device $shortId will be removed from the sync group and can no longer sync. This cannot be undone.';
  }

  @override
  String get devicesRequestWipeTitle => 'Request remote data wipe';

  @override
  String get devicesRequestWipeSubtitle =>
      'Asks the device to erase its sync data. This is a request — if the device is offline or compromised, it may not be honored.';

  @override
  String get devicesRevoke => 'Revoke';

  @override
  String devicesRevoked(String shortId) {
    return 'Device $shortId revoked';
  }

  @override
  String devicesFailedToRevoke(Object error) {
    return 'Failed to revoke: $error';
  }

  @override
  String devicesSemanticLabel(String shortId, String status, int gen) {
    return 'Device $shortId, $status, key generation $gen';
  }

  @override
  String devicesSemanticLabelCurrent(String shortId, String status, int gen) {
    return 'Device $shortId, $status, key generation $gen, this device';
  }

  @override
  String get continueLabel => 'Continue';

  @override
  String devicesEpochKeyGen(int epoch, int gen) {
    return 'Epoch $epoch · Key gen $gen';
  }

  @override
  String get devicesRotateKeyTooltip => 'Rotate signing key';

  @override
  String get devicesRevokeTooltip => 'Revoke device';

  @override
  String get devicesIdCopied => 'Device ID copied';

  @override
  String get syncTroubleshootingTitle => 'Prism Sync Troubleshooting';

  @override
  String get syncTroubleshootingConnectionStatus => 'Connection Status';

  @override
  String get syncTroubleshootingNotConfigured => 'Not configured';

  @override
  String get syncTroubleshootingConnected => 'Connected';

  @override
  String get syncTroubleshootingConfiguredLocally => 'Configured locally';

  @override
  String get syncTroubleshootingNotConfiguredSubtitle =>
      'This device does not currently have sync set up.';

  @override
  String get syncTroubleshootingConnectedSubtitle =>
      'Sync engine is active and ready';

  @override
  String get syncTroubleshootingConfiguredLocallySubtitle =>
      'Settings are stored. The engine will reconnect on the next sync.';

  @override
  String get syncTroubleshootingLastSync => 'Last Sync';

  @override
  String get syncTroubleshootingLastSuccessful => 'Last successful sync';

  @override
  String get syncTroubleshootingNeverSynced => 'Never synced';

  @override
  String get syncTroubleshootingLastError => 'Last sync error';

  @override
  String get syncTroubleshootingCurrentState => 'Current sync state';

  @override
  String get syncTroubleshootingSyncing => 'Syncing…';

  @override
  String get syncTroubleshootingIdle => 'Idle';

  @override
  String get syncTroubleshootingPendingOps => 'Pending operations';

  @override
  String syncTroubleshootingPendingOpsValue(int count) {
    return '$count ops waiting to sync';
  }

  @override
  String get syncTroubleshootingSyncId => 'Sync ID';

  @override
  String get syncTroubleshootingRelayUrl => 'Relay URL';

  @override
  String get syncTroubleshootingActions => 'Actions';

  @override
  String get syncTroubleshootingForceSync => 'Force Sync';

  @override
  String get syncTroubleshootingOpenEventLog => 'Open Prism Sync Event Log';

  @override
  String get syncTroubleshootingResetSync => 'Reset Sync System';

  @override
  String get syncTroubleshootingRepair => 'Re-pair Device';

  @override
  String get syncTroubleshootingCommonIssues => 'Common Issues';

  @override
  String get syncTroubleshootingIssue1Title => 'Sync not working?';

  @override
  String get syncTroubleshootingIssue1Description =>
      'Check that your relay URL and sync ID are correctly configured in Sync settings. Both devices must use the same sync ID.';

  @override
  String get syncTroubleshootingIssue2Title => 'Duplicate data?';

  @override
  String get syncTroubleshootingIssue2Description =>
      'Try resetting the sync system using the button above. This wipes local sync setup and lets you pair again cleanly.';

  @override
  String get syncTroubleshootingIssue3Title => 'Connection errors?';

  @override
  String get syncTroubleshootingIssue3Description =>
      'Verify that your device has network access and that the relay server is online. Check the relay URL for typos.';

  @override
  String get syncTroubleshootingIssue4Title => 'Sync is slow?';

  @override
  String get syncTroubleshootingIssue4Description =>
      'Initial sync may take longer with large datasets. Subsequent syncs are incremental and should be faster.';

  @override
  String get syncTroubleshootingIssue5Title => 'Device Identity Mismatch';

  @override
  String get syncTroubleshootingIssue5Description =>
      'If pairing failed mid-way, your device identity may be inconsistent. Use \"Re-pair Device\" to generate a fresh identity and pair again.';

  @override
  String get syncTroubleshootingFinished => 'Sync finished';

  @override
  String syncTroubleshootingFailed(Object error) {
    return 'Sync failed: $error';
  }

  @override
  String get syncTroubleshootingResetTitle => 'Reset sync system?';

  @override
  String get syncTroubleshootingResetMessage =>
      'This keeps your local app data, but wipes sync keys, relay configuration, device identity, and sync history from this device. You will need to set up sync again afterward.';

  @override
  String get syncTroubleshootingResetConfirm => 'Reset';

  @override
  String get syncTroubleshootingResetSuccess => 'Sync system reset';

  @override
  String get syncTroubleshootingRepairTitle => 'Re-pair Device?';

  @override
  String get syncTroubleshootingRepairMessage =>
      'This will clear your sync credentials and require you to pair again. Any local changes not yet synced will be lost.\n\nWe recommend exporting your data first as a safety net.';

  @override
  String get syncTroubleshootingRepairNow => 'Re-pair Now';

  @override
  String get syncTroubleshootingExportFirst => 'Export Data First';

  @override
  String get syncTroubleshootingCredentialsCleared =>
      'Sync credentials cleared';

  @override
  String get syncTroubleshootingPluralKitSection => 'PluralKit';

  @override
  String get syncTroubleshootingPkRepairTitle => 'Open PluralKit group repair';

  @override
  String get syncTroubleshootingPkRepairSubtitle =>
      'Use the PluralKit setup screen to run group repair and check any suppressed PK group matches.';

  @override
  String featureChatDescription(String term) {
    return 'Internal messaging between system $term.';
  }

  @override
  String get featureChatGeneral => 'General';

  @override
  String get featureChatEnable => 'Enable Chat';

  @override
  String featureChatEnableSubtitle(String term) {
    return 'In-system messaging between $term';
  }

  @override
  String get featureChatOptions => 'Options';

  @override
  String get featureChatLogFront => 'Log Front on Switch';

  @override
  String get featureChatLogFrontSubtitle =>
      'Changing who\'s speaking in chat also logs a front';

  @override
  String get featureChatProxyTagAuthoring =>
      'Use proxy tags to author messages';

  @override
  String featureChatProxyTagAuthoringSubtitle(String termSingularLower) {
    return 'Type a proxy tag (e.g. A:) to author as that $termSingularLower for one message. Case-sensitive.';
  }

  @override
  String chatPostingAsProxy(String name) {
    return 'Posting as $name';
  }

  @override
  String get chatPostingAsProxyDismiss => 'Don\'t post as proxy';

  @override
  String get featureChatGifSearch => 'GIF Search';

  @override
  String get featureChatGifSearchSubtitle => 'Search and send GIFs in chat';

  @override
  String get featureChatGifSearchUndecidedSubtitle =>
      'Off until you review the privacy details';

  @override
  String get featureChatGifSearchEnabledSubtitle => 'Enabled on this device';

  @override
  String get featureChatGifSearchDeclinedSubtitle =>
      'Hidden after you declined it on this device';

  @override
  String get featureChatGifSearchSyncRequiredSubtitle =>
      'Sync must be enabled to use GIFs';

  @override
  String get featureChatGifSearchSyncRequiredDialogTitle =>
      'Sync required for GIFs';

  @override
  String get featureChatGifSearchSyncRequiredDialogBody =>
      'GIF search runs through your sync relay so the service stays private. Set up sync to enable GIFs on this device.';

  @override
  String get featureChatGifSearchSyncRequiredDialogAction => 'Set up sync';

  @override
  String get featureChatVoiceNotes => 'Voice Notes';

  @override
  String get featureChatVoiceNotesSubtitle => 'Send voice messages in chat';

  @override
  String get featureFrontingDescription =>
      'Configure how fronting sessions work.';

  @override
  String get featureFrontingOptions => 'Options';

  @override
  String get featureFrontingQuickSwitch => 'Quick Switch';

  @override
  String get featureFrontingQuickSwitchOff => 'Off';

  @override
  String featureFrontingQuickSwitchSeconds(int seconds) {
    return '${seconds}s correction window';
  }

  @override
  String featureFrontingQuickSwitchMinutes(int minutes) {
    return '${minutes}m correction window';
  }

  @override
  String get featureFrontingQuickSwitchTitle => 'Quick Switch Window';

  @override
  String get featureFrontingQuickSwitchMessage =>
      'If you switch fronters within this window, it corrects the current session instead of creating a new one.';

  @override
  String get featureFrontingShowQuickFront => 'Quick Front';

  @override
  String featureFrontingShowQuickFrontSubtitle(String termPluralLower) {
    return 'Show frequently fronting $termPluralLower as tap-and-hold shortcuts';
  }

  @override
  String featureHabitsDescription(String term) {
    return 'Track recurring tasks and build streaks with your system $term.';
  }

  @override
  String get featureHabitsGeneral => 'General';

  @override
  String get featureHabitsEnable => 'Enable Habits';

  @override
  String get featureHabitsEnableSubtitle => 'Track daily routines and goals';

  @override
  String get featureHabitsOptions => 'Options';

  @override
  String get featureHabitsDueBadge => 'Due Habits Badge';

  @override
  String get featureHabitsDueBadgeSubtitle =>
      'Show count of due habits on the tab icon';

  @override
  String get featureSleepDescription =>
      'Sleep sessions help you track rest patterns alongside fronting sessions. You can start a sleep session from the moon icon on the fronting screen.';

  @override
  String get featureSleepGeneral => 'General';

  @override
  String get featureSleepEnable => 'Enable Sleep';

  @override
  String get featureSleepEnableSubtitle => 'Log and monitor sleep sessions';

  @override
  String get featureSleepOptions => 'Options';

  @override
  String get featureSleepDefaultQuality => 'Default Quality';

  @override
  String get featureSleepDefaultQualityTitle => 'Default Quality';

  @override
  String get featureSleepDefaultQualityMessage =>
      'Choose the default quality rating for new sleep sessions.';

  @override
  String get featurePollsDescription =>
      'Let your system vote on decisions together. Disabling hides polls from navigation but keeps existing poll data.';

  @override
  String get featurePollsEnable => 'Enable Polls';

  @override
  String get featurePollsEnableSubtitle => 'Create polls for system decisions';

  @override
  String featureNotesDescription(String term) {
    return 'A personal journal for system $term. Disabling hides notes from navigation but keeps existing entries.';
  }

  @override
  String get featureNotesEnable => 'Enable Notes';

  @override
  String get featureNotesEnableSubtitle => 'Write notes and journal entries';

  @override
  String get featureRemindersDescription =>
      'Get reminded on a schedule or when fronters change. Disabling hides reminders from navigation but keeps existing ones.';

  @override
  String get featureRemindersGeneral => 'General';

  @override
  String get featureRemindersEnable => 'Enable Reminders';

  @override
  String get featureRemindersEnableSubtitle =>
      'Scheduled and front-change reminders';

  @override
  String get featureRemindersOptions => 'Options';

  @override
  String get featureRemindersManage => 'Manage Reminders';

  @override
  String get featureRemindersManageSubtitle => 'Create and edit your reminders';

  @override
  String get voicePreparingNote => 'Preparing voice note...';

  @override
  String get voiceRecordingStartedAnnouncement => 'Recording started.';

  @override
  String get voiceRecordingReadyAnnouncement => 'Voice note ready to send.';

  @override
  String get voiceMicPermissionDenied =>
      'Microphone permission is required to record voice notes.';

  @override
  String get voiceMicPermissionBlocked =>
      'Microphone access is blocked. Enable it in Settings.';

  @override
  String get voiceRecordingFailed => 'Could not start recording.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get frontingListView => 'List view';

  @override
  String get frontingTimelineView => 'Timeline view';

  @override
  String get frontingAddEntry => 'Add fronting entry';

  @override
  String get frontingLoadingOlderSessions => 'Loading older sessions';

  @override
  String get frontingTimelineIssuesFound => 'Timeline issues found';

  @override
  String frontingTimelineIssuesBannerMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count timeline issues found. Tap to review.',
      one: '1 timeline issue found. Tap to review.',
    );
    return '$_temp0';
  }

  @override
  String get frontingTimelineIssuesReview => 'Review';

  @override
  String frontingAlwaysPresentLabel(String duration) {
    return 'Always present · $duration';
  }

  @override
  String frontingAlwaysPresentSemantics(String names, String duration) {
    return 'Always-present fronters: $names, $duration';
  }

  @override
  String frontingAlwaysPresentDurationWeeks(int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks weeks',
      one: '1 week',
    );
    return '$_temp0';
  }

  @override
  String frontingAlwaysPresentDurationDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String frontingAlwaysPresentDurationHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String get frontingMenuWakeUpAs => 'Wake Up As...';

  @override
  String get frontingMenuLogFront => 'Log Front';

  @override
  String get frontingMenuNewPoll => 'New Poll';

  @override
  String get frontingMenuStartSleep => 'Start Sleep';

  @override
  String get frontingMenuSyncPluralKit => 'Sync with PluralKit';

  @override
  String get frontingPluralKitSyncingToast => 'Syncing with PluralKit…';

  @override
  String get frontingPluralKitSyncDoneToast => 'PluralKit sync complete';

  @override
  String frontingPluralKitSyncFailedToast(Object error) {
    return 'PluralKit sync failed: $error';
  }

  @override
  String get frontingWakeUpAsTitle => 'Wake Up As...';

  @override
  String frontingErrorWakingUp(Object error) {
    return 'Error waking up: $error';
  }

  @override
  String frontingErrorSwitchingFronter(Object error) {
    return 'Error switching fronter: $error';
  }

  @override
  String get frontingNoSessionHistory => 'No session history yet';

  @override
  String frontingErrorLoadingHistory(Object error) {
    return 'Error loading history: $error';
  }

  @override
  String get frontingDeleteSleepTitle => 'Delete Sleep Session';

  @override
  String get frontingDeleteSleepMessage =>
      'Are you sure you want to delete this sleep session?';

  @override
  String get frontingSleeping => 'Sleep';

  @override
  String frontingSleepSessionSemantics(String duration, String timeRange) {
    return 'Sleep session, $duration, $timeRange';
  }

  @override
  String get frontingWelcomeTitle => 'Welcome to Prism';

  @override
  String frontingWelcomeSubtitle(String member) {
    return 'Add your first system $member to get started';
  }

  @override
  String frontingQuickFrontLabel(String name) {
    return 'Quick front $name';
  }

  @override
  String get frontingQuickFrontHoldHint => 'Hold to start fronting';

  @override
  String get frontingNewSession => 'New Session';

  @override
  String get frontingAddCoFronterTitle => 'Add Co-Fronter';

  @override
  String get frontingStartSessionTooltip => 'Start session';

  @override
  String get frontingAddCoFronterTooltip => 'Add co-fronter';

  @override
  String get frontingSelectFronter => 'Select Fronter';

  @override
  String get frontingAddFrontModeAdditive => 'Add as co-fronter';

  @override
  String get frontingAddFrontModeReplace => 'Replace current';

  @override
  String frontingSelectMember(String term) {
    return 'Select $term';
  }

  @override
  String get frontingCoFrontToggle => 'Co-front';

  @override
  String get frontingCoFronters => 'Co-Fronters';

  @override
  String frontingNoOtherMembers(String term) {
    return 'No other $term available';
  }

  @override
  String frontingCoFrontHint(String term) {
    return 'Tap a $term to add them to the co-front of the current session.';
  }

  @override
  String get frontingConfidenceLevel => 'Confidence Level';

  @override
  String get frontingConfidenceUnsure => 'Unsure';

  @override
  String get frontingConfidenceStrong => 'Strong';

  @override
  String get frontingConfidenceCertain => 'Certain';

  @override
  String get frontingNotes => 'Notes';

  @override
  String get frontingNotesHint => 'Optional notes about this session...';

  @override
  String get frontingNotesHintEdit => 'Optional notes...';

  @override
  String frontingSearchMembersHint(String term) {
    return 'Search $term...';
  }

  @override
  String frontingNoMembersMatching(String term, String query) {
    return 'No $term matching \"$query\"';
  }

  @override
  String get frontingFronting => 'Fronting';

  @override
  String frontingErrorAddingCoFronter(Object error) {
    return 'Error adding co-fronter: $error';
  }

  @override
  String frontingErrorCreatingSession(Object error) {
    return 'Error creating session: $error';
  }

  @override
  String get frontingAddCoFrontersTitle => 'Add Co-Fronters';

  @override
  String frontingErrorAddingCoFronters(Object error) {
    return 'Error adding co-fronters: $error';
  }

  @override
  String get frontingEditSessionTitle => 'Edit Session';

  @override
  String get frontingSaveSession => 'Save session';

  @override
  String get frontingSessionNotFound => 'Session not found';

  @override
  String get frontingStillActive => 'Still Active';

  @override
  String get frontingStart => 'Start';

  @override
  String get frontingEnd => 'End';

  @override
  String get frontingFronter => 'Fronter';

  @override
  String get frontingShortSessionTitle => 'Short Session';

  @override
  String get frontingShortSessionMessage =>
      'This session is less than a minute long. Save anyway?';

  @override
  String get frontingDuplicateSessionTitle => 'Duplicate Session';

  @override
  String frontingDuplicateSessionMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This session appears to be a duplicate of $count other sessions. Save anyway?',
      one:
          'This session appears to be a duplicate of 1 other session. Save anyway?',
    );
    return '$_temp0';
  }

  @override
  String get frontingSaveAnyway => 'Save anyway';

  @override
  String frontingErrorSavingSession(Object error) {
    return 'Error saving session: $error';
  }

  @override
  String get frontingSessionDetailEditTooltip => 'Edit';

  @override
  String get frontingSessionDetailDeleteTooltip => 'Delete';

  @override
  String get frontingSleepingNow => 'Sleeping now';

  @override
  String get frontingSleepSession => 'Sleep session';

  @override
  String get frontingInfoStarted => 'Started';

  @override
  String get frontingInfoEnded => 'Ended';

  @override
  String get frontingInfoDuration => 'Duration';

  @override
  String get frontingInfoActive => 'Active';

  @override
  String get frontingInfoQuality => 'Quality';

  @override
  String get frontingInfoQualityUnrated => 'Unrated';

  @override
  String get frontingTimeSection => 'Time';

  @override
  String get frontingConfidenceSection => 'Confidence';

  @override
  String get frontingNotesSection => 'Notes';

  @override
  String get frontingCoFrontersSection => 'Co-Fronters';

  @override
  String get frontingSleepingLabel => 'Sleeping';

  @override
  String frontingSleepSince(String time) {
    return 'Since $time';
  }

  @override
  String get frontingWakeUp => 'Wake Up';

  @override
  String get frontingSleepQualityUnrated => 'Sleep Quality: Unrated';

  @override
  String frontingSleepQualityRated(String label) {
    return 'Sleep Quality: $label';
  }

  @override
  String frontingRateSleepAs(String label) {
    return 'Rate sleep as $label';
  }

  @override
  String get sleepQualityNotRated => 'Not rated';

  @override
  String get sleepQualityVeryPoor => 'Very Poor';

  @override
  String get sleepQualityPoor => 'Poor';

  @override
  String get sleepQualityFair => 'Fair';

  @override
  String get sleepQualityGood => 'Good';

  @override
  String get sleepQualityExcellent => 'Excellent';

  @override
  String get sleepSuggestionBedtimeDismiss => 'Dismiss until tomorrow';

  @override
  String get frontingStartSleepTitle => 'Start Sleep';

  @override
  String get frontingStartButton => 'Start';

  @override
  String get frontingStartSleepNotesHint =>
      'Optional notes about this sleep...';

  @override
  String frontingErrorStartingSleep(Object error) {
    return 'Error starting sleep: $error';
  }

  @override
  String get frontingEditSleepTitle => 'Edit Sleep';

  @override
  String get frontingEditSleepLabel => 'Sleep session';

  @override
  String get frontingStillSleeping => 'Still Sleeping';

  @override
  String get frontingStillSleepingSubtitle => 'Leave the session open-ended';

  @override
  String get frontingSleepQualityLabel => 'Sleep quality';

  @override
  String get frontingEditSleepNotesHint => 'Optional notes about this sleep...';

  @override
  String get frontingEndTimeMustBeAfterStart =>
      'End time must be after start time.';

  @override
  String frontingErrorSavingSleepSession(Object error) {
    return 'Error saving sleep session: $error';
  }

  @override
  String get frontingCommentsTitle => 'Comments';

  @override
  String get frontingAddCommentTooltip => 'Add comment';

  @override
  String get frontingNoCommentsYet => 'No comments yet';

  @override
  String get frontingAddCommentTitle => 'Add Comment';

  @override
  String get frontingEditCommentTitle => 'Edit Comment';

  @override
  String get frontingCommentHint => 'Write your comment...';

  @override
  String get frontingDeleteCommentTitle => 'Delete comment?';

  @override
  String get frontingDeleteCommentMessage => 'This action cannot be undone.';

  @override
  String get frontingTimelineJumpToDate => 'Jump to date';

  @override
  String get frontingTimelineJumpToNow => 'Jump to now';

  @override
  String get frontingTimelineZoomOut => 'Zoom out';

  @override
  String get frontingTimelineZoomIn => 'Zoom in';

  @override
  String get frontingTimelineNoHistory => 'No fronting history';

  @override
  String get frontingTimelineNoHistorySubtitle =>
      'Start a fronting session to see it appear on the timeline.';

  @override
  String get frontingSanitizationTitle => 'Timeline Sanitization';

  @override
  String get frontingSanitizationScanning => 'Scanning timeline…';

  @override
  String get frontingSanitizationIntroTitle => 'Timeline Sanitization';

  @override
  String get frontingSanitizationIntroBody =>
      'Scan your fronting history for overlapping, duplicate, or invalid sessions, then apply automatic fixes.';

  @override
  String get frontingSanitizationScanButton => 'Scan Timeline';

  @override
  String get frontingSanitizationCleanTitle => 'Timeline looks clean!';

  @override
  String get frontingSanitizationCleanSubtitle =>
      'No overlaps, duplicates, or invalid sessions found.';

  @override
  String get frontingSanitizationScanAgain => 'Scan Again';

  @override
  String frontingSanitizationIssuesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count issues in your timeline.',
      one: 'Found 1 issue in your timeline.',
    );
    return '$_temp0';
  }

  @override
  String frontingSanitizationFixesApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fixes applied successfully.',
      one: '1 fix applied successfully.',
    );
    return '$_temp0';
  }

  @override
  String frontingSanitizationScanFailed(Object error) {
    return 'Scan failed: $error';
  }

  @override
  String frontingSanitizationFixFailed(Object error) {
    return 'Fix failed: $error';
  }

  @override
  String frontingSanitizationLoadFixFailed(Object error) {
    return 'Could not load fix options: $error';
  }

  @override
  String get frontingSanitizationFixOptionsTitle => 'Fix Options';

  @override
  String get frontingSanitizationNoAutoFix =>
      'No automated fixes available for this issue.\nPlease review and resolve it manually.';

  @override
  String get frontingSanitizationPreview => 'Preview';

  @override
  String get frontingSanitizationHidePreview => 'Hide Preview';

  @override
  String get frontingSanitizationApply => 'Apply';

  @override
  String get frontingIssueTypeOverlap => 'Overlap';

  @override
  String get frontingIssueTypeGap => 'Gap';

  @override
  String get frontingIssueTypeDuplicate => 'Duplicate';

  @override
  String get frontingIssueTypeMergeable => 'Mergeable';

  @override
  String get frontingIssueTypeInvalidRange => 'Invalid Range';

  @override
  String get frontingIssueTypeFutureSession => 'Future Session';

  @override
  String get frontingIssueSectionOverlap => 'Overlapping Sessions';

  @override
  String get frontingIssueSectionGap => 'Gaps';

  @override
  String get frontingIssueSectionDuplicate => 'Duplicates';

  @override
  String get frontingIssueSectionMergeable => 'Mergeable Adjacent';

  @override
  String get frontingIssueSectionInvalidRange => 'Invalid Ranges';

  @override
  String get frontingIssueSectionFutureSession => 'Future Sessions';

  @override
  String frontingIssueSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String get frontingDeleteStrategyTitle => 'What should happen to this time?';

  @override
  String get frontingDeleteStrategyRecommended => 'Recommended';

  @override
  String frontingGapDetectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gaps detected',
      one: 'Gap detected',
    );
    return '$_temp0';
  }

  @override
  String frontingGapDetectedMessage(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This edit would create $count gaps totaling $total.',
      one: 'This edit would create a gap totaling $total.',
    );
    return '$_temp0';
  }

  @override
  String get frontingGapFillWithUnknown => 'Fill with unknown fronter';

  @override
  String get frontingGapFillWithUnknownSubtitle =>
      'Create unknown sessions to cover the gaps.';

  @override
  String get frontingGapLeaveGaps => 'Leave gaps';

  @override
  String get frontingGapLeaveGapsSubtitle => 'Save without filling the gaps.';

  @override
  String frontingOverlapTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Overlap with $count sessions',
      one: 'Overlap with 1 session',
    );
    return '$_temp0';
  }

  @override
  String get frontingOverlapTrimOption => 'Trim overlapping sessions';

  @override
  String get frontingOverlapTrimSubtitle =>
      'Shorten or remove sessions that conflict with your edit.';

  @override
  String get frontingOverlapCoFrontOption => 'Create co-fronting session';

  @override
  String get frontingOverlapCoFrontSubtitle =>
      'Split the overlapping time into shared co-fronting segments.';

  @override
  String get frontingOverlapRemoveSessionTitle => 'Remove Session';

  @override
  String get frontingOverlapRemoveSessionMessage =>
      'This would remove a session entirely. Continue?';

  @override
  String get frontingOverlapContinue => 'Continue';

  @override
  String get frontingTimingModeTitle => 'Timing Mode';

  @override
  String get frontingTimingModeFlexible => 'Flexible';

  @override
  String get frontingTimingModeStrict => 'Strict';

  @override
  String get frontingTimingModeFlexibleSubtitle =>
      'Small gaps (under 5 minutes) are allowed between sessions.';

  @override
  String get frontingTimingModeStrictSubtitle =>
      'Sessions must be continuous with no gaps in the timeline.';

  @override
  String get memberSectionCustomFields => 'Custom Fields';

  @override
  String get memberSectionFrontingStats => 'Fronting Stats';

  @override
  String get memberSectionRecentSessions => 'Recent Sessions';

  @override
  String get memberSectionConversations => 'Conversations';

  @override
  String get memberSectionNotes => 'Notes';

  @override
  String get memberSectionBio => 'Notes';

  @override
  String get memberSectionProxyTags => 'Proxy Tags';

  @override
  String get memberProxyTagsManagedOnPk =>
      'Proxy tags are managed on PluralKit.';

  @override
  String get memberProxyTagsEditOnPk => 'Edit on PluralKit';

  @override
  String get memberProxyTagsLocalDescription =>
      'Saved in Prism for chat proxy-tag authoring. Linked members sync with PluralKit when push sync is enabled.';

  @override
  String get memberProxyTagsEditInPrism => 'Edit proxy tags';

  @override
  String get memberProxyTagsAdd => 'Add proxy tag';

  @override
  String get memberProxyTagsRemove => 'Remove proxy tag';

  @override
  String get memberProxyTagPrefixLabel => 'Prefix';

  @override
  String get memberProxyTagPrefixHint => 'A:';

  @override
  String get memberProxyTagSuffixLabel => 'Suffix';

  @override
  String get memberProxyTagSuffixHint => '-a';

  @override
  String get memberProxyTagsEmpty => 'No proxy tags set.';

  @override
  String memberEditTooltip(String termSingularLower) {
    return 'Edit $termSingularLower';
  }

  @override
  String get memberMoreOptionsTooltip => 'More options';

  @override
  String get memberAddNoteTooltip => 'Add note';

  @override
  String get memberSaveNoteTooltip => 'Save note';

  @override
  String get memberCancelSelectionTooltip => 'Cancel selection';

  @override
  String get memberClearDateTooltip => 'Clear date';

  @override
  String get memberNewGroupTooltip => 'New group';

  @override
  String memberAdded(String term) {
    return '$term added';
  }

  @override
  String memberIsFronting(String name) {
    return '$name is now fronting';
  }

  @override
  String memberGroupDeleted(String name) {
    return '$name deleted';
  }

  @override
  String memberActivated(String name) {
    return '$name activated';
  }

  @override
  String memberDeactivated(String name) {
    return '$name archived';
  }

  @override
  String memberRemoved(String name) {
    return '$name removed';
  }

  @override
  String memberRemoveFromGroupTitle(String term) {
    return 'Remove $term';
  }

  @override
  String memberRemoveFromGroupMessage(String name, String termLower) {
    return 'Remove $name from this group? The $termLower will not be deleted.';
  }

  @override
  String get memberGroupEmptyList => 'No groups yet';

  @override
  String memberGroupEmptySubtitle(String termPlural) {
    return 'Create groups to organize your system $termPlural';
  }

  @override
  String memberGroupNoMembers(String termPlural) {
    return 'No $termPlural';
  }

  @override
  String memberGroupNoMembersSubtitle(String termPlural) {
    return 'Add $termPlural to this group';
  }

  @override
  String get memberArchived => 'Inactive';

  @override
  String get memberActive => 'Active';

  @override
  String get memberOrderUpdated => 'Order updated';

  @override
  String get memberReorderBy => 'Reorder by';

  @override
  String get memberSortNameAZ => 'Name A–Z';

  @override
  String get memberSortNameZA => 'Name Z–A';

  @override
  String get memberSortRecentlyCreated => 'Recently created';

  @override
  String get memberSortMostFronting => 'Most fronting';

  @override
  String get memberSortLeastFronting => 'Least fronting';

  @override
  String get memberShowInactive => 'Show inactive';

  @override
  String get memberHideInactive => 'Hide inactive';

  @override
  String get memberStatsTotalSessions => 'Total sessions';

  @override
  String get memberStatsTotalTime => 'Total time';

  @override
  String get memberStatsLastFronted => 'Last fronted';

  @override
  String get memberStatsToday => 'Today';

  @override
  String get memberStatsYesterday => 'Yesterday';

  @override
  String memberStatsDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String memberStatsWeeksAgo(int count) {
    return '$count weeks ago';
  }

  @override
  String get memberSessionActive => 'Active';

  @override
  String memberSessionTodayAt(String time) {
    return 'Today at $time';
  }

  @override
  String get memberFrontingChip => 'Fronting';

  @override
  String get memberAdminChip => 'Admin';

  @override
  String get memberInactiveChip => 'Inactive';

  @override
  String get memberSetAsFronter => 'Set as fronter';

  @override
  String get memberNoteTitle => 'Note';

  @override
  String get memberNoteUntitled => 'Untitled';

  @override
  String get memberNoteNotFound => 'Note not found';

  @override
  String get memberNoteDeleteTitle => 'Delete note?';

  @override
  String memberNoteDeleteMessage(String title) {
    return 'Are you sure you want to delete \"$title\"? This action cannot be undone.';
  }

  @override
  String get memberNoteNoNotesYet => 'No notes yet';

  @override
  String get memberNoteEmptySubtitle =>
      'Create notes to keep track of thoughts and observations';

  @override
  String get memberNoteTitleHint => 'Title';

  @override
  String get memberNoteBodyHint => 'Start writing...';

  @override
  String memberNoteAddHeadmate(String termLower) {
    return 'Add $termLower';
  }

  @override
  String get memberNoteDiscardTitle => 'Discard changes?';

  @override
  String get memberNoteDiscardMessage =>
      'You have unsaved changes. Are you sure you want to discard them?';

  @override
  String get memberNoteDiscardConfirm => 'Discard';

  @override
  String memberNoteChooseHeadmate(String termSingular) {
    return 'Choose $termSingular';
  }

  @override
  String memberNoteDateSemantics(String date) {
    return 'Note date, $date. Tap to change';
  }

  @override
  String memberNoteMemberSemantics(String termSingular, String name) {
    return '$termSingular: $name. Tap to change';
  }

  @override
  String memberNoteNoHeadmateSemantics(String termLower) {
    return 'No $termLower selected. Tap to choose';
  }

  @override
  String get memberSelectNone => 'None';

  @override
  String get memberGroupsTitle => 'Groups';

  @override
  String memberGroupErrorLoading(Object error) {
    return 'Error loading groups: $error';
  }

  @override
  String memberGroupErrorLoadingDetail(Object error) {
    return 'Error loading group: $error';
  }

  @override
  String get memberGroupNotFound => 'Group not found';

  @override
  String get memberGroupSubGroupsLabel => 'Sub-groups';

  @override
  String memberGroupSectionMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get memberGroupStartChat => 'Start chat';

  @override
  String memberGroupAddMember(String termSingularLower) {
    return 'Add $termSingularLower';
  }

  @override
  String get memberGroupAddSubGroup => 'Add sub-group';

  @override
  String get memberGroupAddToGroup => 'Add to group';

  @override
  String memberGroupAddToGroupSemantics(String name) {
    return 'Add $name to a group';
  }

  @override
  String get memberGroupDeleteTitle => 'Delete group';

  @override
  String memberGroupDeleteMessage(String name, String termPlural) {
    return 'Are you sure you want to delete \"$name\"? $termPlural will not be deleted.';
  }

  @override
  String get memberGroupDeleteConfirm => 'Delete';

  @override
  String get memberGroupDeleteCascadeSubtitle =>
      'This group has sub-groups. What should happen to them?';

  @override
  String get memberGroupDeletePromote => 'Move sub-groups to top level';

  @override
  String get memberGroupDeletePromoteSubtitle =>
      'Sub-groups stay, just without a parent';

  @override
  String get memberGroupDeleteAll => 'Delete everything';

  @override
  String get memberGroupDeleteAllSubtitle =>
      'All sub-groups will also be deleted';

  @override
  String get memberGroupDeleteAllConfirmTitle => 'Delete sub-groups too?';

  @override
  String memberGroupDeleteAllConfirmMessage(String name, String termPlural) {
    return 'This will permanently delete \"$name\" and all its sub-groups. $termPlural will not be deleted.';
  }

  @override
  String get memberGroupPromoted => 'Sub-groups moved to top level';

  @override
  String get memberGroupEditTitle => 'Edit Group';

  @override
  String get memberGroupNewTitle => 'New Group';

  @override
  String get memberGroupNameLabel => 'Name';

  @override
  String get memberGroupNameRequired => 'Name is required';

  @override
  String get memberGroupDescriptionLabel => 'Description';

  @override
  String get memberGroupColorLabel => 'Color';

  @override
  String get memberGroupColorNone => 'No color';

  @override
  String memberGroupErrorSaving(Object error) {
    return 'Error saving group: $error';
  }

  @override
  String get memberGroupParentLabel => 'Parent group';

  @override
  String get memberGroupParentNone => 'None (top level)';

  @override
  String get memberGroupParentDepthLimit => 'Can\'t nest deeper';

  @override
  String get memberGroupFilterAll => 'All';

  @override
  String get memberGroupFilterBarLabel => 'Filter by group';

  @override
  String get memberGroupFilterUngrouped => 'Ungrouped';

  @override
  String memberGroupFrontAllAlreadyFronting(
    String termPluralLower,
    Object termPlural,
  ) {
    return 'All $termPluralLower are already fronting';
  }

  @override
  String memberGroupFrontAllInactive(String name, String termPluralLower) {
    return 'All $termPluralLower in $name are inactive. Front anyway?';
  }

  @override
  String get memberGroupFrontGroup => 'Front as Group';

  @override
  String memberGroupFrontGroupConfirmTitle(String name) {
    return 'Front as $name?';
  }

  @override
  String memberGroupFrontGroupConfirmMessage(int count, String termForCount) {
    return 'This will start a co-front session with $count $termForCount.';
  }

  @override
  String memberGroupFrontGroupSemantics(String name, String termPluralLower) {
    return 'Front all $termPluralLower in $name';
  }

  @override
  String memberGroupFrontSomeAlreadyFronting(
    int count,
    String termForCount,
    int remaining,
  ) {
    return '$count $termForCount already fronting. Add the remaining $remaining?';
  }

  @override
  String get memberGroupManageNoGroups => 'No groups yet';

  @override
  String get memberGroupManageNoGroupsAction => 'Create a group';

  @override
  String get memberGroupManageTitle => 'Groups';

  @override
  String get memberNameLabel => 'Name *';

  @override
  String get memberNameHint => 'Enter name';

  @override
  String get memberNameRequired => 'Name is required';

  @override
  String get memberPronounsLabel => 'Pronouns';

  @override
  String get memberPronounsHint => 'e.g. she/her, they/them';

  @override
  String get memberAgeLabel => 'Age';

  @override
  String get memberAgeHint => 'Optional';

  @override
  String get memberBioLabel => 'Bio';

  @override
  String get memberBioHint => 'A short description...';

  @override
  String get memberDisplayNameLabel => 'Display name';

  @override
  String get memberDisplayNameHint => 'Optional alias shown alongside the name';

  @override
  String get memberBirthdayLabel => 'Birthday';

  @override
  String get memberBirthdayHint => 'Tap to set a date';

  @override
  String get memberBirthdayHideYear => 'Hide year';

  @override
  String get memberBirthdayHideYearSubtitle => 'Show only the month and day';

  @override
  String get memberBirthdayClear => 'Clear birthday';

  @override
  String get memberSectionBirthday => 'Birthday';

  @override
  String get memberMarkdownTitle => 'Format bio as markdown';

  @override
  String get memberMarkdownSubtitle =>
      'Render bio text with markdown formatting';

  @override
  String get memberAdminTitle => 'Admin';

  @override
  String get memberAdminSubtitle => 'Admins can manage system settings';

  @override
  String get memberCustomColorTitle => 'Custom color';

  @override
  String memberCustomColorSubtitle(String termSingularLower) {
    return 'Use a personal color for this $termSingularLower';
  }

  @override
  String get memberColorHexLabel => 'Color hex';

  @override
  String memberErrorSaving(String term, Object error) {
    return 'Error saving $term: $error';
  }

  @override
  String memberAgeDisplay(int age) {
    return 'Age $age';
  }

  @override
  String memberSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String memberSearchConfirmSelectionTooltip(String termPluralLower) {
    return 'Confirm selected $termPluralLower';
  }

  @override
  String memberSaveTooltip(String termSingularLower) {
    return 'Save $termSingularLower';
  }

  @override
  String get memberBulkActivate => 'Activate';

  @override
  String get memberBulkDeactivate => 'Deactivate';

  @override
  String memberNoInactive(String terms) {
    return 'No inactive $terms';
  }

  @override
  String memberNoActive(String terms) {
    return 'No active $terms';
  }

  @override
  String get memberConversationFallback => 'Conversation';

  @override
  String get memberCustomFieldSelectDate => 'Select date';

  @override
  String memberCustomFieldEnterHint(String fieldName) {
    return 'Enter $fieldName';
  }

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatNewConversation => 'New Conversation';

  @override
  String get chatManageCategories => 'Manage categories';

  @override
  String get chatSearchMessages => 'Search messages';

  @override
  String get chatNoConversations => 'No conversations';

  @override
  String get chatNoConversationsSubtitle => 'Start chatting with your system';

  @override
  String get chatErrorLoadingConversations => 'Error loading conversations';

  @override
  String get chatUncategorized => 'Uncategorized';

  @override
  String get chatMarkAsRead => 'Mark as Read';

  @override
  String get chatMarkAllAsRead => 'Mark all as read';

  @override
  String get chatMute => 'Mute';

  @override
  String get chatUnmute => 'Unmute';

  @override
  String get chatDeleteConversationTitle => 'Delete Conversation';

  @override
  String get chatDeleteConversationMessage =>
      'Are you sure you want to delete this conversation? All messages will be permanently removed.';

  @override
  String get chatDeleteConversationFullMessage =>
      'Are you sure you want to delete this conversation? All messages will be permanently removed. This cannot be undone.';

  @override
  String get chatBadgeMentionsOnly => 'Badge: mentions only';

  @override
  String get chatBadgeAllMessages => 'Badge: all messages';

  @override
  String get chatHideArchived => 'Hide archived';

  @override
  String get chatShowArchived => 'Show archived';

  @override
  String get chatConversationNotFound => 'Conversation not found';

  @override
  String get chatConversationInfo => 'Conversation info';

  @override
  String get chatNoMessages => 'No messages yet';

  @override
  String get chatStartConversation => 'Start the conversation!';

  @override
  String chatErrorLoadingMessages(Object error) {
    return 'Error loading messages: $error';
  }

  @override
  String get chatLoadingOlderMessages => 'Loading older messages';

  @override
  String get chatSearchPlaceholder => 'Search messages...';

  @override
  String get chatSearchHint => 'Find messages across your conversations';

  @override
  String get chatSearchKeepTyping => 'Keep typing to search...';

  @override
  String chatSearchNoResults(String query) {
    return 'No messages found for \'$query\'';
  }

  @override
  String get chatSearchTryDifferent => 'Try fewer or different words';

  @override
  String chatSearchError(Object error) {
    return 'Error: $error';
  }

  @override
  String get chatMessagePlaceholder => 'Message';

  @override
  String get chatSendMessage => 'Send message';

  @override
  String get chatSendMessageDisabled => 'Send message, disabled';

  @override
  String get chatRecordVoiceNote => 'Record voice note';

  @override
  String chatSpeakingAs(String name) {
    return 'Speaking as $name. Double tap to change.';
  }

  @override
  String chatChooseSpeakingMember(String termSingularLower) {
    return 'Choose speaking $termSingularLower';
  }

  @override
  String get chatCancelReply => 'Cancel reply';

  @override
  String get chatAddAttachment => 'Add Attachment';

  @override
  String get chatCamera => 'Camera';

  @override
  String get chatPhotoLibrary => 'Photo Library';

  @override
  String get chatContextReply => 'Reply';

  @override
  String get chatContextCopyText => 'Copy Text';

  @override
  String get chatContextEditMessage => 'Edit Message';

  @override
  String get chatContextDelete => 'Delete';

  @override
  String get chatCopied => 'Copied';

  @override
  String get chatEditMessageTitle => 'Edit Message';

  @override
  String get chatMessageContentHint => 'Message content';

  @override
  String get chatDeleteMessageTitle => 'Delete Message';

  @override
  String get chatDeleteMessageMessage =>
      'This message will be permanently deleted.';

  @override
  String get chatReplyQuoteDeleted => 'Original message deleted';

  @override
  String chatReplyQuoteSemantics(String authorName, String content) {
    return 'Replying to $authorName: $content. Double-tap to scroll to message.';
  }

  @override
  String get chatReplyQuoteDeletedSemantics => 'Original message deleted';

  @override
  String get chatMessageEdited => 'edited';

  @override
  String get chatInfoTitle => 'Info';

  @override
  String get chatInfoConversationTitle => 'Conversation title';

  @override
  String chatInfoCreatedAt(String date) {
    return 'Created $date';
  }

  @override
  String chatInfoParticipants(int count) {
    return 'Participants ($count)';
  }

  @override
  String chatInfoAddMembers(String termPluralLower) {
    return 'Add $termPluralLower';
  }

  @override
  String get chatInfoOwner => 'Owner';

  @override
  String get chatInfoAdmin => 'Admin';

  @override
  String chatInfoUnknownMember(String termSingular) {
    return 'Unknown $termSingular';
  }

  @override
  String chatInfoErrorLoadingMember(String termSingularLower) {
    return 'Error loading $termSingularLower';
  }

  @override
  String get chatInfoCategory => 'Category';

  @override
  String get chatInfoCategoryNone => 'None';

  @override
  String chatInfoCategorySemantics(String name) {
    return 'Category: $name';
  }

  @override
  String get chatInfoDirectMessage => 'Direct Message';

  @override
  String get chatInfoGroupChat => 'Group Chat';

  @override
  String chatInfoCannotManage(String memberName) {
    return '$memberName can\'t manage this conversation';
  }

  @override
  String get chatInfoArchiveConversation => 'Archive conversation';

  @override
  String get chatInfoUnarchiveConversation => 'Unarchive conversation';

  @override
  String get chatInfoLeaveConversation => 'Leave conversation';

  @override
  String get chatInfoDeleteConversation => 'Delete conversation';

  @override
  String get chatInfoConversationArchived => 'Conversation archived';

  @override
  String get chatInfoConversationUnarchived => 'Conversation unarchived';

  @override
  String chatInfoFailedSaveTitle(Object error) {
    return 'Failed to save title: $error';
  }

  @override
  String chatInfoFailedSaveEmoji(Object error) {
    return 'Failed to save emoji: $error';
  }

  @override
  String get chatLeaveConversationTitle => 'Leave Conversation';

  @override
  String get chatLeaveConversationMessage =>
      'Leave this conversation? Your past messages will remain.';

  @override
  String get chatLeaveConversationConfirm => 'Leave';

  @override
  String get chatSelectNewOwner => 'Select new conversation owner';

  @override
  String chatAddMembersTitle(String termPlural) {
    return 'Add $termPlural';
  }

  @override
  String chatAddMembersAllAdded(String termPluralLower, Object termPlural) {
    return 'All active $termPluralLower are already in this conversation.';
  }

  @override
  String chatAddMembersFailed(String termPluralLower, Object error) {
    return 'Failed to add $termPluralLower: $error';
  }

  @override
  String get chatCreateTitle => 'New Conversation';

  @override
  String get chatCreateConversationTooltip => 'Create conversation';

  @override
  String get chatCreateGroupTab => 'Group';

  @override
  String get chatCreateDirectMessageTab => 'Direct Message';

  @override
  String get chatCreateGroupName => 'Group Name';

  @override
  String get chatCreateGroupNameHint => 'e.g., System Discussion';

  @override
  String get chatCreateSelectParticipants => 'Select participants (2+)';

  @override
  String chatCreateMessageAs(String name) {
    return 'Message as $name with:';
  }

  @override
  String get chatCreateSelectAll => 'Select All';

  @override
  String get chatCreateDeselectAll => 'Deselect All';

  @override
  String chatCreateNoMembers(String termPluralLower) {
    return 'No $termPluralLower available. Create $termPluralLower first.';
  }

  @override
  String get chatCreateFronting => 'Fronting';

  @override
  String chatCreateFronterDeselectedWarning(String name) {
    return '$name is currently fronting but not in this chat. You won\'t be able to see or send messages.';
  }

  @override
  String chatCreateFailed(Object error) {
    return 'Failed to create conversation: $error';
  }

  @override
  String get chatCategoriesTitle => 'Manage Categories';

  @override
  String get chatCategoriesNone => 'No categories yet';

  @override
  String get chatCategoriesNewHint => 'New category name';

  @override
  String get chatCategoriesCategoryNameHint => 'Category name';

  @override
  String get chatCategoriesAddTooltip => 'Add category';

  @override
  String chatCategoriesDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get chatCategoriesDeleteMessage =>
      'Conversations in this category will become uncategorized.';

  @override
  String chatCategoriesCreateFailed(Object error) {
    return 'Failed to create category: $error';
  }

  @override
  String chatCategoriesRenameFailed(Object error) {
    return 'Failed to rename category: $error';
  }

  @override
  String chatCategoriesDeleteFailed(Object error) {
    return 'Failed to delete category: $error';
  }

  @override
  String chatNoMembersAvailable(String termPluralLower) {
    return 'No $termPluralLower available';
  }

  @override
  String chatErrorLoadingMembersShort(String termPluralLower) {
    return 'Error loading $termPluralLower';
  }

  @override
  String get chatGifsTitle => 'GIFs';

  @override
  String get chatGifsSearchHint => 'Search for GIFs';

  @override
  String get chatGifsPoweredBy => 'Powered by KLIPY';

  @override
  String get chatGifsLoadFailed => 'Failed to load GIFs';

  @override
  String get chatGifsNotFound => 'No GIFs found';

  @override
  String get chatGifsNotFoundSubtitle => 'Try different search terms';

  @override
  String get chatGifConsentTitle => 'Enable GIFs?';

  @override
  String get chatGifConsentIntro =>
      'GIFs use a relay-backed Klipy service. Here\'s what each side can and cannot see.';

  @override
  String get chatGifConsentRelayTitle => 'What Prism relay can see';

  @override
  String get chatGifConsentRelayBody =>
      'Your relay can see the GIF searches you send through it and your device\'s network metadata. It cannot see your encrypted chats.';

  @override
  String get chatGifConsentKlipyTitle => 'What Klipy can see';

  @override
  String get chatGifConsentKlipyBody =>
      'Klipy receives the search request from the relay and can see the search terms plus the relay\'s network identity, not yours directly.';

  @override
  String get chatGifConsentMediaTitle => 'What happens when you open a GIF';

  @override
  String get chatGifConsentMediaBody =>
      'GIF previews and playback still load from Klipy\'s media host, so opening a GIF can contact Klipy directly from your device.';

  @override
  String get chatGifConsentDecline => 'No Thanks';

  @override
  String get chatGifConsentEnable => 'Enable GIFs';

  @override
  String chatGifsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count GIFs found',
      one: '1 GIF found',
    );
    return '$_temp0';
  }

  @override
  String get chatGifSendButton => 'Send';

  @override
  String chatGifPreviewSemantics(String description) {
    return 'GIF preview: $description. Send button below.';
  }

  @override
  String chatGifCellSemantics(String description) {
    return 'GIF: $description';
  }

  @override
  String get chatGifCellSemanticsDefault => 'GIF: search result';

  @override
  String get chatMediaNoLongerAvailable => 'Media no longer available';

  @override
  String get chatAttachedImagePreview => 'Attached image preview';

  @override
  String get chatRemoveAttachment => 'Remove attachment';

  @override
  String get chatSearchClear => 'Clear search';

  @override
  String get chatInfoEditEmoji => 'Edit conversation emoji';

  @override
  String get chatInfoEditTitle => 'Edit conversation title';

  @override
  String get chatImageAttachment => 'Image attachment';

  @override
  String get chatImageLoading => 'Image attachment loading.';

  @override
  String get chatImageOpenFullScreen =>
      'Image attachment. Double tap to view full screen.';

  @override
  String chatMessageToggleReaction(String emoji) {
    return 'Toggle reaction $emoji';
  }

  @override
  String get chatMessageAddCustomReaction => 'Add custom reaction';

  @override
  String get chatMessageToggleTimeFormat => 'Toggle time format';

  @override
  String chatReactionAdd(String emoji) {
    return 'Add reaction $emoji';
  }

  @override
  String chatReactionSheetTitle(String emoji) {
    return '$emoji Reactions';
  }

  @override
  String chatVoiceNoteSemantics(String duration) {
    return 'Voice note from message, $duration';
  }

  @override
  String chatVoiceNoteLoading(String duration) {
    return 'Loading voice note, $duration';
  }

  @override
  String chatVoiceNotePause(String duration) {
    return 'Pause voice note, $duration';
  }

  @override
  String chatVoiceNotePlay(String duration) {
    return 'Play voice note, $duration';
  }

  @override
  String chatVoiceNoteSpeed(String speed) {
    return 'Playback speed ${speed}x. Double tap to change.';
  }

  @override
  String get chatVoiceNoteError => 'Failed to load voice note. Tap to retry.';

  @override
  String get chatImageError => 'Failed to load image. Tap to retry.';

  @override
  String get chatImageUploadFailed => 'Image failed to send';

  @override
  String get chatVoiceNoteUploadFailed => 'Voice note failed to send';

  @override
  String get chatVoiceRecorderCancel => 'Cancel recording';

  @override
  String get chatVoiceRecorderSend => 'Send voice note';

  @override
  String chatImageViewerSemantics(String caption) {
    return 'Full screen image viewer. $caption. Pinch to zoom, swipe down to close.';
  }

  @override
  String get chatImageViewerClose => 'Close viewer';

  @override
  String get chatImageViewerShare => 'Share image';

  @override
  String get chatConversationNoTitle => 'Conversation';

  @override
  String memberSelectLoadFailed(String termPlural) {
    return 'Failed to load $termPlural';
  }

  @override
  String get onboardingPermissionsNotGranted => 'Not granted';

  @override
  String get syncSetupConnectingToJoiner => 'Connecting to joiner...';

  @override
  String get syncSetupCompletingPairing => 'Completing pairing...';

  @override
  String get syncSetupScanJoinerPrompt =>
      'The new device can generate a pairing request QR code. Scan it here to approve the device and share your sync credentials.';

  @override
  String get setupDeviceEnterMnemonicTitle => 'Enter your recovery phrase';

  @override
  String get setupDeviceEnterMnemonicSubtitle =>
      'Needed to set up this new device. Your recovery phrase is not stored on this device — type it from your saved backup.';

  @override
  String get setupDeviceMnemonicContinue => 'Continue';

  @override
  String get syncSetupScanJoinerButton => 'Scan Joiner\'s QR';

  @override
  String get syncSetupScanJoinerDescription =>
      'Scan the joiner\'s pairing QR code.';

  @override
  String get syncSetupInvalidPairingQr => 'Invalid pairing QR code.';

  @override
  String get syncSetupVerifyDescription =>
      'Confirm these words match on the joining device.';

  @override
  String get syncSetupPairingComplete =>
      'Pairing complete! The new device is now syncing.';

  @override
  String get syncSetupSnapshotNotice =>
      'An encrypted snapshot has been uploaded and will be automatically deleted after the new device connects (or after 24 hours).';

  @override
  String get syncSetupPairingFailed => 'Pairing Failed';

  @override
  String get syncSetupSnapshotUploadingTitle =>
      'Uploading your system to the new device';

  @override
  String syncSetupSnapshotUploadProgress(String sent, String total) {
    return '$sent of $total';
  }

  @override
  String get syncSetupSnapshotUploadStarting => 'Preparing upload...';

  @override
  String get syncSetupSnapshotUploadFailedTitle =>
      'Couldn\'t upload your system';

  @override
  String get syncSetupSnapshotUploadRetry => 'Retry upload';

  @override
  String get syncSetupPairingReadyTitle => 'Pairing ready';

  @override
  String get syncSetupPairingReadyWaiting =>
      'Waiting for the other device to finish setting up.';

  @override
  String memberAvatarSemantics(String name) {
    return '$name avatar';
  }

  @override
  String memberAvatarSemanticsUnnamed(
    String termSingular,
    Object termSingularLower,
  ) {
    return '$termSingular avatar';
  }

  @override
  String groupMemberAvatarSemantics(String termSingularLower) {
    return 'Group $termSingularLower avatar';
  }

  @override
  String get habitsReminderNotificationTitle => 'Habit Reminder';

  @override
  String habitsReminderNotificationBody(String habitName) {
    return 'Time to complete: $habitName';
  }

  @override
  String get chatTileNoMessages => 'No messages yet';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get showToken => 'Show token';

  @override
  String get hideToken => 'Hide token';

  @override
  String get onboardingCloseOnboarding => 'Close onboarding';

  @override
  String onboardingProgressStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String onboardingErrorCompletingSetup(Object error) {
    return 'Error completing setup: $error';
  }

  @override
  String get onboardingImportCompleteTitle => 'Import Complete';

  @override
  String get onboardingImportCompleteDescription =>
      'Your Prism export has been restored and this device is ready.';

  @override
  String get onboardingImportedDataLabel => 'Imported data';

  @override
  String get onboardingWelcomePrivateTitle => 'Private by default';

  @override
  String get onboardingWelcomePrivateDescription =>
      'Not even we can read your data. Everything stays on your device unless you choose to sync.';

  @override
  String get onboardingWelcomeSyncTitle => 'Sync across devices';

  @override
  String get onboardingWelcomeSyncDescription =>
      'End-to-end encrypted. The server only sees noise.';

  @override
  String get onboardingWelcomeBuiltForYouTitle => 'Built for you';

  @override
  String get onboardingWelcomeBuiltForYouDescription =>
      'Your words, your colors, your features. Prism adapts to how your system works.';

  @override
  String onboardingAddMembersNoMembers(
    String termPluralLower,
    String termSingular,
    Object termSingularLower,
  ) {
    return 'No $termPluralLower yet.\nTap \"Add $termSingular\" to get started.';
  }

  @override
  String onboardingAddMembersRemoveMember(String termSingularLower) {
    return 'Remove $termSingularLower';
  }

  @override
  String onboardingAddMembersAddMember(
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Add $termSingular';
  }

  @override
  String onboardingAddMemberSheetTitle(
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Add $termSingular';
  }

  @override
  String get onboardingAddMemberFieldEmoji => 'Emoji';

  @override
  String get onboardingAddMemberFieldName => 'Name *';

  @override
  String get onboardingAddMemberPronounSheHer => 'She/Her';

  @override
  String get onboardingAddMemberPronounHeHim => 'He/Him';

  @override
  String get onboardingAddMemberPronounTheyThem => 'They/Them';

  @override
  String get onboardingAddMemberFieldPronounsCustom => 'Pronouns (custom)';

  @override
  String get onboardingAddMemberFieldAge => 'Age (optional)';

  @override
  String get onboardingAddMemberFieldBio => 'Bio (optional)';

  @override
  String get onboardingAddMemberSaveButton => 'Add';

  @override
  String get onboardingFeaturesChat => 'Chat';

  @override
  String onboardingFeaturesChatDescription(String termPluralLower) {
    return 'Internal messaging between system $termPluralLower';
  }

  @override
  String get onboardingFeaturesPolls => 'Polls';

  @override
  String get onboardingFeaturesPollsDescription =>
      'Create polls for system decisions';

  @override
  String get onboardingFeaturesHabits => 'Habits';

  @override
  String get onboardingFeaturesHabitsDescription =>
      'Track daily habits and routines';

  @override
  String get onboardingFeaturesSleepTracking => 'Sleep Tracking';

  @override
  String get onboardingFeaturesSleepTrackingDescription =>
      'Monitor sleep patterns and quality';

  @override
  String get onboardingFeaturesNotes => 'Notes';

  @override
  String get onboardingFeaturesNotesDescription =>
      'A personal journal and writing space for your system';

  @override
  String get onboardingFeaturesReminders => 'Reminders';

  @override
  String onboardingFeaturesRemindersDescription(String termPluralLower) {
    return 'Set reminders for yourself or system $termPluralLower';
  }

  @override
  String get onboardingCompleteTrackFrontingTitle => 'Track fronting';

  @override
  String get onboardingCompleteTrackFrontingDescription =>
      'Log who\'s here and look back at patterns over time.';

  @override
  String get onboardingCompleteChatTitle => 'Talk to each other';

  @override
  String get onboardingCompleteChatDescription =>
      'Leave messages for whoever fronts next, or chat in real time.';

  @override
  String get onboardingCompletePollsTitle => 'Decide together';

  @override
  String get onboardingCompletePollsDescription =>
      'Polls, votes — the democracy your system deserves.';

  @override
  String get onboardingImportDataSourcePickerIntro =>
      'You can import your existing data or skip this step to start fresh.';

  @override
  String get onboardingImportSyncWithDevice => 'Sync with Existing Device';

  @override
  String get onboardingImportSyncWithDeviceDescription =>
      'Scan a pairing QR code to sync data from another device';

  @override
  String get onboardingImportPluralKit => 'PluralKit';

  @override
  String get onboardingImportPluralKitDescription =>
      'Import members and fronting history from PluralKit via API token';

  @override
  String get onboardingImportPrismExport => 'Prism Export';

  @override
  String get onboardingImportPrismExportDescription =>
      'Import from a Prism .json or encrypted .prism export file';

  @override
  String get onboardingImportSimplyPlural => 'Simply Plural';

  @override
  String get onboardingImportSimplyPluralDescription =>
      'Import from a Simply Plural JSON export file';

  @override
  String get onboardingImportLaterHint =>
      'You can always import data later from Settings.';

  @override
  String get onboardingImportOtherOptions => 'Other import options';

  @override
  String get onboardingPluralKitHowToGetToken => 'How to get your token:';

  @override
  String get onboardingPluralKitStep1 => 'Open Discord';

  @override
  String get onboardingPluralKitStep2 => 'DM PluralKit bot: pk;token';

  @override
  String get onboardingPluralKitStep3 => 'Copy the token and paste below';

  @override
  String get onboardingPluralKitTokenHint => 'Paste your PluralKit token';

  @override
  String get onboardingPluralKitImportButton => 'Import PluralKit Data';

  @override
  String get onboardingPluralKitConnecting => 'Connecting to PluralKit…';

  @override
  String get onboardingPluralKitImportingMembers => 'Importing members…';

  @override
  String get onboardingPluralKitImportingHistory => 'Importing switch history…';

  @override
  String onboardingPluralKitImportSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count members from PluralKit!',
      one: 'Imported 1 member from PluralKit!',
    );
    return '$_temp0';
  }

  @override
  String get onboardingPluralKitErrorEnterToken =>
      'Please enter your PluralKit token.';

  @override
  String get onboardingPluralKitErrorCouldNotConnect =>
      'Could not connect. Please check your token.';

  @override
  String onboardingImportError(Object error) {
    return 'Import failed: $error';
  }

  @override
  String onboardingImportReadFileFailed(Object error) {
    return 'Failed to read file: $error';
  }

  @override
  String get onboardingImportPasswordEmpty => 'Password cannot be empty';

  @override
  String get onboardingImportIncorrectPassword => 'Incorrect password';

  @override
  String onboardingImportDecryptionFailed(Object error) {
    return 'Decryption failed: $error';
  }

  @override
  String get onboardingImportUnencryptedBackup =>
      'This backup isn\'t encrypted. Re-export from the app to get a secure .prism file.';

  @override
  String get onboardingPrismExportHowToExport => 'How to export from Prism:';

  @override
  String get onboardingPrismExportStep1 => 'Open Prism on your other device';

  @override
  String get onboardingPrismExportStep2 =>
      'Go to Settings → Import & Export → Export Data';

  @override
  String get onboardingPrismExportStep3 =>
      'Save the .json or .prism file and select it below';

  @override
  String get onboardingPrismExportSelectFile => 'Select Export File';

  @override
  String get onboardingPrismExportEncryptedTitle => 'Encrypted Export';

  @override
  String get onboardingPrismExportEncryptedDescription =>
      'Enter the export password to unlock this Prism backup.';

  @override
  String get onboardingPrismExportPasswordHint => 'Export password';

  @override
  String get onboardingPrismExportUnlockButton => 'Unlock Export';

  @override
  String get onboardingPrismExportReadyToImport => 'Ready to import';

  @override
  String get onboardingPrismExportPreviewDescription =>
      'This will restore your exported Prism system and finish setup on this device.';

  @override
  String get onboardingPrismExportImportButton => 'Import and Continue';

  @override
  String get onboardingPrismExportImporting => 'Importing your Prism export...';

  @override
  String get onboardingSimplyPluralHowToExport =>
      'How to export from Simply Plural:';

  @override
  String get onboardingSimplyPluralStep1 => 'Open Simply Plural app';

  @override
  String get onboardingSimplyPluralStep2 => 'Go to Settings → Export Data';

  @override
  String get onboardingSimplyPluralStep3 =>
      'Save the JSON file and select it below';

  @override
  String get onboardingSimplyPluralSelectFile => 'Select Export File';

  @override
  String get onboardingSimplyPluralReadingFile => 'Reading file...';

  @override
  String get onboardingSimplyPluralFoundData => 'Found data:';

  @override
  String get onboardingSimplyPluralImportButton => 'Import Data';

  @override
  String get onboardingSimplyPluralImportComplete =>
      'Import complete! Your data is ready.';

  @override
  String get onboardingImportPreviewMembers => 'Members';

  @override
  String get onboardingImportPreviewFrontingSessions => 'Fronting sessions';

  @override
  String get onboardingImportPreviewConversations => 'Conversations';

  @override
  String get onboardingImportPreviewMessages => 'Messages';

  @override
  String get onboardingImportPreviewHabits => 'Habits';

  @override
  String get onboardingImportPreviewNotes => 'Notes';

  @override
  String get onboardingImportPreviewTotalRecords => 'Total records';

  @override
  String get onboardingImportPreviewCustomFronts => 'Custom fronts';

  @override
  String get onboardingImportPreviewGroups => 'Groups';

  @override
  String get onboardingImportPreviewPolls => 'Polls';

  @override
  String get onboardingImportPreviewCustomFields => 'Custom fields';

  @override
  String get onboardingImportPreviewComments => 'Comments';

  @override
  String get onboardingImportPreviewReminders => 'Reminders';

  @override
  String get onboardingImportPreviewSleepSessions => 'Sleep sessions';

  @override
  String get onboardingImportPreviewFriends => 'Friends';

  @override
  String get onboardingImportPreviewMediaAttachments => 'Media attachments';

  @override
  String get onboardingDataReadyMembers => 'Members';

  @override
  String get onboardingDataReadyFrontingSessions => 'Fronting sessions';

  @override
  String get onboardingDataReadyConversations => 'Conversations';

  @override
  String get onboardingDataReadyMessages => 'Messages';

  @override
  String get onboardingDataReadyHabits => 'Habits';

  @override
  String get onboardingDataReadyNotes => 'Notes';

  @override
  String get onboardingDataReadySyncedData => 'Synced data';

  @override
  String get onboardingSystemNameHint => 'Enter system name';

  @override
  String get onboardingSystemNameHelperText =>
      'This is how your system will be identified in the app.';

  @override
  String get onboardingSystemNameHelperTextImported =>
      'We pulled this from your import — edit it if you\'d like something different.';

  @override
  String get onboardingWhosFrontingSelectHint =>
      'Tap to select who is currently fronting';

  @override
  String onboardingWhosFrontingNoMembers(String termPluralLower) {
    return 'No $termPluralLower added yet.\nGo back to add $termPluralLower first.';
  }

  @override
  String get onboardingChatSuggestedChannels => 'Suggested Channels';

  @override
  String get onboardingChatCustomChannel => 'Custom Channel';

  @override
  String get onboardingChatChannelNameHint => 'Channel name';

  @override
  String onboardingChatChannelAllMembers(
    String termPlural,
    Object termPluralLower,
  ) {
    return 'All $termPlural';
  }

  @override
  String get onboardingChatChannelVenting => 'Venting';

  @override
  String get onboardingChatChannelPlanning => 'Planning';

  @override
  String get onboardingChatChannelJournal => 'Journal';

  @override
  String get onboardingChatChannelUpdates => 'Updates';

  @override
  String get onboardingChatChannelRandom => 'Random';

  @override
  String get onboardingPreferencesTerminology => 'Terminology';

  @override
  String get onboardingPreferencesCustomTerminology => 'Custom';

  @override
  String get onboardingPreferencesSingularHint => 'Singular (e.g. Alter)';

  @override
  String get onboardingPreferencesPluralHint => 'Plural (e.g. Alters)';

  @override
  String get onboardingPreferencesAccentColor => 'Accent Color';

  @override
  String onboardingPreferencesPerMemberColors(
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Per-$termSingular Colors';
  }

  @override
  String onboardingPreferencesPerMemberColorsSubtitle(
    String termSingularLower,
  ) {
    return 'Let each $termSingularLower have their own accent color';
  }

  @override
  String get onboardingSyncJoinYourGroup => 'Join your sync group';

  @override
  String get onboardingSyncJoinDescription =>
      'Create a pairing request on this device and have an existing device approve it.';

  @override
  String get onboardingSyncRequestToJoin => 'Request to Join';

  @override
  String get onboardingSyncRequestToJoinHint =>
      'Show a QR code for your existing device to scan and approve.';

  @override
  String get onboardingSyncShowToExistingDevice =>
      'Show this to your existing device';

  @override
  String get onboardingSyncScanInstructions =>
      'On your existing device, open \"Set Up Another Device\" and scan this code.';

  @override
  String get onboardingSyncWaitingForScan =>
      'Waiting for other device to scan...';

  @override
  String get onboardingSyncWaitingForVerification =>
      'Waiting for security verification...';

  @override
  String get onboardingSyncWaitingForVerificationSubtitle =>
      'The other device is connecting. Security codes will appear shortly.';

  @override
  String get onboardingSyncVerifySecurityCode => 'Verify Security Code';

  @override
  String get onboardingSyncVerifyDescription =>
      'Confirm these words match the ones shown on your existing device.';

  @override
  String get onboardingSyncTheyMatch => 'They Match';

  @override
  String get onboardingSyncTheyDontMatch => 'They Don\'t Match';

  @override
  String get onboardingSyncEnterPassword => 'Enter your sync PIN';

  @override
  String get onboardingSyncEnterPasswordDescription =>
      'Enter the 6-digit PIN from the device you\'re syncing with.';

  @override
  String get onboardingSyncConnecting => 'Pairing and syncing...';

  @override
  String get onboardingSyncConnectingSubtitle =>
      'This may take a moment while the device is enrolled.';

  @override
  String get onboardingSyncDataStillSyncing =>
      'Some data is still syncing and will appear shortly.';

  @override
  String get onboardingSyncWelcomeBackTitle => 'Welcome Back!';

  @override
  String get onboardingSyncWelcomeBackDescription =>
      'Your device has been paired and your data is ready.';

  @override
  String get onboardingSyncUnknownError => 'An unknown error occurred.';

  @override
  String get habitsNewHabit => 'New Habit';

  @override
  String get habitsEditHabit => 'Edit Habit';

  @override
  String get habitsSectionBasicInfo => 'BASIC INFO';

  @override
  String get habitsFieldName => 'Name';

  @override
  String get habitsFieldNameHint => 'e.g., Morning meditation';

  @override
  String get habitsFieldDescription => 'Description (optional)';

  @override
  String get habitsSectionSchedule => 'SCHEDULE';

  @override
  String get habitsIntervalEvery => 'Every ';

  @override
  String get habitsIntervalDays => ' days';

  @override
  String get habitsIntervalDecrease => 'Decrease interval';

  @override
  String get habitsIntervalIncrease => 'Increase interval';

  @override
  String get habitsSectionNotifications => 'NOTIFICATIONS';

  @override
  String get habitsEnableReminders => 'Enable Reminders';

  @override
  String get habitsReminderTime => 'Reminder Time';

  @override
  String get habitsReminderTimeNotSet => 'Not set';

  @override
  String habitsReminderSetFor(String time) {
    return 'Reminder set for $time';
  }

  @override
  String get habitsCustomMessageField => 'Custom message (optional)';

  @override
  String get habitsSectionAssignment => 'ASSIGNMENT';

  @override
  String habitsAssignedMember(String termSingular) {
    return 'Assigned $termSingular';
  }

  @override
  String get habitsAssignedMemberAnyone => 'Anyone';

  @override
  String get habitsOnlyNotifyWhenFronting => 'Only notify when fronting';

  @override
  String habitsOnlyFrontingCaveat(String termSingularLower) {
    return 'Reminders will fire even if this $termSingularLower isn\'t fronting — fronting-aware delivery requires background access.';
  }

  @override
  String get habitsPrivate => 'Private';

  @override
  String get habitsPrivateSubtitle => 'Hide from shared views';

  @override
  String get habitsCompleteHabit => 'Complete Habit';

  @override
  String get habitsCompletedAt => 'Completed At';

  @override
  String get habitsCompletedBy => 'Completed By';

  @override
  String get habitsSectionRating => 'RATING';

  @override
  String habitsRateNStars(int n) {
    return 'Rate $n out of 5 stars';
  }

  @override
  String habitsRateNStarsTooltip(int n) {
    return 'Rate $n stars';
  }

  @override
  String get habitsNotesField => 'Notes (optional)';

  @override
  String get habitsDetailDeleteTitle => 'Delete Habit';

  @override
  String get habitsDetailDeleteMessage =>
      'This will permanently delete this habit and all its completions. This action cannot be undone.';

  @override
  String get habitsDetailMoreOptions => 'More options';

  @override
  String habitsDetailFrequencyEveryNDays(int n) {
    return 'Every $n days';
  }

  @override
  String get habitsDetailSectionRecentCompletions => 'Recent completions';

  @override
  String get habitsDetailNoCompletions => 'No completions yet';

  @override
  String get habitsDetailNoCompletionsSubtitle =>
      'Complete this habit to start tracking progress.';

  @override
  String get habitsStatCompletions => 'Completions';

  @override
  String get habitsStatCompletionRate => 'Completion Rate';

  @override
  String habitsStatCurrentStreak(int count) {
    return '$count streak';
  }

  @override
  String habitsStatBestStreak(int count) {
    return '$count best';
  }

  @override
  String habitsStatsSemanticsLabel(int completions, String rate) {
    return '$completions completions, $rate% completion rate';
  }

  @override
  String habitsCompletionRatedNStars(int n) {
    return 'Rated $n out of 5 stars';
  }

  @override
  String habitsCompletionTileToday(String time) {
    return 'Today $time';
  }

  @override
  String habitsCompletionTileYesterday(String time) {
    return 'Yesterday $time';
  }

  @override
  String get habitsAlreadyCompleted =>
      'Habit already completed for this period';

  @override
  String get habitsCompleteButtonLabel => 'Complete habit';

  @override
  String get habitsCompleted => 'Completed';

  @override
  String get habitsComplete => 'Complete';

  @override
  String get habitsListTitle => 'Habits';

  @override
  String get habitsCreateHabitTooltip => 'Create habit';

  @override
  String get habitsEmptyTitle => 'No habits yet';

  @override
  String get habitsEmptySubtitle =>
      'Create habits to track daily routines, self-care, or anything your system wants to keep up with.';

  @override
  String get habitsEmptyCreateLabel => 'Create Habit';

  @override
  String get habitsSectionUpcoming => 'Upcoming';

  @override
  String get habitsSectionInactive => 'Inactive';

  @override
  String habitsWeeklyProgressSemantics(int completed, int total) {
    return '$completed of $total days completed this week';
  }

  @override
  String get habitsTodayAllDone => 'all done';

  @override
  String get habitsTodaySemantics => 'Today';

  @override
  String get habitsTodayAllDoneSemantics => 'Today, all habits complete';

  @override
  String get habitsTodayHeader => 'Today';

  @override
  String get habitsSectionComplete => 'Complete';

  @override
  String habitsChipCompletedSemantics(String name) {
    return '$name, completed';
  }

  @override
  String habitsChipCompleteSemantics(String name) {
    return 'Complete $name';
  }

  @override
  String habitsColorSemantics(String hex, String selected) {
    return 'Color #$hex$selected';
  }

  @override
  String get habitsColorSelected => ', selected';

  @override
  String get pollsNewPoll => 'New Poll';

  @override
  String get pollsQuestionLabel => 'Question';

  @override
  String get pollsQuestionHint => 'What do you want to ask?';

  @override
  String get pollsDescriptionLabel => 'Description (optional)';

  @override
  String get pollsDescriptionHint => 'Add context or details...';

  @override
  String get pollsOptionsHeader => 'Options';

  @override
  String pollsOptionLabel(int n) {
    return 'Option $n';
  }

  @override
  String get pollsRemoveOptionTooltip => 'Remove option';

  @override
  String get pollsAddOption => 'Add option';

  @override
  String get pollsAddOtherOption => 'Add \"Other\" option';

  @override
  String get pollsAddOtherOptionSubtitle => 'Allows free-text responses';

  @override
  String get pollsAnonymousVoting => 'Anonymous voting';

  @override
  String get pollsAnonymousVotingSubtitle => 'Hide who voted for what';

  @override
  String get pollsAllowMultipleVotes => 'Allow multiple votes';

  @override
  String pollsAllowMultipleVotesSubtitle(String plural) {
    return '$plural can vote for more than one option';
  }

  @override
  String get pollsSetExpiration => 'Set expiration';

  @override
  String get pollsNoExpiration => 'Poll stays open until manually closed';

  @override
  String get pollsPickDateTime => 'Pick date & time';

  @override
  String pollsChangeDateTime(String datetime) {
    return 'Change: $datetime';
  }

  @override
  String pollsCreateError(Object error) {
    return 'Failed to create poll: $error';
  }

  @override
  String get pollsListTitle => 'Polls';

  @override
  String get pollsCreateTooltip => 'Create poll';

  @override
  String get pollsFilterActive => 'Active';

  @override
  String get pollsFilterClosed => 'Closed';

  @override
  String get pollsFilterAll => 'All';

  @override
  String get pollsEmptyActiveTitle => 'No active polls';

  @override
  String get pollsEmptyActiveSubtitle =>
      'Create a poll to get your system voting';

  @override
  String get pollsEmptyClosedTitle => 'No closed polls';

  @override
  String get pollsEmptyClosedSubtitle =>
      'Closed and expired polls will appear here';

  @override
  String get pollsEmptyAllTitle => 'No polls yet';

  @override
  String get pollsEmptyAllSubtitle => 'Create your first poll to get started';

  @override
  String get pollsEmptyCreateLabel => 'Create Poll';

  @override
  String get pollsLoadError => 'Error loading polls';

  @override
  String pollsVoteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '1 vote',
    );
    return '$_temp0';
  }

  @override
  String pollsOptionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count options',
      one: '1 option',
    );
    return '$_temp0';
  }

  @override
  String get pollsExpired => 'Expired';

  @override
  String get pollsClosed => 'Closed';

  @override
  String pollsCountdownDays(int n) {
    return '${n}d left';
  }

  @override
  String pollsCountdownHours(int n) {
    return '${n}h left';
  }

  @override
  String pollsCountdownMinutes(int n) {
    return '${n}m left';
  }

  @override
  String get pollsCountdownEndingSoon => 'Ending soon';

  @override
  String get pollsAnonymous => 'Anonymous';

  @override
  String get pollsMultiVote => 'Multi-vote';

  @override
  String pollsDetailLoadError(Object error) {
    return 'Error loading poll: $error';
  }

  @override
  String get pollsDetailNotFound => 'Poll not found';

  @override
  String get pollsDetailClosePollTooltip => 'Close poll';

  @override
  String get pollsDetailMoreOptions => 'More options';

  @override
  String get pollsDetailResultsLabel => 'Results';

  @override
  String get pollsDetailOptionsLabel => 'Options';

  @override
  String get pollsDetailVoteAs => 'Vote as';

  @override
  String pollsDetailNoMembers(String termPluralLower) {
    return 'No $termPluralLower available';
  }

  @override
  String get pollsDetailSubmitVote => 'Submit Vote';

  @override
  String get pollsDetailVoteSubmitted => 'Vote submitted';

  @override
  String pollsDetailVoteError(Object error) {
    return 'Failed to vote: $error';
  }

  @override
  String get pollsDetailClosePollTitle => 'Close poll?';

  @override
  String get pollsDetailClosePollMessage =>
      'No more votes can be cast once the poll is closed. This cannot be undone.';

  @override
  String get pollsDetailClosePollConfirm => 'Close Poll';

  @override
  String get pollsDetailDeleteTitle => 'Delete poll?';

  @override
  String get pollsDetailDeleteMessage =>
      'This will permanently delete the poll and all votes. This action cannot be undone.';

  @override
  String get pollsDetailExpired => 'Expired';

  @override
  String pollsDetailExpiresLabel(String date) {
    return 'Expires $date';
  }

  @override
  String get pollsDetailOtherResponseHint => 'Enter your response...';

  @override
  String pollsNotificationBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count polls need',
      one: '1 poll needs',
    );
    return '$_temp0 your vote';
  }

  @override
  String get migrationImportData => 'Import Data';

  @override
  String get migrationReadingFile => 'Reading file…';

  @override
  String get migrationVerifyingToken => 'Verifying token…';

  @override
  String get migrationImportFromSimplyPlural => 'Import from Simply Plural';

  @override
  String get migrationImportDescription =>
      'Bring your existing data into Prism. Choose how you would like to import your Simply Plural data.';

  @override
  String get migrationConnectWithApi => 'Connect with API';

  @override
  String get migrationConnectWithApiSubtitle =>
      'No file export needed — imports directly from your account';

  @override
  String get migrationRecommended => 'Recommended';

  @override
  String get migrationImportFromFile => 'Import from file';

  @override
  String get migrationImportFromFileSubtitle =>
      'Use a JSON export file from Simply Plural';

  @override
  String get migrationSupportedDataTypes => 'Supported data types';

  @override
  String migrationSupportedMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get migrationSupportedCustomFronts => 'Custom fronts';

  @override
  String get migrationSupportedFrontingHistory => 'Fronting history';

  @override
  String get migrationSupportedChatChannels => 'Chat channels & messages';

  @override
  String get migrationSupportedPolls => 'Polls';

  @override
  String migrationSupportedMemberColors(String termSingular) {
    return '$termSingular colors';
  }

  @override
  String migrationSupportedMemberDescriptions(String termSingular) {
    return '$termSingular descriptions';
  }

  @override
  String get migrationSupportedAvatarImages => 'Avatar images';

  @override
  String get migrationSupportedNotes => 'Notes';

  @override
  String get migrationSupportedCustomFields => 'Custom fields';

  @override
  String get migrationSupportedGroups => 'Groups';

  @override
  String get migrationSupportedComments => 'Comments on front sessions';

  @override
  String get migrationSupportedReminders => 'Reminders';

  @override
  String get migrationConnectToSimplyPlural => 'Connect to Simply Plural';

  @override
  String get migrationEnterTokenDescription =>
      'Enter your API token to import data directly.';

  @override
  String get migrationApiTokenLabel => 'API Token';

  @override
  String get migrationPasteTokenHint => 'Paste your token here';

  @override
  String get migrationShowToken => 'Show token';

  @override
  String get migrationHideToken => 'Hide token';

  @override
  String get migrationPasteFromClipboard => 'Paste from clipboard';

  @override
  String get migrationWhereDoIFindThis => 'Where do I find this?';

  @override
  String get migrationTokenHelpText =>
      'In Simply Plural, go to Settings → Account → Tokens. Create a new token with Read permission and copy it.';

  @override
  String get migrationVerifyToken => 'Verify Token';

  @override
  String get migrationConnected => 'Connected';

  @override
  String migrationSignedInAs(String username) {
    return 'Signed in as $username';
  }

  @override
  String get migrationContinue => 'Continue';

  @override
  String get migrationFetchingData => 'Fetching data from Simply Plural…';

  @override
  String get migrationPreviewImport => 'Preview Import';

  @override
  String get migrationPreviewDescription =>
      'Review what was found before importing.';

  @override
  String get migrationImportInfoNote =>
      'Imported data will be added alongside any existing data. Nothing will be overwritten.';

  @override
  String get migrationRemindersApiNote =>
      'Reminders are not available via the API. To import reminders, use a file export instead.';

  @override
  String get migrationImportAllAddToExisting => 'Import All (add to existing)';

  @override
  String get migrationStartFresh => 'Start Fresh (replace all data)';

  @override
  String get migrationImportAll => 'Import All';

  @override
  String get migrationReplaceAllTitle => 'Replace all data?';

  @override
  String migrationReplaceAllMessage(String termPluralLower) {
    return 'This will delete all existing $termPluralLower, front history, conversations, and other data before importing. This action cannot be undone.\n\nIf you have sync set up, other paired devices should also be reset to avoid conflicts.';
  }

  @override
  String get migrationReplaceAll => 'Replace All';

  @override
  String get migrationImporting => 'Importing…';

  @override
  String get migrationImportComplete => 'Import Complete';

  @override
  String migrationImportSuccess(int total, int seconds) {
    return 'Successfully imported $total items in ${seconds}s.';
  }

  @override
  String get migrationSummary => 'Summary';

  @override
  String migrationResultMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get migrationResultFrontSessions => 'Front sessions';

  @override
  String get migrationResultConversations => 'Conversations';

  @override
  String get migrationResultMessages => 'Messages';

  @override
  String get migrationResultPolls => 'Polls';

  @override
  String get migrationResultNotes => 'Notes';

  @override
  String get migrationResultComments => 'Comments';

  @override
  String get migrationResultCustomFields => 'Custom fields';

  @override
  String get migrationResultGroups => 'Groups';

  @override
  String get migrationResultReminders => 'Reminders';

  @override
  String get migrationResultAvatarsDownloaded => 'Avatars downloaded';

  @override
  String migrationWarnings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '1 warning',
    );
    return '$_temp0';
  }

  @override
  String get migrationNotImportedTitle => 'What didn\'t come over';

  @override
  String get migrationNotImportedFriendsTitle => 'Friends';

  @override
  String get migrationNotImportedFriendsDetail =>
      'SP friends are separate accounts on another system. Prism doesn\'t have a cross-system friends concept yet.';

  @override
  String get migrationNotImportedBoardMetaTitle => 'Board message metadata';

  @override
  String get migrationNotImportedBoardMetaDetail =>
      'Message categories and bucket assignments aren\'t part of the export format.';

  @override
  String get migrationNotImportedNotifTitle => 'Notification preferences';

  @override
  String get migrationNotImportedNotifDetail =>
      'These are stored on your device in SP and aren\'t included in the export.';

  @override
  String get migrationNotImportedFrontRulesTitle =>
      'Custom front display rules';

  @override
  String get migrationNotImportedFrontRulesDetail =>
      'Display rules and front conditions don\'t map to Prism\'s system.';

  @override
  String get migrationImportFailed => 'Import Failed';

  @override
  String get migrationTryFileImport => 'Try file import instead';

  @override
  String get migrationUnknownError => 'An unknown error occurred.';

  @override
  String migrationPreviewSystem(String name) {
    return 'System: $name';
  }

  @override
  String get migrationPreviewDataFound => 'Data found';

  @override
  String get migrationPreviewFrontHistoryEntries => 'Front history entries';

  @override
  String get migrationPreviewChatChannels => 'Chat channels';

  @override
  String get migrationPreviewMessages => 'Messages';

  @override
  String get migrationPreviewTotalEntities => 'Total entities';

  @override
  String get migrationPreviewWarnings => 'Warnings';

  @override
  String get migrationPreviewCustomFronts => 'Custom fronts';

  @override
  String get migrationPreviewGroups => 'Groups';

  @override
  String get migrationPreviewPolls => 'Polls';

  @override
  String get pluralkitTitle => 'PluralKit';

  @override
  String get pluralkitAccount => 'PluralKit Account';

  @override
  String get pluralkitSyncDirection => 'Sync Direction';

  @override
  String get pluralkitSyncActions => 'Sync Actions';

  @override
  String get pluralkitHowItWorks => 'How It Works';

  @override
  String get pluralkitDisconnectTitle => 'Disconnect PluralKit?';

  @override
  String get pluralkitDisconnectMessage =>
      'This will remove your token and disconnect from PluralKit. Your imported data will remain in the app.';

  @override
  String get pluralkitDisconnect => 'Disconnect';

  @override
  String get pluralkitConnected => 'Connected';

  @override
  String pluralkitLastSync(String when) {
    return 'Last sync: $when';
  }

  @override
  String pluralkitLastManualSync(String when) {
    return 'Last manual sync: $when';
  }

  @override
  String get pluralkitTokenLabel => 'PluralKit Token';

  @override
  String get pluralkitPasteTokenHint => 'Paste your token here';

  @override
  String get pluralkitConnect => 'Connect';

  @override
  String get pluralkitTokenHelp =>
      'To get your token, DM the PluralKit bot on Discord with \"pk;token\" and paste the result here.';

  @override
  String get pluralkitFileImportHelp =>
      'Recover old PluralKit fronting history with a pk;export file and token. The file provides the switch history; the token lets Prism match it safely.';

  @override
  String get pluralkitImportButton => 'Import from PluralKit';

  @override
  String get pluralkitSyncRecent => 'Sync Recent Changes';

  @override
  String pluralkitSyncRecentCooldown(int seconds) {
    return 'Sync Recent Changes (${seconds}s)';
  }

  @override
  String get pluralkitSyncDirectionDescription =>
      'Choose how data flows between Prism and PluralKit.';

  @override
  String get pluralkitPull => 'Pull';

  @override
  String get pluralkitBoth => 'Both';

  @override
  String get pluralkitPush => 'Push';

  @override
  String get pluralkitLastSyncSummary => 'Last Sync Summary';

  @override
  String get pluralkitUpToDate => 'Everything is up to date.';

  @override
  String pluralkitMembersPulled(int count, String termForCount) {
    return '$count $termForCount pulled';
  }

  @override
  String pluralkitMembersPushed(int count, String termForCount) {
    return '$count $termForCount pushed';
  }

  @override
  String pluralkitSwitchesPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count switches pulled',
      one: '1 switch pulled',
    );
    return '$_temp0';
  }

  @override
  String pluralkitSwitchesPushed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count switches pushed',
      one: '1 switch pushed',
    );
    return '$_temp0';
  }

  @override
  String pluralkitMembersUnchanged(int count, String termForCount) {
    return '$count $termForCount unchanged';
  }

  @override
  String get pluralkitInfoSync =>
      'Supports pull, push, or bidirectional sync. Choose your preferred direction above.';

  @override
  String get pluralkitInfoToken =>
      'Your token is stored securely in the device keychain and never leaves your device.';

  @override
  String pluralkitInfoMembers(String termPluralLower) {
    return 'After connecting, link your PluralKit members to Prism $termPluralLower — or import them as new — so nothing gets duplicated.';
  }

  @override
  String get pluralkitInfoSwitches =>
      'Fronting history recovery uses a pk;export file plus a token so Prism can match export switches to PluralKit switch IDs.';

  @override
  String get pluralkitJustNow => 'Just now';

  @override
  String get pluralkitRepairThisGroup => 'This group';

  @override
  String get pluralkitRepairPkGroup => 'PK group';

  @override
  String get pluralkitRepairPluralKitGroup => 'PluralKit group';

  @override
  String get pluralkitRepairReconnectForComparison =>
      'Reconnect PluralKit to see comparison details';

  @override
  String pluralkitRepairSharedPkMembers(
    int count,
    String termSingularLower,
    String termPluralLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shared PK $termPluralLower',
      one: '1 shared PK $termSingularLower',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairLocalOnlyMembers(
    int count,
    String termSingularLower,
    String termPluralLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count local-only $termPluralLower',
      one: '1 local-only $termSingularLower',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairOnlyInPkMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count only in PK',
      one: '1 only in PK',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSuspectedPkUuid(String uuid) {
    return 'Suspected PK UUID: $uuid';
  }

  @override
  String pluralkitRepairMergeActionPreview(String summary) {
    return 'Using this match will $summary.';
  }

  @override
  String get pluralkitRepairPreviewLinkLocalGroup =>
      'link this local group to the suspected PK group';

  @override
  String pluralkitRepairPreviewPreserveShared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shared PK memberships',
      one: '1 shared PK membership',
    );
    return 'preserve $_temp0';
  }

  @override
  String pluralkitRepairPreviewKeepLocalOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count local-only memberships',
      one: '1 local-only membership',
    );
    return 'keep $_temp0';
  }

  @override
  String pluralkitRepairPreviewLeavePkOnly(
    int count,
    String termSingularLower,
    String termPluralLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PK-only $termPluralLower',
      one: '1 PK-only $termSingularLower',
    );
    return 'leave $_temp0 unmatched';
  }

  @override
  String get pluralkitRepairUsePluralKitMatch => 'Use this PluralKit match';

  @override
  String get pluralkitRepairKeepMyPrismGroup => 'Keep my Prism group';

  @override
  String get pluralkitRepairDismissFalsePositive => 'Dismiss false positive';

  @override
  String get pluralkitRepairSection => 'Group repair';

  @override
  String get pluralkitRepairTemporaryTokenTitle => 'Temporary PluralKit token';

  @override
  String get pluralkitRepairTemporaryTokenBody =>
      'Use a one-off token for this repair run only. Prism will not save it.';

  @override
  String get pluralkitRepairTokenLabel => 'PluralKit token';

  @override
  String get pluralkitRepairTokenHint => 'Paste a temporary token';

  @override
  String get pluralkitRepairTemporaryTokenHelp =>
      'This token is only used to compare your local groups against live PluralKit group data for one repair run.';

  @override
  String get pluralkitRepairRunTokenBacked => 'Run token-backed repair';

  @override
  String get pluralkitRepairLoadingStatus => 'Loading repair status...';

  @override
  String get pluralkitRepairCardTitle => 'PluralKit group repair';

  @override
  String get pluralkitRepairRunLocal => 'Run local repair';

  @override
  String get pluralkitRepairRun => 'Run repair';

  @override
  String get pluralkitRepairResetAndReimport => 'Reset PK groups and re-import';

  @override
  String get pluralkitRepairResetOnly => 'Reset PK groups only';

  @override
  String get pluralkitRepairCurrentStatus => 'Current status';

  @override
  String get pluralkitRepairPendingReview => 'Pending review';

  @override
  String get pluralkitRepairLastRun => 'Last run';

  @override
  String get pluralkitRepairWhatChanged => 'What changed';

  @override
  String get pluralkitRepairUseTemporaryToken => 'Use temporary token';

  @override
  String get pluralkitRepairCutoverTitle => 'PK group sync v2 cutover';

  @override
  String get pluralkitRepairSharedEnablement => 'Shared enablement';

  @override
  String get pluralkitRepairEnablePkGroupSync => 'Enable PK group sync';

  @override
  String get pluralkitRepairHeadlineRunning =>
      'Scanning linked groups, repairing obvious duplicates, and cross-checking live PK groups when a token is available.';

  @override
  String get pluralkitRepairHeadlinePending =>
      'Ambiguous imported groups are currently suppressed so Prism does not create duplicate sync links.';

  @override
  String get pluralkitRepairHeadlineReconnectRequired =>
      'Local repair can still restore directly provable PK links, but reconnecting PluralKit is still required to reconstruct missing PK group identity automatically.';

  @override
  String get pluralkitRepairHeadlineChanged =>
      'The last run made concrete local repair changes. Review the summary below before enabling PK-backed group sync.';

  @override
  String get pluralkitRepairHeadlineCompleted =>
      'The last run completed. You can rerun repair after reconnecting or importing more PluralKit data.';

  @override
  String get pluralkitRepairHeadlineDefault =>
      'Fixes obvious PK group duplicates locally and flags ambiguous matches for follow-up review.';

  @override
  String get pluralkitRepairStatusRunning => 'Repair running';

  @override
  String get pluralkitRepairStatusRetryNeeded => 'Retry needed';

  @override
  String pluralkitRepairStatusPendingReview(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending review',
      one: '1 pending review',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairStatusLastRunComplete => 'Last run complete';

  @override
  String get pluralkitRepairStatusReadyToRun => 'Ready to run';

  @override
  String get pluralkitRepairTokenBackedReady => 'Token-backed ready';

  @override
  String get pluralkitRepairLocalOnlyUntilToken => 'Local-only until token';

  @override
  String get pluralkitRepairCheckingTokenAccess => 'Checking token access';

  @override
  String get pluralkitRepairCutoverEnabledChip => 'PK sync v2 enabled';

  @override
  String get pluralkitRepairCutoverOffChip => 'PK sync v2 off';

  @override
  String get pluralkitRepairCheckingCutover => 'Checking cutover';

  @override
  String get pluralkitRepairCurrentRunning => 'Repair is running now.';

  @override
  String get pluralkitRepairCurrentError =>
      'The last manual run failed. Retry below when you are ready.';

  @override
  String pluralkitRepairCurrentPending(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count groups still need review before they can be linked or cleared.',
      one: '1 group still needs review before it can be linked or cleared.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairCurrentNoRun =>
      'No repair run has been recorded in this app session yet.';

  @override
  String get pluralkitRepairCurrentReconnectRequired =>
      'The last run finished the safe local repair pass, but missing PK group identity still needs a live PluralKit reference source to be reconstructed automatically.';

  @override
  String get pluralkitRepairCurrentChanged =>
      'The last run changed local PK group data. See the last-run summary below for the exact repairs applied.';

  @override
  String get pluralkitRepairCurrentNoChanges =>
      'The last run did not find any new PK group repairs to apply.';

  @override
  String get pluralkitRepairCutoverHeadlineEnabled =>
      'PK-backed group sync is enabled for this sync group. Manual/local-only groups still stay local.';

  @override
  String get pluralkitRepairCutoverHeadlineReady =>
      'Local repair prerequisites are satisfied. The remaining safety boundary is explicit operator confirmation of cutover.';

  @override
  String get pluralkitRepairCutoverHeadlineBlocked =>
      'PK-backed group sync stays off until repair is complete and you explicitly confirm that legacy devices are no longer paired.';

  @override
  String get pluralkitRepairCutoverStatusLoading =>
      'Loading the shared cutover setting for this sync group.';

  @override
  String get pluralkitRepairCutoverStatusEnabled =>
      'Enabled for this sync group after explicit confirmation.';

  @override
  String get pluralkitRepairCutoverStatusRunning =>
      'Unavailable while repair is still running.';

  @override
  String get pluralkitRepairCutoverStatusNoRun =>
      'Unavailable until a repair run completes in this app session.';

  @override
  String get pluralkitRepairCutoverStatusPending =>
      'Unavailable until pending review items are resolved or kept local-only.';

  @override
  String get pluralkitRepairCutoverStatusReady =>
      'Ready to enable after explicit cutover confirmation.';

  @override
  String get pluralkitRepairCutoverRecommendationEnabled =>
      'This only affects PK-backed group sync. Manual/local-only groups remain unaffected.';

  @override
  String get pluralkitRepairCutoverRecommendationRunFirst =>
      'Run repair first. Prism keeps PK group sync v2 off until this client has completed a repair pass.';

  @override
  String get pluralkitRepairCutoverRecommendationPending =>
      'Resolve each pending review item or explicitly keep it local-only before enabling cutover.';

  @override
  String get pluralkitRepairCutoverRecommendationReady =>
      'Only enable after every legacy 0.4.0+1-era device in this sync group has been upgraded, reset/re-paired, removed, or after you moved testing to a fresh sync group.';

  @override
  String get pluralkitRepairPendingNone =>
      'No ambiguous PK group matches are waiting for review.';

  @override
  String pluralkitRepairPendingCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups still need follow-up review.',
      one: '1 group still needs follow-up review.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairModeLocalOnlyRun => 'Local-only run';

  @override
  String get pluralkitRepairModeStoredTokenRun => 'Stored-token run';

  @override
  String get pluralkitRepairModeTemporaryTokenRun => 'Temporary-token run';

  @override
  String get pluralkitRepairLastRunPrefixLocal => 'Local run';

  @override
  String get pluralkitRepairLastRunPrefixStoredToken => 'Stored-token run';

  @override
  String get pluralkitRepairLastRunPrefixTemporaryToken =>
      'Temporary-token run';

  @override
  String pluralkitRepairLastRunNoChanges(Object prefix) {
    return '$prefix found no new PK group changes to apply.';
  }

  @override
  String pluralkitRepairLastRunChanged(Object prefix, Object summary) {
    return '$prefix $summary.';
  }

  @override
  String pluralkitRepairJoinPair(Object first, Object second) {
    return '$first and $second';
  }

  @override
  String pluralkitRepairJoinSerial(Object last, Object leading) {
    return '$leading, and $last';
  }

  @override
  String pluralkitRepairSummaryUpdatedParentLinks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'updated $count child-group parent links',
      one: 'updated 1 child-group parent link',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryMovedMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'moved $count group memberships',
      one: 'moved 1 group membership',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRemovedDuplicateGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'removed $count duplicate local groups',
      one: 'removed 1 duplicate local group',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRemovedConflictingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'removed $count conflicting group memberships',
      one: 'removed 1 conflicting group membership',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummarySuppressedAmbiguousGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'suppressed $count ambiguous groups for review',
      one: 'suppressed 1 ambiguous group for review',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRestoredMissingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'restored $count missing PK membership links',
      one: 'restored 1 missing PK membership link',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRecordedLegacyAliases(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'recorded $count legacy group aliases',
      one: 'recorded 1 legacy group alias',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailUpdatedParentLinks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Updated $count child-group parent links to point at the surviving group.',
      one: 'Updated 1 child-group parent link to point at the surviving group.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailMovedMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Moved $count group memberships onto the surviving group.',
      one: 'Moved 1 group membership onto the surviving group.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRemovedDuplicateGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Removed $count duplicate local groups.',
      one: 'Removed 1 duplicate local group.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRemovedConflictingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Removed $count conflicting group memberships while merging duplicates.',
      one: 'Removed 1 conflicting group membership while merging duplicates.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailSuppressedAmbiguousGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Suppressed $count ambiguous groups for review before sync can continue.',
      one: 'Suppressed 1 ambiguous group for review before sync can continue.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRestoredMissingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restored $count missing PK membership links.',
      one: 'Restored 1 missing PK membership link.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRecordedLegacyAliases(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Recorded $count legacy group aliases so older group IDs still resolve.',
      one: 'Recorded 1 legacy group alias so older group IDs still resolve.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairReferenceImportOnly =>
      'This looks like import-only PK data with no local PK-linked groups left to use as repair references. Prism can still repair directly linked rows locally, but reconnecting PluralKit or using a temporary token is the only way to reconstruct missing PK group identity automatically.';

  @override
  String get pluralkitRepairReferenceStoredTokenFailed =>
      'A stored token exists, but the last live reference lookup failed. Reconnect PluralKit or use a temporary token if you want a full token-backed repair pass.';

  @override
  String get pluralkitRepairReferenceReconnectOrToken =>
      'Reconnect PluralKit above or use a temporary token for a fuller repair pass. Local repair still handles the obvious duplicates.';

  @override
  String get pluralkitRepairReferenceTokenRecommended =>
      'A token-backed repair run is recommended when you can provide one. Until then, Prism will only run the safe local repair pass.';

  @override
  String get pluralkitRepairReferenceLocalNow =>
      'Repair can run locally now. Live PK cross-checks appear once token access is confirmed.';

  @override
  String pluralkitRepairReferenceError(Object error) {
    return 'Live PK lookup failed on the last run, so Prism fell back to the local repair pass. $error';
  }

  @override
  String pluralkitRepairError(Object error) {
    return 'Repair failed: $error';
  }

  @override
  String get pluralkitRepairConfirmEnableTitle => 'Enable PK sync v2?';

  @override
  String get pluralkitRepairConfirmEnableBody =>
      'Only enable this after every legacy 0.4.0+1-era device has been upgraded, reset/re-paired, removed, or after you moved to a fresh sync group.';

  @override
  String get pluralkitRepairConfirmEnableFootnote =>
      'If any device is unaccounted for, keep this off. Manual/local-only groups stay local either way.';

  @override
  String get pluralkitRepairConfirmEnableAction => 'Enable PK sync v2';

  @override
  String get pluralkitRepairConfirmResetTitle => 'Reset PK groups only?';

  @override
  String get pluralkitRepairConfirmResetConnectedBody =>
      'Prism will remove PK-linked and repair-suppressed groups, keep manual/local-only groups, clear deferred PK membership ops, and then re-import your current PK groups.';

  @override
  String get pluralkitRepairConfirmResetDisconnectedBody =>
      'Prism will remove PK-linked and repair-suppressed groups, keep manual/local-only groups, and clear deferred PK membership ops. Reconnect PluralKit or import again afterward to rebuild them.';

  @override
  String get pluralkitRepairConfirmResetExportHint =>
      'Export data first if you want a full backup before the reset.';

  @override
  String get pluralkitRepairConfirmResetExportFirst => 'Export data first';

  @override
  String get pluralkitRepairConfirmResetActionConnected =>
      'Reset and re-import';

  @override
  String get pluralkitRepairConfirmResetActionDisconnected => 'Reset PK groups';

  @override
  String pluralkitRepairFailedToast(Object error) {
    return 'PluralKit group repair failed: $error';
  }

  @override
  String get pluralkitRepairReviewDismissed =>
      'Group review dismissed. Sync suppression was cleared.';

  @override
  String get pluralkitRepairKeepLocalOnlySuccess =>
      'Group kept local-only. It will stay out of sync.';

  @override
  String get pluralkitRepairMergedSuccess =>
      'Group linked to the PluralKit match.';

  @override
  String pluralkitRepairDismissReviewFailed(Object error) {
    return 'Could not dismiss this repair review item: $error';
  }

  @override
  String pluralkitRepairKeepLocalOnlyFailed(Object error) {
    return 'Could not keep this group local-only: $error';
  }

  @override
  String pluralkitRepairMergeFailed(Object error) {
    return 'Could not use this PluralKit match: $error';
  }

  @override
  String get pluralkitRepairCutoverSettingsLoadingError =>
      'Could not verify the shared cutover setting yet. Wait for repair status to finish loading and try again.';

  @override
  String get pluralkitRepairCutoverAlreadyEnabled =>
      'PK group sync v2 is already enabled for this sync group.';

  @override
  String get pluralkitRepairCutoverRepairLoadingError =>
      'Repair status is still loading or running. Wait for it to finish before enabling PK group sync v2.';

  @override
  String get pluralkitRepairCutoverRunRepairFirstError =>
      'Run PluralKit group repair first. PK group sync v2 stays off until this client completes a repair pass.';

  @override
  String pluralkitRepairCutoverPendingReviewError(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Resolve or keep local-only the $count pending review items before enabling PK group sync v2.',
      one:
          'Resolve or keep local-only the 1 pending review item before enabling PK group sync v2.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairCutoverEnabledSuccess =>
      'PK group sync v2 enabled for this sync group. Manual/local-only groups are unchanged.';

  @override
  String pluralkitRepairCutoverEnableFailed(Object error) {
    return 'Could not enable PK group sync v2: $error';
  }

  @override
  String get pluralkitRepairResetNoGroupsNeeded =>
      'No PK-backed or repair-suppressed groups needed reset on this device.';

  @override
  String pluralkitRepairResetFinishedReconnect(Object summary) {
    return 'PK group reset finished. $summary Reconnect PluralKit or import from a file to rebuild them.';
  }

  @override
  String pluralkitRepairResetFinishedReimported(Object summary) {
    return 'PK group reset finished. $summary Current PK groups were re-imported.';
  }

  @override
  String pluralkitRepairResetFinishedReimportFailed(
    Object error,
    Object summary,
  ) {
    return 'PK group reset finished, but re-import failed: $error. $summary';
  }

  @override
  String pluralkitRepairResetFailed(Object error) {
    return 'Could not reset PK groups: $error';
  }

  @override
  String get pluralkitRepairNoNewNeeded =>
      'No new PK group repairs were needed.';

  @override
  String pluralkitRepairSuccessLocalLookupFailed(Object detail) {
    return 'Repair finished locally. $detail Live PK lookup failed, so a token-backed rerun is still recommended.';
  }

  @override
  String pluralkitRepairSuccessLocalLookupFailedWithFollowUp(
    Object detail,
    Object followUp,
  ) {
    return 'Repair finished locally. $detail $followUp Live PK lookup failed, so a token-backed rerun is still recommended.';
  }

  @override
  String pluralkitRepairSuccessWithFollowUp(Object detail, Object followUp) {
    return 'Repair finished. $detail $followUp';
  }

  @override
  String pluralkitRepairSuccess(Object detail) {
    return 'Repair finished. $detail';
  }

  @override
  String pluralkitRepairFollowUpPendingReview(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suppressed groups still need follow-up review.',
      one: '1 suppressed group still needs follow-up review.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairStatusLoadFailed(Object error) {
    return 'Could not load repair status: $error';
  }

  @override
  String pluralkitRepairResetSummaryRemovedGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'removed $count PK-backed or suppressed groups',
      one: 'removed 1 PK-backed or suppressed group',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairResetSummaryPromotedChildGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'promoted $count local child groups to root',
      one: 'promoted 1 local child group to root',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairResetSummaryClearedDeferredOps(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'cleared $count deferred PK membership ops',
      one: 'cleared 1 deferred PK membership op',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairResetSummaryNoGroupsNeeded =>
      'No PK-backed groups needed reset.';

  @override
  String pluralkitMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String pluralkitHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String pluralkitDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get dataManagementExportTitle => 'Export Data';

  @override
  String get dataManagementImportTitle => 'Import Data';

  @override
  String get dataManagementImportExportTitle => 'Import & Export';

  @override
  String get dataManagementExportSectionTitle => 'Export';

  @override
  String get dataManagementImportSectionTitle => 'Import';

  @override
  String get dataManagementImportFromOtherApps => 'Import from Other Apps';

  @override
  String get dataManagementExportRowTitle => 'Export Data';

  @override
  String get dataManagementExportRowSubtitle =>
      'Create a password-protected backup';

  @override
  String get dataManagementImportRowTitle => 'Import Data';

  @override
  String get dataManagementImportRowSubtitle =>
      'Restore data from a Prism export file (.json or .prism)';

  @override
  String dataManagementPluralKitRowSubtitle(String termPluralLower) {
    return 'Import $termPluralLower & fronting via API token';
  }

  @override
  String get dataManagementSimplyPluralRowTitle => 'Simply Plural';

  @override
  String get dataManagementSimplyPluralRowSubtitle =>
      'Import from a Simply Plural export file';

  @override
  String get dataManagementExportYourData => 'Export Your Data';

  @override
  String dataManagementExportDescription(String termPluralLower) {
    return 'Create a password-protected backup of all your data including $termPluralLower, fronting sessions, messages, polls, and settings.';
  }

  @override
  String get dataManagementExportButton => 'Export Data';

  @override
  String get dataManagementEncryptExport => 'Encrypt Export';

  @override
  String get dataManagementEncryptDescription =>
      'Set a password to encrypt your export file. You will need this password to import the data later.';

  @override
  String get dataManagementUnencryptedWarning =>
      'Unencrypted exports are plain JSON. Anyone who opens the file can read its contents.';

  @override
  String get dataManagementPasswordLabel => 'Password';

  @override
  String get dataManagementPasswordHint =>
      'At least 12 characters — a long passphrase is best';

  @override
  String get dataManagementShowPassword => 'Show password';

  @override
  String get dataManagementHidePassword => 'Hide password';

  @override
  String get dataManagementConfirmPasswordLabel => 'Confirm Password';

  @override
  String get dataManagementExportUnencrypted => 'Export Unencrypted';

  @override
  String get dataManagementEncrypt => 'Encrypt';

  @override
  String get dataManagementExporting => 'Exporting your data…';

  @override
  String get dataManagementMayTakeMoment => 'This may take a moment.';

  @override
  String get dataManagementExportFailed => 'Export Failed';

  @override
  String get dataManagementRetry => 'Retry';

  @override
  String get dataManagementExportComplete => 'Export Complete';

  @override
  String get dataManagementExportWithoutEncryptionTitle =>
      'Export without encryption?';

  @override
  String get dataManagementExportWithoutEncryptionMessage =>
      'This will create a plain JSON file that anyone who opens it can read. Use encrypted export unless you specifically need an insecure backup.';

  @override
  String get dataManagementExportUnencryptedConfirm => 'Export Unencrypted';

  @override
  String get dataManagementPasswordEmpty => 'Password cannot be empty';

  @override
  String get dataManagementPasswordTooShort =>
      'Password must be at least 12 characters';

  @override
  String get dataManagementPasswordMismatch => 'Passwords do not match';

  @override
  String get dataManagementSelectFile => 'Select File';

  @override
  String get dataManagementImportFileDescription =>
      'Select a Prism export file (.json or .prism) to restore your data. Existing data will not be overwritten.';

  @override
  String get dataManagementEncryptedFile => 'Encrypted File';

  @override
  String get dataManagementEncryptedFileDescription =>
      'This export file is encrypted. Enter the password that was used when the export was created.';

  @override
  String get dataManagementDecrypt => 'Decrypt';

  @override
  String get dataManagementImportPreview => 'Import Preview';

  @override
  String dataManagementExportedDate(String date) {
    return 'Exported: $date';
  }

  @override
  String dataManagementPreviewMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get dataManagementPreviewFrontSessions => 'Front Sessions';

  @override
  String get dataManagementPreviewSleepSessions => 'Sleep Sessions';

  @override
  String get dataManagementPreviewConversations => 'Conversations';

  @override
  String get dataManagementPreviewMessages => 'Messages';

  @override
  String get dataManagementPreviewPolls => 'Polls';

  @override
  String get dataManagementPreviewPollOptions => 'Poll Options';

  @override
  String get dataManagementPreviewSettings => 'Settings';

  @override
  String get dataManagementPreviewHabits => 'Habits';

  @override
  String get dataManagementPreviewHabitCompletions => 'Habit Completions';

  @override
  String get dataManagementPreviewTotal => 'Total';

  @override
  String get dataManagementPreviewTotalCreated => 'Total Created';

  @override
  String get dataManagementImport => 'Import';

  @override
  String get dataManagementImporting => 'Importing your data…';

  @override
  String get dataManagementImportingMessage =>
      'This may take a moment. Do not close the app.';

  @override
  String get dataManagementImportComplete => 'Import Complete';

  @override
  String get dataManagementImportFailed => 'Import Failed';

  @override
  String get dataManagementImportFailedNote =>
      'No data was imported. The database was not modified.';

  @override
  String get dataManagementIncorrectPassword => 'Incorrect password';

  @override
  String dataManagementDecryptionFailed(String error) {
    return 'Decryption failed: $error';
  }

  @override
  String get dataManagementUnencryptedBackup =>
      'This backup isn\'t encrypted. Re-export from the app to get a secure .prism file.';

  @override
  String get dataManagementPasswordEmptyImport => 'Password cannot be empty';

  @override
  String get sharingTitle => 'Sharing';

  @override
  String get sharingRefreshInbox => 'Refresh inbox';

  @override
  String get sharingUseSharingCodeTooltip => 'Use sharing code';

  @override
  String get sharingShareYourCodeTooltip => 'Share your code';

  @override
  String get sharingPendingRequests => 'Pending Requests';

  @override
  String get sharingTrustedPeople => 'Trusted People';

  @override
  String get sharingEmptyTitle => 'No sharing relationships yet';

  @override
  String get sharingEmptySubtitle =>
      'Share your code so someone can send you a request, or use someone else\'s code to connect.';

  @override
  String get sharingShareMyCode => 'Share My Code';

  @override
  String get sharingUseACode => 'Use a Code';

  @override
  String get sharingRequestSent =>
      'Sharing request sent. They will see it the next time they check sharing.';

  @override
  String get sharingNoNewRequests => 'No new sharing requests';

  @override
  String get sharingUnableToRefresh => 'Unable to refresh sharing inbox';

  @override
  String get sharingSyncNotConfigured => 'Sync is not configured';

  @override
  String get sharingRequestAccepted => 'Sharing request accepted';

  @override
  String get sharingUnableToAccept => 'Unable to accept request';

  @override
  String get sharingRequestDismissed => 'Request dismissed';

  @override
  String get sharingRemoveTitle => 'Remove relationship';

  @override
  String sharingRemoveMessage(String name) {
    return 'Remove $name and revoke their access? This cannot be undone.';
  }

  @override
  String get sharingRemove => 'Remove';

  @override
  String get sharingNoScopesGranted => 'No scopes granted';

  @override
  String get sharingJustNow => 'Just now';

  @override
  String sharingMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String sharingHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String sharingDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get sharingIgnore => 'Ignore';

  @override
  String get sharingDismiss => 'Dismiss';

  @override
  String get sharingAccept => 'Accept';

  @override
  String get sharingUseSharingCode => 'Use Sharing Code';

  @override
  String get sharingSharingCodeLabel => 'Sharing code';

  @override
  String get sharingSharingCodeHint => 'Paste the code you received';

  @override
  String sharingConnectingWith(String name) {
    return 'Connecting with $name';
  }

  @override
  String get sharingReadyToSend => 'Ready to send a sharing request';

  @override
  String get sharingYourDisplayName => 'Your display name';

  @override
  String get sharingDisplayNameHint => 'How they will see you';

  @override
  String get sharingWhatToShare => 'What to share';

  @override
  String get sharingSending => 'Sending…';

  @override
  String get sharingSendRequest => 'Send Request';

  @override
  String get sharingInvalidCode => 'Invalid sharing code';

  @override
  String sharingFailedToSend(Object error) {
    return 'Failed to send sharing request: $error';
  }

  @override
  String get sharingShareYourCode => 'Share Your Code';

  @override
  String get sharingEnableSharing => 'Enable Sharing';

  @override
  String get sharingDescription =>
      'Sharing uses a stable code instead of an inline key exchange. Anyone with this code can send you a sharing request.';

  @override
  String get sharingDisplayNameOptionalLabel => 'Display name (optional)';

  @override
  String get sharingDisplayNameOptionalHint =>
      'Shown to the person opening your code';

  @override
  String get sharingSharingCodeTitle => 'Sharing Code';

  @override
  String get sharingCodeValidNote =>
      'This code stays valid until you turn sharing off.';

  @override
  String get sharingCopy => 'Copy';

  @override
  String sharingFailedToEnable(Object error) {
    return 'Failed to enable sharing: $error';
  }

  @override
  String get sharingCodeCopied => 'Sharing code copied (auto-clears in 15s)';

  @override
  String get sharingFriend => 'Friend';

  @override
  String get sharingFriendNotFound => 'Friend not found';

  @override
  String get sharingGrantedScopes => 'Granted Scopes';

  @override
  String get sharingSharingId => 'Sharing ID';

  @override
  String get sharingCopySharingId => 'Copy sharing ID';

  @override
  String get sharingSharingIdCopied => 'Sharing ID copied';

  @override
  String get sharingLastSynced => 'Last synced';

  @override
  String get sharingRevokeAccess => 'Revoke Access';

  @override
  String get sharingVerified => 'Verified';

  @override
  String get sharingNotVerified => 'Not verified';

  @override
  String sharingAddedDate(String date) {
    return 'Added $date';
  }

  @override
  String get sharingVerificationRecommended => 'Verification Recommended';

  @override
  String sharingVerificationDescription(String name) {
    return 'Compare fingerprints with $name out of band before marking this relationship as verified.';
  }

  @override
  String get sharingCompareFingerprint => 'Compare Fingerprint';

  @override
  String get sharingSecurityFingerprintTitle => 'Security Fingerprint';

  @override
  String sharingFingerprintCompareText(String name) {
    return 'Compare this fingerprint with $name. Only mark it verified if they see the same value.';
  }

  @override
  String get sharingFingerprintWarning =>
      'Do not verify if the fingerprints differ.';

  @override
  String get sharingMarkVerified => 'Mark Verified';

  @override
  String get sharingRevokeTitle => 'Revoke access';

  @override
  String sharingRevokeMessage(String name) {
    return 'Revoke all access for $name? Resource keys will be rotated.';
  }

  @override
  String get sharingRevoke => 'Revoke';

  @override
  String get sharingUnableToComputeFingerprint =>
      'Unable to compute fingerprint';

  @override
  String sharingFingerprintCopied(String label) {
    return '$label copied';
  }

  @override
  String sharingCopyLabel(String label) {
    return 'Copy $label';
  }

  @override
  String get sharingFingerprint => 'Fingerprint';

  @override
  String get sharingIdentity => 'Identity';

  @override
  String get remindersTitle => 'Reminders';

  @override
  String remindersLoadError(String error) {
    return 'Error: $error';
  }

  @override
  String get remindersEmptyTitle => 'No reminders';

  @override
  String get remindersEmptySubtitle =>
      'Create reminders for fronting changes or scheduled times';

  @override
  String get remindersEmptyAction => 'Add Reminder';

  @override
  String remindersDeletedSnackbar(String name) {
    return 'Deleted \"$name\"';
  }

  @override
  String get remindersUndoAction => 'Undo';

  @override
  String get remindersSubtitleOnFrontChange => 'On front change';

  @override
  String remindersSubtitleOnFrontChangeDelay(int hours) {
    return 'On front change (${hours}h delay)';
  }

  @override
  String get remindersSubtitleDaily => 'Daily';

  @override
  String remindersSubtitleEveryNDays(int days) {
    return 'Every $days days';
  }

  @override
  String get remindersFrequencyWeekly => 'Weekly';

  @override
  String get remindersFrequencyInterval => 'Every few days';

  @override
  String get remindersScheduleLabel => 'Schedule';

  @override
  String get remindersWeeklyEmptyHelper => 'Select at least one day';

  @override
  String get remindersSubtitleEveryDay => 'Every day';

  @override
  String get remindersSubtitleWeekdays => 'Weekdays';

  @override
  String get remindersSubtitleWeekends => 'Weekends';

  @override
  String remindersSubtitleDaysPerWeek(int count) {
    return '$count days/week';
  }

  @override
  String get weekdayAbbreviationSun => 'Sun';

  @override
  String get weekdayAbbreviationMon => 'Mon';

  @override
  String get weekdayAbbreviationTue => 'Tue';

  @override
  String get weekdayAbbreviationWed => 'Wed';

  @override
  String get weekdayAbbreviationThu => 'Thu';

  @override
  String get weekdayAbbreviationFri => 'Fri';

  @override
  String get weekdayAbbreviationSat => 'Sat';

  @override
  String get remindersScheduled => 'Scheduled';

  @override
  String get remindersEditTitle => 'Edit Reminder';

  @override
  String get remindersNewTitle => 'New Reminder';

  @override
  String get remindersNameLabel => 'Reminder name';

  @override
  String get remindersMessageLabel => 'Notification message';

  @override
  String get remindersTriggerLabel => 'Trigger';

  @override
  String get remindersTriggerFrontChange => 'Front Change';

  @override
  String get remindersRepeatEveryLabel => 'Repeat every';

  @override
  String remindersIntervalDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get remindersTimeLabel => 'Time';

  @override
  String get remindersDelayLabel => 'Delay after front change';

  @override
  String get remindersImmediately => 'Immediately';

  @override
  String remindersDelayHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String get remindersTargetLabel => 'Target';

  @override
  String get remindersTargetAny => 'Any front change';

  @override
  String get remindersTargetDisclosure =>
      'Fires when Prism is running and sees the switch. External switches logged while Prism is closed may not trigger this reminder.';

  @override
  String remindersSubtitleTargetPrefix(String name) {
    return 'When $name fronts';
  }

  @override
  String get settingsAboutAppName => 'Prism';

  @override
  String get settingsAboutTagline => 'Plural system management';

  @override
  String settingsAboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String settingsAboutDescription(String termPluralLower) {
    return 'A privacy-focused app for managing plural systems. Track fronting, communicate between $termPluralLower, and keep your system organized.';
  }

  @override
  String get settingsAboutGitHub => 'GitHub';

  @override
  String get settingsAboutPrivacy => 'Privacy';

  @override
  String get settingsAboutFeedback => 'Feedback';

  @override
  String get settingsAboutGitHubComingSoon => 'GitHub link coming soon';

  @override
  String get settingsAboutSecurity => 'Security';

  @override
  String get settingsAboutFeedbackComingSoon => 'Feedback form coming soon';

  @override
  String get settingsCustomFieldsTitle => 'Custom Fields';

  @override
  String get settingsCustomFieldsAddTooltip => 'Add field';

  @override
  String settingsCustomFieldsError(String error) {
    return 'Error: $error';
  }

  @override
  String get settingsCustomFieldsEmptyTitle => 'No custom fields';

  @override
  String settingsCustomFieldsEmptySubtitle(String termSingularLower) {
    return 'Add fields to track custom attributes for each $termSingularLower';
  }

  @override
  String get settingsCustomFieldsAddAction => 'Add Field';

  @override
  String get settingsCustomFieldsDeleteTitle => 'Delete Field';

  @override
  String settingsCustomFieldsDeleteConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"? This will delete the field and all its values.';
  }

  @override
  String settingsCustomFieldsDeletedToast(String name) {
    return '$name deleted';
  }

  @override
  String get settingsAccentColorPrismPurple => 'Prism Purple';

  @override
  String get settingsAccentColorBlue => 'Blue';

  @override
  String get settingsAccentColorGreen => 'Green';

  @override
  String get settingsAccentColorRed => 'Red';

  @override
  String get settingsAccentColorOrange => 'Orange';

  @override
  String get settingsAccentColorPink => 'Pink';

  @override
  String get settingsAccentColorTeal => 'Teal';

  @override
  String get settingsAccentColorAmber => 'Amber';

  @override
  String get settingsAccentColorIndigo => 'Indigo';

  @override
  String get settingsAccentColorGray => 'Gray';

  @override
  String get settingsAccentColorSystemColor => 'System color';

  @override
  String get settingsAccentColorCustom => 'Custom';

  @override
  String get settingsAccentColorPickerTitle => 'Pick a color';

  @override
  String get settingsAccentColorSelect => 'Select';

  @override
  String get settingsAccentColorSystemPaletteNote =>
      'Using your system color palette';

  @override
  String get accentLegibilityTooDark =>
      'This color is very dark — it may be hard to see on dark backgrounds.';

  @override
  String get accentLegibilityTooLight =>
      'This color is very light — it may be hard to see on light backgrounds.';

  @override
  String get accentLegibilityTooDesaturated =>
      'This color is very gray — it may blend into the background.';

  @override
  String get settingsChangePinTitle => 'Change PIN';

  @override
  String get settingsChangePinVerifyBody =>
      'Enter your current PIN to continue.';

  @override
  String get settingsChangePinCurrentLabel => 'Current PIN';

  @override
  String get settingsChangePinContinue => 'Continue';

  @override
  String get settingsChangePinCurrentRequired => 'Enter your current PIN.';

  @override
  String get settingsChangePinNoSecretKey =>
      'Secret Key not found on this device. Re-pair to restore it.';

  @override
  String get settingsChangePinEngineUnavailable => 'Sync engine not available.';

  @override
  String get settingsChangePinIncorrect => 'Incorrect PIN. Please try again.';

  @override
  String settingsChangePinVerifyFailed(String error) {
    return 'Verification failed: $error';
  }

  @override
  String settingsChangePinGenericError(String error) {
    return 'An error occurred: $error';
  }

  @override
  String get settingsChangePinSessionExpired =>
      'Session expired — please verify again.';

  @override
  String get settingsChangePinWarnBody =>
      'Your other devices will need to enter the new PIN when they next open Prism.';

  @override
  String get settingsChangePinAction => 'Change PIN';

  @override
  String get settingsChangePinNewBody => 'Choose a new sync PIN.';

  @override
  String get settingsChangePinNewLabel => 'New PIN';

  @override
  String get settingsChangePinConfirmLabel => 'Confirm new PIN';

  @override
  String get settingsChangePinNewRequired => 'Enter a new PIN.';

  @override
  String get settingsChangePinInvalidLength => 'PIN must be exactly 6 digits.';

  @override
  String get settingsChangePinSamePin =>
      'Your sync PIN is already set to that.';

  @override
  String get settingsChangePinMismatch => 'PINs don\'t match.';

  @override
  String get settingsChangePinGenerationConflict =>
      'Another device recently changed settings — please try again.';

  @override
  String settingsChangePinFailed(String error) {
    return 'Failed to change PIN: $error';
  }

  @override
  String get settingsChangePinSuccessTitle => 'PIN changed';

  @override
  String get settingsChangePinSuccessBody =>
      'Your sync PIN has been updated on this device.';

  @override
  String get changePinEnterMnemonicTitle => 'Enter your recovery phrase';

  @override
  String get changePinEnterMnemonicSubtitle =>
      'Your 12-word phrase is not stored on this device. Type it from your saved backup.';

  @override
  String get changePinMnemonicHint => '12 words separated by spaces';

  @override
  String get changePinMnemonicInvalid =>
      'That doesn\'t look like a valid recovery phrase.';

  @override
  String get changePinMnemonicRequired => 'Enter your 12-word recovery phrase.';

  @override
  String get changePinVerifyButton => 'Continue';

  @override
  String get changePinVerificationFailed =>
      'PIN or recovery phrase is incorrect.';

  @override
  String get settingsCreateEditFieldEditTitle => 'Edit Field';

  @override
  String get settingsCreateEditFieldNewTitle => 'New Field';

  @override
  String get settingsCreateEditFieldNameLabel => 'Field Name';

  @override
  String get settingsCreateEditFieldNameHint => 'e.g. Birthday, Favorite Color';

  @override
  String get settingsCreateEditFieldTypeHeading => 'Type';

  @override
  String get settingsCreateEditFieldTypeImmutable =>
      'Type cannot be changed after creation.';

  @override
  String get settingsCreateEditFieldDatePrecisionHeading => 'Date Precision';

  @override
  String settingsCreateEditFieldSaveError(String error) {
    return 'Error saving field: $error';
  }

  @override
  String get settingsDataBrowserTitle => 'Data Browser';

  @override
  String get settingsDataBrowserReloadTooltip => 'Reload data';

  @override
  String settingsDataBrowserTabMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get settingsDataBrowserTabSessions => 'Sessions';

  @override
  String get settingsDataBrowserTabChats => 'Chats';

  @override
  String get settingsDataBrowserTabMessages => 'Msgs';

  @override
  String get settingsDataBrowserTabPolls => 'Polls';

  @override
  String settingsDataBrowserError(String error) {
    return 'Error: $error';
  }

  @override
  String settingsDataBrowserNoMembers(String termPluralLower) {
    return 'No $termPluralLower';
  }

  @override
  String get settingsDataBrowserNoSessions => 'No sessions';

  @override
  String get settingsDataBrowserNoConversations => 'No conversations';

  @override
  String get settingsDataBrowserNoMessages => 'No messages';

  @override
  String get settingsDataBrowserNoPolls => 'No polls';

  @override
  String get settingsDataBrowserSessionActive => 'Active';

  @override
  String get settingsDataBrowserSessionEnded => 'Ended';

  @override
  String get settingsDataBrowserUntitled => 'Untitled';

  @override
  String settingsDataBrowserParticipantCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count participants',
      one: '1 participant',
    );
    return '$_temp0';
  }

  @override
  String get settingsDataBrowserSystemMessage => 'System';

  @override
  String get settingsDataBrowserPollClosed => 'Closed';

  @override
  String get settingsDataBrowserPollActive => 'Active';

  @override
  String get settingsDataBrowserNoMessagesInConversation =>
      'No messages in this conversation.';

  @override
  String get settingsDataBrowserLoadError => 'Error loading — tap to retry';

  @override
  String settingsDataBrowserMessageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }

  @override
  String get settingsDataBrowserTapToLoad => 'Tap to load messages';

  @override
  String get settingsDataBrowserSessionEndTimeActive => 'null (active)';

  @override
  String get settingsSyncDebugTitle => 'Prism Sync Event Log';

  @override
  String settingsSyncDebugEventCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count events',
      one: '1 event',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncDebugCopyLogTooltip => 'Copy log';

  @override
  String get settingsSyncDebugClearLogTooltip => 'Clear log';

  @override
  String get settingsSyncDebugCopiedToast => 'Sync event log copied';

  @override
  String get settingsSyncDebugEmptyTitle => 'No sync events recorded';

  @override
  String get settingsSyncDebugEmptyBody =>
      'Sync events will appear here as they happen.';

  @override
  String get settingsTerminologyPickerLabel => 'Terminology';

  @override
  String get settingsTerminologyOptionMembers => 'Members';

  @override
  String get settingsTerminologyOptionMembersSingular => 'member';

  @override
  String get settingsTerminologyOptionHeadmates => 'Headmates';

  @override
  String get settingsTerminologyOptionHeadmatesSingular => 'headmate';

  @override
  String get settingsTerminologyOptionAlters => 'Alters';

  @override
  String get settingsTerminologyOptionAltersSingular => 'alter';

  @override
  String get settingsTerminologyOptionParts => 'Parts';

  @override
  String get settingsTerminologyOptionPartsSingular => 'part';

  @override
  String get settingsTerminologyOptionFacets => 'Facets';

  @override
  String get settingsTerminologyOptionFacetsSingular => 'facet';

  @override
  String get settingsTerminologyOptionCustom => 'Custom';

  @override
  String get settingsTerminologyOptionCustomSingular => 'custom term';

  @override
  String get settingsTerminologyCustomSingularLabel => 'Custom term (singular)';

  @override
  String get settingsTerminologyCustomSingularHint => 'e.g. fragment';

  @override
  String get settingsTerminologyCustomPluralLabel => 'Custom term (plural)';

  @override
  String get settingsTerminologyCustomPluralHint => 'e.g. fragments';

  @override
  String get settingsTerminologyPreviewLabel => 'Preview';

  @override
  String get terminologyEnglishOptionsLabel => 'In English';

  @override
  String get navHome => 'Home';

  @override
  String get navChat => 'Chat';

  @override
  String get navHabits => 'Habits';

  @override
  String get navPolls => 'Polls';

  @override
  String get navSettings => 'Settings';

  @override
  String get navMembers => 'Members';

  @override
  String get navReminders => 'Reminders';

  @override
  String get navNotes => 'Notes';

  @override
  String get navStatistics => 'Statistics';

  @override
  String get navTimeline => 'Timeline';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Prism';

  @override
  String get onboardingWelcomeSubtitle => 'Your system, your way.';

  @override
  String get onboardingWelcomeSyncLink =>
      'I already use Prism on another device';

  @override
  String get onboardingBiometricSetupTitle => 'Enable biometrics';

  @override
  String get onboardingBiometricSetupSubtitle =>
      'Use Face ID or Touch ID to unlock.';

  @override
  String get onboardingSyncDeviceTitle => 'Sync From Device';

  @override
  String get onboardingSyncDeviceSubtitle => 'Pair with an existing device';

  @override
  String get onboardingImportedDataReadyTitle => 'Data Ready';

  @override
  String get onboardingImportedDataReadySubtitle =>
      'Your imported system is ready to use';

  @override
  String get onboardingImportDataTitle => 'Already have data?';

  @override
  String get onboardingImportDataSubtitle => 'Bring your system with you.';

  @override
  String get onboardingSystemNameTitle => 'Name your system';

  @override
  String get onboardingSystemNameSubtitle => 'Whatever feels right.';

  @override
  String get onboardingAddMembersTitle => 'Who\'s here?';

  @override
  String get onboardingAddMembersSubtitle => 'Add the people in your system.';

  @override
  String get onboardingFeaturesTitle => 'Pick your tools';

  @override
  String get onboardingFeaturesSubtitle =>
      'Turn on what you need. Change anytime.';

  @override
  String get onboardingChatSetupTitle => 'Set up chat';

  @override
  String get onboardingChatSetupSubtitle => 'Channels for your system to talk.';

  @override
  String get onboardingPreferencesTitle => 'Make it yours';

  @override
  String get onboardingPreferencesSubtitle =>
      'Colors, language, the small things.';

  @override
  String get onboardingPermissionsTitle => 'One more thing';

  @override
  String get onboardingPermissionsSubtitle =>
      'Optional permissions for the best experience.';

  @override
  String get onboardingPermissionsNotificationTitle => 'Notifications';

  @override
  String onboardingPermissionsNotificationRationale(String termPluralLower) {
    return 'We\'ll let you know when $termPluralLower log a switch or a habit reminder is due';
  }

  @override
  String get onboardingPermissionsMicrophoneTitle => 'Microphone';

  @override
  String onboardingPermissionsMicrophoneRationale(String termPluralLower) {
    return 'So you can record voice messages for your $termPluralLower';
  }

  @override
  String get onboardingPermissionsAllowed => 'Allowed';

  @override
  String get onboardingPermissionsAllow => 'Allow';

  @override
  String get onboardingPermissionsOpenSettings => 'Change in Settings';

  @override
  String get onboardingWhosFrontingTitle => 'Who\'s fronting?';

  @override
  String get onboardingWhosFrontingSubtitle => 'Tap whoever\'s here right now.';

  @override
  String get onboardingCompleteTitle => 'Ready when you are';

  @override
  String get onboardingCompleteSubtitle =>
      'Your system is set up. Here\'s what to explore.';

  @override
  String terminologyAddButton(String term) {
    return 'Add $term';
  }

  @override
  String terminologySearchHint(String term) {
    return 'Search $term...';
  }

  @override
  String terminologyEmptyTitle(String term) {
    return 'No $term yet';
  }

  @override
  String terminologyEmptyActiveTitle(String term) {
    return 'No active $term yet';
  }

  @override
  String terminologyNewItem(String term) {
    return 'New $term';
  }

  @override
  String terminologyEditItem(String term) {
    return 'Edit $term';
  }

  @override
  String terminologyDeleteItem(String term) {
    return 'Delete $term';
  }

  @override
  String terminologyManage(String term) {
    return 'Manage $term';
  }

  @override
  String terminologyDeleteSelected(String term) {
    return 'Delete Selected $term';
  }

  @override
  String terminologySelectPrompt(String term) {
    return 'Select a $term';
  }

  @override
  String terminologyNoFound(String term) {
    return 'No $term found';
  }

  @override
  String terminologyLoadError(String term, String error) {
    return 'Error loading $term: $error';
  }

  @override
  String terminologyAddFirstSubtitle(String term) {
    return 'Add your first system $term to get started';
  }

  @override
  String pollsVotingAsSelectPrompt(String term) {
    return 'Select a $term to vote as';
  }

  @override
  String get onboardingPinSetupTitle => 'Set your PIN';

  @override
  String get onboardingPinSetupSubtitle =>
      'You\'ll use this 6-digit PIN to lock Prism and recover access if needed.';

  @override
  String get onboardingRecoveryPhraseTitle => 'Save your recovery phrase';

  @override
  String get onboardingRecoveryPhraseSubtitle =>
      'Write these 12 words somewhere safe. You\'ll need them to set up sync, add new devices, or change your PIN.';

  @override
  String get onboardingConfirmPhraseTitle => 'Verify your phrase';

  @override
  String get onboardingConfirmPhraseSubtitle =>
      'Select the correct word for each position.';

  @override
  String get syncPinSheetTitle => 'Enter your PIN';

  @override
  String get syncPinSheetSubtitle => 'Your PIN is required to unlock Prism.';

  @override
  String get syncPinSheetMnemonicSubtitle =>
      'Enter your 12-word recovery phrase to continue. This isn\'t stored on your device.';

  @override
  String get syncPinSheetMnemonicInvalid =>
      'This doesn\'t look like a valid recovery phrase.';

  @override
  String get syncPinSheetUnlockFailed =>
      'Couldn\'t unlock with this phrase and PIN.';

  @override
  String get syncPinSheetLostPhrase => 'Lost your phrase?';

  @override
  String get syncPinSheetLostPhraseBody =>
      'Your recovery phrase is the only way to unlock sync on this device. If you\'ve lost it, reset the app and restore from an exported backup.';

  @override
  String get syncPinSheetMnemonicContinue => 'Continue';

  @override
  String get syncPinSheetBack => 'Back';

  @override
  String mnemonicFieldWordCounter(String filled) {
    return '$filled of 12 words';
  }

  @override
  String get mnemonicFieldPaste => 'Paste phrase';

  @override
  String get mnemonicFieldShowWords => 'Show words';

  @override
  String get mnemonicFieldHideWords => 'Hide words';

  @override
  String mnemonicFieldWordSlotLabel(String n) {
    return 'Word $n';
  }

  @override
  String mnemonicFieldWordChipValid(String n, String word) {
    return 'Word $n: $word, valid';
  }

  @override
  String mnemonicFieldWordChipInvalid(String n, String word) {
    return 'Word $n: $word, not recognized';
  }

  @override
  String get mnemonicFieldScanQrTooltip => 'Scan QR code';

  @override
  String get mnemonicFieldShowQrTooltip => 'Show QR code';

  @override
  String get mnemonicFieldQrTitle => 'Recovery Phrase QR';

  @override
  String get mnemonicFieldQrDescription =>
      'Scan this QR code to fill the 12-word recovery phrase on another device.';

  @override
  String get mnemonicFieldScanQrTitle => 'Scan Recovery QR';

  @override
  String get mnemonicFieldScanQrDescription =>
      'Scan a QR code that contains your 12-word recovery phrase.';

  @override
  String get mnemonicFieldInvalidQr =>
      'Invalid QR code. Scan a 12-word recovery phrase.';

  @override
  String get mnemonicFieldCameraPermissionTitle => 'Camera permission needed';

  @override
  String get mnemonicFieldCameraPermissionDeniedBody =>
      'Prism needs the camera to scan your recovery QR code. Try again and allow camera access when prompted.';

  @override
  String get mnemonicFieldCameraPermissionPermanentlyDeniedBody =>
      'Camera access is blocked. Open Settings to grant Prism camera permission, then try again.';

  @override
  String get mnemonicFieldCameraPermissionOpenSettings => 'Open Settings';

  @override
  String get pluralkitAutoSyncSection => 'Auto-sync';

  @override
  String get pluralkitAutoSyncTitle => 'Pull new switches automatically';

  @override
  String get pluralkitAutoSyncDescription =>
      'While Prism is open, check PluralKit for new switches on an interval. Pauses in the background.';

  @override
  String get pluralkitAutoSyncIntervalLabel => 'Check every';

  @override
  String get pluralkitAutoSyncLoadFailed =>
      'Could not load auto-sync settings.';

  @override
  String get pluralkitRerunMemberMapping => 'Re-run member mapping';

  @override
  String get pluralkitImportFromFile => 'Recover history from pk;export';

  @override
  String pluralkitMappingBannerTitle(String termPluralLower) {
    return 'One more step: link your $termPluralLower';
  }

  @override
  String pluralkitMappingBannerBody(String termSingularLower) {
    return 'You\'re connected. Before sync turns on, match each PluralKit member to a $termSingularLower in Prism — or import them as new. This prevents duplicates and keeps switch history attached to the right person.';
  }

  @override
  String pluralkitMappingBannerButton(String termPluralLower) {
    return 'Link $termPluralLower';
  }

  @override
  String get sleepWakeUpMorning => 'Good morning!';

  @override
  String get sleepWakeUpAfternoon => 'Good afternoon!';

  @override
  String get sleepWakeUpEvening => 'Good evening!';

  @override
  String get sleepWakeUpNight => 'Rise and shine!';

  @override
  String sleepWakeUpSleptFor(String duration) {
    return 'You slept for $duration';
  }

  @override
  String get sleepWakeUpQualityQuestion => 'How was your sleep?';

  @override
  String get sleepWakeUpWhosFronting => 'Who\'s fronting now?';

  @override
  String get sleepWakeUpDone => 'Done';

  @override
  String get sleepWakeUpSkip => 'Skip';

  @override
  String get sleepWakeUpOthers => 'Others...';

  @override
  String get sleepSuggestionBedtime => 'It\'s your usual bedtime';

  @override
  String get sleepSuggestionBedtimeAction => 'Start Sleep';

  @override
  String sleepWakeSuggestionNudge(String duration) {
    return 'You\'ve been sleeping for $duration';
  }

  @override
  String get featureSleepSuggestions => 'Suggestions';

  @override
  String get featureSleepBedtimeReminder => 'Bedtime Reminder';

  @override
  String get featureSleepBedtimeReminderSubtitle =>
      'Show a reminder at your usual bedtime';

  @override
  String get featureSleepBedtimeTime => 'Bedtime';

  @override
  String get featureSleepWakeReminder => 'Wake Reminder';

  @override
  String get featureSleepWakeReminderSubtitle =>
      'Nudge to wake after a set duration';

  @override
  String get featureSleepWakeAfter => 'Wake After';

  @override
  String featureSleepWakeAfterHours(String hours) {
    return '$hours hours';
  }

  @override
  String get onboardingSyncMembersLabel => 'System members';

  @override
  String get onboardingSyncPhaseConnectTitle => 'Connecting…';

  @override
  String get onboardingSyncPhaseConnectSubtitle =>
      'Saying hello to your other device';

  @override
  String get onboardingSyncPhaseDownloadTitle => 'Downloading your system';

  @override
  String get onboardingSyncPhaseDownloadSubtitle =>
      'Pulling the encrypted snapshot';

  @override
  String get onboardingSyncPhaseRestoreTitle => 'Restoring your data';

  @override
  String get onboardingSyncPhaseRestoreSubtitle =>
      'Unpacking headmates, messages, and notes';

  @override
  String get onboardingSyncPhaseFinishTitle => 'Wrapping up';

  @override
  String get onboardingSyncPhaseFinishSubtitle => 'Locking things in for good';

  @override
  String get onboardingSyncReassurance =>
      'Still going — larger systems can take a minute on slow networks.';

  @override
  String get onboardingSyncReconnecting => 'Reconnecting to the relay…';

  @override
  String get onboardingSyncNoDataToRestore =>
      'No prior data to restore — starting fresh.';

  @override
  String get onboardingSyncStillPullingBackground =>
      'Still pulling updates in the background. You can continue.';

  @override
  String onboardingSyncPhaseAnnouncement(String phase) {
    return 'Now $phase';
  }

  @override
  String onboardingSyncRestoredSummary(int members, int messages) {
    return 'Restored $members members and $messages messages.';
  }

  @override
  String onboardingPhaseSegmentsSemantics(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get pkProfileDisclosureTitle =>
      'Import your system profile from PluralKit?';

  @override
  String get pkProfileDisclosureSubtitle => 'We\'ll only copy what you check.';

  @override
  String get pkProfileDisclosureImport => 'Import selected';

  @override
  String get pkProfileDisclosureSkip => 'Skip';

  @override
  String get pkProfileFieldName => 'System name';

  @override
  String get pkProfileFieldDescription => 'Description';

  @override
  String get pkProfileFieldTag => 'System tag';

  @override
  String get pkProfileFieldAvatar => 'System avatar';

  @override
  String get pkProfileFieldOverwriteHint =>
      'Prism already has a value — tick to overwrite.';

  @override
  String get migrationCfStepTitle => 'Custom fronts';

  @override
  String get migrationCfStepExplainer =>
      'Simply Plural has custom fronts (Co-fronting, Asleep, and others). Prism doesn\'t track these as first-class statuses. Pick how to handle each one.';

  @override
  String get migrationCfResetDefaults => 'Reset to smart defaults';

  @override
  String get migrationCfBack => 'Back';

  @override
  String get migrationCfContinue => 'Continue';

  @override
  String migrationCfOptionMember(String termSingularLower) {
    return 'Import as $termSingularLower';
  }

  @override
  String get migrationCfOptionNote => 'Merge into notes';

  @override
  String get migrationCfOptionSleep => 'Convert to sleep';

  @override
  String get migrationCfOptionSkip => 'Skip';

  @override
  String migrationCfOptionMemberDesc(String termSingularLower) {
    return 'Creates a $termSingularLower with this name. Front history entries for it are kept as $termSingularLower sessions.';
  }

  @override
  String get migrationCfOptionNoteDesc =>
      'No member is created. The custom front\'s name is appended to the notes of sessions it touches.';

  @override
  String get migrationCfOptionSleepDesc =>
      'Front history entries where this is the primary fronter become sleep sessions instead.';

  @override
  String get migrationCfOptionSkipDesc =>
      'No member, no note. Sessions with no other fronter are dropped.';

  @override
  String get migrationCfReasonSleepName => 'Name matches sleep keywords';

  @override
  String get migrationCfReasonZeroUsage =>
      'Never used in front history or timers';

  @override
  String get migrationCfReasonCoFronterOnly => 'Only used as co-fronter';

  @override
  String get migrationCfReasonPrimaryHeavy => 'Used mostly as primary fronter';

  @override
  String get migrationCfReasonFallback =>
      'Mixed usage — safest to preserve as a note';

  @override
  String migrationCfUsageSummary(int primary, int coFront, int timers) {
    String _temp0 = intl.Intl.pluralLogic(
      primary,
      locale: localeName,
      other: '$primary primary',
      one: '1 primary',
      zero: 'Never primary',
    );
    String _temp1 = intl.Intl.pluralLogic(
      coFront,
      locale: localeName,
      other: '$coFront co-front',
      one: '1 co-front',
      zero: '0 co-front',
    );
    String _temp2 = intl.Intl.pluralLogic(
      timers,
      locale: localeName,
      other: '$timers timers',
      one: '1 timer',
      zero: '0 timers',
    );
    return '$_temp0 · $_temp1 · $_temp2';
  }

  @override
  String migrationCfPreviewBreakdown(
    int asMember,
    int asSleep,
    int asNote,
    int asSkip,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      asMember,
      locale: localeName,
      other: '$asMember as members',
      one: '1 as member',
    );
    String _temp1 = intl.Intl.pluralLogic(
      asSleep,
      locale: localeName,
      other: '$asSleep as sleep',
      one: '1 as sleep',
    );
    String _temp2 = intl.Intl.pluralLogic(
      asNote,
      locale: localeName,
      other: '$asNote notes',
      one: '1 note',
    );
    String _temp3 = intl.Intl.pluralLogic(
      asSkip,
      locale: localeName,
      other: '$asSkip skipped',
      one: '1 skipped',
    );
    return '$_temp0 · $_temp1 · $_temp2 · $_temp3';
  }

  @override
  String migrationWarnCfDroppedEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count front-history entries dropped (primary was a skipped custom front with no co-fronters).',
      one:
          '1 front-history entry dropped (primary was a skipped custom front with no co-fronters).',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepCoFrontersDiscarded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sleep-mode sessions had co-fronters that were discarded.',
      one: '1 sleep-mode session had co-fronters that were discarded.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepCoFronterAsNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count front sessions had a sleep custom front as co-fronter, preserved as note only.',
      one:
          '1 front session had a sleep custom front as co-fronter, preserved as note only.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepOverlap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sleep sessions overlap with other sessions in your timeline — resolve in the Fronting tab.',
      one:
          '1 sleep session overlaps with other sessions in your timeline — resolve in the Fronting tab.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfCommentsDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count comments dropped (attached to skipped custom-front sessions).',
      one: '1 comment dropped (attached to skipped custom-front sessions).',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfStaleMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count previously-imported custom fronts are no longer imported as members; the existing member records remain — delete manually if you want them gone.',
      one:
          '1 previously-imported custom front is no longer imported as a member; the existing member record remains — delete manually if you want it gone.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfDeletedRefs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count front-history references pointed to custom fronts deleted in SP — handled as notes.',
      one:
          '1 front-history reference pointed to a custom front deleted in SP — handled as a note.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepClamped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open-ended SP sleep entries clamped to 24h duration.',
      one: '1 open-ended SP sleep entry clamped to 24h duration.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfTimersAdjusted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count timers targeted custom fronts that aren\'t imported as members — target dropped or timer removed.',
      one:
          '1 timer targeted a custom front that isn\'t imported as a member — target dropped or timer removed.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepDedup(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count duplicate-start SP sleep entries collapsed.',
      one: '1 duplicate-start SP sleep entry collapsed.',
    );
    return '$_temp0';
  }

  @override
  String get frontingUpgradeTitle => 'Fronting upgrade';

  @override
  String get frontingUpgradeIntroHeadline =>
      'We\'re upgrading how fronting is stored';

  @override
  String frontingUpgradeIntroBody(String termSingularLower) {
    return 'Co-fronting now uses one record per $termSingularLower instead of one shared record. This makes overlaps, edits, and analytics work correctly. We\'ll save a backup of your current data first, then run the upgrade.';
  }

  @override
  String get frontingUpgradeContinue => 'Continue';

  @override
  String get frontingUpgradeNotNow => 'Not now';

  @override
  String get frontingUpgradeRoleHeadline => 'Is this your main device?';

  @override
  String get frontingUpgradeRoleBody =>
      'Your main device keeps all your fronting history. Other devices will need to pair again afterward and pull the migrated history from the main device.';

  @override
  String get frontingUpgradeRolePrimary => 'Yes, this is my main device';

  @override
  String get frontingUpgradeRoleSecondary => 'No, this is a secondary';

  @override
  String get frontingUpgradeModeHeadline => 'How should we upgrade?';

  @override
  String get frontingUpgradeModeKeepTitle => 'Keep my data';

  @override
  String get frontingUpgradeModeKeepBody =>
      'Your existing fronts stay. PluralKit-imported fronts get re-imported with the new shape on next PluralKit sync.';

  @override
  String get frontingUpgradeModeFreshTitle => 'Start fresh';

  @override
  String get frontingUpgradeModeFreshBody =>
      'All fronts are wiped. Useful if your fronting history is messy and you want a clean slate. A backup file is still created.';

  @override
  String get frontingUpgradeRecommended => 'Recommended';

  @override
  String get frontingUpgradePasswordHeadline => 'Protect your backup';

  @override
  String get frontingUpgradePasswordBody =>
      'We\'re about to back up your current fronting data and then upgrade it.';

  @override
  String get frontingUpgradePasswordNote =>
      'This password protects your backup file. Save it somewhere safe — without it, the file can\'t be recovered.';

  @override
  String get frontingUpgradePasswordSubmit => 'Back up and upgrade';

  @override
  String get frontingUpgradeRunning => 'Migrating your fronting history…';

  @override
  String get frontingUpgradeRunningSubtitle =>
      'This may take a moment. Don\'t close the app.';

  @override
  String get frontingUpgradeExporting => 'Building your backup…';

  @override
  String get frontingUpgradeExportingSubtitle =>
      'Encrypting your fronting data so you can keep a copy.';

  @override
  String get frontingUpgradeBackupReadyHeadline => 'Backup ready';

  @override
  String get frontingUpgradeBackupReadyBody =>
      'Save this backup somewhere you\'ll be able to find it later — outside the app. Without it, you can\'t recover your old data if anything goes wrong.';

  @override
  String get frontingUpgradeBackupSaveAs => 'Save backup…';

  @override
  String get frontingUpgradeBackupShare => 'Share…';

  @override
  String get frontingUpgradeBackupAcknowledge =>
      'I have saved this backup somewhere I can find later';

  @override
  String get frontingUpgradeBackupContinue => 'Continue';

  @override
  String get frontingUpgradeSuccessHeadline => 'Migration complete!';

  @override
  String frontingUpgradeCountSpMigrated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Migrated $count Simply Plural sessions.',
      one: 'Migrated 1 Simply Plural session.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountNativeMigrated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Migrated $count fronting sessions.',
      one: 'Migrated 1 fronting session.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountNativeExpanded(
    int count,
    String termSingularLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Expanded $count co-fronting periods into per-$termSingularLower records.',
      one: 'Expanded 1 co-fronting period into per-$termSingularLower records.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountPkDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Old-format PluralKit history was cleared ($count sessions). Re-import it from a PluralKit token or a pk;export file.',
      one:
          'Old-format PluralKit history was cleared (1 session). Re-import it from a PluralKit token or a pk;export file.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountCommentsMigrated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Migrated $count comments.',
      one: 'Migrated 1 comment.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountOrphansAssigned(
    int count,
    String termSingularLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Assigned $count unattributed sessions to the Unknown $termSingularLower.',
      one: 'Assigned 1 unattributed session to the Unknown $termSingularLower.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountSentinelCreated(String termSingularLower) {
    return 'Created an Unknown $termSingularLower to hold sessions with no clear fronter.';
  }

  @override
  String frontingUpgradeCountCorruptCoFronters(
    int count,
    String termSingularLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sessions had unreadable co-fronter data and were migrated as single-$termSingularLower.',
      one:
          '1 session had unreadable co-fronter data and was migrated as single-$termSingularLower.',
    );
    return '$_temp0';
  }

  @override
  String get frontingUpgradeIntroPendingSyncWarning =>
      'If you have unsynced changes from offline use, make sure your device is online and synced before you continue. Pending uploads will need to be redone after the upgrade.';

  @override
  String frontingUpgradeAnalyticsNote(String term) {
    return 'Analytics are now framed as $term-minutes — when two of you co-front for an hour, that\'s two $term-hours. Same math as before, clearer label.';
  }

  @override
  String get frontingUpgradeRepairPrimary =>
      'Your other devices need to pair again to receive the migrated history. Open Settings → Sync on your other devices and follow the pairing flow.';

  @override
  String get frontingUpgradeRepairSecondary =>
      'Pair this device with your main device again to receive the migrated history.';

  @override
  String get frontingUpgradeRepairSolo =>
      'All set. Your fronting data is on the new format.';

  @override
  String get frontingUpgradeOpenPluralKitImport => 'Open PluralKit import';

  @override
  String get frontingUpgradeFailureHeadline => 'Migration failed';

  @override
  String get frontingUpgradeFailureBackupNote =>
      'Your backup file was saved. You can find it in your share sheet history if you need to recover.';

  @override
  String get frontingUpgradeBannerTitle => 'Fronting upgrade pending';

  @override
  String get frontingUpgradeBannerMessage => 'Tap to continue the upgrade.';

  @override
  String pkFileImportMembersLabel(String termPlural) {
    return '$termPlural';
  }

  @override
  String get pkFileImportGroupsLabel => 'Groups';

  @override
  String get pkFileImportFrontingSessionsLabel =>
      'Switches found (not imported)';

  @override
  String get pkFileImportSwitchesFoundLabel => 'Switches found (not imported)';

  @override
  String pkFileImportPreviewNote(String termPlural) {
    return 'Existing $termPlural with the same PluralKit ID will be updated. To import fronting history, add a PluralKit token so Prism can match export switches before importing fronts.';
  }

  @override
  String get pkFileImportImportButton => 'Import';

  @override
  String get pkFileImportPickDifferentButton => 'Pick a different file';

  @override
  String get pkFileImportCompleteHeading => 'Import complete';

  @override
  String get pkFileImportSwitchesCreatedLabel => 'Switches created';

  @override
  String get pkFileImportSwitchesSkippedLabel =>
      'Switches found (not imported)';

  @override
  String get settingsFrontingSessionDisplaySectionTitle =>
      'Session display & front behavior';

  @override
  String get settingsFrontingListViewModeLabel => 'Session list view';

  @override
  String get settingsFrontingListViewModeCombinedPeriods => 'Combined periods';

  @override
  String get settingsFrontingListViewModeCombinedPeriodsDescription =>
      'Avatar stacks for each unique fronter group';

  @override
  String settingsFrontingListViewModePerMemberRows(String term) {
    return 'Per-$term rows';
  }

  @override
  String get settingsFrontingListViewModePerMemberRowsDescription =>
      'One row per fronter session, side-by-side';

  @override
  String get settingsFrontingListViewModeTimeline => 'Timeline';

  @override
  String get settingsFrontingListViewModeTimelineDescription =>
      'Bar chart view of fronting over time';

  @override
  String get settingsAddFrontDefaultBehaviorLabel => 'When adding a new front';

  @override
  String get settingsAddFrontDefaultBehaviorAdditive => 'Add as co-fronter';

  @override
  String get settingsAddFrontDefaultBehaviorAdditiveDescription =>
      'New fronts join existing ones';

  @override
  String get settingsAddFrontDefaultBehaviorReplace =>
      'Replace current fronters';

  @override
  String get settingsAddFrontDefaultBehaviorReplaceDescription =>
      'End all current fronts before starting new ones';

  @override
  String get settingsQuickFrontDefaultBehaviorLabel => 'When using quick front';

  @override
  String get settingsQuickFrontDefaultBehaviorAdditive => 'Add as co-fronter';

  @override
  String get settingsQuickFrontDefaultBehaviorReplace =>
      'Replace current fronters';
}
