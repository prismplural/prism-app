import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

/// Wraps [DriftSyncAdapter] with a [Completer]-based batch completion signal
/// so callers can await the end of a remote-change batch instead of relying
/// on a hardcoded delay.
class SyncAdapterWithCompletion {
  SyncAdapterWithCompletion(this.adapter, this._pendingQuarantineWrites);

  final DriftSyncAdapter adapter;
  final List<Future<void>> _pendingQuarantineWrites;

  Completer<void>? _batchCompleter;

  /// Call before starting a sync to create a new completion signal.
  void beginSyncBatch() {
    _batchCompleter = Completer<void>();
  }

  /// Completes when all pending writes from the current batch are committed.
  Future<void> get syncBatchComplete =>
      _batchCompleter?.future ?? Future.value();

  /// Resolve once tracked quarantine writes for the current batch finish.
  Future<void> completeSyncBatch() async {
    final completer = _batchCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }

    final pendingWrites = List<Future<void>>.from(_pendingQuarantineWrites);
    _pendingQuarantineWrites.clear();

    for (final write in pendingWrites) {
      try {
        await write;
      } catch (_) {
        // Quarantine is diagnostic-only; sync application already succeeded.
      }
    }

    if (!completer.isCompleted) {
      completer.complete();
    }
    _batchCompleter = null;
  }
}

SyncAdapterWithCompletion buildSyncAdapterWithCompletion(
  AppDatabase db, {
  SyncQuarantineService? quarantine,
}) {
  final pendingQuarantineWrites = <Future<void>>[];
  final adapter = DriftSyncAdapter(
    entities: [
      _membersEntity(db, quarantine, pendingQuarantineWrites.add),
      _frontingSessionsEntity(db, quarantine, pendingQuarantineWrites.add),
      _conversationsEntity(db, quarantine, pendingQuarantineWrites.add),
      _chatMessagesEntity(db, quarantine, pendingQuarantineWrites.add),
      _systemSettingsEntity(db, quarantine, pendingQuarantineWrites.add),
      _pollsEntity(db, quarantine, pendingQuarantineWrites.add),
      _pollOptionsEntity(db, quarantine, pendingQuarantineWrites.add),
      _pollVotesEntity(db, quarantine, pendingQuarantineWrites.add),
      _habitsEntity(db, quarantine, pendingQuarantineWrites.add),
      _habitCompletionsEntity(db, quarantine, pendingQuarantineWrites.add),
      _conversationCategoriesEntity(
        db,
        quarantine,
        pendingQuarantineWrites.add,
      ),
      _remindersEntity(db, quarantine, pendingQuarantineWrites.add),
      _memberGroupsEntity(db, quarantine, pendingQuarantineWrites.add),
      _memberGroupEntriesEntity(db, quarantine, pendingQuarantineWrites.add),
      _customFieldsEntity(db, quarantine, pendingQuarantineWrites.add),
      _customFieldValuesEntity(db, quarantine, pendingQuarantineWrites.add),
      _notesEntity(db, quarantine, pendingQuarantineWrites.add),
      _frontSessionCommentsEntity(db, quarantine, pendingQuarantineWrites.add),
      _friendsEntity(db, quarantine, pendingQuarantineWrites.add),
      _mediaAttachmentsEntity(db, quarantine, pendingQuarantineWrites.add),
    ],
  );
  return SyncAdapterWithCompletion(adapter, pendingQuarantineWrites);
}

// ---------------------------------------------------------------------------
// Safe type-cast helpers
// ---------------------------------------------------------------------------
// These avoid TypeError when remote data has unexpected types. For non-nullable
// fields a null return means "bad data — skip this field" (use Value.absent()).

String? _asString(dynamic value) => value is String ? value : null;

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _asBool(dynamic value) => value is bool ? value : null;

