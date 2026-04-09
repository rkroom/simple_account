import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final StreamController<String?> selectNotificationStream =
    StreamController<String?>.broadcast();

class NotificationService {
  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _statisticsChannelSpecifics =
      AndroidNotificationDetails(
        'statistics',
        'timing_statistics',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: false,
      );

  static const NotificationDetails _platformChannelSpecifics =
      NotificationDetails(android: _statisticsChannelSpecifics);

  static const AndroidNotificationDetails _scheduleChannelSpecifics =
      AndroidNotificationDetails(
        'schedule',
        'schedule',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: false,
      );

  static const NotificationDetails _schedulePlatformChannelSpecifics =
      NotificationDetails(android: _scheduleChannelSpecifics);

  Future<void> initNotification() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (
        NotificationResponse notificationResponse,
      ) async {
        final String? payload = notificationResponse.payload;
        if (payload != null) {
          selectNotificationStream.add(payload);
        }
      },
    );
  }

  Future<void> showNotification(int id, String title, String body) async {
    await _flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _platformChannelSpecifics,
      payload: '/statistic',
    );
  }

  Future<void> showScheduleNotification(
    int id,
    String title,
    String body,
  ) async {
    await _flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _schedulePlatformChannelSpecifics,
      payload: '/home/schedule',
    );
  }

  Future<void> checkAppLaunchFromNotification() async {
    final NotificationAppLaunchDetails? notificationAppLaunchDetails =
        await _flutterLocalNotificationsPlugin
            .getNotificationAppLaunchDetails();

    if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
      final String? payload =
          notificationAppLaunchDetails?.notificationResponse?.payload;
      if (payload != null) {
        selectNotificationStream.add(payload);
      }
    }
  }
}
