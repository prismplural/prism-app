/// App-wide constants for Prism
abstract final class AppConstants {
  static const String appName = 'Prism';
  static const String packageName = 'prism_plurality';
  static const String databaseName = 'prism.db';

  /// Default emoji for new members
  static const String defaultEmoji = '❔';

  /// Default accent color (purple)
  static const String defaultAccentColorHex = '#AF8EE9';

  /// Quick reactions for chat
  static const List<String> quickReactions = [
    '❤️',
    '👍',
    '😂',
    '😮',
  ];

  /// Max avatar image size in bytes (256KB)
  static const int maxAvatarSize = 256 * 1024;

  /// Default fronting reminder interval in minutes
  static const int defaultReminderIntervalMinutes = 60;

  /// Sync engine SQLite database filename
  static const String syncDatabaseName = 'prism_sync.db';

  /// Default relay URL for sync
  static const String defaultRelayUrl = 'https://prismrelay.neatkit.xyz';

  /// CRDT sync constants
  static const int maxClockDriftSeconds = 300; // 5 minutes
  static const int changesetTtlHours = 72;
  static const int snapshotTtlHours = 168; // 7 days
}
