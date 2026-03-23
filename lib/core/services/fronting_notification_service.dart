import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service that manages fronting-related local notifications.
class FrontingNotificationService {
  FrontingNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _reminderChannelId = 'fronting_reminders';
  static const _reminderChannelName = 'Fronting Reminders';
  static const _reminderChannelDesc =
      'Periodic reminders to check who is fronting';

  static const _changeChannelId = 'fronting_changes';
  static const _changeChannelName = 'Fronting Changes';
  static const _changeChannelDesc =
      'Notifications when the current fronter changes';

  static const _reminderNotificationId = 1000;
  static const _changeNotificationId = 2000;

  bool _initialized = false;

  /// Initialize the notification plugin with platform-specific settings.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  /// Request notification permission from the user.
  ///
  /// Returns `true` if permission was granted.
  Future<bool> requestPermission() async {
    // iOS / macOS
    final darwinPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (darwinPlugin != null) {
      final granted = await darwinPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    final macPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
    if (macPlugin != null) {
      final granted = await macPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    // Android 13+ runtime permission
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    return false;
  }

  /// Check whether notification permission is currently granted.
  Future<bool> isPermissionGranted() async {
    final darwinPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (darwinPlugin != null) {
      // Re-request with no-op to check – iOS returns current state.
      final granted = await darwinPlugin.requestPermissions();
      return granted ?? false;
    }

    final macPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
    if (macPlugin != null) {
      final granted = await macPlugin.requestPermissions();
      return granted ?? false;
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.areNotificationsEnabled();
      return granted ?? false;
    }

    // Fallback: assume granted on unsupported platforms.
    return true;
  }

  /// Schedule a repeating fronting reminder notification.
  Future<void> scheduleFrontingReminder({
    required Duration interval,
    required String currentFronterName,
  }) async {
    await _ensureInitialized();

    // Cancel any existing reminder first.
    await cancelFrontingReminder();

    const androidDetails = AndroidNotificationDetails(
      _reminderChannelId,
      _reminderChannelName,
      channelDescription: _reminderChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const darwinDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.periodicallyShow(
      id: _reminderNotificationId,
      title: 'Fronting Reminder',
      body:
          '$currentFronterName is currently fronting. Is this still accurate?',
      repeatInterval: _repeatIntervalFrom(interval),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Cancel the scheduled fronting reminder.
  Future<void> cancelFrontingReminder() async {
    await _plugin.cancel(id: _reminderNotificationId);
  }

  /// Show an immediate notification when the fronter changes.
  Future<void> showFrontingChange({required String newFronterName}) async {
    await _ensureInitialized();

    const androidDetails = AndroidNotificationDetails(
      _changeChannelId,
      _changeChannelName,
      channelDescription: _changeChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      id: _changeNotificationId,
      title: 'Fronting Change',
      body: '$newFronterName is now fronting.',
      notificationDetails: details,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  RepeatInterval _repeatIntervalFrom(Duration duration) {
    if (duration.inMinutes <= 60) return RepeatInterval.hourly;
    if (duration.inHours <= 24) return RepeatInterval.daily;
    return RepeatInterval.weekly;
  }
}
