import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/sqlite_constraint.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/core/services/secure_storage.dart'
    as storage_config;
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_bidirectional_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_fronting_switch_matcher.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_session_id.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_switch_cursor.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/shared/utils/avatar_fetcher.dart';

final RegExp _pluralKitSwitchUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

@visibleForTesting
bool isPluralKitSwitchUuid(String? value) {
  final trimmed = value?.trim();
  return trimmed != null &&
      trimmed.isNotEmpty &&
      _pluralKitSwitchUuidPattern.hasMatch(trimmed);
}

/// Snapshot of one local member's currently-active PluralKit presence
/// during a diff sweep (WS3 step 3).
///
/// Replaces the previous `Map<String, String> openRowIds` representation,
/// which only carried the row id and silently lost track of presences
/// whose row writes were skipped (e.g. tombstoned-row collisions). The
/// struct keeps every active local member as a peg in the active map so
/// later leaver events have something to match against, while
/// distinguishing presences that own a real fronting-session row from
/// those that don't.
///
/// Fields:
/// - [pkMemberUuid]: the member's PluralKit UUID at sweep start. Carried
///   so PR E2 can re-derive ids without re-scanning the reverse map.
///   Nullable because a DB-rebuilt presence may belong to a local member
///   whose PK mapping was dropped between writes.
/// - [startedAt]: when the presence began (the entrant switch's timestamp,
///   or the open row's start_time when reconstituted from the DB).
/// - [rowId]: the fronting-session row id, or `null` if no row was written
///   for this presence (tombstoned-row collision; the diff sweep correctly
///   skips both the entrant write and the future leaver close).
/// - [isTombstonedCollision]: `true` when the entrant write was skipped
///   because the deterministic row id collided with a soft-deleted row
///   during incremental sync. PR E1 only records the flag — PR E2 will
///   use it to fix findings #7 and #33.
///
/// Equality is value-based so tests and assertions can compare snapshots
/// without caring about identity.
@immutable
class _PkActivePresence {
  const _PkActivePresence({
    required this.localMemberId,
    required this.pkMemberUuid,
    required this.startedAt,
    this.rowId,
    this.isTombstonedCollision = false,
  });

  final String localMemberId;
  final String? pkMemberUuid;
  final DateTime startedAt;
  final String? rowId;
  final bool isTombstonedCollision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PkActivePresence &&
          localMemberId == other.localMemberId &&
          pkMemberUuid == other.pkMemberUuid &&
          startedAt == other.startedAt &&
          rowId == other.rowId &&
          isTombstonedCollision == other.isTombstonedCollision;

  @override
  int get hashCode => Object.hash(
        localMemberId,
        pkMemberUuid,
        startedAt,
        rowId,
        isTombstonedCollision,
      );

  @override
  String toString() =>
      '_PkActivePresence(localMemberId: $localMemberId, '
      'pkMemberUuid: $pkMemberUuid, startedAt: $startedAt, '
      'rowId: $rowId, isTombstonedCollision: $isTombstonedCollision)';
}

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

const pkImportSourceFile = 'file';
const pkImportSourceFileApi = 'file_api';

// ---------------------------------------------------------------------------
// Sync service / notifier
// ---------------------------------------------------------------------------

typedef SyncStateCallback = void Function(PluralKitSyncState state);

/// Fields the user can choose to import from the PK system profile on first
/// pull. See [PluralKitSyncService.adoptSystemProfile] (plan 04).
enum PkProfileField { name, description, tag, avatar }

/// Read-only PK reference data used by local repair flows.
///
/// This is fetched via an ephemeral client and does not imply that the service
/// is connected for sync/import side effects.
class PkRepairReferenceData {
  final PKSystem system;
  final List<PKMember> members;
  final List<PKGroup> groups;

  const PkRepairReferenceData({
    required this.system,
    required this.members,
    required this.groups,
  });
}

/// Result for a one-shot PluralKit token import.
///
/// The token is used only for the import run. It is not persisted, and the
/// PluralKit connection state is not enabled.
class PkTokenImportResult {
  final PKSystem system;
  final List<PKMember> members;
  final int switchesImported;
  final int unmappedMemberReferences;

  const PkTokenImportResult({
    required this.system,
    required this.members,
    required this.switchesImported,
    required this.unmappedMemberReferences,
  });
}

class _PkFullImportRun {
  final PKSystem system;
  final List<PKMember> members;
  final int totalSwitches;
  final int unmappedMemberReferences;
  final DateTime? completedAt;

  const _PkFullImportRun({
    required this.system,
    required this.members,
    required this.totalSwitches,
    required this.unmappedMemberReferences,
    required this.completedAt,
  });
}

/// Core PluralKit synchronization logic.
///
/// Designed to be driven by a Riverpod notifier that passes a
/// [SyncStateCallback] so the notifier can update its state.
class PluralKitSyncService {
  /// Hard cap on incremental sweep pagination: 1000 pages × 100 switches/page
  /// = 100,000 switches, well above any realistic system. Hitting it means
  /// either the API is stuck or the cursor is so stale a full re-import is
  /// the appropriate path; we surface [PkImportTooLargeError] instead of
  /// looping. See WS3 step 2.
  static const int _maxIncrementalPages = 1000;

  /// Test-only accessor for [_maxIncrementalPages]. Exposed so the
  /// page-cap guard test can build a fixture sized to the cap without
  /// hard-coding the constant in two places.
  @visibleForTesting
  static int get maxIncrementalPagesForTesting => _maxIncrementalPages;

