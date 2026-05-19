import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/crypto_boot_log.dart';
import 'package:prism_plurality/core/services/keychain_degraded_state.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_pairing_phase.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Diagnostic screen that lists every `prism_sync.*` keychain entry —
/// present/missing + length only, never the value. Goal: when a user
/// reports intermittent PIN/SecretKey re-prompts, a screenshot of this
/// screen pinpoints which key the OS is failing to persist.
///
/// Also surfaces the live engine state (handle present, unlocked) and
/// the sync health classification so the snapshot is self-contained.
class CryptoStorageDebugScreen extends ConsumerStatefulWidget {
  const CryptoStorageDebugScreen({super.key});

  @override
  ConsumerState<CryptoStorageDebugScreen> createState() =>
      _CryptoStorageDebugScreenState();
}

class _CryptoStorageDebugScreenState
    extends ConsumerState<CryptoStorageDebugScreen> {
  Future<_SnapshotData>? _future;
  Future<List<CryptoBootSnapshot>>? _historyFuture;
  bool _faultBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _loadSnapshot();
    _historyFuture = CryptoBootLog.instance.readAll();
  }

  Future<_SnapshotData> _loadSnapshot() async {
    // Debug-screen readAll — go through the classified wrapper so a cipher
    // failure on the top-level readAll still produces a populated entries
    // list via the slot probe, and the debug screen reflects "missing"
    // rather than crashing. See `docs/0.9.2-secure-storage-remediation.md` §2.
    final readAll = await safeSecureReadAll();
    final all = readAll.entries;
    final entries = <_KeyStatus>[];

    final scanned = <String>{};
    for (final fullKey in all.keys) {
      if (!fullKey.startsWith('prism_sync.')) continue;
      final bare = fullKey.substring('prism_sync.'.length);
      scanned.add(bare);
      entries.add(
        _KeyStatus(
          bareKey: bare,
          present: true,
          base64Length: all[fullKey]?.length ?? 0,
          decodedLength: _safeDecodedLength(all[fullKey]),
        ),
      );
    }

    // Add expected-but-missing rows so a missing key is visible at a
    // glance instead of just being absent from the list.
    for (final expected in _expectedKeys) {
      if (scanned.contains(expected)) continue;
      entries.add(_KeyStatus(bareKey: expected, present: false));
    }

    entries.sort((a, b) => a.bareKey.compareTo(b.bareKey));

    final handle = ref.read(prismSyncHandleProvider).value;
    bool? unlocked;
    if (handle != null) {
      try {
        unlocked = await ffi.isUnlocked(handle: handle);
      } catch (_) {
        unlocked = null;
      }
    }

    final health = ref.read(syncHealthProvider);

    Map<String, dynamic>? platformDiagnostics;
    try {
      platformDiagnostics = await const DeviceBoundRuntimeDekStore()
          .getDiagnostics();
    } catch (_) {
      platformDiagnostics = null;
    }

    return _SnapshotData(
      entries: entries,
      handlePresent: handle != null,
      unlocked: unlocked,
      health: health,
      capturedAt: DateTime.now(),
      lastUnwrapFailure: RuntimeDekUnwrapFailureRegistry.last,
      platformDiagnostics: platformDiagnostics,
    );
  }

  int? _safeDecodedLength(String? base64Value) {
    if (base64Value == null || base64Value.isEmpty) return null;
    try {
      return base64Decode(base64Value).length;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadSnapshot();
      _historyFuture = CryptoBootLog.instance.readAll();
    });
    await _future;
    await _historyFuture;
  }

  Future<void> _captureNow() async {
    final health = ref.read(syncHealthProvider);
    final handle = ref.read(prismSyncHandleProvider).value;
    bool? unlocked;
    if (handle != null) {
      try {
        unlocked = await ffi.isUnlocked(handle: handle);
      } catch (_) {
        unlocked = null;
      }
    }
    final snapshot = await CryptoBootLog.instance.capture(
      syncHealth: health.name,
      handlePresent: handle != null,
      engineUnlocked: unlocked,
      trigger: 'manual',
    );
    await CryptoBootLog.instance.append(snapshot);
    if (!mounted) return;
    setState(() {
      _historyFuture = CryptoBootLog.instance.readAll();
    });
    PrismToast.show(context, message: 'Snapshot captured');
  }

  Future<void> _clearHistory() async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Clear boot log?',
      message:
          'Removes all persisted crypto-storage snapshots. The current '
          'state at the top of this screen is unaffected.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (confirmed != true) return;
    await CryptoBootLog.instance.clear();
    if (!mounted) return;
    setState(() {
      _historyFuture = CryptoBootLog.instance.readAll();
    });
    PrismToast.show(context, message: 'Boot log cleared');
  }

  Future<void> _copyDiagnostic(_SnapshotData snapshot) async {
    final history = await CryptoBootLog.instance.readAll();
    const jsonIndent = JsonEncoder.withIndent('  ');
    final buf = StringBuffer()
      ..writeln('Prism crypto storage diagnostic')
      ..writeln('Captured: ${snapshot.capturedAt.toIso8601String()}')
      ..writeln('Handle present: ${snapshot.handlePresent}')
      ..writeln('Engine unlocked: ${snapshot.unlocked ?? 'unknown'}')
      ..writeln('Sync health: ${snapshot.health.name}');

    if (snapshot.lastUnwrapFailure != null) {
      final f = snapshot.lastUnwrapFailure!;
      buf
        ..writeln()
        ..writeln('Last unwrap failure:')
        ..writeln('  classification: ${f.classification.name}')
        ..writeln('  attempts: ${f.attempts}')
        ..writeln('  cache_preserved: ${f.cachePreserved}')
        ..writeln('  error_code: ${f.errorCode ?? '(none)'}')
        ..writeln('  error_message: ${f.errorMessage ?? '(none)'}')
        ..writeln('  timestamp: ${f.timestamp.toIso8601String()}');
    }

    if (snapshot.platformDiagnostics != null) {
      buf
        ..writeln()
        ..writeln('Platform diagnostics:')
        ..writeln(jsonIndent.convert(snapshot.platformDiagnostics));
    }

    buf
      ..writeln()
      ..writeln('Keychain entries (prism_sync.*) — current:');
    for (final e in snapshot.entries) {
      if (e.present) {
        buf.writeln(
          '  ✓ ${e.bareKey}'
          '  base64Len=${e.base64Length}'
          '  decodedLen=${e.decodedLength ?? '?'}',
        );
      } else {
        buf.writeln('  ✗ ${e.bareKey}  MISSING');
      }
    }

    if (history.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(
          'Boot log history (${history.length} entries, '
          'oldest first):',
        );
      for (final s in history) {
        buf
          ..writeln()
          ..writeln(
            '  ${s.timestamp.toIso8601String()}  '
            'trigger=${s.trigger}  '
            'health=${s.syncHealth}  '
            'unlocked=${s.engineUnlocked ?? 'unknown'}  '
            'v=${s.appVersion}  '
            'platform=${s.platform}',
          );
        if (s.unwrapFailure != null) {
          final f = s.unwrapFailure!;
          buf.writeln(
            '    unwrap_failure: ${f.classification.name}  '
            'code=${f.errorCode ?? '(none)'}  '
            'attempts=${f.attempts}  '
            'preserved=${f.cachePreserved}',
          );
          if (f.errorMessage != null) {
            buf.writeln('    unwrap_message: ${f.errorMessage}');
          }
        }
        if (s.platformDiagnostics != null) {
          buf.writeln(
            '    platform_diagnostics: '
            '${jsonIndent.convert(s.platformDiagnostics)}',
          );
        }
        for (final e in s.keys) {
          buf.writeln(
            '    ✓ ${e.bareKey}  '
            'len=${e.decodedLength ?? '?'}',
          );
        }
      }
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    PrismToast.show(context, message: 'Diagnostic copied to clipboard');
  }

  Future<void> _runFaultAction({
    required String title,
    required String message,
    required String confirmLabel,
    required String successMessage,
    required Future<void> Function() action,
    bool destructive = true,
    bool refreshAfter = true,
    bool invalidateProviders = false,
  }) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      icon: destructive
          ? AppIcons.warningAmberRounded
          : AppIcons.bugReportOutlined,
    );
    if (confirmed != true) return;

    setState(() => _faultBusy = true);
    try {
      await action();
      if (invalidateProviders) {
        _invalidateCryptoProviders();
      }
      if (refreshAfter) {
        await _refresh();
      } else if (mounted) {
        setState(() {});
      }
      if (!mounted) return;
      PrismToast.success(context, message: successMessage);
    } catch (e) {
      if (!mounted) return;
      PrismToast.error(context, message: 'Fault action failed: $e');
    } finally {
      if (mounted) setState(() => _faultBusy = false);
    }
  }

  void _invalidateCryptoProviders() {
    ref.invalidate(prismSyncHandleProvider);
    ref.invalidate(syncHealthProvider);
  }

  Future<String> _readRequiredSlot(String key) async {
    final result = await safeSecureRead(key);
    if (!result.ok) {
      throw StateError(
        'read failed for $key '
        '(failure=${result.failure?.name}, code=${result.code})',
      );
    }
    final value = result.value;
    if (value == null || value.isEmpty) {
      throw StateError('$key is missing');
    }
    return value;
  }

  Future<String?> _readOptionalSlot(String key) async {
    final result = await safeSecureRead(key);
    if (!result.ok) {
      throw StateError(
        'read failed for $key '
        '(failure=${result.failure?.name}, code=${result.code})',
      );
    }
    final value = result.value;
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _writeSlot(String key, String value) async {
    final result = await safeSecureWrite(key, value);
    if (!result.ok) {
      throw StateError(
        'write failed for $key '
        '(failure=${result.failure?.name}, code=${result.code})',
      );
    }
  }

  String _wrongHexDifferentFrom(String? current, int byte) {
    final first = byte.clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final candidate = first * 32;
    if (candidate != current) return candidate;
    final second = ((byte + 1) & 0xff).toRadixString(16).padLeft(2, '0');
    return second * 32;
  }

  Future<void> _seedAppRecoveryAndCorruptPrimary() async {
    final appKey = await _readRequiredSlot(kDatabaseKeyStorageKey);
    await _writeSlot('${kSyncDatabaseKeyStorageKey}_staging', appKey);
    await _writeSlot(
      kDatabaseKeyStorageKey,
      _wrongHexDifferentFrom(appKey, 0x01),
    );
  }

  Future<void> _corruptAllAppDbKeyCandidates() async {
    await _writeSlot(
      kDatabaseKeyStorageKey,
      _wrongHexDifferentFrom(null, 0x11),
    );
    await _writeSlot(
      '${kDatabaseKeyStorageKey}_staging',
      _wrongHexDifferentFrom(null, 0x22),
    );
    await _writeSlot(
      kSyncDatabaseKeyStorageKey,
      _wrongHexDifferentFrom(null, 0x33),
    );
    await _writeSlot(
      '${kSyncDatabaseKeyStorageKey}_staging',
      _wrongHexDifferentFrom(null, 0x44),
    );
  }

  Future<void> _seedSyncStagingAndCorruptPrimary() async {
    final syncKey = await _resolveVerifiedSyncDbKeyForFaultInjection();
    await _writeSlot('${kSyncDatabaseKeyStorageKey}_staging', syncKey);
    await _writeSlot(
      kSyncDatabaseKeyStorageKey,
      _wrongHexDifferentFrom(syncKey, 0x55),
    );
  }

  Future<String> _resolveVerifiedSyncDbKeyForFaultInjection() async {
    final dir = await getAppDataDir();
    final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
    if (!File(dbPath).existsSync()) {
      throw StateError('${AppConstants.syncDatabaseName} is missing');
    }

    String? bootSyncKey;
    try {
      bootSyncKey = ref.read(syncDatabaseStartupProvider).keyInMemory;
    } catch (_) {
      bootSyncKey = null;
    }

    String? verifiedAppKey;
    try {
      verifiedAppKey = ref.read(verifiedStartupKeyProvider);
    } catch (_) {
      verifiedAppKey = null;
    }

    final candidates = <String?>[
      await _readOptionalSlot(kSyncDatabaseKeyStorageKey),
      await _readOptionalSlot('${kSyncDatabaseKeyStorageKey}_staging'),
      bootSyncKey,
      verifiedAppKey,
      await _readOptionalSlot(kDatabaseKeyStorageKey),
      await _readOptionalSlot('${kDatabaseKeyStorageKey}_staging'),
    ];
    final verified = debugFirstVerifiedHexKeyForDatabase(
      dbPath: dbPath,
      candidates: candidates,
    );
    if (verified == null) {
      throw StateError(
        'No available keychain/startup candidate opens '
        '${AppConstants.syncDatabaseName}',
      );
    }
    return verified;
  }

  Future<void> _corruptSyncDbKeySlots() async {
    await _writeSlot(
      kSyncDatabaseKeyStorageKey,
      _wrongHexDifferentFrom(null, 0x66),
    );
    await _writeSlot(
      '${kSyncDatabaseKeyStorageKey}_staging',
      _wrongHexDifferentFrom(null, 0x77),
    );
  }

  Future<void> _markSyncWipeInProgress() async {
    await KeychainDegradedStateService().updateSlot(
      'syncKey',
      SlotState.unreadable,
    );
    await SyncPairingPhaseService().write(SyncPairingPhase.wipeInProgress);
  }

  Future<void> _runSyncRepairWipe() async {
    await wipeSyncDatabaseForRepair();
  }

  Future<void> _deleteSyncDatabaseFiles() async {
    final dir = await getAppDataDir();
    final dbPath = p.join(dir.path, AppConstants.syncDatabaseName);
    for (final suffix in const <String>['', '-shm', '-wal', '-journal']) {
      final file = File('$dbPath$suffix');
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  void _queueFault(
    SecureStorageFaultOperation operation, {
    String? key,
    SecureStorageFailure failure = SecureStorageFailure.cipher,
  }) {
    SecureStorageFaultInjector.queueNext(
      operation: operation,
      key: key,
      failure: failure,
    );
    setState(() {});
    PrismToast.success(context, message: 'Queued ${operation.name} failure');
  }

  @override
  Widget build(BuildContext context) {
    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Crypto storage',
        subtitle: 'Keychain inventory + engine state',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.refresh,
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: FutureBuilder<_SnapshotData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: PrismLoadingState(),
            );
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to read keychain: ${snap.error}'),
            );
          }
          final data = snap.data!;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              NavBarInset.of(context) + 16,
            ),
            children: [
              _EngineStateCard(snapshot: data),
              const SizedBox(height: 16),
              _KeychainCard(entries: data.entries),
              const SizedBox(height: 16),
              _BootLogCard(
                historyFuture: _historyFuture,
                onCaptureNow: _captureNow,
                onClear: _clearHistory,
              ),
              if (!kReleaseMode) ...[
                const SizedBox(height: 16),
                _FaultInjectionCard(
                  busy: _faultBusy,
                  pendingFaults: SecureStorageFaultInjector.pending,
                  onSeedAppRecoveryAndCorruptPrimary: () => _runFaultAction(
                    title: 'Seed app recovery path?',
                    message:
                        'Copies the current app DB key into the sync staging '
                        'slot, then replaces the app primary key with a wrong '
                        '64-character key. Restart the app to verify fallback '
                        'startup and repair write-back.',
                    confirmLabel: 'Corrupt key',
                    successMessage: 'App primary key corrupted',
                    action: _seedAppRecoveryAndCorruptPrimary,
                  ),
                  onCorruptAllAppDbCandidates: () => _runFaultAction(
                    title: 'Make app DB unrecoverable?',
                    message:
                        'Replaces every app DB recovery key candidate with a '
                        'wrong 64-character key. Restart should enter the '
                        'keychain-unreadable recovery screen.',
                    confirmLabel: 'Corrupt all',
                    successMessage: 'All app DB key candidates corrupted',
                    action: _corruptAllAppDbKeyCandidates,
                  ),
                  onSeedSyncStagingAndCorruptPrimary: () => _runFaultAction(
                    title: 'Seed sync staging recovery?',
                    message:
                        'Copies the current sync DB key into sync staging, then '
                        'replaces the sync primary key with a wrong key. Restart '
                        'should promote staging.',
                    confirmLabel: 'Corrupt key',
                    successMessage: 'Sync primary key corrupted',
                    action: _seedSyncStagingAndCorruptPrimary,
                  ),
                  onCorruptSyncDbKeySlots: () => _runFaultAction(
                    title: 'Corrupt sync DB key slots?',
                    message:
                        'Replaces sync primary and staging DB-key slots with '
                        'wrong keys. App data should still open; sync should '
                        'recover via app-primary only on older converged-key '
                        'installs, otherwise degrade.',
                    confirmLabel: 'Corrupt sync',
                    successMessage: 'Sync DB key slots corrupted',
                    action: _corruptSyncDbKeySlots,
                  ),
                  onMarkSyncWipeInProgress: () => _runFaultAction(
                    title: 'Mark sync wipe in progress?',
                    message:
                        'Sets syncKey unreadable and persists the pairing phase '
                        'as wipeInProgress without deleting sync files. Use this '
                        'to test crash-resume behavior.',
                    confirmLabel: 'Mark phase',
                    successMessage: 'Sync wipeInProgress marker written',
                    action: _markSyncWipeInProgress,
                  ),
                  onRunSyncRepairWipe: () => _runFaultAction(
                    title: 'Run sync repair wipe?',
                    message:
                        'Deletes prism_sync.db sidecars and sync keychain '
                        'credentials, then moves the pairing phase to '
                        'pendingPair only if every checked delete succeeds.',
                    confirmLabel: 'Run wipe',
                    successMessage: 'Sync repair wipe completed',
                    action: _runSyncRepairWipe,
                    invalidateProviders: true,
                  ),
                  onDeleteSyncDatabaseFiles: () => _runFaultAction(
                    title: 'Delete sync database files?',
                    message:
                        'Deletes prism_sync.db and sidecar files only. Keychain '
                        'credentials are left untouched.',
                    confirmLabel: 'Delete files',
                    successMessage: 'Sync database files deleted',
                    action: _deleteSyncDatabaseFiles,
                  ),
                  onQueueAppDbReadFailure: () => _queueFault(
                    SecureStorageFaultOperation.read,
                    key: kDatabaseKeyStorageKey,
                  ),
                  onQueueReadAllFailure: () =>
                      _queueFault(SecureStorageFaultOperation.readAll),
                  onQueueSyncIdWriteFailure: () => _queueFault(
                    SecureStorageFaultOperation.write,
                    key: kSyncIdKey,
                  ),
                  onQueueSyncIdDeleteFailure: () => _queueFault(
                    SecureStorageFaultOperation.delete,
                    key: kSyncIdKey,
                  ),
                  onClearFaults: () {
                    SecureStorageFaultInjector.clear();
                    setState(() {});
                    PrismToast.success(
                      context,
                      message: 'Queued wrapper failures cleared',
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              PrismButton(
                tone: PrismButtonTone.subtle,
                onPressed: () => _copyDiagnostic(data),
                label: 'Copy diagnostic',
              ),
              const SizedBox(height: 12),
              Text(
                'Values are never shown — only presence and length. '
                'Send the copied diagnostic when reporting issues like '
                'unexpected PIN or recovery-phrase prompts. The boot log '
                'auto-captures on every cold start (capped at 50 entries).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

@visibleForTesting
String? debugFirstVerifiedHexKeyForDatabase({
  required String dbPath,
  required Iterable<String?> candidates,
}) {
  final seen = <String>{};
  for (final candidate in candidates) {
    if (!validateHexKey(candidate) || !seen.add(candidate!)) {
      continue;
    }
    if (tryOpenEncryptedDb(dbPath, candidate)) {
      return candidate;
    }
  }
  return null;
}

class _EngineStateCard extends StatelessWidget {
  const _EngineStateCard({required this.snapshot});

  final _SnapshotData snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );

    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Engine state',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          row('Handle', snapshot.handlePresent ? 'present' : 'null'),
          row(
            'Unlocked',
            snapshot.unlocked == null
                ? 'unknown'
                : (snapshot.unlocked! ? 'yes' : 'no'),
          ),
          row('Health', snapshot.health.name),

          if (snapshot.lastUnwrapFailure != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last unwrap failure',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            row(
              'Classification',
              snapshot.lastUnwrapFailure!.classification.name,
            ),
            row('Attempts', snapshot.lastUnwrapFailure!.attempts.toString()),
            row(
              'Cache preserved',
              snapshot.lastUnwrapFailure!.cachePreserved ? 'yes' : 'no',
            ),
            if (snapshot.lastUnwrapFailure!.errorCode != null)
              row('Error code', snapshot.lastUnwrapFailure!.errorCode!),
            if (snapshot.lastUnwrapFailure!.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                'Error message:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SelectableText(
                snapshot.lastUnwrapFailure!.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],

          if (snapshot.platformDiagnostics != null &&
              snapshot.platformDiagnostics!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Platform diagnostics',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              const JsonEncoder.withIndent(
                '  ',
              ).convert(snapshot.platformDiagnostics),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeychainCard extends StatelessWidget {
  const _KeychainCard({required this.entries});

  final List<_KeyStatus> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = entries.where((e) => e.present).length;
    final missing = entries.length - present;

    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keychain entries',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$present present, $missing missing/expected — '
            'prism_sync.* namespace',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(8),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final e in entries) _KeyRow(entry: e)],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.entry});

  final _KeyStatus entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.present
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            entry.present ? AppIcons.checkCircle : AppIcons.close,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.bareKey,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (entry.present)
            Text(
              '${entry.decodedLength ?? '?'} B',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              'missing',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _FaultInjectionCard extends StatelessWidget {
  const _FaultInjectionCard({
    required this.busy,
    required this.pendingFaults,
    required this.onSeedAppRecoveryAndCorruptPrimary,
    required this.onCorruptAllAppDbCandidates,
    required this.onSeedSyncStagingAndCorruptPrimary,
    required this.onCorruptSyncDbKeySlots,
    required this.onMarkSyncWipeInProgress,
    required this.onRunSyncRepairWipe,
    required this.onDeleteSyncDatabaseFiles,
    required this.onQueueAppDbReadFailure,
    required this.onQueueReadAllFailure,
    required this.onQueueSyncIdWriteFailure,
    required this.onQueueSyncIdDeleteFailure,
    required this.onClearFaults,
  });

  final bool busy;
  final List<SecureStorageInjectedFault> pendingFaults;
  final VoidCallback onSeedAppRecoveryAndCorruptPrimary;
  final VoidCallback onCorruptAllAppDbCandidates;
  final VoidCallback onSeedSyncStagingAndCorruptPrimary;
  final VoidCallback onCorruptSyncDbKeySlots;
  final VoidCallback onMarkSyncWipeInProgress;
  final VoidCallback onRunSyncRepairWipe;
  final VoidCallback onDeleteSyncDatabaseFiles;
  final VoidCallback onQueueAppDbReadFailure;
  final VoidCallback onQueueReadAllFailure;
  final VoidCallback onQueueSyncIdWriteFailure;
  final VoidCallback onQueueSyncIdDeleteFailure;
  final VoidCallback onClearFaults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.bugReportOutlined,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Fault injection',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Debug/profile builds only. These actions intentionally corrupt '
            'local secure-storage state for recovery testing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _sectionLabel(context, 'Cold-start state mutations'),
          const SizedBox(height: 8),
          _FaultButton(
            label: 'Seed app fallback + corrupt app primary',
            icon: AppIcons.key,
            busy: busy,
            onPressed: onSeedAppRecoveryAndCorruptPrimary,
          ),
          _FaultButton(
            label: 'Corrupt all app DB key candidates',
            icon: AppIcons.dangerousOutlined,
            busy: busy,
            destructive: true,
            onPressed: onCorruptAllAppDbCandidates,
          ),
          _FaultButton(
            label: 'Seed sync staging + corrupt sync primary',
            icon: AppIcons.syncProblem,
            busy: busy,
            onPressed: onSeedSyncStagingAndCorruptPrimary,
          ),
          _FaultButton(
            label: 'Corrupt sync DB key slots',
            icon: AppIcons.syncDisabled,
            busy: busy,
            destructive: true,
            onPressed: onCorruptSyncDbKeySlots,
          ),
          _FaultButton(
            label: 'Mark sync wipeInProgress',
            icon: AppIcons.pendingOutlined,
            busy: busy,
            onPressed: onMarkSyncWipeInProgress,
          ),
          _FaultButton(
            label: 'Run sync repair wipe',
            icon: AppIcons.deleteForever,
            busy: busy,
            destructive: true,
            onPressed: onRunSyncRepairWipe,
          ),
          _FaultButton(
            label: 'Delete sync DB files only',
            icon: AppIcons.deleteOutline,
            busy: busy,
            destructive: true,
            onPressed: onDeleteSyncDatabaseFiles,
          ),
          const SizedBox(height: 16),
          _sectionLabel(context, 'One-shot wrapper failures'),
          const SizedBox(height: 8),
          _FaultButton(
            label: 'Next app DB key read → cipher',
            icon: AppIcons.lockClock,
            busy: busy,
            onPressed: onQueueAppDbReadFailure,
          ),
          _FaultButton(
            label: 'Next readAll → cipher',
            icon: AppIcons.warningAmber,
            busy: busy,
            onPressed: onQueueReadAllFailure,
          ),
          _FaultButton(
            label: 'Next sync_id write → cipher',
            icon: AppIcons.keyOffRounded,
            busy: busy,
            onPressed: onQueueSyncIdWriteFailure,
          ),
          _FaultButton(
            label: 'Next sync_id delete → cipher',
            icon: AppIcons.block,
            busy: busy,
            onPressed: onQueueSyncIdDeleteFailure,
          ),
          if (pendingFaults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Queued: ${pendingFaults.map((f) => f.label).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            PrismButton(
              label: 'Clear queued failures',
              icon: AppIcons.close,
              tone: PrismButtonTone.outlined,
              density: PrismControlDensity.compact,
              expanded: true,
              onPressed: onClearFaults,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FaultButton extends StatelessWidget {
  const _FaultButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final bool destructive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PrismButton(
        label: label,
        icon: icon,
        tone: destructive
            ? PrismButtonTone.destructive
            : PrismButtonTone.subtle,
        density: PrismControlDensity.compact,
        expanded: true,
        enabled: !busy,
        onPressed: onPressed,
      ),
    );
  }
}

class _BootLogCard extends StatelessWidget {
  const _BootLogCard({
    required this.historyFuture,
    required this.onCaptureNow,
    required this.onClear,
  });

  final Future<List<CryptoBootSnapshot>>? historyFuture;
  final VoidCallback onCaptureNow;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Boot log',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(AppIcons.deleteOutline),
                tooltip: 'Clear log',
                onPressed: onClear,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Auto-captures on every cold start, plus manual snapshots. '
            'Scroll back to find the boot where a key disappeared.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<CryptoBootSnapshot>>(
            future: historyFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: PrismLoadingState(),
                );
              }
              final history = snap.data!;
              if (history.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No snapshots yet — restart the app or tap "Capture '
                    'snapshot now" below.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              // Newest first.
              final ordered = history.reversed.toList();
              return Column(
                children: [for (final s in ordered) _BootLogTile(snapshot: s)],
              );
            },
          ),
          const SizedBox(height: 8),
          PrismButton(
            tone: PrismButtonTone.subtle,
            onPressed: onCaptureNow,
            label: 'Capture snapshot now',
          ),
        ],
      ),
    );
  }
}

