/// JSON schema describing all syncable entities for prism-sync.
///
/// Field types: String, Int, Real, Bool, DateTime, Blob
///
/// Transitional / deprecated fields:
///   - `fronting_sessions.pk_member_ids_json` — legacy per-switch PK member
///     id list, kept on disk through v7 so legacy peers can still round-trip
///     the value until the mandatory per-member-fronting upgrade completes.
///     v7+ does not write to it; the apply path uses `Value.absent()` when
///     missing so we don't clobber whatever a legacy peer last sent. Removal
///     target: 0.8.0 alongside the v8 cleanup `TableMigration` and
///     `reset_sync_state` cutover.
const String prismSyncSchema = '''
{
  "entities": {
    "members": {
      "fields": {
        "name": "String",
        "pronouns": "String",
        "emoji": "String",
        "age": "Int",
        "bio": "String",
        "avatar_image_data": "Blob",
        "is_active": "Bool",
        "created_at": "DateTime",
        "display_order": "Int",
        "is_admin": "Bool",
        "custom_color_enabled": "Bool",
        "custom_color_hex": "String",
        "parent_system_id": "String",
        "pluralkit_uuid": "String",
        "pluralkit_id": "String",
        "markdown_enabled": "Bool",
        "display_name": "String",
        "birthday": "String",
        "is_always_fronting": "Bool",
        "proxy_tags_json": "String",
        "pk_banner_url": "String",
        "profile_header_source": "Int",
        "profile_header_layout": "Int",
        "profile_header_visible": "Bool",
        "name_style_font": "Int",
        "name_style_bold": "Bool",
        "name_style_italic": "Bool",
        "name_style_color_mode": "Int",
        "name_style_color_hex": "String",
        "profile_header_image_data": "Blob",
        "pk_banner_image_data": "Blob",
        "pk_banner_cached_url": "String",
        "pluralkit_sync_ignored": "Bool",
        "delete_push_started_at": "Int",
        "is_deleted": "Bool",
        "board_last_read_at": "DateTime"
      }
    },
    "fronting_sessions": {
      "fields": {
        "start_time": "DateTime",
        "end_time": "DateTime",
        "member_id": "String",
        "notes": "String",
        "confidence": "Int",
        "session_type": "Int",
        "quality": "Int",
        "is_health_kit_import": "Bool",
        "pluralkit_uuid": "String",
        "pk_import_source": "String",
        "pk_file_switch_id": "String",
        "pk_member_ids_json": "String",
        "delete_push_started_at": "Int",
        "is_deleted": "Bool"
      }
    },
    "conversations": {
      "fields": {
        "created_at": "DateTime",
        "last_activity_at": "DateTime",
        "title": "String",
        "emoji": "String",
        "is_direct_message": "Bool",
        "creator_id": "String",
        "participant_ids": "String",
        "archived_by_member_ids": "String",
        "muted_by_member_ids": "String",
        "last_read_timestamps": "String",
        "description": "String",
        "category_id": "String",
        "display_order": "Int",
        "is_deleted": "Bool"
      }
    },
    "chat_messages": {
      "fields": {
        "content": "String",
        "timestamp": "DateTime",
        "is_system_message": "Bool",
        "edited_at": "DateTime",
        "author_id": "String",
        "conversation_id": "String",
        "reactions": "String",
        "reply_to_id": "String",
        "reply_to_author_id": "String",
        "reply_to_content": "String",
        "is_deleted": "Bool"
      }
    },
    "system_settings": {
      "fields": {
        "system_name": "String",
        "sharing_id": "String",
        "show_quick_front": "Bool",
        "accent_color_hex": "String",
        "per_member_accent_colors": "Bool",
        "terminology": "Int",
        "custom_terminology": "String",
        "custom_plural_terminology": "String",
        "terminology_use_english": "Bool",
        "fronting_reminders_enabled": "Bool",
        "fronting_reminder_interval_minutes": "Int",
        "theme_mode": "Int",
        "theme_brightness": "Int",
        "theme_style": "Int",
        "theme_corner_style": "Int",
        "chat_enabled": "Bool",
        "gif_search_enabled": "Bool",
        "voice_notes_enabled": "Bool",
        "locale_override": "String",
        "polls_enabled": "Bool",
        "habits_enabled": "Bool",
        "sleep_tracking_enabled": "Bool",
        "quick_switch_threshold_seconds": "Int",
        "identity_generation": "Int",
        "sleep_suggestion_enabled": "Bool",
        "sleep_suggestion_hour": "Int",
        "sleep_suggestion_minute": "Int",
        "wake_suggestion_enabled": "Bool",
        "wake_suggestion_after_hours": "Real",
        "chat_logs_front": "Bool",
        "sync_theme_enabled": "Bool",
        "timing_mode": "Int",
        "notes_enabled": "Bool",
        "pk_group_sync_v2_enabled": "Bool",
        "system_color": "String",
        "system_description": "String",
        "system_tag": "String",
        "system_avatar_data": "Blob",
        "reminders_enabled": "Bool",
        "sync_navigation_enabled": "Bool",
        "habits_badge_enabled": "Bool",
        "nav_bar_items": "String",
        "nav_bar_overflow_items": "String",
        "chat_badge_preferences": "String",
        "fronting_list_view_mode": "Int",
        "add_front_default_behavior": "Int",
        "quick_front_default_behavior": "Int",
        "is_deleted": "Bool",
        "boards_enabled": "Bool",
        "sp_boards_backfilled_at": "DateTime"
      }
    },
    "polls": {
      "fields": {
        "question": "String",
        "description": "String",
        "is_anonymous": "Bool",
        "allows_multiple_votes": "Bool",
        "is_closed": "Bool",
        "expires_at": "DateTime",
        "created_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "poll_options": {
      "fields": {
        "poll_id": "String",
        "option_text": "String",
        "sort_order": "Int",
        "is_other_option": "Bool",
        "color_hex": "String",
        "is_deleted": "Bool"
      }
    },
    "poll_votes": {
      "fields": {
        "poll_option_id": "String",
        "member_id": "String",
        "voted_at": "DateTime",
        "response_text": "String",
        "is_deleted": "Bool"
      }
    },
    "habits": {
      "fields": {
        "name": "String",
        "description": "String",
        "icon": "String",
        "color_hex": "String",
        "is_active": "Bool",
        "created_at": "DateTime",
        "modified_at": "DateTime",
        "frequency": "String",
        "weekly_days": "String",
        "interval_days": "Int",
        "reminder_time": "String",
        "notifications_enabled": "Bool",
        "notification_message": "String",
        "assigned_member_id": "String",
        "only_notify_when_fronting": "Bool",
        "is_private": "Bool",
        "current_streak": "Int",
        "best_streak": "Int",
        "total_completions": "Int",
        "is_deleted": "Bool"
      }
    },
    "habit_completions": {
      "fields": {
        "habit_id": "String",
        "completed_at": "DateTime",
        "completed_by_member_id": "String",
        "notes": "String",
        "was_fronting": "Bool",
        "rating": "Int",
        "created_at": "DateTime",
        "modified_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "member_groups": {
      "fields": {
        "name": "String",
        "description": "String",
        "color_hex": "String",
        "emoji": "String",
        "display_order": "Int",
        "parent_group_id": "String",
        "group_type": "Int",
        "filter_rules": "String",
        "created_at": "DateTime",
        "pluralkit_id": "String",
        "pluralkit_uuid": "String",
        "last_seen_from_pk_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "member_group_entries": {
      "fields": {
        "group_id": "String",
        "member_id": "String",
        "pk_group_uuid": "String",
        "pk_member_uuid": "String",
        "is_deleted": "Bool"
      }
    },
    "custom_fields": {
      "fields": {
        "name": "String",
        "field_type": "Int",
        "date_precision": "Int",
        "display_order": "Int",
        "created_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "custom_field_values": {
      "fields": {
        "custom_field_id": "String",
        "member_id": "String",
        "value": "String",
        "is_deleted": "Bool"
      }
    },
    "notes": {
      "fields": {
        "title": "String",
        "body": "String",
        "color_hex": "String",
        "member_id": "String",
        "date": "DateTime",
        "created_at": "DateTime",
        "modified_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "front_session_comments": {
      "fields": {
        "target_time": "DateTime",
        "author_member_id": "String",
        "body": "String",
        "timestamp": "DateTime",
        "created_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "conversation_categories": {
      "fields": {
        "name": "String",
        "display_order": "Int",
        "created_at": "DateTime",
        "modified_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "reminders": {
      "fields": {
        "name": "String",
        "message": "String",
        "trigger": "Int",
        "interval_days": "Int",
        "time_of_day": "String",
        "delay_hours": "Int",
        "target_member_id": "String",
        "is_active": "Bool",
        "created_at": "DateTime",
        "modified_at": "DateTime",
        "frequency": "String",
        "weekly_days": "String",
        "is_deleted": "Bool"
      }
    },
    "friends": {
      "fields": {
        "display_name": "String",
        "peer_sharing_id": "String",
        "pairwise_secret": "Blob",
        "pinned_identity": "Blob",
        "offered_scopes": "String",
        "public_key_hex": "String",
        "shared_secret_hex": "String",
        "granted_scopes": "String",
        "is_verified": "Bool",
        "init_id": "String",
        "created_at": "DateTime",
        "established_at": "DateTime",
        "last_sync_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "media_attachments": {
      "fields": {
        "message_id": "String",
        "media_id": "String",
        "media_type": "String",
        "encryption_key_b64": "String",
        "content_hash": "String",
        "plaintext_hash": "String",
        "mime_type": "String",
        "size_bytes": "Int",
        "width": "Int",
        "height": "Int",
        "duration_ms": "Int",
        "blurhash": "String",
        "waveform_b64": "String",
        "thumbnail_media_id": "String",
        "source_url": "String",
        "preview_url": "String",
        "is_deleted": "Bool"
      }
    },
    "member_board_posts": {
      "fields": {
        "target_member_id": "String",
        "author_id": "String",
        "audience": "String",
        "title": "String",
        "body": "String",
        "created_at": "DateTime",
        "written_at": "DateTime",
        "edited_at": "DateTime",
        "is_deleted": "Bool"
      }
    }
  }
}
''';
