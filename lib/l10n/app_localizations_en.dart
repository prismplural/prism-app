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
  String get voiceMicPermissionDenied =>
      'Microphone permission is required to record voice notes.';

  @override
  String get voiceMicPermissionBlocked =>
      'Microphone access is blocked. Enable it in Settings.';

  @override
  String get voiceRecordingFailed => 'Could not start recording.';
}
