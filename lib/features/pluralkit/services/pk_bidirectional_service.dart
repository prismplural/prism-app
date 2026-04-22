import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

/// Orchestrates bidirectional sync between Prism and PluralKit.
///
/// Compares local members with PK members and, per-field and per-direction,
/// either pulls (PK -> Prism, writing via `memberRepository.updateMember`)
/// or pushes (Prism -> PK, via `PkPushService`).
class PkBidirectionalService {
  final PkPushService _pushService;

  PkBidirectionalService({PkPushService? pushService})
    : _pushService = pushService ?? const PkPushService();

  /// Sync members bidirectionally.
  ///
  /// [localMembers] — all local members (may or may not have PK IDs).
  /// [pkMembers] — all members fetched from PK.
  /// [fieldConfigs] — per-member field direction config (keyed by local member ID).
  /// [direction] — overall sync direction.
  /// [lastSyncDate] — the last time a sync completed (unused here, kept for API stability).
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
          try {
            await _pushService.pushMember(local, client, pkMember: pk);
            pushed++;
            continue;
          } on PkStaleLinkException catch (_) {
            // PK deleted the linked member out from under us. Clear the link
            // so the user can re-link via the mapping screen and the next
            // sync treats this as an unlinked local member.
            await memberRepository.updateMember(
              local.copyWith(pluralkitId: null, pluralkitUuid: null),
            );
            skipped++;
            continue;
          }
        }
      }

      if (direction.pullEnabled) {
        // Apply PK-side changes to the local member.
        final applied = await _applyPkChanges(
          local,
          pk,
          config,
          direction,
          memberRepository,
        );
        if (applied) {
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
        await memberRepository.updateMember(local.copyWith(pluralkitId: pkId));
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
  ///
  /// Plan 08 "Conflict semantics on link": we never push an empty local value
  /// over a populated PK value — that would be a "null-clear on link" for any
  /// field the user hadn't set locally. Linking is supposed to be safe by
  /// default; the mapping applier pulls PK's values into default-local fields
  /// at link time (see `_applyLink`), so by the time this runs for a freshly
  /// linked member the local side already reflects PK. The null-guard here is
  /// belt-and-suspenders in case a link arrives via another path.
  bool _hasLocalChanges(
    domain.Member local,
    PKMember pk,
    PkFieldSyncConfig config,
    PkSyncDirection direction,
  ) {
    if (_pushField(config.name, direction)) {
      // name can't be null; still skip push when local is empty string.
      if (local.name != pk.name && local.name.isNotEmpty) return true;
    }
    if (_pushField(config.displayName, direction)) {
      if (local.displayName != pk.displayName &&
          !_wouldClear(local.displayName, pk.displayName)) {
        return true;
      }
    }
    if (_pushField(config.pronouns, direction)) {
      if (local.pronouns != pk.pronouns &&
          !_wouldClear(local.pronouns, pk.pronouns)) {
        return true;
      }
    }
    if (_pushField(config.description, direction)) {
      if (local.bio != pk.description &&
          !_wouldClear(local.bio, pk.description)) {
        return true;
      }
    }
    if (_pushField(config.birthday, direction)) {
      final localBd = _normalizeBirthday(local.birthday);
      final pkBd = _normalizeBirthday(pk.birthday);
      if (localBd != pkBd && !_wouldClear(localBd, pkBd)) {
        return true;
      }
    }
    if (_pushField(config.color, direction)) {
      // When local has no color enabled, don't sync color either way —
      // toggling local color off must not silently clear PK's color.
      if (local.customColorEnabled) {
        final localColor = _normalizeColor(local.customColorHex);
        final pkColor = _normalizeColor(pk.color);
        if (localColor != pkColor && !_wouldClear(localColor, pkColor)) {
          return true;
        }
      }
    }
    return false;
  }

  /// True when pushing would amount to null-clearing PK: local is null/empty
  /// and PK has a real value. The caller treats this as "no local changes."
  bool _wouldClear(String? local, String? pk) {
    final localEmpty = local == null || local.isEmpty;
    final pkEmpty = pk == null || pk.isEmpty;
    return localEmpty && !pkEmpty;
  }

  /// Apply PK-side changes to the local member. Writes via [memberRepository]
  /// when any pull-direction field differs. Returns whether anything was
  /// applied (so the caller can bump the "pulled" counter).
  ///
  /// Note: `proxyTags` is always pull-only — there is no push path. It is
  /// applied here regardless of direction config (guarded by overall
  /// `direction.pullEnabled`, which the caller already checks).
  Future<bool> _applyPkChanges(
    domain.Member local,
    PKMember pk,
    PkFieldSyncConfig config,
    PkSyncDirection direction,
    MemberRepository memberRepository,
  ) async {
    if (!direction.pullEnabled) return false;

    var updated = local;
    var changed = false;

    // Pre-phase-3 the pull path wrote `pk.displayName ?? pk.name` into
    // local.name (no separate displayName field). If an existing mapped
    // member still has that legacy shape — local.displayName is null and
    // local.name equals pk.displayName — promote local.name into displayName
    // before touching name, so we don't silently rename to pk.name.
    final needsDisplayNameMigration =
        pk.displayName != null &&
        local.displayName == null &&
        local.name == pk.displayName;
    if (needsDisplayNameMigration &&
        _pullField(config.displayName, direction)) {
      updated = updated.copyWith(displayName: pk.displayName);
      changed = true;
    }

    if (_pullField(config.name, direction)) {
      if (updated.name != pk.name) {
        updated = updated.copyWith(name: pk.name);
        changed = true;
      }
    }
    if (_pullField(config.displayName, direction) &&
        !needsDisplayNameMigration) {
      if (updated.displayName != pk.displayName) {
        updated = updated.copyWith(displayName: pk.displayName);
        changed = true;
      }
    }
    if (_pullField(config.pronouns, direction)) {
      if (local.pronouns != pk.pronouns) {
        updated = updated.copyWith(pronouns: pk.pronouns);
        changed = true;
      }
    }
    if (_pullField(config.description, direction)) {
      if (local.bio != pk.description) {
        updated = updated.copyWith(bio: pk.description);
        changed = true;
      }
    }
    if (_pullField(config.birthday, direction)) {
      final localBd = _normalizeBirthday(local.birthday);
      final pkBd = _normalizeBirthday(pk.birthday);
      if (localBd != pkBd) {
        updated = updated.copyWith(birthday: pk.birthday);
        changed = true;
      }
    }
    if (_pullField(config.color, direction)) {
      final localColor = _normalizeColor(local.customColorHex);
      final pkColor = _normalizeColor(pk.color);
      if (localColor != pkColor) {
        updated = updated.copyWith(
          customColorHex: pk.color,
          customColorEnabled: pk.color != null && pk.color!.isNotEmpty,
        );
        changed = true;
      }
    }

    // proxy_tags is pull-only — Prism has no editor UI for proxy tags, so
    // PK is authoritative.
    if (pk.proxyTagsJson != null && local.proxyTagsJson != pk.proxyTagsJson) {
      updated = updated.copyWith(proxyTagsJson: pk.proxyTagsJson);
      changed = true;
    }

    if (changed) {
      await memberRepository.updateMember(updated);
    }
    return changed;
  }

  /// Whether a field should be pushed given its per-field config and the
  /// overall direction. Overall direction takes precedence when it is
  /// push-only or pull-only (forces push/no-push regardless of per-field).
  bool _pushField(PkSyncDirection field, PkSyncDirection overall) {
    if (overall == PkSyncDirection.pullOnly) return false;
    if (overall == PkSyncDirection.pushOnly) return true;
    return field.pushEnabled;
  }

  bool _pullField(PkSyncDirection field, PkSyncDirection overall) {
    if (overall == PkSyncDirection.pushOnly) return false;
    if (overall == PkSyncDirection.pullOnly) return true;
    return field.pullEnabled;
  }

  /// Normalize a color hex string for comparison (strip '#', lowercase).
  String? _normalizeColor(String? color) {
    if (color == null || color.isEmpty) return null;
    var c = color.toLowerCase();
    if (c.startsWith('#')) c = c.substring(1);
    return c;
  }

  /// Normalize a birthday for equality comparison.
  ///
  /// PK emits `YYYY-MM-DD` with a `0004` sentinel for "no year." We keep the
  /// raw string on both sides, but normalize by lowercasing whitespace so
  /// `" 2020-01-15"` and `"2020-01-15"` compare equal. No year-0004
  /// collapsing — PK itself is stable about the sentinel, so round-trip is
  /// byte-identical unless a human edits it.
  String? _normalizeBirthday(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
