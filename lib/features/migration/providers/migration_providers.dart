import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_api_client.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_analysis.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
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

  /// Whether the user chose "Start Fresh" (wipe existing data). Carried across
  /// the disposition step so the eventual import uses the right mode.
  final bool pendingResetFirst;

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
    this.pendingResetFirst = false,
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
    bool? pendingResetFirst,
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
      pendingResetFirst: pendingResetFirst ?? this.pendingResetFirst,
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

  /// Enter the custom-front disposition step if the export has CFs. Otherwise
  /// run the import directly. [resetFirst] carries the user's add-to-existing
  /// vs. start-fresh choice across the disposition step.
  void proceedFromPreview({bool resetFirst = false}) {
    final data = state.exportData;
    if (data == null) return;

    if (data.customFronts.isEmpty) {
      unawaited(executeImport(resetFirst: resetFirst));
      return;
    }

    // Seed disposition map if export identity changed.
    ref.read(cfDispositionControllerProvider).seedFromExport(data);
    state = state.copyWith(
      step: ImportState.chooseDispositions,
      pendingResetFirst: resetFirst,
    );
  }

  /// Return to the preview from the disposition step without losing user edits.
  void backToPreview() {
    state = state.copyWith(step: ImportState.previewing);
  }

  /// Continue from the disposition step into the actual import, using the
  /// preserved start-fresh choice and the current disposition map.
  Future<void> continueFromDispositions({bool downloadAvatars = true}) async {
    await executeImport(
      downloadAvatars: downloadAvatars,
      resetFirst: state.pendingResetFirst,
    );
  }

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
        spImportDao: ref.read(databaseProvider).spImportDao,
        downloadAvatars: downloadAvatars,
        clearExistingData: resetFirst,
        customFrontDispositions: ref.read(cfDispositionProvider),
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

      ref.read(cfDispositionControllerProvider).clear();

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
    ref.read(cfDispositionControllerProvider).clear();
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

// ---------------------------------------------------------------------------
// Custom front disposition state
// ---------------------------------------------------------------------------

/// State wrapper for the disposition step: the per-CF choice map, the paired
/// suggestion map (so UI can display the "reason" text), and the export
/// identity hash used to decide whether to re-seed.
class CfDispositionState {
  final Map<String, CfDisposition> dispositions;
  final Map<String, CfSuggestion> suggestions;
  final String? exportIdentity;

  const CfDispositionState({
    this.dispositions = const {},
    this.suggestions = const {},
    this.exportIdentity,
  });
}

class CfDispositionNotifier extends Notifier<CfDispositionState> {
  @override
  CfDispositionState build() => const CfDispositionState();

  /// Stable hash of the export so back-nav into the disposition step keeps
  /// user edits but a brand-new export re-seeds. Based on system id + member
  /// count + CF id set so small edits within the same export don't clobber.
  String _identityFor(SpExportData data) {
    // Deterministic canonical form: sort CFs by id so export ordering
    // doesn't affect the hash. Include CF names (catches renamed/replaced
    // CFs that keep the same id), front-history length, and timer count so
    // a meaningfully-different export reseeds instead of inheriting stale
    // dispositions keyed by CF id alone.
    final sortedCfs = [...data.customFronts]
      ..sort((a, b) => a.id.compareTo(b.id));
    final cfIds = sortedCfs.map((c) => c.id).toList();
    final cfNames = sortedCfs.map((c) => c.name).toList();
    final payload = <String, Object?>{
      'sys': data.systemName,
      'members': data.members.length,
      'cfCount': data.customFronts.length,
      'cfIds': cfIds,
      'cfNames': cfNames,
      'fhLen': data.frontHistory.length,
      'timers':
          data.automatedTimers.length + data.repeatedTimers.length,
    };
    final bytes = utf8.encode(jsonEncode(payload));
    return sha256.convert(bytes).toString();
  }

  /// Seed once per export identity. If the identity matches the previous
  /// seed, preserves user edits; otherwise re-seeds from [suggestDefaults].
  void seedFromExport(SpExportData data) {
    final identity = _identityFor(data);
    if (identity == state.exportIdentity && state.dispositions.isNotEmpty) {
      return;
    }
    final usage = analyzeCfUsage(data);
    final suggestions = suggestDefaults(data.customFronts, usage);
    state = CfDispositionState(
      dispositions: {
        for (final e in suggestions.entries) e.key: e.value.disposition,
      },
      suggestions: suggestions,
      exportIdentity: identity,
    );
  }

  /// Force-reseed using the smart defaults, discarding user edits.
  void resetToDefaults(SpExportData data) {
    final usage = analyzeCfUsage(data);
    final suggestions = suggestDefaults(data.customFronts, usage);
    state = CfDispositionState(
      dispositions: {
        for (final e in suggestions.entries) e.key: e.value.disposition,
      },
      suggestions: suggestions,
      exportIdentity: _identityFor(data),
    );
  }

  /// Set the disposition for a single CF.
  void setDisposition(String spId, CfDisposition value) {
    final next = Map<String, CfDisposition>.from(state.dispositions);
    next[spId] = value;
    state = CfDispositionState(
      dispositions: next,
      suggestions: state.suggestions,
      exportIdentity: state.exportIdentity,
    );
  }

  /// Clear everything (call on import cancel / success).
  void clear() {
    state = const CfDispositionState();
  }
}

final _cfDispositionStateProvider =
    NotifierProvider<CfDispositionNotifier, CfDispositionState>(
        CfDispositionNotifier.new);

/// Current per-CF disposition map, keyed by SP CF id.
final cfDispositionProvider = Provider<Map<String, CfDisposition>>((ref) {
  return ref.watch(_cfDispositionStateProvider).dispositions;
});

/// The smart-default suggestion paired with each CF (disposition + reason).
/// UI reads this to show the "why" under each card.
final cfSuggestionsProvider = Provider<Map<String, CfSuggestion>>((ref) {
  return ref.watch(_cfDispositionStateProvider).suggestions;
});

/// Convenience accessor for the notifier so UI can call setDisposition /
/// resetToDefaults / clear without poking the private state provider name.
final cfDispositionControllerProvider = Provider<CfDispositionNotifier>((ref) {
  return ref.read(_cfDispositionStateProvider.notifier);
});
