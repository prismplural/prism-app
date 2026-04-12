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
  String get notesTitle => 'Notes';

  @override
  String get notesNewNoteTooltip => 'New note';

  @override
  String get notesEmptyTitle => 'No notes yet';

  @override
  String get notesEmptySubtitle =>
      'Create notes to keep track of thoughts and observations';

  @override
  String get notesNewNoteAction => 'New Note';

  @override
  String get notesUntitled => 'Untitled';

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
  String get migrationSupportedMembers => 'Members';

  @override
  String get migrationSupportedCustomFronts => 'Custom fronts';

  @override
  String get migrationSupportedFrontingHistory => 'Fronting history';

  @override
  String get migrationSupportedChatChannels => 'Chat channels & messages';

  @override
  String get migrationSupportedPolls => 'Polls';

  @override
  String get migrationSupportedMemberColors => 'Member colors';

  @override
  String get migrationSupportedMemberDescriptions => 'Member descriptions';

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
  String get migrationReplaceAllMessage =>
      'This will delete all existing members, front history, conversations, and other data before importing. This action cannot be undone.\n\nIf you have sync set up, other paired devices should also be reset to avoid conflicts.';

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
  String get migrationResultMembers => 'Members';

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
  String pluralkitMembersPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members pulled',
      one: '1 member pulled',
    );
    return '$_temp0';
  }

  @override
  String pluralkitMembersPushed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members pushed',
      one: '1 member pushed',
    );
    return '$_temp0';
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
  String pluralkitMembersUnchanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members unchanged',
      one: '1 member unchanged',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitInfoSync =>
      'Supports pull, push, or bidirectional sync. Choose your preferred direction above.';

  @override
  String get pluralkitInfoToken =>
      'Your token is stored securely in the device keychain and never leaves your device.';

  @override
  String get pluralkitInfoMembers =>
      'Members are matched by PluralKit UUID. Existing members are updated, new ones are created.';

  @override
  String get pluralkitInfoSwitches =>
      'Switches are imported as fronting sessions. Duplicate switches are automatically skipped.';

  @override
  String get pluralkitJustNow => 'Just now';

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
  String get dataManagementPluralKitRowSubtitle =>
      'Import members & fronting via API token';

  @override
  String get dataManagementSimplyPluralRowTitle => 'Simply Plural';

  @override
  String get dataManagementSimplyPluralRowSubtitle =>
      'Import from a Simply Plural export file';

  @override
  String get dataManagementExportYourData => 'Export Your Data';

  @override
  String get dataManagementExportDescription =>
      'Create a password-protected backup of all your data including members, fronting sessions, messages, polls, and settings.';

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
      'Use a passphrase of 15+ words for best protection';

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
  String get dataManagementPreviewMembers => 'Members';

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
}
