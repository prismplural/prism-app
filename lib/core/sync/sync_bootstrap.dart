import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';

typedef BootstrapRecordCreate = Future<void> Function({
  required ffi.PrismSyncHandle handle,
  required String table,
  required String entityId,
  required String fieldsJson,
});

/// Walks every synced Drift table and emits a `record_create` op for each
/// row. Used at first-device sync setup so existing local data reaches
/// peers (the pairing snapshot is built from `field_versions` /
/// `applied_ops`, so a row that never had an op emitted is invisible).
///
/// **Precondition:** the engine's CRDT storage is empty for `sync_id`.
/// Bootstrap unconditionally writes fresh HLCs; running this after any
/// peer state exists will overwrite newer field versions.
///
/// `recordCreate` is injected for tests; defaults to [ffi.recordCreate].
///
/// Returns the number of ops successfully emitted.
Future<int> bootstrapExistingData({
  required ffi.PrismSyncHandle handle,
  required AppDatabase db,
  required DriftSyncAdapter adapter,
  BootstrapRecordCreate recordCreate = _defaultRecordCreate,
}) async {
  final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
  final entities = (schema['entities'] as Map<String, dynamic>).keys;
  final tableQueries = bootstrapTableQueries(db);

  var totalOps = 0;
  for (final entityName in entities) {
    final entity = adapter.entityForTable(entityName);
    if (entity == null) continue;

    final query = tableQueries[entityName];
    if (query == null) {
      if (kDebugMode) {
        debugPrint('[BOOTSTRAP] no query for $entityName — skipping');
      }
      continue;
    }

    final rows = await query();
    for (final row in rows) {
      try {
        final fields = entity.toSyncFields(row);
        final id = entity.entityIdFor(row);
        // Tombstones are emitted too. Skipping `is_deleted == true` rows
        // is unsafe for entities with deterministic IDs (member_groups,
        // member_group_entries): a peer can later import the same PK
        // object and emit recordCreate under the same canonical ID;
        // without a tombstone in field_versions, CRDT tombstone
        // protection has nothing to enforce against → resurrection.
        await recordCreate(
          handle: handle,
          table: entityName,
          entityId: id,
          fieldsJson: jsonEncode(fields),
        );
        totalOps++;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BOOTSTRAP] failed $entityName row: $e');
        }
      }
    }
  }

  if (kDebugMode) {
    debugPrint('[BOOTSTRAP] pushed $totalOps records');
  }
  return totalOps;
}

@visibleForTesting
Map<String, Future<List<dynamic>> Function()> bootstrapTableQueries(
  AppDatabase db,
) {
  return {
    'members': () => db.select(db.members).get(),
    'fronting_sessions': () => db.select(db.frontingSessions).get(),
    'conversations': () => db.select(db.conversations).get(),
    'chat_messages': () => db.select(db.chatMessages).get(),
    // system_settings is a singleton — filter to the canonical row. The
    // table only defaults `id = 'singleton'`, it doesn't enforce it; any
    // rogue row would otherwise propagate to peers.
    'system_settings': () => (db.select(db.systemSettingsTable)
          ..where((t) => t.id.equals('singleton')))
        .get(),
    'polls': () => db.select(db.polls).get(),
    'poll_options': () => db.select(db.pollOptions).get(),
    'poll_votes': () => db.select(db.pollVotes).get(),
    'habits': () => db.select(db.habits).get(),
    'habit_completions': () => db.select(db.habitCompletions).get(),
    'member_groups': () => db.select(db.memberGroups).get(),
    'member_group_entries': () => db.select(db.memberGroupEntries).get(),
    'custom_fields': () => db.select(db.customFields).get(),
    'custom_field_values': () => db.select(db.customFieldValues).get(),
    'notes': () => db.select(db.notes).get(),
    'front_session_comments': () => db.select(db.frontSessionComments).get(),
    'conversation_categories': () =>
        db.select(db.conversationCategories).get(),
    'reminders': () => db.select(db.reminders).get(),
    'friends': () => db.select(db.friends).get(),
    'media_attachments': () => db.select(db.mediaAttachments).get(),
  };
}

Future<void> _defaultRecordCreate({
  required ffi.PrismSyncHandle handle,
  required String table,
  required String entityId,
  required String fieldsJson,
}) {
  return ffi.recordCreate(
    handle: handle,
    table: table,
    entityId: entityId,
    fieldsJson: fieldsJson,
  );
}
