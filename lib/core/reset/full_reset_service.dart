import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart'
    show SecureStorageDiagnostic;
import 'package:prism_plurality/core/reset/native_reset_keys.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

const kFreshInstallSentinelKey = 'has_launched_before';
const kFullResetRestartRequiredKey = 'prism.reset.restart_required';
const kFullResetCompletedAtKey = 'prism.reset.completed_at';
const kFreshInstallAnomalyKey = 'prism.reset.fresh_install_anomaly';
const kNativeResetKeyClearPendingKey = 'prism.reset.native_key_clear_pending';
const kMediaCacheClearPendingKey = 'prism.reset.media_cache_clear_pending';

/// SharedPreferences flag set to `true` on the first successful sync pairing.
///
/// Read by the §7 keychain-unreadable recovery screen to decide whether the
/// "Re-pair from another device" affordance is meaningful for this user. A
/// fresh install that never paired should not see the re-pair option — there
/// is nothing to re-pair from.
///
/// TODO(§6 / §10 follow-up): set this from the pair-success path in
/// `lib/core/sync/prism_sync_providers.dart` / `lib/features/onboarding/`.
/// For §7 scope this constant is read-only.
const kPrismHadSyncSetup = 'prism.sync.had_setup';

typedef FullResetLog = void Function(String message);
typedef FullResetFileObserver = void Function(String path);
typedef FullResetDirectoryLister =
    List<FileSystemEntity> Function(Directory directory);

abstract interface class FullResetSecureStore {
  Future<Map<String, String>> readAll();
  Future<void> deleteAll();
  Future<void> delete(String key);
}

class PlatformFullResetSecureStore implements FullResetSecureStore {
  const PlatformFullResetSecureStore();

  /// Funnels each operation through the classified wrappers in
  /// [safeSecureReadAll] / [safeSecureDeleteAll] / [safeSecureDelete] so a
  /// platform exception during reset cannot escape this layer. Reset is
  /// best-effort by contract — cipher / transient / unknown failures are
  /// swallowed at the call site (see `lib/core/reset/full_reset_service.dart`
  /// further down) which records partial-cleanup state in SharedPref.
  @override
  Future<Map<String, String>> readAll() async {
    final result = await safeSecureReadAll();
    return result.entries;
  }

  @override
  Future<void> deleteAll() async {
    await safeSecureDeleteAll();
  }

  @override
  Future<void> delete(String key) async {
    await safeSecureDelete(key);
  }
}

class FreshInstallResidueReport {
  const FreshInstallResidueReport({
    required this.preferenceKeys,
    required this.files,
    required this.secureStoreKeys,
    required this.nativeKeysPresent,
  });

  final Set<String> preferenceKeys;
  final List<String> files;
  final Set<String> secureStoreKeys;
  final bool nativeKeysPresent;

  bool get hasResidue =>
      preferenceKeys.isNotEmpty ||
      files.isNotEmpty ||
      secureStoreKeys.isNotEmpty ||
      nativeKeysPresent;

  bool get hasAppContainerResidue =>
      preferenceKeys.isNotEmpty || files.isNotEmpty;

  bool get hasSecureResidue => secureStoreKeys.isNotEmpty || nativeKeysPresent;

  @override
  String toString() {
    return 'FreshInstallResidueReport('
        'prefs=${preferenceKeys.length}, '
        'files=${files.length}, '
        'secureStore=${secureStoreKeys.length}, '
        'nativeKeys=$nativeKeysPresent)';
  }
}

enum ResetStartupMode {
  normal,
  freshInstallRecoveryRequired,
  keychainUnreadable,
}

class ResetStartupDecision {
  const ResetStartupDecision({
    required this.mode,
    required this.report,
    this.diagnostic,
  });

  const ResetStartupDecision.normal()
    : mode = ResetStartupMode.normal,
      report = const FreshInstallResidueReport(
        preferenceKeys: {},
        files: [],
        secureStoreKeys: {},
        nativeKeysPresent: false,
      ),
      diagnostic = null;

  /// Decision for the §6 keychain-unreadable boot branch. Carries the
  /// secure-storage diagnostic so the recovery screen can write it out via
  /// "Save diagnostic report".
  const ResetStartupDecision.keychainUnreadable({this.diagnostic})
    : mode = ResetStartupMode.keychainUnreadable,
      report = const FreshInstallResidueReport(
        preferenceKeys: {},
        files: [],
        secureStoreKeys: {},
        nativeKeysPresent: false,
      );

