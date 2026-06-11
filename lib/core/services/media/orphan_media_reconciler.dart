import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';

/// Feature-flag gate for the startup orphan-media reconcile. Flip to `false`
/// in a hotfix if the sweep turns out to be too aggressive — keeps the wiring
/// in place without requiring a revert.
const bool kEnableOrphanMediaReconcile = true;

/// Resolves the directory where encrypted media files (`<mediaId>.enc`) live.
///
/// Production: `<applicationSupport>/prism_media`, matching the path used by
/// `DownloadManager._resolveCacheDir`. Tests override this with a temp dir
/// so the reconciler can actually inspect and delete files without going
/// through path_provider's platform channel.
final orphanMediaReconcileDirectoryProvider = FutureProvider<Directory>((
  ref,
) async {
  final supportDir = await getApplicationSupportDirectory();
  return Directory(p.join(supportDir.path, 'prism_media'));
});

/// Scans the on-disk encrypted media cache and deletes any `<mediaId>.enc`
/// whose `media_id` is not referenced by any row in `media_attachments`
/// (including soft-deleted rows — those are still claims on the file until
/// the sync layer reconciles their tombstones).
///
/// This sweep recovers `.enc` files orphaned by a mid-reset crash: in
/// `_resetChat` and `_resetAll`, DB rows are deleted first and then the on-
/// disk files are unlinked. If the app is killed (OS, SIGKILL, panic, etc.)
/// after the DB commit but before the file loop completes, every file whose
/// row was just deleted is stranded permanently.
///
/// Returns the number of files actually deleted.
///
/// Best-effort: all I/O is wrapped in try/catch and logged via
/// [ErrorReportingService]. Returns `0` on any unrecoverable error rather
/// than throwing — startup must never fail because of cache hygiene.
///
/// **Idempotence**: safe to call repeatedly. Only files whose media_id is
/// absent from `media_attachments` are deleted; running twice in a row
/// produces the same outcome as running once.
///
/// **Scope**: v1 is a startup-only sweep. No scheduler, no retry, no
/// background-job infrastructure.
Future<int> reconcileOrphanMedia({
  required AppDatabase db,
  required Directory mediaDir,
  void Function(String message)? log,
}) async {
  final logFn = log ?? _defaultLog;

  if (!kEnableOrphanMediaReconcile) {
    logFn('Orphan media reconcile disabled by feature flag');
    return 0;
  }

  try {
    if (!await mediaDir.exists()) {
      // No cache dir means no files to reconcile — first launch, post-full-
      // reset, or platform that hasn't created the directory yet. Nothing
      // to do.
      return 0;
    }

    // 1. Snapshot every media_id currently claimed by the DB. Includes
    //    soft-deleted rows: the file is still a valid claim until the sync
    //    layer materializes and reconciles those tombstones. Without this,
    //    a row tombstoned by a remote peer (but not yet hard-deleted) would
    //    have its still-referenced .enc nuked here.
    final claimed = <String>{};
    final rows = await db
        .customSelect(
          'SELECT media_id, thumbnail_media_id FROM media_attachments',
        )
        .get();
    for (final row in rows) {
      final mediaId = row.read<String>('media_id');
      if (mediaId.isNotEmpty) claimed.add(mediaId);
      // A thumbnail (media thumbnails) lives in `thumbnail_media_id` and has
      // NO row of its own, so it must be claimed explicitly — otherwise every
      // cached thumbnail `.enc` looks like an orphan and is swept on each
      // launch (which, once relay retention shortens and the media heal can re-supply it,
      // would be permanent loss).
      final thumbnailMediaId = row.read<String>('thumbnail_media_id');
      if (thumbnailMediaId.isNotEmpty) claimed.add(thumbnailMediaId);
    }

    // 2. Walk the cache dir, collecting `.enc` filenames whose media_id is
    //    not in the claimed set.
    final orphans = <File>[];
    await for (final entity in mediaDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.enc')) continue;
      final mediaId = name.substring(0, name.length - '.enc'.length);
      if (mediaId.isEmpty) continue;
      if (claimed.contains(mediaId)) continue;
      orphans.add(entity);
    }

    if (orphans.isEmpty) return 0;

    // 3. Delete each orphan. Per-file try/catch so a single permission
    //    failure or transient OS error doesn't strand the rest.
    var deleted = 0;
    for (final file in orphans) {
      try {
        await file.delete();
        deleted += 1;
      } catch (e) {
        logFn(
          'Orphan media reconcile: failed to delete '
          '${p.basename(file.path)} (non-fatal): $e',
        );
      }
    }
    if (deleted > 0) {
      logFn('Orphan media reconcile: deleted $deleted file(s)');
    }
    return deleted;
  } catch (e) {
    logFn('Orphan media reconcile failed (non-fatal): $e');
    return 0;
  }
}

void _defaultLog(String message) {
  ErrorReportingService.instance.report(
    message,
    severity: ErrorSeverity.info,
  );
}

/// Convenience wrapper that resolves the directory + DB from a [WidgetRef]
/// and runs [reconcileOrphanMedia]. Called from app startup once after the
/// Riverpod tree is up. Accepts [WidgetRef] (the type that [ConsumerState]
/// exposes via its `ref` field) rather than the provider-only [Ref] so the
/// startup hook in `app.dart` can wire this without an extra adapter.
Future<int> runOrphanMediaReconcileFromRef(WidgetRef ref) async {
  if (!kEnableOrphanMediaReconcile) return 0;
  try {
    final db = ref.read(databaseProvider);
    final mediaDir = await ref.read(
      orphanMediaReconcileDirectoryProvider.future,
    );
    return await reconcileOrphanMedia(db: db, mediaDir: mediaDir);
  } catch (e) {
    ErrorReportingService.instance.report(
      'Orphan media reconcile failed to resolve dependencies (non-fatal): $e',
      severity: ErrorSeverity.info,
    );
    return 0;
  }
}
