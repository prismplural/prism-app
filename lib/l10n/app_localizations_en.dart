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
  String get noResults => 'No results';

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
  String get selectMember => 'Select member';

  @override
  String get selectMembers => 'Select members';

  @override
  String get selectAMember => 'Select a member';

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
  String get searchMembers => 'Search members...';

  @override
  String get noMembersFound => 'No members found';

  @override
  String get moreOptions => 'More options';

  @override
  String get settingsSectionSystem => 'System';

  @override
  String get settingsSectionApp => 'App';

  @override
  String get settingsSectionData => 'Data';

  @override
  String get settingsSectionAbout => 'About';

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
  String get settingsSync => 'Sync';

  @override
  String get settingsSharing => 'Sharing';

  @override
  String get settingsImportExport => 'Import & Export';

  @override
  String get settingsResetData => 'Reset Data';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsEncryptionPrivacy => 'Encryption & Privacy';

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
  String get appearanceAccentColor => 'Accent Color';

  @override
  String get appearancePerMemberColors => 'Per-Member Colors';

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
  String get appearancePreview => 'Preview';

  @override
  String get appearanceSamplePronouns => 'she/her';

  @override
  String get appearanceFronting => 'Fronting';

  @override
  String get appearanceUsingSystemPalette => 'Using your system color palette';

  @override
  String get syncTitle => 'Sync';

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
  String get syncChangePassword => 'Change Password';

  @override
  String get syncChangePasswordSubtitle =>
      'Update your sync encryption password';

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
  String get syncSetupPasswordTitle => 'Create Password';

  @override
  String get syncSetupSecretKeyTitle => 'Your Secret Key';

  @override
  String get syncSetupIntroHeadline =>
      'Keep your data in sync across all your devices.';

  @override
  String get syncSetupIntroBody =>
      'Everything is end-to-end encrypted — the server never sees your data. You\'ll create a password and receive a recovery key to keep safe.';

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
  String get syncSetupPasswordIntro =>
      'Create a password to protect your encryption keys.';

  @override
  String get syncSetupPasswordHelp =>
      'You\'ll need this password each time you set up a new device.';

  @override
  String get syncSetupPasswordLabel => 'Password';

  @override
  String get syncSetupConfirmPasswordLabel => 'Confirm password';

  @override
  String get syncSetupContinueButton => 'Continue';

  @override
  String get syncSetupCompleteButton => 'Complete setup';

  @override
  String get syncSetupPasswordTooShort =>
      'Password must be at least 8 characters';

  @override
  String get syncSetupPasswordMismatch => 'Passwords do not match';

  @override
  String get syncSetupProgressCreatingGroup => 'Creating sync group...';

  @override
  String get syncSetupProgressConfiguringEngine => 'Configuring encryption...';

  @override
  String get syncSetupProgressCachingKeys => 'Securing keys...';

  @override
  String get syncSetupProgressBootstrapping => 'Uploading your data...';

  @override
  String get syncSetupProgressSyncing => 'Syncing...';

  @override
  String get syncSecretKeyTitle => 'Secret Key';

  @override
  String get syncVerifyPasswordTitle => 'Verify Password';

  @override
  String get syncVerifyPasswordPrompt =>
      'Enter your sync password to reveal your 12-word recovery phrase.';

  @override
  String get syncPasswordHint => 'Sync password';

  @override
  String get syncShowPassword => 'Show password';

  @override
  String get syncHidePassword => 'Hide password';

  @override
  String get syncRevealSecretKey => 'Reveal Secret Key';

  @override
  String get syncSecretKeyNotFound => 'Secret Key not found in keychain.';

  @override
  String get syncEngineNotAvailable => 'Sync engine not available.';

  @override
  String get syncIncorrectPassword => 'Incorrect password. Please try again.';

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
  String get resetDataConfirmAll =>
      'This will permanently delete all your data including members, fronting sessions, messages, polls, habits, sleep data, and settings. This action cannot be undone.';

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
  String get statisticsTotalMembers => 'Total members';

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
    return '$count sessions';
  }

  @override
  String statisticsActiveMembersBreakdown(int active, int inactive) {
    return '$active active, $inactive inactive';
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
  String get debugResetDatabaseConfirm2Message =>
      'This will permanently erase all members, sessions, conversations, messages, and polls. There is no undo.';

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
  String get systemInfoRemoveAvatar => 'Remove avatar';

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
  String get devicesThisDevicePill => 'This Device';

  @override
  String get devicesStatusActive => 'Active';

  @override
  String get devicesStatusStale => 'Stale';

  @override
  String get devicesStatusRevoked => 'Revoked';

  @override
  String get devicesRotateKey => 'Rotate signing key';

  @override
  String get devicesRevokeDevice => 'Revoke device';

  @override
  String get devicesDeviceCopied => 'Device ID copied';

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
  String get syncTroubleshootingTitle => 'Sync Troubleshooting';

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
  String get syncTroubleshootingOpenEventLog => 'Open Sync Event Log';

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
  String get featureChatDescription =>
      'Internal messaging between system members.';

  @override
  String get featureChatGeneral => 'General';

  @override
  String get featureChatEnable => 'Enable Chat';

  @override
  String get featureChatEnableSubtitle => 'In-system messaging between members';

  @override
  String get featureChatOptions => 'Options';

  @override
  String get featureChatLogFront => 'Log Front on Switch';

  @override
  String get featureChatLogFrontSubtitle =>
      'Changing who\'s speaking in chat also logs a front';

  @override
  String get featureChatGifSearch => 'GIF Search';

  @override
  String get featureChatGifSearchSubtitle => 'Search and send GIFs in chat';

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
  String get featureHabitsDescription =>
      'Track recurring tasks and build streaks with your system members.';

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
  String get featureNotesDescription =>
      'A personal journal for system members. Disabling hides notes from navigation but keeps existing entries.';

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
  String get frontingMenuWakeUpAs => 'Wake Up As...';

  @override
  String get frontingMenuLogFront => 'Log Front';

  @override
  String get frontingMenuNewPoll => 'New Poll';

  @override
  String get frontingMenuStartSleep => 'Start Sleep';

  @override
  String get frontingWakeUpAsTitle => 'Wake Up As...';

  @override
  String frontingErrorWakingUp(Object error) {
    return 'Error waking up: $error';
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
  String get frontingSleepping => 'Sleep';

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
  String get frontingSelectFronter => 'Select Fronter';

  @override
  String get frontingSelectMember => 'Select Member';

  @override
  String get frontingCoFrontToggle => 'Co-front';

  @override
  String get frontingCoFronters => 'Co-Fronters';

  @override
  String get frontingNoOtherMembers => 'No other members available';

  @override
  String get frontingCoFrontHint =>
      'Tap a member to add them as a co-fronter to the current session.';

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
  String get frontingSearchMembersHint => 'Search members...';

  @override
  String frontingNoMembersMatching(String query) {
    return 'No members matching \"$query\"';
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
  String get memberEditTooltip => 'Edit member';

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
  String get memberAdded => 'Member added';

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
  String get memberRemoveFromGroupTitle => 'Remove member';

  @override
  String memberRemoveFromGroupMessage(String name) {
    return 'Remove $name from this group? The member will not be deleted.';
  }

  @override
  String get memberEmptyList => 'No members yet';

  @override
  String get memberGroupEmptyList => 'No groups yet';

  @override
  String get memberGroupEmptySubtitle =>
      'Create groups to organize your system members';

  @override
  String get memberGroupNoMembers => 'No members';

  @override
  String get memberGroupNoMembersSubtitle => 'Add members to this group';

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
  String get memberNoteAddHeadmate => 'Add headmate';

  @override
  String get memberNoteDiscardTitle => 'Discard changes?';

  @override
  String get memberNoteDiscardMessage =>
      'You have unsaved changes. Are you sure you want to discard them?';

  @override
  String get memberNoteDiscardConfirm => 'Discard';

  @override
  String get memberNoteChooseHeadmate => 'Choose Headmate';

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
  String get memberGroupSectionMembers => 'Members';

  @override
  String get memberGroupAddMember => 'Add member';

  @override
  String get memberGroupDeleteTitle => 'Delete group';

  @override
  String memberGroupDeleteMessage(String name) {
    return 'Are you sure you want to delete \"$name\"? Members will not be deleted.';
  }

  @override
  String get memberGroupDeleteConfirm => 'Delete';

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
  String get memberGroupColorLabel => 'Color (hex)';

  @override
  String memberGroupErrorSaving(Object error) {
    return 'Error saving group: $error';
  }

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
  String get memberCustomColorSubtitle =>
      'Use a personal color for this member';

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
    return '$count selected';
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
}