  final ResetStartupMode mode;
  final FreshInstallResidueReport report;

  /// Boot-time secure-storage diagnostic captured by `probeAppDatabaseStartup`.
  /// Non-null only for [ResetStartupMode.keychainUnreadable]; null otherwise.
  final SecureStorageDiagnostic? diagnostic;
}

class FullResetFailure implements Exception {
  FullResetFailure(this.failures);

  final List<String> failures;

  @override
  String toString() => 'Full reset failed: ${failures.join('; ')}';
}

enum AndroidApplicationDataClearResult { osAccepted, manualFallbackCompleted }

class FullResetService {
  FullResetService({
    FullResetSecureStore? secureStore,
    NativeResetKeys? nativeResetKeys,
    Future<Directory> Function()? appDataDirectory,
    Future<Directory> Function()? mediaCacheDirectory,
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function()? clearMediaCache,
    FullResetLog? log,
    FullResetFileObserver? fileObserver,
    FullResetDirectoryLister? directoryLister,
  }) : secureStore = secureStore ?? const PlatformFullResetSecureStore(),
       nativeResetKeys =
           nativeResetKeys ?? const MethodChannelNativeResetKeys(),
       _appDataDirectory = appDataDirectory ?? getAppDataDir,
       _mediaCacheDirectory = mediaCacheDirectory ?? _defaultMediaCacheDir,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _clearMediaCache = clearMediaCache ?? _deleteDefaultMediaCache,
       _log = log ?? _noopLog,
       _fileObserver = fileObserver ?? _noopFileObserver,
       _directoryLister =
           directoryLister ?? ((directory) => directory.listSync());

  final FullResetSecureStore secureStore;
  final NativeResetKeys nativeResetKeys;
  final Future<Directory> Function() _appDataDirectory;
  final Future<Directory> Function() _mediaCacheDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function() _clearMediaCache;
  final FullResetLog _log;
  final FullResetFileObserver _fileObserver;
  final FullResetDirectoryLister _directoryLister;