class _BootLogTile extends StatelessWidget {
  const _BootLogTile({required this.snapshot});

  final CryptoBootSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = _expectedKeys
        .where((k) => !snapshot.keyPresent(k))
        .toList();
    final summaryColor = missing.isEmpty
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.error;

    return PrismExpandableSection(
      title: Text(
        '${_formatTimestamp(snapshot.timestamp)}  ·  ${snapshot.syncHealth}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${snapshot.trigger}  ·  '
        '${missing.isEmpty ? "all expected keys present" : "${missing.length} expected key(s) missing"}',
        style: theme.textTheme.bodySmall?.copyWith(color: summaryColor),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('App version', snapshot.appVersion),
              _kv('Platform', snapshot.platform),
              _kv('Handle', snapshot.handlePresent ? 'present' : 'null'),
              _kv(
                'Unlocked',
                snapshot.engineUnlocked == null
                    ? 'unknown'
                    : (snapshot.engineUnlocked! ? 'yes' : 'no'),
              ),
              const SizedBox(height: 8),
              if (snapshot.unwrapFailure != null) ...[
                Text(
                  'Unwrap failure: ${snapshot.unwrapFailure!.classification.name}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    'code=${snapshot.unwrapFailure!.errorCode ?? '(none)'}  '
                    'attempts=${snapshot.unwrapFailure!.attempts}  '
                    'cache_preserved=${snapshot.unwrapFailure!.cachePreserved}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                if (snapshot.unwrapFailure!.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      'message: ${snapshot.unwrapFailure!.errorMessage}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              if (snapshot.platformDiagnostics != null &&
                  snapshot.platformDiagnostics!.isNotEmpty) ...[
                Text(
                  'Platform diagnostics:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: SelectableText(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(snapshot.platformDiagnostics),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (missing.isNotEmpty) ...[
                Text(
                  'Missing expected keys:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final k in missing)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      '✗ $k',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              Text(
                'All present keys (${snapshot.keys.length}):',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final e in snapshot.keys)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    '✓ ${e.bareKey}  (${e.decodedLength ?? '?'} B)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );

  String _formatTimestamp(DateTime ts) {
    final local = ts.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

/// Keys we expect to see for a paired, healthy device. Missing entries
/// from this list show up as red ✗ rows so a user diagnosing intermittent
/// re-prompts can spot which slot the OS is failing to persist.
///
/// Solo (never paired) devices will legitimately show many of these as
/// missing — that's expected, not a bug. The "Engine state" card up top
/// distinguishes "unpaired" from "paired but credentials lost."
const _expectedKeys = <String>[
  'sync_id',
  'relay_url',
  'device_id',
  'device_secret',
  'wrapped_dek',
  'dek_salt',
  'session_token',
  'epoch',
  'runtime_dek_wrapped_v1',
];

class _KeyStatus {
  const _KeyStatus({
    required this.bareKey,
    required this.present,
    this.base64Length = 0,
    this.decodedLength,
  });

  final String bareKey;
  final bool present;
  final int base64Length;
  final int? decodedLength;
}

class _SnapshotData {
  const _SnapshotData({
    required this.entries,
    required this.handlePresent,
    required this.unlocked,
    required this.health,
    required this.capturedAt,
    this.lastUnwrapFailure,
    this.platformDiagnostics,
  });

  final List<_KeyStatus> entries;
  final bool handlePresent;
  final bool? unlocked;
  final SyncHealthState health;
  final DateTime capturedAt;
  final RuntimeDekUnwrapFailure? lastUnwrapFailure;
  final Map<String, dynamic>? platformDiagnostics;
}
