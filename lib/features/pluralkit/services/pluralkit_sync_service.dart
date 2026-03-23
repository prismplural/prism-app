import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/services/secure_storage.dart'
    as storage_config;
import 'package:prism_plurality/core/database/app_database.dart';
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
  final DateTime? lastSyncDate;
  final DateTime? lastManualSyncDate;

  const PluralKitSyncState({
    this.isSyncing = false,
    this.syncProgress = 0.0,
    this.syncStatus = '',
    this.syncError,
    this.isConnected = false,
    this.lastSyncDate,
    this.lastManualSyncDate,
  });

  PluralKitSyncState copyWith({
    bool? isSyncing,
    double? syncProgress,
    String? syncStatus,
    String? syncError,
    bool clearError = false,
    bool? isConnected,
    DateTime? lastSyncDate,
    DateTime? lastManualSyncDate,
  }) {
    return PluralKitSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: syncProgress ?? this.syncProgress,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: clearError ? null : (syncError ?? this.syncError),
      isConnected: isConnected ?? this.isConnected,
      lastSyncDate: lastSyncDate ?? this.lastSyncDate,
      lastManualSyncDate: lastManualSyncDate ?? this.lastManualSyncDate,
    );
  }

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

  PluralKitSyncState _state = const PluralKitSyncState();
  SyncStateCallback? onStateChanged;

  PluralKitSyncService({
    required MemberRepository memberRepository,
    required FrontingSessionRepository frontingSessionRepository,
    required PluralKitSyncDao syncDao,
    FlutterSecureStorage? secureStorage,
  }) : _memberRepository = memberRepository,
       _frontingSessionRepository = frontingSessionRepository,
       _syncDao = syncDao,
       _secureStorage =
           secureStorage ?? storage_config.secureStorage,
       _uuid = const Uuid();

  PluralKitSyncState get state => _state;

  void _emit(PluralKitSyncState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  // -- helpers --------------------------------------------------------------

  Future<String?> _getToken() => _secureStorage.read(key: _pkTokenKey);

  Future<PluralKitClient?> _buildClient() async {
    final token = await _getToken();
    if (token == null) return null;
    return PluralKitClient(token: token);
  }

  // -- public API -----------------------------------------------------------

  /// Build a PK client if connected. Exposed for use by auto-push.
  Future<PluralKitClient?> buildClientIfConnected() async {
    if (!_state.isConnected) return null;
    return _buildClient();
  }

  /// Load persisted sync state from the database.
  Future<void> loadState() async {
    final row = await _syncDao.getSyncState();
    _emit(
      _state.copyWith(
        isConnected: row.isConnected,
        lastSyncDate: row.lastSyncDate,
        lastManualSyncDate: row.lastManualSyncDate,
      ),
    );
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
      final client = PluralKitClient(token: trimmed);
      final system = await client.getSystem();
      client.dispose();

      await _syncDao.upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value('pk_config'),
          systemId: Value(system.id),
          isConnected: const Value(true),
        ),
      );

      _emit(_state.copyWith(isConnected: true, clearError: true));
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
  Future<void> clearToken() async {
    await _secureStorage.delete(key: _pkTokenKey);
    await _syncDao.upsertSyncState(
      const PluralKitSyncStateCompanion(
        id: Value('pk_config'),
        systemId: Value(null),
        isConnected: Value(false),
        lastSyncDate: Value(null),
        lastManualSyncDate: Value(null),
      ),
    );
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
        );

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
        DateTime? pageBefore;
        bool done = false;

        while (!done) {
          final page = await client.getSwitches(before: pageBefore);
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
            );
            if (!isDuplicate) totalNew++;
          }

          if (page.length < 100) break;
          pageBefore = page.last.timestamp;
        }
      }

      // -- Push current front as a switch (if push enabled) --
      int switchesPushed = 0;
      if (direction.pushEnabled) {
        _emit(
          _state.copyWith(
            syncProgress: 0.8,
            syncStatus: 'Pushing local changes...',
          ),
        );

        try {
          final activeSessions =
              await _frontingSessionRepository.getActiveSessions();
          if (activeSessions.isNotEmpty) {
            final pushService = PkPushService();
            // Batch-fetch to avoid N+1 queries
            final allMembersForPush = await _memberRepository.getAllMembers();
            final memberByIdMap = {for (final m in allMembersForPush) m.id: m};
            final pkMemberIds = <String>[];
            for (final session in activeSessions) {
              if (session.memberId == null) continue;
              final member = memberByIdMap[session.memberId!];
              if (member?.pluralkitId != null) {
                pkMemberIds.add(member!.pluralkitId!);
              }
            }
            if (pkMemberIds.isNotEmpty) {
              await pushService.pushSwitch(pkMemberIds, client);
              switchesPushed = 1;
            }
          }
        } catch (_) {
          // Non-fatal — we still count the pull as successful
        }
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
      );

      final statusParts = <String>[];
      if (finalSummary.membersPushed > 0) {
        statusParts.add('Pushed ${finalSummary.membersPushed} members');
      }
      if (totalNew > 0) {
        statusParts.add('Pulled $totalNew switches');
      }
      if (switchesPushed > 0) {
        statusParts.add('Pushed current front');
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          syncProgress: 1.0,
          syncStatus: statusParts.isNotEmpty
              ? '${statusParts.join('. ')}.'
              : 'Everything is up to date.',
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
  Future<bool> _importSwitch(
    PKSwitch sw, {
    DateTime? endTime,
    required Map<String, String> pkIdToLocalId,
  }) async {
    // Check for existing session with same PK UUID
    // (We use the PK switch ID as the pluralkitUuid on fronting sessions)
    final existing = await _frontingSessionRepository.getAllSessions();
    final isDuplicate = existing.any((s) => s.pluralkitUuid == sw.id);
    if (isDuplicate) return true;

    // Find the primary fronter (first member in list)
    String? primaryMemberId;
    final coFronterLocalIds = <String>[];

    for (var i = 0; i < sw.members.length; i++) {
      final localId = pkIdToLocalId[sw.members[i]];
      if (localId == null) continue;

      if (i == 0) {
        primaryMemberId = localId;
      } else {
        coFronterLocalIds.add(localId);
      }
    }

    // Skip switches with no mapped members
    if (primaryMemberId == null && sw.members.isNotEmpty) return false;

    await _frontingSessionRepository.createSession(
      domain.FrontingSession(
        id: _uuid.v4(),
        startTime: sw.timestamp,
        endTime: endTime,
        memberId: primaryMemberId,
        coFronterIds: coFronterLocalIds,
        pluralkitUuid: sw.id,
      ),
    );

    return false;
  }
}