  Future<FreshInstallResidueReport> inspectFreshInstallResidue({
    bool avoidFlutterSecureStorage = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final preferenceKeys = prefs.getKeys().where((key) {
      return key != kFreshInstallSentinelKey &&
          key != kFullResetRestartRequiredKey &&
          key != kFullResetCompletedAtKey &&
          key != kFreshInstallAnomalyKey &&
          key != kNativeResetKeyClearPendingKey &&
          key != kMediaCacheClearPendingKey;
    }).toSet();

    final files = <String>[];
    for (final path in await _appOwnedFilePaths()) {
      if (await File(path).exists()) files.add(path);
    }
    try {
      final mediaDir = await _mediaCacheDirectory();
      if (await _directoryHasEntries(mediaDir)) files.add(mediaDir.path);
    } catch (e) {
      _log('Media-cache residue inspection failed; forcing wipe: $e');
      files.add('<media cache inspection failed>');
    }

    Set<String> secureStoreKeys = const {};
    if (!avoidFlutterSecureStorage) {
      try {
        secureStoreKeys = (await secureStore.readAll()).keys.toSet();
      } catch (e) {
        _log('Secure-store residue inspection failed; forcing recovery: $e');
        secureStoreKeys = const {'<readAll failed>'};
      }
    }

    bool nativeKeysPresent;
    try {
      nativeKeysPresent = await nativeResetKeys.hasKnownNativeKeys();
    } catch (e) {
      _log('Native-key residue inspection failed; forcing recovery: $e');
      nativeKeysPresent = true;
    }

    return FreshInstallResidueReport(
      preferenceKeys: preferenceKeys,
      files: files,
      secureStoreKeys: secureStoreKeys,
      nativeKeysPresent: nativeKeysPresent,
    );
  }

  Future<ResetStartupDecision> runFreshInstallResidueGuard() async {
    try {
      return await _runFreshInstallResidueGuard();
    } catch (e) {
      _log('Fresh install residue guard failed; entering recovery: $e');
      return const ResetStartupDecision(
        mode: ResetStartupMode.freshInstallRecoveryRequired,
        report: FreshInstallResidueReport(
          preferenceKeys: {},
          files: ['<fresh install guard failed>'],
          secureStoreKeys: {},
          nativeKeysPresent: true,
        ),
      );
    }
  }

  Future<ResetStartupDecision> _runFreshInstallResidueGuard() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kMediaCacheClearPendingKey) == true) {
      await _retryPendingMediaCacheClear(prefs);
    }
    if (prefs.getBool(kNativeResetKeyClearPendingKey) == true) {
      await _retryPendingNativeKeyClear(prefs);
    }

    if (prefs.getBool(kFullResetRestartRequiredKey) == true) {
      await prefs.remove(kFullResetRestartRequiredKey);
      await prefs.remove(kFullResetCompletedAtKey);
      return const ResetStartupDecision.normal();
    }

    if (prefs.getBool(kFreshInstallSentinelKey) == true) {
      return const ResetStartupDecision.normal();
    }

    final report = await inspectFreshInstallResidue(
      avoidFlutterSecureStorage: true,
    );

    if (report.hasAppContainerResidue) {
      _log('Fresh install marker missing while app data exists: $report');
      await prefs.setBool(kFreshInstallAnomalyKey, true);
      return ResetStartupDecision(
        mode: ResetStartupMode.freshInstallRecoveryRequired,
        report: report,
      );
    }

    _log(
      'Fresh install marker missing with no app files; clearing secure residue',
    );
    await _clearFreshInstallSecureResidue(prefs);

    final refreshedPrefs = await SharedPreferences.getInstance();
    await refreshedPrefs.setBool(kFreshInstallSentinelKey, true);
    await refreshedPrefs.remove(kFreshInstallAnomalyKey);
    return ResetStartupDecision(mode: ResetStartupMode.normal, report: report);
  }

  Future<void> restoreInstallSentinelAfterAnomaly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kFreshInstallSentinelKey, true);
    await prefs.remove(kFreshInstallAnomalyKey);
  }

  Future<bool> canContinueWithExistingDataAfterAnomaly() async {
    try {
      final dir = await _appDataDirectory();
      final dbPath = p.join(dir.path, 'prism.db');
      final syncDbPath = p.join(dir.path, AppConstants.syncDatabaseName);
      final appDbExists = await File(dbPath).exists();

      final appDbResidue = _databaseResiduePaths(dbPath);
      final appDbFilesExist = _anyFileExistsSync(appDbResidue);
      if (appDbFilesExist) {
        if (!appDbExists) {
          _log(
            'Cannot continue after reset anomaly: app database sidecar files '
            'remain without the main database',
          );
          return false;
        }
        final key = await readDatabaseKeyHex();
        if (key == null) {
          _log('Cannot continue after reset anomaly: database key is missing');
          return false;
        }
        final openable = tryOpenEncryptedDb(dbPath, key);
        if (!openable) {
          _log(
            'Cannot continue after reset anomaly: database does not open with '
            'the stored key',
          );
          return false;
        }
      }

      final syncDbResidue = _databaseResiduePaths(syncDbPath);
      final syncDbFilesExist = _anyFileExistsSync(syncDbResidue);
      if (syncDbFilesExist) {
        if (!appDbExists) {
          _log(
            'Cannot continue after reset anomaly: sync database remains '
            'without the main app database',
          );
          return false;
        }
        if (!await File(syncDbPath).exists()) {
          _log(
            'Cannot continue after reset anomaly: sync database sidecar files '
            'remain without the main sync database',
          );
          return false;
        }
        final syncKey = await readSyncDatabaseKeyHex();
        if (syncKey == null) {
          _log(
            'Cannot continue after reset anomaly: sync database key is missing',
          );
          return false;
        }
        final syncOpenable = tryOpenEncryptedDb(syncDbPath, syncKey);
        if (!syncOpenable) {
          _log(
            'Cannot continue after reset anomaly: sync database does not open '
            'with the stored key',
          );
          return false;
        }
      }

      return true;
    } catch (e) {
      _log('Cannot continue after reset anomaly: database probe failed: $e');
      return false;
    }
  }

  Future<bool> isRestartRequired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kFullResetRestartRequiredKey) == true;
  }

  Future<AndroidApplicationDataClearResult> startAndroidClearApplicationData({
    AppDatabase? openDatabase,
  }) async {
    Object? clearFailure;
    try {
      final accepted = await nativeResetKeys.clearApplicationUserData();
      if (accepted) return AndroidApplicationDataClearResult.osAccepted;
      clearFailure = 'Android clearApplicationUserData returned false';
    } catch (e) {
      clearFailure = e;
    }

    _log(
      'Android OS app-data clear did not complete; falling back to local '
      'wipe before clearing native keys: $clearFailure',
    );
    await wipeLocalData(openDatabase: openDatabase);
    return AndroidApplicationDataClearResult.manualFallbackCompleted;
  }

  Future<void> wipeLocalData({
    AppDatabase? openDatabase,
    bool requireRestart = true,
  }) async {
    final failures = <String>[];
    Future<bool> attempt(String label, Future<void> Function() action) async {
      try {
        await action();
        return true;
      } catch (e) {
        failures.add('$label: $e');
        _log('$label failed during full reset: $e');
        return false;
      }
    }

    if (openDatabase != null) {
      await attempt('app database close', openDatabase.close);
    }

    final recoverySafePrefs = _snapshotRecoverySafePreferences(
      await SharedPreferences.getInstance(),
    );

    // Clear cached UI/provider prefs before deleting app files so a crash
    // midway through file deletion cannot relaunch with stale preference state.
    await attempt('SharedPreferences clear', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });
    await attempt(
      'SharedPreferences recovery-safe restore',
      () => _restoreRecoverySafePreferences(recoverySafePrefs),
    );

    var databaseFileDeleteFailed = false;
    List<String> appOwnedPaths;
    try {
      appOwnedPaths = await _appOwnedFilePaths(failures: failures);
    } catch (e) {
      failures.add('app file discovery: $e');
      _log('App file discovery failed during full reset: $e');
      appOwnedPaths = const [];
      databaseFileDeleteFailed = true;
    }
    for (final path in appOwnedPaths) {
      final ok = await attempt(
        'app file delete $path',
        () => _deleteFileIfExists(path),
      );
      if (!ok && _isDatabaseFilePath(path)) {
        databaseFileDeleteFailed = true;
      }
    }
    final remainingDbFile = appOwnedPaths
        .where(_isDatabaseFilePath)
        .any((path) => File(path).existsSync());
    databaseFileDeleteFailed = databaseFileDeleteFailed || remainingDbFile;

    await _clearMediaCacheBestEffort();
    if (databaseFileDeleteFailed) {
      failures.add('secure state clear skipped: database files remain on disk');
      _log('Skipping secure state clear because database files remain on disk');
    } else {
      await attempt(
        'database encryption state clear',
        clearDatabaseEncryptionState,
      );
      await attempt('secure store clear', secureStore.deleteAll);
      try {
        await nativeResetKeys.deleteKnownKeys();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(kNativeResetKeyClearPendingKey);
      } catch (e) {
        _log(
          'Native key clear failed during full reset; will retry on startup: $e',
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kNativeResetKeyClearPendingKey, true);
      }
    }

    if (failures.isEmpty) {
      await attempt('SharedPreferences reset marker write', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kFreshInstallSentinelKey, true);
        if (requireRestart) {
          await prefs.setBool(kFullResetRestartRequiredKey, true);
          await prefs.setString(
            kFullResetCompletedAtKey,
            DateTime.now().toUtc().toIso8601String(),
          );
        }
      });
    }

    if (failures.isNotEmpty) {
      await _restoreRecoverySafePreferences(recoverySafePrefs);
      throw FullResetFailure(failures);
    }
  }

  Future<void> _clearFreshInstallSecureResidue(SharedPreferences prefs) async {
    await secureStore.deleteAll();
    await clearNativeKeysBestEffort(
      prefs: prefs,
      reason: 'during fresh install secure-residue clear',
    );
  }

  Future<void> clearNativeKeysBestEffort({
    SharedPreferences? prefs,
    String reason = 'during full reset',
  }) async {
    final localPrefs = prefs ?? await SharedPreferences.getInstance();
    try {
      await nativeResetKeys.deleteKnownKeys();
      await localPrefs.remove(kNativeResetKeyClearPendingKey);
    } catch (e) {
      _log('Native key clear failed $reason; will retry on startup: $e');
      await localPrefs.setBool(kNativeResetKeyClearPendingKey, true);
    }
  }

  Future<void> _retryPendingNativeKeyClear(SharedPreferences prefs) async {
    try {
      await nativeResetKeys.deleteKnownKeys();
      await prefs.remove(kNativeResetKeyClearPendingKey);
    } catch (e) {
      _log('Pending native-key cleanup retry failed (non-fatal): $e');
    }
  }

  Future<void> _clearMediaCacheBestEffort() async {
    try {
      await _clearMediaCache();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kMediaCacheClearPendingKey);
    } catch (e) {
      _log(
        'Media cache clear failed during full reset; will retry on startup: $e',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kMediaCacheClearPendingKey, true);
    }
  }

  Future<void> _retryPendingMediaCacheClear(SharedPreferences prefs) async {
    try {
      await _clearMediaCache();
      await prefs.remove(kMediaCacheClearPendingKey);
    } catch (e) {
      _log('Pending media-cache cleanup retry failed (non-fatal): $e');
    }
  }

  Map<String, Object> _snapshotRecoverySafePreferences(
    SharedPreferences prefs,
  ) {
    final values = <String, Object>{};
    for (final key in prefs.getKeys()) {
      if (key == 'prism.pref.screen_privacy_enabled' ||
          key.startsWith('prism.cache.')) {
        final value = prefs.get(key);
        if (value is Object) values[key] = value;
      }
    }
    return values;
  }

  Future<void> _restoreRecoverySafePreferences(
    Map<String, Object> values,
  ) async {
    if (values.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      switch (entry.value) {
        case final bool value:
          await prefs.setBool(entry.key, value);
        case final int value:
          await prefs.setInt(entry.key, value);
        case final double value:
          await prefs.setDouble(entry.key, value);
        case final String value:
          await prefs.setString(entry.key, value);
        case final List<String> value:
          await prefs.setStringList(entry.key, value);
      }
    }
  }

  Future<List<String>> _appOwnedFilePaths({List<String>? failures}) async {
    final dir = await _appDataDirectory();
    final appDbPath = p.join(dir.path, 'prism.db');
    final syncDbPath = p.join(dir.path, AppConstants.syncDatabaseName);
    final paths = [
      for (final base in [appDbPath, syncDbPath])
        for (final suffix in ['', '-wal', '-shm']) '$base$suffix',
      p.join(dir.path, 'crypto_boot_log.json'),
      p.join(dir.path, 'fronting_migration_breadcrumbs.json'),
    ];

    try {
      final tempDir = await _temporaryDirectory();
      paths.add(p.join(tempDir.path, 'shared_image.png'));
      if (await tempDir.exists()) {
        for (final entity in _directoryLister(tempDir)) {
          if (entity is File && p.basename(entity.path).startsWith('voice_')) {
            paths.add(entity.path);
          }
        }
      }
    } catch (e) {
      final message = 'temporary file discovery: $e';
      failures?.add(message);
      _log('Temporary file discovery failed during full reset: $e');
    }

    return paths;
  }

  bool _isDatabaseFilePath(String path) {
    final name = p.basename(path);
    return name == 'prism.db' ||
        name.startsWith('prism.db-') ||
        name == AppConstants.syncDatabaseName ||
        name.startsWith('${AppConstants.syncDatabaseName}-');
  }

  List<String> _databaseResiduePaths(String basePath) {
    return [basePath, '$basePath-wal', '$basePath-shm'];
  }

  bool _anyFileExistsSync(Iterable<String> paths) {
    return paths.any((path) => File(path).existsSync());
  }

  Future<bool> _directoryHasEntries(Directory directory) async {
    if (!await directory.exists()) return false;
    return _directoryLister(directory).isNotEmpty;
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    _fileObserver(path);
    await file.delete();
    if (await file.exists()) {
      throw FileSystemException('file still exists after delete', path);
    }
  }

  static Future<void> _deleteDefaultMediaCache() async {
    final mediaDir = await _defaultMediaCacheDir();
    if (await mediaDir.exists()) {
      await mediaDir.delete(recursive: true);
    }
  }

  static Future<Directory> _defaultMediaCacheDir() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(p.join(supportDir.path, 'prism_media'));
  }
}

void _noopLog(String message) {}

void _noopFileObserver(String path) {}

Future<ResetStartupDecision> runFreshInstallResidueGuard({
  FullResetService? service,
}) {
  return (service ?? FullResetService()).runFreshInstallResidueGuard();
}