DateTime? _asDateTime(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Nullable blob from base64 string.
Uint8List? _blob(dynamic v) {
  if (v is String) {
    try {
      return base64Decode(v);
    } catch (_) {
      return null;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// _FieldContext — wraps entity metadata + quarantine for field-level reporting
// ---------------------------------------------------------------------------

/// Scoped context for a single applyFields invocation. Methods mirror the
/// top-level `_*Field` helpers but additionally quarantine type mismatches
/// when a [SyncQuarantineService] is provided.
class _FieldContext {
  _FieldContext({
    required this.entityType,
    required this.entityId,
    required this.fields,
    this.quarantine,
    this.trackQuarantineWrite,
  });

  final String entityType;
  final String entityId;
  final Map<String, dynamic> fields;
  final SyncQuarantineService? quarantine;
  final void Function(Future<void> write)? trackQuarantineWrite;

  // -- Non-nullable String ---------------------------------------------------

  Value<String> stringField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asString(raw);
    if (v != null) return Value(v);
    _report(key, 'String', raw);
    return const Value.absent();
  }

  // -- Nullable String -------------------------------------------------------

  Value<String?> stringFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _asString(raw);
    if (v != null) return Value(v);
    _report(key, 'String?', raw);
    return const Value.absent();
  }

  // -- Non-nullable int ------------------------------------------------------

  Value<int> intField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asInt(raw);
    if (v != null) return Value(v);
    _report(key, 'int', raw);
    return const Value.absent();
  }

  // -- Nullable int ----------------------------------------------------------

  Value<int?> intFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _asInt(raw);
    if (v != null) return Value(v);
    _report(key, 'int?', raw);
    return const Value.absent();
  }

  // -- Non-nullable bool -----------------------------------------------------

  Value<bool> boolField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asBool(raw);
    if (v != null) return Value(v);
    _report(key, 'bool', raw);
    return const Value.absent();
  }

  // -- Non-nullable DateTime -------------------------------------------------

  Value<DateTime> dateTimeField(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    final v = _asDateTime(raw);
    if (v != null) return Value(v);
    _report(key, 'DateTime', raw);
    return const Value.absent();
  }

  // -- Nullable DateTime -----------------------------------------------------

  Value<DateTime?> dateTimeFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _asDateTime(raw);
    if (v != null) return Value(v);
    _report(key, 'DateTime?', raw);
    return const Value.absent();
  }

  // -- Nullable blob ---------------------------------------------------------

  Value<Uint8List?> blobFieldNullable(String key) {
    if (!fields.containsKey(key)) return const Value.absent();
    final raw = fields[key];
    if (raw == null) return const Value(null);
    final v = _blob(raw);
    if (v != null) return Value(v);
    _report(key, 'Uint8List?', raw);
    return const Value.absent();
  }

  // -- Internal reporting ----------------------------------------------------

  void _report(String fieldName, String expectedType, dynamic received) {
    final q = quarantine;
    if (q == null) return;
    final write = q.quarantineField(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
      expectedType: expectedType,
      receivedType: received?.runtimeType.toString() ?? 'null',
      receivedValue: _safeValuePreview(received),
      errorMessage:
          'Type mismatch: expected $expectedType, '
          'got ${received?.runtimeType ?? "null"}',
    );
    trackQuarantineWrite?.call(write);
  }

  /// Truncated string representation for diagnostics (avoid storing huge blobs).
  static String? _safeValuePreview(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    return s.length > 200 ? '${s.substring(0, 200)}...' : s;
  }
}

// ---------------------------------------------------------------------------
// members
// ---------------------------------------------------------------------------

