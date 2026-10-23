import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/app_constants.dart';
import '../data/repositories/document_repository.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      tz.initializeTimeZones();
      final String timeZoneName = DateTime.now().timeZoneName;
      try {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('Notification clicked: ${response.payload}');
        },
      );

      // Request notification permission on Android 13+
      if (Platform.isAndroid) {
        final androidImpl = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidImpl?.requestNotificationsPermission();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init notice: $e');
      _initialized = true;
    }
  }

  /// Calculates a stable unique integer notification ID for (documentId, offsetDays).
  static int generateNotificationId(int documentId, int offsetDays) {
    return (documentId * 100 + offsetDays).abs();
  }

  /// Schedules standard expiry reminders (30d, 7d, 1d, 0d) for a document.
  Future<void> scheduleExpiryReminders({
    required int documentId,
    required String documentName,
    required DateTime expiryDate,
    required DocumentRepository repository,
  }) async {
    if (!_initialized) await initialize();

    // First cancel existing reminders for this document to avoid duplicates
    await cancelRemindersForDocument(
      documentId: documentId,
      repository: repository,
    );

    final now = DateTime.now();

    for (final offset in AppConstants.reminderOffsetsDays) {
      final scheduledDate = DateTime(
        expiryDate.year,
        expiryDate.month,
        expiryDate.day - offset,
        9, // 9:00 AM
        0,
      );

      // If scheduled time is in the past, skip
      if (scheduledDate.isBefore(now)) continue;

      final notificationId = generateNotificationId(documentId, offset);
      final reminderType = offset == 0
          ? 'Day of Expiry'
          : '$offset Days Before';

      String title;
      String body;
      if (offset == 0) {
        title = 'Document Expiring Today';
        body = '"$documentName" expires today.';
      } else {
        title = 'Document Expiry Reminder';
        body =
            '"$documentName" expires in $offset ${offset == 1 ? 'day' : 'days'}.';
      }

      const androidDetails = AndroidNotificationDetails(
        'document_vault_expiry',
        'Document Expiry Reminders',
        channelDescription: 'Alerts for documents approaching expiry dates',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      try {
        final tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);
        await _plugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: body,
          scheduledDate: tzScheduled,
          notificationDetails: const NotificationDetails(
            android: androidDetails,
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: documentId.toString(),
        );

        // Persist reminder in SQLite database
        await repository.saveReminder(
          documentId: documentId,
          reminderType: reminderType,
          scheduledFor: scheduledDate,
          notificationId: notificationId,
        );
      } catch (e) {
        debugPrint('Failed to schedule reminder (id: $notificationId): $e');
      }
    }
  }

  /// Cancels all scheduled notifications and deletes reminder records for a document.
  Future<void> cancelRemindersForDocument({
    required int documentId,
    required DocumentRepository repository,
  }) async {
    if (!_initialized) await initialize();

    for (final offset in AppConstants.reminderOffsetsDays) {
      final id = generateNotificationId(documentId, offset);
      try {
        await _plugin.cancel(id: id);
      } catch (e) {
        debugPrint('Error cancelling notification $id: $e');
      }
    }

    await repository.deleteRemindersForDocument(documentId);
  }
}
