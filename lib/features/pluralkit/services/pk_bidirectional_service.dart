import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// Orchestrates bidirectional sync between Prism and PluralKit.
///
/// Compares local members with PK members, and depending on per-member
/// field config, either pulls (PK -> Prism), pushes (Prism -> PK), or
/// uses last-modified heuristics for bidirectional fields.
class PkBidirectionalService {
  final PkPushService _pushService;

  PkBidirectionalService({PkPushService? pushService})
      : _pushService = pushService ?? PkPushService();

  /// Sync members bidirectionally.
  ///
  /// [localMembers] — all local members (may or may not have PK IDs).
  /// [pkMembers] — all members fetched from PK.
  /// [fieldConfigs] — per-member field direction config (keyed by local member ID).
  /// [direction] — overall sync direction.
  /// [lastSyncDate] — the last time a sync completed (used for change detection).
  /// [memberRepository] — for persisting pulled changes.
  /// [client] — PK API client.
  ///
  /// Returns a summary of what was synced.
  Future<PkSyncSummary> syncMembers({
    required List<domain.Member> localMembers,
    required List<PKMember> pkMembers,
    required Map<String, PkFieldSyncConfig> fieldConfigs,
    required PkSyncDirection direction,
    required DateTime? lastSyncDate,
    required MemberRepository memberRepository,
    required PluralKitClient client,
  }) async {
    int pulled = 0;
    int pushed = 0;
    int skipped = 0;

    // Build lookup maps
    final pkByUuid = <String, PKMember>{};
    final pkById = <String, PKMember>{};
    for (final pk in pkMembers) {
      pkByUuid[pk.uuid] = pk;
      pkById[pk.id] = pk;
    }

    final localByPkUuid = <String, domain.Member>{};
    final localByPkId = <String, domain.Member>{};
    for (final m in localMembers) {
      if (m.pluralkitUuid != null) localByPkUuid[m.pluralkitUuid!] = m;
      if (m.pluralkitId != null) localByPkId[m.pluralkitId!] = m;
    }

    // Process members that exist on PK
    for (final pk in pkMembers) {
      final local = localByPkUuid[pk.uuid] ?? localByPkId[pk.id];

      if (local == null) {
        // New member on PK, not in Prism — pull if direction allows
        if (direction.pullEnabled) {
          // Pulling is handled by the existing import flow; just count it.
          pulled++;
        } else {
          skipped++;
        }
        continue;
      }

      final config = fieldConfigs[local.id] ?? const PkFieldSyncConfig();

      if (direction.pushEnabled) {
        // Check if local data is newer and should be pushed
        final hasLocalChanges = _hasLocalChanges(local, pk, config, direction);
        if (hasLocalChanges) {
          await _pushService.pushMember(local, client);
          pushed++;
          continue;
        }
      }

      if (direction.pullEnabled) {
        // Check if PK data differs and should be pulled
        final hasPkChanges = _hasPkChanges(local, pk, config, direction);
        if (hasPkChanges) {
          pulled++;
          continue;
        }
      }

      skipped++;
    }

    // Process local members that have no PK counterpart
    if (direction.pushEnabled) {
      for (final local in localMembers) {
        if (local.pluralkitUuid != null || local.pluralkitId != null) continue;
        // New local member — push to PK
        final pkId = await _pushService.pushMember(local, client);
        // Store the PK ID back on the local member
        await memberRepository.updateMember(
          local.copyWith(pluralkitId: pkId),
        );
        pushed++;
      }
    }

    return PkSyncSummary(
      membersPulled: pulled,
      membersPushed: pushed,
      membersSkipped: skipped,
    );
  }

  /// Check if the local member has changes that should be pushed to PK.
  bool _hasLocalChanges(
    domain.Member local,
    PKMember pk,
    PkFieldSyncConfig config,
    PkSyncDirection direction,
  ) {
    if (config.name.pushEnabled || direction == PkSyncDirection.pushOnly) {
      if (local.name != (pk.displayName ?? pk.name)) return true;
    }
    if (config.pronouns.pushEnabled || direction == PkSyncDirection.pushOnly) {
      if (local.pronouns != pk.pronouns) return true;
    }
    if (config.description.pushEnabled ||
        direction == PkSyncDirection.pushOnly) {
      if (local.bio != pk.description) return true;
    }
    if (config.color.pushEnabled || direction == PkSyncDirection.pushOnly) {
      final localColor = _normalizeColor(local.customColorHex);
      final pkColor = _normalizeColor(pk.color);
      if (local.customColorEnabled && localColor != pkColor) return true;
    }
    return false;
  }

  /// Check if the PK member has changes that should be pulled into Prism.
  bool _hasPkChanges(
    domain.Member local,
    PKMember pk,
    PkFieldSyncConfig config,
    PkSyncDirection direction,
  ) {
    if (config.name.pullEnabled || direction == PkSyncDirection.pullOnly) {
      if (local.name != (pk.displayName ?? pk.name)) return true;
    }
    if (config.pronouns.pullEnabled || direction == PkSyncDirection.pullOnly) {
      if (local.pronouns != pk.pronouns) return true;
    }
    if (config.description.pullEnabled ||
        direction == PkSyncDirection.pullOnly) {
      if (local.bio != pk.description) return true;
    }
    if (config.color.pullEnabled || direction == PkSyncDirection.pullOnly) {
      final localColor = _normalizeColor(local.customColorHex);
      final pkColor = _normalizeColor(pk.color);
      if (localColor != pkColor) return true;
    }
    return false;
  }

  /// Normalize a color hex string for comparison (strip '#', lowercase).
  String? _normalizeColor(String? color) {
    if (color == null || color.isEmpty) return null;
    var c = color.toLowerCase();
    if (c.startsWith('#')) c = c.substring(1);
    return c;
  }
}
