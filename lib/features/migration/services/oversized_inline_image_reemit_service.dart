import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';
import 'package:prism_plurality/shared/utils/profile_header_image_normalizer.dart';

/// Emit one changed-field patch for a member.
typedef OversizedImageRecordUpdate =
    Future<void> Function({
      required String table,
      required String entityId,
      required Map<String, dynamic> fields,
    });

/// Re-encode an avatar blob to the on-disk + on-wire budget. Returns null if the
/// input can't be decoded (caller skips the field). Async so the default can run
/// the decode off the main isolate (this loop over members otherwise ANR'd).
typedef AvatarInlineNormalizer = Future<Uint8List?> Function(Uint8List bytes);

/// Re-encode a profile-header / banner blob. Throws if it can't be normalized.
typedef HeaderInlineNormalizer = Future<Uint8List> Function(Uint8List bytes);

class OversizedInlineImageReemitResult {
  const OversizedInlineImageReemitResult({
    this.membersRepaired = 0,
    this.fieldsReemitted = 0,
    this.alreadyCompleted = false,
    this.error,
  });

  final int membersRepaired;
  final int fieldsReemitted;
  final bool alreadyCompleted;
  final String? error;

  bool get hasError => error != null;
}

/// One-time repair for member avatars/banners stored inline (base64 in the
/// member CRDT op) at a size no single sync envelope can carry — these are
/// silently quarantined on push, so peers show the ❔ fallback. The usual source
/// is animated GIFs from the reverted `AvatarNormalizer` passthrough.
///
/// Re-normalizes the offending blob under the inline budget, writes it locally,
/// and re-emits the per-field op so the shrunk value supersedes the stuck one
/// and reaches peers (animation is lost; the image appears). Runs from the
/// post-healthy-sync catch-up so the re-emit pushes against live sync.
class OversizedInlineImageReemitService {
  OversizedInlineImageReemitService({
    required AppDatabase db,
    required OversizedImageRecordUpdate recordUpdate,
    SharedPreferences? preferences,
    AvatarInlineNormalizer? avatarNormalizer,
    HeaderInlineNormalizer? headerNormalizer,
  }) : _db = db,
       _recordUpdate = recordUpdate,
       _preferences = preferences,
       _avatarNormalizer =
           avatarNormalizer ?? AvatarNormalizer.normalizeOffMainIsolate,
       _headerNormalizer =
           headerNormalizer ?? _defaultHeaderNormalizer;

  static const flagKey = 'sync.oversized_inline_image_reemit_v1';

  /// Above every normalizer's output budget (avatar 256 KB, header 512 KB) and
  /// just under the ~560 KB raw envelope cliff, so only genuinely-stuck blobs
  /// are touched.
  static const maxInlineSyncBytes = 512 * 1024;

  final AppDatabase _db;
  final OversizedImageRecordUpdate _recordUpdate;
  final SharedPreferences? _preferences;
  final AvatarInlineNormalizer _avatarNormalizer;
  final HeaderInlineNormalizer _headerNormalizer;

  // Off-main: this loops over members, and the banners it touches — animated
  // GIFs among them — froze the UI thread on inline decode (ANR).
  static Future<Uint8List> _defaultHeaderNormalizer(Uint8List bytes) =>
      ProfileHeaderImageNormalizer().normalizeOffMainIsolate(bytes);