DriftSyncEntity _membersEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'members',
    toSyncFields: (dynamic row) {
      final r = row as Member;
      return {
        'name': r.name,
        'pronouns': r.pronouns,
        'emoji': r.emoji,
        'age': r.age,
        'bio': r.bio,
        'avatar_image_data': r.avatarImageData != null
            ? base64Encode(r.avatarImageData!)
            : null,
        'is_active': r.isActive,
        'created_at': r.createdAt.toIso8601String(),
        'display_order': r.displayOrder,
        'is_admin': r.isAdmin,
        'custom_color_enabled': r.customColorEnabled,
        'custom_color_hex': r.customColorHex,
        'parent_system_id': r.parentSystemId,
        'pluralkit_uuid': r.pluralkitUuid,
        'pluralkit_id': r.pluralkitId,
        'markdown_enabled': r.markdownEnabled,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'members',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = MembersCompanion(
        id: Value(id),
        name: f.stringField('name'),
        pronouns: f.stringFieldNullable('pronouns'),
        emoji: f.stringField('emoji'),
        age: f.intFieldNullable('age'),
        bio: f.stringFieldNullable('bio'),
        avatarImageData: f.blobFieldNullable('avatar_image_data'),
        isActive: f.boolField('is_active'),
        createdAt: f.dateTimeField('created_at'),
        displayOrder: f.intField('display_order'),
        isAdmin: f.boolField('is_admin'),
        customColorEnabled: f.boolField('custom_color_enabled'),
        customColorHex: f.stringFieldNullable('custom_color_hex'),
        parentSystemId: f.stringFieldNullable('parent_system_id'),
        pluralkitUuid: f.stringFieldNullable('pluralkit_uuid'),
        pluralkitId: f.stringFieldNullable('pluralkit_id'),
        markdownEnabled: f.boolField('markdown_enabled'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.members).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.members)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.members,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'pronouns': row.pronouns,
        'emoji': row.emoji,
        'age': row.age,
        'bio': row.bio,
        'avatar_image_data': row.avatarImageData != null
            ? base64Encode(row.avatarImageData!)
            : null,
        'is_active': row.isActive,
        'created_at': row.createdAt.toIso8601String(),
        'display_order': row.displayOrder,
        'is_admin': row.isAdmin,
        'custom_color_enabled': row.customColorEnabled,
        'custom_color_hex': row.customColorHex,
        'parent_system_id': row.parentSystemId,
        'pluralkit_uuid': row.pluralkitUuid,
        'pluralkit_id': row.pluralkitId,
        'markdown_enabled': row.markdownEnabled,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.members,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// fronting_sessions
// ---------------------------------------------------------------------------

DriftSyncEntity _frontingSessionsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'fronting_sessions',
    toSyncFields: (dynamic row) {
      final r = row as FrontingSession;
      return {
        'start_time': r.startTime.toIso8601String(),
        'end_time': r.endTime?.toIso8601String(),
        'member_id': r.memberId,
        'co_fronter_ids': r.coFronterIds,
        'notes': r.notes,
        'confidence': r.confidence,
        'session_type': r.sessionType,
        'quality': r.quality,
        'is_health_kit_import': r.isHealthKitImport,
        'pluralkit_uuid': r.pluralkitUuid,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'fronting_sessions',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = FrontingSessionsCompanion(
        id: Value(id),
        startTime: f.dateTimeField('start_time'),
        endTime: f.dateTimeFieldNullable('end_time'),
        memberId: f.stringFieldNullable('member_id'),
        coFronterIds: f.stringField('co_fronter_ids'),
        notes: f.stringFieldNullable('notes'),
        confidence: f.intFieldNullable('confidence'),
        sessionType: f.intField('session_type'),
        quality: f.intFieldNullable('quality'),
        isHealthKitImport: f.boolField('is_health_kit_import'),
        pluralkitUuid: f.stringFieldNullable('pluralkit_uuid'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.frontingSessions).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.frontingSessions,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'start_time': row.startTime.toIso8601String(),
        'end_time': row.endTime?.toIso8601String(),
        'member_id': row.memberId,
        'co_fronter_ids': row.coFronterIds,
        'notes': row.notes,
        'confidence': row.confidence,
        'session_type': row.sessionType,
        'quality': row.quality,
        'is_health_kit_import': row.isHealthKitImport,
        'pluralkit_uuid': row.pluralkitUuid,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.frontingSessions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// conversations
// ---------------------------------------------------------------------------

DriftSyncEntity _conversationsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'conversations',
    toSyncFields: (dynamic row) {
      final r = row as Conversation;
      return {
        'created_at': r.createdAt.toIso8601String(),
        'last_activity_at': r.lastActivityAt.toIso8601String(),
        'title': r.title,
        'emoji': r.emoji,
        'is_direct_message': r.isDirectMessage,
        'creator_id': r.creatorId,
        'participant_ids': r.participantIds,
        'archived_by_member_ids': r.archivedByMemberIds,
        'last_read_timestamps': r.lastReadTimestamps,
        'description': r.description,
        'category_id': r.categoryId,
        'display_order': r.displayOrder,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'conversations',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = ConversationsCompanion(
        id: Value(id),
        createdAt: f.dateTimeField('created_at'),
        lastActivityAt: f.dateTimeField('last_activity_at'),
        title: f.stringFieldNullable('title'),
        emoji: f.stringFieldNullable('emoji'),
        isDirectMessage: f.boolField('is_direct_message'),
        creatorId: f.stringFieldNullable('creator_id'),
        participantIds: f.stringField('participant_ids'),
        archivedByMemberIds: f.stringField('archived_by_member_ids'),
        lastReadTimestamps: f.stringField('last_read_timestamps'),
        description: f.stringFieldNullable('description'),
        categoryId: f.stringFieldNullable('category_id'),
        displayOrder: f.intField('display_order'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.conversations).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.conversations)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.conversations,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'created_at': row.createdAt.toIso8601String(),
        'last_activity_at': row.lastActivityAt.toIso8601String(),
        'title': row.title,
        'emoji': row.emoji,
        'is_direct_message': row.isDirectMessage,
        'creator_id': row.creatorId,
        'participant_ids': row.participantIds,
        'archived_by_member_ids': row.archivedByMemberIds,
        'last_read_timestamps': row.lastReadTimestamps,
        'description': row.description,
        'category_id': row.categoryId,
        'display_order': row.displayOrder,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.conversations,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// chat_messages
// ---------------------------------------------------------------------------

DriftSyncEntity _chatMessagesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'chat_messages',
    toSyncFields: (dynamic row) {
      final r = row as ChatMessage;
      return {
        'content': r.content,
        'timestamp': r.timestamp.toIso8601String(),
        'is_system_message': r.isSystemMessage,
        'edited_at': r.editedAt?.toIso8601String(),
        'author_id': r.authorId,
        'conversation_id': r.conversationId,
        'reactions': r.reactions,
        'reply_to_id': r.replyToId,
        'reply_to_author_id': r.replyToAuthorId,
        'reply_to_content': r.replyToContent,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'chat_messages',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = ChatMessagesCompanion(
        id: Value(id),
        content: f.stringField('content'),
        timestamp: f.dateTimeField('timestamp'),
        isSystemMessage: f.boolField('is_system_message'),
        editedAt: f.dateTimeFieldNullable('edited_at'),
        authorId: f.stringFieldNullable('author_id'),
        conversationId: f.stringField('conversation_id'),
        reactions: f.stringField('reactions'),
        replyToId: f.stringFieldNullable('reply_to_id'),
        replyToAuthorId: f.stringFieldNullable('reply_to_author_id'),
        replyToContent: f.stringFieldNullable('reply_to_content'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.chatMessages).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.chatMessages)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.chatMessages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'content': row.content,
        'timestamp': row.timestamp.toIso8601String(),
        'is_system_message': row.isSystemMessage,
        'edited_at': row.editedAt?.toIso8601String(),
        'author_id': row.authorId,
        'conversation_id': row.conversationId,
        'reactions': row.reactions,
        'reply_to_id': row.replyToId,
        'reply_to_author_id': row.replyToAuthorId,
        'reply_to_content': row.replyToContent,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.chatMessages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// system_settings
// ---------------------------------------------------------------------------

DriftSyncEntity _systemSettingsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'system_settings',
    toSyncFields: (dynamic row) {
      final r = row as SystemSettingsData;
      return {
        'system_name': r.systemName,
        'sharing_id': r.sharingId,
        'show_quick_front': r.showQuickFront,
        'accent_color_hex': r.accentColorHex,
        'per_member_accent_colors': r.perMemberAccentColors,
        'terminology': r.terminology,
        'custom_terminology': r.customTerminology,
        'custom_plural_terminology': r.customPluralTerminology,
        'fronting_reminders_enabled': r.frontingRemindersEnabled,
        'fronting_reminder_interval_minutes': r.frontingReminderIntervalMinutes,
        'theme_mode': r.themeMode,
        'theme_brightness': r.themeBrightness,
        'theme_style': r.themeStyle,
        'chat_enabled': r.chatEnabled,
        'polls_enabled': r.pollsEnabled,
        'habits_enabled': r.habitsEnabled,
        'sleep_tracking_enabled': r.sleepTrackingEnabled,
        'quick_switch_threshold_seconds': r.quickSwitchThresholdSeconds,
        // has_completed_onboarding excluded — local-only (see applyFields)
        'chat_logs_front': r.chatLogsFront,
        'sync_theme_enabled': r.syncThemeEnabled,
        'timing_mode': r.timingMode,
        'notes_enabled': r.notesEnabled,
        'system_description': r.systemDescription,
        'system_avatar_data': r.systemAvatarData != null
            ? base64Encode(r.systemAvatarData!)
            : null,
        'reminders_enabled': r.remindersEnabled,
        'sync_navigation_enabled': r.syncNavigationEnabled,
        'nav_bar_items': r.navBarItems,
        'nav_bar_overflow_items': r.navBarOverflowItems,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'system_settings',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = SystemSettingsTableCompanion(
        id: Value(id),
        systemName: f.stringFieldNullable('system_name'),
        sharingId: f.stringFieldNullable('sharing_id'),
        showQuickFront: f.boolField('show_quick_front'),
        accentColorHex: f.stringField('accent_color_hex'),
        perMemberAccentColors: f.boolField('per_member_accent_colors'),
        terminology: f.intField('terminology'),
        customTerminology: f.stringFieldNullable('custom_terminology'),
        customPluralTerminology: f.stringFieldNullable(
          'custom_plural_terminology',
        ),
        frontingRemindersEnabled: f.boolField('fronting_reminders_enabled'),
        frontingReminderIntervalMinutes: f.intField(
          'fronting_reminder_interval_minutes',
        ),
        themeMode: f.intField('theme_mode'),
        themeBrightness: f.intField('theme_brightness'),
        themeStyle: f.intField('theme_style'),
        chatEnabled: f.boolField('chat_enabled'),
        pollsEnabled: f.boolField('polls_enabled'),
        habitsEnabled: f.boolField('habits_enabled'),
        sleepTrackingEnabled: f.boolField('sleep_tracking_enabled'),
        quickSwitchThresholdSeconds: f.intField(
          'quick_switch_threshold_seconds',
        ),
        // has_completed_onboarding is intentionally excluded — it must remain
        // local-only so that a remote `true` value cannot skip onboarding on a
        // new device via CRDT sync.
        chatLogsFront: f.boolField('chat_logs_front'),
        syncThemeEnabled: f.boolField('sync_theme_enabled'),
        timingMode: f.intField('timing_mode'),
        notesEnabled: f.boolField('notes_enabled'),
        systemDescription: f.stringFieldNullable('system_description'),
        systemAvatarData: f.blobFieldNullable('system_avatar_data'),
        remindersEnabled: f.boolField('reminders_enabled'),
        syncNavigationEnabled: f.boolField('sync_navigation_enabled'),
        navBarItems: f.stringField('nav_bar_items'),
        navBarOverflowItems: f.stringField('nav_bar_overflow_items'),
        // Device-local fields (font*, pin*, biometric*, autoLock*) are
        // intentionally excluded from sync.
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.systemSettingsTable).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.systemSettingsTable,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.systemSettingsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'system_name': row.systemName,
        'sharing_id': row.sharingId,
        'show_quick_front': row.showQuickFront,
        'accent_color_hex': row.accentColorHex,
        'per_member_accent_colors': row.perMemberAccentColors,
        'terminology': row.terminology,
        'custom_terminology': row.customTerminology,
        'custom_plural_terminology': row.customPluralTerminology,
        'fronting_reminders_enabled': row.frontingRemindersEnabled,
        'fronting_reminder_interval_minutes':
            row.frontingReminderIntervalMinutes,
        'theme_mode': row.themeMode,
        'theme_brightness': row.themeBrightness,
        'theme_style': row.themeStyle,
        'chat_enabled': row.chatEnabled,
        'polls_enabled': row.pollsEnabled,
        'habits_enabled': row.habitsEnabled,
        'sleep_tracking_enabled': row.sleepTrackingEnabled,
        'quick_switch_threshold_seconds': row.quickSwitchThresholdSeconds,
        // has_completed_onboarding excluded — local-only (see applyFields)
        'chat_logs_front': row.chatLogsFront,
        'sync_theme_enabled': row.syncThemeEnabled,
        'timing_mode': row.timingMode,
        'notes_enabled': row.notesEnabled,
        'system_description': row.systemDescription,
        'system_avatar_data': row.systemAvatarData != null
            ? base64Encode(row.systemAvatarData!)
            : null,
        'reminders_enabled': row.remindersEnabled,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.systemSettingsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// polls
// ---------------------------------------------------------------------------

DriftSyncEntity _pollsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'polls',
    toSyncFields: (dynamic row) {
      final r = row as Poll;
      return {
        'question': r.question,
        'description': r.description,
        'is_anonymous': r.isAnonymous,
        'allows_multiple_votes': r.allowsMultipleVotes,
        'is_closed': r.isClosed,
        'expires_at': r.expiresAt?.toIso8601String(),
        'created_at': r.createdAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'polls',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = PollsCompanion(
        id: Value(id),
        question: f.stringField('question'),
        description: f.stringFieldNullable('description'),
        isAnonymous: f.boolField('is_anonymous'),
        allowsMultipleVotes: f.boolField('allows_multiple_votes'),
        isClosed: f.boolField('is_closed'),
        expiresAt: f.dateTimeFieldNullable('expires_at'),
        createdAt: f.dateTimeField('created_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.polls).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.polls)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.polls,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'question': row.question,
        'description': row.description,
        'is_anonymous': row.isAnonymous,
        'allows_multiple_votes': row.allowsMultipleVotes,
        'is_closed': row.isClosed,
        'expires_at': row.expiresAt?.toIso8601String(),
        'created_at': row.createdAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.polls,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// poll_options
// ---------------------------------------------------------------------------

DriftSyncEntity _pollOptionsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'poll_options',
    toSyncFields: (dynamic row) {
      final r = row as PollOption;
      return {
        'poll_id': r.pollId,
        'option_text': r.optionText,
        'sort_order': r.sortOrder,
        'is_other_option': r.isOtherOption,
        'color_hex': r.colorHex,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'poll_options',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = PollOptionsCompanion(
        id: Value(id),
        pollId: f.stringField('poll_id'),
        optionText: f.stringField('option_text'),
        sortOrder: f.intField('sort_order'),
        isOtherOption: f.boolField('is_other_option'),
        colorHex: f.stringFieldNullable('color_hex'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.pollOptions).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.pollOptions)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.pollOptions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'poll_id': row.pollId,
        'option_text': row.optionText,
        'sort_order': row.sortOrder,
        'is_other_option': row.isOtherOption,
        'color_hex': row.colorHex,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.pollOptions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// poll_votes
// ---------------------------------------------------------------------------

DriftSyncEntity _pollVotesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'poll_votes',
    toSyncFields: (dynamic row) {
      final r = row as PollVote;
      return {
        'poll_option_id': r.pollOptionId,
        'member_id': r.memberId,
        'voted_at': r.votedAt.toIso8601String(),
        'response_text': r.responseText,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'poll_votes',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = PollVotesCompanion(
        id: Value(id),
        pollOptionId: f.stringField('poll_option_id'),
        memberId: f.stringField('member_id'),
        votedAt: f.dateTimeField('voted_at'),
        responseText: f.stringFieldNullable('response_text'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.pollVotes).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.pollVotes)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.pollVotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'poll_option_id': row.pollOptionId,
        'member_id': row.memberId,
        'voted_at': row.votedAt.toIso8601String(),
        'response_text': row.responseText,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.pollVotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// habits
// ---------------------------------------------------------------------------

DriftSyncEntity _habitsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'habits',
    toSyncFields: (dynamic row) {
      final r = row as Habit;
      return {
        'name': r.name,
        'description': r.description,
        'icon': r.icon,
        'color_hex': r.colorHex,
        'is_active': r.isActive,
        'created_at': r.createdAt.toIso8601String(),
        'modified_at': r.modifiedAt.toIso8601String(),
        'frequency': r.frequency,
        'weekly_days': r.weeklyDays,
        'interval_days': r.intervalDays,
        'reminder_time': r.reminderTime,
        'notifications_enabled': r.notificationsEnabled,
        'notification_message': r.notificationMessage,
        'assigned_member_id': r.assignedMemberId,
        'only_notify_when_fronting': r.onlyNotifyWhenFronting,
        'is_private': r.isPrivate,
        'current_streak': r.currentStreak,
        'best_streak': r.bestStreak,
        'total_completions': r.totalCompletions,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'habits',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = HabitsCompanion(
        id: Value(id),
        name: f.stringField('name'),
        description: f.stringFieldNullable('description'),
        icon: f.stringFieldNullable('icon'),
        colorHex: f.stringFieldNullable('color_hex'),
        isActive: f.boolField('is_active'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        frequency: f.stringField('frequency'),
        weeklyDays: f.stringFieldNullable('weekly_days'),
        intervalDays: f.intFieldNullable('interval_days'),
        reminderTime: f.stringFieldNullable('reminder_time'),
        notificationsEnabled: f.boolField('notifications_enabled'),
        notificationMessage: f.stringFieldNullable('notification_message'),
        assignedMemberId: f.stringFieldNullable('assigned_member_id'),
        onlyNotifyWhenFronting: f.boolField('only_notify_when_fronting'),
        isPrivate: f.boolField('is_private'),
        currentStreak: f.intField('current_streak'),
        bestStreak: f.intField('best_streak'),
        totalCompletions: f.intField('total_completions'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.habits).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.habits)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.habits,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'description': row.description,
        'icon': row.icon,
        'color_hex': row.colorHex,
        'is_active': row.isActive,
        'created_at': row.createdAt.toIso8601String(),
        'modified_at': row.modifiedAt.toIso8601String(),
        'frequency': row.frequency,
        'weekly_days': row.weeklyDays,
        'interval_days': row.intervalDays,
        'reminder_time': row.reminderTime,
        'notifications_enabled': row.notificationsEnabled,
        'notification_message': row.notificationMessage,
        'assigned_member_id': row.assignedMemberId,
        'only_notify_when_fronting': row.onlyNotifyWhenFronting,
        'is_private': row.isPrivate,
        'current_streak': row.currentStreak,
        'best_streak': row.bestStreak,
        'total_completions': row.totalCompletions,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.habits,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// habit_completions
// ---------------------------------------------------------------------------

DriftSyncEntity _habitCompletionsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'habit_completions',
    toSyncFields: (dynamic row) {
      final r = row as HabitCompletion;
      return {
        'habit_id': r.habitId,
        'completed_at': r.completedAt.toIso8601String(),
        'completed_by_member_id': r.completedByMemberId,
        'notes': r.notes,
        'was_fronting': r.wasFronting,
        'rating': r.rating,
        'created_at': r.createdAt.toIso8601String(),
        'modified_at': r.modifiedAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'habit_completions',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = HabitCompletionsCompanion(
        id: Value(id),
        habitId: f.stringField('habit_id'),
        completedAt: f.dateTimeField('completed_at'),
        completedByMemberId: f.stringFieldNullable('completed_by_member_id'),
        notes: f.stringFieldNullable('notes'),
        wasFronting: f.boolField('was_fronting'),
        rating: f.intFieldNullable('rating'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.habitCompletions).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.habitCompletions,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.habitCompletions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'habit_id': row.habitId,
        'completed_at': row.completedAt.toIso8601String(),
        'completed_by_member_id': row.completedByMemberId,
        'notes': row.notes,
        'was_fronting': row.wasFronting,
        'rating': row.rating,
        'created_at': row.createdAt.toIso8601String(),
        'modified_at': row.modifiedAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.habitCompletions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// conversation_categories
// ---------------------------------------------------------------------------

DriftSyncEntity _conversationCategoriesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'conversation_categories',
    toSyncFields: (dynamic row) {
      final r = row as ConversationCategoryRow;
      return {
        'name': r.name,
        'display_order': r.displayOrder,
        'created_at': r.createdAt.toIso8601String(),
        'modified_at': r.modifiedAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'conversation_categories',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = ConversationCategoriesCompanion(
        id: Value(id),
        name: f.stringField('name'),
        displayOrder: f.intField('display_order'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db
          .into(db.conversationCategories)
          .insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.conversationCategories,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.conversationCategories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'display_order': row.displayOrder,
        'created_at': row.createdAt.toIso8601String(),
        'modified_at': row.modifiedAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.conversationCategories,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// reminders
// ---------------------------------------------------------------------------

DriftSyncEntity _remindersEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'reminders',
    toSyncFields: (dynamic row) {
      final r = row as ReminderRow;
      return {
        'name': r.name,
        'message': r.message,
        'trigger': r.trigger,
        'interval_days': r.intervalDays,
        'time_of_day': r.timeOfDay,
        'delay_hours': r.delayHours,
        'is_active': r.isActive,
        'created_at': r.createdAt.toIso8601String(),
        'modified_at': r.modifiedAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'reminders',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = RemindersCompanion(
        id: Value(id),
        name: f.stringField('name'),
        message: f.stringField('message'),
        trigger: f.intField('trigger'),
        intervalDays: f.intFieldNullable('interval_days'),
        timeOfDay: f.stringFieldNullable('time_of_day'),
        delayHours: f.intFieldNullable('delay_hours'),
        isActive: f.boolField('is_active'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.reminders).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.reminders)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.reminders,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'message': row.message,
        'trigger': row.trigger,
        'interval_days': row.intervalDays,
        'time_of_day': row.timeOfDay,
        'delay_hours': row.delayHours,
        'is_active': row.isActive,
        'created_at': row.createdAt.toIso8601String(),
        'modified_at': row.modifiedAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.reminders,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// member_groups
// ---------------------------------------------------------------------------

DriftSyncEntity _memberGroupsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'member_groups',
    toSyncFields: (dynamic row) {
      final r = row as MemberGroupRow;
      return {
        'name': r.name,
        'description': r.description,
        'color_hex': r.colorHex,
        'emoji': r.emoji,
        'display_order': r.displayOrder,
        'parent_group_id': r.parentGroupId,
        'created_at': r.createdAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'member_groups',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = MemberGroupsCompanion(
        id: Value(id),
        name: f.stringField('name'),
        description: f.stringFieldNullable('description'),
        colorHex: f.stringFieldNullable('color_hex'),
        emoji: f.stringFieldNullable('emoji'),
        displayOrder: f.intField('display_order'),
        parentGroupId: f.stringFieldNullable('parent_group_id'),
        createdAt: f.dateTimeField('created_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.memberGroups).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.memberGroups)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'description': row.description,
        'color_hex': row.colorHex,
        'emoji': row.emoji,
        'display_order': row.displayOrder,
        'parent_group_id': row.parentGroupId,
        'created_at': row.createdAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// member_group_entries
// ---------------------------------------------------------------------------

DriftSyncEntity _memberGroupEntriesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'member_group_entries',
    toSyncFields: (dynamic row) {
      final r = row as MemberGroupEntryRow;
      return {
        'group_id': r.groupId,
        'member_id': r.memberId,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'member_group_entries',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = MemberGroupEntriesCompanion(
        id: Value(id),
        groupId: f.stringField('group_id'),
        memberId: f.stringField('member_id'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.memberGroupEntries).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'group_id': row.groupId,
        'member_id': row.memberId,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// custom_fields
// ---------------------------------------------------------------------------

DriftSyncEntity _customFieldsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'custom_fields',
    toSyncFields: (dynamic row) {
      final r = row as CustomFieldRow;
      return {
        'name': r.name,
        'field_type': r.fieldType,
        'date_precision': r.datePrecision,
        'display_order': r.displayOrder,
        'created_at': r.createdAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'custom_fields',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = CustomFieldsCompanion(
        id: Value(id),
        name: f.stringField('name'),
        fieldType: f.intField('field_type'),
        datePrecision: f.intFieldNullable('date_precision'),
        displayOrder: f.intField('display_order'),
        createdAt: f.dateTimeField('created_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.customFields).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.customFields)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.customFields,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'name': row.name,
        'field_type': row.fieldType,
        'date_precision': row.datePrecision,
        'display_order': row.displayOrder,
        'created_at': row.createdAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.customFields,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// custom_field_values
// ---------------------------------------------------------------------------

DriftSyncEntity _customFieldValuesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'custom_field_values',
    toSyncFields: (dynamic row) {
      final r = row as CustomFieldValueRow;
      return {
        'custom_field_id': r.customFieldId,
        'member_id': r.memberId,
        'value': r.value,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'custom_field_values',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = CustomFieldValuesCompanion(
        id: Value(id),
        customFieldId: f.stringField('custom_field_id'),
        memberId: f.stringField('member_id'),
        value: f.stringField('value'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.customFieldValues).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.customFieldValues,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.customFieldValues,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'custom_field_id': row.customFieldId,
        'member_id': row.memberId,
        'value': row.value,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.customFieldValues,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// notes
// ---------------------------------------------------------------------------

DriftSyncEntity _notesEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'notes',
    toSyncFields: (dynamic row) {
      final r = row as NoteRow;
      return {
        'title': r.title,
        'body': r.body,
        'color_hex': r.colorHex,
        'member_id': r.memberId,
        'date': r.date.toIso8601String(),
        'created_at': r.createdAt.toIso8601String(),
        'modified_at': r.modifiedAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'notes',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = NotesCompanion(
        id: Value(id),
        title: f.stringField('title'),
        body: f.stringField('body'),
        colorHex: f.stringFieldNullable('color_hex'),
        memberId: f.stringFieldNullable('member_id'),
        date: f.dateTimeField('date'),
        createdAt: f.dateTimeField('created_at'),
        modifiedAt: f.dateTimeField('modified_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.notes).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.notes)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.notes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'title': row.title,
        'body': row.body,
        'color_hex': row.colorHex,
        'member_id': row.memberId,
        'date': row.date.toIso8601String(),
        'created_at': row.createdAt.toIso8601String(),
        'modified_at': row.modifiedAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.notes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// front_session_comments
// ---------------------------------------------------------------------------

DriftSyncEntity _frontSessionCommentsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'front_session_comments',
    toSyncFields: (dynamic row) {
      final r = row as FrontSessionCommentRow;
      return {
        'session_id': r.sessionId,
        'body': r.body,
        'timestamp': r.timestamp.toIso8601String(),
        'created_at': r.createdAt.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'front_session_comments',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = FrontSessionCommentsCompanion(
        id: Value(id),
        sessionId: f.stringField('session_id'),
        body: f.stringField('body'),
        timestamp: f.dateTimeField('timestamp'),
        createdAt: f.dateTimeField('created_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.frontSessionComments).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(
        db.frontSessionComments,
      )..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'session_id': row.sessionId,
        'body': row.body,
        'timestamp': row.timestamp.toIso8601String(),
        'created_at': row.createdAt.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// friends
// ---------------------------------------------------------------------------

DriftSyncEntity _friendsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'friends',
    toSyncFields: (dynamic row) {
      final r = row as FriendRow;
      return {
        'display_name': r.displayName,
        'peer_sharing_id': r.peerSharingId,
        'pairwise_secret': r.pairwiseSecret != null
            ? base64Encode(r.pairwiseSecret!)
            : null,
        'pinned_identity': r.pinnedIdentity != null
            ? base64Encode(r.pinnedIdentity!)
            : null,
        'offered_scopes': r.offeredScopes,
        'public_key_hex': r.publicKeyHex,
        'shared_secret_hex': r.sharedSecretHex,
        'granted_scopes': r.grantedScopes,
        'is_verified': r.isVerified,
        'init_id': r.initId,
        'created_at': r.createdAt.toIso8601String(),
        'established_at': r.establishedAt?.toIso8601String(),
        'last_sync_at': r.lastSyncAt?.toIso8601String(),
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'friends',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = FriendsCompanion(
        id: Value(id),
        displayName: f.stringField('display_name'),
        peerSharingId: f.stringFieldNullable('peer_sharing_id'),
        pairwiseSecret: f.blobFieldNullable('pairwise_secret'),
        pinnedIdentity: f.blobFieldNullable('pinned_identity'),
        offeredScopes: f.stringField('offered_scopes'),
        publicKeyHex: f.stringField('public_key_hex'),
        sharedSecretHex: f.stringFieldNullable('shared_secret_hex'),
        grantedScopes: f.stringField('granted_scopes'),
        isVerified: f.boolField('is_verified'),
        initId: f.stringFieldNullable('init_id'),
        createdAt: f.dateTimeField('created_at'),
        establishedAt: f.dateTimeFieldNullable('established_at'),
        lastSyncAt: f.dateTimeFieldNullable('last_sync_at'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.friends).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.friends)..where((t) => t.id.equals(id))).go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.friends,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'display_name': row.displayName,
        'peer_sharing_id': row.peerSharingId,
        'pairwise_secret': row.pairwiseSecret != null
            ? base64Encode(row.pairwiseSecret!)
            : null,
        'pinned_identity': row.pinnedIdentity != null
            ? base64Encode(row.pinnedIdentity!)
            : null,
        'offered_scopes': row.offeredScopes,
        'public_key_hex': row.publicKeyHex,
        'shared_secret_hex': row.sharedSecretHex,
        'granted_scopes': row.grantedScopes,
        'is_verified': row.isVerified,
        'init_id': row.initId,
        'created_at': row.createdAt.toIso8601String(),
        'established_at': row.establishedAt?.toIso8601String(),
        'last_sync_at': row.lastSyncAt?.toIso8601String(),
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.friends,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}

// ---------------------------------------------------------------------------
// media_attachments
// ---------------------------------------------------------------------------

DriftSyncEntity _mediaAttachmentsEntity(
  AppDatabase db,
  SyncQuarantineService? quarantine,
  void Function(Future<void> write) trackQuarantineWrite,
) {
  return DriftSyncEntity(
    tableName: 'media_attachments',
    toSyncFields: (dynamic row) {
      final r = row as MediaAttachment;
      return {
        'message_id': r.messageId,
        'media_id': r.mediaId,
        'media_type': r.mediaType,
        'encryption_key_b64': r.encryptionKeyB64,
        'content_hash': r.contentHash,
        'plaintext_hash': r.plaintextHash,
        'mime_type': r.mimeType,
        'size_bytes': r.sizeBytes,
        'width': r.width,
        'height': r.height,
        'duration_ms': r.durationMs,
        'blurhash': r.blurhash,
        'waveform_b64': r.waveformB64,
        'thumbnail_media_id': r.thumbnailMediaId,
        'source_url': r.sourceUrl,
        'preview_url': r.previewUrl,
        'is_deleted': r.isDeleted,
      };
    },
    applyFields: (String id, Map<String, dynamic> fields) async {
      final f = _FieldContext(
        entityType: 'media_attachments',
        entityId: id,
        fields: fields,
        quarantine: quarantine,
        trackQuarantineWrite: trackQuarantineWrite,
      );
      final companion = MediaAttachmentsCompanion(
        id: Value(id),
        messageId: f.stringField('message_id'),
        mediaId: f.stringField('media_id'),
        mediaType: f.stringField('media_type'),
        encryptionKeyB64: f.stringField('encryption_key_b64'),
        contentHash: f.stringField('content_hash'),
        plaintextHash: f.stringField('plaintext_hash'),
        mimeType: f.stringField('mime_type'),
        sizeBytes: f.intField('size_bytes'),
        width: f.intField('width'),
        height: f.intField('height'),
        durationMs: f.intField('duration_ms'),
        blurhash: f.stringField('blurhash'),
        waveformB64: f.stringField('waveform_b64'),
        thumbnailMediaId: f.stringField('thumbnail_media_id'),
        sourceUrl: f.stringField('source_url'),
        previewUrl: f.stringField('preview_url'),
        isDeleted: f.boolField('is_deleted'),
      );
      await db.into(db.mediaAttachments).insertOnConflictUpdate(companion);
    },
    hardDelete: (String id) async {
      await (db.delete(db.mediaAttachments)..where((t) => t.id.equals(id)))
          .go();
    },
    readRow: (String id) async {
      final row = await (db.select(
        db.mediaAttachments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) return null;
      return {
        'message_id': row.messageId,
        'media_id': row.mediaId,
        'media_type': row.mediaType,
        'encryption_key_b64': row.encryptionKeyB64,
        'content_hash': row.contentHash,
        'plaintext_hash': row.plaintextHash,
        'mime_type': row.mimeType,
        'size_bytes': row.sizeBytes,
        'width': row.width,
        'height': row.height,
        'duration_ms': row.durationMs,
        'blurhash': row.blurhash,
        'waveform_b64': row.waveformB64,
        'thumbnail_media_id': row.thumbnailMediaId,
        'source_url': row.sourceUrl,
        'preview_url': row.previewUrl,
        'is_deleted': row.isDeleted,
      };
    },
    isDeleted: (String id) async {
      final row = await (db.select(
        db.mediaAttachments,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row?.isDeleted ?? true;
    },
  );
}
