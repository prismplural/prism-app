import 'dart:convert';

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_avatar_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_banner_cache_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';

/// Orchestrates bidirectional sync between Prism and PluralKit.
///
/// Compares local members with PK members and, per-field and per-direction,
/// either pulls (PK -> Prism, writing via `memberRepository.updateMember`)
/// or pushes (Prism -> PK, via `PkPushService`).
class PkBidirectionalService {
  final PkPushService _pushService;
  final PkAvatarCacheService _avatarCacheService;
  final PkBannerCacheService _bannerCacheService;

  PkBidirectionalService({
    PkPushService? pushService,
    PkAvatarCacheService? avatarCacheService,
    PkBannerCacheService? bannerCacheService,
  }) : _pushService = pushService ?? const PkPushService(),
       _avatarCacheService = avatarCacheService ?? PkAvatarCacheService(),
       _bannerCacheService = bannerCacheService ?? PkBannerCacheService();

  /// F4: how long a create-push lease is honored before a peer assumes the
  /// stamping device crashed/went offline and takes over (adopting any orphan
  /// or re-POSTing). Mirrors the delete lease's R6 takeover threshold.
  static const _createPushTakeoverThreshold = Duration(minutes: 10);

  bool _createLeaseActive(int? startedAtMs, DateTime now) {
    if (startedAtMs == null) return false;
    final age = Duration(
      milliseconds: now.millisecondsSinceEpoch - startedAtMs,
    );
    return age < _createPushTakeoverThreshold;
  }

  /// F5: find an orphaned-create PK member for [local] — unlinked, matched by
  /// name (the only join key; an orphan has no pluralkit_uuid/id). The caller
  /// gates this on [local] holding a stale create lease, bounding collision risk
  /// to members this fleet tried to create. A rename across the crash window
  /// misses and re-POSTs — the same pre-F5 duplicate, never worse.
  PKMember? _findAdoptableOrphan(
    domain.Member local,
    List<PKMember> pkMembers,
    Set<String> linkedPkUuids,
  ) {
    final name = local.name.trim();
    if (name.isEmpty) return null;
    for (final pk in pkMembers) {
      if (linkedPkUuids.contains(pk.uuid.trim())) continue;
      if (pk.name.trim() == name) return pk;
    }
    return null;
  }

