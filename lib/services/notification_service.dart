import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// NotificationService handles scheduling, cancelling, and initializing local notifications
/// using flutter_local_notifications and timezone packages.
class NotificationService {
  static final NotificationService instance = NotificationService._init();
  NotificationService._init();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Initializes timezone data, Android/iOS settings, and requests permissions.
  Future<void> initNotification() async {
    if (_isInitialized) return;

    try {
      // Initialize timezone database for zoned schedules
      tz.initializeTimeZones();

      // Android initialization settings using standard app launcher icon
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS / Darwin initialization settings
      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification tapped with payload: ${response.payload}');
        },
      );

      // Request permissions for Android 13+ (API level 33+)
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final notifGranted =
            await androidImplementation.requestNotificationsPermission();
        final alarmGranted =
            await androidImplementation.requestExactAlarmsPermission();
        debugPrint(
            'Notification permission granted: $notifGranted, Exact alarm granted: $alarmGranted');
      }

      _isInitialized = true;
      debugPrint('NotificationService successfully initialized.');
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  /// Returns NotificationDetails configured with high-priority alarm sound & heads-up banner.
  NotificationDetails _getNotificationDetails({String? body}) {
    final androidDetails = AndroidNotificationDetails(
      'task_reminders_channel_v4', // Fresh channel ID for Alarm stream sound & heads-up banner
      'Task Reminders',
      channelDescription: 'Notifications for task reminders and deadlines',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.alarm, // Rings on Alarm volume stream
      styleInformation: BigTextStyleInformation(body ?? ''),
      ticker: 'Task Reminder',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
    );

    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  /// Schedules a local notification at the specified [scheduledDate].
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    try {
      await initNotification();

      // Ensure notification is not set in the past
      if (scheduledDate.isBefore(DateTime.now())) {
        debugPrint(
            'Scheduled time ($scheduledDate) is in the past. Skipping notification.');
        return;
      }

      final platformDetails = _getNotificationDetails(body: body);

      // Convert local DateTime to UTC TZDateTime so Android AlarmManager triggers at the exact local time
      final tz.TZDateTime tzScheduledDate = tz.TZDateTime.from(
        scheduledDate.toUtc(),
        tz.getLocation('UTC'),
      );

      try {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzScheduledDate,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        debugPrint(
            'Scheduled exact notification #$id for $tzScheduledDate (local target: $scheduledDate)');
      } catch (e) {
        debugPrint('Exact alarm failed, falling back to inexact schedule: $e');
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzScheduledDate,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexact,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('Failed to schedule notification #$id: $e');
      rethrow;
    }
  }

  /// Triggers an instant notification immediately for testing sound & banner popup
  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await initNotification();
      final platformDetails = _getNotificationDetails(body: body);
      await _notificationsPlugin.show(id, title, body, platformDetails);
      debugPrint('Triggered instant notification #$id');
    } catch (e) {
      debugPrint('Error showing instant notification: $e');
    }
  }

  /// Cancels a scheduled local notification by task ID.
  Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
      debugPrint('Cancelled notification #$id');
    } catch (e) {
      debugPrint('Error cancelling notification #$id: $e');
    }
  }

  /// Cancels all scheduled local notifications.
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('Cancelled all scheduled notifications.');
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }
}
