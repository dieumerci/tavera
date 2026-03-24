import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/meal_log.dart';

// ─── Notification IDs ─────────────────────────────────────────────────────────
const _kBreakfastId = 1;
const _kLunchId     = 2;
const _kDinnerId    = 3;

// ─── Android notification channel ────────────────────────────────────────────
const _kChannelId   = 'meal_reminders';
const _kChannelName = 'Meal Reminders';
const _kChannelDesc = 'Daily reminders to log your breakfast, lunch, and dinner.';

// ─── Notification payload ─────────────────────────────────────────────────────
// Tapping any notification brings the app to the camera screen.
const _kPayloadCamera = 'camera';

// ─── NotificationService ──────────────────────────────────────────────────────

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialised = false;

  // ── Initialise ───────────────────────────────────────────────────────────

  /// Call once in main() after Firebase.initializeApp().
  static Future<void> initialise({
    void Function(String? payload)? onTap,
  }) async {
    if (_initialised) return;

    // Load the IANA timezone database — required for zonedSchedule.
    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      // Defer permission to requestPermission() — don't ask at init time.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (details) {
        if (details.payload == _kPayloadCamera) onTap?.call(details.payload);
      },
    );

    _initialised = true;
  }

  // ── Permission ───────────────────────────────────────────────────────────

  /// Requests notification permission via FCM (wraps APNs on iOS).
  /// Returns true if the user granted (or had previously granted) permission.
  static Future<bool> requestPermission() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final granted = settings.authorizationStatus ==
            AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (granted) {
      // Ensure flutter_local_notifications also has iOS permission.
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    return granted;
  }

  /// Returns true if notification permission is currently granted.
  static Future<bool> isEnabled() async {
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  // ── Scheduling ───────────────────────────────────────────────────────────

  /// Reschedules today's meal-time reminders based on which windows already
  /// have a logged meal. Call this:
  ///   • on app startup (from camera screen initState)
  ///   • when logControllerProvider changes (ref.listen in camera screen)
  ///   • when app resumes from background (didChangeAppLifecycleState)
  ///
  /// Windows: breakfast 5–10am → 8:00am
  ///          lunch    10–16pm → 12:30pm
  ///          dinner   16–21pm → 7:00pm
  static Future<void> scheduleDailyReminders(List<MealLog> todayLogs) async {
    // Guard: do nothing if not permitted (avoids Android 13 crash on schedule).
    if (!await isEnabled()) return;

    bool covered(int startHour, int endHour) => todayLogs.any((l) {
          final h = l.loggedAt.toLocal().hour;
          return h >= startHour && h < endHour;
        });

    final hasBreakfast = covered(5, 10);
    final hasLunch     = covered(10, 16);
    final hasDinner    = covered(16, 21);

    // Cancel existing to avoid stale scheduled notifications.
    await _plugin.cancelAll();

    final now = DateTime.now();

    if (!hasBreakfast) {
      await _maybeSchedule(
        id:    _kBreakfastId,
        title: 'Time for breakfast 🌅',
        body:  'Log what you\'re eating to stay on track.',
        time:  _todayAt(8, 0),
        now:   now,
      );
    }

    if (!hasLunch) {
      await _maybeSchedule(
        id:    _kLunchId,
        title: 'Lunch time 🥗',
        body:  'Don\'t forget to log your meal.',
        time:  _todayAt(12, 30),
        now:   now,
      );
    }

    if (!hasDinner) {
      await _maybeSchedule(
        id:    _kDinnerId,
        title: 'Dinner time 🍽️',
        body:  'Log your evening meal to hit your goal.',
        time:  _todayAt(19, 0),
        now:   now,
      );
    }
  }

  /// Cancels all scheduled notifications (call when user disables reminders).
  static Future<void> cancelAll() => _plugin.cancelAll();

  // ── Helpers ──────────────────────────────────────────────────────────────

  static DateTime _todayAt(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  static Future<void> _maybeSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime time,
    required DateTime now,
  }) async {
    // Don't schedule notifications in the past.
    if (!time.isAfter(now)) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(time, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _kPayloadCamera,
    );
  }
}
