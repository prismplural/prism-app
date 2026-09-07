-- Immutable historical schema fixture for Prism v0.13.1.
--
-- Provenance:
--   annotated release tag: v0.13.1
--   tag target: 6a412badd53c676c1749e0ed1551a04000bf3079
--   released AppDatabase.currentSchemaVersion: 38
--
-- Construction recipe:
--   1. Check out the exact tag and resolve its committed dependencies.
--   2. Open an empty SQLite file through that tag's AppDatabase and issue a
--      query to materialize its normal onCreate schema.
--   3. Export non-internal sqlite_master SQL ordered as tables, indexes, then
--      triggers; retain the v38 PRAGMA below.
--   4. Exclude FTS5 shadow-table DDL (chat_messages_fts_{config,content,data,
--      docsize,idx}): SQLite creates those from the retained virtual-table DDL.
--
-- Synthetic data belongs in the consuming test. Do not regenerate this from
-- the current AppDatabase or by dropping current columns: this captures the
-- released v38 schema as its independent starting point.

CREATE TABLE "app_preference_values" ("key" TEXT NOT NULL, "value_type" TEXT NOT NULL, "value_json" TEXT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("key"));

CREATE TABLE "chat_messages" ("id" TEXT NOT NULL, "content" TEXT NOT NULL, "timestamp" INTEGER NOT NULL, "is_system_message" INTEGER NOT NULL DEFAULT 0 CHECK ("is_system_message" IN (0, 1)), "edited_at" INTEGER NULL, "author_id" TEXT NULL, "conversation_id" TEXT NOT NULL, "reactions" TEXT NOT NULL DEFAULT '[]', "reply_to_id" TEXT NULL, "reply_to_author_id" TEXT NULL, "reply_to_content" TEXT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE VIRTUAL TABLE chat_messages_fts USING fts5(
        content,
        message_id UNINDEXED,
        conversation_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2',
        prefix='2 3 4'
      );

CREATE TABLE "conversation_categories" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "display_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "modified_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "conversations" ("id" TEXT NOT NULL, "created_at" INTEGER NOT NULL, "last_activity_at" INTEGER NOT NULL, "title" TEXT NULL, "emoji" TEXT NULL, "is_direct_message" INTEGER NOT NULL DEFAULT 0 CHECK ("is_direct_message" IN (0, 1)), "creator_id" TEXT NULL, "participant_ids" TEXT NOT NULL DEFAULT '[]', "last_read_timestamps" TEXT NOT NULL DEFAULT '{}', "archived_by_member_ids" TEXT NOT NULL DEFAULT '[]', "muted_by_member_ids" TEXT NOT NULL DEFAULT '[]', "description" TEXT NULL, "category_id" TEXT NULL, "display_order" INTEGER NOT NULL DEFAULT 0, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "includes_all_members" INTEGER NOT NULL DEFAULT 0 CHECK ("includes_all_members" IN (0, 1)), "archived_for_everyone" INTEGER NOT NULL DEFAULT 0 CHECK ("archived_for_everyone" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "custom_field_values" ("id" TEXT NOT NULL, "custom_field_id" TEXT NOT NULL, "member_id" TEXT NOT NULL, "value" TEXT NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "custom_fields" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "field_type" INTEGER NOT NULL, "date_precision" INTEGER NULL, "display_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "field_type_id" TEXT NULL, "parent_field_id" TEXT NULL, "type_config_json" TEXT NULL, PRIMARY KEY ("id"));

CREATE TABLE "friends" ("id" TEXT NOT NULL, "display_name" TEXT NOT NULL, "peer_sharing_id" TEXT NULL, "pairwise_secret" BLOB NULL, "pinned_identity" BLOB NULL, "offered_scopes" TEXT NOT NULL DEFAULT '[]', "public_key_hex" TEXT NOT NULL, "shared_secret_hex" TEXT NULL, "granted_scopes" TEXT NOT NULL DEFAULT '[]', "is_verified" INTEGER NOT NULL DEFAULT 0 CHECK ("is_verified" IN (0, 1)), "init_id" TEXT NULL, "created_at" INTEGER NOT NULL, "established_at" INTEGER NULL, "last_sync_at" INTEGER NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "front_session_comments" ("id" TEXT NOT NULL, "session_id" TEXT NOT NULL, "body" TEXT NOT NULL, "timestamp" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "fronting_sessions" ("id" TEXT NOT NULL, "session_type" INTEGER NOT NULL DEFAULT 0, "start_time" INTEGER NOT NULL, "end_time" INTEGER NULL, "member_id" TEXT NULL, "co_fronter_ids" TEXT NOT NULL DEFAULT '[]', "notes" TEXT NULL, "confidence" INTEGER NULL, "quality" INTEGER NULL, "is_health_kit_import" INTEGER NOT NULL DEFAULT 0 CHECK ("is_health_kit_import" IN (0, 1)), "pluralkit_uuid" TEXT NULL, "pk_import_source" TEXT NULL, "pk_file_switch_id" TEXT NULL, "pk_member_ids_json" TEXT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "delete_intent_epoch" INTEGER NULL, "delete_push_started_at" INTEGER NULL, PRIMARY KEY ("id"), CHECK (session_type != 0 OR member_id IS NOT NULL));

CREATE TABLE "habit_completions" ("id" TEXT NOT NULL, "habit_id" TEXT NOT NULL, "completed_at" INTEGER NOT NULL, "completed_by_member_id" TEXT NULL, "notes" TEXT NULL, "was_fronting" INTEGER NOT NULL DEFAULT 0 CHECK ("was_fronting" IN (0, 1)), "rating" INTEGER NULL, "created_at" INTEGER NOT NULL, "modified_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "habits" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "description" TEXT NULL, "icon" TEXT NULL, "color_hex" TEXT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)), "created_at" INTEGER NOT NULL, "modified_at" INTEGER NOT NULL, "frequency" TEXT NOT NULL DEFAULT 'daily', "weekly_days" TEXT NULL, "interval_days" INTEGER NULL, "reminder_time" TEXT NULL, "notifications_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("notifications_enabled" IN (0, 1)), "notification_message" TEXT NULL, "assigned_member_id" TEXT NULL, "only_notify_when_fronting" INTEGER NOT NULL DEFAULT 0 CHECK ("only_notify_when_fronting" IN (0, 1)), "is_private" INTEGER NOT NULL DEFAULT 0 CHECK ("is_private" IN (0, 1)), "current_streak" INTEGER NOT NULL DEFAULT 0, "best_streak" INTEGER NOT NULL DEFAULT 0, "total_completions" INTEGER NOT NULL DEFAULT 0, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "media_attachments" ("id" TEXT NOT NULL, "message_id" TEXT NOT NULL DEFAULT '', "member_id" TEXT NOT NULL DEFAULT '', "tag" TEXT NOT NULL DEFAULT '', "media_id" TEXT NOT NULL DEFAULT '', "media_type" TEXT NOT NULL DEFAULT '', "encryption_key_b64" TEXT NOT NULL DEFAULT '', "content_hash" TEXT NOT NULL DEFAULT '', "plaintext_hash" TEXT NOT NULL DEFAULT '', "mime_type" TEXT NOT NULL DEFAULT '', "size_bytes" INTEGER NOT NULL DEFAULT 0, "width" INTEGER NOT NULL DEFAULT 0, "height" INTEGER NOT NULL DEFAULT 0, "duration_ms" INTEGER NOT NULL DEFAULT 0, "blurhash" TEXT NOT NULL DEFAULT '', "waveform_b64" TEXT NOT NULL DEFAULT '', "thumbnail_media_id" TEXT NOT NULL DEFAULT '', "thumbnail_content_hash" TEXT NOT NULL DEFAULT '', "thumbnail_plaintext_hash" TEXT NOT NULL DEFAULT '', "source_url" TEXT NOT NULL DEFAULT '', "preview_url" TEXT NOT NULL DEFAULT '', "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "member_board_posts" ("id" TEXT NOT NULL, "target_member_id" TEXT NULL, "author_id" TEXT NULL, "audience" TEXT NOT NULL, "title" TEXT NULL, "body" TEXT NOT NULL, "created_at" INTEGER NOT NULL, "written_at" INTEGER NOT NULL, "edited_at" INTEGER NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "member_group_entries" ("id" TEXT NOT NULL, "group_id" TEXT NOT NULL, "member_id" TEXT NOT NULL, "pk_group_uuid" TEXT NULL, "pk_member_uuid" TEXT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "pending_pk_op" TEXT NOT NULL DEFAULT 'none', "created_at" INTEGER NULL, "sync_generation" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));

CREATE TABLE "member_groups" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "description" TEXT NULL, "color_hex" TEXT NULL, "emoji" TEXT NULL, "avatar_image_data" BLOB NULL, "display_order" INTEGER NOT NULL DEFAULT 0, "parent_group_id" TEXT NULL, "group_type" INTEGER NOT NULL DEFAULT 0, "filter_rules" TEXT NULL, "created_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "pluralkit_id" TEXT NULL, "pluralkit_uuid" TEXT NULL, "last_seen_from_pk_at" INTEGER NULL, "sync_suppressed" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_suppressed" IN (0, 1)), "suspected_pk_group_uuid" TEXT NULL, "sort_state" TEXT NOT NULL DEFAULT '{"mode":0,"order":[]}', "sync_generation" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));

CREATE TABLE "member_profile_preference_values" ("id" TEXT NOT NULL, "member_id" TEXT NOT NULL, "key" TEXT NOT NULL, "value_type" TEXT NOT NULL, "value_json" TEXT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "members" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "pronouns" TEXT NULL, "emoji" TEXT NOT NULL DEFAULT '❔', "age" TEXT NULL, "bio" TEXT NULL, "avatar_image_data" BLOB NULL, "pk_avatar_cached_url" TEXT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)), "created_at" INTEGER NOT NULL, "display_order" INTEGER NOT NULL DEFAULT 0, "is_admin" INTEGER NOT NULL DEFAULT 0 CHECK ("is_admin" IN (0, 1)), "custom_color_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("custom_color_enabled" IN (0, 1)), "custom_color_hex" TEXT NULL, "parent_system_id" TEXT NULL, "pluralkit_uuid" TEXT NULL, "pluralkit_id" TEXT NULL, "pluralkit_display_name" TEXT NULL, "display_name" TEXT NULL, "birthday" TEXT NULL, "proxy_tags_json" TEXT NULL, "pk_banner_url" TEXT NULL, "profile_header_source" INTEGER NOT NULL DEFAULT 1, "profile_header_layout" INTEGER NOT NULL DEFAULT 0, "profile_header_visible" INTEGER NOT NULL DEFAULT 1 CHECK ("profile_header_visible" IN (0, 1)), "name_style_font" INTEGER NOT NULL DEFAULT 0, "name_style_bold" INTEGER NOT NULL DEFAULT 1 CHECK ("name_style_bold" IN (0, 1)), "name_style_italic" INTEGER NOT NULL DEFAULT 0 CHECK ("name_style_italic" IN (0, 1)), "name_style_color_mode" INTEGER NOT NULL DEFAULT 0, "name_style_color_hex" TEXT NULL, "profile_header_image_data" BLOB NULL, "pk_banner_image_data" BLOB NULL, "pk_banner_cached_url" TEXT NULL, "pluralkit_sync_ignored" INTEGER NOT NULL DEFAULT 0 CHECK ("pluralkit_sync_ignored" IN (0, 1)), "markdown_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("markdown_enabled" IN (0, 1)), "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "delete_intent_epoch" INTEGER NULL, "delete_push_started_at" INTEGER NULL, "is_always_fronting" INTEGER NOT NULL DEFAULT 0 CHECK ("is_always_fronting" IN (0, 1)), "board_last_read_at" INTEGER NULL, PRIMARY KEY ("id"));

CREATE TABLE "missing_media" ("media_id" TEXT NOT NULL, "priority" INTEGER NOT NULL DEFAULT 1, "first_missing_at" INTEGER NOT NULL, "last_requested_at" INTEGER NULL, "attempts" INTEGER NOT NULL DEFAULT 0, "next_eligible_at" INTEGER NOT NULL DEFAULT 0, "state" TEXT NOT NULL DEFAULT 'pending', PRIMARY KEY ("media_id"));

CREATE TABLE "notes" ("id" TEXT NOT NULL, "title" TEXT NOT NULL, "body" TEXT NOT NULL, "color_hex" TEXT NULL, "member_id" TEXT NULL, "date" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "modified_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "pk_group_entry_deferred_sync_ops" ("id" TEXT NOT NULL, "entity_type" TEXT NOT NULL, "entity_id" TEXT NOT NULL, "fields_json" TEXT NOT NULL, "reason" TEXT NOT NULL, "created_at" INTEGER NOT NULL, "last_retry_at" INTEGER NULL, "retry_count" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));

CREATE TABLE "pk_group_sync_aliases" ("legacy_entity_id" TEXT NOT NULL, "pk_group_uuid" TEXT NOT NULL, "canonical_entity_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL, PRIMARY KEY ("legacy_entity_id"));

CREATE TABLE "pk_identity_sync_aliases" ("entity_table" TEXT NOT NULL, "legacy_entity_id" TEXT NOT NULL, "pk_uuid" TEXT NULL, "pk_id" TEXT NULL, "member_id" TEXT NULL, "target_row_id" TEXT NOT NULL, "created_at" INTEGER NOT NULL, PRIMARY KEY ("entity_table", "legacy_entity_id"));

CREATE TABLE "pk_mapping_state" ("id" TEXT NOT NULL, "decision_type" TEXT NOT NULL, "pk_member_id" TEXT NULL, "pk_member_uuid" TEXT NULL, "local_member_id" TEXT NULL, "status" TEXT NOT NULL DEFAULT 'pending', "error_message" TEXT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"));

CREATE TABLE "plural_kit_sync_state" ("id" TEXT NOT NULL, "system_id" TEXT NULL, "last_sync_date" INTEGER NULL, "last_manual_sync_date" INTEGER NULL, "is_connected" INTEGER NOT NULL DEFAULT 0 CHECK ("is_connected" IN (0, 1)), "field_sync_config" TEXT NULL, "mapping_acknowledged" INTEGER NOT NULL DEFAULT 0 CHECK ("mapping_acknowledged" IN (0, 1)), "linked_at" INTEGER NULL, "link_epoch" INTEGER NOT NULL DEFAULT 0, "switch_cursor_timestamp" INTEGER NULL, "switch_cursor_id" TEXT NULL, "direction_confirmed" INTEGER NOT NULL DEFAULT 0 CHECK ("direction_confirmed" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "poll_options" ("id" TEXT NOT NULL, "poll_id" TEXT NOT NULL, "option_text" TEXT NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "is_other_option" INTEGER NOT NULL DEFAULT 0 CHECK ("is_other_option" IN (0, 1)), "color_hex" TEXT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "poll_votes" ("id" TEXT NOT NULL, "poll_option_id" TEXT NOT NULL, "member_id" TEXT NOT NULL, "voted_at" INTEGER NOT NULL, "response_text" TEXT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "polls" ("id" TEXT NOT NULL, "question" TEXT NOT NULL, "is_anonymous" INTEGER NOT NULL DEFAULT 0 CHECK ("is_anonymous" IN (0, 1)), "allows_multiple_votes" INTEGER NOT NULL DEFAULT 0 CHECK ("allows_multiple_votes" IN (0, 1)), "is_closed" INTEGER NOT NULL DEFAULT 0 CHECK ("is_closed" IN (0, 1)), "description" TEXT NULL, "expires_at" INTEGER NULL, "created_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "reminders" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "message" TEXT NOT NULL, "trigger" INTEGER NOT NULL DEFAULT 0, "frequency" TEXT NULL, "interval_days" INTEGER NULL, "weekly_days" TEXT NULL, "time_of_day" TEXT NULL, "delay_hours" INTEGER NULL, "target_member_id" TEXT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)), "created_at" INTEGER NOT NULL, "modified_at" INTEGER NOT NULL, "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "sharing_requests" ("init_id" TEXT NOT NULL, "sender_sharing_id" TEXT NOT NULL, "display_name" TEXT NOT NULL, "offered_scopes" TEXT NOT NULL DEFAULT '[]', "sender_identity" BLOB NULL, "pairwise_secret" BLOB NULL, "fingerprint" TEXT NULL, "trust_decision" TEXT NOT NULL, "error_message" TEXT NULL, "is_resolved" INTEGER NOT NULL DEFAULT 0 CHECK ("is_resolved" IN (0, 1)), "received_at" INTEGER NOT NULL, "resolved_at" INTEGER NULL, PRIMARY KEY ("init_id"));

CREATE TABLE "sleep_sessions" ("id" TEXT NOT NULL, "start_time" INTEGER NOT NULL, "end_time" INTEGER NULL, "quality" INTEGER NOT NULL DEFAULT 0, "notes" TEXT NULL, "is_health_kit_import" INTEGER NOT NULL DEFAULT 0 CHECK ("is_health_kit_import" IN (0, 1)), "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "sp_id_map" ("sp_id" TEXT NOT NULL, "entity_type" TEXT NOT NULL, "prism_id" TEXT NOT NULL, PRIMARY KEY ("sp_id", "entity_type"));

CREATE TABLE "sp_sync_state" ("id" TEXT NOT NULL, "last_import_at" INTEGER NULL, "sp_system_id" TEXT NULL, PRIMARY KEY ("id"));

CREATE TABLE "sync_migration_repairs" ("table_name" TEXT NOT NULL, "entity_id" TEXT NOT NULL, "field_names_json" TEXT NOT NULL, "reason" TEXT NOT NULL, "enqueued_at" INTEGER NOT NULL, PRIMARY KEY ("table_name", "entity_id", "reason"));

CREATE TABLE "sync_op_outbox" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "table_name" TEXT NOT NULL, "entity_id" TEXT NOT NULL, "op_type" TEXT NOT NULL, "fields_json" TEXT NOT NULL, "created_at" INTEGER NOT NULL, "attempts" INTEGER NOT NULL DEFAULT 0, "last_error" TEXT NULL, "quarantined" INTEGER NOT NULL DEFAULT 0 CHECK ("quarantined" IN (0, 1)));

CREATE TABLE "sync_quarantine" ("id" TEXT NOT NULL, "entity_type" TEXT NOT NULL, "entity_id" TEXT NOT NULL, "field_name" TEXT NULL, "expected_type" TEXT NOT NULL, "received_type" TEXT NOT NULL, "received_value" TEXT NULL, "source_device" TEXT NULL, "retry_count" INTEGER NOT NULL DEFAULT 0, "last_retry_at" INTEGER NULL, "created_at" INTEGER NOT NULL, "error_message" TEXT NULL, PRIMARY KEY ("id"));

CREATE TABLE "system_settings" ("id" TEXT NOT NULL DEFAULT 'singleton', "system_name" TEXT NULL, "show_quick_front" INTEGER NOT NULL DEFAULT 1 CHECK ("show_quick_front" IN (0, 1)), "accent_color_hex" TEXT NOT NULL DEFAULT '#9070A0', "per_member_accent_colors" INTEGER NOT NULL DEFAULT 0 CHECK ("per_member_accent_colors" IN (0, 1)), "terminology" INTEGER NOT NULL DEFAULT 0, "custom_terminology" TEXT NULL, "custom_plural_terminology" TEXT NULL, "locale_override" TEXT NULL, "terminology_use_english" INTEGER NOT NULL DEFAULT 0 CHECK ("terminology_use_english" IN (0, 1)), "sharing_id" TEXT NULL, "fronting_reminders_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("fronting_reminders_enabled" IN (0, 1)), "fronting_reminder_interval_minutes" INTEGER NOT NULL DEFAULT 60, "theme_mode" INTEGER NOT NULL DEFAULT 0, "theme_brightness" INTEGER NOT NULL DEFAULT 0, "theme_style" INTEGER NOT NULL DEFAULT 0, "theme_corner_style" INTEGER NOT NULL DEFAULT 0, "palette_source" INTEGER NOT NULL DEFAULT 1, "palette_seed_color_hex" TEXT NOT NULL DEFAULT '#9070A0', "palette_mood" INTEGER NOT NULL DEFAULT 0, "palette_contrast" INTEGER NOT NULL DEFAULT 1, "chat_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("chat_enabled" IN (0, 1)), "polls_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("polls_enabled" IN (0, 1)), "habits_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("habits_enabled" IN (0, 1)), "sleep_tracking_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("sleep_tracking_enabled" IN (0, 1)), "gif_search_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("gif_search_enabled" IN (0, 1)), "voice_notes_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("voice_notes_enabled" IN (0, 1)), "sleep_suggestion_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("sleep_suggestion_enabled" IN (0, 1)), "sleep_suggestion_hour" INTEGER NOT NULL DEFAULT 22, "sleep_suggestion_minute" INTEGER NOT NULL DEFAULT 0, "wake_suggestion_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("wake_suggestion_enabled" IN (0, 1)), "wake_suggestion_after_hours" REAL NOT NULL DEFAULT 8.0, "quick_switch_threshold_seconds" INTEGER NOT NULL DEFAULT 30, "identity_generation" INTEGER NOT NULL DEFAULT 0, "chat_logs_front" INTEGER NOT NULL DEFAULT 0 CHECK ("chat_logs_front" IN (0, 1)), "has_completed_onboarding" INTEGER NOT NULL DEFAULT 0 CHECK ("has_completed_onboarding" IN (0, 1)), "sync_theme_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("sync_theme_enabled" IN (0, 1)), "timing_mode" INTEGER NOT NULL DEFAULT 0, "habits_badge_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("habits_badge_enabled" IN (0, 1)), "notes_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("notes_enabled" IN (0, 1)), "pk_group_sync_v2_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("pk_group_sync_v2_enabled" IN (0, 1)), "system_description" TEXT NULL, "system_color" TEXT NULL, "system_tag" TEXT NULL, "system_avatar_data" BLOB NULL, "reminders_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("reminders_enabled" IN (0, 1)), "gif_consent_state" INTEGER NOT NULL DEFAULT 0, "font_scale" REAL NOT NULL DEFAULT 1.0, "font_family" INTEGER NOT NULL DEFAULT 0, "pin_lock_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("pin_lock_enabled" IN (0, 1)), "biometric_lock_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("biometric_lock_enabled" IN (0, 1)), "auto_lock_delay_seconds" INTEGER NOT NULL DEFAULT 0, "display_font_in_app_bar" INTEGER NOT NULL DEFAULT 1 CHECK ("display_font_in_app_bar" IN (0, 1)), "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "previous_accent_color_hex" TEXT NOT NULL DEFAULT '', "nav_bar_items" TEXT NOT NULL DEFAULT '', "nav_bar_overflow_items" TEXT NOT NULL DEFAULT '', "sync_navigation_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("sync_navigation_enabled" IN (0, 1)), "nav_bar_label_display_mode" INTEGER NOT NULL DEFAULT 0, "nav_bar_reveal_labels_when_expanded" INTEGER NOT NULL DEFAULT 1 CHECK ("nav_bar_reveal_labels_when_expanded" IN (0, 1)), "chat_badge_preferences" TEXT NOT NULL DEFAULT '{}', "default_sleep_quality" TEXT NULL, "pending_fronting_migration_mode" TEXT NOT NULL DEFAULT 'complete', "fronting_list_view_mode" INTEGER NOT NULL DEFAULT 0, "add_front_default_behavior" INTEGER NOT NULL DEFAULT 0, "quick_front_default_behavior" INTEGER NOT NULL DEFAULT 0, "auto_promote_long_fronting_sessions" INTEGER NOT NULL DEFAULT 1 CHECK ("auto_promote_long_fronting_sessions" IN (0, 1)), "pending_fronting_migration_cleanup_substate" TEXT NOT NULL DEFAULT '', "boards_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("boards_enabled" IN (0, 1)), "sp_boards_backfilled_at" INTEGER NULL, "members_list_view_mode" INTEGER NOT NULL DEFAULT 1, "members_grouped_default_state" INTEGER NOT NULL DEFAULT 0, "members_folder_member_visibility" INTEGER NOT NULL DEFAULT 0, "members_show_pronouns" INTEGER NOT NULL DEFAULT 1 CHECK ("members_show_pronouns" IN (0, 1)), "members_show_front_buttons" INTEGER NOT NULL DEFAULT 0 CHECK ("members_show_front_buttons" IN (0, 1)), "members_show_groups" INTEGER NOT NULL DEFAULT 1 CHECK ("members_show_groups" IN (0, 1)), "members_front_button_behavior" INTEGER NOT NULL DEFAULT 0, "bio_markdown_enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("bio_markdown_enabled" IN (0, 1)), PRIMARY KEY ("id"));

CREATE TABLE "upload_queue_entries" ("media_id" TEXT NOT NULL, "content_hash" TEXT NOT NULL, "ciphertext" BLOB NOT NULL, "ttl_secs" INTEGER NULL, "attempts" INTEGER NOT NULL DEFAULT 0, "next_attempt_at" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "state" TEXT NOT NULL DEFAULT 'pending', "last_error" TEXT NULL, PRIMARY KEY ("media_id"));

CREATE INDEX idx_app_preference_values_deleted ON app_preference_values (is_deleted);

CREATE INDEX idx_comments_session ON front_session_comments (session_id, is_deleted, timestamp ASC);

CREATE INDEX idx_conv_categories_deleted_order ON conversation_categories (is_deleted, display_order ASC);

CREATE INDEX idx_conversations_category ON conversations (category_id) WHERE category_id IS NOT NULL;

CREATE INDEX idx_conversations_deleted_activity ON conversations (is_deleted, last_activity_at DESC);

CREATE UNIQUE INDEX idx_custom_field_values_field_member ON custom_field_values (custom_field_id, member_id) WHERE is_deleted = 0;

CREATE INDEX idx_custom_field_values_member ON custom_field_values (member_id, is_deleted);

CREATE INDEX idx_custom_fields_deleted_order ON custom_fields (is_deleted, display_order ASC);

CREATE INDEX idx_custom_fields_parent ON custom_fields(parent_field_id) WHERE parent_field_id IS NOT NULL;

CREATE INDEX idx_friends_deleted ON friends (is_deleted);

CREATE INDEX idx_friends_peer_sharing ON friends (peer_sharing_id, is_deleted);

CREATE UNIQUE INDEX idx_fronting_sessions_pluralkit_uuid_member_id ON fronting_sessions(pluralkit_uuid, member_id) WHERE pluralkit_uuid IS NOT NULL AND member_id IS NOT NULL;

CREATE UNIQUE INDEX idx_fronting_sessions_pluralkit_uuid_orphan ON fronting_sessions(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL AND member_id IS NULL;

CREATE INDEX idx_habit_completions_habit_deleted_at ON habit_completions (habit_id, is_deleted, completed_at DESC);

CREATE INDEX idx_habit_completions_member ON habit_completions (completed_by_member_id, is_deleted, completed_at DESC);

CREATE INDEX idx_mbp_audience ON member_board_posts (audience, written_at DESC, is_deleted);

CREATE INDEX idx_mbp_author ON member_board_posts (author_id, written_at DESC, is_deleted);

CREATE INDEX idx_mbp_target_audience ON member_board_posts (target_member_id, audience, written_at DESC, is_deleted);

CREATE INDEX idx_media_attachments_message_id ON media_attachments (message_id);

CREATE INDEX idx_member_group_entries_group_deleted ON member_group_entries (group_id, is_deleted);

CREATE INDEX idx_member_group_entries_member_deleted ON member_group_entries (member_id, is_deleted);

CREATE INDEX idx_member_group_entries_pk_canonicalize ON member_group_entries (pk_group_uuid, pk_member_uuid) WHERE is_deleted = 0 AND pk_group_uuid IS NOT NULL AND pk_member_uuid IS NOT NULL;

CREATE INDEX idx_member_group_entries_pk_group_uuid ON member_group_entries (pk_group_uuid) WHERE pk_group_uuid IS NOT NULL;

CREATE INDEX idx_member_group_entries_pk_member_uuid ON member_group_entries (pk_member_uuid) WHERE pk_member_uuid IS NOT NULL;

CREATE UNIQUE INDEX idx_member_group_entries_unique ON member_group_entries (group_id, member_id) WHERE is_deleted = 0;

CREATE INDEX idx_member_groups_parent_id ON member_groups (parent_group_id) WHERE parent_group_id IS NOT NULL;

CREATE INDEX idx_member_groups_pluralkit_id ON member_groups(pluralkit_id) WHERE pluralkit_id IS NOT NULL;

CREATE UNIQUE INDEX idx_member_groups_pluralkit_uuid ON member_groups(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL AND is_deleted = 0;

CREATE INDEX idx_member_groups_suspected_pk_group_uuid ON member_groups (suspected_pk_group_uuid) WHERE suspected_pk_group_uuid IS NOT NULL;

CREATE INDEX idx_member_groups_sync_suppressed ON member_groups (sync_suppressed, is_deleted);

CREATE INDEX idx_member_profile_pref_member_deleted_key ON member_profile_preference_values (member_id, is_deleted, key);

CREATE UNIQUE INDEX idx_member_profile_pref_member_key ON member_profile_preference_values (member_id, key);

CREATE INDEX idx_members_active ON members (is_active, is_deleted);

CREATE UNIQUE INDEX idx_members_pluralkit_id ON members(pluralkit_id) WHERE pluralkit_id IS NOT NULL;

CREATE UNIQUE INDEX idx_members_pluralkit_uuid ON members(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL;

CREATE INDEX idx_messages_conv_deleted_ts ON chat_messages (conversation_id, is_deleted, timestamp DESC);

CREATE INDEX idx_notes_all ON notes (is_deleted, date DESC);

CREATE INDEX idx_notes_member ON notes (member_id, is_deleted, date DESC);

CREATE INDEX idx_pk_group_entry_deferred_ops_entity ON pk_group_entry_deferred_sync_ops (entity_type, entity_id);

CREATE INDEX idx_pk_group_sync_aliases_pk_group_uuid ON pk_group_sync_aliases (pk_group_uuid);

CREATE INDEX idx_pk_identity_sync_aliases_identity ON pk_identity_sync_aliases (entity_table, pk_uuid, pk_id, member_id);

CREATE INDEX idx_poll_options_poll_deleted_order ON poll_options (poll_id, is_deleted, sort_order ASC);

CREATE INDEX idx_poll_votes_option_deleted ON poll_votes (poll_option_id, is_deleted, voted_at DESC);

CREATE INDEX idx_polls_closed_deleted_created ON polls (is_closed, is_deleted, created_at DESC);

CREATE INDEX idx_quarantine_entity ON sync_quarantine (entity_type, entity_id);

CREATE INDEX idx_reminders_active_deleted ON reminders (is_active, is_deleted);

CREATE INDEX idx_sessions_active_fronting ON fronting_sessions (session_type, is_deleted, end_time, start_time DESC, member_id) WHERE session_type = 0 AND is_deleted = 0 AND end_time IS NULL;

CREATE INDEX idx_sessions_deleted_start ON fronting_sessions (is_deleted, start_time DESC);

CREATE INDEX idx_sessions_end ON fronting_sessions (end_time);

CREATE INDEX idx_sessions_member_deleted_start ON fronting_sessions (member_id, session_type, is_deleted, start_time DESC);

CREATE INDEX idx_sessions_start ON fronting_sessions (start_time);

CREATE INDEX idx_sessions_type ON fronting_sessions (session_type, is_deleted, start_time DESC);

CREATE INDEX idx_sharing_requests_resolved_received ON sharing_requests (is_resolved, received_at DESC);

CREATE INDEX idx_sp_id_map_entity_type ON sp_id_map (entity_type);

CREATE TRIGGER chat_messages_fts_delete
      AFTER DELETE ON chat_messages
      BEGIN
        DELETE FROM chat_messages_fts WHERE message_id = OLD.id;
      END;

CREATE TRIGGER chat_messages_fts_insert
      AFTER INSERT ON chat_messages
      WHEN NEW.is_deleted = 0 AND NEW.is_system_message = 0 AND NEW.content != ''
      BEGIN
        INSERT INTO chat_messages_fts(content, message_id, conversation_id)
        VALUES (NEW.content, NEW.id, NEW.conversation_id);
      END;

CREATE TRIGGER chat_messages_fts_update
      AFTER UPDATE ON chat_messages
      WHEN OLD.content != NEW.content
        OR OLD.is_deleted != NEW.is_deleted
        OR OLD.is_system_message != NEW.is_system_message
        OR OLD.conversation_id != NEW.conversation_id
      BEGIN
        DELETE FROM chat_messages_fts WHERE message_id = OLD.id;
        INSERT INTO chat_messages_fts(content, message_id, conversation_id)
        SELECT NEW.content, NEW.id, NEW.conversation_id
        WHERE NEW.is_deleted = 0 AND NEW.is_system_message = 0 AND NEW.content != '';
      END;

PRAGMA user_version = 38;
