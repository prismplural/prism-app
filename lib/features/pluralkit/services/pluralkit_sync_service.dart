import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/services/secure_storage.dart'
    as storage_config;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_bidirectional_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/shared/utils/avatar_fetcher.dart';

// ---------------------------------------------------------------------------
// Sync state
// ---------------------------------------------------------------------------

/// Immutable snapshot of the current PluralKit sync state.
class PluralKitSyncState {
  final bool isSyncing;
  final double syncProgress;
  final String syncStatus;
  final String? syncError;
  final bool isConnected;

  /// True while a connection exists but the user hasn't completed (or
  /// dismissed) the member mapping flow yet. See plan 08 — in this state,
  /// auto-push and auto-sync are gated off to prevent duplicate members.
  final bool needsMapping;
  final DateTime? lastSyncDate;
  final DateTime? lastManualSyncDate;

  /// When the current PK connection was linked. Used to scope switch push to
  /// fronting sessions that started after linking (so we don't spam PK with
  /// historical local-only sessions).
  final DateTime? linkedAt;

  const PluralKitSyncState({
    this.isSyncing = false,
    this.syncProgress = 0.0,
    this.syncStatus = '',
    this.syncError,
    this.isConnected = false,
    this.needsMapping = false,
    this.lastSyncDate,
    this.lastManualSyncDate,
    this.linkedAt,
  });

  PluralKitSyncState copyWith({
    bool? isSyncing,
    double? syncProgress,
    String? syncStatus,
    String? syncError,
    bool clearError = false,
    bool? isConnected,
    bool? needsMapping,
    DateTime? lastSyncDate,
    DateTime? lastManualSyncDate,
    DateTime? linkedAt,
    bool clearLinkedAt = false,
  }) {
    return PluralKitSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: syncProgress ?? this.syncProgress,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: clearError ? null : (syncError ?? this.syncError),
      isConnected: isConnected ?? this.isConnected,
      needsMapping: needsMapping ?? this.needsMapping,
      lastSyncDate: lastSyncDate ?? this.lastSyncDate,
      lastManualSyncDate: lastManualSyncDate ?? this.lastManualSyncDate,
      linkedAt: clearLinkedAt ? null : (linkedAt ?? this.linkedAt),
    );
  }

  /// True when the connection is fully usable — connected AND mapping
  /// complete. Callers gate auto-push / auto-sync on this.
  bool get canAutoSync => isConnected && !needsMapping;

  /// Whether a manual sync can be triggered (60-second cooldown).
  bool get canManualSync =>
      lastManualSyncDate == null ||
      DateTime.now().difference(lastManualSyncDate!) >=
          const Duration(seconds: 60);
}

// ---------------------------------------------------------------------------
// Secure storage key
// ---------------------------------------------------------------------------

const _pkTokenKey = 'prism_pluralkit_token';

// ---------------------------------------------------------------------------
// Sync service / notifier
// ---------------------------------------------------------------------------

typedef SyncStateCallback = void Function(PluralKitSyncState state);

/// Fields the user can choose to import from the PK system profile on first
/// pull. See [PluralKitSyncService.adoptSystemProfile] (plan 04).
enum PkProfileField { name, description, tag, avatar }

/// Core PluralKit synchronization logic.
///
/// Designed to be driven by a Riverpod notifier that passes a
/// [SyncStateCallback] so the notifier can update its state.
class PluralKitSyncService {
  final MemberRepository _memberRepository;
  final FrontingSessionRepository _frontingSessionRepository;
  final PluralKitSyncDao _syncDao;
  final SystemSettingsRepository? _settingsRepository;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;
  final PluralKitClient Function(String token)? _clientFactory;
  final String? _tokenOverride;
  final PkGroupsImporter? _groupsImporter;

  PluralKitSyncState _state = const PluralKitSyncState();
  SyncStateCallback? onStateChanged;

  PluralKitSyncService({
    required MemberRepository memberRepository,
    required FrontingSessionRepository frontingSessionRepository,
    required PluralKitSyncDao syncDao,
    SystemSettingsRepository? settingsRepository,
    FlutterSecureStorage? secureStorage,
    PluralKitClient Function(String token)? clientFactory,
    String? tokenOverride,
    PkGroupsImporter? groupsImporter,
  }) : _memberRepository = memberRepository,
       _frontingSessionRepository = frontingSessionRepository,
       _syncDao = syncDao,
       _settingsRepository = settingsRepository,
       _secureStorage =
           secureStorage ?? storage_config.secureStorage,
       _uuid = const Uuid(),
       _clientFactory = clientFactory,
       _tokenOverride = tokenOverride,
       _groupsImporter = groupsImporter;

  PluralKitSyncState get state => _state;

