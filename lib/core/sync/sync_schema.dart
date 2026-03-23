/// JSON schema describing all syncable entities for prism-sync.
///
/// Field types: String, Int, Bool, DateTime, Blob
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
        "is_deleted": "Bool"
      }
    },
    "fronting_sessions": {
      "fields": {
        "start_time": "DateTime",
        "end_time": "DateTime",
        "member_id": "String",
        "co_fronter_ids": "String",
        "notes": "String",
        "confidence": "Int",
        "pluralkit_uuid": "String",
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
        "show_quick_front": "Bool",
        "accent_color_hex": "String",
        "per_member_accent_colors": "Bool",
        "terminology": "Int",
        "custom_terminology": "String",
        "custom_plural_terminology": "String",
        "fronting_reminders_enabled": "Bool",
        "fronting_reminder_interval_minutes": "Int",
        "theme_mode": "Int",
        "theme_brightness": "Int",
        "theme_style": "Int",
        "chat_enabled": "Bool",
        "polls_enabled": "Bool",
        "habits_enabled": "Bool",
        "sleep_tracking_enabled": "Bool",
        "quick_switch_threshold_seconds": "Int",
        "has_completed_onboarding": "Bool",
        "chat_logs_front": "Bool",
        "sync_theme_enabled": "Bool",
        "timing_mode": "Int",
        "notes_enabled": "Bool",
        "system_description": "String",
        "system_avatar_data": "Blob",
        "reminders_enabled": "Bool",
        "sync_navigation_enabled": "Bool",
        "nav_bar_items": "String",
        "nav_bar_overflow_items": "String",
        "chat_badge_preferences": "String",
        "is_deleted": "Bool"
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
    "sleep_sessions": {
      "fields": {
        "start_time": "DateTime",
        "end_time": "DateTime",
        "quality": "Int",
        "notes": "String",
        "is_health_kit_import": "Bool",
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
        "created_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "member_group_entries": {
      "fields": {
        "group_id": "String",
        "member_id": "String",
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
        "session_id": "String",
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
        "is_active": "Bool",
        "created_at": "DateTime",
        "modified_at": "DateTime",
        "is_deleted": "Bool"
      }
    },
    "friends": {
      "fields": {
        "display_name": "String",
        "public_key_hex": "String",
        "shared_secret_hex": "String",
        "granted_scopes": "String",
        "is_verified": "Bool",
        "created_at": "DateTime",
        "last_sync_at": "DateTime",
        "is_deleted": "Bool"
      }
    }
  }
}
''';
