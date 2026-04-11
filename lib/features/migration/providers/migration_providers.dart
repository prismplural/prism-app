import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_api_client.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

/// Key used to track whether a previous SP import has been completed.
const _spImportCompletedKey = 'sp_import_completed';

/// Current import state exposed to the UI.
class MigrationState {
  final ImportState step;
  final ImportSource source;
  final SpExportData? exportData;
  final ImportResult? result;
  final String? error;
  final int current;
  final int total;
  final String progressLabel;
  final String? spUsername;

  const MigrationState({
    this.step = ImportState.idle,
    this.source = ImportSource.file,
    this.exportData,
    this.result,
    this.error,
    this.current = 0,
    this.total = 0,
    this.progressLabel = '',
    this.spUsername,
  });

  double get progress => total > 0 ? current / total : 0;

  MigrationState copyWith({
    ImportState? step,
    ImportSource? source,
    SpExportData? exportData,
    ImportResult? result,
    String? error,
    int? current,
    int? total,
    String? progressLabel,
    String? spUsername,
  }) {
    return MigrationState(
      step: step ?? this.step,
      source: source ?? this.source,
      exportData: exportData ?? this.exportData,
      result: result ?? this.result,
      error: error ?? this.error,
      current: current ?? this.current,
      total: total ?? this.total,
      progressLabel: progressLabel ?? this.progressLabel,
      spUsername: spUsername ?? this.spUsername,
    );
  }
}

/// Notifier managing the SP import workflow.
class ImporterNotifier extends Notifier<MigrationState> {
  final _importer = SpImporter();
  SpApiClient? _apiClient;

  @override
  MigrationState build() => const MigrationState();

  // ---------------------------------------------------------------------------
  // File import flow
  // ---------------------------------------------------------------------------

  /// Let the user pick a file, then parse it.
  Future<void> selectAndParseFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      state = state.copyWith(
        step: ImportState.parsing,
        source: ImportSource.file,
      );

      final exportData = _importer.parseFile(filePath);

      if (exportData.isEmpty) {
        state = state.copyWith(
          step: ImportState.error,
          error: 'The selected file does not contain any recognized '
              'Simply Plural data. Please check that you exported '
              'from Simply Plural correctly.',
        );
        return;
      }

      state = state.copyWith(
        step: ImportState.previewing,
        exportData: exportData,
      );
    } on FormatException catch (e) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Could not parse the file: ${e.message}',
      );
    } catch (_) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'An unexpected error occurred while reading the file.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // API import flow
  // ---------------------------------------------------------------------------

  /// Verify an SP API token. On success, transitions to [ImportState.verifying]
  /// then to [ImportState.previewing] equivalent — actually a confirmation step
  /// showing the connected username.
  Future<void> verifyToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        step: ImportState.error,
        source: ImportSource.api,
        error: 'Please enter your Simply Plural API token.',
      );
      return;
    }

    state = state.copyWith(
      step: ImportState.verifying,
      source: ImportSource.api,
      progressLabel: 'Verifying token\u2026',
    );

    try {
      _apiClient?.dispose();
      _apiClient = SpApiClient(token: trimmed);
      final result = await _apiClient!.verifyToken();

      state = state.copyWith(
        step: ImportState.verifying,
        spUsername: result.username ?? result.systemId,
      );
    } on SpAuthError {
      _apiClient?.dispose();
      _apiClient = null;
      state = state.copyWith(
        step: ImportState.error,
        error: 'Invalid token. Make sure you copied the full token from '
            'Simply Plural (Settings \u2192 Account \u2192 Tokens) and that '
            'it has Read permission.',
      );
    } on TimeoutException {
      _apiClient?.dispose();
      _apiClient = null;
      state = state.copyWith(
        step: ImportState.error,
        error: 'Could not reach Simply Plural\u2019s servers. They may be '
            'temporarily unavailable. Try again in a few minutes, or use '
            'a file import instead.',
      );
    } catch (_) {
      _apiClient?.dispose();
      _apiClient = null;
      state = state.copyWith(
        step: ImportState.error,
        error: 'Could not connect to Simply Plural. Check your internet '
            'connection and try again.',
      );
    }
  }

  /// Fetch all data from the SP API after successful token verification.
  Future<void> fetchFromApi() async {
    final client = _apiClient;
    if (client == null) return;

    state = state.copyWith(
      step: ImportState.fetching,
      current: 0,
      total: 0,
      progressLabel: 'Connecting\u2026',
    );

    try {
      final exportData = await client.fetchAll(
        onProgress: (collection, count) {
          state = state.copyWith(
            progressLabel: '$collection\u2026 $count items',
          );
        },
      );

      if (exportData.isEmpty) {
        state = state.copyWith(
          step: ImportState.error,
          error: 'No data found in your Simply Plural account.',
        );
        return;
      }

      state = state.copyWith(
        step: ImportState.previewing,
        exportData: exportData,
      );
    } on SpAuthError {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Your token was revoked or expired during the fetch. '
            'Please generate a new token in Simply Plural.',
      );
    } on TimeoutException {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Simply Plural\u2019s servers stopped responding. '
            'Try again later or use a file import instead.',
      );
    } catch (_) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Something went wrong while fetching your data. '
            'Try again, or use a file import instead.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Shared import execution
  // ---------------------------------------------------------------------------

  /// Execute the import using the previously parsed/fetched data.
  ///
  /// If [resetFirst] is true, all existing app data is wiped before importing.
  Future<void> executeImport({
    bool downloadAvatars = true,
    bool resetFirst = false,
  }) async {
    final data = state.exportData;
    if (data == null) return;

    state = state.copyWith(
      step: ImportState.importing,
      current: 0,
      total: data.totalEntities,
      progressLabel: 'Starting import\u2026',
    );

    try {
      final result = await _importer.executeImport(
        db: ref.read(databaseProvider),
        data: data,
        memberRepo: ref.read(memberRepositoryProvider),
        sessionRepo: ref.read(frontingSessionRepositoryProvider),
        conversationRepo: ref.read(conversationRepositoryProvider),
        messageRepo: ref.read(chatMessageRepositoryProvider),
        pollRepo: ref.read(pollRepositoryProvider),
        notesRepo: ref.read(notesRepositoryProvider),
        commentsRepo: ref.read(frontSessionCommentsRepositoryProvider),
        customFieldsRepo: ref.read(customFieldsRepositoryProvider),
        groupsRepo: ref.read(memberGroupsRepositoryProvider),
        remindersRepo: ref.read(remindersRepositoryProvider),
        settingsRepo: ref.read(systemSettingsRepositoryProvider),
        categoriesRepo: ref.read(conversationCategoriesRepositoryProvider),
        downloadAvatars: downloadAvatars,
        clearExistingData: resetFirst,
        onProgress: (current, total, label) {
          state = state.copyWith(
            current: current,
            total: total,
            progressLabel: label,
          );
        },
      );

      // Mark that an SP import has been completed.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_spImportCompletedKey, true);

      state = state.copyWith(
        step: ImportState.complete,
        result: result,
        current: state.total,
      );
    } catch (_) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Import failed. No changes were made to your data.',
      );
    }
  }

  /// Reset to initial state and clean up resources.
  void reset() {
    _apiClient?.dispose();
    _apiClient = null;
    state = const MigrationState();
  }
}

final importerProvider =
    NotifierProvider<ImporterNotifier, MigrationState>(ImporterNotifier.new);

/// Whether a previous SP import has been completed.
final hasPreviousSpImportProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_spImportCompletedKey) ?? false;
});