  void _emit(PluralKitSyncState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  // -- helpers --------------------------------------------------------------

  Future<String?> _getToken() => _tokenOverride != null
      ? Future.value(_tokenOverride)
      : _secureStorage.read(key: _pkTokenKey);

  PluralKitClient _makeClient(String token) =>
      _clientFactory != null
          ? _clientFactory(token)
          : PluralKitClient(token: token);

  Future<PluralKitClient?> _buildClient() async {
    final token = await _getToken();
    if (token == null) return null;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;
    return _makeClient(trimmed);
  }

  // -- public API -----------------------------------------------------------

  /// Build a PK client if connected. Exposed for use by auto-push.
  ///
  /// Returns null while the connection is in `connected_pending_map` —
  /// auto-push must not run until the mapping flow completes. Callers that
  /// explicitly need the client regardless (e.g. the mapping screen itself)
  /// should use [buildClientIgnoringMappingGate].
  Future<PluralKitClient?> buildClientIfConnected() async {
    if (!_state.canAutoSync) return null;
    return _buildClient();
  }

  /// Build a PK client even while mapping is pending — used by the mapping
  /// applier and the mapping screen itself.
  Future<PluralKitClient?> buildClientIgnoringMappingGate() async {
    if (!_state.isConnected) return null;
    return _buildClient();
  }

  /// Load persisted sync state from the database.
  Future<void> loadState() async {
    final row = await _syncDao.getSyncState();
    _emit(
      _state.copyWith(
        isConnected: row.isConnected,
        needsMapping: row.isConnected && !row.mappingAcknowledged,
        lastSyncDate: row.lastSyncDate,
        lastManualSyncDate: row.lastManualSyncDate,
        linkedAt: row.linkedAt,
      ),
    );
  }

  /// Flip the connection out of `connected_pending_map` — called after the
  /// mapping screen finishes Apply, or when the user explicitly dismisses it.
  /// Auto-push / auto-sync unlock after this is called.
  Future<void> acknowledgeMapping() async {
    await _syncDao.upsertSyncState(
      const PluralKitSyncStateCompanion(
        id: Value('pk_config'),
        mappingAcknowledged: Value(true),
      ),
    );
    _emit(_state.copyWith(needsMapping: false));
  }

  /// Store the token, test the connection, and persist connected state.
  Future<void> setToken(String token) async {
    final trimmed = token.trim();
    debugPrint('[PK_SVC] setToken: trimmed length=${trimmed.length}');
    if (trimmed.isEmpty) {
      _emit(_state.copyWith(syncError: 'Token cannot be empty'));
      return;
    }

    await _secureStorage.write(key: _pkTokenKey, value: trimmed);
    debugPrint('[PK_SVC] setToken: wrote to secureStorage');

    try {
      final client = _makeClient(trimmed);
      debugPrint('[PK_SVC] setToken: calling client.getSystem()...');
      final system = await client.getSystem();
      debugPrint(
        '[PK_SVC] setToken: getSystem ok — id=${system.id} name=${system.name}',
      );
      client.dispose();

      // Preserve existing linkedAt on re-connect with the same system (user
      // rotated their token without re-linking). For a truly fresh link we
      // stamp `now` so the scoped switch push has a stable cutoff.
      final existing = await _syncDao.getSyncState();
      final DateTime linkedAt;
      if (existing.systemId == system.id && existing.linkedAt != null) {
        linkedAt = existing.linkedAt!;
      } else {
        // Subtract 1ms so that a fronting session created in the same tick as
        // linking (startTime == now) still clears the `isAfter(linkedAt)`
        // boundary in [pushPendingSwitches]. Without this nudge, any switch
        // whose startTime equals linkedAt would be dropped forever.
        linkedAt = DateTime.now().subtract(const Duration(milliseconds: 1));
      }

      // Plan 02 R1: bump the local link epoch whenever the connected system
      // changes identity. Tombstones stamped under the prior epoch will be
      // skipped at push time on this device.
      final bumpEpoch = existing.systemId != system.id;

      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          systemId: Value(system.id),
          isConnected: const Value(true),
          // Fresh connection → user hasn't mapped yet. Gate auto-sync until
          // the mapping screen runs (or user dismisses it).
          mappingAcknowledged: const Value(false),
          linkedAt: Value(linkedAt),
        ),
      );
      if (bumpEpoch) {
        await _syncDao.bumpLinkEpoch();
      }

      _emit(_state.copyWith(
        isConnected: true,
        needsMapping: true,
        linkedAt: linkedAt,
        clearError: true,
      ));
    } on PluralKitAuthError catch (e) {
      debugPrint('[PK_SVC] setToken: PluralKitAuthError: $e');
      await _secureStorage.delete(key: _pkTokenKey);
      _emit(
        _state.copyWith(
          isConnected: false,
          syncError: 'Invalid token — please check and try again.',
        ),
      );
    } catch (e, st) {
      debugPrint('[PK_SVC] setToken: caught $e\n$st');
      await _secureStorage.delete(key: _pkTokenKey);
      _emit(
        _state.copyWith(isConnected: false, syncError: 'Connection failed: $e'),
      );
    }
  }

  /// Remove the token and reset connected state.
  ///
  /// Also truncates the PK mapping-state table and resets
  /// [PluralKitSyncState.needsMapping] so a future reconnect (potentially
  /// against a different PK system) starts with a fresh mapping flow — stale
  /// Skip/Link decisions keyed by the previous session's local member IDs
  /// would otherwise silently skip or link members the user never saw.
  Future<void> clearToken() async {
    await _secureStorage.delete(key: _pkTokenKey);
    await _syncDao.upsertSyncState(
      const PluralKitSyncStateCompanion(
        id: Value('pk_config'),
        systemId: Value(null),
        isConnected: Value(false),
        mappingAcknowledged: Value(false),
        lastSyncDate: Value(null),
        lastManualSyncDate: Value(null),
        linkedAt: Value(null),
      ),
    );
    // Plan 02 R1: bump on disconnect so tombstones made while linked become
    // stale immediately. A later reconnect will bump again (new systemId
    // path).
    await _syncDao.bumpLinkEpoch();
    // Wipe prior Skip/Link/Import decisions — they're keyed by local member
    // IDs that may not even exist in the next connected system.
    await PkMappingStateDao(_syncDao.attachedDatabase).clearAll();
    _emit(const PluralKitSyncState());
  }

  /// Test the connection without modifying stored state.
  Future<bool> testConnection() async {
    try {
      final client = await _buildClient();
      if (client == null) return false;
      await client.getSystem();
      client.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Read-only fetch: returns PK system name and members without writing
  /// anything to the local members table. Used by the mapping screen so we
  /// don't auto-create clones before the user makes mapping decisions.
  ///
  /// Unlike [importMembersOnly], this path does NOT download avatars or
  /// call [_importMembers]. Avatar downloads and row writes happen later,
  /// per-decision, via the mapping applier.
  Future<(String? systemName, List<PKMember> pkMembers)>
  fetchPkMembersWithoutImport() async {
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');

    try {
      final system = await client.getSystem();
      final pkMembers = await client.getMembers();
      return (system.name, pkMembers);
    } finally {
      client.dispose();
    }
  }

  /// Fast member-only import. Returns system name and PK members for UI.
  Future<(String? systemName, List<PKMember> pkMembers)>
  importMembersOnly() async {
    debugPrint('[PK_SVC] importMembersOnly: building client...');
    final client = await _buildClient();
    if (client == null) {
      debugPrint('[PK_SVC] importMembersOnly: _buildClient returned null '
          '(token missing from secure storage?)');
      throw StateError('Not connected');
    }

    try {
      _emit(
        _state.copyWith(
          isSyncing: true,
          syncProgress: 0.0,
          syncStatus: 'Fetching system info...',
          clearError: true,
        ),
      );

      debugPrint('[PK_SVC] importMembersOnly: calling getSystem...');
      final system = await client.getSystem();
      debugPrint('[PK_SVC] importMembersOnly: system.name=${system.name}');
      _emit(
        _state.copyWith(syncProgress: 0.3, syncStatus: 'Fetching members...'),
      );

      debugPrint('[PK_SVC] importMembersOnly: calling getMembers...');
      final pkMembers = await client.getMembers();
      debugPrint(
        '[PK_SVC] importMembersOnly: getMembers returned ${pkMembers.length} '
        '(first 3 names=${pkMembers.take(3).map((m) => m.name).toList()})',
      );
      _emit(
        _state.copyWith(
          syncProgress: 0.5,
          syncStatus: 'Importing ${pkMembers.length} members...',
        ),
      );

      debugPrint('[PK_SVC] importMembersOnly: calling _importMembers...');
      await _importMembers(client, pkMembers);
      debugPrint('[PK_SVC] importMembersOnly: _importMembers done');

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: 'Imported ${pkMembers.length} members.',
        ),
      );

      return (system.name, pkMembers);
    } catch (e, st) {
      debugPrint('[PK_SVC] importMembersOnly: caught $e\n$st');
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: 'Member import failed: $e',
        ),
      );
      rethrow;
    } finally {
      client.dispose();
    }
  }

  /// Full import: members + switches history.
  Future<void> performFullImport() async {
    if (_state.needsMapping) {
      throw StateError(
        'Mapping pending — complete the mapping flow before auto-syncing.',
      );
    }
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');

    try {
      _emit(
        _state.copyWith(
          isSyncing: true,
          syncProgress: 0.0,
          syncStatus: 'Fetching system info...',
          clearError: true,
        ),
      );

      // -- Members (0-10%) --
      await client.getSystem();
      _emit(
        _state.copyWith(syncProgress: 0.02, syncStatus: 'Fetching members...'),
      );

      final pkMembers = await client.getMembers();
      _emit(
        _state.copyWith(
          syncProgress: 0.05,
          syncStatus: 'Importing ${pkMembers.length} members...',
        ),
      );
      await _importMembers(client, pkMembers);
      _emit(_state.copyWith(syncProgress: 0.10));

      // Build PK ID -> local member ID map
      final allMembers = await _memberRepository.getAllMembers();
      final pkIdToLocalId = <String, String>{};
      for (final m in allMembers) {
        if (m.pluralkitId != null) {
          pkIdToLocalId[m.pluralkitId!] = m.id;
        }
      }

      // -- Groups (10-15%) --
      _emit(_state.copyWith(syncProgress: 0.10, syncStatus: 'Importing groups...'));
      await _importGroups(client, overwriteMetadata: true);
      _emit(_state.copyWith(syncProgress: 0.15));

      // -- Switches (15-95%) --
      _emit(
        _state.copyWith(syncProgress: 0.10, syncStatus: 'Fetching switches...'),
      );

      int totalSwitches = 0;
      int consecutiveDuplicates = 0;
      DateTime? pageBefore;
      final allSwitches = <PKSwitch>[];

      // Fetch all switch pages
      while (true) {
        final page = await client.getSwitches(before: pageBefore);
        if (page.isEmpty) break;

        allSwitches.addAll(page);
        totalSwitches += page.length;
        pageBefore = page.last.timestamp;

        _emit(
          _state.copyWith(syncStatus: 'Fetched $totalSwitches switches...'),
        );

        if (page.length < 100) break; // last page
      }

      // Process switches into fronting sessions
      _emit(
        _state.copyWith(
          syncProgress: 0.50,
          syncStatus: 'Processing $totalSwitches switches...',
        ),
      );

      // Switches come newest-first; sort oldest-first for processing
      allSwitches.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Precompute existing PK UUIDs (O(N²) → O(N)).
      final existingSessions =
          await _frontingSessionRepository.getAllSessions();
      final existingPkUuids = <String>{
        for (final s in existingSessions)
          if (s.pluralkitUuid != null) s.pluralkitUuid!,
      };

      consecutiveDuplicates = 0;
      final switchOutTimestamps = <DateTime>[];
      for (var i = 0; i < allSwitches.length; i++) {
        final sw = allSwitches[i];
        final endTime = i + 1 < allSwitches.length
            ? allSwitches[i + 1].timestamp
            : null;
        if (sw.members.isEmpty) switchOutTimestamps.add(sw.timestamp);

        final progress = 0.50 + (0.45 * (i / allSwitches.length));
        if (i % 50 == 0) {
          _emit(
            _state.copyWith(
              syncProgress: progress,
              syncStatus: 'Processing switch ${i + 1}/$totalSwitches...',
            ),
          );
        }

        final isDuplicate = await _importSwitch(
          sw,
          endTime: endTime,
          pkIdToLocalId: pkIdToLocalId,
          existingPkUuids: existingPkUuids,
        );
        if (!isDuplicate) existingPkUuids.add(sw.id);

        if (isDuplicate) {
          consecutiveDuplicates++;
          if (consecutiveDuplicates >= 100) {
            break; // early termination
          }
        } else {
          consecutiveDuplicates = 0;
        }
      }

      await _closePkSessionChainGaps(extraBoundaries: switchOutTimestamps);

      // -- Complete (95-100%) --
      final now = DateTime.now();
      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastSyncDate: Value(now),
        ),
      );

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus:
              'Imported ${pkMembers.length} members and $totalSwitches switches.',
          lastSyncDate: now,
        ),
      );
    } catch (e) {
      _emit(
        _state.copyWith(isSyncing: false, syncError: 'Full import failed: $e'),
      );
      rethrow;
    } finally {
      client.dispose();
    }
  }

  /// Import a parsed `pk;export` file. Creates/updates members, groups, and
  /// fronting sessions without hitting the PK API — the file is the complete
  /// source of truth for the snapshot.
  ///
  /// Switch sessions created this way carry `pluralkitUuid = null` because
  /// the export format doesn't include switch IDs. If the user later connects
  /// a token, [syncRecentData] will adopt the API's UUIDs onto these rows by
  /// matching on timestamp + PK member IDs.
  Future<PkFileImportResult> importFromFile(
    PkFileExport export, {
    void Function(double progress, String status)? onProgress,
  }) async {
    void progress(double p, String s) {
      onProgress?.call(p, s);
      _emit(_state.copyWith(syncProgress: p, syncStatus: s));
    }

    _emit(_state.copyWith(
      isSyncing: true,
      syncProgress: 0.0,
      syncStatus: 'Importing from file…',
      clearError: true,
    ));

    try {
      progress(0.05, 'Importing ${export.members.length} members…');
      await _importMembers(null, export.members);

      if (export.groups.isNotEmpty && _groupsImporter != null) {
        progress(0.40, 'Importing ${export.groups.length} groups…');
        final client = await _buildClient();
        if (client != null) {
          try {
            await _groupsImporter.importGroups(
              client,
              export.groups,
              overwriteMetadata: true,
            );
          } catch (e) {
            debugPrint('[PK_FILE] group import failed (non-fatal): $e');
          } finally {
            client.dispose();
          }
        } else {
          // No token wired yet — groups import needs a client right now.
          // Users who connect a token afterward will backfill groups via the
          // normal sync path.
          debugPrint(
            '[PK_FILE] skipping ${export.groups.length} groups — no token yet',
          );
        }
      }

      progress(0.60, 'Importing ${export.switches.length} switches…');
      final allMembers = await _memberRepository.getAllMembers();
      final pkIdToLocalId = <String, String>{};
      for (final m in allMembers) {
        if (m.pluralkitId != null) {
          pkIdToLocalId[m.pluralkitId!] = m.id;
        }
      }

      // Dedup against existing rows keyed by (timestamp epoch, sorted member IDs).
      final existingSessions =
          await _frontingSessionRepository.getAllSessions();
      final existingKeys = <String>{
        for (final s in existingSessions) _fileSwitchKey(s.startTime, _pkIdsOf(s)),
      };

      // Process oldest-first so sequential `endTime` assignment is correct.
      final sorted = List<PkFileSwitch>.from(export.switches)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      int created = 0;
      int skipped = 0;
      final switchOutTimestamps = <DateTime>[];
      for (var i = 0; i < sorted.length; i++) {
        final sw = sorted[i];
        if (sw.memberIds.isEmpty) {
          // Switch-out — no local representation.
          switchOutTimestamps.add(sw.timestamp);
          skipped++;
          continue;
        }
        final key = _fileSwitchKey(sw.timestamp, sw.memberIds);
        if (existingKeys.contains(key)) {
          skipped++;
          continue;
        }

        final (primaryMemberId, coFronterLocalIds) = _resolvePkMembers(
          sw.memberIds,
          pkIdToLocalId,
        );
        final endTime = i + 1 < sorted.length ? sorted[i + 1].timestamp : null;

        await _frontingSessionRepository.createSession(
          domain.FrontingSession(
            id: _uuid.v4(),
            startTime: sw.timestamp,
            endTime: endTime,
            memberId: primaryMemberId,
            coFronterIds: coFronterLocalIds,
            pluralkitUuid: null,
            pkMemberIdsJson: jsonEncode(sw.memberIds),
          ),
        );
        existingKeys.add(key);
        created++;

        if (i % 50 == 0) {
          final frac = 0.60 + (0.35 * (i / sorted.length));
          progress(frac, 'Imported $created switches…');
        }
      }

      await _closePkSessionChainGaps(extraBoundaries: switchOutTimestamps);

      // Stamp lastSyncDate so subsequent token syncs only pull deltas.
      final now = DateTime.now();
      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastSyncDate: Value(now),
        ),
      );
      _emit(_state.copyWith(
        isSyncing: false,
        syncProgress: 1.0,
        syncStatus: 'Imported ${export.members.length} members, '
            '$created switches.',
        lastSyncDate: now,
      ));

      return PkFileImportResult(
        systemName: export.system.name,
        membersImported: export.members.length,
        groupsImported: export.groups.length,
        switchesCreated: created,
        switchesSkipped: skipped,
      );
    } catch (e) {
      _emit(_state.copyWith(
        isSyncing: false,
        syncError: 'File import failed: $e',
      ));
      rethrow;
    }
  }

  /// Canonical key for file-switch dedup: ISO UTC timestamp + sorted member
  /// short IDs. Deterministic across parses of the same export.
  static String _fileSwitchKey(DateTime ts, List<String> memberIds) {
    final ids = List<String>.from(memberIds)..sort();
    return '${ts.toUtc().toIso8601String()}|${ids.join(',')}';
  }

  /// Build a lookup of file-imported sessions (those with no pluralkitUuid
  /// but with stored PK short IDs) keyed by [_fileSwitchKey]. Used to adopt
  /// API switch UUIDs onto sessions that came in via `pk;export` file import.
  static Map<String, domain.FrontingSession> _buildFileImportIndex(
    List<domain.FrontingSession> sessions,
  ) {
    final out = <String, domain.FrontingSession>{};
    for (final s in sessions) {
      if (s.pluralkitUuid != null) continue;
      final ids = _pkIdsOf(s);
      if (ids.isEmpty) continue;
      out[_fileSwitchKey(s.startTime, ids)] = s;
    }
    return out;
  }

  /// If [sw] matches a file-imported session, stamp the API UUID onto it and
  /// return true. The caller should skip [_importSwitch] in that case so we
  /// don't create a second row for the same switch.
  Future<bool> _adoptFileImportedSwitch(
    PKSwitch sw,
    Map<String, domain.FrontingSession> fileIndex,
    Set<String> existingPkUuids,
  ) async {
    final key = _fileSwitchKey(sw.timestamp, sw.members);
    final match = fileIndex.remove(key);
    if (match == null) return false;
    await _frontingSessionRepository.updateSession(
      match.copyWith(pluralkitUuid: sw.id),
    );
    existingPkUuids.add(sw.id);
    return true;
  }

  static List<String> _pkIdsOf(domain.FrontingSession s) {
    final raw = s.pkMemberIdsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [for (final e in decoded) if (e is String) e];
      }
    } catch (_) {}
    return const [];
  }

  /// Sync recent changes since last sync.
  ///
  /// When [direction] includes push, local member changes are pushed to PK
  /// and the bidirectional orchestrator is used for member sync.
  /// Returns a [PkSyncSummary] when bidirectional sync is performed, or null
  /// for legacy pull-only mode.
  Future<PkSyncSummary?> syncRecentData({
    bool isManual = false,
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) async {
    if (_state.needsMapping) {
      throw StateError(
        'Mapping pending — complete the mapping flow before auto-syncing.',
      );
    }
    if (_state.lastSyncDate == null) {
      // Never synced before — perform full import
      await performFullImport();
      if (isManual) {
        final now = DateTime.now();
        await _syncDao.upsertSyncState(
          PluralKitSyncStateCompanion(
            id: const Value('pk_config'),
            lastManualSyncDate: Value(now),
          ),
        );
        _emit(_state.copyWith(lastManualSyncDate: now));
      }
      return null;
    }

    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');

    try {
      _emit(
        _state.copyWith(
          isSyncing: true,
          syncProgress: 0.0,
          syncStatus: 'Syncing recent changes...',
          clearError: true,
        ),
      );

      // Build PK ID -> local member ID map
      final allMembers = await _memberRepository.getAllMembers();
      final pkIdToLocalId = <String, String>{};
      for (final m in allMembers) {
        if (m.pluralkitId != null) {
          pkIdToLocalId[m.pluralkitId!] = m.id;
        }
      }

      // Accumulates messages for PK-side 404s we detected during this run.
      // Surfaced via `syncError` at the end so the user sees that a linked
      // member or switch was deleted on PK (otherwise the unlink would be
      // silent — see bug S3).
      final staleLinkMessages = <String>[];

      // -- Bidirectional member sync --
      PkSyncSummary? summary;
      if (direction.pushEnabled) {
        _emit(
          _state.copyWith(
            syncProgress: 0.1,
            syncStatus: 'Syncing members...',
          ),
        );

        final pkMembers = await client.getMembers();

        // Load per-member field configs
        final row = await _syncDao.getSyncState();
        final fieldConfigs = parseFieldSyncConfig(row.fieldSyncConfig);

        // Snapshot linked-member names before the bidirectional run so we can
        // detect stale-link clears (pk_bidirectional_service clears
        // `pluralkitId` / `pluralkitUuid` on 404 but doesn't surface anything
        // to the user).
        final linkedBefore = <String, String>{
          for (final m in allMembers)
            if (m.pluralkitId != null || m.pluralkitUuid != null) m.id: m.name,
        };

        final biService = PkBidirectionalService();
        summary = await biService.syncMembers(
          localMembers: allMembers,
          pkMembers: pkMembers,
          fieldConfigs: fieldConfigs,
          direction: direction,
          lastSyncDate: _state.lastSyncDate,
          memberRepository: _memberRepository,
          client: client,
        );

        // Detect stale-link clears: any previously-linked local member that
        // no longer has `pluralkitId` AND no longer has `pluralkitUuid` was
        // unlinked by the bidirectional service's 404 branch.
        final afterMembers = await _memberRepository.getAllMembers();
        final afterById = {for (final m in afterMembers) m.id: m};
        for (final entry in linkedBefore.entries) {
          final now = afterById[entry.key];
          if (now == null) continue;
          if (now.pluralkitId == null && now.pluralkitUuid == null) {
            staleLinkMessages.add(
              "PluralKit member '${entry.value}' was removed on the "
              'server — unlinked locally. Re-link from the mapping screen '
              'to resume syncing.',
            );
          }
        }

        _emit(
          _state.copyWith(
            syncProgress: 0.3,
            syncStatus: 'Members synced. Fetching switches...',
          ),
        );
      }

      // -- Groups (membership reconcile only, see R5) --
      await _importGroups(client, overwriteMetadata: false);

      // -- Pull recent switches --
      //
      // We used to short-circuit on `sw.timestamp.isBefore(lastSyncDate)`, but
      // that permanently strands any switch missed by a prior buggy sync: once
      // lastSyncDate advances past a missed switch's timestamp, it's
      // unreachable forever. Instead we mirror [performFullImport]'s approach:
      // page newest-first and stop after a full page of already-imported
      // switches (100 consecutive duplicates). `existingPkUuids` dedup is O(1),
      // so on a 10k-switch system the steady-state cost is the same as a
      // 100-switch system — 1-2 pages per sync.
      int totalNew = 0;
      if (direction.pullEnabled) {
        debugPrint(
          '[PK_PULL] start lastSyncDate=${_state.lastSyncDate?.toIso8601String()} '
          'linkedMembers=${pkIdToLocalId.length}',
        );
        final existingSessions =
            await _frontingSessionRepository.getAllSessions();
        final existingPkUuids = <String>{
          for (final s in existingSessions)
            if (s.pluralkitUuid != null) s.pluralkitUuid!,
        };
        final fileIndex = _buildFileImportIndex(existingSessions);
        // Collect PK switch-out timestamps seen during this pull so the
        // post-pass can close prior fronters at the correct boundary (PK
        // switch-outs don't create local rows).
        final switchOutTimestamps = <DateTime>[];
        DateTime? pageBefore;
        int pageNum = 0;
        int consecutiveDuplicates = 0;
        const int earlyStopAfterDups = 100;

        outer:
        while (true) {
          final page = await client.getSwitches(before: pageBefore, limit: 100);
          pageNum++;
          debugPrint(
            '[PK_PULL] page=$pageNum fetched=${page.length} '
            'newest=${page.isEmpty ? "-" : page.first.timestamp.toIso8601String()} '
            'oldest=${page.isEmpty ? "-" : page.last.timestamp.toIso8601String()}',
          );
          if (page.isEmpty) break;

          // Sort oldest-first within this page so sequential `endTime`
          // assignment (next switch's start) is correct.
          final sorted = List<PKSwitch>.from(page)
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

          for (var i = 0; i < sorted.length; i++) {
            final sw = sorted[i];
            final endTime = i + 1 < sorted.length
                ? sorted[i + 1].timestamp
                : null;
            if (sw.members.isEmpty) {
              switchOutTimestamps.add(sw.timestamp);
            }
            if (fileIndex.isNotEmpty &&
                await _adoptFileImportedSwitch(
                  sw,
                  fileIndex,
                  existingPkUuids,
                )) {
              // Adopted onto an existing file-imported row — treat as dup so
              // the early-stop heuristic behaves correctly.
              consecutiveDuplicates++;
              if (consecutiveDuplicates >= earlyStopAfterDups) {
                debugPrint(
                  '[PK_PULL] early stop — $earlyStopAfterDups consecutive duplicates',
                );
                break outer;
              }
              continue;
            }
            final isDuplicate = await _importSwitch(
              sw,
              endTime: endTime,
              pkIdToLocalId: pkIdToLocalId,
              existingPkUuids: existingPkUuids,
            );
            if (isDuplicate) {
              consecutiveDuplicates++;
              if (consecutiveDuplicates >= earlyStopAfterDups) {
                debugPrint(
                  '[PK_PULL] early stop — $earlyStopAfterDups consecutive duplicates',
                );
                break outer;
              }
            } else {
              consecutiveDuplicates = 0;
              totalNew++;
              existingPkUuids.add(sw.id);
              debugPrint(
                '[PK_PULL] imported id=${sw.id} ts=${sw.timestamp.toIso8601String()} '
                'members=${sw.members.length}',
              );
            }
          }

          if (page.length < 100) break;
          pageBefore = page.last.timestamp;
        }
        debugPrint('[PK_PULL] done totalNew=$totalNew pages=$pageNum');
        // Repair any prior "ongoing" sessions whose chains broke because
        // the newer switch lived in a different sync cycle (or different
        // page, or was a switch-out).
        await _closePkSessionChainGaps(
          extraBoundaries: switchOutTimestamps,
        );
      } else {
        debugPrint('[PK_PULL] skipped — pullEnabled=false direction=$direction');
      }

      // Phase 4: run a pure-local re-attribution pass after any member sync
      // so newly-linked PK IDs promote headless switches in-place. Cheap
      // when nothing changed (idempotent skip).
      await reattributeSwitches();

      // Phase 4 scoped push: emit pending local sessions (post-linkedAt,
      // unpushed, with a linked primary) to PK. Replaces the old
      // auto-push-current-front block which silently created duplicates on
      // every sync (it never persisted the returned PK switch ID).
      final int switchesPushed = direction.pushEnabled
          ? await pushPendingSwitches(
              onStaleLink: staleLinkMessages.add,
            )
          : 0;

      // Plan 02: deletions. Switches-first so PK's cascade doesn't 404 every
      // switch-delete we queued after a member-delete succeeds.
      int switchesDeletedOnPk = 0;
      int membersDeletedOnPk = 0;
      if (direction.pushEnabled) {
        switchesDeletedOnPk = await _pushPendingSwitchDeletions(
          client: client,
          onStaleLink: staleLinkMessages.add,
        );
        membersDeletedOnPk = await _pushPendingMemberDeletions(
          client: client,
          onStaleLink: staleLinkMessages.add,
        );
      }

      final now = DateTime.now();
      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastSyncDate: Value(now),
          lastManualSyncDate: isManual ? Value(now) : const Value.absent(),
        ),
      );

      // Build final summary
      final finalSummary = PkSyncSummary(
        membersPulled: summary?.membersPulled ?? 0,
        membersPushed: summary?.membersPushed ?? 0,
        membersSkipped: summary?.membersSkipped ?? 0,
        switchesPulled: totalNew,
        switchesPushed: switchesPushed,
        membersDeletedOnPk: membersDeletedOnPk,
        switchesDeletedOnPk: switchesDeletedOnPk,
        staleLinkMessages: List.unmodifiable(staleLinkMessages),
      );

      final statusParts = <String>[];
      if (finalSummary.membersPushed > 0) {
        statusParts.add('Pushed ${finalSummary.membersPushed} members');
      }
      if (totalNew > 0) {
        statusParts.add('Pulled $totalNew switches');
      }
      if (finalSummary.switchesDeletedOnPk > 0) {
        statusParts.add(
          'Deleted ${finalSummary.switchesDeletedOnPk} switches on PK',
        );
      }
      if (finalSummary.membersDeletedOnPk > 0) {
        statusParts.add(
          'Deleted ${finalSummary.membersDeletedOnPk} members on PK',
        );
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: statusParts.isNotEmpty
              ? '${statusParts.join('. ')}.'
              : 'Everything is up to date.',
          // Surface stale-link events so the UI can render them. Uses
          // `syncError` (there's no dedicated warnings channel) — callers
          // read `state.syncError` to show a banner/toast.
          syncError:
              staleLinkMessages.isEmpty ? null : staleLinkMessages.join('\n'),
          clearError: staleLinkMessages.isEmpty,
          lastSyncDate: now,
          lastManualSyncDate: isManual ? now : _state.lastManualSyncDate,
        ),
      );

      return finalSummary;
    } catch (e) {
      _emit(_state.copyWith(isSyncing: false, syncError: 'Sync failed: $e'));
      rethrow;
    } finally {
      client.dispose();
    }
  }

  /// Fetch the PK system-level avatar and store it on the local settings row.
  ///
  /// Returns `true` iff an avatar was fetched AND stored. Returns `false`
  /// when PK reports no system avatar, when the helper declines the download
  /// (timeout, non-image, oversize), or when no [SystemSettingsRepository]
  /// was wired into this service.
  ///
  /// Track 04 (disclosure toggle) is the expected caller; it gates the call
  /// behind a user-facing checkbox.
  Future<bool> importSystemAvatar() async {
    if (_settingsRepository == null) return false;
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');
    try {
      final system = await client.getSystem();
      final url = system.avatarUrl;
      if (url == null || url.isEmpty) return false;
      final bytes = await fetchAvatarBytes(url);
      if (bytes == null) return false;
      await _settingsRepository.updateSystemAvatarData(bytes);
      return true;
    } finally {
      client.dispose();
    }
  }

  /// Fetch the PK system profile without writing anything. Callers show the
  /// first-pull disclosure and then invoke [adoptSystemProfile] for the
  /// subset of fields the user accepted.
  ///
  /// Returns `null` when the service is not connected (no token) — the setup
  /// screen can then skip the disclosure entirely.
  Future<PKSystem?> fetchSystemProfile() async {
    final client = await _buildClient();
    if (client == null) return null;
    try {
      return await client.getSystem();
    } finally {
      client.dispose();
    }
  }

  /// Write the user-selected subset of the PK system profile into Prism's
  /// `system_settings`. Each field write is isolated in its own try/catch so
  /// a single failure doesn't abort the rest of the adoption. Failures are
  /// surfaced via [PluralKitSyncState.syncError] but never raised — the
  /// connection itself is already established at this point.
  Future<void> adoptSystemProfile({
    required PKSystem pk,
    required Set<PkProfileField> accepted,
  }) async {
    if (_settingsRepository == null) return;
    final failures = <String>[];

    if (accepted.contains(PkProfileField.name) &&
        pk.name != null && pk.name!.isNotEmpty) {
      try {
        await _settingsRepository.updateSystemName(pk.name);
      } catch (e) {
        failures.add('name ($e)');
      }
    }
    if (accepted.contains(PkProfileField.description) &&
        pk.description != null && pk.description!.isNotEmpty) {
      try {
        await _settingsRepository.updateSystemDescription(pk.description);
      } catch (e) {
        failures.add('description ($e)');
      }
    }
    if (accepted.contains(PkProfileField.tag) &&
        pk.tag != null && pk.tag!.isNotEmpty) {
      try {
        await _settingsRepository.updateSystemTag(pk.tag);
      } catch (e) {
        failures.add('tag ($e)');
      }
    }
    if (accepted.contains(PkProfileField.avatar) &&
        pk.avatarUrl != null && pk.avatarUrl!.isNotEmpty) {
      try {
        await importSystemAvatar();
      } catch (e) {
        failures.add('avatar ($e)');
      }
    }

    if (failures.isNotEmpty) {
      _emit(_state.copyWith(
        syncError: 'Some profile fields did not import: '
            '${failures.join(', ')}',
      ));
    }
  }

  /// Phase 1 PK-groups pull.
  ///
  /// - `overwriteMetadata=false` (background `syncRecentData`): new groups are
  ///   inserted, memberships are reconciled against the authoritative PK set,
  ///   but existing row metadata (name/description/color/displayOrder) is NOT
  ///   overwritten. Local edits survive the sync.
  /// - `overwriteMetadata=true` (`performFullImport` / explicit re-import):
  ///   metadata is replaced with PK's values.
  ///
  /// Returns 0 when no importer was wired (e.g. older tests that construct
  /// the service without an AppDatabase reference) — callers can still proceed.
  Future<PkGroupsImportResult?> _importGroups(
    PluralKitClient client, {
    required bool overwriteMetadata,
  }) async {
    final importer = _groupsImporter;
    if (importer == null) return null;
    try {
      final pkGroups = await client.getGroups(withMembers: true);
      return await importer.importGroups(
        client,
        pkGroups,
        overwriteMetadata: overwriteMetadata,
      );
    } catch (e) {
      // Groups are not a first-class blocker for the rest of the sync — don't
      // abort members/switches on a group-fetch failure.
      debugPrint('[PK] group import failed: $e');
      return null;
    }
  }

  // -- private helpers ------------------------------------------------------

  Future<void> _importMembers(
    PluralKitClient? client,
    List<PKMember> pkMembers,
  ) async {
    final existing = await _memberRepository.getAllMembers();
    debugPrint('[PK_SVC] _importMembers: existing in DB=${existing.length}');
    final byPkUuid = <String, domain.Member>{};
    for (final m in existing) {
      if (m.pluralkitUuid != null) {
        byPkUuid[m.pluralkitUuid!] = m;
      }
    }

    var created = 0;
    var updated = 0;
    var failures = 0;
    for (final pk in pkMembers) {
      // PK serves avatars from a public CDN (not the API host) and requires
      // no auth header, so the shared helper's short-lived http.Client is
      // fine here. Failures (timeout, non-image, oversize) yield null and
      // leave the existing avatar untouched.
      Uint8List? avatarData;
      if (pk.avatarUrl != null && pk.avatarUrl!.isNotEmpty) {
        avatarData = await fetchAvatarBytes(pk.avatarUrl!);
      }

      try {
        final localMember = byPkUuid[pk.uuid];
        if (localMember != null) {
          await _memberRepository.updateMember(
            localMember.copyWith(
              name: pk.displayName ?? pk.name,
              pronouns: pk.pronouns,
              bio: pk.description,
              customColorHex: pk.color,
              customColorEnabled: pk.color != null && pk.color!.isNotEmpty,
              pluralkitUuid: pk.uuid,
              pluralkitId: pk.id,
              avatarImageData: avatarData ?? localMember.avatarImageData,
            ),
          );
          updated++;
        } else {
          await _memberRepository.createMember(
            domain.Member(
              id: _uuid.v4(),
              name: pk.displayName ?? pk.name,
              pronouns: pk.pronouns,
              bio: pk.description,
              emoji: '❔',
              isActive: true,
              createdAt: DateTime.now(),
              customColorHex: pk.color,
              customColorEnabled: pk.color != null && pk.color!.isNotEmpty,
              pluralkitUuid: pk.uuid,
              pluralkitId: pk.id,
              avatarImageData: avatarData,
            ),
          );
          created++;
        }
      } catch (e, st) {
        failures++;
        debugPrint(
          '[PK_SVC] _importMembers: write FAILED for ${pk.name} (${pk.uuid}): '
          '$e\n$st',
        );
      }
    }
    debugPrint(
      '[PK_SVC] _importMembers: done — created=$created updated=$updated '
      'failures=$failures (input=${pkMembers.length})',
    );
  }

  /// Import a single switch. Returns true if it was a duplicate.
  ///
  /// Phase 4 semantics:
  /// - Iterate the PK members list; pick the FIRST locally-mapped PK ID as
  ///   `memberId`, the rest as `coFronterIds`. This fixes the old "drop the
  ///   whole switch if the first PK member is unmapped" bug.
  /// - ALWAYS persist `pkMemberIdsJson` (the raw list of PK short IDs from
  ///   PK). That lets [reattributeSwitches] re-resolve memberId / coFronters
  ///   pure-locally once more members get linked, without re-fetching from PK.
  /// - Headless sessions (no member currently maps) are still persisted — the
  ///   Drift column `fronting_sessions.memberId` is nullable, so we can store
  ///   the PK switch with `memberId = null` and reattribute later. Empty
  ///   switches (PK "no one fronting") have `sw.members == []`; we skip them
  ///   because there is nothing to attribute and the tombstone has no useful
  ///   local representation in Prism's model.
  Future<bool> _importSwitch(
    PKSwitch sw, {
    DateTime? endTime,
    required Map<String, String> pkIdToLocalId,
    Set<String>? existingPkUuids,
  }) async {
    // Check for existing session with same PK UUID
    // (We use the PK switch ID as the pluralkitUuid on fronting sessions).
    // Callers that import many switches in a loop should pass a precomputed
    // [existingPkUuids] set to avoid the O(N²) per-switch scan.
    final bool isDuplicate;
    if (existingPkUuids != null) {
      isDuplicate = existingPkUuids.contains(sw.id);
    } else {
      final existing = await _frontingSessionRepository.getAllSessions();
      isDuplicate = existing.any((s) => s.pluralkitUuid == sw.id);
    }
    if (isDuplicate) return true;

    // PK "switch-out" (empty members list) has no local representation.
    if (sw.members.isEmpty) return false;

    final (primaryMemberId, coFronterLocalIds) = _resolvePkMembers(
      sw.members,
      pkIdToLocalId,
    );

    await _frontingSessionRepository.createSession(
      domain.FrontingSession(
        id: _uuid.v4(),
        startTime: sw.timestamp,
        endTime: endTime,
        memberId: primaryMemberId,
        coFronterIds: coFronterLocalIds,
        pluralkitUuid: sw.id,
        pkMemberIdsJson: jsonEncode(sw.members),
      ),
    );

    return false;
  }

  /// Close any PK-sourced fronting sessions whose `endTime` is null but
  /// which have a later session (by `startTime`) that should have closed
  /// them. Fixes chain breaks caused by:
  ///   * incremental pulls where the previously-newest session in the DB
  ///     never gets its endTime updated when a newer switch arrives,
  ///   * switch-outs imported after a fronter session (switch-outs don't
  ///     create local rows, so pass their timestamps via [extraBoundaries]),
  ///   * cross-page boundaries in paginated pulls.
  ///
  /// Idempotent — closed sessions are left alone. "PK-sourced" = has a
  /// `pluralkitUuid` (API-imported) or `pkMemberIdsJson` (file-imported).
  Future<int> _closePkSessionChainGaps({
    Iterable<DateTime> extraBoundaries = const [],
  }) async {
    final pk = (await _frontingSessionRepository.getAllSessions())
        .where((s) => s.pluralkitUuid != null || s.pkMemberIdsJson != null)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (pk.isEmpty) return 0;

    final boundaries = <DateTime>[
      for (final s in pk) s.startTime,
      ...extraBoundaries,
    ]..sort();

    int fixed = 0;
    for (final s in pk) {
      if (s.endTime != null) continue;
      DateTime? closeAt;
      for (final b in boundaries) {
        if (b.isAfter(s.startTime)) {
          closeAt = b;
          break;
        }
      }
      if (closeAt == null) continue; // truly the latest — stays ongoing
      await _frontingSessionRepository.endSession(s.id, closeAt);
      fixed++;
    }
    if (fixed > 0) {
      debugPrint('[PK_PULL] closed $fixed stale ongoing session(s)');
    }
    return fixed;
  }

  /// Resolve a list of PK short IDs to (primary local memberId, cofronter
  /// local IDs), picking the first mapped PK ID as primary. Returns
  /// `(null, [])` when no PK IDs map locally.
  static (String?, List<String>) _resolvePkMembers(
    List<String> pkMemberIds,
    Map<String, String> pkIdToLocalId,
  ) {
    String? primary;
    final coFronters = <String>[];
    for (final pkId in pkMemberIds) {
      final localId = pkIdToLocalId[pkId];
      if (localId == null) continue;
      if (primary == null) {
        primary = localId;
      } else {
        coFronters.add(localId);
      }
    }
    return (primary, coFronters);
  }

  // -- Phase 4 public API ---------------------------------------------------

  /// Walk PK switch history after a mapping Apply and import every switch,
  /// writing `pkMemberIdsJson` on every row so [reattributeSwitches] can do
  /// pure-local re-attribution when more members get linked later.
  ///
  /// Idempotent: switches already imported (matched by `pluralkitUuid`) are
  /// skipped. Safe to re-run.
  Future<void> importSwitchesAfterLink() async {
    if (!_state.isConnected) {
      throw StateError('Not connected — cannot import switch history');
    }
    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');

    try {
      _emit(_state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Fetching PK switch history...',
        clearError: true,
      ));

      final allMembers = await _memberRepository.getAllMembers();
      final pkIdToLocalId = <String, String>{};
      for (final m in allMembers) {
        if (m.pluralkitId != null) pkIdToLocalId[m.pluralkitId!] = m.id;
      }

      // Paginate `/switches`. PK doesn't guarantee unique timestamps, so two
      // switches at the same instant across a page boundary could duplicate
      // or skip. We defend against both by keeping a seen-ID set across
      // pages and stopping when a whole page is re-seen.
      final allSwitches = <PKSwitch>[];
      final seenIds = <String>{};
      DateTime? pageBefore;
      int fetched = 0;
      while (true) {
        final page = await client.getSwitches(before: pageBefore, limit: 100);
        if (page.isEmpty) break;
        final fresh = page.where((sw) => seenIds.add(sw.id)).toList();
        if (fresh.isEmpty) break; // every switch already seen → loop cut-off
        allSwitches.addAll(fresh);
        fetched += fresh.length;
        pageBefore = page.last.timestamp;
        _emit(_state.copyWith(syncStatus: 'Fetched $fetched switches...'));
        if (page.length < 100) break;
      }

      // Sort oldest-first so we can chain endTime from next switch's startTime.
      allSwitches.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Precompute existing PK switch UUIDs so _importSwitch doesn't rescan
      // the full session list for every switch (O(N²) → O(N)).
      final existingSessions =
          await _frontingSessionRepository.getAllSessions();
      final existingPkUuids = <String>{
        for (final s in existingSessions)
          if (s.pluralkitUuid != null) s.pluralkitUuid!,
      };
      // File-imported sessions lack UUIDs; match by timestamp+member IDs and
      // adopt the API's UUID so we don't create a duplicate row here.
      final fileIndex = _buildFileImportIndex(existingSessions);

      final switchOutTimestamps = <DateTime>[];
      for (var i = 0; i < allSwitches.length; i++) {
        final sw = allSwitches[i];
        final endTime =
            i + 1 < allSwitches.length ? allSwitches[i + 1].timestamp : null;
        if (sw.members.isEmpty) switchOutTimestamps.add(sw.timestamp);
        if (i % 50 == 0) {
          _emit(_state.copyWith(
            syncProgress: allSwitches.isEmpty
                ? 1.0
                : i / allSwitches.length,
            syncStatus: 'Importing switch ${i + 1}/${allSwitches.length}...',
          ));
        }
        if (fileIndex.isNotEmpty &&
            await _adoptFileImportedSwitch(sw, fileIndex, existingPkUuids)) {
          continue;
        }
        final wasDup = await _importSwitch(
          sw,
          endTime: endTime,
          pkIdToLocalId: pkIdToLocalId,
          existingPkUuids: existingPkUuids,
        );
        if (!wasDup) existingPkUuids.add(sw.id);
      }

      await _closePkSessionChainGaps(extraBoundaries: switchOutTimestamps);

      // Phase 1 R3 — insert-only re-attribution pass for PK groups. After
      // the mapping flow applies new member links, any group memberships
      // that were deferred on first pull can now be inserted.
      final importer = _groupsImporter;
      if (importer != null) {
        try {
          await importer.reattribute(client);
        } catch (e) {
          debugPrint('[PK] group reattribute failed: $e');
        }
      }

      _emit(_state.copyWith(
        isSyncing: false,
        syncProgress: 1.0,
        syncStatus: 'Imported ${allSwitches.length} switches.',
      ));
    } catch (e) {
      _emit(_state.copyWith(
        isSyncing: false,
        syncError: 'Switch history import failed: $e',
      ));
      rethrow;
    } finally {
      client.dispose();
    }
  }

  /// Pure-local pass: re-resolve every fronting session's `memberId` and
  /// `coFronterIds` against the current `members.pluralkitId` mapping, using
  /// the stored `pkMemberIdsJson`. Idempotent — sessions whose attribution
  /// hasn't changed are not re-written.
  ///
  /// Runs after mapping Apply and after any member sync that could have
  /// linked new PK IDs. Returns the number of sessions updated.
  Future<int> reattributeSwitches() async {
    final sessions = await _frontingSessionRepository.getAllSessions();
    final members = await _memberRepository.getAllMembers();

    final pkIdToLocalId = <String, String>{};
    for (final m in members) {
      if (m.pluralkitId != null) pkIdToLocalId[m.pluralkitId!] = m.id;
    }

    // Collect dirty rows first, then flush in a single Drift transaction so a
    // bulk re-attribution isn't N separate auto-commits.
    final pending = <domain.FrontingSession>[];
    for (final session in sessions) {
      final raw = session.pkMemberIdsJson;
      if (raw == null || raw.isEmpty) continue;

      final List<String> pkIds;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        pkIds = decoded.whereType<String>().toList(growable: false);
      } catch (_) {
        continue;
      }

      final (primary, coFronters) = _resolvePkMembers(pkIds, pkIdToLocalId);

      // Skip write if nothing changed. Comparing lists: same length AND
      // element-by-element equal (order matters — first is primary).
      final sameCofronters = session.coFronterIds.length == coFronters.length &&
          _listEquals(session.coFronterIds, coFronters);
      if (session.memberId == primary && sameCofronters) continue;

      pending.add(
        session.copyWith(memberId: primary, coFronterIds: coFronters),
      );
    }

    if (pending.isEmpty) return 0;

    await _syncDao.attachedDatabase.transaction(() async {
      for (final s in pending) {
        await _frontingSessionRepository.updateSession(s);
      }
    });
    return pending.length;
  }

  // -- Plan 02: PK deletion push --------------------------------------------

  /// Threshold for the R6 multi-device coordination stamp. If another device
  /// recently claimed the push (within this window), we back off; past this
  /// window we assume the other device crashed or is offline and take over.
  static const _deletePushTakeoverThreshold = Duration(minutes: 10);

  /// Push pending switch deletions. Returns the number that succeeded.
  Future<int> _pushPendingSwitchDeletions({
    required PluralKitClient client,
    void Function(String message)? onStaleLink,
    PkPushService? pushServiceOverride,
  }) async {
    final currentEpoch = await _syncDao.getLinkEpoch();
    final candidates =
        await _frontingSessionRepository.getDeletedLinkedSessions();
    if (candidates.isEmpty) return 0;

    final push = pushServiceOverride ?? PkPushService();
    int deleted = 0;

    for (final session in candidates) {
      // R6: cross-device coordination stamp. If another device started
      // pushing this within the takeover window, let them finish.
      final startedAtMs = session.deletePushStartedAt;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (startedAtMs != null) {
        final age = Duration(milliseconds: nowMs - startedAtMs);
        if (age < _deletePushTakeoverThreshold) {
          debugPrint(
            '[PK] Switch deletion for ${session.id} started by another '
            'device ${age.inSeconds}s ago — skipping this pass.',
          );
          continue;
        }
        // else: stale lease, take over.
      } else {
        // Claim the lease via the synced update so peers see it.
        await _frontingSessionRepository.stampDeletePushStartedAt(
          session.id,
          nowMs,
        );
      }

      // R2: re-read and re-check every invariant at execution time.
      final fresh =
          await _frontingSessionRepository.getSessionById(session.id);
      if (fresh == null) continue;
      if (!fresh.isDeleted) {
        debugPrint(
          '[PK] Session ${session.id} was resurrected by CRDT merge; '
          'aborting DELETE.',
        );
        continue;
      }
      if (fresh.pluralkitUuid == null ||
          fresh.pluralkitUuid != session.pluralkitUuid) {
        debugPrint(
          '[PK] Session ${session.id} pluralkit_uuid changed since dequeue; '
          'aborting DELETE.',
        );
        continue;
      }
      // R1: epoch gate. deleteIntentEpoch is local and not synced.
      // getDeletedLinkedSessions returns rows where it's non-null.
      final intentEpoch = session.deleteIntentEpoch;
      if (intentEpoch != currentEpoch) {
        debugPrint(
          '[PK] Session ${session.id} intent epoch $intentEpoch != current '
          '$currentEpoch; aborting DELETE (stale link).',
        );
        continue;
      }

      final pkUuid = fresh.pluralkitUuid!;
      try {
        await push.pushSwitchDeletion(session.id, pkUuid, client);
        await _frontingSessionRepository.clearPluralKitLink(session.id);
        deleted++;
      } on PkDeletionForbiddenException catch (e) {
        onStaleLink?.call(
          'PluralKit refused switch deletion — your token may not own this '
          'switch. Check your token and retry. (pkUuid=${e.pkId})',
        );
      } on PluralKitAuthError {
        rethrow;
      } catch (e) {
        debugPrint('[PK] Switch deletion failed for ${session.id}: $e');
      }
    }
    return deleted;
  }

  /// Push pending member deletions. Runs AFTER switch deletions (caller
  /// orders). R5 cascade guard included: skip any member that still has
  /// live local sessions linked to PK.
  Future<int> _pushPendingMemberDeletions({
    required PluralKitClient client,
    void Function(String message)? onStaleLink,
    PkPushService? pushServiceOverride,
  }) async {
    final currentEpoch = await _syncDao.getLinkEpoch();
    final candidates = await _memberRepository.getDeletedLinkedMembers();
    if (candidates.isEmpty) return 0;

    // R5: fetch live sessions once and check in-memory.
    final liveSessions = await _frontingSessionRepository.getAllSessions();
    final membersWithLiveLinkedSessions = <String>{};
    for (final s in liveSessions) {
      if (s.isDeleted) continue; // getAllSessions already filters, defensive
      if (s.pluralkitUuid == null) continue;
      final mid = s.memberId;
      if (mid != null) membersWithLiveLinkedSessions.add(mid);
    }

    final push = pushServiceOverride ?? PkPushService();
    int deleted = 0;

    for (final member in candidates) {
      if (membersWithLiveLinkedSessions.contains(member.id)) {
        debugPrint(
          '[PK] R5 cascade guard: member ${member.id} has live linked '
          'sessions; skipping DELETE.',
        );
        onStaleLink?.call(
          "Skipped deleting PluralKit member '${member.name}' — it still "
          'has linked local switches. Delete those first, or undelete the '
          'member to keep it.',
        );
        continue;
      }

      // R6: coordination lease.
      final startedAtMs = member.deletePushStartedAt;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (startedAtMs != null) {
        final age = Duration(milliseconds: nowMs - startedAtMs);
        if (age < _deletePushTakeoverThreshold) {
          debugPrint(
            '[PK] Member deletion for ${member.id} started by another '
            'device ${age.inSeconds}s ago — skipping.',
          );
          continue;
        }
      } else {
        await _memberRepository.stampDeletePushStartedAt(member.id, nowMs);
      }

      // R2 re-read.
      final fresh = await _memberRepository.getMemberById(member.id);
      if (fresh == null) continue;
      if (!fresh.isDeleted) {
        debugPrint(
          '[PK] Member ${member.id} was resurrected by CRDT merge; aborting.',
        );
        continue;
      }
      if (fresh.pluralkitId == null || fresh.pluralkitId != member.pluralkitId) {
        debugPrint(
          '[PK] Member ${member.id} pluralkit_id changed since dequeue; '
          'aborting DELETE.',
        );
        continue;
      }
      final intentEpoch = member.deleteIntentEpoch;
      if (intentEpoch != currentEpoch) {
        debugPrint(
          '[PK] Member ${member.id} intent epoch $intentEpoch != current '
          '$currentEpoch; aborting DELETE (stale link).',
        );
        continue;
      }

      final pkId = fresh.pluralkitId!;
      try {
        await push.pushMemberDeletion(member.id, pkId, client);
        await _memberRepository.clearPluralKitLink(member.id);
        deleted++;
      } on PkDeletionForbiddenException catch (e) {
        onStaleLink?.call(
          "PluralKit refused member deletion of '${member.name}' — your "
          'token may not own this member. Check your token and retry. '
          '(pkId=${e.pkId})',
        );
      } on PluralKitAuthError {
        rethrow;
      } catch (e) {
        debugPrint('[PK] Member deletion failed for ${member.id}: $e');
      }
    }
    return deleted;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Phase 4 scoped switch push.
  ///
  /// Pushes local fronting sessions to PK that:
  /// - started after `linkedAt` (no backfilling pre-link history)
  /// - have no `pluralkitUuid` yet (never pushed)
  /// - have a `memberId` that resolves to a member with a `pluralkitId`
  ///
  /// For sessions with `endTime != null`, follows up with a second "switch-
  /// out" create — `createSwitch([], timestamp: endTime)` — which is PK's
  /// convention for "no one is fronting." The returned PK switch UUID is
  /// stored on the local session so subsequent syncs don't duplicate it.
  ///
  /// Returns the number of local sessions that were pushed.
  ///
  /// When [onStaleLink] is provided, it is called once per session whose
  /// push failed with a 404 (`PkStaleLinkException`). The caller can use
  /// this to surface a user-facing message. The callback receives a short
  /// human-readable description; the session is still counted as "not
  /// pushed" and left retriable, same as before.
  Future<int> pushPendingSwitches({
    PkPushService? pushService,
    void Function(String message)? onStaleLink,
  }) async {
    if (!_state.isConnected) {
      throw StateError('Not connected — cannot push switches');
    }
    final linkedAt = _state.linkedAt;
    if (linkedAt == null) {
      // No linkedAt means we don't have a safe cutoff — don't push anything
      // to avoid flooding PK with historical sessions.
      return 0;
    }

    final client = await _buildClient();
    if (client == null) throw StateError('Not connected');

    final push = pushService ?? const PkPushService();

    try {
      final members = await _memberRepository.getAllMembers();
      final localIdToPkId = <String, String>{};
      for (final m in members) {
        if (m.pluralkitId != null && m.pluralkitId!.isNotEmpty) {
          localIdToPkId[m.id] = m.pluralkitId!;
        }
      }

      final sessions = await _frontingSessionRepository.getAllSessions();
      int pushed = 0;
      for (final session in sessions) {
        if (session.pluralkitUuid != null) continue;
        if (!session.startTime.isAfter(linkedAt)) continue;
        final memberId = session.memberId;
        if (memberId == null) continue;
        final pkPrimary = localIdToPkId[memberId];
        if (pkPrimary == null) continue; // fronter isn't linked

        // Cofronters: include only the ones that are linked.
        final pkMemberIds = <String>[pkPrimary];
        for (final coId in session.coFronterIds) {
          final pkCo = localIdToPkId[coId];
          if (pkCo != null) pkMemberIds.add(pkCo);
        }

        String? createdUuid;
        try {
          final created = await push.pushSwitch(
            pkMemberIds,
            client,
            timestamp: session.startTime,
          );
          createdUuid = created.id;

          // Explicit switch-out for completed sessions. Keeping this in the
          // same try/catch means (a) a stale-link on the switch-out only
          // skips this session, and (b) if the switch-out fails after the
          // start already succeeded we can roll the start back below so
          // the session stays retriable.
          if (session.endTime != null) {
            await push.pushSwitch(
              const [],
              client,
              timestamp: session.endTime,
            );
          }

          // Only persist the PK UUID once BOTH pushes succeed — otherwise a
          // crash between them would leave an "open" PK switch and a local
          // session tagged as pushed, which we'd never retry.
          await _frontingSessionRepository.updateSession(
            session.copyWith(pluralkitUuid: createdUuid),
          );
          pushed++;
        } on PkStaleLinkException catch (e) {
          // A 404 on switch push is the switch/members resource going stale
          // on PK. We don't know which member to clear (the create call
          // doesn't name one), and the switch itself wasn't persisted
          // locally yet. Skip this session; a future retry may re-attempt.
          // Do NOT clear member pluralkitId here — member-side stale-link
          // handling is pushMember's job.
          if (createdUuid != null) {
            try {
              await client.deleteSwitch(createdUuid);
            } catch (cleanupErr) {
              debugPrint(
                '[PK] Failed to roll back partial switch $createdUuid '
                'after stale-link: $cleanupErr. Leaving session $memberId '
                'retriable; a future push may create a duplicate switch.',
              );
            }
          }
          debugPrint(
            '[PK] Stale link on switch push (pkId=${e.pkId}); skipping '
            'session ${session.id}.',
          );
          onStaleLink?.call(
            'A PluralKit switch target was removed on the server — '
            'skipped pushing one local session. (pkId=${e.pkId})',
          );
        } catch (e) {
          // Non-stale failure mid-two-push. If the start already succeeded,
          // roll it back so the session remains pending and won't leak an
          // open switch on PK. If rollback fails, we leave pluralkitUuid
          // unset so the session stays retriable — trade-off: a future
          // retry may create a duplicate PK switch, but that's preferable
          // to silently dropping the session forever.
          if (createdUuid != null) {
            try {
              await client.deleteSwitch(createdUuid);
            } catch (cleanupErr) {
              debugPrint(
                '[PK] Failed to roll back partial switch $createdUuid '
                'after error $e: $cleanupErr. Session ${session.id} will '
                'be retried; expect a possible duplicate PK switch.',
              );
            }
          }
          debugPrint(
            '[PK] Switch push failed for session ${session.id}: $e. '
            'Leaving session pending for retry.',
          );
        }
      }
      return pushed;
    } finally {
      client.dispose();
    }
  }

  /// Push a single linked member's fields to PluralKit after a local edit.
  ///
  /// Caller is responsible for gating on connection state and push-direction
  /// (see `PluralKitSyncNotifier.pushMemberUpdate`). A 404 from PK clears the
  /// local link so the user can re-link via the mapping screen.
  ///
  /// Returns true if a PATCH was actually sent, false when skipped (no link,
  /// not connected, etc.). Errors are swallowed with a debugPrint so a failed
  /// push never breaks the user's edit flow — the next manual sync retries.
  Future<bool> pushMemberUpdate(
    domain.Member member, {
    PkPushService? pushService,
  }) async {
    if (member.pluralkitId == null || member.pluralkitId!.isEmpty) return false;
    if (!_state.canAutoSync) return false;

    final client = await _buildClient();
    if (client == null) return false;

    final push = pushService ?? const PkPushService();
    try {
      await push.pushMember(member, client);
      return true;
    } on PkStaleLinkException {
      // PK deleted the linked member. Clear the local link; a future manual
      // sync or re-mapping will reconcile.
      try {
        await _memberRepository.updateMember(
          member.copyWith(pluralkitId: null, pluralkitUuid: null),
        );
      } catch (_) {}
      return false;
    } catch (e) {
      debugPrint('[PK] pushMemberUpdate failed for ${member.id}: $e');
      return false;
    } finally {
      client.dispose();
    }
  }
}
