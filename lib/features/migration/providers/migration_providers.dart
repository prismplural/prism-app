import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/migration/services/sp_api_client.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_analysis.dart';
import 'package:prism_plurality/features/migration/services/sp_custom_front_disposition.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/providers/sp_member_mapping_provider.dart';

/// Key used to track whether a previous SP import has been completed.
const _spImportCompletedKey = 'sp_import_completed';
const _unsetAvatarZipPath = Object();
const _unsetAvatarZipName = Object();
const _unsetAvatarZipBytes = Object();

/// Current import state exposed to the UI.
class MigrationState {
  final ImportState step;
  final ImportSource source;
  final SpExportData? exportData;
  final ImportResult? result;
  final String? error;
  final String? avatarZipPath;
  final String? avatarZipName;
  final Uint8List? avatarZipBytes;
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
    this.avatarZipPath,
    this.avatarZipName,
    this.avatarZipBytes,
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
    Object? avatarZipPath = _unsetAvatarZipPath,
    Object? avatarZipName = _unsetAvatarZipName,
    Object? avatarZipBytes = _unsetAvatarZipBytes,
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
      avatarZipPath: identical(avatarZipPath, _unsetAvatarZipPath)
          ? this.avatarZipPath
          : avatarZipPath as String?,
      avatarZipName: identical(avatarZipName, _unsetAvatarZipName)
          ? this.avatarZipName
          : avatarZipName as String?,
      avatarZipBytes: identical(avatarZipBytes, _unsetAvatarZipBytes)
          ? this.avatarZipBytes
          : avatarZipBytes as Uint8List?,
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
      final handle = await ref
          .read(prismFileDialogServiceProvider)
          .pickFile(allowedExtensions: const ['json']);
      if (handle == null) return;

      state = state.copyWith(
        step: ImportState.parsing,
        source: ImportSource.file,
      );

      final exportData = _importer.parseString(
        utf8.decode(await handle.readAsBytes()),
      );

      if (exportData.isEmpty) {
        state = state.copyWith(
          step: ImportState.error,
          error:
              'The selected file does not contain any recognized '
              'Simply Plural data. Please check that you exported '
              'from Simply Plural correctly.',
        );
        return;
      }

