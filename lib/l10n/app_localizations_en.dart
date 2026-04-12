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
  String get onboardingAddMembersSkylarsDefaults => 'Skylar\'s Defaults';

  @override
  String get onboardingAddMembersNoMembers =>
      'No members yet.\nTap \"Add Member\" or use the defaults.';

  @override
  String get onboardingAddMembersRemoveMember => 'Remove member';

  @override
  String get onboardingAddMembersAddMember => 'Add Member';

  @override
  String get onboardingAddMemberSheetTitle => 'Add Member';

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
  String get onboardingFeaturesChatDescription =>
      'Internal messaging between system members';

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
  String get onboardingPluralKitImportButton => 'Import Members';

  @override
  String onboardingPluralKitImportSuccess(int count) {
    return 'Imported $count members from PluralKit!';
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
  String get onboardingWhosFrontingSelectHint =>
      'Tap to select who is currently fronting';

  @override
  String get onboardingWhosFrontingNoMembers =>
      'No members added yet.\nGo back to add members first.';

  @override
  String get onboardingChatSuggestedChannels => 'Suggested Channels';

  @override
  String get onboardingChatCustomChannel => 'Custom Channel';

  @override
  String get onboardingChatChannelNameHint => 'Channel name';

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
  String get onboardingPreferencesPerMemberColors => 'Per-Member Colors';

  @override
  String get onboardingPreferencesPerMemberColorsSubtitle =>
      'Let each member have their own accent color';

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
  String get onboardingSyncEnterPassword => 'Enter your password';

  @override
  String get onboardingSyncEnterPasswordDescription =>
      'Enter your sync password to finish enrolling this device.';

  @override
  String get onboardingSyncPasswordHint => 'Password';

  @override
  String get onboardingSyncFinishPairing => 'Finish Pairing';

  @override
  String get onboardingSyncEnterPasswordPrompt => 'Please enter your password.';

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
  String get onboardingSyncPairingFailed => 'Pairing failed';

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
  String get habitsCustomMessageField => 'Custom message (optional)';

  @override
  String get habitsSectionAssignment => 'ASSIGNMENT';

  @override
  String get habitsAssignedMember => 'Assigned Member';

  @override
  String get habitsAssignedMemberAnyone => 'Anyone';

  @override
  String get habitsOnlyNotifyWhenFronting => 'Only notify when fronting';

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
    return '$count options';
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
  String get pollsDetailSelectToVoteAs => 'to vote as';

  @override
  String get pollsDetailNoMembers => 'No members available';

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
}