  static Future<bool> hasCandidates(AppDatabase db) async {
    final rows = await db
        .customSelect(
          '''
          SELECT 1 FROM members
          WHERE is_deleted = 0
            AND ( length(avatar_image_data) > ?1
               OR length(profile_header_image_data) > ?1
               OR length(pk_banner_image_data) > ?1 )
          LIMIT 1
          ''',
          variables: [const Variable<int>(maxInlineSyncBytes)],
          readsFrom: {db.members},
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<OversizedInlineImageReemitResult> runOnce() async {
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) == true) {
      return const OversizedInlineImageReemitResult(alreadyCompleted: true);
    }

    try {
      final rows = await _db
          .customSelect(
            '''
            SELECT id, avatar_image_data, profile_header_image_data,
                   pk_banner_image_data
            FROM members
            WHERE is_deleted = 0
              AND ( length(avatar_image_data) > ?1
                 OR length(profile_header_image_data) > ?1
                 OR length(pk_banner_image_data) > ?1 )
            ORDER BY id ASC
            ''',
            variables: [const Variable<int>(maxInlineSyncBytes)],
            readsFrom: {_db.members},
          )
          .get();

      var membersRepaired = 0;
      var fieldsReemitted = 0;

      for (final row in rows) {
        final id = row.read<String>('id');
        final fields = <String, dynamic>{};
        var touched = false;

        final avatar = row.readNullable<Uint8List>('avatar_image_data');
        if (_isOversized(avatar)) {
          final shrunk = await _shrinkAvatar(avatar!);
          if (shrunk != null) {
            await _writeBlob(id, avatar: shrunk);
            fields['avatar_image_data'] = base64Encode(shrunk);
            touched = true;
          }
        }

        final header = row.readNullable<Uint8List>('profile_header_image_data');
        if (_isOversized(header)) {
          final shrunk = await _shrinkHeader(header!);
          if (shrunk != null) {
            await _writeBlob(id, header: shrunk);
            fields['profile_header_image_data'] = base64Encode(shrunk);
            touched = true;
          }
        }

        final pkBanner = row.readNullable<Uint8List>('pk_banner_image_data');
        if (_isOversized(pkBanner)) {
          final shrunk = await _shrinkHeader(pkBanner!);
          if (shrunk != null) {
            await _writeBlob(id, pkBanner: shrunk);
            fields['pk_banner_image_data'] = base64Encode(shrunk);
            touched = true;
          }
        }

        if (touched) {
          await _recordUpdate(table: 'members', entityId: id, fields: fields);
          membersRepaired++;
          fieldsReemitted += fields.length;
        }
      }

      await prefs.setBool(flagKey, true);
      if (membersRepaired > 0) {
        debugPrint(
          '[OVERSIZED_IMAGE_SYNC] Re-normalized $fieldsReemitted inline image '
          'field(s) across $membersRepaired member(s) so they fit one sync op.',
        );
      }
      return OversizedInlineImageReemitResult(
        membersRepaired: membersRepaired,
        fieldsReemitted: fieldsReemitted,
      );
    } catch (error) {
      debugPrint('[OVERSIZED_IMAGE_SYNC] re-normalize failed: $error');
      return OversizedInlineImageReemitResult(error: error.toString());
    }
  }

  static bool _isOversized(Uint8List? bytes) =>
      bytes != null && bytes.length > maxInlineSyncBytes;

  /// Only accept the re-encode if it's under budget and smaller — never make a
  /// stuck row worse.
  Future<Uint8List?> _shrinkAvatar(Uint8List bytes) async {
    try {
      final out = await _avatarNormalizer(bytes);
      if (out == null) return null;
      if (out.length > maxInlineSyncBytes || out.length >= bytes.length) {
        return null;
      }
      return out;
    } catch (error) {
      debugPrint('[OVERSIZED_IMAGE_SYNC] avatar re-encode skipped: $error');
      return null;
    }
  }

  Future<Uint8List?> _shrinkHeader(Uint8List bytes) async {
    try {
      final out = await _headerNormalizer(bytes);
      if (out.length > maxInlineSyncBytes || out.length >= bytes.length) {
        return null;
      }
      return out;
    } catch (error) {
      debugPrint('[OVERSIZED_IMAGE_SYNC] header re-encode skipped: $error');
      return null;
    }
  }

  Future<void> _writeBlob(
    String id, {
    Uint8List? avatar,
    Uint8List? header,
    Uint8List? pkBanner,
  }) async {
    await (_db.update(_db.members)..where((t) => t.id.equals(id))).write(
      MembersCompanion(
        avatarImageData: avatar == null ? const Value.absent() : Value(avatar),
        profileHeaderImageData:
            header == null ? const Value.absent() : Value(header),
        pkBannerImageData:
            pkBanner == null ? const Value.absent() : Value(pkBanner),
      ),
    );
  }
}