      if (exportData.hasEncryptedChatMessages) {
        state = state.copyWith(
          step: ImportState.encryptedChatsDetected,
          exportData: exportData,
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

  /// Let the user pick the optional Simply Plural avatar ZIP export.
  Future<void> selectAvatarZipFile() async {
    final handle = await ref
        .read(prismFileDialogServiceProvider)
        .pickFile(allowedExtensions: const ['zip']);

    if (handle == null) return;

    state = state.copyWith(
      avatarZipPath: handle.path,
      avatarZipName: handle.name,
      avatarZipBytes: handle.path == null ? await handle.readAsBytes() : null,
    );
  }

  void clearAvatarZipFile() {
    state = state.copyWith(
      avatarZipPath: null,
      avatarZipName: null,
      avatarZipBytes: null,
    );
  }

  void skipEncryptedChatsAndPreview() {
    final data = state.exportData;
    if (data == null) return;

    state = state.copyWith(
      step: ImportState.previewing,
      exportData: data.withoutChat(),
    );
  }

  Future<void> chooseFreshFileImport() async {
    reset();
    await selectAndParseFile();
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
        error:
            'Invalid token. Make sure you copied the full token from '
            'Simply Plural (Settings \u2192 Account \u2192 Tokens) and that '
            'it has Read permission.',
      );
    } on TimeoutException {
      _apiClient?.dispose();
      _apiClient = null;
      state = state.copyWith(
        step: ImportState.error,
        error:
            'Could not reach Simply Plural\u2019s servers. They may be '
            'temporarily unavailable. Try again in a few minutes, or use '
            'a file import instead.',
      );
    } catch (_) {
      _apiClient?.dispose();
      _apiClient = null;
      state = state.copyWith(
        step: ImportState.error,
        error:
            'Could not connect to Simply Plural. Check your internet '
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
        error:
            'Your token was revoked or expired during the fetch. '
            'Please generate a new token in Simply Plural.',
      );
    } on TimeoutException {
      state = state.copyWith(
        step: ImportState.error,
        error:
            'Simply Plural\u2019s servers stopped responding. '
            'Try again later or use a file import instead.',
      );
    } catch (_) {
      state = state.copyWith(
        step: ImportState.error,
        error:
            'Something went wrong while fetching your data. '
            'Try again, or use a file import instead.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Shared import execution
  // ---------------------------------------------------------------------------

  /// Enter member mapping and custom-front disposition steps as needed.
  /// [resetFirst] carries the user's add-to-existing vs. start-fresh choice
  /// across any pre-import decision steps.
  void proceedFromPreview({bool resetFirst = false}) {
    final data = state.exportData;
    if (data == null) return;

    if (!resetFirst && data.members.isNotEmpty) {
      unawaited(_enterMemberMapping(data, resetFirst: resetFirst));
      return;
    }

    _continueAfterMemberMapping(data, resetFirst: resetFirst);
  }

  Future<void> _enterMemberMapping(
    SpExportData data, {
    required bool resetFirst,
  }) async {
    try {
      await ref.read(spMemberMappingControllerProvider).seedFromExport(data);
      final mappingState = ref.read(spMemberMappingProvider);
      if (mappingState.localMembers.isEmpty) {
        _continueAfterMemberMapping(data, resetFirst: resetFirst);
        return;
      }
      state = state.copyWith(
        step: ImportState.matchMembers,
        pendingResetFirst: resetFirst,
      );
    } catch (_) {
      state = state.copyWith(
        step: ImportState.error,
        error: 'Could not prepare member matching choices.',
      );
    }
  }

  void _continueAfterMemberMapping(
    SpExportData data, {
    required bool resetFirst,
  }) {
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

  /// Return to the preview from a decision step without losing user edits.
  void backToPreview() {
    state = state.copyWith(step: ImportState.previewing);
  }

  /// Continue from member mapping to CF disposition or the actual import.
  void continueFromMemberMapping() {
    final data = state.exportData;
    if (data == null) return;
    _continueAfterMemberMapping(data, resetFirst: state.pendingResetFirst);
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
        boardPostsRepo: ref.read(memberBoardPostsRepositoryProvider),
        categoriesRepo: ref.read(conversationCategoriesRepositoryProvider),
        spImportDao: ref.read(databaseProvider).spImportDao,
        downloadAvatars: downloadAvatars,
        avatarZipPath: state.avatarZipPath,
        avatarZipBytes: state.avatarZipBytes,
        clearExistingData: resetFirst,
        customFrontDispositions: ref.read(cfDispositionProvider),
        memberMappingDecisions: resetFirst
            ? const {}
            : ref.read(spMemberMappingDecisionsProvider),
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
      ref.read(spMemberMappingControllerProvider).clear();

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

  /// Retry only avatar downloads for the currently loaded SP export.
  ///
  /// This is intentionally same-session: Prism keeps SP entity ID mappings,
  /// but it does not persist avatar source URLs after the import flow is
  /// dismissed.
  Future<void> retryAvatarDownloads() async {
    final data = state.exportData;
    final previous = state.result;
    if (data == null || previous == null) return;

    state = state.copyWith(
      step: ImportState.downloadingAvatars,
      current: 0,
      total: 0,
      progressLabel: 'Retrying avatar downloads\u2026',
    );

    try {
      final retryResult = await _importer.retryAvatarDownloads(
        data: data,
        memberRepo: ref.read(memberRepositoryProvider),
        settingsRepo: ref.read(systemSettingsRepositoryProvider),
        spImportDao: ref.read(databaseProvider).spImportDao,
        customFrontDispositions: ref.read(cfDispositionProvider),
        onProgress: (current, total, label) {
          state = state.copyWith(
            current: current,
            total: total,
            progressLabel: label,
          );
        },
      );

      final retainedWarnings = previous.warnings
          .where((warning) => !ImportResult.isAvatarDownloadWarning(warning))
          .toList();
      final mergedWarnings = [...retainedWarnings, ...retryResult.warnings];
      final avatarsDownloaded =
          retryResult.avatarsDownloaded > previous.avatarsDownloaded
          ? retryResult.avatarsDownloaded
          : previous.avatarsDownloaded;

      state = state.copyWith(
        step: ImportState.complete,
        result: previous.copyWith(
          avatarsDownloaded: avatarsDownloaded,
          systemAvatarDownloaded:
              previous.systemAvatarDownloaded ||
              retryResult.systemAvatarDownloaded,
          warnings: mergedWarnings,
          duration: previous.duration + retryResult.duration,
        ),
      );
    } catch (_) {
      state = state.copyWith(step: ImportState.complete, result: previous);
    }
  }

  /// Reset to initial state and clean up resources.
  void reset() {
    _apiClient?.dispose();
    _apiClient = null;
    ref.read(cfDispositionControllerProvider).clear();
    ref.read(spMemberMappingControllerProvider).clear();
    state = const MigrationState();
  }
}

final importerProvider = NotifierProvider<ImporterNotifier, MigrationState>(
  ImporterNotifier.new,
);

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
      'timers': data.automatedTimers.length + data.repeatedTimers.length,
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
      CfDispositionNotifier.new,
    );

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