  final MemberRepository _memberRepository;
  final FrontingSessionRepository _frontingSessionRepository;
  final PluralKitSyncDao _syncDao;
  final SystemSettingsRepository? _settingsRepository;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;
  final PluralKitClient Function(String token)? _clientFactory;
  final String? _tokenOverride;
  final PkGroupsImporter? _groupsImporter;
  final PkBannerCacheService _bannerCacheService;

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
    PkBannerCacheService? bannerCacheService,
  }) : _memberRepository = memberRepository,
       _frontingSessionRepository = frontingSessionRepository,
       _syncDao = syncDao,
       _settingsRepository = settingsRepository,
       _secureStorage = secureStorage ?? storage_config.secureStorage,
       _uuid = const Uuid(),
       _clientFactory = clientFactory,
       _tokenOverride = tokenOverride,
       _groupsImporter = groupsImporter,
       _bannerCacheService = bannerCacheService ?? PkBannerCacheService();

  PluralKitSyncState get state => _state;

  void _emit(PluralKitSyncState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  // -- helpers --------------------------------------------------------------

  String? _normalizeToken(String? token) {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<String?> _getToken() => _tokenOverride != null
      ? Future.value(_tokenOverride)
      : _secureStorage.read(key: _pkTokenKey);

  PluralKitClient _makeClient(String token) => _clientFactory != null
      ? _clientFactory(token)
      : PluralKitClient(token: token);

  PluralKitClient? _buildClientFromToken(String? token) {
    final normalized = _normalizeToken(token);
    if (normalized == null) return null;
    return _makeClient(normalized);
  }

  Future<PluralKitClient?> _buildClient() async =>
      _buildClientFromToken(await _getToken());

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  Future<String?> _getRepairToken({String? token}) async {
    if (token != null) return _normalizeToken(token);
    return _normalizeToken(await _getToken());
  }

  Future<PluralKitClient?> _buildRepairClient({String? token}) async =>
      _buildClientFromToken(await _getRepairToken(token: token));

  Future<PkRepairReferenceData> _fetchReferenceData(
    PluralKitClient client, {
    bool includeGroups = true,
  }) async {
    final system = await client.getSystem();
    final members = await client.getMembers();
    final groups = includeGroups
        ? await client.getGroups(withMembers: true)
        : const <PKGroup>[];
    return PkRepairReferenceData(
      system: system,
      members: members,
      groups: groups,
    );
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

  /// Whether repair can use a stored or explicitly-provided PK token.
  ///
  /// This is read-only: it does not validate the token, persist it, or change
  /// sync state.
  Future<bool> hasRepairToken({String? token}) async =>
      (await _getRepairToken(token: token)) != null;

  /// Read-only PK fetch for repair reference data.
  ///
  /// This intentionally does not call [setToken], write secure storage, update
  /// the sync DAO, or emit connected/syncing state changes. A future repair
  /// coordinator can pass a one-off [token] or fall back to the stored token.
  Future<PkRepairReferenceData> fetchRepairReferenceData({
    String? token,
  }) async {
    final client = await _buildRepairClient(token: token);
    if (client == null) {
      throw StateError('No PluralKit token available for repair');
    }

    try {
      return await _fetchReferenceData(client);
    } finally {
      client.dispose();
    }
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

      _emit(
        _state.copyWith(
          isConnected: true,
          needsMapping: true,
          linkedAt: linkedAt,
          clearError: true,
        ),
      );
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
        switchCursorTimestamp: Value(null),
        switchCursorId: Value(null),
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
      final data = await _fetchReferenceData(client, includeGroups: false);
      return (data.system.name, data.members);
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
      debugPrint(
        '[PK_SVC] importMembersOnly: _buildClient returned null '
        '(token missing from secure storage?)',
      );
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

  /// Corrective full re-import: members + groups + complete PK switch history.
  ///
  /// This is the explicit "Re-import all from PluralKit" user action. It
  /// differs from [syncRecentData] in setup:
  ///   1. Pre-closes all currently-open PK-linked sessions (sets end_time=now).
  ///   2. Resets prevActive to {} (starts fresh).
  ///   3. Resets the diff-sweep cursor so the sweep runs from the beginning
  ///      of PK history.
  ///   4. Runs the diff sweep from oldest switch to newest.
  ///
  /// Deterministic IDs: rows created by a previous import keep the same id
  /// when the sweep re-derives them (v5 UUIDs from entry-switch + member uuid).
  /// CRDT field-LWW handles boundary correction on collision.
  Future<void> performFullImport() async {
    if (_state.isSyncing) return;
    await _performFullImport();
  }

  /// One-time full import using a stored or caller-provided token without
  /// changing PluralKit connection state.
  ///
  /// This is for migration recovery flows: it imports members, groups, and
  /// switch history from PK, but does not call [setToken], does not persist a
  /// provided token, and does not mark ongoing PK sync as connected.
  Future<PkTokenImportResult> performOneTimeFullImport({String? token}) =>
      _performFullImport(useRepairToken: true, token: token);

  Future<PkTokenImportResult> _performFullImport({
    bool useRepairToken = false,
    String? token,
  }) async {
    if (!useRepairToken && _state.needsMapping) {
      throw StateError(
        'Mapping pending — complete the mapping flow before auto-syncing.',
      );
    }
    if (_state.isSyncing) {
      throw StateError('PluralKit import is already running');
    }
    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Fetching system info...',
        clearError: true,
      ),
    );

    final client = useRepairToken
        ? await _buildRepairClient(token: token)
        : await _buildClient();
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      throw StateError(
        useRepairToken
            ? 'PluralKit token is required for one-time import'
            : 'Not connected',
      );
    }

    try {
      final run = await _runFullImportWithClient(client, updateSyncState: true);
      final statusParts = [
        'Imported ${run.members.length} members and '
            '${run.totalSwitches} switches.',
        if (run.unmappedMemberReferences > 0)
          '${run.unmappedMemberReferences} switches had unmapped members.',
      ];

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: statusParts.join(' '),
          lastSyncDate: run.completedAt,
        ),
      );
      return PkTokenImportResult(
        system: run.system,
        members: run.members,
        switchesImported: run.totalSwitches,
        unmappedMemberReferences: run.unmappedMemberReferences,
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

  /// One-shot token import used by onboarding.
  ///
  /// This imports members, groups, and complete switch history without calling
  /// [setToken], writing secure storage, or marking PK sync connected.
  Future<PkTokenImportResult> importFromTokenOnce(String token) =>
      performOneTimeFullImport(token: token);

  /// Import a parsed `pk;export` file.
  ///
  /// Members and groups are imported from the file. The fronting/switches
  /// portion of file imports is DROPPED per §2.1 of the per-member fronting
  /// spec — fronting history requires API linking to use the diff-sweep
  /// algorithm correctly. Any switches in the file are silently skipped; the
  /// returned [PkFileImportResult] reports `switchesCreated = 0` and
  /// `switchesSkipped` = the count of switches in the file.
  Future<PkFileImportResult> importFromFile(
    PkFileExport export, {
    void Function(double progress, String status)? onProgress,
  }) async {
    void progress(double p, String s) {
      onProgress?.call(p, s);
      _emit(_state.copyWith(syncProgress: p, syncStatus: s));
    }

    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Importing from file…',
        clearError: true,
      ),
    );

    try {
      progress(0.05, 'Importing ${export.members.length} members…');
      await _importMembers(null, export.members);

      if (export.groups.isNotEmpty && _groupsImporter != null) {
        progress(0.40, 'Importing ${export.groups.length} groups…');
        try {
          await _groupsImporter.importGroups(
            export.groups,
            overwriteMetadata: true,
          );
        } catch (e) {
          debugPrint('[PK_FILE] group import failed (non-fatal): $e');
        }
      }

      // Fronting history from files is not imported — see §2.1. Requires API
      // linking to use the diff-sweep algorithm. Switches are counted and
      // reported so the UI can explain what happened.
      final switchCount = export.switches.length;
      if (switchCount > 0) {
        debugPrint(
          '[PK_FILE] Skipping $switchCount file switches — '
          'fronting history import requires API linking (§2.1).',
        );
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: 'Imported ${export.members.length} members.',
        ),
      );

      return PkFileImportResult(
        systemName: export.system.name,
        membersImported: export.members.length,
        groupsImported: export.groups.length,
        switchesCreated: 0,
        switchesSkipped: switchCount,
      );
    } catch (e) {
      _emit(
        _state.copyWith(isSyncing: false, syncError: 'File import failed: $e'),
      );
      rethrow;
    }
  }

  /// Import a `pk;export` file while using a token only to canonicalize
  /// fronting history against PluralKit API switch IDs.
  ///
  /// Members/groups still come from the file import path. Fronting rows are
  /// written only when the file/API switch matcher says canonicalization is
  /// safe; otherwise this returns a mismatch summary without persisting any
  /// fronting rows.
  Future<PkFileTokenFrontingImportResult> importFromFileWithToken(
    PkFileExport export, {
    String? token,
    void Function(double progress, String status)? onProgress,
  }) async {
    void progress(double p, String s) {
      onProgress?.call(p, s);
      _emit(_state.copyWith(syncProgress: p, syncStatus: s));
    }

    if (_state.isSyncing) {
      return PkFileTokenFrontingImportResult(
        systemName: export.system.name,
        membersImported: 0,
        groupsImported: 0,
        canonicalizationSafe: false,
        frontingImported: false,
        exactImportedCount: 0,
        staleFileCount: 0,
        ambiguousCount: 0,
        ambiguousKeys: const [],
        fileOnlyCount: export.switches.length,
        apiOnlyInRangeCount: 0,
        apiOnlyOutsideRangeCount: 0,
        apiSwitchesFetched: 0,
        unmappedMemberReferences: 0,
        apiSwitchIdsByFileIndex: const {},
      );
    }

    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Importing from file and PluralKit...',
        clearError: true,
      ),
    );

    final client = await _buildRepairClient(token: token);
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      throw StateError('PluralKit token is required for file + token import');
    }

    try {
      progress(0.03, 'Checking PluralKit token...');
      await client.getSystem();

      progress(0.05, 'Importing ${export.members.length} members...');
      await _importMembers(null, export.members);

      if (export.groups.isNotEmpty && _groupsImporter != null) {
        progress(0.25, 'Importing ${export.groups.length} groups...');
        try {
          await _groupsImporter.importGroups(
            export.groups,
            overwriteMetadata: true,
          );
        } catch (e) {
          debugPrint('[PK_FILE_TOKEN] group import failed (non-fatal): $e');
        }
      }

      progress(0.40, 'Fetching PluralKit switches...');
      final apiSwitches = await _fetchSwitchesForFileRange(
        client,
        export.switches,
      );

      progress(0.55, 'Matching file switches to PluralKit...');
      final match = const PkFrontingSwitchMatcher().compare(
        fileSwitches: export.switches,
        apiSwitches: apiSwitches,
      );

      var frontingImported = false;
      var unmappedMemberReferences = 0;
      if (match.canonicalizationSafe) {
        final fileSwitchIdsByApiSwitchId = <String, String>{
          for (final exactMatch in match.exactMatches)
            exactMatch.apiSwitchId: _pkFileSwitchSourceId(
              exactMatch.fileSwitch,
            ),
        };
        final pkImportSourcesByApiSwitchId = <String, String>{
          for (final exactMatch in match.exactMatches)
            exactMatch.apiSwitchId: pkImportSourceFileApi,
        };

        progress(0.70, 'Importing canonical fronting history...');
        final shortIdToUuid = await _buildShortIdToUuidMap();
        if (shortIdToUuid.isEmpty && apiSwitches.isNotEmpty) {
          throw StateError(
            'No PluralKit members resolved to local members. '
            'Ensure members are imported before importing fronting history.',
          );
        }

        unmappedMemberReferences = await _runDiffSweep(
          switches: apiSwitches,
          shortIdToUuid: shortIdToUuid,
          prevActive: {},
          corrective: true,
          pkImportSourceByApiSwitchId: pkImportSourcesByApiSwitchId,
          pkFileSwitchIdsByApiSwitchId: fileSwitchIdsByApiSwitchId,
        );
        frontingImported = true;
      } else {
        debugPrint(
          '[PK_FILE_TOKEN] switch canonicalization blocked: '
          'fileOnly=${match.fileOnlyCount}, '
          'apiOnlyInRange=${match.apiOnlyInsideFileRangeCount}, '
          'ambiguous=${match.ambiguousCount}',
        );
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: frontingImported
              ? 'Imported canonical PluralKit fronting history.'
              : 'Imported file data; fronting history needs review.',
        ),
      );

      return PkFileTokenFrontingImportResult(
        systemName: export.system.name,
        membersImported: export.members.length,
        groupsImported: export.groups.length,
        canonicalizationSafe: match.canonicalizationSafe,
        frontingImported: frontingImported,
        exactImportedCount: frontingImported ? match.exactMatchCount : 0,
        staleFileCount: match.apiOnlyOutsideFileRangeCount,
        ambiguousCount: match.ambiguousCount,
        ambiguousKeys: List.unmodifiable(
          match.ambiguousKeys.map((entry) => entry.key.toString()),
        ),
        fileOnlyCount: match.fileOnlyCount,
        apiOnlyInRangeCount: match.apiOnlyInsideFileRangeCount,
        apiOnlyOutsideRangeCount: match.apiOnlyOutsideFileRangeCount,
        apiSwitchesFetched: apiSwitches.length,
        unmappedMemberReferences: unmappedMemberReferences,
        apiSwitchIdsByFileIndex: match.apiSwitchIdsByFileIndex,
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: 'File + token import failed: $e',
        ),
      );
      rethrow;
    } finally {
      client.dispose();
    }
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
    // Claim isSyncing before the first await so no concurrent caller can
    // slip through the flag check during an await gap.
    if (_state.isSyncing) return null;
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

    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Syncing recent changes...',
        clearError: true,
      ),
    );

    final client = await _buildClient();
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      throw StateError('Not connected');
    }

    try {
      // Build member resolution map for the diff sweep.
      final shortIdToUuid = await _buildShortIdToUuidMap();

      // Accumulates messages for PK-side 404s we detected during this run.
      // Surfaced via `syncError` at the end so the user sees that a linked
      // member or switch was deleted on PK (otherwise the unlink would be
      // silent — see bug S3).
      final staleLinkMessages = <String>[];

      // -- Bidirectional member sync --
      PkSyncSummary? summary;
      if (direction.pushEnabled) {
        _emit(
          _state.copyWith(syncProgress: 0.1, syncStatus: 'Syncing members...'),
        );

        final pkMembers = await client.getMembers();

        // Load per-member field configs
        final row = await _syncDao.getSyncState();
        final fieldConfigs = parseFieldSyncConfig(row.fieldSyncConfig);

        final allMembers = await _memberRepository.getAllMembers();

        // Snapshot linked-member names before the bidirectional run so we can
        // detect stale-link clears.
        final linkedBefore = <String, String>{
          for (final m in allMembers)
            if (m.pluralkitId != null || m.pluralkitUuid != null) m.id: m.name,
        };

        final biService = PkBidirectionalService(
          bannerCacheService: _bannerCacheService,
        );
        summary = await biService.syncMembers(
          localMembers: allMembers,
          pkMembers: pkMembers,
          fieldConfigs: fieldConfigs,
          direction: direction,
          lastSyncDate: _state.lastSyncDate,
          memberRepository: _memberRepository,
          client: client,
        );

        // Detect stale-link clears.
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

      // -- Pull recent switches via incremental diff sweep --
      //
      // Resume cursor: read (switchCursorTimestamp, switchCursorId) from DB
      // as a `PkSwitchCursor`. PK paginates newest-first via the `before`
      // query param (max 100 switches/page). We fetch newest first, walk
      // backwards by `before = page.last.timestamp`, and accept every switch
      // strictly newer than the cursor — i.e. `(sw.ts, sw.id) > cursor`
      // lexicographically. Switches at the same timestamp as the cursor with
      // a different id are *not* skipped, because they were never processed
      // on the prior sweep (regression fix: WS3 step 2 / review finding #6).
      //
      // Pagination is bounded by [_maxIncrementalPages] and aborts on a
      // no-progress page (where `before = page.last.timestamp` doesn't
      // advance), surfacing typed errors instead of spinning forever.
      int totalNew = 0;
      int totalUnmapped = 0;
      if (direction.pullEnabled) {
        final cursorRow = await _syncDao.getSyncState();
        final PkSwitchCursor? cursor =
            (cursorRow.switchCursorTimestamp != null &&
                cursorRow.switchCursorId != null)
            ? PkSwitchCursor(
                timestamp: cursorRow.switchCursorTimestamp!,
                switchId: cursorRow.switchCursorId!,
              )
            : null;

        debugPrint(
          '[PK_PULL] incremental sweep cursor='
          '${cursor?.toString() ?? 'null'}',
        );

        // Reconstitute prevActive from currently-open PK-linked rows.
        final currentSessions = await _frontingSessionRepository
            .getAllSessions();
        final prevActive = <String>{
          for (final s in currentSessions)
            if (s.endTime == null &&
                isPluralKitSwitchUuid(s.pluralkitUuid) &&
                !s.isDeleted &&
                s.memberId != null)
              s.memberId!,
        };

        debugPrint(
          '[PK_PULL] prevActive from open rows: ${prevActive.length} members',
        );

        final newSwitches = <PKSwitch>[];
        int pageNum = 0;
        bool reachedCursor = (cursor == null); // no cursor → fetch all
        DateTime? previousPageBefore;

        while (true) {
          // First page: no `before`, fetch newest. Subsequent pages: page
          // backwards from the previous page's oldest timestamp. Note that
          // we use the *page's* last timestamp, not `newSwitches.last`, so
          // that even if the cursor break trims the page partway through we
          // continue paging from the actual API boundary.
          final DateTime? fetchBefore = previousPageBefore;
          final page = await client.getSwitches(
            before: fetchBefore,
            limit: 100,
          );
          pageNum++;
          debugPrint('[PK_PULL] page=$pageNum fetched=${page.length}');
          if (page.isEmpty) break;

          // No-progress guard: a non-empty page that doesn't advance the
          // paging boundary would loop forever under naive `before =
          // page.last.timestamp`. Bail with a typed error so the caller
          // sees a real failure rather than a hung sweep.
          final pageOldest = page.last.timestamp;
          if (previousPageBefore != null && pageOldest == previousPageBefore) {
            throw PkPaginationNoProgressError(
              lastBefore: pageOldest,
              pagesFetched: pageNum,
            );
          }
          previousPageBefore = pageOldest;

          for (final sw in page) {
            // Skip any switch at or before the cursor lexicographically.
            // Crucially, switches at the same timestamp as the cursor but a
            // different id are NOT covered and must be processed.
            if (cursor != null && cursor.covers(sw.timestamp, sw.id)) {
              reachedCursor = true;
              continue;
            }
            newSwitches.add(sw);
          }

          if (reachedCursor) break;
          if (page.length < 100) break; // last page
          if (pageNum >= _maxIncrementalPages) {
            throw PkImportTooLargeError(
              pagesFetched: pageNum,
              cap: _maxIncrementalPages,
            );
          }
        }

        // Sort oldest-first for chronological diff sweep.
        newSwitches.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        debugPrint('[PK_PULL] ${newSwitches.length} new switches to process');

        if (newSwitches.isNotEmpty) {
          // Re-build shortIdToUuid in case member sync updated mappings.
          final resolvedShortIdToUuid = shortIdToUuid.isEmpty
              ? await _buildShortIdToUuidMap()
              : shortIdToUuid;

          final unmappedCount = await _runDiffSweep(
            switches: newSwitches,
            shortIdToUuid: resolvedShortIdToUuid,
            prevActive: prevActive,
            onProgress: (i) {
              if (i % 50 == 0) {
                _emit(
                  _state.copyWith(
                    syncProgress:
                        0.5 +
                        0.4 *
                            (i /
                                newSwitches.length.clamp(
                                  1,
                                  newSwitches.length,
                                )),
                    syncStatus:
                        'Processing switch ${i + 1}/${newSwitches.length}...',
                  ),
                );
              }
            },
          );
          totalNew = newSwitches.length;
          totalUnmapped = unmappedCount;
        }
      } else {
        debugPrint(
          '[PK_PULL] skipped — pullEnabled=false direction=$direction',
        );
      }

      // Phase 4: scoped push.
      final int switchesPushed = direction.pushEnabled
          ? await pushPendingSwitches(onStaleLink: staleLinkMessages.add)
          : 0;

      // Push deletions with switches first.
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
      if (totalUnmapped > 0) {
        statusParts.add('$totalUnmapped switches had unmapped members');
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
          syncError: staleLinkMessages.isEmpty
              ? null
              : staleLinkMessages.join('\n'),
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
        pk.name != null &&
        pk.name!.isNotEmpty) {
      try {
        await _settingsRepository.updateSystemName(pk.name);
      } catch (e) {
        failures.add('name ($e)');
      }
    }
    if (accepted.contains(PkProfileField.description) &&
        pk.description != null &&
        pk.description!.isNotEmpty) {
      try {
        await _settingsRepository.updateSystemDescription(pk.description);
      } catch (e) {
        failures.add('description ($e)');
      }
    }
    if (accepted.contains(PkProfileField.tag) &&
        pk.tag != null &&
        pk.tag!.isNotEmpty) {
      try {
        await _settingsRepository.updateSystemTag(pk.tag);
      } catch (e) {
        failures.add('tag ($e)');
      }
    }
    if (accepted.contains(PkProfileField.avatar) &&
        pk.avatarUrl != null &&
        pk.avatarUrl!.isNotEmpty) {
      try {
        await importSystemAvatar();
      } catch (e) {
        failures.add('avatar ($e)');
      }
    }

    if (failures.isNotEmpty) {
      _emit(
        _state.copyWith(
          syncError:
              'Some profile fields did not import: '
              '${failures.join(', ')}',
        ),
      );
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
      Uint8List? avatarData;
      if (pk.avatarUrl != null && pk.avatarUrl!.isNotEmpty) {
        avatarData = await fetchAvatarBytes(pk.avatarUrl!);
      }

      try {
        final localMember = byPkUuid[pk.uuid];
        final bannerCache = await _bannerCacheService.resolve(
          PkBannerCacheInput(
            currentPkBannerUrl: localMember?.pkBannerUrl,
            currentPkBannerImageData: localMember?.pkBannerImageData,
            currentPkBannerCachedUrl: localMember?.pkBannerCachedUrl,
            hasIncomingBannerField: pk.hasBannerField,
            incomingBannerUrl: pk.bannerUrl,
          ),
        );
        if (localMember != null) {
          await _memberRepository.updateMember(
            localMember.copyWith(
              name: pk.displayName ?? pk.name,
              displayName: pk.displayName != null ? pk.name : null,
              pronouns: pk.pronouns,
              bio: pk.description,
              birthday: pk.birthday,
              customColorHex: pk.color,
              customColorEnabled: pk.color != null && pk.color!.isNotEmpty,
              proxyTagsJson: pk.proxyTagsJson ?? localMember.proxyTagsJson,
              pkBannerUrl: bannerCache.pkBannerUrl,
              pkBannerImageData: bannerCache.pkBannerImageData,
              pkBannerCachedUrl: bannerCache.pkBannerCachedUrl,
              profileHeaderSource:
                  localMember.profileHeaderSource ==
                          domain.MemberProfileHeaderSource.prism &&
                      localMember.profileHeaderImageData == null &&
                      _hasText(bannerCache.pkBannerUrl)
                  ? domain.MemberProfileHeaderSource.pluralKit
                  : localMember.profileHeaderSource,
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
              displayName: pk.displayName != null ? pk.name : null,
              pronouns: pk.pronouns,
              bio: pk.description,
              birthday: pk.birthday,
              emoji: '❔',
              isActive: true,
              createdAt: DateTime.now(),
              customColorHex: pk.color,
              customColorEnabled: pk.color != null && pk.color!.isNotEmpty,
              proxyTagsJson: pk.proxyTagsJson,
              pkBannerUrl: bannerCache.pkBannerUrl,
              profileHeaderSource: _hasText(bannerCache.pkBannerUrl)
                  ? domain.MemberProfileHeaderSource.pluralKit
                  : domain.MemberProfileHeaderSource.prism,
              pkBannerImageData: bannerCache.pkBannerImageData,
              pkBannerCachedUrl: bannerCache.pkBannerCachedUrl,
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

  // -- Phase 4B: diff sweep -------------------------------------------------

  /// Build a map from PK short ID (5-char) → PK full UUID for all locally
  /// stored members. Used by [_runDiffSweep] to resolve switch member lists.
  ///
  /// The canonical key for deterministic ID derivation is the full PK UUID
  /// (pluralkitUuid on the member row), not the short 5-char ID. PK switch
  /// payloads list short IDs; we resolve through this map.
  Future<Map<String, String>> _buildShortIdToUuidMap() async {
    final members = await _memberRepository.getAllMembers();
    final map = <String, String>{};
    for (final m in members) {
      if (m.pluralkitId != null && m.pluralkitUuid != null) {
        map[m.pluralkitId!] = m.pluralkitUuid!;
      }
    }
    return map;
  }

  /// Build a map from PK full UUID → local Prism member ID.
  Future<Map<String, String>> _buildUuidToLocalIdMap() async {
    final members = await _memberRepository.getAllMembers();
    final map = <String, String>{};
    for (final m in members) {
      if (m.pluralkitUuid != null) {
        map[m.pluralkitUuid!] = m.id;
      }
    }
    return map;
  }

  /// Paginate the full PK switch history and return all switches sorted
  /// oldest-first. Used by [performFullImport].
  Future<List<PKSwitch>> _fetchAllSwitches(PluralKitClient client) async {
    final allSwitches = <PKSwitch>[];
    DateTime? pageBefore;
    while (true) {
      final page = await client.getSwitches(before: pageBefore, limit: 100);
      if (page.isEmpty) break;
      allSwitches.addAll(page);
      pageBefore = page.last.timestamp;
      if (page.length < 100) break;
    }
    // PK returns newest-first; sort oldest-first for the diff sweep.
    allSwitches.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return allSwitches;
  }

  Future<_PkFullImportRun> _runFullImportWithClient(
    PluralKitClient client, {
    required bool updateSyncState,
  }) async {
    // -- Members (0-10%) --
    final system = await client.getSystem();
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

    // -- Groups (10-15%) --
    _emit(
      _state.copyWith(syncProgress: 0.10, syncStatus: 'Importing groups...'),
    );
    await _importGroups(client, overwriteMetadata: true);
    _emit(_state.copyWith(syncProgress: 0.15));

    // -- Build member resolution maps --
    final shortIdToUuid = await _buildShortIdToUuidMap();
    if (shortIdToUuid.isEmpty && pkMembers.isNotEmpty) {
      throw StateError(
        'No PluralKit members resolved to local members. '
        'Ensure members are imported before importing fronting history.',
      );
    }

    // -- Reset the sweep cursor so we fetch from the beginning of history.
    if (updateSyncState) {
      await _syncDao.upsertSyncState(
        const PluralKitSyncStateCompanion(
          id: Value('pk_config'),
          switchCursorTimestamp: Value(null),
          switchCursorId: Value(null),
        ),
      );
    }

    // -- Switches (15-95%): fetch all pages first so we know the canonical
    // PK row set the API agrees on.
    _emit(
      _state.copyWith(syncProgress: 0.15, syncStatus: 'Fetching switches...'),
    );

    final allSwitches = await _fetchAllSwitches(client);
    final totalSwitches = allSwitches.length;

    // -- Canonicalize: tombstone PK-linked rescue rows the API
    // wouldn't create. The PRISM1 rescue importer fans out every
    // legacy PK switch/member row (one row per (switch, member) pair
    // in the file), but the diff sweep only writes ENTRANT rows
    // (one per "this member became active at this switch"). For a
    // history A -> A+B -> A the rescue creates 4 rows but the diff
    // sweep would only create 2: A entering at sw-1 stays open
    // across A+B and back to A; B enters at sw-2 and leaves at sw-3.
    // The 2 stale A rows at det(sw-2, A) and det(sw-3, A) are
    // rescue artifacts the diff sweep never touches.
    //
    // On the corrective re-import the API is authoritative for API-backed
    // switch rows: any API-linked local row whose id isn't an entrant
    // (sw, member) pair is a stale rescue artifact and must be tombstoned
    // so paired devices converge. Synthetic/file-origin IDs are not API
    // switch refs and must not be canonicalized here.
    _emit(
      _state.copyWith(
        syncProgress: 0.40,
        syncStatus: 'Canonicalizing PK history...',
      ),
    );
    final canonicalIds = <String>{};
    {
      // Resolve canonical entrant ids in (switchId, localMemberId) space —
      // exactly what the diff sweep writes — via the shared
      // [deriveCanonicalPkSessionId] helper. Routing both call sites through
      // one helper guarantees the canonicalization pass and the live diff
      // sweep agree byte-for-byte on the row id, so we can never tombstone
      // a row the sweep just wrote (WS3 step 9 / review finding #8).
      final uuidToLocalIdForCanon = await _buildUuidToLocalIdMap();
      final pkUuidByLocalId = <String, String>{
        for (final entry in uuidToLocalIdForCanon.entries)
          entry.value: entry.key,
      };
      final prevActive = <String>{};
      for (final sw in allSwitches) {
        final newActive = <String>{};
        for (final shortId in sw.members) {
          final pkUuid = shortIdToUuid[shortId];
          if (pkUuid == null) continue;
          final localId = uuidToLocalIdForCanon[pkUuid];
          if (localId == null) continue;
          newActive.add(localId);
        }
        for (final entrantLocalId in newActive.difference(prevActive)) {
          canonicalIds.add(deriveCanonicalPkSessionId(
            switchId: sw.id,
            localMemberId: entrantLocalId,
            pkUuidByLocalId: pkUuidByLocalId,
          ));
        }
        prevActive
          ..clear()
          ..addAll(newActive);
      }
    }
    final allSessions = await _frontingSessionRepository.getAllSessions();
    var tombstonedStale = 0;
    for (final s in allSessions) {
      if (isPluralKitSwitchUuid(s.pluralkitUuid) &&
          !s.isDeleted &&
          !canonicalIds.contains(s.id)) {
        await _frontingSessionRepository.deleteSession(s.id);
        tombstonedStale++;
      }
    }
    if (tombstonedStale > 0) {
      debugPrint(
        '[PK_FULL_IMPORT] tombstoned $tombstonedStale stale PK-linked '
        'rows not in canonical API set (rescue fan-out artifacts).',
      );
    }

    _emit(
      _state.copyWith(
        syncProgress: 0.50,
        syncStatus: 'Processing $totalSwitches switches...',
      ),
    );

    // Diff sweep in corrective mode. prevActive starts empty (full
    // re-import path; any leftover open PK-linked rows are either
    // canonical entrants this sweep will reopen via the corrective
    // collision branch, which clobbers end_time, or were tombstoned
    // above as stale).
    final unmappedCount = await _runDiffSweep(
      switches: allSwitches,
      shortIdToUuid: shortIdToUuid,
      prevActive: {},
      corrective: true,
      advanceCursor: updateSyncState,
      onProgress: (i) {
        if (i % 50 == 0) {
          final progress =
              0.50 + (0.45 * (i / (totalSwitches.clamp(1, totalSwitches))));
          _emit(
            _state.copyWith(
              syncProgress: progress,
              syncStatus: 'Processing switch ${i + 1}/$totalSwitches...',
            ),
          );
        }
      },
    );

    DateTime? complete;
    if (updateSyncState) {
      // -- Complete (95-100%) --
      complete = DateTime.now();
      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          lastSyncDate: Value(complete),
        ),
      );
    }

    return _PkFullImportRun(
      system: system,
      members: pkMembers,
      totalSwitches: totalSwitches,
      unmappedMemberReferences: unmappedCount,
      completedAt: complete,
    );
  }

  /// Fetch enough API switch pages to cover the export's timestamp range,
  /// plus any newer API switches that indicate the file is stale.
  Future<List<PKSwitch>> _fetchSwitchesForFileRange(
    PluralKitClient client,
    List<PkFileSwitch> fileSwitches,
  ) async {
    if (fileSwitches.isEmpty) return const <PKSwitch>[];

    final minFileTimestampMicros = fileSwitches
        .map((entry) => entry.timestamp.toUtc().microsecondsSinceEpoch)
        .reduce((left, right) => left < right ? left : right);

    final switches = <PKSwitch>[];
    DateTime? pageBefore;
    while (true) {
      final page = await client.getSwitches(before: pageBefore, limit: 100);
      if (page.isEmpty) break;

      var pageReachedBeforeFileRange = false;
      for (final switchEntry in page) {
        final timestampMicros = switchEntry.timestamp
            .toUtc()
            .microsecondsSinceEpoch;
        if (timestampMicros >= minFileTimestampMicros) {
          switches.add(switchEntry);
        } else {
          pageReachedBeforeFileRange = true;
        }
      }

      if (pageReachedBeforeFileRange || page.length < 100) break;
      pageBefore = page.last.timestamp;
    }

    switches.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return switches;
  }

  String _pkFileSwitchSourceId(PkFileSwitch switchEntry) {
    final explicitId = switchEntry.id?.trim();
    if (explicitId != null && explicitId.isNotEmpty) return explicitId;

    final timestamp = DateTime.fromMicrosecondsSinceEpoch(
      switchEntry.timestamp.toUtc().microsecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
    final memberIds = switchEntry.memberIds.toSet().toList()..sort();
    return 'pkfile:v1:$timestamp|${memberIds.join(',')}';
  }

  /// Core diff-sweep algorithm. Processes [switches] in chronological order,
  /// computing per-member presence intervals from the snapshot stream.
  ///
  /// Algorithm (spec §2.6):
  ///   prevActive = {local member IDs currently active in open PK rows}
  ///   for each switch in chronological order:
  ///     newActive = {local member IDs in switch.members}
  ///     for each entrant in newActive - prevActive:
  ///       open a new per-member row (id derived from entry-switch + member UUID)
  ///     for each leaver in prevActive - newActive:
  ///       close the open row at switch.timestamp
  ///     prevActive = newActive
  ///   advance resume cursor once at end of the batch to (newest.ts, newest.id)
  ///
  /// Each switch's row writes commit in a single Drift transaction (atomic).
  /// The resume cursor advances ONCE after the batch loop succeeds (WS3 step 7),
  /// not per switch — so a partial-batch crash leaves the cursor at the prior
  /// boundary and the sweep re-processes from there. Re-processing is safe
  /// because row ids are deterministic and the upsert is idempotent.
  ///
  /// Returns the count of switch member references that couldn't be resolved
  /// to a local member (i.e., the PK short ID has no matching local member).
  ///
  /// [corrective] selects the end_time policy on entrant collisions:
  /// - `false` (incremental): conservative — preserve any pre-existing
  ///   non-null `end_time`, since it may be a deliberate user close on a
  ///   rescue row. Used by the routine diff sweep + post-mapping pull.
  /// - `true` (corrective full re-import): API is authoritative — clear
  ///   `end_time` to `null` on entrant collisions so currently-active API
  ///   rows actually surface as open after the rescue→re-import recovery
  ///   flow. The user has explicitly asked to rebuild PK history from API,
  ///   so clobber is the point. See codex pass 2 #B-NEW2.
  Future<int> _runDiffSweep({
    required List<PKSwitch> switches,
    required Map<String, String> shortIdToUuid,
    required Set<String> prevActive,
    void Function(int index)? onProgress,
    bool corrective = false,
    bool advanceCursor = true,
    String? pkImportSource,
    Map<String, String> pkImportSourceByApiSwitchId = const <String, String>{},
    Map<String, String> pkFileSwitchIdsByApiSwitchId = const <String, String>{},
  }) async {
    final uuidToLocalId = await _buildUuidToLocalIdMap();
    // Forward map: local member id → PK UUID. Built once and passed to the
    // unified [deriveCanonicalPkSessionId] helper. Rebuilding mid-sweep
    // would defeat the determinism contract guarded by the assert below.
    // Replaces the previous per-entrant `_localIdToPkUuid` reverse scan.
    final pkUuidByLocalId = <String, String>{
      for (final entry in uuidToLocalId.entries) entry.value: entry.key,
    };

    // Track active PluralKit presence by local member ID. Each entry is a
    // [_PkActivePresence] snapshot — see the class docstring for why we
    // moved off the previous `Map<String, String> openRowIds`.
    //
    // The keys of this map ARE the running prev-active set; we recompute
    // entrants/leavers off `active.keys` each switch. The DB-rebuild
    // pre-loop below populates one entry per currently-open PK row, and
    // the entrant/leaver paths below add and remove entries.
    final active = <String, _PkActivePresence>{};

    // Populate `active` from the database (for crash-resume on incremental).
    // For full re-import, all open rows were pre-closed so this starts empty.
    if (prevActive.isNotEmpty) {
      final currentSessions = await _frontingSessionRepository.getAllSessions();
      for (final s in currentSessions) {
        if (s.endTime == null &&
            isPluralKitSwitchUuid(s.pluralkitUuid) &&
            !s.isDeleted &&
            s.memberId != null) {
          final localId = s.memberId!;
          active[localId] = _PkActivePresence(
            localMemberId: localId,
            // Reverse-map at rebuild time. May be null if the member's
            // PK mapping was dropped between writes — that's fine for
            // E1; only E2 readers will care.
            pkMemberUuid: pkUuidByLocalId[localId],
            startedAt: s.startTime,
            rowId: s.id,
          );
        }
      }
    }

    int unmappedCount = 0;

    // Track newest successfully-processed switch in memory; advance the resume
    // cursor once after the loop succeeds (WS3 step 7). Per-switch cursor
    // writes were unnecessary (deterministic ids make replay safe) and made
    // every switch a separate `pluralkit_sync_state` upsert.
    DateTime? batchNewestTs;
    String? batchNewestId;

    for (var i = 0; i < switches.length; i++) {
      final sw = switches[i];
      onProgress?.call(i);

      // Resolve this switch's member list to local member IDs.
      // Also track which short IDs couldn't be resolved for reporting.
      final newActive = <String>{};
      int switchUnmapped = 0;
      for (final shortId in sw.members) {
        final pkUuid = shortIdToUuid[shortId];
        if (pkUuid == null) {
          switchUnmapped++;
          continue;
        }
        final localId = uuidToLocalId[pkUuid];
        if (localId == null) {
          switchUnmapped++;
          continue;
        }
        newActive.add(localId);
      }
      unmappedCount += switchUnmapped;

      // `active` carries the running prev-active set as its key space. The
      // first iteration's keys come from the DB-rebuild block above (or
      // are empty for full re-import); subsequent iterations see whatever
      // the previous iteration's entrant/leaver block left behind.
      final prevActiveKeys = active.keys.toSet();
      final entrants = newActive.difference(prevActiveKeys);
      final leavers = prevActiveKeys.difference(newActive);

      // Atomic transaction: opens + closes for this switch.
      await _syncDao.attachedDatabase.transaction(() async {
        // Open rows for entrants.
        //
        // We branch on existing-row presence rather than catching a
        // unique-constraint violation because the existing row may be
        // a PRISM1 rescue import with lossy boundaries (one row per
        // old switch covering its full duration). We MUST overwrite
        // start_time + member_id + pluralkit_uuid with the API truth
        // so a future sync's field-LWW carries the corrected boundary
        // to paired devices. The previous `createSession`-then-catch
        // pattern recorded the row id but never wrote the API values,
        // leaving rescue-derived boundaries on disk forever.
        for (final localId in entrants) {
          // Derive the row id via the shared helper so this site and the
          // canonicalization pass agree on the id (WS3 step 9 / #8).
          final rowId = deriveCanonicalPkSessionId(
            switchId: sw.id,
            localMemberId: localId,
            pkUuidByLocalId: pkUuidByLocalId,
          );
          // Debug-only invariant: the derived id is stable for a given
          // (switchId, localMemberId) regardless of map state, so long as
          // pkUuidByLocalId either contains the same mapping or is missing
          // the local id. Re-deriving against an empty map must equal
          // re-deriving against the full map IFF the local id is absent
          // from the full map; otherwise the two derivations differ on
          // purpose (the fallback only applies to unmapped ids). We assert
          // the more useful invariant: re-derivation against the SAME map
          // is idempotent.
          assert(
            deriveCanonicalPkSessionId(
                  switchId: sw.id,
                  localMemberId: localId,
                  pkUuidByLocalId: pkUuidByLocalId,
                ) ==
                rowId,
            'deriveCanonicalPkSessionId is non-deterministic for '
            '(${sw.id}, $localId) — id derivation contract broken.',
          );
          final switchImportSource =
              pkImportSourceByApiSwitchId[sw.id] ?? pkImportSource;
          final pkFileSwitchId = pkFileSwitchIdsByApiSwitchId[sw.id];
          final openRowId = await _upsertEntrantSession(
            rowId: rowId,
            switchEntry: sw,
            localId: localId,
            corrective: corrective,
            switchImportSource: switchImportSource,
            pkFileSwitchId: pkFileSwitchId,
          );
          if (openRowId == null) {
            // Tombstoned-row collision: the entrant's deterministic row id
            // pointed at a soft-deleted row, so we (correctly) didn't write
            // a fronting-session row for this presence. We still record the
            // member as active — without a rowId — so a future leaver event
            // has a peg to match against and so the prev-active key set
            // stays in sync with the loop's view of who is fronting.
            //
            // TODO(PR-E2): use isTombstonedCollision to actually reopen or
            // re-derive a row for this presence so it isn't dropped from
            // history (review findings #7 / #33).
            active[localId] = _PkActivePresence(
              localMemberId: localId,
              pkMemberUuid: pkUuidByLocalId[localId],
              startedAt: sw.timestamp,
              isTombstonedCollision: true,
            );
            continue;
          }
          active[localId] = _PkActivePresence(
            localMemberId: localId,
            pkMemberUuid: pkUuidByLocalId[localId],
            startedAt: sw.timestamp,
            rowId: openRowId,
          );
        }

        // Close rows for leavers.
        for (final localId in leavers) {
          final presence = active[localId];
          final rowId = presence?.rowId;
          if (rowId != null) {
            await _frontingSessionRepository.endSession(rowId, sw.timestamp);
          }
          // Always drop the presence: with no rowId there's nothing to
          // close, but the member is no longer active either way. This
          // matches the prior behavior where leavers were unconditionally
          // removed from `prevActive` via `prevActive = newActive`.
          active.remove(localId);
        }
      });

      // Track newest (timestamp, id) we've seen for the batch-end cursor
      // write. Switches are sorted oldest-first, so the last one wins —
      // but we compare lexicographically anyway in case a caller hands us
      // an unsorted list.
      if (batchNewestTs == null ||
          sw.timestamp.isAfter(batchNewestTs) ||
          (sw.timestamp == batchNewestTs &&
              (batchNewestId == null || sw.id.compareTo(batchNewestId) > 0))) {
        batchNewestTs = sw.timestamp;
        batchNewestId = sw.id;
      }

      // `active` already reflects newActive after the entrant + leaver
      // blocks above — the previous `prevActive = newActive` reassignment
      // is no longer needed now that `active.keys` is the single source
      // of truth for "who is fronting going into the next switch".
    }

    if (advanceCursor && batchNewestTs != null && batchNewestId != null) {
      // One cursor write per batch (WS3 step 7).
      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          switchCursorTimestamp: Value(batchNewestTs),
          switchCursorId: Value(batchNewestId),
        ),
      );
    }

    debugPrint(
      '[PK_SWEEP] done: ${switches.length} switches processed, '
      '$unmappedCount unmapped member references',
    );
    return unmappedCount;
  }

  Future<String?> _upsertEntrantSession({
    required String rowId,
    required PKSwitch switchEntry,
    required String localId,
    required bool corrective,
    required String? switchImportSource,
    required String? pkFileSwitchId,
  }) async {
    var existing =
        await _frontingSessionRepository.getSessionById(rowId) ??
        await _findSessionByPkSwitchAndMember(
          switchId: switchEntry.id,
          localId: localId,
        );

    if (existing == null) {
      try {
        await _frontingSessionRepository.createSession(
          domain.FrontingSession(
            id: rowId,
            startTime: switchEntry.timestamp,
            memberId: localId,
            pluralkitUuid: switchEntry.id,
            pkImportSource: switchImportSource,
            pkFileSwitchId: pkFileSwitchId,
          ),
        );
        return rowId;
      } catch (error) {
        if (!isUniqueOrPrimaryKeyConstraintViolation(error)) rethrow;
        existing =
            await _frontingSessionRepository.getSessionById(rowId) ??
            await _findSessionByPkSwitchAndMember(
              switchId: switchEntry.id,
              localId: localId,
            );
        if (existing == null) rethrow;
      }
    }

    // Collision — usually a PRISM1 rescue row. It may have the new
    // deterministic id, or it may be an older PK-imported row whose id
    // predates the per-member derivation. Correct by the DB uniqueness key
    // `(pluralkit_uuid, member_id)` so re-import is idempotent in both cases.
    if (existing.isDeleted && !corrective) {
      debugPrint(
        '[PK_SWEEP] entrant collision on deleted row ${existing.id}: '
        'preserved tombstone during incremental sync.',
      );
      return null;
    }

    if (!corrective && existing.endTime != null) {
      debugPrint(
        '[PK_SWEEP] entrant collision on ${existing.id}: existing '
        'end_time ${existing.endTime} preserved (API says fronting; user '
        'may have closed the rescue row).',
      );
    }

    // end_time policy depends on [corrective]:
    // - incremental (default): preserve a non-null existing end_time.
    // - corrective: API is authoritative. Clear end_time so active API rows
    //   surface as open; a later leaver in the same sweep will close it.
    //
    // Corrective import also clears delete-push bookkeeping because a
    // resurrected PK row is no longer a pending local deletion.
    await _frontingSessionRepository.updateSession(
      existing.copyWith(
        isDeleted: corrective ? false : existing.isDeleted,
        startTime: switchEntry.timestamp,
        memberId: localId,
        pluralkitUuid: switchEntry.id,
        pkImportSource: switchImportSource ?? existing.pkImportSource,
        pkFileSwitchId: switchImportSource == null
            ? existing.pkFileSwitchId
            : pkFileSwitchId,
        endTime: corrective ? null : existing.endTime,
        deleteIntentEpoch: corrective ? null : existing.deleteIntentEpoch,
        deletePushStartedAt: corrective ? null : existing.deletePushStartedAt,
      ),
    );
    return existing.id;
  }

  Future<domain.FrontingSession?> _findSessionByPkSwitchAndMember({
    required String switchId,
    required String localId,
  }) async {
    final db = _syncDao.attachedDatabase;
    final row =
        await (db.select(db.frontingSessions)
              ..where(
                (s) =>
                    s.pluralkitUuid.equals(switchId) &
                    s.memberId.equals(localId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : FrontingSessionMapper.toDomain(row);
  }

  /// Walk PK switch history after a mapping Apply and import every switch.
  ///
  /// This is the entry point used after the user completes the mapping flow
  /// (see [importSwitchesAfterLink]). It uses the incremental diff sweep
  /// starting from the current resume cursor, so it's safe to call multiple
  /// times (idempotent via deterministic IDs and atomic cursor advance).
  Future<void> importSwitchesAfterLink() async {
    if (!_state.isConnected) {
      throw StateError('Not connected — cannot import switch history');
    }
    if (_state.isSyncing) return;
    _emit(
      _state.copyWith(
        isSyncing: true,
        syncProgress: 0.0,
        syncStatus: 'Fetching PK switch history...',
        clearError: true,
      ),
    );

    final client = await _buildClient();
    if (client == null) {
      _emit(_state.copyWith(isSyncing: false));
      throw StateError('Not connected');
    }

    try {
      final shortIdToUuid = await _buildShortIdToUuidMap();

      // Fetch all switches from the beginning (this is the post-mapping full
      // history pull). Use the corrective full-sweep path: no pre-close needed
      // since the DB was empty (or will have no PK rows yet after mapping).
      final allSwitches = await _fetchAllSwitches(client);

      _emit(
        _state.copyWith(
          syncProgress: 0.5,
          syncStatus: 'Processing ${allSwitches.length} switches...',
        ),
      );

      // Reconstitute prevActive from currently-open PK-linked rows.
      final currentSessions = await _frontingSessionRepository.getAllSessions();
      final prevActive = <String>{
        for (final s in currentSessions)
          if (s.endTime == null &&
              isPluralKitSwitchUuid(s.pluralkitUuid) &&
              !s.isDeleted &&
              s.memberId != null)
            s.memberId!,
      };

      await _runDiffSweep(
        switches: allSwitches,
        shortIdToUuid: shortIdToUuid,
        prevActive: prevActive,
        onProgress: (i) {
          if (i % 50 == 0) {
            final frac = allSwitches.isEmpty
                ? 1.0
                : 0.5 + 0.4 * (i / allSwitches.length);
            _emit(
              _state.copyWith(
                syncProgress: frac,
                syncStatus:
                    'Importing switch ${i + 1}/${allSwitches.length}...',
              ),
            );
          }
        },
      );

      // Phase 1 R3 — insert-only re-attribution pass for PK groups.
      final importer = _groupsImporter;
      if (importer != null) {
        try {
          await importer.reattribute(client);
        } catch (e) {
          debugPrint('[PK] group reattribute failed: $e');
        }
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: 'Imported ${allSwitches.length} switches.',
        ),
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          syncError: 'Switch history import failed: $e',
        ),
      );
      rethrow;
    } finally {
      client.dispose();
    }
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
    final candidates = await _frontingSessionRepository
        .getDeletedLinkedSessions();
    if (candidates.isEmpty) return 0;

    final push = pushServiceOverride ?? const PkPushService();
    int deleted = 0;

    for (final session in candidates) {
      // R6: cross-device coordination stamp.
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
      } else {
        await _frontingSessionRepository.stampDeletePushStartedAt(
          session.id,
          nowMs,
        );
      }

      // R2: re-read and re-check every invariant at execution time.
      final fresh = await _frontingSessionRepository.getSessionById(session.id);
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
      // R1: epoch gate.
      final intentEpoch = session.deleteIntentEpoch;
      if (intentEpoch != currentEpoch) {
        debugPrint(
          '[PK] Session ${session.id} intent epoch $intentEpoch != current '
          '$currentEpoch; aborting DELETE (stale link).',
        );
        continue;
      }

      final pkUuid = fresh.pluralkitUuid!;
      if (!isPluralKitSwitchUuid(pkUuid)) {
        debugPrint(
          '[PK] Session ${session.id} has non-API pluralkit_uuid=$pkUuid; '
          'clearing local link without DELETE.',
        );
        await _frontingSessionRepository.clearPluralKitLink(session.id);
        continue;
      }
      try {
        await push.pushSwitchDeletion(session.id, pkUuid.trim(), client);
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
      if (s.isDeleted) continue;
      if (!isPluralKitSwitchUuid(s.pluralkitUuid)) continue;
      final mid = s.memberId;
      if (mid != null) membersWithLiveLinkedSessions.add(mid);
    }

    final push = pushServiceOverride ?? const PkPushService();
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
      if (fresh.pluralkitId == null ||
          fresh.pluralkitId != member.pluralkitId) {
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
  Future<int> pushPendingSwitches({
    PkPushService? pushService,
    void Function(String message)? onStaleLink,
  }) async {
    if (!_state.isConnected) {
      throw StateError('Not connected — cannot push switches');
    }
    final linkedAt = _state.linkedAt;
    if (linkedAt == null) {
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
        if (session.pkImportSource == pkImportSourceFile) continue;
        if (session.pluralkitUuid != null) continue;
        if (!session.startTime.isAfter(linkedAt)) continue;
        final memberId = session.memberId;
        if (memberId == null) continue;
        final pkPrimary = localIdToPkId[memberId];
        if (pkPrimary == null) continue; // fronter isn't linked

        // Per-member sessions: push as single-member switch.
        final pkMemberIds = <String>[pkPrimary];

        String? createdUuid;
        try {
          final created = await push.pushSwitch(
            pkMemberIds,
            client,
            timestamp: session.startTime,
          );
          createdUuid = created.id;

          if (session.endTime != null) {
            await push.pushSwitch(const [], client, timestamp: session.endTime);
          }

          await _frontingSessionRepository.updateSession(
            session.copyWith(pluralkitUuid: createdUuid),
          );
          pushed++;
        } on PkStaleLinkException catch (e) {
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

  /// Lightweight poll: GET /systems/@me/fronters and only trigger a full
  /// `syncRecentData` ingest when the current PK switch id isn't already
  /// stored on any local session. Designed for periodic foreground polling
  /// — honors rate limits via the client's request queue and no-ops when
  /// auto-sync isn't ready.
  ///
  /// Returns true when the full ingest path ran (switch was new), false
  /// otherwise. Errors are swallowed with a debugPrint.
  Future<bool> pollFrontersOnly() async {
    if (!_state.canAutoSync) return false;
    if (_state.isSyncing) return false;
    final client = await _buildClient();
    if (client == null) return false;

    try {
      final PKSwitch? current = await client.getCurrentFronters();
      if (current == null) return false;

      // If we've already ingested this switch, skip the heavier path.
      final sessions = await _frontingSessionRepository.getAllSessions();
      final seen = sessions.any((s) => s.pluralkitUuid == current.id);
      if (seen) return false;

      await syncRecentData(
        isManual: false,
        direction: PkSyncDirection.pullOnly,
      );
      return true;
    } catch (e) {
      debugPrint('[PK] pollFrontersOnly failed: $e');
      return false;
    } finally {
      client.dispose();
    }
  }
}
