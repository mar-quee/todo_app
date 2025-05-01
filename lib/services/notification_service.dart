import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform;

// Priority の名前の衝突を回避するためのインポート
import '../main.dart' as app;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  // 通知の初期化
  Future<void> init() async {
    tz.initializeTimeZones();

    // Android設定
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS設定（DarwinはiOSとmacOS共通の設定）
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    // 初期化設定
    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin, // macOS用の設定を追加
        );

    // 初期化と通知の処理方法の設定
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (
        NotificationResponse notificationResponse,
      ) async {
        // 通知がタップされた時の処理
        final String? payload = notificationResponse.payload;
        if (payload != null) {
          debugPrint('通知ペイロード: $payload');
          // TODO: 通知がタップされた時の処理を追加
        }
      },
    );

    // 通知の許可を確認
    if (Platform.isIOS) {
      // iOS向け
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      // macOS向け
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // 通知の有効・無効設定を保存
  Future<void> saveNotificationSettings({
    required bool enableDueReminders,
    required int reminderTime,
    required bool notifyHighPriority,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableDueReminders', enableDueReminders);
    await prefs.setInt('reminderTime', reminderTime);
    await prefs.setBool('notifyHighPriority', notifyHighPriority);
  }

  // 通知設定を読み込む
  Future<Map<String, dynamic>> loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // 設定が存在しない場合はデフォルト値を保存してから返す
    final enableDueReminders = prefs.getBool('enableDueReminders');
    if (enableDueReminders == null) {
      await saveNotificationSettings(
        enableDueReminders: false,
        reminderTime: 24,
        notifyHighPriority: false,
      );
    }

    return {
      'enableDueReminders': prefs.getBool('enableDueReminders') ?? false,
      'reminderTime': prefs.getInt('reminderTime') ?? 24, // デフォルト24時間前
      'notifyHighPriority': prefs.getBool('notifyHighPriority') ?? false,
    };
  }

  // 期限日のリマインダー通知をスケジュール
  Future<void> scheduleDueReminder(app.TodoItem todo) async {
    if (todo.dueDate == null) return;

    final settings = await loadNotificationSettings();
    if (!settings['enableDueReminders']) return;

    // 既存の通知をキャンセル
    await cancelNotification(todo.id);

    // 通知する時間（期限の数時間前）
    final int hoursBeforeDue = settings['reminderTime'];
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      todo.dueDate!.subtract(Duration(hours: hoursBeforeDue)),
      tz.local,
    );

    // 現在時刻を過ぎている場合はスケジュールしない
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
      return;
    }

    // macOS用の通知詳細を追加
    final macOSPlatformSpecifics = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // 通知をスケジュール
    await flutterLocalNotificationsPlugin.zonedSchedule(
      int.parse(todo.id.substring(0, 9)), // IDを整数に変換
      '${todo.title} の期限が近づいています',
      '$hoursBeforeDue時間後が期限です',
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'due_reminder_channel',
          '期限リマインダー',
          channelDescription: 'TODOの期限が近づいたときに通知します',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: macOSPlatformSpecifics, // macOS用の設定を追加
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: todo.id,
    );
  }

  // 優先度が高いタスクの通知
  Future<void> notifyHighPriorityTask(app.TodoItem todo) async {
    if (todo.priority != app.Priority.high) return;

    final settings = await loadNotificationSettings();
    if (!settings['notifyHighPriority']) return;

    await flutterLocalNotificationsPlugin.show(
      int.parse(todo.id.substring(0, 9)), // IDを整数に変換
      '優先度の高いタスクが追加されました',
      todo.title,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_priority_channel',
          '優先度高タスク',
          channelDescription: '優先度の高いタスクについて通知します',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails( // macOS用の設定を追加
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: todo.id,
    );
  }

  // 通知をキャンセル
  Future<void> cancelNotification(String todoId) async {
    await flutterLocalNotificationsPlugin.cancel(
      int.parse(todoId.substring(0, 9)),
    );
  }

  // すべての通知をキャンセル
  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  // すべてのTODOの通知をスケジュールし直す
  Future<void> rescheduleAllNotifications(List<app.TodoItem> todos) async {
    // すべての通知をキャンセル
    await cancelAllNotifications();

    final settings = await loadNotificationSettings();
    if (!settings['enableDueReminders']) return;

    // 完了していないTODOでかつ期限日があるものだけ通知をスケジュール
    for (final todo in todos) {
      if (!todo.completed && todo.dueDate != null) {
        await scheduleDueReminder(todo);
      }
    }
  }
}