  /// Sync members bidirectionally.
  ///
  /// [localMembers] — all local members (may or may not have PK IDs).
  /// [pkMembers] — all members fetched from PK.
  /// [fieldConfigs] — per-member field direction config (keyed by local member ID).
  /// [direction] — overall sync direction.
  /// [lastSyncDate] — the last time a sync completed (unused here, kept for API stability).
  /// [memberRepository] — for persisting pulled changes.
  /// [client] — PK API client.
  /// [onPushSkipped] — optional hook invoked once per push-skip message so
  ///   the orchestrator can merge them into its user-facing error channel.
  ///
  /// Per-member push isolation (2026-06 PK audit M10a): a [PluralKitApiError]
  /// from one member's push no longer aborts the whole sync — count, collect
  /// a classified message, continue. [PluralKitAuthError] still propagates
  /// (a revoked token fails every member identically; handled upstream, M3).
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
    void Function(String message)? onPushSkipped,
  }) async {
    int pulled = 0;
    int pushed = 0;
    int skipped = 0;
    final pushSkippedMessages = <String>[];
    void recordPushSkip(String message) {
      pushSkippedMessages.add(message);
      onPushSkipped?.call(message);
    }

    // Build lookup maps.
    final localByPkUuid = <String, domain.Member>{};
    final localByPkId = <String, domain.Member>{};
    for (final m in localMembers) {
      final pkUuid = m.pluralkitUuid?.trim();
      if (pkUuid != null && pkUuid.isNotEmpty) {
        localByPkUuid[pkUuid] = m;
      }
      final pkId = m.pluralkitId?.trim();
      if (pkId != null && pkId.isNotEmpty) {
        localByPkId[pkId] = m;
      }
    }

    // Process members that exist on PK
    for (final pk in pkMembers) {
      var local = localByPkUuid[pk.uuid] ?? localByPkId[pk.id];

      if (local == null) {
        // New member on PK, not in Prism. The caller's pull step
        // (_importMembers over the unseen set, F14) creates these BEFORE this
        // pass runs against the pre-create snapshot, so here we only count it.
        if (direction.pullEnabled) {
          pulled++;
        } else {
          skipped++;
        }
        continue;
      }

      // User-excluded locals must not flow through push OR pull, even when
      // they still carry PK identifiers. The repo invariant is the durable
      // backstop; the guard here makes the skip explicit and avoids any
      // network work for excluded members.
      if (local.pluralkitSyncIgnored) {
        skipped++;
        continue;
      }

      final needsIdentityRepair =
          !memberMatchesPkMember(local, pk) ||
          local.pluralkitUuid != pk.uuid ||
          local.pluralkitId != pk.id;
      if (needsIdentityRepair) {
        local = local.copyWith(pluralkitUuid: pk.uuid, pluralkitId: pk.id);
      }

      final config = fieldConfigs[local.id] ?? const PkFieldSyncConfig();

      if (direction.pushEnabled) {
        // Compute, once, the exact set of PK payload keys this push may carry.
        // A field is includable only when push is allowed by direction config,
        // it differs from PK, and it is not a would-clear (local empty + PK
        // populated). The push fires only when at least one field qualifies.
        final allowedFields = _pushableFields(local, pk, config, direction);
        if (allowedFields.isNotEmpty) {
          final localName = local.name;
          try {
            await _pushService.pushMember(
              local,
              client,
              pkMember: pk,
              includeProxyTags: allowedFields.contains('proxy_tags'),
              allowedFields: allowedFields,
              onFieldSkipped: (field, reason) =>
                  recordPushSkip("'$localName': $field $reason."),
            );
            if (needsIdentityRepair) {
              await memberRepository.applyPluralKitLink(local.id, {
                'pluralkit_uuid': pk.uuid,
                'pluralkit_id': pk.id,
              });
            }
            pushed++;
            continue;
          } on PkStaleLinkException catch (_) {
            // PK deleted the linked member out from under us. Clear the link
            // so the user can re-link via the mapping screen and the next
            // sync treats this as an unlinked local member. Null writes pass
            // through Rule A unchanged, so this stays on generic updateMember.
            await memberRepository.updateMember(
              local.copyWith(pluralkitId: null, pluralkitUuid: null),
            );
            skipped++;
            continue;
          } on PluralKitAuthError {
            // Auth failures abort meaningfully — every member would fail the
            // same way and the upstream M3 handler owns the messaging.
            rethrow;
          } on PluralKitRateLimitError {
            // A sustained 429 (past the queue's retry budget) is a global
            // condition like auth — walking the remaining members would burn
            // a fresh retry budget per member for the same answer. Abort and
            // let the upstream M3 classifier schedule the backoff.
            rethrow;
          } on PluralKitApiError catch (e) {
            // M10a: isolate this member's failure; keep syncing the rest.
            recordPushSkip(_describePushFailure(localName, e));
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
          forceWrite: needsIdentityRepair,
        );
        if (applied) {
          pulled++;
          continue;
        }
      }

      if (needsIdentityRepair) {
        await memberRepository.applyPluralKitLink(local.id, {
          'pluralkit_uuid': pk.uuid,
          'pluralkit_id': pk.id,
        });
      }
      skipped++;
    }

    // Process local members that have no PK counterpart
    if (direction.pushEnabled) {
      final now = DateTime.now();
      // PK uuids already claimed by some local member, so an ORPHANED PK member
      // (created by a prior interrupted push whose link-back never landed) is
      // recognizable for F5 adoption below.
      final linkedPkUuids = <String>{
        for (final m in localMembers)
          if ((m.pluralkitUuid ?? '').trim().isNotEmpty)
            m.pluralkitUuid!.trim(),
      };
      // F5 safety: a soft-deleted member retains its pluralkit_uuid, and its PK
      // member may still be live on the server (the delete-push hasn't completed,
      // or PK refused it). Exclude those uuids too, so a new same-named member
      // never adopts — and silently inherits — a deleted member's PK identity.
      for (final m in await memberRepository.getDeletedLinkedMembers()) {
        final u = (m.pluralkitUuid ?? '').trim();
        if (u.isNotEmpty) linkedPkUuids.add(u);
      }
      for (final local in localMembers) {
        if (hasPluralKitLink(local)) continue;
        // User picked Keep local via the push-on-create dialog or banner;
        // respect their durable preference.
        if (local.pluralkitSyncIgnored) continue;

        // F4: a FRESH create lease means another device (or this one) is
        // mid-POST for this member. Skip so two paired devices don't each mint
        // a separate PK member; whoever holds the lease finishes and links it,
        // and the next sync sees it linked.
        if (_createLeaseActive(local.createPushStartedAt, now)) {
          skipped++;
          continue;
        }

        // F5: a set-but-STALE lease means a prior POST may have orphaned a PK
        // member (the link-back never completed). Adopt a matching orphan
        // instead of re-POSTing a duplicate.
        if (local.createPushStartedAt != null) {
          final orphan = _findAdoptableOrphan(local, pkMembers, linkedPkUuids);
          if (orphan != null) {
            await memberRepository.applyPluralKitLink(local.id, {
              'pluralkit_uuid': orphan.uuid,
              'pluralkit_id': orphan.id,
            });
            await memberRepository.clearCreatePushStartedAt(local.id);
            linkedPkUuids.add(orphan.uuid.trim());
            pushed++;
            continue;
          }
        }

        // New local member — push to PK. Same per-member isolation as the
        // linked-member loop above (M10a): one rejected create must not
        // abort the remaining creates or the rest of the sync.
        final localName = local.name;
        // F4: stamp the synced lease BEFORE the POST so a peer syncing in this
        // window backs off and does not also mint a PK member.
        //
        // Deliberately re-stamps `now` on a retry (unlike the delete lease's
        // stamp-if-null at _runSwitchDeletions): for CREATE the re-stamp IS the
        // backoff — a stale-lease retry that re-POSTs gets a fresh 10-min window
        // before the next attempt. Mirroring delete's stamp-if-null here would
        // REMOVE that backoff (a stale lease would re-POST every sync), so the
        // asymmetry is correct, not a livelock to "fix". The one genuine residual
        // — repeated orphan creation when a POST succeeds, the link-back keeps
        // failing, AND the local was renamed so _findAdoptableOrphan (exact-name)
        // can't reclaim the orphan — needs a "this fleet already POSTed" signal
        // distinct from the lease, not a lease-stamp tweak. Narrow; left as-is.
        await memberRepository.stampCreatePushStartedAt(
          local.id,
          now.millisecondsSinceEpoch,
        );
        final PKMember pkMember;
        try {
          pkMember = await _pushService.pushMemberFull(
            local,
            client,
            onFieldSkipped: (field, reason) =>
                recordPushSkip("'$localName': $field $reason."),
          );
        } catch (e) {
          // The POST failed (transport error, validation rejection, auth, rate
          // limit, …) so NO PK member was created. Release the lease: leaving it
          // set would falsely read as "a prior POST orphaned a PK member" and let
          // a later sync ADOPT an unrelated same-named PK member (a silent
          // wrong-identity merge), and would starve peers who skip on a fresh
          // lease. The lease is kept ONLY when the POST genuinely succeeds but
          // the link-back fails (the real F5 orphan case, below).
          await memberRepository.clearCreatePushStartedAt(local.id);
          if (e is PluralKitAuthError || e is PluralKitRateLimitError) {
            // Global condition — see the linked-member loop above.
            rethrow;
          }
          if (e is PluralKitApiError) {
            recordPushSkip(_describePushFailure(localName, e));
          } else {
            recordPushSkip("'$localName': create push failed ($e).");
          }
          skipped++;
          continue;
        }
        try {
          // POST succeeded — a PK member now exists. Store both identifiers back
          // on the local member and release the lease; the create is durably
          // linked.
          await memberRepository.applyPluralKitLink(local.id, {
            'pluralkit_uuid': pkMember.uuid,
            'pluralkit_id': pkMember.id,
          });
          await memberRepository.clearCreatePushStartedAt(local.id);
          linkedPkUuids.add(pkMember.uuid.trim());
          pushed++;
        } catch (e) {
          // F5/F16: the link-back failed AFTER a successful POST, so a PK member
          // is orphaned. KEEP the lease set so the next sync adopts that orphan
          // rather than re-POSTing a duplicate, and don't abort the remaining
          // creates.
          recordPushSkip("'$localName': create link-back failed ($e).");
          skipped++;
        }
      }
    }

    return PkSyncSummary(
      membersPulled: pulled,
      membersPushed: pushed,
      membersSkipped: skipped,
      pushSkippedMessages: List.unmodifiable(pushSkippedMessages),
    );
  }

  /// Build a user-facing, classified reason for a per-member push failure
  /// (M10a). For PK validation rejections (400 code 40001)
  /// the per-field `errors` map — `max_length` / `actual_length`, parsed
  /// from the raw body that [PluralKitApiError.message] preserves — is
  /// flattened into the message so the user can see exactly which field to
  /// shorten.
  String _describePushFailure(String memberName, PluralKitApiError e) {
    if (e.code == 40001) {
      return "PluralKit rejected '$memberName': "
          '${_describeValidationErrors(e.message)} — skipped this sync.';
    }
    if (e.statusCode >= 500) {
      return 'PluralKit server error (${e.statusCode}) while pushing '
          "'$memberName' — skipped this sync.";
    }
    final code = e.code != null ? ', code ${e.code}' : '';
    return "PluralKit rejected '$memberName' "
        '(HTTP ${e.statusCode}$code) — skipped this sync.';
  }

  /// Flatten PK's 40001 `errors` map (`{field: [{message, max_length,
  /// actual_length}]}`) into a short human-readable string. Falls back to a
  /// generic phrase when the body isn't the expected JSON shape.
  String _describeValidationErrors(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map && decoded['errors'] is Map) {
        final parts = <String>[];
        (decoded['errors'] as Map).forEach((field, errs) {
          final list = errs is List ? errs : [errs];
          for (final err in list) {
            if (err is Map &&
                err['max_length'] != null &&
                err['actual_length'] != null) {
              parts.add(
                '$field is ${err['actual_length']} characters '
                '(max ${err['max_length']})',
              );
            } else if (err is Map && err['message'] is String) {
              parts.add('$field: ${err['message']}');
            } else {
              parts.add('$field is invalid');
            }
          }
        });
        if (parts.isNotEmpty) return parts.join('; ');
      }
    } catch (_) {
      // Non-JSON / unexpected body — fall through.
    }
    return 'validation failed (code 40001)';
  }

  /// The exact set of PK payload keys that may be pushed for [local]: a field
  /// is included only when its direction config allows push, it differs from
  /// the PK value, and it is not a would-clear (local null/empty + PK
  /// populated). Decides whether to push AND gates the payload so one edit
  /// can't null-clear unrelated PK-only fields (audit H1); clears never
  /// propagate from auto-push. Keys MUST match
  /// `PkPushService._memberToPayload`.
  Set<String> _pushableFields(
    domain.Member local,
    PKMember pk,
    PkFieldSyncConfig config,
    PkSyncDirection direction,
  ) {
    final fields = <String>{};
    if (_pushField(config.displayName, direction)) {
      final localDn = _normalizeText(local.pluralkitDisplayName);
      final pkDn = _normalizeText(pk.displayName);
      if (localDn != pkDn && !_wouldClear(localDn, pkDn)) {
        fields.add('display_name');
      }
    }
    if (_pushField(config.pronouns, direction)) {
      final localPn = _normalizeText(local.pronouns);
      final pkPn = _normalizeText(pk.pronouns);
      if (localPn != pkPn && !_wouldClear(localPn, pkPn)) {
        fields.add('pronouns');
      }
    }
    if (_pushField(config.description, direction)) {
      final localBio = _normalizeText(local.bio);
      final pkBio = _normalizeText(pk.description);
      if (localBio != pkBio && !_wouldClear(localBio, pkBio)) {
        fields.add('description');
      }
    }
    if (_pushField(config.birthday, direction)) {
      final localBd = _normalizeBirthday(local.birthday);
      final pkBd = _normalizeBirthday(pk.birthday);
      if (localBd != pkBd && !_wouldClear(localBd, pkBd)) {
        fields.add('birthday');
      }
    }
    if (_pushField(config.color, direction)) {
      // When local has no color enabled, don't sync color either way —
      // toggling local color off must not silently clear PK's color.
      if (local.customColorEnabled) {
        final localColor = _normalizeColor(local.customColorHex);
        final pkColor = _normalizeColor(pk.color);
        if (localColor != pkColor && !_wouldClear(localColor, pkColor)) {
          fields.add('color');
        }
      }
    }
    if (_hasProxyTagPushChange(local, pk, config, direction)) {
      fields.add('proxy_tags');
    }
    return fields;
  }

  bool _hasProxyTagPushChange(
    domain.Member local,
    PKMember pk,
    PkFieldSyncConfig config,
    PkSyncDirection direction,
  ) {
    if (!_pushField(config.proxyTags, direction)) return false;
    final localTags = _normalizeProxyTags(local.proxyTagsJson);
    final pkTags = _normalizeProxyTags(pk.proxyTagsJson);
    // Null means "no local opinion"; explicit [] is a pushable clear after
    // manual sync's delete-risk preview has warned.
    return localTags != null && localTags != pkTags;
  }

  /// Normalize a string field for comparison: null, empty, and
  /// whitespace-only all mean "unset." PK treats both explicit `null` and
  /// `""` as a field CLEAR on PATCH, so the `''`-vs-null distinction must
  /// never count as a difference — otherwise local `''` vs PK `null` pushes
  /// a destructive clear on every sync cycle, and local `null` vs PK `''`
  /// enters the pushable set only for the payload builder to omit it
  /// (risking an empty `{}` PATCH, which PK rejects with 400).
  String? _normalizeText(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// True when pushing would amount to null-clearing PK: local is null/empty
  /// and PK has a real value. The caller treats this as "no local changes."
  bool _wouldClear(String? local, String? pk) {
    final localEmpty = local == null || local.trim().isEmpty;
    final pkEmpty = pk == null || pk.trim().isEmpty;
    return localEmpty && !pkEmpty;
  }

  /// Apply PK-side changes to the local member. Writes via [memberRepository]
  /// when any pull-direction field differs. Returns whether anything was
  /// applied (so the caller can bump the "pulled" counter).
  ///
  Future<bool> _applyPkChanges(
    domain.Member local,
    PKMember pk,
    PkFieldSyncConfig config,
    PkSyncDirection direction,
    MemberRepository memberRepository, {
    bool forceWrite = false,
  }) async {
    if (!direction.pullEnabled) return false;

    var updated = local;
    var changed = forceWrite;

    if (_pullField(config.displayName, direction)) {
      if (updated.pluralkitDisplayName != pk.displayName) {
        updated = updated.copyWith(pluralkitDisplayName: pk.displayName);
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
      if (pkColor != null &&
          (localColor != pkColor || !local.customColorEnabled)) {
        updated = updated.copyWith(
          customColorHex: pk.color,
          customColorEnabled: true,
        );
        changed = true;
      }
    }

    if (_pullField(config.proxyTags, direction)) {
      final localTags = _normalizeProxyTags(local.proxyTagsJson);
      final pkTags = _normalizeProxyTags(pk.proxyTagsJson);
      if (pkTags != null && localTags != pkTags) {
        updated = updated.copyWith(proxyTagsJson: pk.proxyTagsJson);
        changed = true;
      }
    }

    final pkCreated = pk.created;
    if (pkCreated != null && updated.createdAt.isAfter(pkCreated)) {
      updated = updated.copyWith(createdAt: pkCreated);
      changed = true;
    }

    final avatarCache = await _avatarCacheService.resolve(
      PkAvatarCacheInput(
        currentAvatarImageData: local.avatarImageData,
        currentPkAvatarCachedUrl: local.pkAvatarCachedUrl,
        incomingAvatarUrl: pk.avatarUrl,
      ),
    );
    if (updated.avatarImageData != avatarCache.avatarImageData ||
        updated.pkAvatarCachedUrl != avatarCache.pkAvatarCachedUrl) {
      updated = updated.copyWith(
        avatarImageData: avatarCache.avatarImageData,
        pkAvatarCachedUrl: avatarCache.pkAvatarCachedUrl,
      );
      changed = true;
    }

    final bannerCache = await _bannerCacheService.resolve(
      PkBannerCacheInput(
        currentPkBannerUrl: local.pkBannerUrl,
        currentPkBannerImageData: local.pkBannerImageData,
        currentPkBannerCachedUrl: local.pkBannerCachedUrl,
        hasIncomingBannerField: pk.hasBannerField,
        incomingBannerUrl: pk.bannerUrl,
      ),
    );
    if (updated.pkBannerUrl != bannerCache.pkBannerUrl ||
        updated.pkBannerImageData != bannerCache.pkBannerImageData ||
        updated.pkBannerCachedUrl != bannerCache.pkBannerCachedUrl) {
      updated = updated.copyWith(
        pkBannerUrl: bannerCache.pkBannerUrl,
        pkBannerImageData: bannerCache.pkBannerImageData,
        pkBannerCachedUrl: bannerCache.pkBannerCachedUrl,
      );
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

  /// Normalize PK proxy tag JSON for comparison.
  ///
  /// Returns null when the field is absent or malformed. Returns `"[]"` for
  /// an explicit empty tag list so the sync layer can distinguish "unknown"
  /// from "clear all proxy tags."
  ///
  /// Equality must survive list reordering and per-tag map key reordering,
  /// otherwise we'd push every sync just because the JSON keys came back in
  /// a different order than we sent them. See [_canonicalProxyTagsList].
  String? _normalizeProxyTags(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      return _canonicalProxyTagsList(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Build a stable string for two proxy-tag JSON arrays so equality survives
  /// reordering at both levels:
  ///   1. Sort each tag's map keys alphabetically before encoding.
  ///   2. Sort the outer list by `(prefix, suffix)` ascending.
  ///
  /// The result is intended only for `==` comparison — do NOT round-trip it
  /// back into PK or persist it; it's a comparison-only canonical form.
  String _canonicalProxyTagsList(List<dynamic> list) {
    final canonical = <Map<String, dynamic>>[];
    for (final entry in list) {
      if (entry is Map) {
        final sortedKeys = entry.keys.map((k) => k.toString()).toList()..sort();
        final sorted = <String, dynamic>{
          for (final k in sortedKeys) k: entry[k],
        };
        canonical.add(sorted);
      } else {
        // Non-map entry: preserve as-is under a synthetic wrapper so the
        // outer sort still terminates without throwing.
        canonical.add({'__raw__': entry});
      }
    }
    canonical.sort((a, b) {
      final aPrefix = (a['prefix'] ?? '').toString();
      final bPrefix = (b['prefix'] ?? '').toString();
      final byPrefix = aPrefix.compareTo(bPrefix);
      if (byPrefix != 0) return byPrefix;
      final aSuffix = (a['suffix'] ?? '').toString();
      final bSuffix = (b['suffix'] ?? '').toString();
      return aSuffix.compareTo(bSuffix);
    });
    return jsonEncode(canonical);
  }
}
