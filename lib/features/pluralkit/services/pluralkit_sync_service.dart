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
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_bidirectional_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

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

/// Core PluralKit synchronization logic.
///
/// Designed to be driven by a Riverpod notifier that passes a
/// [SyncStateCallback] so the notifier can update its state.
class PluralKitSyncService {
  final MemberRepository _memberRepository;
  final FrontingSessionRepository _frontingSessionRepository;
  final PluralKitSyncDao _syncDao;
  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;
  final PluralKitClient Function(String token)? _clientFactory;
  final String? _tokenOverride;

  PluralKitSyncState _state = const PluralKitSyncState();
  SyncStateCallback? onStateChanged;

  PluralKitSyncService({
    required MemberRepository memberRepository,
    required FrontingSessionRepository frontingSessionRepository,
    required PluralKitSyncDao syncDao,
    FlutterSecureStorage? secureStorage,
    PluralKitClient Function(String token)? clientFactory,
    String? tokenOverride,
  }) : _memberRepository = memberRepository,
       _frontingSessionRepository = frontingSessionRepository,
       _syncDao = syncDao,
       _secureStorage =
           secureStorage ?? storage_config.secureStorage,
       _uuid = const Uuid(),
       _clientFactory = clientFactory,
       _tokenOverride = tokenOverride;

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
    if (trimmed.isEmpty) {
      _emit(_state.copyWith(syncError: 'Token cannot be empty'));
      return;
    }

    await _secureStorage.write(key: _pkTokenKey, value: trimmed);

    try {
      final client = _makeClient(trimmed);
      final system = await client.getSystem();
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

      _emit(_state.copyWith(
        isConnected: true,
        needsMapping: true,
        linkedAt: linkedAt,
        clearError: true,
      ));
    } on PluralKitAuthError {
      await _secureStorage.delete(key: _pkTokenKey);
      _emit(
        _state.copyWith(
          isConnected: false,
          syncError: 'Invalid token — please check and try again.',
        ),
      );
    } catch (e) {
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

      final system = await client.getSystem();
      _emit(
        _state.copyWith(syncProgress: 0.3, syncStatus: 'Fetching members...'),
      );

      final pkMembers = await client.getMembers();
      _emit(
        _state.copyWith(
          syncProgress: 0.5,
          syncStatus: 'Importing ${pkMembers.length} members...',
        ),
      );

      await _importMembers(client, pkMembers);

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: 'Imported ${pkMembers.length} members.',
        ),
      );

      return (system.name, pkMembers);
    } catch (e) {
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

      // -- Switches (10-95%) --
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
      for (var i = 0; i < allSwitches.length; i++) {
        final sw = allSwitches[i];
        final endTime = i + 1 < allSwitches.length
            ? allSwitches[i + 1].timestamp
            : null;

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

      // -- Pull recent switches (same as before) --
      int totalNew = 0;
      if (direction.pullEnabled) {
        final existingSessions =
            await _frontingSessionRepository.getAllSessions();
        final existingPkUuids = <String>{
          for (final s in existingSessions)
            if (s.pluralkitUuid != null) s.pluralkitUuid!,
        };
        DateTime? pageBefore;
        bool done = false;

        while (!done) {
          final page = await client.getSwitches(before: pageBefore, limit: 100);
          if (page.isEmpty) break;

          // Sort oldest-first within this page for sequential processing
          final sorted = List<PKSwitch>.from(page)
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

          for (var i = 0; i < sorted.length; i++) {
            final sw = sorted[i];

            // Stop if we've gone past our last sync date
            if (sw.timestamp.isBefore(_state.lastSyncDate!)) {
              done = true;
              break;
            }

            final endTime = i + 1 < sorted.length
                ? sorted[i + 1].timestamp
                : null;
            final isDuplicate = await _importSwitch(
              sw,
              endTime: endTime,
              pkIdToLocalId: pkIdToLocalId,
              existingPkUuids: existingPkUuids,
            );
            if (!isDuplicate) {
              totalNew++;
              existingPkUuids.add(sw.id);
            }
          }

          if (page.length < 100) break;
          pageBefore = page.last.timestamp;
        }
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
        staleLinkMessages: List.unmodifiable(staleLinkMessages),
      );

      final statusParts = <String>[];
      if (finalSummary.membersPushed > 0) {
        statusParts.add('Pushed ${finalSummary.membersPushed} members');
      }
      if (totalNew > 0) {
        statusParts.add('Pulled $totalNew switches');
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

  // -- private helpers ------------------------------------------------------

  Future<void> _importMembers(
    PluralKitClient client,
    List<PKMember> pkMembers,
  ) async {
    final existing = await _memberRepository.getAllMembers();
    final byPkUuid = <String, domain.Member>{};
    for (final m in existing) {
      if (m.pluralkitUuid != null) {
        byPkUuid[m.pluralkitUuid!] = m;
      }
    }

    for (final pk in pkMembers) {
      Uint8List? avatarData;
      if (pk.avatarUrl != null) {
        try {
          final bytes = await client.downloadBytes(pk.avatarUrl!);
          avatarData = Uint8List.fromList(bytes);
        } catch (_) {
          // Avatar download failure is non-fatal
        }
      }

      final localMember = byPkUuid[pk.uuid];
      if (localMember != null) {
        // Update existing member
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
      } else {
        // Create new member
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
      }
    }
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

      for (var i = 0; i < allSwitches.length; i++) {
        final sw = allSwitches[i];
        final endTime =
            i + 1 < allSwitches.length ? allSwitches[i + 1].timestamp : null;
        if (i % 50 == 0) {
          _emit(_state.copyWith(
            syncProgress: allSwitches.isEmpty
                ? 1.0
                : i / allSwitches.length,
            syncStatus: 'Importing switch ${i + 1}/${allSwitches.length}...',
          ));
        }
        final wasDup = await _importSwitch(
          sw,
          endTime: endTime,
          pkIdToLocalId: pkIdToLocalId,
          existingPkUuids: existingPkUuids,
        );
        if (!wasDup) existingPkUuids.add(sw.id);
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
}
