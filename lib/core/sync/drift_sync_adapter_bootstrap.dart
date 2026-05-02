import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';

/// A row extracted from a Drift table, flattened to the wire-shape the Rust
/// bootstrap primitive expects: `{ entity_id, fields }`.
class SyncRow {
  const SyncRow({required this.id, required this.fields});

  final String id;
  final Map<String, dynamic> fields;
}

/// Zero-argument fetcher that loads all rows from one synced table.
///
/// Returned rows are already mapped through the corresponding
/// [DriftSyncEntity.toSyncFields] so the bootstrap caller can forward them
/// directly to the Rust `bootstrap_existing_state` FFI.
typedef BootstrapFetcher = Future<List<SyncRow>> Function();

/// Build a registry of `tableName -> fetcher` for every entity registered on
/// [adapter].
///
/// The bootstrap flow iterates this map to seed the Rust engine's
/// `field_versions` tables from existing Drift state. Adding a new synced
/// entity therefore requires adding a case here too — the parity test at
/// `test/core/sync/drift_sync_adapter_bootstrap_parity_test.dart` keeps the
/// two sides in lockstep.
Map<String, BootstrapFetcher> bootstrapFetchersFor(
  DriftSyncAdapter adapter,
  AppDatabase db,
) {
  BootstrapFetcher build<T>(
    String tableName,
    Future<List<dynamic>> Function() select,
  ) {
    final entity = adapter.entityForTable(tableName);
    if (entity == null) {
      // The parity test enforces adapter coverage of this map, so reaching
      // this branch in production means the adapter registry drifted from
      // the bootstrap map. Fail loudly instead of silently skipping rows.
      throw StateError(
        'No sync entity registered for bootstrap table "$tableName".',
      );
    }
    return () async {
      final rows = await select();
      return rows
          .map(
            (row) => SyncRow(
              id: (row as dynamic).id as String,
              fields: entity.toSyncFields(row),
            ),
          )
          .toList(growable: false);
    };
  }

  return <String, BootstrapFetcher>{
    'members': build('members', () => db.select(db.members).get()),
    'fronting_sessions': build(
      'fronting_sessions',
      () => db.select(db.frontingSessions).get(),
    ),
    'conversations': build(
      'conversations',
      () => db.select(db.conversations).get(),
    ),
    'chat_messages': build(
      'chat_messages',
      () => db.select(db.chatMessages).get(),
    ),
    'system_settings': build(
      'system_settings',
      () => db.select(db.systemSettingsTable).get(),
    ),
    'polls': build('polls', () => db.select(db.polls).get()),
    'poll_options': build(
      'poll_options',
      () => db.select(db.pollOptions).get(),
    ),
    'poll_votes': build('poll_votes', () => db.select(db.pollVotes).get()),
    'habits': build('habits', () => db.select(db.habits).get()),
    'habit_completions': build(
      'habit_completions',
      () => db.select(db.habitCompletions).get(),
    ),
    'conversation_categories': build(
      'conversation_categories',
      () => db.select(db.conversationCategories).get(),
    ),
    'reminders': build('reminders', () => db.select(db.reminders).get()),
    'member_groups': build(
      'member_groups',
      () => db.select(db.memberGroups).get(),
    ),
    'member_group_entries': build(
      'member_group_entries',
      () => db.select(db.memberGroupEntries).get(),
    ),
    'custom_fields': build(
      'custom_fields',
      () => db.select(db.customFields).get(),
    ),
    'custom_field_values': build(
      'custom_field_values',
      () => db.select(db.customFieldValues).get(),
    ),
    'notes': build('notes', () => db.select(db.notes).get()),
    'front_session_comments': build(
      'front_session_comments',
      () => db.select(db.frontSessionComments).get(),
    ),
    'friends': build('friends', () => db.select(db.friends).get()),
    'media_attachments': build(
      'media_attachments',
      () => db.select(db.mediaAttachments).get(),
    ),
    'member_board_posts': build(
      'member_board_posts',
      () => db.select(db.memberBoardPosts).get(),
    ),
  };
}

/// Aggregate every registered table's rows into the JSON wire-shape expected
/// by `bootstrap_existing_state`:
/// ```json
/// [
///   { "table": "members", "entity_id": "...", "fields": { ... } },
///   ...
/// ]
/// ```
Future<List<Map<String, dynamic>>> buildBootstrapRecords(
  Map<String, BootstrapFetcher> fetchers,
) async {
  final records = <Map<String, dynamic>>[];
  for (final entry in fetchers.entries) {
    final rows = await entry.value();
    for (final row in rows) {
      records.add({
        'table': entry.key,
        'entity_id': row.id,
        'fields': row.fields,
      });
    }
  }
  return records;
}
